import 'wardrobe_observation_contract.dart';

enum ObservationQualificationDisposition {
  unchanged,
  qualified,
  degradedToUnknown,
  degradedToNotVisible,
  conflict,
}

class QualifiedObservation<T> {
  const QualifiedObservation({
    required this.property,
    required this.raw,
    required this.qualified,
    required this.disposition,
    required this.reasonCodes,
  });

  final String property;
  final List<ObservationValue<T>> raw;
  final ObservationValue<T> qualified;
  final ObservationQualificationDisposition disposition;
  final List<String> reasonCodes;

  Map<String, Object?> toMap(Object? Function(T value) encodeValue) => {
    'property': property,
    'raw': raw.map((item) => item.toMap(encodeValue)).toList(),
    'qualified': qualified.toMap(encodeValue),
    'disposition': disposition.name,
    'reasonCodes': reasonCodes,
  };
}

class ObservationAbsencePolicy<T> {
  const ObservationAbsencePolicy({
    required this.property,
    required this.isAbsence,
    required this.isPositiveExistence,
    required this.minimumSingleViewScope,
    this.minimumConsistentSufficientViews = 2,
    this.maximumAbsenceConfidence = 0.9,
    this.absenceCanBeObserved = true,
  });

  final String property;
  final bool Function(T value) isAbsence;
  final bool Function(T value) isPositiveExistence;
  final ObservationVisibilityScope minimumSingleViewScope;
  final int minimumConsistentSufficientViews;
  final double maximumAbsenceConfidence;
  final bool absenceCanBeObserved;
}

final class ObservationAbsenceQualifier {
  const ObservationAbsenceQualifier();

  QualifiedObservation<T> qualify<T>({
    required ObservationAbsencePolicy<T> policy,
    required Iterable<ObservationValue<T>> observations,
  }) {
    final raw = observations.toList(growable: false);
    final observed = raw.where((item) => item.isObserved).toList();
    final positives = observed
        .where((item) => policy.isPositiveExistence(item.value as T))
        .toList();
    final negatives = observed
        .where((item) => policy.isAbsence(item.value as T))
        .toList();

    if (positives.isNotEmpty) {
      final values = positives.map((item) => item.value as T).toSet();
      if (values.length > 1) {
        return QualifiedObservation(
          property: policy.property,
          raw: raw,
          qualified: ObservationValue<T>.unknown(),
          disposition: ObservationQualificationDisposition.conflict,
          reasonCodes: const ['conflicting_positive_observations'],
        );
      }
      final winner = positives.reduce(
        (left, right) => left.confidence >= right.confidence ? left : right,
      );
      return QualifiedObservation(
        property: policy.property,
        raw: raw,
        qualified: winner,
        disposition: ObservationQualificationDisposition.qualified,
        reasonCodes: negatives.isEmpty
            ? const ['positive_existence_observed']
            : const [
                'positive_existence_overrides_negative',
                'negative_absence_not_decisive',
              ],
      );
    }

    if (negatives.isEmpty) {
      final allNotApplicable =
          raw.isNotEmpty &&
          raw.every((item) => item.state == ObservationState.notApplicable);
      final allNotVisible =
          raw.isNotEmpty &&
          raw.every((item) => item.state == ObservationState.notVisible);
      return QualifiedObservation(
        property: policy.property,
        raw: raw,
        qualified: allNotApplicable
            ? ObservationValue<T>.notApplicable()
            : allNotVisible
            ? ObservationValue<T>.notVisible()
            : ObservationValue<T>.unknown(),
        disposition: allNotApplicable
            ? ObservationQualificationDisposition.unchanged
            : allNotVisible
            ? ObservationQualificationDisposition.degradedToNotVisible
            : ObservationQualificationDisposition.unchanged,
        reasonCodes: [
          allNotApplicable
              ? 'property_not_applicable'
              : allNotVisible
              ? 'relevant_region_not_visible'
              : 'no_observed_absence_evidence',
        ],
      );
    }

    if (!policy.absenceCanBeObserved) {
      return QualifiedObservation(
        property: policy.property,
        raw: raw,
        qualified: ObservationValue<T>.unknown(),
        disposition: ObservationQualificationDisposition.degradedToUnknown,
        reasonCodes: const ['absence_not_visually_provable'],
      );
    }

    final complete = negatives.where(
      (item) =>
          item.visibilityScope == ObservationVisibilityScope.complete &&
          _scopeRank(item.visibilityScope!) >=
              _scopeRank(policy.minimumSingleViewScope),
    );
    final sufficient = negatives.where(
      (item) =>
          item.visibilityScope == ObservationVisibilityScope.sufficient ||
          item.visibilityScope == ObservationVisibilityScope.complete,
    );
    final canConfirm =
        complete.isNotEmpty ||
        sufficient.length >= policy.minimumConsistentSufficientViews;
    if (!canConfirm) {
      final noneVisible = negatives.every(
        (item) => item.visibilityScope == ObservationVisibilityScope.notVisible,
      );
      return QualifiedObservation(
        property: policy.property,
        raw: raw,
        qualified: noneVisible
            ? ObservationValue<T>.notVisible()
            : ObservationValue<T>.unknown(),
        disposition: noneVisible
            ? ObservationQualificationDisposition.degradedToNotVisible
            : ObservationQualificationDisposition.degradedToUnknown,
        reasonCodes: [
          noneVisible
              ? 'relevant_region_not_visible'
              : 'insufficient_visibility_for_absence',
        ],
      );
    }

    final winner = negatives.reduce(
      (left, right) => left.confidence >= right.confidence ? left : right,
    );
    final confidence = winner.confidence < policy.maximumAbsenceConfidence
        ? winner.confidence
        : policy.maximumAbsenceConfidence;
    return QualifiedObservation(
      property: policy.property,
      raw: raw,
      qualified: ObservationValue<T>.observed(
        value: winner.value as T,
        confidence: confidence,
        visibilityScope: winner.visibilityScope,
      ),
      disposition: ObservationQualificationDisposition.qualified,
      reasonCodes: [
        complete.isNotEmpty
            ? 'complete_visibility_confirms_absence'
            : 'multiple_sufficient_views_confirm_absence',
        if (confidence < winner.confidence) 'absence_confidence_calibrated',
      ],
    );
  }

  ObservationAbsenceQualificationReport qualifyBundles(
    Iterable<ClothingObservationBundle> bundles,
  ) {
    final inputs = bundles.toList(growable: false);
    if (inputs.isEmpty) {
      throw ArgumentError.value(bundles, 'bundles', 'Must not be empty');
    }
    final primary = inputs.first;
    final pockets = qualify(
      policy: ObservationAbsencePolicies.pockets,
      observations: inputs
          .map((item) => item.visiblePocketStructure)
          .whereType<ObservationValue<VisiblePocketStructure>>(),
    );
    final hood = qualify(
      policy: ObservationAbsencePolicies.hood,
      observations: inputs
          .map((item) => item.hasHood)
          .whereType<ObservationValue<bool>>(),
    );
    final closure = qualify(
      policy: ObservationAbsencePolicies.closure,
      observations: inputs
          .map((item) => item.frontClosure)
          .whereType<ObservationValue<FrontClosure>>(),
    );
    final stretch = qualify(
      policy: ObservationAbsencePolicies.stretch,
      observations: inputs
          .map((item) => item.visibleStretchCue)
          .whereType<ObservationValue<bool>>(),
    );
    return ObservationAbsenceQualificationReport(
      qualifiedBundle: ClothingObservationBundle(
        analysisId: primary.analysisId,
        modelVersion: primary.modelVersion,
        sourceReference: primary.sourceReference,
        observedAt: primary.observedAt,
        quality: primary.quality,
        coverage: _aggregateOrdinary(inputs.map((item) => item.coverage)),
        hasHood: hood.qualified,
        frontClosure: closure.qualified,
        visibleBulk: _aggregateOrdinary(inputs.map((item) => item.visibleBulk)),
        surfaceAppearance: _aggregateOrdinary(
          inputs.map((item) => item.surfaceAppearance),
        ),
        necklineShape: _aggregateOrdinary(
          inputs.map((item) => item.necklineShape),
        ),
        visiblePocketStructure: pockets.qualified,
        visibleStretchCue: stretch.qualified,
        sportyCues: _aggregateOrdinary(inputs.map((item) => item.sportyCues)),
        formalCues: _aggregateOrdinary(inputs.map((item) => item.formalCues)),
        footwearConstruction: _aggregateOrdinary(
          inputs.map((item) => item.footwearConstruction),
        ),
        footwearFastening: _aggregateOrdinary(
          inputs.map((item) => item.footwearFastening),
        ),
        soleProfile: _aggregateOrdinary(inputs.map((item) => item.soleProfile)),
        visibleTread: _aggregateOrdinary(
          inputs.map((item) => item.visibleTread),
        ),
        footwearUpperHeight: _aggregateOrdinary(
          inputs.map((item) => item.footwearUpperHeight),
        ),
      ),
      pockets: pockets,
      hood: hood,
      closure: closure,
      stretch: stretch,
    );
  }

  static ObservationValue<T>? _aggregateOrdinary<T>(
    Iterable<ObservationValue<T>?> input,
  ) {
    final values = input.whereType<ObservationValue<T>>().toList();
    final observed = values.where((item) => item.isObserved).toList();
    final distinct = observed.map((item) => item.value).toSet();
    if (distinct.length > 1) return ObservationValue<T>.unknown();
    if (observed.isNotEmpty) {
      return observed.reduce(
        (left, right) => left.confidence >= right.confidence ? left : right,
      );
    }
    if (values.any((item) => item.state == ObservationState.unknown)) {
      return ObservationValue<T>.unknown();
    }
    if (values.any((item) => item.state == ObservationState.notVisible)) {
      return ObservationValue<T>.notVisible();
    }
    if (values.any((item) => item.state == ObservationState.notApplicable)) {
      return ObservationValue<T>.notApplicable();
    }
    return null;
  }

  static int _scopeRank(ObservationVisibilityScope scope) => switch (scope) {
    ObservationVisibilityScope.complete => 3,
    ObservationVisibilityScope.sufficient => 2,
    ObservationVisibilityScope.partial => 1,
    ObservationVisibilityScope.notVisible => 0,
  };
}

class ObservationAbsenceQualificationReport {
  const ObservationAbsenceQualificationReport({
    required this.qualifiedBundle,
    required this.pockets,
    required this.hood,
    required this.closure,
    required this.stretch,
  });

  final ClothingObservationBundle qualifiedBundle;
  final QualifiedObservation<VisiblePocketStructure> pockets;
  final QualifiedObservation<bool> hood;
  final QualifiedObservation<FrontClosure> closure;
  final QualifiedObservation<bool> stretch;

  Map<String, Object?> toMap() => {
    'visiblePocketStructure': pockets.toMap((value) => value.wireName),
    'hasHood': hood.toMap((value) => value),
    'frontClosure': closure.toMap((value) => value.wireName),
    'visibleStretchCue': stretch.toMap((value) => value),
  };
}

abstract final class ObservationAbsencePolicies {
  static final pockets = ObservationAbsencePolicy<VisiblePocketStructure>(
    property: 'visiblePocketStructure',
    isAbsence: (value) => value == VisiblePocketStructure.none,
    isPositiveExistence: (value) => value != VisiblePocketStructure.none,
    minimumSingleViewScope: ObservationVisibilityScope.complete,
    maximumAbsenceConfidence: 0.9,
  );

  static final hood = ObservationAbsencePolicy<bool>(
    property: 'hasHood',
    isAbsence: (value) => !value,
    isPositiveExistence: (value) => value,
    minimumSingleViewScope: ObservationVisibilityScope.sufficient,
    maximumAbsenceConfidence: 0.9,
  );

  static final closure = ObservationAbsencePolicy<FrontClosure>(
    property: 'frontClosure',
    isAbsence: (value) => value == FrontClosure.none,
    isPositiveExistence: (value) => value != FrontClosure.none,
    minimumSingleViewScope: ObservationVisibilityScope.sufficient,
    maximumAbsenceConfidence: 0.9,
  );

  static final stretch = ObservationAbsencePolicy<bool>(
    property: 'visibleStretchCue',
    isAbsence: (value) => !value,
    isPositiveExistence: (value) => value,
    minimumSingleViewScope: ObservationVisibilityScope.complete,
    absenceCanBeObserved: false,
  );
}
