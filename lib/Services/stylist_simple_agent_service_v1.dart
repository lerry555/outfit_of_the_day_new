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
  final List<Map<String, dynamic>> resultingOutfitItems;
  final List<Map<String, dynamic>> displayItems;

  static List<String>? _ids(Object? raw) {
    if (raw is! List) return null;
    final ids = raw
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (ids.length != raw.length || ids.toSet().length != ids.length) {
      return null;
    }
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
    final comment = (data['stylistComment'] ?? data['reply'] ?? '')
        .toString()
        .trim();
    if (data['simpleAgent'] != true || comment.isEmpty) {
      throw const FormatException('simple_agent_contract_invalid');
    }
    if (failClosed) {
      return StylistSimpleAgentResultV1(
        ok: false,
        failClosed: true,
        stylistComment: comment,
        resultingOutfitItemIds: const [],
        displayItemIds: const [],
        outfitChanged: false,
        quickReplyMode: 'none',
        resultingOutfitItems: const [],
        displayItems: const [],
      );
    }

    final resultIds = _ids(data['resultingOutfitItemIds']);
    final displayIds = _ids(data['displayItemIds']);
    final resultById = _itemsById(data['resultingOutfitItems']);
    final displayById = _itemsById(data['displayItems']);
    if (resultIds == null ||
        displayIds == null ||
        resultById == null ||
        displayById == null ||
        data['outfitChanged'] is! bool) {
      throw const FormatException('simple_agent_contract_invalid');
    }
    if (resultById.keys.toSet().length != resultIds.length ||
        !resultIds.every(resultById.containsKey) ||
        displayById.keys.toSet().length != displayIds.length ||
        !displayIds.every(displayById.containsKey) ||
        !displayIds.every(resultIds.contains)) {
      throw const FormatException('simple_agent_id_materialization_mismatch');
    }

    return StylistSimpleAgentResultV1(
      ok: true,
      failClosed: false,
      stylistComment: comment,
      resultingOutfitItemIds: List<String>.unmodifiable(resultIds),
      displayItemIds: List<String>.unmodifiable(displayIds),
      outfitChanged: data['outfitChanged'] as bool,
      quickReplyMode: data['quickReplyMode'] == 'yes_no' ? 'yes_no' : 'none',
      resultingOutfitItems: List<Map<String, dynamic>>.unmodifiable(
        resultIds.map((id) => Map<String, dynamic>.from(resultById[id]!)),
      ),
      displayItems: List<Map<String, dynamic>>.unmodifiable(
        displayIds.map((id) => Map<String, dynamic>.from(displayById[id]!)),
      ),
    );
  }

  Map<String, dynamic> toUiResponse() => <String, dynamic>{
    'ok': ok,
    'simpleAgent': true,
    'failClosed': failClosed,
    'reply': stylistComment,
    'stylistComment': stylistComment,
    'resultingOutfitItemIds': resultingOutfitItemIds,
    'displayItemIds': displayItemIds,
    'outfitChanged': outfitChanged,
    'quickReplyMode': quickReplyMode,
    'resultingOutfitItems': resultingOutfitItems,
    'displayItems': displayItems,
    'action': failClosed ? 'simple_agent_fail_closed' : 'simple_agent_result',
  };
}

class StylistSimpleAgentServiceV1 {
  StylistSimpleAgentServiceV1({
    FirebaseAuth? auth,
    UserStylePreferencesReader? stylePreferences,
  }) : _authOverride = auth,
       _stylePreferences =
           stylePreferences ?? UserStylePreferencesReader(auth: auth);

  final FirebaseAuth? _authOverride;
  final UserStylePreferencesReader _stylePreferences;

  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  Future<Map<String, dynamic>> sendTurn({
    required String message,
    required List<Map<String, String>> history,
    required List<String> currentOutfitItemIds,
    List<Map<String, String>> currentSelectionReasons = const [],
    required Map<String, dynamic> weatherContext,
    required Map<String, dynamic> clientContext,
    Map<String, dynamic>? eventContext,
    String? notifyJobId,
    String? chatId,
  }) async {
    debugPrint(
      'SIMPLE_AGENT_REQUEST history=${history.length} '
      'current=${currentOutfitItemIds.length}',
    );
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-east1',
      ).httpsCallable('stylistSimpleAgentV1');
      final payload = <String, dynamic>{
        'message': message,
        'history': history,
        'currentOutfitItemIds': currentOutfitItemIds,
        if (currentSelectionReasons.isNotEmpty)
          'currentSelectionReasons': currentSelectionReasons,
        'weatherContext': weatherContext,
        'clientContext': clientContext,
        if (eventContext != null && eventContext.isNotEmpty)
          'eventContext': eventContext,
        if (notifyJobId != null && notifyJobId.trim().isNotEmpty)
          'notifyJobId': notifyJobId.trim(),
        if (chatId != null && chatId.trim().isNotEmpty) 'chatId': chatId.trim(),
      };
      try {
        final prefs = await _stylePreferences.loadForUid(
          _auth.currentUser?.uid,
        );
        final stylePayload = StylePreferencesRuntime.stylistPayload(prefs);
        if (stylePayload != null) {
          payload['userStylePreferences'] = stylePayload;
        }
      } catch (_) {}

      final response = await callable
          .call(_jsonSafeMap(payload))
          .timeout(const Duration(seconds: 90));
      if (response.data is! Map) {
        throw const FormatException('simple_agent_response_not_map');
      }
      debugPrint('SIMPLE_AGENT_RESULT received=true');
      final result = StylistSimpleAgentResultV1.fromCallableData(
        response.data as Map,
      );
      if (result.failClosed) {
        debugPrint('SIMPLE_AGENT_FAIL_CLOSED server=true');
      } else {
        debugPrint(
          'SIMPLE_AGENT_VALIDATED result=${result.resultingOutfitItemIds} '
          'display=${result.displayItemIds}',
        );
      }
      return result.toUiResponse();
    } catch (error, stackTrace) {
      debugPrint('SIMPLE_AGENT_FAIL_CLOSED client=$error');
      debugPrint('$stackTrace');
      final offline =
          error is TimeoutException ||
          (error is FirebaseFunctionsException &&
              const {
                'unavailable',
                'deadline-exceeded',
                'internal',
              }.contains(error.code));
      return <String, dynamic>{
        'ok': false,
        'offline': offline,
        'simpleAgent': true,
        'failClosed': true,
        'reply':
            'Túto požiadavku sa mi nepodarilo bezpečne dokončiť, takže aktuálny outfit nemením.',
        'stylistComment':
            'Túto požiadavku sa mi nepodarilo bezpečne dokončiť, takže aktuálny outfit nemením.',
        'resultingOutfitItemIds': const <String>[],
        'displayItemIds': const <String>[],
        'resultingOutfitItems': const <Map<String, dynamic>>[],
        'displayItems': const <Map<String, dynamic>>[],
        'outfitChanged': false,
        'quickReplyMode': 'none',
        'action': 'simple_agent_fail_closed',
      };
    }
  }

  static Map<String, dynamic> normalizeJobResult(Map<String, dynamic> data) {
    try {
      return StylistSimpleAgentResultV1.fromCallableData(data).toUiResponse();
    } catch (_) {
      return const <String, dynamic>{
        'ok': false,
        'simpleAgent': true,
        'failClosed': true,
        'reply':
            'Túto požiadavku sa mi nepodarilo bezpečne dokončiť, takže aktuálny outfit nemením.',
        'stylistComment':
            'Túto požiadavku sa mi nepodarilo bezpečne dokončiť, takže aktuálny outfit nemením.',
        'resultingOutfitItemIds': <String>[],
        'displayItemIds': <String>[],
        'resultingOutfitItems': <Map<String, dynamic>>[],
        'displayItems': <Map<String, dynamic>>[],
        'outfitChanged': false,
        'quickReplyMode': 'none',
        'action': 'simple_agent_fail_closed',
      };
    }
  }

  static Map<String, dynamic> _jsonSafeMap(Map<String, dynamic> input) {
    dynamic convert(dynamic value) {
      if (value == null || value is num || value is bool || value is String) {
        return value;
      }
      if (value is Timestamp) return value.millisecondsSinceEpoch;
      if (value is DateTime) return value.toIso8601String();
      if (value is Map) {
        return value.map(
          (key, child) => MapEntry(key.toString(), convert(child)),
        );
      }
      if (value is Iterable) {
        return value.map(convert).toList(growable: false);
      }
      return value.toString();
    }

    return Map<String, dynamic>.from(convert(input) as Map);
  }
}
