import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class StylistChatService {
  static const _genericErrorReply =
      'Niečo sa pokazilo 😅 Skús to prosím ešte raz.';

  static List<Map<String, dynamic>> slimOutfitItemsForApi(
    List<Map<String, dynamic>> items,
  ) {
    return items
        .map((item) {
          final colors = item['colors'];
          return <String, dynamic>{
            'id': (item['id'] ?? '').toString(),
            'name': (item['name'] ?? '').toString(),
            'category': (item['category'] ?? item['categoryKey'] ?? '')
                .toString(),
            'subCategory': (item['subCategory'] ?? item['subCategoryKey'] ?? '')
                .toString(),
            if (colors is List)
              'colors': colors.map((v) => v.toString()).toList(growable: false),
          };
        })
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> sendMessage(
    String message, {
    List<Map<String, String>> history = const [],
    Map<String, dynamic>? weatherContext,
    Map<String, dynamic>? clientContext,
    Map<String, dynamic>? outfitContextState,
    String mode = 'chat',
    bool includeWardrobe = false,
    Map<String, dynamic>? eventContext,
    List<Map<String, dynamic>> selectedOutfitItems = const [],
    Map<String, dynamic>? occasionContext,
    Map<String, dynamic>? bottomGuidance,
    Map<String, dynamic>? footwearGuidance,
    Map<String, dynamic>? wardrobeAnalysis,
    Map<String, dynamic>? stylistOpinion,
    String? imageUrl,
    bool wardrobeAccess = false,
    String? improveHint,
    String? notifyJobId,
    String? chatId,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-east1',
      ).httpsCallable('stylistChat');
      final payload = <String, dynamic>{
        'message': message,
        'history': history,
        'weatherContext': weatherContext,
        'clientContext': clientContext,
        'mode': mode,
        'includeWardrobe': includeWardrobe,
      };
      if (outfitContextState != null && outfitContextState.isNotEmpty) {
        payload['outfitContextState'] = outfitContextState;
      }
      if (imageUrl != null && imageUrl.trim().isNotEmpty) {
        payload['imageUrl'] = imageUrl.trim();
      }
      if (wardrobeAccess) {
        payload['wardrobeAccess'] = true;
      }
      if (improveHint != null && improveHint.trim().isNotEmpty) {
        payload['improveHint'] = improveHint.trim();
      }
      if (notifyJobId != null && notifyJobId.trim().isNotEmpty) {
        payload['notifyJobId'] = notifyJobId.trim();
      }
      if (chatId != null && chatId.trim().isNotEmpty) {
        payload['chatId'] = chatId.trim();
      }
      if (eventContext != null && eventContext.isNotEmpty) {
        payload['eventContext'] = eventContext;
      }
      if (selectedOutfitItems.isNotEmpty) {
        payload['selectedOutfitItems'] =
            slimOutfitItemsForApi(selectedOutfitItems);
      }
      if (occasionContext != null && occasionContext.isNotEmpty) {
        payload['occasionContext'] = occasionContext;
      }
      if (bottomGuidance != null && bottomGuidance.isNotEmpty) {
        payload['bottomGuidance'] = bottomGuidance;
      }
      if (footwearGuidance != null && footwearGuidance.isNotEmpty) {
        payload['footwearGuidance'] = footwearGuidance;
      }
      if (wardrobeAnalysis != null && wardrobeAnalysis.isNotEmpty) {
        payload['wardrobeAnalysis'] = wardrobeAnalysis;
      }
      if (stylistOpinion != null && stylistOpinion.isNotEmpty) {
        payload['stylistOpinion'] = stylistOpinion;
      }
      // Analýza fotky (OpenAI Vision) + čítanie šatníka trvá dlhšie, preto
      // pre rate_photo dávame väčší časový limit.
      final callTimeout = mode == 'rate_photo'
          ? const Duration(seconds: 90)
          : const Duration(seconds: 45);
      // Prechodný výpadok (napr. appka na chvíľu v pozadí → uspaté spojenie)
      // dokáže zhodiť request. Skúsime ho preto raz/dvakrát zopakovať.
      final result = await _callWithRetry(
        callable,
        payload,
        callTimeout,
        maxAttempts: 3,
      );

      final data = result.data;
      if (data is Map) {
        final reply = data['reply'];
        final suggestedItems = data['suggestedItems'];
        return <String, dynamic>{
          'ok': true,
          'reply': reply is String ? reply : _genericErrorReply,
          'suggestedItems': suggestedItems is List
              ? suggestedItems
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList(growable: false)
              : const <Map<String, dynamic>>[],
          'action': (data['action'] ?? 'chat').toString(),
          'offerWardrobe': data['offerWardrobe'] == true,
          'improveHint': (data['improveHint'] ?? '').toString(),
          'eventContext': data['eventContext'] is Map
              ? Map<String, dynamic>.from(data['eventContext'] as Map)
              : null,
          'excludeItemKeywords': data['excludeItemKeywords'] is List
              ? (data['excludeItemKeywords'] as List)
                  .map((v) => v.toString().trim())
                  .where((v) => v.isNotEmpty)
                  .toList(growable: false)
              : const <String>[],
          ..._outfitDecisionFieldsFromData(Map<String, dynamic>.from(data)),
        };
      }
    } catch (error, stackTrace) {
      debugPrint('STYLIST CHAT callable error: $error');
      debugPrint('$stackTrace');
      return <String, dynamic>{
        'ok': false,
        'offline': _looksLikeConnectivityError(error),
        'reply': '',
        'suggestedItems': const <Map<String, dynamic>>[],
        'action': 'chat',
        'eventContext': null,
        'excludeItemKeywords': const <String>[],
      };
    }

    return <String, dynamic>{
      'ok': false,
      'offline': false,
      'reply': '',
      'suggestedItems': const <Map<String, dynamic>>[],
      'action': 'chat',
      'eventContext': null,
      'excludeItemKeywords': const <String>[],
    };
  }

  /// Cloud Function dobehne na serveri aj keď klientovi medzitým spadlo
  /// spojenie (appka šla na pozadie). Výsledok si vtedy vie klient dotiahnuť
  /// z `users/{uid}/stylistJobs/{jobId}`, kam ho funkcia zapísala. Počúva na
  /// tento dokument až kým sa neobjaví hotový výsledok (alebo do timeoutu).
  Future<Map<String, dynamic>?> awaitJobResult(
    String jobId, {
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || jobId.trim().isEmpty) return null;
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('stylistJobs')
        .doc(jobId.trim());

    final completer = Completer<Map<String, dynamic>?>();
    StreamSubscription? sub;
    Timer? timer;

    void finish(Map<String, dynamic>? value) {
      if (completer.isCompleted) return;
      sub?.cancel();
      timer?.cancel();
      completer.complete(value);
    }

    timer = Timer(timeout, () => finish(null));
    sub = ref.snapshots().listen((snap) {
      final data = snap.data();
      if (data == null) return;
      if ((data['status'] ?? '').toString() != 'done') return;
      final rawResult = data['result'];
      if (rawResult is! Map) return;
      finish(_normalizeResult(Map<String, dynamic>.from(rawResult)));
    }, onError: (_) => finish(null));

    final value = await completer.future;
    // Po prevzatí výsledok zmažeme, nech sa job dokumenty nehromadia.
    if (value != null) {
      unawaited(ref.delete().catchError((_) {}));
    }
    return value;
  }

  /// Prevedie surový `result` z Firestore do rovnakého tvaru, aký vracia
  /// `sendMessage`, aby ho klient vedel spracovať rovnakou cestou.
  Map<String, dynamic> _normalizeResult(Map<String, dynamic> data) {
    final reply = data['reply'];
    final suggestedItems = data['suggestedItems'];
    return <String, dynamic>{
      'ok': true,
      'reply': reply is String ? reply : _genericErrorReply,
      'suggestedItems': suggestedItems is List
          ? suggestedItems
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
          : const <Map<String, dynamic>>[],
      'action': (data['action'] ?? 'chat').toString(),
      'offerWardrobe': data['offerWardrobe'] == true,
      'improveHint': (data['improveHint'] ?? '').toString(),
      'eventContext': data['eventContext'] is Map
          ? Map<String, dynamic>.from(data['eventContext'] as Map)
          : null,
      'excludeItemKeywords': data['excludeItemKeywords'] is List
          ? (data['excludeItemKeywords'] as List)
              .map((v) => v.toString().trim())
              .where((v) => v.isNotEmpty)
              .toList(growable: false)
          : const <String>[],
      ..._outfitDecisionFieldsFromData(data),
    };
  }

  static Map<String, dynamic> _outfitDecisionFieldsFromData(
    Map<String, dynamic> data,
  ) {
    final confidenceRaw = data['confidence'] ?? data['readiness'];
    final impactRaw = data['impactFields'] ?? data['missingFields'];
    return <String, dynamic>{
      if (confidenceRaw is num) 'confidence': confidenceRaw.toDouble(),
      if (data['decisionRisk'] != null)
        'decisionRisk': data['decisionRisk'].toString(),
      'assumptions': data['assumptions'] is List
          ? (data['assumptions'] as List)
              .map((v) => v.toString().trim())
              .where((v) => v.isNotEmpty)
              .toList(growable: false)
          : const <String>[],
      if (data['clarifyReason'] != null)
        'clarifyReason': data['clarifyReason'].toString(),
      'impactFields': impactRaw is List
          ? impactRaw
              .map((v) => v.toString().trim())
              .where((v) => v.isNotEmpty)
              .toList(growable: false)
          : const <String>[],
    };
  }

  /// Zavolá callable a pri prechodnej chybe pripojenia to ešte raz skúsi.
  /// Rieši to typický prípad, keď používateľ na chvíľu prepne z appky preč a
  /// systém uspí jej sieťové spojenia práve počas dlhšieho volania.
  static Future<HttpsCallableResult> _callWithRetry(
    HttpsCallable callable,
    Map<String, dynamic> payload,
    Duration timeout, {
    int maxAttempts = 3,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await callable.call(payload).timeout(timeout);
      } catch (error) {
        lastError = error;
        // Opakujeme len pri prechodných sieťových chybách; iné chyby hneď hore.
        if (attempt >= maxAttempts || !_looksLikeConnectivityError(error)) {
          rethrow;
        }
        debugPrint(
          'STYLIST CHAT retry ${attempt + 1}/$maxAttempts po chybe: $error',
        );
        await Future<void>.delayed(Duration(milliseconds: 600 * attempt));
      }
    }
    // Sem sa nedostaneme, ale Dart to vyžaduje.
    throw lastError ?? Exception('callable failed');
  }

  /// Rozozná, či ide o problém s pripojením (offline / nedostupný server /
  /// timeout) — vtedy chceme používateľovi ukázať jasnú hlášku o internete.
  static bool _looksLikeConnectivityError(Object error) {
    if (error is TimeoutException) return true;
    if (error is FirebaseFunctionsException) {
      const networkCodes = {'unavailable', 'deadline-exceeded', 'internal'};
      if (networkCodes.contains(error.code)) return true;
    }
    final text = error.toString().toLowerCase();
    return text.contains('unavailable') ||
        text.contains('failed host lookup') ||
        text.contains('unable to resolve host') ||
        text.contains('socketexception') ||
        text.contains('network') ||
        text.contains('timed out') ||
        text.contains('timeout');
  }
}
