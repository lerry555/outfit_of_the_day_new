import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/ai_stylist_known_context_adapter_v1.dart';
import 'package:outfitofTheDay/models/outfit_context_state.dart';

void main() {
  test('projects only known deterministic context facts', () {
    final context = AiStylistKnownContextAdapterV1.resolvedContext(
      const OutfitContextState(
        activityHint: 'walk',
        occasion: 'casual',
        activityLocationKnown: false,
        activityLocationLabel: 'Bratislava',
        dateKey: '2026-08-19',
        hourLocal: 18,
        hourExplicit: true,
      ),
    ).toJson();
    expect(context['activity'], 'walk');
    expect(context['occasion'], 'casual');
    expect(context.containsKey('environment'), isFalse);
    expect(context['relevantKnownTimingFacts'], {
      'dateKey': '2026-08-19',
      'hourLocal': '18',
    });
    expect(context.toString(), isNot(contains('gpsDefaultCity')));
    expect(context.toString(), isNot(contains('lastAssumptions')));
  });

  test(
    'does not promote unresolved or non-explicit timing into known facts',
    () {
      final request = AiStylistKnownContextAdapterV1.clarificationRequest(
        const OutfitContextState(hourLocal: 18, hourExplicit: false),
      );
      expect(request.knownFacts, isEmpty);
    },
  );
}
