import '../../data/clothing_knowledge_base.dart';
import 'wardrobe_profile_contract.dart';

enum CanonicalCompatibilityLevel {
  strong,
  compatible,
  uncertain,
  conflicting;

  String get wireName => name;
}

enum CandidateGap {
  unavailable,
  none,
  small,
  large;

  String get wireName => name;
}

enum SignatureCueStrength {
  supporting(1),
  strong(2);

  const SignatureCueStrength(this.weight);
  final int weight;
}

class CanonicalObservationCue {
  const CanonicalObservationCue({
    required this.property,
    required this.compatibleValues,
    required this.incompatibleValues,
    required this.strength,
    required this.neededEvidence,
  });

  final String property;
  final Set<Object> compatibleValues;
  final Set<Object> incompatibleValues;
  final SignatureCueStrength strength;

  /// Stable machine-readable request, not user-facing copy.
  final String neededEvidence;
}

class CanonicalObservationSignature {
  const CanonicalObservationSignature({
    required this.canonicalTypes,
    required this.cues,
    this.minimumDefiningSupports = 0,
  });

  final Set<String> canonicalTypes;
  final List<CanonicalObservationCue> cues;
  final int minimumDefiningSupports;
}

class CanonicalCompatibilityResult {
  const CanonicalCompatibilityResult({
    required this.identityEvidenceId,
    required this.candidateCanonicalType,
    required this.identitySource,
    required this.identityConfidence,
    required this.compatibilityLevel,
    required this.score,
    required this.supportingEvidence,
    required this.definingEvidence,
    required this.supportingOnlyEvidence,
    required this.conflictingEvidence,
    required this.missingExpectedEvidence,
    required this.missingDefiningEvidence,
    required this.reasonCodes,
    required this.neededEvidence,
  });

  final String identityEvidenceId;
  final String candidateCanonicalType;
  final EvidenceSource identitySource;
  final double identityConfidence;
  final CanonicalCompatibilityLevel compatibilityLevel;
  final int score;
  final List<String> supportingEvidence;
  final List<String> definingEvidence;
  final List<String> supportingOnlyEvidence;
  final List<String> conflictingEvidence;
  final List<String> missingExpectedEvidence;
  final List<String> missingDefiningEvidence;
  final List<String> reasonCodes;
  final List<String> neededEvidence;

  bool get hasConflict =>
      compatibilityLevel == CanonicalCompatibilityLevel.conflicting;

  Map<String, Object?> toMap() => <String, Object?>{
    'identityEvidenceId': identityEvidenceId,
    'candidateCanonicalType': candidateCanonicalType,
    'identitySource': identitySource.wireName,
    'identityConfidence': identityConfidence,
    'compatibilityLevel': compatibilityLevel.wireName,
    'score': score,
    'supportingEvidence': supportingEvidence,
    'definingEvidence': definingEvidence,
    'supportingOnlyEvidence': supportingOnlyEvidence,
    'conflictingEvidence': conflictingEvidence,
    'missingExpectedEvidence': missingExpectedEvidence,
    'missingDefiningEvidence': missingDefiningEvidence,
    'reasonCodes': reasonCodes,
    'neededEvidence': neededEvidence,
  };
}

class CanonicalConsistencyReport {
  const CanonicalConsistencyReport({
    required this.results,
    required this.identityConflict,
    required this.candidateGap,
    required this.competingCanonicalTypes,
    required this.decisionRelevantDifferences,
    required this.neededEvidence,
  });

  final List<CanonicalCompatibilityResult> results;
  final bool identityConflict;
  final CandidateGap candidateGap;
  final List<String> competingCanonicalTypes;
  final List<String> decisionRelevantDifferences;
  final List<String> neededEvidence;

  Map<String, Object?> toMap() => <String, Object?>{
    'results': results.map((item) => item.toMap()).toList(),
    'identityConflict': identityConflict,
    'candidateGap': candidateGap.wireName,
    'competingCanonicalTypes': competingCanonicalTypes,
    'decisionRelevantDifferences': decisionRelevantDifferences,
    'neededEvidence': neededEvidence,
  };
}

/// Audits identity candidates against observations without choosing identity.
final class CanonicalObservationConsistencyValidator {
  const CanonicalObservationConsistencyValidator();

  CanonicalConsistencyReport validate({
    required Iterable<ProfileEvidence> identityEvidence,
    required Iterable<ProfileEvidence> observationEvidence,
  }) {
    final observations = _ObservationIndex(observationEvidence);
    final candidates =
        identityEvidence
            .where(
              (item) =>
                  item.active &&
                  item.property == WardrobeProfileProperty.canonicalType &&
                  item.valueState == EvidenceValueState.known &&
                  item.value is String &&
                  (item.value as String).trim().isNotEmpty,
            )
            .toList()
          ..sort(_compareIdentityEvidence);

    final results = candidates
        .map((candidate) => _validateCandidate(candidate, observations))
        .toList(growable: false);
    final canonicalTypes =
        results.map((item) => item.candidateCanonicalType).toSet().toList()
          ..sort();
    final neededEvidence =
        results.expand((item) => item.neededEvidence).toSet().toList()..sort();

    return CanonicalConsistencyReport(
      results: List<CanonicalCompatibilityResult>.unmodifiable(results),
      identityConflict:
          results.any((item) => item.hasConflict) ||
          _hasCompetingIdentityConflict(results),
      candidateGap: _candidateGap(results),
      competingCanonicalTypes: List<String>.unmodifiable(canonicalTypes),
      decisionRelevantDifferences: List<String>.unmodifiable(
        _decisionRelevantDifferences(results),
      ),
      neededEvidence: List<String>.unmodifiable(neededEvidence),
    );
  }

  CanonicalCompatibilityResult _validateCandidate(
    ProfileEvidence identity,
    _ObservationIndex observations,
  ) {
    final canonical = (identity.value as String).trim().toLowerCase();
    final signature = _registry[canonical];
    if (signature == null ||
        ClothingKnowledgeBase.findByCanonicalType(canonical) == null) {
      return CanonicalCompatibilityResult(
        identityEvidenceId: identity.id,
        candidateCanonicalType: canonical,
        identitySource: identity.source,
        identityConfidence: identity.confidence,
        compatibilityLevel: CanonicalCompatibilityLevel.uncertain,
        score: 0,
        supportingEvidence: const [],
        definingEvidence: const [],
        supportingOnlyEvidence: const [],
        conflictingEvidence: const [],
        missingExpectedEvidence: const ['signature.unavailable'],
        missingDefiningEvidence: const ['signature.unavailable'],
        reasonCodes: const [
          'signature_not_covered',
          'missing_signature_coverage',
        ],
        neededEvidence: const ['supported_signature_or_verified_model'],
      );
    }

    var supportScore = 0;
    var conflictScore = 0;
    var hasStrongConflict = false;
    var hasObservationConflict = false;
    final supporting = <String>[];
    final defining = <String>[];
    final supportingOnly = <String>[];
    final conflicting = <String>[];
    final missing = <String>[];
    final missingDefining = <String>[];
    final reasons = <String>[];
    final needed = <String>[];

    for (final cue in signature.cues) {
      final fact = observations.factFor(cue.property);
      if (fact == null || fact.state == _ObservationFactState.missing) {
        missing.add(cue.property);
        if (cue.strength == SignatureCueStrength.strong) {
          missingDefining.add(cue.property);
        }
        needed.add(cue.neededEvidence);
        reasons.add('missing:${cue.property}');
        continue;
      }
      if (fact.state == _ObservationFactState.conflicting) {
        hasObservationConflict = true;
        conflicting.add(cue.property);
        if (cue.strength == SignatureCueStrength.strong) {
          missingDefining.add(cue.property);
        }
        needed.add(cue.neededEvidence);
        reasons.add('observation_conflict:${cue.property}');
        continue;
      }
      if (fact.state == _ObservationFactState.notApplicable) {
        missing.add(cue.property);
        if (cue.strength == SignatureCueStrength.strong) {
          missingDefining.add(cue.property);
        }
        reasons.add('not_applicable:${cue.property}');
        continue;
      }

      final value = fact.value;
      if (cue.compatibleValues.contains(value)) {
        supportScore += cue.strength.weight;
        supporting.add(cue.property);
        if (cue.strength == SignatureCueStrength.strong) {
          defining.add(cue.property);
        } else {
          supportingOnly.add(cue.property);
        }
        reasons.add('supports:${cue.property}=${_valueKey(value)}');
      } else if (cue.incompatibleValues.contains(value)) {
        conflictScore += cue.strength.weight;
        hasStrongConflict |= cue.strength == SignatureCueStrength.strong;
        conflicting.add(cue.property);
        if (cue.strength == SignatureCueStrength.strong) {
          missingDefining.add(cue.property);
        }
        needed.add(cue.neededEvidence);
        reasons.add('conflicts:${cue.property}=${_valueKey(value)}');
      }
    }

    final score = supportScore - conflictScore;
    final level = switch ((
      hasStrongConflict,
      conflictScore,
      hasObservationConflict,
      supportScore,
    )) {
      (true, _, _, _) ||
      (_, >= 2, _, _) => CanonicalCompatibilityLevel.conflicting,
      (_, _, true, _) => CanonicalCompatibilityLevel.uncertain,
      (_, _, _, >= 4) => CanonicalCompatibilityLevel.strong,
      (_, _, _, >= 1) => CanonicalCompatibilityLevel.compatible,
      _ => CanonicalCompatibilityLevel.uncertain,
    };

    supporting.sort();
    defining.sort();
    supportingOnly.sort();
    conflicting.sort();
    missing.sort();
    missingDefining.sort();
    reasons.sort();
    needed.sort();
    return CanonicalCompatibilityResult(
      identityEvidenceId: identity.id,
      candidateCanonicalType: canonical,
      identitySource: identity.source,
      identityConfidence: identity.confidence,
      compatibilityLevel: level,
      score: score,
      supportingEvidence: List<String>.unmodifiable(supporting),
      definingEvidence: List<String>.unmodifiable(defining),
      supportingOnlyEvidence: List<String>.unmodifiable(supportingOnly),
      conflictingEvidence: List<String>.unmodifiable(conflicting),
      missingExpectedEvidence: List<String>.unmodifiable(missing),
      missingDefiningEvidence: List<String>.unmodifiable(missingDefining),
      reasonCodes: List<String>.unmodifiable(reasons),
      neededEvidence: List<String>.unmodifiable(needed.toSet()),
    );
  }

  static bool _hasCompetingIdentityConflict(
    List<CanonicalCompatibilityResult> results,
  ) {
    final distinct = results.map((item) => item.candidateCanonicalType).toSet();
    if (distinct.length < 2) return false;
    return results.any(
      (item) =>
          item.compatibilityLevel == CanonicalCompatibilityLevel.strong ||
          item.compatibilityLevel == CanonicalCompatibilityLevel.compatible,
    );
  }

  static CandidateGap _candidateGap(
    List<CanonicalCompatibilityResult> results,
  ) {
    if (results.length < 2) return CandidateGap.unavailable;
    final scores = results.map((item) => item.score).toList()
      ..sort((left, right) => right.compareTo(left));
    final difference = scores[0] - scores[1];
    if (difference == 0) return CandidateGap.none;
    return difference >= 3 ? CandidateGap.large : CandidateGap.small;
  }

  static List<String> _decisionRelevantDifferences(
    List<CanonicalCompatibilityResult> results,
  ) {
    if (results.length < 2) return const [];
    final properties = <String>{};
    for (final result in results) {
      properties.addAll(result.supportingEvidence);
      properties.addAll(result.conflictingEvidence);
    }
    return properties.toList()..sort();
  }

  static int _compareIdentityEvidence(
    ProfileEvidence left,
    ProfileEvidence right,
  ) {
    final canonical = (left.value as String).toLowerCase().compareTo(
      (right.value as String).toLowerCase(),
    );
    return canonical != 0 ? canonical : left.id.compareTo(right.id);
  }

  static String _valueKey(Object? value) =>
      value is String ? value : value.toString();

  int minimumDefiningSupportsFor(String canonicalType) {
    final signature = _registry[canonicalType.trim().toLowerCase()];
    if (signature == null) return 0;
    if (signature.minimumDefiningSupports > 0) {
      return signature.minimumDefiningSupports;
    }
    return signature.cues.any(
          (cue) => cue.strength == SignatureCueStrength.strong,
        )
        ? 1
        : 0;
  }

  static final Map<String, CanonicalObservationSignature> _registry =
      _buildRegistry(_signatures);

  static Map<String, CanonicalObservationSignature> _buildRegistry(
    List<CanonicalObservationSignature> signatures,
  ) {
    final registry = <String, CanonicalObservationSignature>{};
    for (final signature in signatures) {
      for (final canonical in signature.canonicalTypes) {
        assert(
          ClothingKnowledgeBase.findByCanonicalType(canonical) != null,
          'Signature references unknown canonical type: $canonical',
        );
        registry[canonical] = signature;
      }
    }
    return Map<String, CanonicalObservationSignature>.unmodifiable(registry);
  }

  static final List<CanonicalObservationSignature> _signatures = [
    _signature(
      const {'hoodie'},
      [
        _cue(
          WardrobeProfileProperty.hasHood,
          compatible: const {true},
          incompatible: const {false},
          strong: true,
          needed: 'show_hood_area',
        ),
        _cue(
          WardrobeProfileProperty.frontClosure,
          compatible: const {'none', 'partial_zip', 'full_zip'},
          incompatible: const {'buttons', 'snaps'},
          needed: 'show_front_closure',
        ),
        _cue(
          WardrobeProfileProperty.sportyCues,
          compatible: const {'medium', 'high'},
          incompatible: const {},
          needed: 'clear_full_item_image',
        ),
      ],
    ),
    _signature(
      const {'zip_hoodie'},
      [
        _cue(
          WardrobeProfileProperty.hasHood,
          compatible: const {true},
          incompatible: const {false},
          strong: true,
          needed: 'show_hood_area',
        ),
        _cue(
          WardrobeProfileProperty.frontClosure,
          compatible: const {'full_zip'},
          incompatible: const {'none', 'buttons', 'snaps'},
          strong: true,
          needed: 'show_front_closure',
        ),
        _cue(
          WardrobeProfileProperty.sportyCues,
          compatible: const {'medium', 'high'},
          incompatible: const {},
          needed: 'clear_full_item_image',
        ),
      ],
    ),
    _signature(
      const {'sweater', 'knit_sweater'},
      [
        _cue(
          WardrobeProfileProperty.surfaceAppearance,
          compatible: const {'knit'},
          incompatible: const {'smooth', 'mesh', 'leather_like'},
          strong: true,
          needed: 'close_surface_image',
        ),
        _cue(
          WardrobeProfileProperty.hasHood,
          compatible: const {false},
          incompatible: const {true},
          strong: true,
          needed: 'show_hood_area',
        ),
        _cue(
          WardrobeProfileProperty.frontClosure,
          compatible: const {'none'},
          incompatible: const {'full_zip'},
          strong: true,
          needed: 'show_front_closure',
        ),
      ],
    ),
    _signature(
      const {'crewneck_sweatshirt', 'sweatshirt'},
      [
        _cue(
          WardrobeProfileProperty.hasHood,
          compatible: const {false},
          incompatible: const {true},
          strong: true,
          needed: 'show_hood_area',
        ),
        _cue(
          WardrobeProfileProperty.frontClosure,
          compatible: const {'none'},
          incompatible: const {'full_zip', 'buttons'},
          needed: 'show_front_closure',
        ),
        _cue(
          WardrobeProfileProperty.surfaceAppearance,
          compatible: const {'fleece_like', 'smooth', 'textured'},
          incompatible: const {'leather_like'},
          needed: 'close_surface_image',
        ),
      ],
    ),
    _signature(
      const {'softshell', 'light_jacket'},
      [
        _cue(
          WardrobeProfileProperty.frontClosure,
          compatible: const {'full_zip', 'snaps'},
          incompatible: const {'none'},
          needed: 'show_front_closure',
        ),
        _cue(
          WardrobeProfileProperty.visibleBulk,
          compatible: const {'low', 'medium'},
          incompatible: const {'high'},
          strong: true,
          needed: 'full_side_profile_image',
        ),
        _cue(
          WardrobeProfileProperty.surfaceAppearance,
          compatible: const {'smooth', 'woven'},
          incompatible: const {'quilted', 'fleece_like'},
          needed: 'close_surface_image',
        ),
      ],
    ),
    _signature(
      const {'puffer_jacket'},
      [
        _cue(
          WardrobeProfileProperty.visibleBulk,
          compatible: const {'high'},
          incompatible: const {'low'},
          strong: true,
          needed: 'full_side_profile_image',
        ),
        _cue(
          WardrobeProfileProperty.surfaceAppearance,
          compatible: const {'quilted'},
          incompatible: const {'mesh'},
          strong: true,
          needed: 'close_surface_image',
        ),
        _cue(
          WardrobeProfileProperty.coverage,
          compatible: const {'full'},
          incompatible: const {'minimal'},
          needed: 'full_item_image',
        ),
      ],
      minimumDefiningSupports: 2,
    ),
    _signature(
      const {'winter_jacket'},
      [
        _cue(
          WardrobeProfileProperty.visibleBulk,
          compatible: const {'medium', 'high'},
          incompatible: const {'low'},
          strong: true,
          needed: 'full_side_profile_image',
        ),
        _cue(
          WardrobeProfileProperty.surfaceAppearance,
          compatible: const {'quilted', 'smooth', 'woven'},
          incompatible: const {'mesh'},
          needed: 'close_surface_image',
        ),
        _cue(
          WardrobeProfileProperty.coverage,
          compatible: const {'full'},
          incompatible: const {'minimal'},
          needed: 'full_item_image',
        ),
      ],
    ),
    _signature(
      const {'t_shirt'},
      [
        _cue(
          WardrobeProfileProperty.visibleBulk,
          compatible: const {'low'},
          incompatible: const {'high'},
          needed: 'full_side_profile_image',
        ),
        _cue(
          WardrobeProfileProperty.hasHood,
          compatible: const {false},
          incompatible: const {true},
          needed: 'show_hood_area',
        ),
        _cue(
          WardrobeProfileProperty.frontClosure,
          compatible: const {'none'},
          incompatible: const {'full_zip'},
          needed: 'show_front_closure',
        ),
        _cue(
          WardrobeProfileProperty.necklineShape,
          compatible: const {'crew', 'scoop'},
          incompatible: const {'high_neck', 'collared'},
          needed: 'clear_neckline_image',
        ),
      ],
    ),
    _signature(
      const {'v_neck_t_shirt'},
      [
        _cue(
          WardrobeProfileProperty.necklineShape,
          compatible: const {'v_neck'},
          incompatible: const {'crew', 'high_neck', 'collared'},
          strong: true,
          needed: 'clear_neckline_image',
        ),
        _cue(
          WardrobeProfileProperty.visibleBulk,
          compatible: const {'low'},
          incompatible: const {'high'},
          needed: 'full_side_profile_image',
        ),
        _cue(
          WardrobeProfileProperty.frontClosure,
          compatible: const {'none'},
          incompatible: const {'full_zip', 'buttons'},
          needed: 'show_front_closure',
        ),
      ],
      minimumDefiningSupports: 1,
    ),
    _signature(
      const {'tank_top'},
      [
        _cue(
          WardrobeProfileProperty.coverage,
          compatible: const {'minimal'},
          incompatible: const {'full'},
          strong: true,
          needed: 'full_item_image',
        ),
        _cue(
          WardrobeProfileProperty.visibleBulk,
          compatible: const {'low'},
          incompatible: const {'high'},
          needed: 'full_side_profile_image',
        ),
      ],
    ),
    // Taxonomy audit: garment coverage safely identifies the generic shorts
    // family. Pocket/closure details are deliberately not subtype evidence.
    _signature(
      const {'shorts'},
      [
        _cue(
          WardrobeProfileProperty.coverage,
          compatible: const {'minimal', 'partial'},
          incompatible: const {'full'},
          strong: true,
          needed: 'full_garment_shape_image',
        ),
      ],
      minimumDefiningSupports: 1,
    ),
    // Cargo shorts need both short coverage and visible cargo pockets. This
    // prevents a generic short from becoming cargo through style inference.
    _signature(
      const {'cargo_shorts'},
      [
        _cue(
          WardrobeProfileProperty.coverage,
          compatible: const {'minimal', 'partial'},
          incompatible: const {'full'},
          strong: true,
          needed: 'full_garment_shape_image',
        ),
        _cue(
          WardrobeProfileProperty.visiblePocketStructure,
          compatible: const {'cargo'},
          incompatible: const {'none', 'standard'},
          strong: true,
          needed: 'clear_side_pocket_image',
        ),
      ],
      minimumDefiningSupports: 2,
    ),
    _signature(
      const {'jeans', 'slim_jeans', 'straight_jeans', 'skinny_jeans'},
      [
        _cue(
          WardrobeProfileProperty.coverage,
          compatible: const {'full'},
          incompatible: const {'minimal'},
          needed: 'full_item_image',
        ),
        _cue(
          WardrobeProfileProperty.surfaceAppearance,
          compatible: const {'woven', 'textured'},
          incompatible: const {'mesh', 'quilted'},
          needed: 'close_surface_image',
        ),
      ],
    ),
    _signature(
      const {'chinos', 'corduroy_pants'},
      [
        _cue(
          WardrobeProfileProperty.coverage,
          compatible: const {'full'},
          incompatible: const {'minimal'},
          needed: 'full_item_image',
        ),
        _cue(
          WardrobeProfileProperty.formalCues,
          compatible: const {'medium', 'high'},
          incompatible: const {'low'},
          needed: 'clear_full_item_image',
        ),
        _cue(
          WardrobeProfileProperty.sportyCues,
          compatible: const {'low'},
          incompatible: const {'high'},
          needed: 'clear_full_item_image',
        ),
      ],
      minimumDefiningSupports: 1,
    ),
    _signature(
      const {'cargo_pants'},
      [
        _cue(
          WardrobeProfileProperty.visiblePocketStructure,
          compatible: const {'cargo'},
          incompatible: const {'none', 'standard'},
          strong: true,
          needed: 'clear_side_pocket_image',
        ),
        _cue(
          WardrobeProfileProperty.coverage,
          compatible: const {'full'},
          incompatible: const {'minimal'},
          needed: 'full_item_image',
        ),
        _cue(
          WardrobeProfileProperty.sportyCues,
          compatible: const {'medium', 'high'},
          incompatible: const {'low'},
          needed: 'clear_full_item_image',
        ),
        _cue(
          WardrobeProfileProperty.formalCues,
          compatible: const {'low'},
          incompatible: const {'high'},
          needed: 'clear_full_item_image',
        ),
      ],
      minimumDefiningSupports: 1,
    ),
    _signature(
      const {'suit_trousers'},
      [
        _cue(
          WardrobeProfileProperty.coverage,
          compatible: const {'full'},
          incompatible: const {'minimal'},
          needed: 'full_item_image',
        ),
        _cue(
          WardrobeProfileProperty.formalCues,
          compatible: const {'high'},
          incompatible: const {'low'},
          strong: true,
          needed: 'clear_full_item_image',
        ),
        _cue(
          WardrobeProfileProperty.sportyCues,
          compatible: const {'low'},
          incompatible: const {'high'},
          strong: true,
          needed: 'clear_full_item_image',
        ),
      ],
    ),
    _signature(
      const {'sneakers'},
      [
        _cue(
          WardrobeProfileProperty.footwearConstruction,
          compatible: const {'closed'},
          incompatible: const {'open'},
          needed: 'full_footwear_image',
        ),
        _cue(
          WardrobeProfileProperty.footwearUpperHeight,
          compatible: const {'low_cut'},
          incompatible: const {'high_shaft'},
          needed: 'side_footwear_image',
        ),
      ],
    ),
    _signature(
      const {'running_shoes'},
      [
        _cue(
          WardrobeProfileProperty.footwearUpperHeight,
          compatible: const {'low_cut'},
          incompatible: const {'high_shaft'},
          needed: 'side_footwear_image',
        ),
        _cue(
          WardrobeProfileProperty.sportyCues,
          compatible: const {'high'},
          incompatible: const {'low'},
          needed: 'clear_full_footwear_image',
        ),
        _cue(
          WardrobeProfileProperty.surfaceAppearance,
          compatible: const {'mesh'},
          incompatible: const {'leather_like'},
          strong: true,
          needed: 'clear_footwear_upper_image',
        ),
        _cue(
          WardrobeProfileProperty.soleProfile,
          compatible: const {'standard', 'chunky'},
          incompatible: const {'thin'},
          strong: true,
          needed: 'clear_side_sole_image',
        ),
        _cue(
          WardrobeProfileProperty.footwearConstruction,
          compatible: const {'closed'},
          incompatible: const {'open'},
          needed: 'full_footwear_image',
        ),
      ],
      minimumDefiningSupports: 2,
    ),
    _signature(
      const {'hiking_shoes'},
      [
        _cue(
          WardrobeProfileProperty.visibleTread,
          compatible: const {'pronounced'},
          incompatible: const {'low'},
          strong: true,
          needed: 'sole_photo',
        ),
        _cue(
          WardrobeProfileProperty.sportyCues,
          compatible: const {'high'},
          incompatible: const {'low'},
          strong: true,
          needed: 'clear_full_footwear_image',
        ),
        _cue(
          WardrobeProfileProperty.footwearConstruction,
          compatible: const {'closed'},
          incompatible: const {'open'},
          needed: 'full_footwear_image',
        ),
      ],
    ),
    _signature(
      const {'boots'},
      [
        _cue(
          WardrobeProfileProperty.footwearUpperHeight,
          compatible: const {'ankle'},
          incompatible: const {'low_cut'},
          strong: true,
          needed: 'side_footwear_image',
        ),
        _cue(
          WardrobeProfileProperty.visibleTread,
          compatible: const {'low', 'moderate'},
          incompatible: const {'pronounced'},
          needed: 'sole_photo',
        ),
        _cue(
          WardrobeProfileProperty.formalCues,
          compatible: const {'medium', 'high'},
          incompatible: const {'low'},
          needed: 'clear_full_footwear_image',
        ),
      ],
    ),
    _signature(
      const {'chelsea_boots'},
      [
        _cue(
          WardrobeProfileProperty.footwearUpperHeight,
          compatible: const {'ankle'},
          incompatible: const {'low_cut', 'high_shaft'},
          strong: true,
          needed: 'side_footwear_image',
        ),
        _cue(
          WardrobeProfileProperty.footwearFastening,
          compatible: const {'elastic_side_panels'},
          incompatible: const {'laces', 'straps'},
          strong: true,
          needed: 'clear_side_footwear_image',
        ),
        _cue(
          WardrobeProfileProperty.formalCues,
          compatible: const {'medium', 'high'},
          incompatible: const {'low'},
          needed: 'clear_full_footwear_image',
        ),
      ],
      minimumDefiningSupports: 2,
    ),
    _signature(
      const {'winter_boots'},
      [
        _cue(
          WardrobeProfileProperty.footwearUpperHeight,
          compatible: const {'ankle', 'high_shaft'},
          incompatible: const {'low_cut'},
          strong: true,
          needed: 'side_footwear_image',
        ),
        _cue(
          WardrobeProfileProperty.visibleBulk,
          compatible: const {'high'},
          incompatible: const {'low'},
          strong: true,
          needed: 'full_side_profile_image',
        ),
      ],
    ),
  ];

  static CanonicalObservationSignature _signature(
    Set<String> types,
    List<CanonicalObservationCue> cues, {
    int minimumDefiningSupports = 0,
  }) => CanonicalObservationSignature(
    canonicalTypes: types,
    cues: cues,
    minimumDefiningSupports: minimumDefiningSupports,
  );

  static CanonicalObservationCue _cue(
    String property, {
    required Set<Object> compatible,
    required Set<Object> incompatible,
    required String needed,
    bool strong = false,
  }) => CanonicalObservationCue(
    property: property,
    compatibleValues: compatible,
    incompatibleValues: incompatible,
    strength: strong
        ? SignatureCueStrength.strong
        : SignatureCueStrength.supporting,
    neededEvidence: needed,
  );
}

enum _ObservationFactState { known, missing, conflicting, notApplicable }

class _ObservationFact {
  const _ObservationFact.known(this.value)
    : state = _ObservationFactState.known;

  const _ObservationFact.missing()
    : state = _ObservationFactState.missing,
      value = null;

  const _ObservationFact.conflicting()
    : state = _ObservationFactState.conflicting,
      value = null;

  const _ObservationFact.notApplicable()
    : state = _ObservationFactState.notApplicable,
      value = null;

  final _ObservationFactState state;
  final Object? value;
}

class _ObservationIndex {
  _ObservationIndex(Iterable<ProfileEvidence> evidence) {
    final byProperty = <String, List<ProfileEvidence>>{};
    for (final item in evidence) {
      if (!item.active ||
          !_isObservationProperty(item.property) ||
          !_allowedSources.contains(item.source)) {
        continue;
      }
      byProperty.putIfAbsent(item.property, () => []).add(item);
    }
    for (final entry in byProperty.entries) {
      _facts[entry.key] = _aggregate(entry.value);
    }
  }

  final Map<String, _ObservationFact> _facts = {};

  _ObservationFact? factFor(String property) => _facts[property];

  _ObservationFact _aggregate(List<ProfileEvidence> evidence) {
    final known = evidence
        .where((item) => item.valueState == EvidenceValueState.known)
        .toList();
    final values = known.map((item) => _normalizedValue(item.value)).toSet();
    if (values.length > 1) return const _ObservationFact.conflicting();
    if (values.length == 1) return _ObservationFact.known(values.single);
    if (evidence.any(
      (item) => item.valueState == EvidenceValueState.notApplicable,
    )) {
      return const _ObservationFact.notApplicable();
    }
    return const _ObservationFact.missing();
  }

  static Object? _normalizedValue(Object? value) =>
      value is String ? value.trim().toLowerCase() : value;

  static bool _isObservationProperty(String property) =>
      property == WardrobeProfileProperty.coverage ||
      property.startsWith('visual.observations.');

  static const Set<EvidenceSource> _allowedSources = {
    EvidenceSource.userCorrection,
    EvidenceSource.verifiedProductMetadata,
    EvidenceSource.labelMetadata,
    EvidenceSource.visualObservation,
  };
}
