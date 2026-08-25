import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/wardrobe_v2/wardrobe_set_v2.dart';

class WardrobeSetRepository {
  WardrobeSetRepository({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  static const minMembers = 2;
  static const maxUiMembers = 6;

  String get _uid =>
      _auth.currentUser?.uid ?? (throw StateError('auth_required'));
  CollectionReference<Map<String, dynamic>> get _sets =>
      _firestore.collection('users').doc(_uid).collection('wardrobe_sets');
  CollectionReference<Map<String, dynamic>> get _items =>
      _firestore.collection('users').doc(_uid).collection('wardrobe');
  CollectionReference<Map<String, dynamic>> get _drafts => _firestore
      .collection('users')
      .doc(_uid)
      .collection('wardrobe_set_drafts');

  Stream<List<WardrobeSetV2>> watchSets() => _sets
      .where('lifecycle', isEqualTo: 'active')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map(
              (doc) => WardrobeSetV2.fromMap({...doc.data(), 'setId': doc.id}),
            )
            .toList(growable: false),
      );

  Future<WardrobeSetV2?> getSet(String setId) async {
    final snapshot = await _sets.doc(setId).get();
    return snapshot.exists
        ? WardrobeSetV2.fromMap({...snapshot.data()!, 'setId': snapshot.id})
        : null;
  }

  Future<String> createSet({
    required Iterable<String> memberIds,
    required WardrobeSetTypeV2 setType,
    required WardrobeSetRelationshipSourceV2 relationshipSource,
    String? userLabel,
  }) async {
    final members = memberIds.toSet().toList(growable: false);
    if (members.length < minMembers)
      throw StateError('set_requires_two_members');
    if (members.length > maxUiMembers) throw StateError('set_ui_max_six');
    final ref = _sets.doc();
    final generated = setType.labelSk;
    await _firestore.runTransaction((transaction) async {
      for (final memberId in members) {
        final itemRef = _items.doc(memberId);
        final item = await transaction.get(itemRef);
        if (!item.exists) throw StateError('set_member_missing:$memberId');
        final current = item.data()?['setMembership'];
        if (current is Map && current['setId'] != ref.id) {
          throw StateError('set_member_already_linked:$memberId');
        }
      }
      transaction.set(ref, {
        ...WardrobeSetV2(
          setId: ref.id,
          setType: setType,
          relationshipSource: relationshipSource,
          memberIds: members,
          generatedLabel: generated,
          userLabel: userLabel,
        ).toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      for (final memberId in members) {
        transaction.update(_items.doc(memberId), {
          'setMembership': {
            'setId': ref.id,
            'setType': setType.wireName,
            'relationshipSource': relationshipSource.wireName,
            'authority': 'user_confirmation',
            'displayName': userLabel?.trim().isNotEmpty == true
                ? userLabel!.trim()
                : generated,
          },
          'fieldSources.setMembership': 'user_confirmation',
          'fieldConfidence.setMembership': 1.0,
          'userOverrideFields': FieldValue.arrayUnion(['setMembership']),
          'pendingSetDraft': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
    return ref.id;
  }

  Future<void> updateSet(
    String setId, {
    String? userLabel,
    WardrobeSetTypeV2? setType,
    WardrobeSetRelationshipSourceV2? relationshipSource,
  }) async {
    await _firestore.runTransaction((transaction) async {
      final ref = _sets.doc(setId);
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) throw StateError('set_missing');
      final set = WardrobeSetV2.fromMap({...snapshot.data()!, 'setId': setId});
      final nextType = setType ?? set.setType;
      final nextSource = relationshipSource ?? set.relationshipSource;
      transaction.update(ref, {
        if (userLabel != null) 'userLabel': userLabel.trim(),
        'setType': nextType.wireName,
        'generatedLabel': nextType.labelSk,
        'relationshipSource': nextSource.wireName,
        'authority': 'user_correction',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      for (final id in set.memberIds) {
        transaction.update(_items.doc(id), {
          'setMembership.setType': nextType.wireName,
          'setMembership.relationshipSource': nextSource.wireName,
          'setMembership.authority': 'user_correction',
          'setMembership.displayName': userLabel?.trim().isNotEmpty == true
              ? userLabel!.trim()
              : (set.userLabel?.trim().isNotEmpty == true
                    ? set.userLabel!.trim()
                    : nextType.labelSk),
          'fieldSources.setMembership': 'user_correction',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Future<void> addMember(String setId, String itemId) async {
    final set = await getSet(setId);
    if (set == null) throw StateError('set_missing');
    final members = {...set.memberIds, itemId};
    if (members.length > maxUiMembers) throw StateError('set_ui_max_six');
    await _firestore.runTransaction((transaction) async {
      final itemRef = _items.doc(itemId);
      final item = await transaction.get(itemRef);
      if (!item.exists) throw StateError('set_member_missing');
      final current = item.data()?['setMembership'];
      if (current is Map && current['setId'] != setId) {
        throw StateError('set_member_already_linked:$itemId');
      }
      transaction.update(_sets.doc(setId), {
        'memberIds': members.toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(itemRef, {
        'setMembership': {
          'setId': setId,
          'setType': set.setType.wireName,
          'relationshipSource': set.relationshipSource.wireName,
          'authority': 'user_confirmation',
          'displayName': set.displayName,
        },
        'fieldSources.setMembership': 'user_confirmation',
        'fieldConfidence.setMembership': 1.0,
        'userOverrideFields': FieldValue.arrayUnion(['setMembership']),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> replaceMember(
    String setId, {
    required String removedItemId,
    required String replacementItemId,
  }) async {
    if (removedItemId == replacementItemId) return;
    await _firestore.runTransaction((transaction) async {
      final setRef = _sets.doc(setId);
      final setSnapshot = await transaction.get(setRef);
      if (!setSnapshot.exists) throw StateError('set_missing');
      final set = WardrobeSetV2.fromMap({
        ...setSnapshot.data()!,
        'setId': setId,
      });
      if (!set.memberIds.contains(removedItemId)) {
        throw StateError('set_member_missing:$removedItemId');
      }
      final replacementRef = _items.doc(replacementItemId);
      final replacement = await transaction.get(replacementRef);
      if (!replacement.exists) throw StateError('replacement_missing');
      final current = replacement.data()?['setMembership'];
      if (current is Map && current['setId'] != setId) {
        throw StateError('replacement_already_linked');
      }
      final members = set.memberIds.where((id) => id != removedItemId).toSet()
        ..add(replacementItemId);
      if (members.length < minMembers) {
        throw StateError('replacement_must_preserve_two_members');
      }
      transaction.update(setRef, {
        'memberIds': members.toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(_items.doc(removedItemId), {
        'setMembership': FieldValue.delete(),
        'fieldSources.setMembership': FieldValue.delete(),
        'fieldConfidence.setMembership': FieldValue.delete(),
        'userOverrideFields': FieldValue.arrayRemove(['setMembership']),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(replacementRef, {
        'setMembership': {
          'setId': setId,
          'setType': set.setType.wireName,
          'relationshipSource': set.relationshipSource.wireName,
          'authority': 'user_correction',
          'displayName': set.displayName,
        },
        'fieldSources.setMembership': 'user_correction',
        'fieldConfidence.setMembership': 1.0,
        'userOverrideFields': FieldValue.arrayUnion(['setMembership']),
        'pendingSetDraft': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> removeMember(String setId, String itemId) async {
    await _firestore.runTransaction((transaction) async {
      final setRef = _sets.doc(setId);
      final snapshot = await transaction.get(setRef);
      if (!snapshot.exists) return;
      final set = WardrobeSetV2.fromMap({...snapshot.data()!, 'setId': setId});
      final remaining = set.memberIds.where((id) => id != itemId).toList();
      transaction.update(_items.doc(itemId), {
        'setMembership': FieldValue.delete(),
        'fieldSources.setMembership': FieldValue.delete(),
        'fieldConfidence.setMembership': FieldValue.delete(),
        'userOverrideFields': FieldValue.arrayRemove(['setMembership']),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (remaining.length < minMembers) {
        for (final id in remaining) {
          transaction.update(_items.doc(id), {
            'setMembership': FieldValue.delete(),
            'fieldSources.setMembership': FieldValue.delete(),
            'fieldConfidence.setMembership': FieldValue.delete(),
            'userOverrideFields': FieldValue.arrayRemove(['setMembership']),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        transaction.update(setRef, {
          'memberIds': const [],
          'lifecycle': 'dissolved',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        transaction.update(setRef, {
          'memberIds': remaining,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Future<void> dissolveSet(String setId) async {
    final set = await getSet(setId);
    if (set == null) return;
    await _firestore.runTransaction((transaction) async {
      for (final id in set.memberIds) {
        transaction.update(_items.doc(id), {
          'setMembership': FieldValue.delete(),
          'fieldSources.setMembership': FieldValue.delete(),
          'fieldConfidence.setMembership': FieldValue.delete(),
          'userOverrideFields': FieldValue.arrayRemove(['setMembership']),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      transaction.update(_sets.doc(setId), {
        'memberIds': const [],
        'lifecycle': 'dissolved',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<Map<String, dynamic>?> getDraft(String draftId) async {
    final snapshot = await _drafts.doc(draftId).get();
    return snapshot.data();
  }

  Future<void> saveDraft(String draftId, Map<String, dynamic> data) =>
      _drafts.doc(draftId).set({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
  Future<void> markPendingMember(String draftId, String itemId) =>
      _items.doc(itemId).update({
        'pendingSetDraft': {'draftId': draftId, 'status': 'incomplete'},
        'updatedAt': FieldValue.serverTimestamp(),
      });
  Future<void> clearPendingMember(String itemId) => _items.doc(itemId).update({
    'pendingSetDraft': FieldValue.delete(),
    'updatedAt': FieldValue.serverTimestamp(),
  });
  Future<void> abandonDraft(String draftId) => _drafts.doc(draftId).delete();
  Future<void> abandonPendingMember(String draftId, String itemId) async {
    await _items.doc(itemId).update({
      'pendingSetDraft': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await abandonDraft(draftId);
  }
}
