import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../domain/style_preferences/style_preferences_runtime.dart';
import 'user_style_preferences_reader.dart';

class StylistSimpleAgentResultV1 {
  const StylistSimpleAgentResultV1({
    required this.ok,
    required this.failClosed,
    required this.stylistComment,
    required this.resultingOutfitItemIds,
    required this.displayItemIds,
    required this.outfitChanged,
    required this.quickReplyMode,
    required this.quickReplyPrompt,
    required this.resultingOutfitItems,
    required this.displayItems,
  });

  final bool ok;
  final bool failClosed;
  final String stylistComment;
  final List<String> resultingOutfitItemIds;
  final List<String> displayItemIds;
  final bool outfitChanged;
  final String quickReplyMode;
  final String? quickReplyPrompt;
  final List<Map<String, dynamic>> resultingOutfitItems;
  final List<Map<String, dynamic>> displayItems;

  static List<String>? _ids(Object? raw) {
    if (raw is! List) return null;
    final ids = raw.map((value) => value.toString().trim()).where((value) => value.isNotEmpty).toList(growable: false);
    if (ids.length != raw.length || ids.toSet().length != ids.length) return null;
    return ids;
  }

  static Map<String, Map<String, dynamic>>? _itemsById(Object? raw) {
    if (raw is! List) return null;
    final out = <String, Map<String, dynamic>>{};
    for (final value in raw) {
      if (value is! Map) return null;
      final item = Map<String, dynamic>.from(value);
      final id = (item['id'] ?? '').toString().trim();
      if (id.isEmpty || out.containsKey(id)) return null;
      out[id] = item;
    }
    return out;
  }

  factory StylistSimpleAgentResultV1.fromCallableData(Map data) {
    final failClosed = data['failClosed'] == true;
    final comment = (data['stylistComment'] ?? data['reply'] ?? '').toString().trim();
    if (data['simpleAgent'] != true || comment.isEmpty) throw const FormatException('simple_agent_contract_invalid');
    if (failClosed) {
      return StylistSimpleAgentResultV1(ok: false, failClosed: true, stylistComment: comment,
        resultingOutfitItemIds: const [], displayItemIds: const [], outfitChanged: false,
        quickReplyMode: 'none', quickReplyPrompt: null, resultingOutfitItems: const [], displayItems: const []);
    }
    final resultIds = _ids(data['resultingOutfitItemIds']);
    final displayIds = _ids(data['displayItemIds']);
    final resultById = _itemsById(data['resultingOutfitItems']);
    final displayById = _itemsById(data['displayItems']);
    if (resultIds == null || displayIds == null || resultById == null || displayById == null || data['outfitChanged'] is! bool) {
      throw const FormatException('simple_agent_contract_invalid');
    }
    if (resultById.keys.toSet().length != resultIds.length || !resultIds.every(resultById.containsKey) ||
        displayById.keys.toSet().length != displayIds.length || !displayIds.every(displayById.containsKey) ||
        !displayIds.every(resultIds.contains)) {
      throw const FormatException('simple_agent_id_materialization_mismatch');
    }
    final quickReplyPromptRaw = (data['quickReplyPrompt'] ?? '').toString().trim();
    return StylistSimpleAgentResultV1(ok: true, failClosed: false, stylistComment: comment,
      resultingOutfitItemIds: List<String>.unmodifiable(resultIds), displayItemIds: List<String>.unmodifiable(displayIds),
      outfitChanged: data['outfitChanged'] as bool, quickReplyMode: data['quickReplyMode'] == 'yes_no' ? 'yes_no' : 'none',
      quickReplyPrompt: quickReplyPromptRaw.isEmpty ? null : quickReplyPromptRaw,
      resultingOutfitItems: List<Map<String, dynamic>>.unmodifiable(resultIds.map((id) => Map<String, dynamic>.from(resultById[id]!))),
      displayItems: List<Map<String, dynamic>>.unmodifiable(displayIds.map((id) => Map<String, dynamic>.from(displayById[id]!))));
  }

  Map<String, dynamic> toUiResponse() => <String, dynamic>{
    'ok': ok, 'simpleAgent': true, 'failClosed': failClosed, 'reply': stylistComment, 'stylistComment': stylistComment,
    'resultingOutfitItemIds': resultingOutfitItemIds, 'displayItemIds': displayItemIds, 'outfitChanged': outfitChanged,
    'quickReplyMode': quickReplyMode, if (quickReplyPrompt != null) 'quickReplyPrompt': quickReplyPrompt,
    'resultingOutfitItems': resultingOutfitItems, 'displayItems': displayItems,
    'action': failClosed ? 'simple_agent_fail_closed' : 'simple_agent_result',
  };
}

class StylistSimpleAgentServiceV1 {
  StylistSimpleAgentServiceV1({FirebaseAuth? auth, UserStylePreferencesReader? stylePreferences})
      : _authOverride = auth,
        _stylePreferences = stylePreferences ?? UserStylePreferencesReader(auth: auth),
        _provisionalV2SessionId = _newProvisionalSessionId();

  final FirebaseAuth? _authOverride;
  final UserStylePreferencesReader _stylePreferences;
  String _provisionalV2SessionId;
  String? _lastV2SessionId;
  String? _boundRealChatId;
  int _turnCounter = 0;
  Map<String, dynamic>? _cachedStylePreferencesPayload;
  DateTime? _stylePreferencesLoadedAt;
  Future<void>? _stylePreferencesLoad;

  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  static String _newProvisionalSessionId() =>
      'v2_${DateTime.now().microsecondsSinceEpoch}';

  static const Set<String> _localGreetingTexts = <String>{
    'ahoj', 'čau', 'cau', 'čauko', 'cauko', 'nazdar', 'dobrý deň', 'dobry den', 'servus', 'hello', 'hi', 'hey',
  };
  static const Set<String> _localThanksTexts = <String>{
    'ďakujem', 'dakujem', 'díky', 'diky', 'vďaka', 'vdaka',
  };

  static String _normalizeLocalFastText(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9áäčďéíĺľňóôŕšťúýž\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _isFriendlyLocalGreeting(String normalized) {
    if (_localGreetingTexts.contains(normalized)) return true;
    return RegExp(
      r'^(ahoj|čau|cau|čauko|cauko|nazdar|servus|hello|hi|hey)\s+(divočák|divocak|kamo|kamarát|kamarat|stylista)$',
    ).hasMatch(normalized);
  }

  static bool _isGenericAdviceIntro(String normalized) => RegExp(
        r'^(ahoj|čau|cau|čauko|cauko|nazdar|servus|hello|hi|hey)'
        r'(?:\s+(divočák|divocak|kamo|kamarát|kamarat|stylista))?'
        r'\s+(potrebujem|chcem|mohol by si|môžeš mi|mozes mi)'
        r'\s+(poradiť|poradit|poradíš|poradis)$',
      ).hasMatch(normalized);

  @visibleForTesting
  static Map<String, dynamic>? localFastReplyForMessage(String message) {
    final normalized = _normalizeLocalFastText(message);
    String? reply;
    if (_isGenericAdviceIntro(normalized)) {
      reply = 'Ahoj! Jasné 🙂 S čím ti môžem pomôcť?';
    } else if (_isFriendlyLocalGreeting(normalized) ||
        (normalized.isEmpty && message.contains('👋'))) {
      reply = 'Ahoj! Ako ti môžem pomôcť?';
    } else if (_localThanksTexts.contains(normalized)) {
      reply = 'Rado sa stalo 🙂';
    }
    if (reply == null) return null;
    return <String, dynamic>{
      'ok': true,
      'simpleAgent': true,
      'v2': true,
      'failClosed': false,
      'modelPath': 'local_fast',
      'reply': reply,
      'stylistComment': reply,
      'resultingOutfitItemIds': const <String>[],
      'displayItemIds': const <String>[],
      'resultingOutfitItems': const <Map<String, dynamic>>[],
      'displayItems': const <Map<String, dynamic>>[],
      'outfitChanged': false,
      'quickReplyMode': 'none',
      'action': 'simple_agent_result',
    };
  }

  void _refreshStylePreferencesInBackground() {
    final loadedAt = _stylePreferencesLoadedAt;
    if (_stylePreferencesLoad != null) return;
    if (loadedAt != null && DateTime.now().difference(loadedAt) < const Duration(minutes: 5)) return;
    final future = _loadStylePreferences();
    _stylePreferencesLoad = future;
    unawaited(future.whenComplete(() => _stylePreferencesLoad = null));
  }

  Future<void> _loadStylePreferences() async {
    try {
      final prefs = await _stylePreferences.loadForUid(_auth.currentUser?.uid)
          .timeout(const Duration(seconds: 3));
      _cachedStylePreferencesPayload = StylePreferencesRuntime.stylistPayload(prefs);
    } catch (_) {
      // Optional personalization must never hold the chat response hostage to
      // Firestore/App Check/network retries.
    } finally {
      _stylePreferencesLoadedAt = DateTime.now();
    }
  }

  Future<Map<String, dynamic>> sendTurn({
    required String message,
    required List<Map<String, String>> history,
    required List<String> currentOutfitItemIds,
    List<Map<String, String>> currentSelectionReasons = const [],
    required Map<String, dynamic> weatherContext,
    required Map<String, dynamic> clientContext,
    Map<String, dynamic>? eventContext,
    Map<String, dynamic>? shoppingContext,
    bool shoppingEnabled = false,
    String? notifyJobId,
    String? chatId,
  }) async {
    // A first-turn greeting is conversation-only even if stale shopping context
    // was hydrated while the new chat UI was being created. Never spend a
    // callable/model round trip on a friendly hello.
    if (history.length <= 1 && currentOutfitItemIds.isEmpty) {
      final localFast = localFastReplyForMessage(message);
      if (localFast != null) {
        debugPrint('SIMPLE_AGENT_LOCAL_FAST history=${history.length}');
        return localFast;
      }
    }

    final stopwatch = Stopwatch()..start();
    debugPrint('SIMPLE_AGENT_REQUEST history=${history.length} current=${currentOutfitItemIds.length}');
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-east1').httpsCallable('stylistChatV2');
      final realChatId = chatId?.trim() ?? '';
      if (realChatId.isEmpty && _boundRealChatId != null) {
        _provisionalV2SessionId = _newProvisionalSessionId();
        _boundRealChatId = null;
        _lastV2SessionId = null;
      }
      final targetSessionId = realChatId.isNotEmpty ? realChatId : _provisionalV2SessionId;
      final previousSessionId = realChatId.isNotEmpty &&
              _lastV2SessionId == _provisionalV2SessionId &&
              _lastV2SessionId != targetSessionId
          ? _lastV2SessionId
          : null;
      final stableTurnId = notifyJobId != null && notifyJobId.trim().isNotEmpty
          ? notifyJobId.trim()
          : 'turn_${DateTime.now().microsecondsSinceEpoch}_${_turnCounter++}';
      final payload = <String, dynamic>{
        'message': message,
        'history': history,
        'currentOutfitItemIds': currentOutfitItemIds,
        if (currentSelectionReasons.isNotEmpty) 'currentSelectionReasons': currentSelectionReasons,
        'weatherContext': weatherContext,
        'clientContext': clientContext,
        if (eventContext != null && eventContext.isNotEmpty) 'eventContext': eventContext,
        if (shoppingContext != null && shoppingContext.isNotEmpty) 'shoppingContext': shoppingContext,
        'shoppingEnabled': shoppingEnabled,
        'v2SessionId': targetSessionId,
        'turnId': stableTurnId,
        if (previousSessionId != null) 'previousV2SessionId': previousSessionId,
        if (notifyJobId != null && notifyJobId.trim().isNotEmpty) 'notifyJobId': notifyJobId.trim(),
        if (realChatId.isNotEmpty) 'chatId': realChatId,
      };

      _refreshStylePreferencesInBackground();
      final stylePayload = _cachedStylePreferencesPayload;
      if (stylePayload != null) payload['userStylePreferences'] = Map<String, dynamic>.from(stylePayload);

      final response = await callable.call(_jsonSafeMap(payload)).timeout(const Duration(seconds: 90));
      if (response.data is! Map) throw const FormatException('simple_agent_response_not_map');
      final rawData = Map<String, dynamic>.from(response.data as Map);
      _lastV2SessionId = targetSessionId;
      if (realChatId.isNotEmpty) _boundRealChatId = realChatId;
      if (_shoppingActions.contains((rawData['action'] ?? '').toString())) {
        debugPrint('SIMPLE_AGENT_SHOPPING_HANDOFF action=${rawData['action']} latencyMs=${stopwatch.elapsedMilliseconds}');
        return rawData;
      }
      debugPrint('SIMPLE_AGENT_RESULT received=true path=${rawData['modelPath'] ?? 'unknown'} latencyMs=${stopwatch.elapsedMilliseconds}');
      final result = StylistSimpleAgentResultV1.fromCallableData(rawData);
      if (result.failClosed) {
        debugPrint('SIMPLE_AGENT_FAIL_CLOSED server=true');
      } else {
        debugPrint('SIMPLE_AGENT_VALIDATED result=${result.resultingOutfitItemIds} display=${result.displayItemIds}');
      }
      return result.toUiResponse();
    } catch (error, stackTrace) {
      debugPrint('SIMPLE_AGENT_FAIL_CLOSED client=$error latencyMs=${stopwatch.elapsedMilliseconds}');
      debugPrint('$stackTrace');
      final offline = error is TimeoutException ||
          (error is FirebaseFunctionsException && const {'unavailable', 'deadline-exceeded', 'internal'}.contains(error.code));
      return <String, dynamic>{
        'ok': false, 'offline': offline, 'simpleAgent': true, 'failClosed': true,
        'reply': 'Túto požiadavku sa mi nepodarilo bezpečne dokončiť, takže aktuálny outfit nemením.',
        'stylistComment': 'Túto požiadavku sa mi nepodarilo bezpečne dokončiť, takže aktuálny outfit nemením.',
        'resultingOutfitItemIds': const <String>[], 'displayItemIds': const <String>[],
        'resultingOutfitItems': const <Map<String, dynamic>>[], 'displayItems': const <Map<String, dynamic>>[],
        'outfitChanged': false, 'quickReplyMode': 'none', 'action': 'simple_agent_fail_closed',
      };
    }
  }

  static const Set<String> _shoppingActions = <String>{
    'SHOPPING_CLARIFY_SOURCE', 'ASK_PERMISSION_TO_SHOP', 'START_SHOPPING_SEARCH', 'REFINE_SHOPPING_SEARCH',
    'SHOW_MORE_SHOPPING', 'SHOW_ALL_SHOPPING', 'FOCUS_SHOPPING_PRODUCT', 'OFFER_WISHLIST', 'WISHLIST_EDITOR',
    'RETURN_TO_WARDROBE_STYLIST', 'ASK_SHOPPING_MAX_PRICE', 'SHOPPING_CLARIFY_STYLE', 'UNSUPPORTED_STRUCTURED_CONSTRAINT',
  };

  static Map<String, dynamic> normalizeJobResult(Map<String, dynamic> data) {
    if (_shoppingActions.contains((data['action'] ?? '').toString())) return Map<String, dynamic>.from(data);
    try {
      return StylistSimpleAgentResultV1.fromCallableData(data).toUiResponse();
    } catch (_) {
      return const <String, dynamic>{
        'ok': false, 'simpleAgent': true, 'failClosed': true,
        'reply': 'Túto požiadavku sa mi nepodarilo bezpečne dokončiť, takže aktuálny outfit nemením.',
        'stylistComment': 'Túto požiadavku sa mi nepodarilo bezpečne dokončiť, takže aktuálny outfit nemením.',
        'resultingOutfitItemIds': <String>[], 'displayItemIds': <String>[],
        'resultingOutfitItems': <Map<String, dynamic>>[], 'displayItems': <Map<String, dynamic>>[],
        'outfitChanged': false, 'quickReplyMode': 'none', 'action': 'simple_agent_fail_closed',
      };
    }
  }

  static Map<String, dynamic> _jsonSafeMap(Map<String, dynamic> input) {
    dynamic convert(dynamic value) {
      if (value == null || value is num || value is bool || value is String) return value;
      if (value is Timestamp) return value.millisecondsSinceEpoch;
      if (value is DateTime) return value.toIso8601String();
      if (value is Map) return value.map((key, child) => MapEntry(key.toString(), convert(child)));
      if (value is Iterable) return value.map(convert).toList(growable: false);
      return value.toString();
    }
    return Map<String, dynamic>.from(convert(input) as Map);
  }
}
