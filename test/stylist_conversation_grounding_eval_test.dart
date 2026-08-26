import 'package:flutter_test/flutter_test.dart';

import 'package:outfitofTheDay/models/outfit_context_state.dart';

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

    test('date correction has authority over an earlier relative date', () {
      final state = stateFor(
        'Zajtra idem do Viedne na večeru. Nie zajtra, až v sobotu.',
        latest: 'Nie zajtra, až v sobotu.',
      );
      expect(state.dateKey, isNot('tomorrow'));
      expect(state.activityLocationLabel, 'Viedeň');
    });

    test(
      'multi-day Prague travel is not treated as a two-hour local event',
      () {
        final state = stateFor('Ideme na tri dni do Prahy.');
        expect(state.groundingStatus, 'needs_grounding');
        expect(state.unresolvedMaterialFields, contains('trip_scope'));
      },
    );

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
