import 'package:flutter_test/flutter_test.dart';

import 'package:outfitofTheDay/models/outfit_context_state.dart';
import 'package:outfitofTheDay/utils/stylist_day_parser.dart';

/// Conversation-level regression evaluation for the deterministic gate that
/// runs before GPT-4o context framing and before any frozen candidate request.
/// It tests event authority/action readiness rather than response prose.
void main() {
  OutfitContextState stateFor(String text, {String? latest}) =>
      OutfitContextState.buildFrom(
        conversation: text,
        latestUserText: latest ?? text,
        gpsCityLabel: 'Martin',
      );

  group('Stylist conversation grounding trajectories', () {
    test('explicit city-centre request is generation-ready', () {
      final state = OutfitContextState.buildFrom(
        conversation: 'Dnes idem do centra v Žiline, čo si mám dať?',
        latestUserText: 'Dnes idem do centra v Žiline, čo si mám dať?',
        gpsCityLabel: 'Martin',
      );

      expect(state.activityLocationLabel, 'Žilina');
      expect(state.activityHint, 'city_walk');
      expect(state.unresolvedMaterialFields, isEmpty);
      expect(state.groundingStatus, 'sufficient');
    });

    test(
      'ambiguous trip stays clarify-only and GPS remains non-event context',
      () {
        final state = stateFor(
          'zajtra chceme ist na vylet, budem potrebovat pomoc s vyberom outfitu',
        );
        expect(state.groundingStatus, 'needs_grounding');
        expect(state.activityLocationLabel, isNull);
        expect(
          state.unresolvedMaterialFields,
          containsAll(['destination', 'activity']),
        );
      },
    );

    test(
      'assistant-style challenge invalidates unsupported location and activity',
      () {
        final state = stateFor(
          'zajtra chceme ist na vylet kde som tvrdil ze idem na prechadzku okolo Martina?',
          latest: 'kde som tvrdil ze idem na prechadzku okolo Martina?',
        );
        expect(state.userCorrectionDetected, isTrue);
        expect(state.groundingStatus, 'needs_grounding');
        expect(state.activityLocationLabel, isNull);
      },
    );

    test(
      'specific destination, terrain, start and duration are generation-ready',
      () {
        final state = stateFor(
          'Zajtra ideme do Tatier na 6-hodinovú turistiku, vyrážame o 8:00.',
        );
        expect(state.groundingStatus, 'sufficient');
        expect(state.activityLocationLabel, 'Tatry');
        expect(state.hourLocal, 8);
      },
    );

    test(
      'zoo is not silently made into hiking and has an explicit destination',
      () {
        final state = stateFor('Zajtra ideme do ZOO v Bojniciach na celý deň.');
        expect(state.groundingStatus, 'sufficient');
        expect(state.activityLocationLabel, 'Bojnice');
        expect(state.activityHint, isNot('turist'));
      },
    );

    test('travel to Vienna does not inherit Martin as destination', () {
      final state = stateFor(
        'Zajtra ideme autom do Viedne, budeme chodiť po centre a večer na večeru.',
      );
      expect(state.groundingStatus, 'sufficient');
      expect(state.activityLocationLabel, 'Viedeň');
      expect(state.activityLocationLabel, isNot('Martin'));
    });

    test('transport mode alone does not ground the destination activity', () {
      final state = stateFor(
        'cez vikend ideme do Viedne a budem chciet poradit outfit ideme autom',
        latest: 'ideme autom',
      );

      expect(state.activityLocationLabel, 'Viedeň');
      expect(state.activityHint, 'travel');
      expect(state.unresolvedMaterialFields, containsAll(['activity', 'date']));
      expect(state.groundingStatus, 'needs_grounding');
    });

    test('an explicit travel-day outfit may treat transport as the activity', () {
      final state = stateFor(
        'cez vikend ideme do Viedne autom a chcem outfit na cestu v sobotu',
      );

      expect(state.activityHint, 'travel');
      expect(state.unresolvedMaterialFields, isEmpty);
      expect(state.groundingStatus, 'sufficient');
    });

    test('typo-tolerant city answer synchronizes destination and activity', () {
      final state = stateFor(
        'zajtra ideme na výlet cestujeme do USA a tam popozeráme po meste '
        'Wasntom a prechádzka po meste',
        latest: 'Wasntom a prechádzka po meste',
      );
      expect(state.activityLocationLabel, 'Washington');
      expect(state.activityHint, 'city_walk');
      expect(state.groundingStatus, 'sufficient');
      expect(state.unresolvedMaterialFields, isEmpty);
    });

    test(
      'routine work request can use local system context without a form',
      () {
        final state = stateFor('Čo si mám zajtra obliecť do práce?');
        expect(state.groundingStatus, 'sufficient');
        expect(state.unresolvedMaterialFields, isEmpty);
      },
    );

    test(
      'venue/activity correction does not preserve the old city assumption',
      () {
        final state = stateFor(
          'Zajtra ideme do mesta. Nie, nejdeme do mesta, ideme do lesa.',
          latest: 'Nie, nejdeme do mesta, ideme do lesa.',
        );
        expect(state.userCorrectionDetected, isTrue);
        expect(state.groundingStatus, 'needs_grounding');
        expect(state.unresolvedMaterialFields, contains('destination'));
      },
    );

    test('correction follow-up makes the latest destination and activity authoritative', () {
      final initial = stateFor('Zajtra idem do Žiliny na prechadzku po meste.');
      final corrected = OutfitContextState.buildFrom(
        conversation:
            'Zajtra idem do Žiliny na prechadzku po meste. '
            'Nie, nejdeme do mesta, ideme do lesa.',
        latestUserText: 'Nie, nejdeme do mesta, ideme do lesa.',
        gpsCityLabel: 'Martin',
        previous: initial,
      );
      final completed = OutfitContextState.buildFrom(
        conversation:
            'Zajtra idem do Žiliny na prechadzku po meste. '
            'Nie, nejdeme do mesta, ideme do lesa. '
            'Ostávame pri Martine asi dve hodiny.',
        latestUserText: 'Ostávame pri Martine asi dve hodiny.',
        gpsCityLabel: 'Martin',
        previous: corrected,
      );

      expect(completed.activityLocationLabel, 'Martin');
      expect(completed.activityHint, contains('les'));
      expect(completed.groundingStatus, 'sufficient');
    });

    test('date correction has authority over an earlier relative date', () {
      expect(
        StylistDayParser.resolveDate(
          'Nie zajtra, až v sobotu.',
          now: DateTime(2026, 8, 26),
        ),
        DateTime(2026, 8, 29),
      );
      expect(
        StylistDayParser.resolveDate(
          'Cestujeme od soboty.',
          now: DateTime(2026, 8, 26),
        ),
        DateTime(2026, 8, 29),
      );
      final state = stateFor(
        'Zajtra idem do Viedne na večeru. Nie zajtra, až v sobotu.',
        latest: 'Nie zajtra, až v sobotu.',
      );
      expect(state.dateKey, isNot('tomorrow'));
      expect(state.activityLocationLabel, 'Viedeň');
      expect(state.userCorrectionDetected, isTrue);
    });

    test('common city-walk typo grounds activity without inventing a city', () {
      final state = stateFor(
        'zajtra chceme ist na vylet cestujeme do USA a tam pojdeme popozerat po mete',
        latest: 'cestujeme do USA a tam pojdeme popozerat po mete',
      );

      expect(state.activityHint, 'city_walk');
      expect(state.activityLocationKnown, isFalse);
      expect(state.unresolvedMaterialFields, ['destination']);
    });

    test('a vague evening is not silently converted into dinner', () {
      final state = stateFor(
        'zajtra vecer niekam ideme a neviem co si obliect',
      );

      expect(state.activityHint, isNull);
      expect(state.unresolvedMaterialFields, containsAll(['destination', 'activity']));
      expect(state.groundingStatus, 'needs_grounding');
    });

    test(
      'multi-day Prague travel is not treated as a two-hour local event',
      () {
        final state = stateFor('Ideme na tri dni do Prahy.');
        expect(state.groundingStatus, 'needs_grounding');
        expect(state.unresolvedMaterialFields, contains('trip_scope'));
        expect(state.unresolvedMaterialFields, contains('date'));
      },
    );

    test('packing wording resolves multi-day scope but still requires activities', () {
      final state = stateFor('Ideme na tri dni do Prahy a neviem co si zobrat.');

      expect(state.unresolvedMaterialFields, contains('activity'));
      expect(state.unresolvedMaterialFields, contains('date'));
      expect(state.unresolvedMaterialFields, isNot(contains('trip_scope')));
      expect(state.groundingStatus, 'needs_grounding');
      expect(
        OutfitContextState.isMultiDayPackingRequest(
          'Ideme na tri dni do Prahy a neviem čo si zbaliť.',
        ),
        isTrue,
      );
    });

    test('sightseeing grounds multi-day city activity before trip scope', () {
      final state = stateFor(
        'Ideme na tri dni do Prahy. Cez deň pamiatky a veľa chodenia, jeden večer lepšia večera.',
        latest:
            'Cez deň pamiatky a veľa chodenia, jeden večer lepšia večera.',
      );

      expect(state.activityHint, 'city_walk');
      expect(
        state.unresolvedMaterialFields,
        containsAll(['date', 'trip_scope']),
      );
    });

    test('paraphrased ambiguous outings remain grounded before generation', () {
      for (final text in [
        'zajtra niekam vybehneme',
        'cez víkend chceme ísť na výlet',
        'ideme preč na celý deň',
        'zajtra budem potrebovať outfit na cestu',
        'asi pôjdeme niekam von',
        'chystáme sa do prírody',
        'ideme na hrad',
        'ideme s malou do zoo',
      ]) {
        final state = stateFor(text);
        expect(state.groundingStatus, 'needs_grounding', reason: text);
      }
    });
  });
}
