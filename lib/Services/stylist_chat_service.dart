import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../domain/style_preferences/style_preferences_runtime.dart';
import 'stylist_job_consumer.dart';
import 'user_style_preferences_reader.dart';

class StylistChatService {
  StylistChatService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    StylistJobConsumer? jobConsumer,
    UserStylePreferencesReader? stylePreferences,
  }) : _firestoreOverride = firestore,
       _authOverride = auth,
       _injectedJobConsumer = jobConsumer,
       _stylePreferences =
           stylePreferences ??
           UserStylePreferencesReader(firestore: firestore, auth: auth);

  /// This branch is an explicit opt-in build. Released clients on master do
  /// not send this marker, so a selective backend deploy can serve both paths
  /// without silently moving existing users onto the experiment.
  static const conversationBrainVersion = 'brain_v1';

  final FirebaseFirestore? _firestoreOverride;
  final FirebaseAuth? _authOverride;
  final StylistJobConsumer? _injectedJobConsumer;
  final UserStylePreferencesReader _stylePreferences;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  StylistJobConsumer? _cachedJobs;

  StylistJobConsumer get jobs =>
      _injectedJobConsumer ??
      (_cachedJobs ??= StylistJobConsumer(
        watch: _watchJob,
        delete: _deleteJob,
        normalize: normalizeJobResult,
      ));
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
    Map<String, dynamic>? shoppingContext,
    Map<String, dynamic>? shoppingWardrobeSignal,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-east1',
      ).httpsCallable('stylistChat');
      final effectiveClientContext = <String, dynamic>{
        ...?clientContext,
        'conversationBrainVersion': conversationBrainVersion,
      };
      final payload = <String, dynamic>{
        'message': message,
        'history': history,
        'weatherContext': weatherContext,
        'clientContext': effectiveClientContext,
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
      if (shoppingContext != null && shoppingContext.isNotEmpty) {
        payload['shoppingContext'] = shoppingContext;
      }
      if (shoppingWardrobeSignal != null && shoppingWardrobeSignal.isNotEmpty) {
        payload['shoppingWardrobeSignal'] = shoppingWardrobeSignal;
      }
      if (eventContext != null && eventContext.isNotEmpty) {
        payload['eventContext'] = eventContext;
      }
      if (selectedOutfitItems.isNotEmpty) {
        payload['selectedOutfitItems'] = slimOutfitItemsForApi(
          selectedOutfitItems,
        );
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
      final stylePayload = await _stylePreferencesPayload();
      if (stylePayload != null) {
        payload['userStylePreferences'] = stylePayload;
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
        jsonSafeMapForCallable(payload),
        callTimeout,
        // Brain/context clarification is authoritative. A transport failure
        // must surface rather than silently create a second conversational
        // decision with potentially different clarification state.
        maxAttempts: mode == 'chat' ? 1 : 3,
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
          ..._shoppingFieldsFromData(Map<String, dynamic>.from(data)),
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
  ///
  /// Does not delete the job. Callers must persist the chat first, then
  /// [deleteJob].
  Future<Map<String, dynamic>?> awaitJobResult(
    String jobId, {
    Duration timeout = const Duration(minutes: 3),
  }) async {
    if (jobId.trim().isEmpty) return null;
    if (_injectedJobConsumer == null && _auth.currentUser?.uid == null) {
      return null;
    }
    final snapshot = await jobs.waitUntilSettled(
      jobId,
      timeout: timeout,
      treatMissingAsPending: true,
    );
    if (snapshot.status != StylistJobStatus.done) return null;
    return snapshot.response;
  }

  Future<void> deleteJob(String jobId) => jobs.deleteJob(jobId);

  Future<Map<String, dynamic>?> _stylePreferencesPayload() {
    return resolveStylePreferencesPayload(
      _stylePreferences,
      _auth.currentUser?.uid,
    );
  }

  /// Loads Stylist preference context. Missing docs, empty values, and
  /// transient read failures resolve to `null` (omit the payload field).
  /// Soft taste follows [StylePreferencesRuntime], while explicit outfit
  /// presentation remains authoritative independently of that rollout flag.
  @visibleForTesting
  static Future<Map<String, dynamic>?> resolveStylePreferencesPayload(
    UserStylePreferencesReader reader,
    String? uid,
  ) async {
    try {
      final prefs = await reader.loadForUid(uid);
      return StylePreferencesRuntime.stylistPayload(prefs);
    } catch (_) {
      return null;
    }
  }

  Stream<StylistJobRaw> _watchJob(String jobId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return Stream<StylistJobRaw>.value(const StylistJobRaw.missing());
    }
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('stylistJobs')
        .doc(jobId.trim())
        .snapshots()
        .map((snap) {
          if (!snap.exists) return const StylistJobRaw.missing();
          final data = snap.data() ?? const <String, dynamic>{};
          final rawResult = data['result'];
          return StylistJobRaw(
            exists: true,
            status: (data['status'] ?? '').toString(),
            result: rawResult is Map
                ? Map<String, dynamic>.from(rawResult as Map)
                : null,
          );
        });
  }

  Future<void> _deleteJob(String jobId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || jobId.trim().isEmpty) return;
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('stylistJobs')
          .doc(jobId.trim())
          .delete();
    } catch (_) {}
  }

  /// Prevedie surový `result` z Firestore do rovnakého tvaru, aký vracia
  /// `sendMessage`, aby ho klient vedel spracovať rovnakou cestou.
  static Map<String, dynamic> normalizeJobResult(Map<String, dynamic> data) {
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
      ..._shoppingFieldsFromData(data),
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

  static Map<String, dynamic> _shoppingFieldsFromData(
    Map<String, dynamic> data,
  ) {
    return <String, dynamic>{
      'messageAttachments': data['messageAttachments'] is List
          ? (data['messageAttachments'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList(growable: false)
          : const <Map<String, dynamic>>[],
      'shoppingContextPatch': data['shoppingContextPatch'] is Map
          ? Map<String, dynamic>.from(data['shoppingContextPatch'] as Map)
          : const <String, dynamic>{},
      'clearShoppingContext': data['clearShoppingContext'] == true,
      if (data['zeroResultDiagnostics'] is Map)
        'zeroResultDiagnostics': Map<String, dynamic>.from(
          data['zeroResultDiagnostics'] as Map,
        ),
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

  static Map<String, dynamic> jsonSafeMapForCallable(
    Map<String, dynamic> input,
  ) {
    final out = _jsonSafe(input);
    return out is Map<String, dynamic>
        ? out
        : Map<String, dynamic>.from(out as Map);
  }

  static dynamic _jsonSafe(dynamic value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is Timestamp) {
      return value.millisecondsSinceEpoch;
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is Map) {
      return value.map(
        (key, child) => MapEntry(key.toString(), _jsonSafe(child)),
      );
    }
    if (value is Iterable) {
      return value.map(_jsonSafe).toList(growable: false);
    }
    return value.toString();
  }
}
