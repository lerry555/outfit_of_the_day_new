import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/stylist_simple_agent_service_v1.dart';
import 'package:outfitofTheDay/Services/hourly_weather_service.dart';
import 'package:outfitofTheDay/screens/stylist_chat_screen.dart';

Map<String, dynamic> _item(String id, String name) => <String, dynamic>{
  'id': id,
  'name': name,
  'canonicalType': 'fixture_type',
  'canonicalFamily': 'fixture_family',
  'bodySlots': const <String>['upper_body'],
  'layerPosition': 'base',
  'colorProfile': const <String, dynamic>{
    'primary': <String, dynamic>{'family': 'blue'},
  },
};

void main() {
  test('text-only explanation retains full outfit state without restoring item cards', () {
    final items = [_item('top', 'Tričko'), _item('jeans', 'Rifle'), _item('shoes', 'Tenisky')];
    final result = StylistSimpleAgentResultV1.fromCallableData({
      'simpleAgent': true, 'stylistComment': 'Rifle zakryjú nohy; over si voľnosť pohybu.',
      'resultingOutfitItemIds': ['top', 'jeans', 'shoes'], 'displayItemIds': [],
      'outfitChanged': false, 'outfitRequested': false,
      'resultingOutfitItems': items, 'displayItems': [],
    });
    expect(result.ok, isTrue);
    expect(result.displayItems, isEmpty);
    final message = StylistChatMessage(text: result.stylistComment, isUser: false,
      suggestedItems: result.displayItems, resultingOutfitItems: result.resultingOutfitItems);
    final restored = StylistChatMessage.fromMap(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(message.toMap())) as Map));
    expect(restored.suggestedItems, isEmpty);
    expect(restored.resultingOutfitItems.map((item) => item['id']), ['top', 'jeans', 'shoes']);
    expect(result.toUiResponse()['displayItems'], isEmpty);
  });

  test('partial outfit with honest footwear gap survives parsing and chat persistence', () {
    final items = [_item('top', 'Tričko'), _item('bottom', 'Nohavice')];
    const warning = 'Na mokrý terén ti chýba vhodná obuv; doplň turistický pár.';
    final result = StylistSimpleAgentResultV1.fromCallableData({
      'simpleAgent': true,
      'stylistComment': warning,
      'resultingOutfitItemIds': ['top', 'bottom'],
      'displayItemIds': ['top', 'bottom'],
      'outfitChanged': true,
      'resultingOutfitItems': items,
      'displayItems': items,
      'footwearAssessment': {
        'use': 'terrain', 'weatherWindow': 'morning',
        'status': 'missing', 'message': warning,
      },
    });
    expect(result.ok, isTrue);
    expect(result.failClosed, isFalse);
    final message = StylistChatMessage(text: result.stylistComment,
      isUser: false, suggestedItems: result.displayItems,
      resultingOutfitItems: result.resultingOutfitItems);
    final restored = StylistChatMessage.fromMap(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(message.toMap())) as Map));
    expect(restored.text, warning);
    expect(restored.resultingOutfitItems.map((item) => item['id']), ['top', 'bottom']);
    expect(restored.suggestedItems.map((item) => item['id']), ['top', 'bottom']);
  });

  test('weather snapshots retain original hourly codes independently of UI labels', () {
    final codes = List<int?>.filled(24, null)..[8] = 75;
    final snapshot = OutfitWeatherDaySnapshot(
      cityName: 'Martin', date: DateTime(2026, 12, 3),
      morningTempC: -2, noonTempC: 3, eveningTempC: 0, minTempC: -3, maxTempC: 3,
      willRain: false, rainTimeText: null, outfitWhyWeatherNote: '',
      morningRainSegment: false, afternoonRainSegment: false, eveningRainSegment: false,
      isWindy: false, summaryText: '', fromOpenMeteo: true,
      mainChipTempC: 3, mainChipBasis: 'fixture', mainChipHour: 14,
      briefingMorningCondition: 'Oblačno', briefingAfternoonCondition: 'Oblačno',
      briefingEveningCondition: 'Oblačno', hourlyWeatherCodeByLocalHour: codes,
    );
    expect(snapshot.hourlyWeatherCodeByLocalHour?[8], 75);
    expect(snapshot.hourlyWeatherCodeByLocalHour?[9], isNull);
    final source = File('lib/screens/stylist_chat_screen.dart').readAsStringSync();
    final start = source.indexOf('Map<String, dynamic> _snapshotToWeatherContext(');
    final end = source.indexOf('Future<void> _ensureWeatherContext()', start);
    final transport = source.substring(start, end);
    expect(transport, contains("'hourlyWeatherCodeByLocalHour': snapshot.hourlyWeatherCodeByLocalHour"));
    expect(transport, contains("'hourlyTempCByLocalHour': snapshot.hourlyTempCByLocalHour"));
    final weatherSource = File('lib/Services/hourly_weather_service.dart').readAsStringSync();
    expect(weatherSource, contains('hourlyWeatherCodeByLocalHour: _hourlyWeatherCodeMap(weather.points)'));
    expect(weatherSource, contains('hourlyWeatherCodeByLocalHour: _hourlyWeatherCodeMap(points)'));
  });

  test('selection reason survives callable parsing and persisted chat restoration', () {
    final piece = _item('jeans', 'Rifle')
      ..['stylistSelectionReason'] = 'Rifle kvôli chladnejšiemu ránu.';
    final result = StylistSimpleAgentResultV1.fromCallableData({
      'simpleAgent': true,
      'stylistComment': 'Outfit na celý deň.',
      'resultingOutfitItemIds': ['jeans'],
      'displayItemIds': ['jeans'],
      'outfitChanged': true,
      'resultingOutfitItems': [piece],
      'displayItems': [piece],
    });
    final message = StylistChatMessage(
      text: result.stylistComment,
      isUser: false,
      resultingOutfitItems: result.resultingOutfitItems,
    );
    final restored = StylistChatMessage.fromMap(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(message.toMap())) as Map),
    );
    expect(restored.resultingOutfitItems.single['stylistSelectionReason'],
        'Rifle kvôli chladnejšiemu ránu.');
    expect(restored.text, 'Outfit na celý deň.');
  });

  test('validated result preserves backend ID order for state and display', () {
    final data = <String, dynamic>{
      'simpleAgent': true,
      'stylistComment': 'Vymenil som iba spodok.',
      'resultingOutfitItemIds': const <String>[
        'blue-top',
        'shorts',
        'white-shoes',
      ],
      'displayItemIds': const <String>['shorts'],
      'outfitChanged': true,
      'resultingOutfitItems': <Map<String, dynamic>>[
        _item('white-shoes', 'biele tenisky'),
        _item('blue-top', 'modré tričko'),
        _item('shorts', 'krátke gate'),
      ],
      'displayItems': <Map<String, dynamic>>[_item('shorts', 'krátke gate')],
    };

    final result = StylistSimpleAgentResultV1.fromCallableData(data);
    expect(result.resultingOutfitItemIds, [
      'blue-top',
      'shorts',
      'white-shoes',
    ]);
    expect(result.resultingOutfitItems.map((item) => item['id']), [
      'blue-top',
      'shorts',
      'white-shoes',
    ]);
    expect(result.displayItemIds, ['shorts']);
    expect(result.displayItems.single['id'], 'shorts');
    expect(result.outfitChanged, isTrue);
  });

  test('invented or mismatched materialized IDs fail closed on the client', () {
    expect(
      () => StylistSimpleAgentResultV1.fromCallableData(<String, dynamic>{
        'simpleAgent': true,
        'stylistComment': 'Hotovo.',
        'resultingOutfitItemIds': const <String>['blue-top', 'invented'],
        'displayItemIds': const <String>['invented'],
        'outfitChanged': true,
        'resultingOutfitItems': <Map<String, dynamic>>[
          _item('blue-top', 'modré tričko'),
        ],
        'displayItems': <Map<String, dynamic>>[
          _item('invented', 'vymyslený kus'),
        ],
      }),
      throwsFormatException,
    );
  });

  test(
    'explicit server fail-closed result cannot mutate client outfit state',
    () {
      final normalized = StylistSimpleAgentServiceV1.normalizeJobResult(
        const <String, dynamic>{
          'simpleAgent': true,
          'failClosed': true,
          'stylistComment': 'Aktuálny outfit nemením.',
        },
      );
      expect(normalized['ok'], isFalse);
      expect(normalized['failClosed'], isTrue);
      expect(normalized['resultingOutfitItems'], isEmpty);
      expect(normalized['displayItems'], isEmpty);
      expect(normalized['outfitChanged'], isFalse);
    },
  );

  test(
    'ordinary Brain V1 UI turn bypasses every legacy outfit interpreter',
    () {
      final source = File(
        'lib/screens/stylist_chat_screen.dart',
      ).readAsStringSync();
      final start = source.indexOf('Future<void> _sendMessage() async');
      final end = source.indexOf('Future<void> _showImageSourceSheet()', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final scope = source.substring(start, end);
      expect(scope, contains('_stylistSimpleAgentService.sendTurn'));
      expect(scope, contains('_handleSimpleAgentResponse(response)'));
      expect(scope, isNot(contains('StylistSwapRequest')));
      expect(scope, isNot(contains('explicit_swap')));
      expect(scope, isNot(contains('outfitDirective')));
      expect(scope, isNot(contains('StylistOutfitDirectiveGuard')));
      expect(scope, isNot(contains('OutfitEditPlan')));
      expect(scope, isNot(contains('_stylistChatOutfitService')));
      expect(scope, isNot(contains('RegExp(')));
      expect(scope, isNot(contains('_handleAssistantResponse(')));
    },
  );
}
