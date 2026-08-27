import 'package:flutter_test/flutter_test.dart';

import 'package:outfitofTheDay/models/outfit_context_state.dart';

void main() {
  test('explicit Slovak túra answer resolves activity after generic výlet', () {
    final initial = OutfitContextState.buildFrom(
      conversation: 'zajtra idem na výlet',
      latestUserText: 'zajtra idem na výlet',
      gpsCityLabel: 'Martin',
    );

    expect(initial.groundingStatus, 'needs_grounding');
    expect(
      initial.unresolvedMaterialFields,
      containsAll(<String>['destination', 'activity']),
    );

    final completed = OutfitContextState.buildFrom(
      conversation:
          'zajtra idem na výlet. '
          'Do Vysokých Tatier, ideme na túru asi na 6 hodín a vyrážame okolo 8:00.',
      latestUserText:
          'Do Vysokých Tatier, ideme na túru asi na 6 hodín a vyrážame okolo 8:00.',
      gpsCityLabel: 'Martin',
      previous: initial,
    );

    expect(completed.activityHint, 'hike');
    expect(completed.activityLocationKnown, isTrue);
    expect(completed.hourLocal, 8);
    expect(completed.unresolvedMaterialFields, isNot(contains('activity')));
    expect(completed.unresolvedMaterialFields, isEmpty);
    expect(completed.groundingStatus, 'sufficient');
  });

  test('generic výlet is still not silently promoted to hiking', () {
    final state = OutfitContextState.buildFrom(
      conversation: 'zajtra idem na výlet',
      latestUserText: 'zajtra idem na výlet',
      gpsCityLabel: 'Martin',
    );

    expect(state.activityHint, isNot('hike'));
    expect(state.unresolvedMaterialFields, contains('activity'));
  });
}
