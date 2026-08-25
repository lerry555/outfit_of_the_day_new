import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/observation_absence_qualifier.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_observation_contract.dart';

void main() {
  const qualifier = ObservationAbsenceQualifier();

  ObservationValue<VisiblePocketStructure> pocket(
    VisiblePocketStructure value,
    ObservationVisibilityScope scope, {
    double confidence = 0.95,
  }) => ObservationValue.observed(
    value: value,
    confidence: confidence,
    visibilityScope: scope,
  );

  test('front-only pocket none degrades to unknown', () {
    final result = qualifier.qualify(
      policy: ObservationAbsencePolicies.pockets,
      observations: [
        pocket(VisiblePocketStructure.none, ObservationVisibilityScope.partial),
      ],
    );

    expect(result.qualified.state, ObservationState.unknown);
    expect(result.raw.single.value, VisiblePocketStructure.none);
    expect(result.reasonCodes, contains('insufficient_visibility_for_absence'));
  });

  test('complete relevant view can confirm pocket none', () {
    final result = qualifier.qualify(
      policy: ObservationAbsencePolicies.pockets,
      observations: [
        pocket(
          VisiblePocketStructure.none,
          ObservationVisibilityScope.complete,
        ),
      ],
    );

    expect(result.qualified.value, VisiblePocketStructure.none);
    expect(result.qualified.confidence, 0.9);
    expect(
      result.reasonCodes,
      contains('complete_visibility_confirms_absence'),
    );
  });

  test('side cargo pocket overrides incomplete negative view', () {
    final result = qualifier.qualify(
      policy: ObservationAbsencePolicies.pockets,
      observations: [
        pocket(VisiblePocketStructure.none, ObservationVisibilityScope.partial),
        pocket(
          VisiblePocketStructure.cargo,
          ObservationVisibilityScope.sufficient,
          confidence: 0.8,
        ),
      ],
    );

    expect(result.qualified.value, VisiblePocketStructure.cargo);
    expect(
      result.reasonCodes,
      contains('positive_existence_overrides_negative'),
    );
  });

  test('unknown and not visible are not negative evidence', () {
    final result = qualifier.qualify(
      policy: ObservationAbsencePolicies.pockets,
      observations: const [
        ObservationValue<VisiblePocketStructure>.unknown(),
        ObservationValue<VisiblePocketStructure>.notVisible(),
      ],
    );

    expect(result.qualified.state, ObservationState.unknown);
    expect(result.reasonCodes, contains('no_observed_absence_evidence'));
  });

  test('not applicable remains not applicable', () {
    final result = qualifier.qualify(
      policy: ObservationAbsencePolicies.pockets,
      observations: const [
        ObservationValue<VisiblePocketStructure>.notApplicable(),
      ],
    );

    expect(result.qualified.state, ObservationState.notApplicable);
    expect(result.reasonCodes, contains('property_not_applicable'));
  });

  test('multiple sufficient views can confirm absence', () {
    final result = qualifier.qualify(
      policy: ObservationAbsencePolicies.pockets,
      observations: [
        pocket(
          VisiblePocketStructure.none,
          ObservationVisibilityScope.sufficient,
          confidence: 0.82,
        ),
        pocket(
          VisiblePocketStructure.none,
          ObservationVisibilityScope.sufficient,
          confidence: 0.84,
        ),
      ],
    );

    expect(result.qualified.value, VisiblePocketStructure.none);
    expect(
      result.reasonCodes,
      contains('multiple_sufficient_views_confirm_absence'),
    );
  });

  test('hood false requires visible hood or collar region', () {
    final result = qualifier.qualify(
      policy: ObservationAbsencePolicies.hood,
      observations: const [
        ObservationValue<bool>.observed(
          value: false,
          confidence: 0.95,
          visibilityScope: ObservationVisibilityScope.partial,
        ),
      ],
    );
    expect(result.qualified.state, ObservationState.unknown);
  });

  test('closure none requires sufficient complete front region', () {
    final result = qualifier.qualify(
      policy: ObservationAbsencePolicies.closure,
      observations: const [
        ObservationValue<FrontClosure>.observed(
          value: FrontClosure.none,
          confidence: 0.95,
          visibilityScope: ObservationVisibilityScope.partial,
        ),
      ],
    );
    expect(result.qualified.state, ObservationState.unknown);
  });

  test('visible stretch false never becomes absence evidence', () {
    final result = qualifier.qualify(
      policy: ObservationAbsencePolicies.stretch,
      observations: const [
        ObservationValue<bool>.observed(
          value: false,
          confidence: 0.95,
          visibilityScope: ObservationVisibilityScope.complete,
        ),
      ],
    );
    expect(result.qualified.state, ObservationState.unknown);
    expect(result.reasonCodes, contains('absence_not_visually_provable'));
  });

  test('conflicting complete positive views remain unknown', () {
    final result = qualifier.qualify(
      policy: ObservationAbsencePolicies.pockets,
      observations: [
        pocket(
          VisiblePocketStructure.cargo,
          ObservationVisibilityScope.complete,
        ),
        pocket(
          VisiblePocketStructure.patch,
          ObservationVisibilityScope.complete,
        ),
      ],
    );
    expect(result.disposition, ObservationQualificationDisposition.conflict);
    expect(result.qualified.state, ObservationState.unknown);
  });
}
