import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/stylist_simple_agent_service_v1.dart';
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
