import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Ľahký prehľad jednej konverzácie pre zoznam chatov (drawer).
class StylistChatThread {
  final String id;
  final String title;
  final DateTime? updatedAt;

  const StylistChatThread({
    required this.id,
    required this.title,
    this.updatedAt,
  });

  factory StylistChatThread.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final ts = data['updatedAt'];
    return StylistChatThread(
      id: doc.id,
      title: (data['title'] ?? '').toString().trim().isEmpty
          ? 'Nový chat'
          : (data['title']).toString(),
      updatedAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

/// Perzistencia stylist chatov vo Firestore: `users/{uid}/stylistChats/{chatId}`.
/// Každý dokument drží metadáta + celé pole správ (text je dátovo zanedbateľný).
class StylistChatStore {
  StylistChatStore({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String? get _uid => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>>? get _col {
    final uid = _uid;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid).collection('stylistChats');
  }

  /// Živý zoznam chatov, najnovšie hore.
  Stream<List<StylistChatThread>> watchThreads() {
    final col = _col;
    if (col == null) return const Stream.empty();
    return col
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map(StylistChatThread.fromDoc).toList(growable: false));
  }

  /// Načíta jeden chat (metadáta + správy) ako surový map.
  Future<Map<String, dynamic>?> loadChat(String chatId) async {
    final col = _col;
    if (col == null) return null;
    final snap = await col.doc(chatId).get();
    return snap.data();
  }

  /// Vytvorí nový prázdny chat a vráti jeho id.
  ///
  /// Pozn.: na zápis NEČAKÁME ack zo servera. Firestore write Future sa
  /// dokončí až po potvrdení backendom — offline by „visel" donekonečna.
  /// Lokálna cache sa aktualizuje okamžite, takže UI (a id) máme hneď.
  Future<String?> createChat({
    required String title,
    bool awaitWrite = false,
  }) async {
    final col = _col;
    if (col == null) return null;
    final doc = col.doc();
    final now = FieldValue.serverTimestamp();
    final write = doc.set(<String, dynamic>{
      'title': title,
      'createdAt': now,
      'updatedAt': now,
      'messages': <Map<String, dynamic>>[],
    });
    if (awaitWrite) {
      await write;
    } else {
      unawaited(write.catchError((_) {}));
    }
    return doc.id;
  }

  /// Uloží (prepíše) stav chatu. Volané s debounce z obrazovky.
  Future<void> saveChat({
    required String chatId,
    required List<Map<String, dynamic>> messages,
    String? title,
    String? photoStage,
    String? activePhotoUrl,
    String? photoImproveHint,
    int? userMessageCount,
    bool awaitWrite = false,
  }) async {
    final col = _col;
    if (col == null) return;
    final data = <String, dynamic>{
      'messages': messages,
      'updatedAt': FieldValue.serverTimestamp(),
      'photoStage': photoStage,
      'activePhotoUrl': activePhotoUrl,
      'photoImproveHint': photoImproveHint,
      'userMessageCount': userMessageCount,
    };
    if (title != null) data['title'] = title;
    final write = col.doc(chatId).set(data, SetOptions(merge: true));
    if (awaitWrite) {
      await write;
    } else {
      unawaited(write.catchError((_) {}));
    }
  }

  /// Last full outfit cards across recent threads. Used only as a soft
  /// diversity memory: safety and suitability still outrank novelty.
  Future<List<Set<String>>> loadRecentFullOutfitItemIdSets({
    int limitChats = 5,
  }) async {
    final col = _col;
    if (col == null) return const <Set<String>>[];
    final snap = await col
        .orderBy('updatedAt', descending: true)
        .limit(limitChats.clamp(1, 10))
        .get();
    final out = <Set<String>>[];
    for (final doc in snap.docs) {
      final rawMessages = doc.data()['messages'];
      if (rawMessages is! List) continue;
      for (final raw in rawMessages.reversed) {
        if (raw is! Map || raw['isUser'] == true) continue;
        final suggested = raw['suggestedItems'];
        if (suggested is! List || suggested.length < 3) continue;
        final ids = suggested
            .whereType<Map>()
            .map((item) => (item['id'] ?? '').toString().trim())
            .where((id) => id.isNotEmpty)
            .toSet();
        if (ids.length >= 3) {
          out.add(Set<String>.unmodifiable(ids));
          break;
        }
      }
    }
    return List<Set<String>>.unmodifiable(out);
  }

  Future<void> renameChat(String chatId, String title) async {
    final col = _col;
    if (col == null) return;
    unawaited(col
        .doc(chatId)
        .set(<String, dynamic>{'title': title}, SetOptions(merge: true))
        .catchError((_) {}));
  }

  Future<void> deleteChat(String chatId) async {
    final col = _col;
    if (col == null) return;
    // Mazanie hneď premietneme do lokálnej cache (stream sa aktualizuje),
    // server sa dosynchronizuje po obnovení pripojenia.
    unawaited(col.doc(chatId).delete().catchError((_) {}));
  }
}
