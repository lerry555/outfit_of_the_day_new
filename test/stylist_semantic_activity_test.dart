import 'package:flutter_test/flutter_test.dart';

import 'package:outfitofTheDay/models/outfit_context_state.dart';
import 'package:outfitofTheDay/utils/stylist_semantic_activity.dart';

void main() {
  group('StylistSemanticActivity Slovak word families', () {
    test('hiking inflections and paraphrases resolve to one canonical activity', () {
      const samples = <String>[
        'ideme na túru',
        'vrátime sa z túry',
        'celý deň bude turistika',
        'dáme si trekking',
        'čaká nás výšľap na hrebeň',
        'spravíme výstup na vrchol',
        'pôjdeme po hrebeni',
        'ideme do hôr',
        'budeme sa asi 6 hodín motať po vysokohorskom chodníku',
        'budeme kráčať po horskom traili',
        'celý deň pôjdeme po horskej trase',
      ];
      for (final sample in samples) {
        expect(
          StylistSemanticActivity.resolveExplicit(sample),
          'hike',
          reason: sample,
        );
      }
    });

    test('common inflections resolve without per-case lists in callers', () {
      expect(
        StylistSemanticActivity.resolveExplicit('prechádzka po lese'),
        'nature_walk',
      );
      expect(
        StylistSemanticActivity.resolveExplicit('ideme do lesa'),
        'nature_walk',
      );
      expect(
        StylistSemanticActivity.resolveExplicit('pozrieme pamiatky'),
        'city_walk',
      );
      expect(
        StylistSemanticActivity.resolveExplicit('večeru máme v reštaurácii'),
        'dinner',
      );
      expect(
        StylistSemanticActivity.resolveExplicit('idem na bicykli'),
        'cycling',
      );
      expect(
        StylistSemanticActivity.resolveExplicit('večer máme koncert'),
        'concert',
      );
    });

    test('generic outing and bare named destination stay unresolved', () {
      for (final sample in <String>[
        'zajtra idem na výlet',
        'ideme niekam von',
        'chystáme sa preč',
        'zajtra večer niekam ideme',
        'zajtra idem do Tatier',
      ]) {
        expect(
          StylistSemanticActivity.resolveExplicit(sample),
          isNull,
          reason: sample,
        );
      }
    });
  });

  group('OutfitContextState uses shared semantics', () {
    test('explicit hike is ready without asking activity twice', () {
      final first = OutfitContextState.buildFrom(
        conversation: 'zajtra idem na výlet',
        latestUserText: 'zajtra idem na výlet',
        gpsCityLabel: 'Martin',
      );
      final second = OutfitContextState.buildFrom(
        conversation:
            'zajtra idem na výlet Do Vysokých Tatier, ideme na túru asi na 6 hodín a vyrážame okolo 8:00.',
        latestUserText:
            'Do Vysokých Tatier, ideme na túru asi na 6 hodín a vyrážame okolo 8:00.',
        gpsCityLabel: 'Martin',
        previous: first,
      );

      expect(second.activityHint, 'hike');
      expect(second.activityLocationKnown, isTrue);
      expect(second.hourLocal, 8);
      expect(second.unresolvedMaterialFields, isNot(contains('activity')));
      expect(second.groundingStatus, 'sufficient');
    });

    test('natural mountain-walking paraphrase is ready without asking activity twice', () {
      final first = OutfitContextState.buildFrom(
        conversation: 'zajtra idem na výlet',
        latestUserText: 'zajtra idem na výlet',
        gpsCityLabel: 'Martin',
      );
      final second = OutfitContextState.buildFrom(
        conversation:
            'zajtra idem na výlet Do Vysokých Tatier, budeme sa asi 6 hodín motať po vysokohorskom chodníku a vyrážame okolo 8:00.',
        latestUserText:
            'Do Vysokých Tatier, budeme sa asi 6 hodín motať po vysokohorskom chodníku a vyrážame okolo 8:00.',
        gpsCityLabel: 'Martin',
        previous: first,
      );

      expect(second.activityHint, 'hike');
      expect(second.activityLocationKnown, isTrue);
      expect(second.hourLocal, 8);
      expect(second.unresolvedMaterialFields, isNot(contains('activity')));
      expect(second.groundingStatus, 'sufficient');
    });

    test('user evidence payload contains user turns but not assistant prose', () {
      final first = OutfitContextState.buildFrom(
        conversation: 'Kam ideš? zajtra idem na výlet',
        latestUserText: 'zajtra idem na výlet',
        gpsCityLabel: 'Martin',
      );
      final second = OutfitContextState.buildFrom(
        conversation:
            'Kam ideš? zajtra idem na výlet Čo tam budeš robiť? budeme sa motať po vysokohorskom chodníku',
        latestUserText: 'budeme sa motať po vysokohorskom chodníku',
        gpsCityLabel: 'Martin',
        previous: first,
      );

      expect(second.semanticEvidenceTexts, contains('zajtra idem na výlet'));
      expect(
        second.semanticEvidenceTexts,
        contains('budeme sa motať po vysokohorskom chodníku'),
      );
      expect(second.semanticEvidenceTexts.join(' '), isNot(contains('Kam ideš?')));
      expect(
        second.semanticEvidenceTexts.join(' '),
        isNot(contains('Čo tam budeš robiť?')),
      );
    });

    test('server canonical activity response clears stale local activity unknown', () {
      final local = OutfitContextState.buildFrom(
        conversation: 'zajtra idem na výlet do Tatier',
        latestUserText: 'zajtra idem na výlet do Tatier',
        gpsCityLabel: 'Martin',
      );
      expect(local.unresolvedMaterialFields, contains('activity'));

      final reconciled = local.mergeFromAiResponse(
        eventContext: const <String, dynamic>{'occasion': 'hike'},
      );
      expect(reconciled.activityHint, 'hike');
      expect(reconciled.unresolvedMaterialFields, isNot(contains('activity')));
    });
  });
}
