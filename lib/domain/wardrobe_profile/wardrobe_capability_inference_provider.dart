import 'wardrobe_profile_contract.dart';

/// Produces conservative capability evidence from item-specific observations.
///
/// Direct product, label, user, and KB evidence remains outside this provider
/// and is passed alongside its output to [WardrobeProfileResolver].
final class WardrobeCapabilityInferenceProvider {
  const WardrobeCapabilityInferenceProvider();

  List<ProfileEvidence> infer({
    required String inferenceId,
    required Iterable<ProfileEvidence> evidence,
    required DateTime createdAt,
    String modelVersion = 'capability-inference-v1',
  }) {
    final observations = _ObservationIndex(evidence);
    final output = <ProfileEvidence>[];

    for (final target in _targets) {
      if (target.footwearOnly &&
          observations.isExplicitlyNotApplicable(
            WardrobeProfileProperty.footwearConstruction,
          )) {
        output.add(
          _buildEvidence(
            inferenceId: inferenceId,
            target: target.property,
            value: null,
            valueState: EvidenceValueState.notApplicable,
            confidence: 1,
            reason: '${target.reasonPrefix}.explicit_non_footwear',
            sourceReferences: observations.sourceReferencesFor(const [
              WardrobeProfileProperty.footwearConstruction,
            ]),
            createdAt: createdAt,
            modelVersion: modelVersion,
          ),
        );
        continue;
      }

      for (final rule in target.rules) {
        final match = rule.match(observations);
        if (match == null) continue;
        output.add(
          _buildEvidence(
            inferenceId: inferenceId,
            target: target.property,
            value: rule.value,
            valueState: EvidenceValueState.known,
            confidence: match.confidence,
            reason: rule.reason,
            sourceReferences: match.sourceReferences,
            createdAt: createdAt,
            modelVersion: modelVersion,
          ),
        );
        break;
      }
    }

    output.sort((left, right) => left.property.compareTo(right.property));
    return List<ProfileEvidence>.unmodifiable(output);
  }

  ProfileEvidence _buildEvidence({
    required String inferenceId,
    required String target,
    required Object? value,
    required EvidenceValueState valueState,
    required double confidence,
    required String reason,
    required List<String> sourceReferences,
    required DateTime createdAt,
    required String modelVersion,
  }) => ProfileEvidence(
    id: 'capability:${Uri.encodeComponent(inferenceId)}:$target',
    property: target,
    value: value,
    valueState: valueState,
    source: EvidenceSource.aiInference,
    nature: EvidenceNature.inferred,
    confidence: confidence,
    method: 'capability_inference:$reason',
    createdAt: createdAt,
    modelVersion: modelVersion,
    sourceReference: sourceReferences.isEmpty
        ? null
        : sourceReferences.join('|'),
  );

  static final List<_CapabilityTarget> _targets = [
    _CapabilityTarget(
      property: WardrobeProfileProperty.warmth,
      reasonPrefix: 'warmth',
      rules: [
        _InferenceRule(
          reason: 'warmth.bulk_and_insulating_surface',
          value: 7,
          maxConfidence: 0.68,
          conditions: [
            _condition(WardrobeProfileProperty.visibleBulk, const ['high']),
            _condition(WardrobeProfileProperty.surfaceAppearance, const [
              'fleece_like',
              'quilted',
            ]),
          ],
        ),
        _InferenceRule(
          reason: 'warmth.bulk_and_full_coverage',
          value: 6,
          maxConfidence: 0.58,
          conditions: [
            _condition(WardrobeProfileProperty.visibleBulk, const ['high']),
            _condition(WardrobeProfileProperty.coverage, const ['full']),
          ],
        ),
        _InferenceRule(
          reason: 'warmth.ankle_upper_and_bulk',
          value: 6,
          maxConfidence: 0.52,
          conditions: [
            _condition(WardrobeProfileProperty.footwearUpperHeight, const [
              'ankle',
              'high_shaft',
            ]),
            _condition(WardrobeProfileProperty.visibleBulk, const ['high']),
          ],
        ),
        _InferenceRule(
          reason: 'warmth.low_bulk_mesh',
          value: 2,
          maxConfidence: 0.62,
          conditions: [
            _condition(WardrobeProfileProperty.visibleBulk, const ['low']),
            _condition(WardrobeProfileProperty.surfaceAppearance, const [
              'mesh',
            ]),
          ],
        ),
        _InferenceRule(
          reason: 'warmth.low_bulk_full_coverage',
          value: 3,
          maxConfidence: 0.48,
          conditions: [
            _condition(WardrobeProfileProperty.visibleBulk, const ['low']),
            _condition(WardrobeProfileProperty.coverage, const ['full']),
          ],
        ),
      ],
    ),
    _CapabilityTarget(
      property: WardrobeProfileProperty.breathability,
      reasonPrefix: 'breathability',
      rules: [
        _InferenceRule(
          reason: 'breathability.mesh_and_low_bulk',
          value: CapabilityLevel.high.wireName,
          maxConfidence: 0.62,
          conditions: [
            _condition(WardrobeProfileProperty.surfaceAppearance, const [
              'mesh',
            ]),
            _condition(WardrobeProfileProperty.visibleBulk, const ['low']),
          ],
        ),
        _InferenceRule(
          reason: 'breathability.mesh_and_open_construction',
          value: CapabilityLevel.high.wireName,
          maxConfidence: 0.58,
          conditions: [
            _condition(WardrobeProfileProperty.surfaceAppearance, const [
              'mesh',
            ]),
            _condition(WardrobeProfileProperty.footwearConstruction, const [
              'open',
              'partially_open',
            ]),
          ],
        ),
      ],
    ),
    _CapabilityTarget(
      property: WardrobeProfileProperty.mobility,
      reasonPrefix: 'mobility',
      rules: [
        _InferenceRule(
          reason: 'mobility.stretch_and_sporty_construction',
          value: CapabilityLevel.high.wireName,
          maxConfidence: 0.7,
          conditions: [
            _condition(WardrobeProfileProperty.visibleStretchCue, const [true]),
            _condition(WardrobeProfileProperty.sportyCues, const ['high']),
          ],
        ),
        _InferenceRule(
          reason: 'mobility.visible_stretch',
          value: CapabilityLevel.medium.wireName,
          maxConfidence: 0.55,
          conditions: [
            _condition(WardrobeProfileProperty.visibleStretchCue, const [true]),
          ],
        ),
      ],
    ),
    // No image-only wind/rain targets in capability-inference-v1. Appearance
    // cannot establish membrane, coating, seam sealing, or permeability.
    _CapabilityTarget(
      property: WardrobeProfileProperty.formality,
      reasonPrefix: 'formality',
      rules: [
        _InferenceRule(
          reason: 'formality.formal_over_sporty_cues',
          value: 8,
          maxConfidence: 0.75,
          conditions: [
            _condition(WardrobeProfileProperty.formalCues, const ['high']),
            _condition(WardrobeProfileProperty.sportyCues, const ['low']),
          ],
        ),
        _InferenceRule(
          reason: 'formality.strong_formal_cues',
          value: 7,
          maxConfidence: 0.65,
          conditions: [
            _condition(WardrobeProfileProperty.formalCues, const ['high']),
          ],
        ),
        _InferenceRule(
          reason: 'formality.strong_sporty_cues',
          value: 3,
          maxConfidence: 0.62,
          conditions: [
            _condition(WardrobeProfileProperty.sportyCues, const ['high']),
            _condition(WardrobeProfileProperty.formalCues, const ['low']),
          ],
        ),
      ],
    ),
    _CapabilityTarget(
      property: WardrobeProfileProperty.supportedLayerRoles,
      reasonPrefix: 'supported_layer_roles',
      rules: [
        _InferenceRule(
          reason: 'supported_layer_roles.hooded_zip_layer',
          value: const ['mid_layer', 'outer_layer'],
          maxConfidence: 0.58,
          conditions: [
            _condition(WardrobeProfileProperty.hasHood, const [true]),
            _condition(WardrobeProfileProperty.frontClosure, const [
              'full_zip',
            ]),
            _condition(WardrobeProfileProperty.visibleBulk, const [
              'medium',
              'high',
            ]),
          ],
        ),
        _InferenceRule(
          reason: 'supported_layer_roles.knit_pullover',
          value: const ['base_layer', 'mid_layer'],
          maxConfidence: 0.52,
          conditions: [
            _condition(WardrobeProfileProperty.surfaceAppearance, const [
              'knit',
            ]),
            _condition(WardrobeProfileProperty.frontClosure, const ['none']),
            _condition(WardrobeProfileProperty.visibleBulk, const [
              'medium',
              'high',
            ]),
          ],
        ),
      ],
    ),
    _CapabilityTarget(
      property: WardrobeProfileProperty.walkingComfort,
      reasonPrefix: 'walking_comfort',
      footwearOnly: true,
      rules: [
        _InferenceRule(
          reason: 'walking_comfort.sporty_low_cut_supported_sole',
          value: CapabilityLevel.medium.wireName,
          maxConfidence: 0.5,
          conditions: [
            _condition(WardrobeProfileProperty.footwearConstruction, const [
              'closed',
            ]),
            _condition(WardrobeProfileProperty.footwearUpperHeight, const [
              'low_cut',
            ]),
            _condition(WardrobeProfileProperty.soleProfile, const [
              'standard',
              'chunky',
            ]),
            _condition(WardrobeProfileProperty.sportyCues, const ['high']),
          ],
        ),
      ],
    ),
    _CapabilityTarget(
      property: WardrobeProfileProperty.traction,
      reasonPrefix: 'traction',
      footwearOnly: true,
      rules: [
        _InferenceRule(
          reason: 'traction.pronounced_visible_tread',
          value: CapabilityLevel.high.wireName,
          maxConfidence: 0.7,
          conditions: [
            _condition(WardrobeProfileProperty.visibleTread, const [
              'pronounced',
            ]),
          ],
        ),
        _InferenceRule(
          reason: 'traction.low_visible_tread',
          value: CapabilityLevel.low.wireName,
          maxConfidence: 0.65,
          conditions: [
            _condition(WardrobeProfileProperty.visibleTread, const ['low']),
          ],
        ),
      ],
    ),
  ];

  static _ObservationCondition _condition(
    String property,
    Iterable<Object> accepted,
  ) => _ObservationCondition(property: property, acceptedValues: accepted);
}

final class _CapabilityTarget {
  const _CapabilityTarget({
    required this.property,
    required this.reasonPrefix,
    required this.rules,
    this.footwearOnly = false,
  });

  final String property;
  final String reasonPrefix;
  final List<_InferenceRule> rules;
  final bool footwearOnly;
}

final class _InferenceRule {
  const _InferenceRule({
    required this.reason,
    required this.value,
    required this.maxConfidence,
    required this.conditions,
  });

  final String reason;
  final Object value;
  final double maxConfidence;
  final List<_ObservationCondition> conditions;

  _RuleMatch? match(_ObservationIndex observations) {
    final matched = <_AggregatedObservation>[];
    for (final condition in conditions) {
      final observation = observations.valueFor(condition.property);
      if (observation == null ||
          observation.hasConflict ||
          !condition.acceptedValues.contains(observation.value)) {
        return null;
      }
      matched.add(observation);
    }

    final averageConfidence =
        matched.fold<double>(0, (sum, item) => sum + item.confidence) /
        matched.length;
    final agreementBonus = matched.fold<int>(
      0,
      (sum, item) => sum + (item.supportingEvidenceCount - 1),
    );
    final supportFactor =
        (0.82 + conditions.length * 0.04 + agreementBonus.clamp(0, 2) * 0.03)
            .clamp(0, 1);
    final confidence = (averageConfidence * supportFactor).clamp(
      0,
      maxConfidence,
    );
    final references =
        matched.expand((item) => item.sourceReferences).toSet().toList()
          ..sort();
    return _RuleMatch(
      confidence: double.parse(confidence.toStringAsFixed(4)),
      sourceReferences: references,
    );
  }
}

final class _ObservationCondition {
  const _ObservationCondition({
    required this.property,
    required this.acceptedValues,
  });

  final String property;
  final Iterable<Object> acceptedValues;
}

final class _RuleMatch {
  const _RuleMatch({required this.confidence, required this.sourceReferences});

  final double confidence;
  final List<String> sourceReferences;
}

final class _ObservationIndex {
  _ObservationIndex(Iterable<ProfileEvidence> evidence) {
    final byProperty = <String, List<ProfileEvidence>>{};
    for (final item in evidence) {
      if (!item.active ||
          item.source != EvidenceSource.visualObservation ||
          !(item.property == WardrobeProfileProperty.coverage ||
              item.property.startsWith('visual.observations.'))) {
        continue;
      }
      byProperty.putIfAbsent(item.property, () => []).add(item);
    }
    for (final entry in byProperty.entries) {
      _raw[entry.key] = List<ProfileEvidence>.unmodifiable(entry.value);
      _values[entry.key] = _aggregate(entry.value);
      if (entry.value.any(
        (item) => item.valueState == EvidenceValueState.notApplicable,
      )) {
        _notApplicable.add(entry.key);
      }
    }
  }

  final Map<String, _AggregatedObservation?> _values = {};
  final Map<String, List<ProfileEvidence>> _raw = {};
  final Set<String> _notApplicable = {};

  _AggregatedObservation? valueFor(String property) => _values[property];

  bool isExplicitlyNotApplicable(String property) =>
      _notApplicable.contains(property) && _values[property] == null;

  List<String> sourceReferencesFor(List<String> properties) {
    final references = <String>{};
    for (final property in properties) {
      for (final item in _rawKnownOrState(property)) {
        final reference = item.sourceReference;
        if (reference != null && reference.isNotEmpty) {
          references.add(reference);
        }
      }
    }
    return references.toList()..sort();
  }

  Iterable<ProfileEvidence> _rawKnownOrState(String property) =>
      _raw[property] ?? const <ProfileEvidence>[];

  _AggregatedObservation? _aggregate(List<ProfileEvidence> evidence) {
    final known = evidence
        .where((item) => item.valueState == EvidenceValueState.known)
        .toList();
    if (known.isEmpty) return null;

    final byValue = <String, List<ProfileEvidence>>{};
    for (final item in known) {
      byValue.putIfAbsent(_valueKey(item.value), () => []).add(item);
    }
    if (byValue.length > 1) {
      return const _AggregatedObservation.conflict();
    }

    final agreeing = byValue.values.single;
    final averageConfidence =
        agreeing.fold<double>(0, (sum, item) => sum + item.confidence) /
        agreeing.length;
    final references =
        agreeing
            .map((item) => item.sourceReference)
            .whereType<String>()
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return _AggregatedObservation(
      value: agreeing.first.value!,
      confidence: averageConfidence,
      supportingEvidenceCount: agreeing.length,
      sourceReferences: references,
    );
  }

  static String _valueKey(Object? value) => value is String
      ? value.trim().toLowerCase()
      : '${value.runtimeType}:$value';
}

final class _AggregatedObservation {
  const _AggregatedObservation({
    required this.value,
    required this.confidence,
    required this.supportingEvidenceCount,
    required this.sourceReferences,
  }) : hasConflict = false;

  const _AggregatedObservation.conflict()
    : value = null,
      confidence = 0,
      supportingEvidenceCount = 0,
      sourceReferences = const [],
      hasConflict = true;

  final Object? value;
  final double confidence;
  final int supportingEvidenceCount;
  final List<String> sourceReferences;
  final bool hasConflict;
}
