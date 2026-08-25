import 'wardrobe_profile_contract.dart';

/// Deterministically resolves wardrobe evidence into the M11.0 runtime profile.
///
/// The resolver is intentionally independent of Firestore, UI, the clothing
/// knowledge base, and outfit selection. Future evidence providers should add
/// assertions before calling [resolve]; they must not override resolved fields.
final class WardrobeProfileResolver {
  const WardrobeProfileResolver();

  ResolvedWardrobeItemProfile resolve({
    required String itemId,
    required Iterable<ProfileEvidence> evidence,
  }) {
    final usableEvidence = _sanitizeEvidence(evidence);
    final canonicalType = _resolve<String>(
      WardrobeProfileProperty.canonicalType,
      usableEvidence,
    );
    final canonicalValue = canonicalType.isKnown ? canonicalType.value : null;

    ResolvedField<T> field<T>(String property) => _resolve<T>(
      property,
      usableEvidence,
      resolvedCanonicalType: canonicalValue,
    );

    return ResolvedWardrobeItemProfile(
      itemId: itemId,
      identity: WardrobeItemIdentity(
        displayName: field<String>(WardrobeProfileProperty.displayName),
        canonicalType: canonicalType,
        primaryType: field<String>(WardrobeProfileProperty.primaryType),
        secondaryType: field<String>(WardrobeProfileProperty.secondaryType),
        mainCategory: field<String>(WardrobeProfileProperty.mainCategory),
        category: field<String>(WardrobeProfileProperty.category),
        subcategory: field<String>(WardrobeProfileProperty.subcategory),
        brand: field<String>(WardrobeProfileProperty.brand),
      ),
      visual: WardrobeItemVisualProfile(
        colors: field<List<String>>(WardrobeProfileProperty.colors),
        baseColors: field<List<String>>(WardrobeProfileProperty.baseColors),
        patterns: field<List<String>>(WardrobeProfileProperty.patterns),
        styles: field<List<String>>(WardrobeProfileProperty.styles),
        fit: field<String>(WardrobeProfileProperty.fit),
        vibe: field<String>(WardrobeProfileProperty.vibe),
        logoProminence: field<String>(WardrobeProfileProperty.logoProminence),
        visualIdentity: field<String>(WardrobeProfileProperty.visualIdentity),
        visualDescription: field<String>(
          WardrobeProfileProperty.visualDescription,
        ),
        materialFeel: field<String>(WardrobeProfileProperty.materialFeel),
        coverage: field<GarmentCoverage>(WardrobeProfileProperty.coverage),
        hasHood: field<bool>(WardrobeProfileProperty.hasHood),
        frontClosure: field<FrontClosure>(WardrobeProfileProperty.frontClosure),
        visibleBulk: field<VisualAmount>(WardrobeProfileProperty.visibleBulk),
        surfaceAppearance: field<SurfaceAppearance>(
          WardrobeProfileProperty.surfaceAppearance,
        ),
        necklineShape: field<NecklineShape>(
          WardrobeProfileProperty.necklineShape,
        ),
        visiblePocketStructure: field<VisiblePocketStructure>(
          WardrobeProfileProperty.visiblePocketStructure,
        ),
        visibleStretchCue: field<bool>(
          WardrobeProfileProperty.visibleStretchCue,
        ),
        sportyCues: field<VisualAmount>(WardrobeProfileProperty.sportyCues),
        formalCues: field<VisualAmount>(WardrobeProfileProperty.formalCues),
        footwearConstruction: field<FootwearConstruction>(
          WardrobeProfileProperty.footwearConstruction,
        ),
        footwearFastening: field<FootwearFastening>(
          WardrobeProfileProperty.footwearFastening,
        ),
        soleProfile: field<SoleProfile>(WardrobeProfileProperty.soleProfile),
        visibleTread: field<VisibleTread>(WardrobeProfileProperty.visibleTread),
        footwearUpperHeight: field<FootwearUpperHeight>(
          WardrobeProfileProperty.footwearUpperHeight,
        ),
      ),
      capabilities: WardrobeItemCapabilities(
        warmth: field<int>(WardrobeProfileProperty.warmth),
        formality: field<int>(WardrobeProfileProperty.formality),
        layerRole: field<WardrobeLayerRole>(WardrobeProfileProperty.layerRole),
        supportedLayerRoles: field<Set<WardrobeLayerRole>>(
          WardrobeProfileProperty.supportedLayerRoles,
        ),
        mobility: field<CapabilityLevel>(WardrobeProfileProperty.mobility),
        breathability: field<CapabilityLevel>(
          WardrobeProfileProperty.breathability,
        ),
        windProtection: field<CapabilityLevel>(
          WardrobeProfileProperty.windProtection,
        ),
        rainProtection: field<CapabilityLevel>(
          WardrobeProfileProperty.rainProtection,
        ),
        walkingComfort: field<CapabilityLevel>(
          WardrobeProfileProperty.walkingComfort,
        ),
        traction: field<CapabilityLevel>(WardrobeProfileProperty.traction),
        rainSuitability: field<RainSuitability>(
          WardrobeProfileProperty.rainSuitability,
        ),
        outdoorSuitability: field<CapabilityLevel>(
          WardrobeProfileProperty.outdoorSuitability,
        ),
      ),
      suitability: WardrobeItemSuitability(
        seasons: field<Set<String>>(WardrobeProfileProperty.seasons),
        occasions: field<Set<String>>(WardrobeProfileProperty.occasions),
        activities: field<Set<String>>(WardrobeProfileProperty.activities),
        terrain: field<Set<String>>(WardrobeProfileProperty.terrain),
      ),
      evidence: usableEvidence,
    );
  }

  List<ProfileEvidence> _sanitizeEvidence(Iterable<ProfileEvidence> evidence) {
    final active = evidence.where((item) => item.active).toList();
    final invalidDuplicateIds = <String>{};
    final firstById = <String, ProfileEvidence>{};

    for (final item in active) {
      final first = firstById[item.id];
      if (first == null) {
        firstById[item.id] = item;
      } else if (!_sameAssertion(first, item)) {
        invalidDuplicateIds.add(item.id);
      }
    }

    final supersededIds = <String>{};
    for (final item in active.where(_isUsableAssertion)) {
      final supersededId = item.supersedesEvidenceId;
      final target = supersededId == null ? null : firstById[supersededId];
      if (target != null && target.property == item.property) {
        supersededIds.add(supersededId!);
      }
    }

    final result =
        active
            .where(
              (item) =>
                  !invalidDuplicateIds.contains(item.id) &&
                  !supersededIds.contains(item.id) &&
                  _isUsableAssertion(item),
            )
            .toList()
          ..sort(_compareEvidenceIdentity);
    return List<ProfileEvidence>.unmodifiable(result);
  }

  bool _isUsableAssertion(ProfileEvidence item) {
    if (item.id.trim().isEmpty ||
        item.property.trim().isEmpty ||
        item.method.trim().isEmpty ||
        !item.confidence.isFinite ||
        item.confidence < 0 ||
        item.confidence > 1 ||
        !_allProperties.contains(item.property)) {
      return false;
    }
    return item.valueState != EvidenceValueState.known ||
        _normalizeUntyped(item.property, item.value) != null;
  }

  bool _sameAssertion(ProfileEvidence left, ProfileEvidence right) =>
      left.property == right.property &&
      _valueKey(left.value) == _valueKey(right.value) &&
      left.valueState == right.valueState &&
      left.source == right.source &&
      left.nature == right.nature &&
      left.confidence == right.confidence &&
      left.verified == right.verified &&
      left.active == right.active &&
      left.method == right.method &&
      left.createdAt.toUtc() == right.createdAt.toUtc() &&
      left.modelVersion == right.modelVersion &&
      left.sourceReference == right.sourceReference &&
      left.supersedesEvidenceId == right.supersedesEvidenceId &&
      left.dependsOnCanonicalType == right.dependsOnCanonicalType;

  ResolvedField<T> _resolve<T>(
    String property,
    List<ProfileEvidence> evidence, {
    String? resolvedCanonicalType,
  }) {
    final policy = _policies[property] ?? _defaultPolicy;
    final candidates = <_Candidate<T>>[];

    for (final item in evidence) {
      if (item.property != property) continue;
      if (_isStaleOrUnsafeDefault(item, property, resolvedCanonicalType)) {
        continue;
      }
      if (item.valueState == EvidenceValueState.unknown ||
          item.valueState == EvidenceValueState.notVisible) {
        continue;
      }
      final normalized = item.valueState == EvidenceValueState.notApplicable
          ? null
          : _normalizeValue<T>(property, item.value);
      if (normalized == null &&
          item.valueState != EvidenceValueState.notApplicable) {
        continue;
      }
      candidates.add(
        _Candidate<T>(
          evidence: item,
          value: normalized,
          valueKey: item.valueState == EvidenceValueState.notApplicable
              ? 'state:not_applicable'
              : _valueKey(normalized),
          authority: policy.authorityFor(item.source),
          quality: _quality(policy, item),
        ),
      );
    }

    if (candidates.isEmpty) return ResolvedField<T>.unknown();
    candidates.sort(_compareCandidates);

    final winner = candidates.first;
    final sameValue = candidates
        .where((candidate) => candidate.valueKey == winner.valueKey)
        .toList();
    final significantConflicts = candidates
        .where(
          (candidate) =>
              candidate.valueKey != winner.valueKey &&
              _isSignificantConflict(winner, candidate),
        )
        .toList();

    final unresolved = significantConflicts.any(
      (candidate) => _isUnresolvablePair(winner, candidate),
    );
    final conflictIds =
        significantConflicts.map((candidate) => candidate.evidence.id).toList()
          ..sort();

    if (unresolved) {
      return ResolvedField<T>.unknown(
        resolutionReason: 'unresolved_high_authority_conflict',
        conflictingEvidenceIds: <String>[winner.evidence.id, ...conflictIds]
          ..sort(),
      );
    }

    final winningIds = sameValue.map((item) => item.evidence.id).toList()
      ..sort();
    if (winner.evidence.valueState == EvidenceValueState.notApplicable) {
      return ResolvedField<T>.notApplicable(
        nature: winner.evidence.nature,
        winningSource: winner.evidence.source,
        confidence: winner.evidence.confidence,
        winningEvidenceIds: winningIds,
        conflictingEvidenceIds: conflictIds,
        userCorrected: winner.evidence.source == EvidenceSource.userCorrection,
        resolutionReason: _resolutionReason(winner, conflictIds.isNotEmpty),
      );
    }
    return ResolvedField<T>.known(
      value: winner.value as T,
      nature: winner.evidence.nature,
      winningSource: winner.evidence.source,
      confidence: winner.evidence.confidence,
      winningEvidenceIds: winningIds,
      conflictingEvidenceIds: conflictIds,
      userCorrected: winner.evidence.source == EvidenceSource.userCorrection,
      resolutionReason: _resolutionReason(winner, conflictIds.isNotEmpty),
    );
  }

  bool _isStaleOrUnsafeDefault(
    ProfileEvidence evidence,
    String property,
    String? resolvedCanonicalType,
  ) {
    if (evidence.nature != EvidenceNature.defaulted ||
        !_canonicalDependentProperties.contains(property)) {
      return false;
    }

    final dependency = evidence.dependsOnCanonicalType?.trim();
    if (dependency == null || dependency.isEmpty) {
      // A type-derived default without its type dependency cannot safely follow
      // a canonical type correction. Providers should add the dependency.
      return resolvedCanonicalType != null;
    }
    return resolvedCanonicalType != null &&
        _normalizedString(dependency) !=
            _normalizedString(resolvedCanonicalType);
  }

  bool _isSignificantConflict<T>(
    _Candidate<T> winner,
    _Candidate<T> challenger,
  ) {
    if (challenger.evidence.source == EvidenceSource.userCorrection) {
      return true;
    }
    if (challenger.evidence.nature == EvidenceNature.defaulted ||
        challenger.evidence.nature == EvidenceNature.unknown) {
      return false;
    }
    return challenger.authority >= 60 &&
        (challenger.evidence.verified || challenger.evidence.confidence >= 0.6);
  }

  bool _isUnresolvablePair<T>(_Candidate<T> winner, _Candidate<T> challenger) {
    if (winner.evidence.source == EvidenceSource.userCorrection) return false;
    return winner.authority >= 80 &&
        challenger.authority >= 80 &&
        winner.authority == challenger.authority &&
        winner.evidence.confidence >= 0.6 &&
        challenger.evidence.confidence >= 0.6;
  }

  String _resolutionReason<T>(_Candidate<T> winner, bool hasConflict) {
    if (winner.evidence.source == EvidenceSource.userCorrection) {
      return hasConflict
          ? 'user_correction_overrode_conflict'
          : 'user_correction';
    }
    final base = 'selected_${winner.evidence.source.wireName}';
    return hasConflict ? '${base}_with_conflict' : base;
  }

  int _quality(_PropertyPolicy policy, ProfileEvidence evidence) {
    final natureAdjustment = switch (evidence.nature) {
      EvidenceNature.observed => 4,
      EvidenceNature.inferred => 0,
      EvidenceNature.defaulted => -15,
      EvidenceNature.unknown => -8,
    };
    final verifiedAdjustment = evidence.verified ? 4 : 0;
    final confidenceAdjustment = (evidence.confidence * 5).round();
    return policy.authorityFor(evidence.source) * 100 +
        natureAdjustment * 10 +
        verifiedAdjustment * 10 +
        confidenceAdjustment;
  }

  T? _normalizeValue<T>(String property, Object? raw) {
    final normalized = _normalizeUntyped(
      property,
      raw,
      collectionAsSet: T == Set<String>,
    );
    return normalized is T ? normalized : null;
  }

  Object? _normalizeUntyped(
    String property,
    Object? raw, {
    bool collectionAsSet = false,
  }) {
    final Object? normalized;
    if (_collectionProperties.contains(property)) {
      normalized = property == WardrobeProfileProperty.supportedLayerRoles
          ? _normalizeLayerRoles(raw)
          : _normalizeCollection(raw, asSet: collectionAsSet);
    } else if (property == WardrobeProfileProperty.warmth ||
        property == WardrobeProfileProperty.formality) {
      normalized = _normalizeLevel(raw);
    } else if (property == WardrobeProfileProperty.layerRole) {
      normalized = _normalizeLayerRole(raw);
    } else if (_capabilityLevelProperties.contains(property)) {
      normalized = _normalizeCapabilityLevel(raw);
    } else if (property == WardrobeProfileProperty.coverage) {
      normalized = _normalizeCoverage(raw);
    } else if (_booleanObservationProperties.contains(property)) {
      normalized = raw is bool ? raw : null;
    } else if (property == WardrobeProfileProperty.frontClosure) {
      normalized = _normalizeEnum<FrontClosure>(
        raw,
        FrontClosure.values,
        (value) => value.wireName,
      );
    } else if (_visualAmountProperties.contains(property)) {
      normalized = _normalizeEnum<VisualAmount>(
        raw,
        VisualAmount.values,
        (value) => value.wireName,
      );
    } else if (property == WardrobeProfileProperty.surfaceAppearance) {
      normalized = _normalizeEnum<SurfaceAppearance>(
        raw,
        SurfaceAppearance.values,
        (value) => value.wireName,
      );
    } else if (property == WardrobeProfileProperty.necklineShape) {
      normalized = _normalizeEnum<NecklineShape>(
        raw,
        NecklineShape.values,
        (value) => value.wireName,
      );
    } else if (property == WardrobeProfileProperty.visiblePocketStructure) {
      normalized = _normalizeEnum<VisiblePocketStructure>(
        raw,
        VisiblePocketStructure.values,
        (value) => value.wireName,
      );
    } else if (property == WardrobeProfileProperty.footwearConstruction) {
      normalized = _normalizeEnum<FootwearConstruction>(
        raw,
        FootwearConstruction.values,
        (value) => value.wireName,
      );
    } else if (property == WardrobeProfileProperty.footwearFastening) {
      normalized = _normalizeEnum<FootwearFastening>(
        raw,
        FootwearFastening.values,
        (value) => value.wireName,
      );
    } else if (property == WardrobeProfileProperty.soleProfile) {
      normalized = _normalizeEnum<SoleProfile>(
        raw,
        SoleProfile.values,
        (value) => value.wireName,
      );
    } else if (property == WardrobeProfileProperty.visibleTread) {
      normalized = _normalizeEnum<VisibleTread>(
        raw,
        VisibleTread.values,
        (value) => value.wireName,
      );
    } else if (property == WardrobeProfileProperty.footwearUpperHeight) {
      normalized = _normalizeEnum<FootwearUpperHeight>(
        raw,
        FootwearUpperHeight.values,
        (value) => value.wireName,
      );
    } else if (property == WardrobeProfileProperty.rainSuitability) {
      normalized = _normalizeRainSuitability(raw);
    } else {
      normalized = _normalizeString(raw);
    }
    return normalized;
  }

  Object? _normalizeCollection(Object? raw, {required bool asSet}) {
    if (raw is! Iterable || raw is String) return null;
    final byKey = <String, String>{};
    for (final value in raw) {
      final normalized = _normalizeString(value);
      if (normalized == null) return null;
      byKey.putIfAbsent(_normalizedString(normalized), () => normalized);
    }
    if (byKey.isEmpty) return null;
    final values = byKey.values.toList()
      ..sort(
        (left, right) =>
            _normalizedString(left).compareTo(_normalizedString(right)),
      );
    return asSet
        ? Set<String>.unmodifiable(values)
        : List<String>.unmodifiable(values);
  }

  int? _normalizeLevel(Object? raw) {
    final value = switch (raw) {
      int number => number,
      num number when number.isFinite && number == number.roundToDouble() =>
        number.toInt(),
      _ => null,
    };
    return value != null && value >= 1 && value <= 10 ? value : null;
  }

  String? _normalizeString(Object? raw) {
    if (raw is! String) return null;
    final value = raw.trim();
    return value.isEmpty || _normalizedString(value) == 'unknown'
        ? null
        : value;
  }

  WardrobeLayerRole? _normalizeLayerRole(Object? raw) {
    if (raw is WardrobeLayerRole && raw != WardrobeLayerRole.unknown) {
      return raw;
    }
    if (raw is! String) return null;
    final key = _normalizedString(raw).replaceAll('-', '_');
    return switch (key) {
      'base_layer' => WardrobeLayerRole.baseLayer,
      'mid_layer' => WardrobeLayerRole.midLayer,
      'outer_layer' => WardrobeLayerRole.outerLayer,
      'bottom' => WardrobeLayerRole.bottom,
      'footwear' || 'shoes' => WardrobeLayerRole.footwear,
      'accessory' => WardrobeLayerRole.accessory,
      _ => null,
    };
  }

  CapabilityLevel? _normalizeCapabilityLevel(Object? raw) {
    if (raw is CapabilityLevel && raw != CapabilityLevel.unknown) return raw;
    if (raw is! String) return null;
    return switch (_normalizedString(raw)) {
      'verylow' || 'very_low' => CapabilityLevel.veryLow,
      'low' => CapabilityLevel.low,
      'medium' => CapabilityLevel.medium,
      'high' => CapabilityLevel.high,
      'veryhigh' || 'very_high' => CapabilityLevel.veryHigh,
      _ => null,
    };
  }

  Set<WardrobeLayerRole>? _normalizeLayerRoles(Object? raw) {
    if (raw is! Iterable || raw is String) return null;
    final roles = <WardrobeLayerRole>{};
    for (final value in raw) {
      final role = _normalizeLayerRole(value);
      if (role == null) return null;
      roles.add(role);
    }
    if (roles.isEmpty) return null;
    final sorted = roles.toList()
      ..sort((left, right) => left.wireName.compareTo(right.wireName));
    return Set<WardrobeLayerRole>.unmodifiable(sorted);
  }

  GarmentCoverage? _normalizeCoverage(Object? raw) {
    if (raw is GarmentCoverage) return raw;
    if (raw is! String) return null;
    return switch (_normalizedString(raw)) {
      'minimal' => GarmentCoverage.minimal,
      'partial' => GarmentCoverage.partial,
      'full' => GarmentCoverage.full,
      _ => null,
    };
  }

  T? _normalizeEnum<T extends Enum>(
    Object? raw,
    Iterable<T> values,
    String Function(T value) wireName,
  ) {
    if (raw is T) return raw;
    if (raw is! String) return null;
    final key = _normalizedString(raw);
    for (final value in values) {
      if (_normalizedString(wireName(value)) == key) return value;
    }
    return null;
  }

  RainSuitability? _normalizeRainSuitability(Object? raw) {
    if (raw is RainSuitability && raw != RainSuitability.unknown) return raw;
    if (raw is! String) return null;
    return switch (_normalizedString(raw)) {
      'unsuitable' => RainSuitability.unsuitable,
      'limited' => RainSuitability.limited,
      'suitable' => RainSuitability.suitable,
      _ => null,
    };
  }

  static String _normalizedString(String value) => value.trim().toLowerCase();

  static String _valueKey(Object? value) {
    if (value is Iterable && value is! String) {
      final elements = value.map((item) => _valueKey(item)).toList()..sort();
      return '[${elements.join('|')}]';
    }
    if (value is Enum) return '${value.runtimeType}:${value.name}';
    if (value is String) return 'string:${_normalizedString(value)}';
    return '${value.runtimeType}:$value';
  }

  static int _compareEvidenceIdentity(
    ProfileEvidence left,
    ProfileEvidence right,
  ) {
    final id = left.id.compareTo(right.id);
    if (id != 0) return id;
    final property = left.property.compareTo(right.property);
    if (property != 0) return property;
    return _valueKey(left.value).compareTo(_valueKey(right.value));
  }

  static int _compareCandidates<T>(_Candidate<T> left, _Candidate<T> right) {
    final quality = right.quality.compareTo(left.quality);
    if (quality != 0) return quality;
    final source = left.evidence.source.index.compareTo(
      right.evidence.source.index,
    );
    if (source != 0) return source;
    return _compareEvidenceIdentity(left.evidence, right.evidence);
  }

  static const _PropertyPolicy _defaultPolicy = _PropertyPolicy();

  static const Map<String, _PropertyPolicy> _policies = {
    WardrobeProfileProperty.canonicalType: _PropertyPolicy(
      verifiedProduct: 92,
      label: 88,
      visual: 68,
      ai: 72,
      kb: 35,
      legacy: 15,
    ),
    WardrobeProfileProperty.brand: _PropertyPolicy(
      verifiedProduct: 94,
      label: 90,
      visual: 55,
      ai: 45,
      kb: 20,
      legacy: 20,
    ),
    WardrobeProfileProperty.colors: _PropertyPolicy.visual(),
    WardrobeProfileProperty.patterns: _PropertyPolicy.visual(),
    WardrobeProfileProperty.fit: _PropertyPolicy.visual(),
    WardrobeProfileProperty.coverage: _PropertyPolicy.visual(),
    WardrobeProfileProperty.hasHood: _PropertyPolicy.visual(),
    WardrobeProfileProperty.frontClosure: _PropertyPolicy.visual(),
    WardrobeProfileProperty.visibleBulk: _PropertyPolicy.visual(),
    WardrobeProfileProperty.surfaceAppearance: _PropertyPolicy.visual(),
    WardrobeProfileProperty.necklineShape: _PropertyPolicy.visual(),
    WardrobeProfileProperty.visiblePocketStructure: _PropertyPolicy.visual(),
    WardrobeProfileProperty.visibleStretchCue: _PropertyPolicy.visual(),
    WardrobeProfileProperty.sportyCues: _PropertyPolicy.visual(),
    WardrobeProfileProperty.formalCues: _PropertyPolicy.visual(),
    WardrobeProfileProperty.footwearConstruction: _PropertyPolicy.visual(),
    WardrobeProfileProperty.footwearFastening: _PropertyPolicy.visual(),
    WardrobeProfileProperty.soleProfile: _PropertyPolicy.visual(),
    WardrobeProfileProperty.visibleTread: _PropertyPolicy.visual(),
    WardrobeProfileProperty.footwearUpperHeight: _PropertyPolicy.visual(),
    WardrobeProfileProperty.warmth: _PropertyPolicy.capability(),
    WardrobeProfileProperty.formality: _PropertyPolicy.capability(),
    WardrobeProfileProperty.layerRole: _PropertyPolicy.capability(),
    WardrobeProfileProperty.supportedLayerRoles: _PropertyPolicy.capability(),
    WardrobeProfileProperty.mobility: _PropertyPolicy.technicalCapability(),
    WardrobeProfileProperty.breathability:
        _PropertyPolicy.technicalCapability(),
    WardrobeProfileProperty.windProtection:
        _PropertyPolicy.technicalCapability(),
    WardrobeProfileProperty.rainProtection:
        _PropertyPolicy.technicalCapability(),
    WardrobeProfileProperty.walkingComfort:
        _PropertyPolicy.technicalCapability(),
    WardrobeProfileProperty.traction: _PropertyPolicy.technicalCapability(),
    WardrobeProfileProperty.rainSuitability:
        _PropertyPolicy.technicalCapability(),
    WardrobeProfileProperty.outdoorSuitability:
        _PropertyPolicy.technicalCapability(),
    WardrobeProfileProperty.seasons: _PropertyPolicy.suitability(),
    WardrobeProfileProperty.occasions: _PropertyPolicy.suitability(),
  };

  static const Set<String> _collectionProperties = {
    WardrobeProfileProperty.colors,
    WardrobeProfileProperty.baseColors,
    WardrobeProfileProperty.patterns,
    WardrobeProfileProperty.styles,
    WardrobeProfileProperty.supportedLayerRoles,
    WardrobeProfileProperty.seasons,
    WardrobeProfileProperty.occasions,
    WardrobeProfileProperty.activities,
    WardrobeProfileProperty.terrain,
  };

  static const Set<String> _capabilityLevelProperties = {
    WardrobeProfileProperty.mobility,
    WardrobeProfileProperty.breathability,
    WardrobeProfileProperty.windProtection,
    WardrobeProfileProperty.rainProtection,
    WardrobeProfileProperty.walkingComfort,
    WardrobeProfileProperty.traction,
    WardrobeProfileProperty.outdoorSuitability,
  };

  static const Set<String> _booleanObservationProperties = {
    WardrobeProfileProperty.hasHood,
    WardrobeProfileProperty.visibleStretchCue,
  };

  static const Set<String> _visualAmountProperties = {
    WardrobeProfileProperty.visibleBulk,
    WardrobeProfileProperty.sportyCues,
    WardrobeProfileProperty.formalCues,
  };

  static const Set<String> _canonicalDependentProperties = {
    WardrobeProfileProperty.warmth,
    WardrobeProfileProperty.formality,
    WardrobeProfileProperty.layerRole,
    WardrobeProfileProperty.supportedLayerRoles,
    WardrobeProfileProperty.mobility,
    WardrobeProfileProperty.breathability,
    WardrobeProfileProperty.windProtection,
    WardrobeProfileProperty.rainProtection,
    WardrobeProfileProperty.walkingComfort,
    WardrobeProfileProperty.traction,
    WardrobeProfileProperty.rainSuitability,
    WardrobeProfileProperty.outdoorSuitability,
    WardrobeProfileProperty.seasons,
    WardrobeProfileProperty.occasions,
    WardrobeProfileProperty.activities,
    WardrobeProfileProperty.terrain,
  };

  static const Set<String> _allProperties = {
    WardrobeProfileProperty.displayName,
    WardrobeProfileProperty.canonicalType,
    WardrobeProfileProperty.primaryType,
    WardrobeProfileProperty.secondaryType,
    WardrobeProfileProperty.mainCategory,
    WardrobeProfileProperty.category,
    WardrobeProfileProperty.subcategory,
    WardrobeProfileProperty.brand,
    WardrobeProfileProperty.colors,
    WardrobeProfileProperty.baseColors,
    WardrobeProfileProperty.patterns,
    WardrobeProfileProperty.styles,
    WardrobeProfileProperty.fit,
    WardrobeProfileProperty.vibe,
    WardrobeProfileProperty.logoProminence,
    WardrobeProfileProperty.visualIdentity,
    WardrobeProfileProperty.visualDescription,
    WardrobeProfileProperty.materialFeel,
    WardrobeProfileProperty.coverage,
    WardrobeProfileProperty.hasHood,
    WardrobeProfileProperty.frontClosure,
    WardrobeProfileProperty.visibleBulk,
    WardrobeProfileProperty.surfaceAppearance,
    WardrobeProfileProperty.necklineShape,
    WardrobeProfileProperty.visiblePocketStructure,
    WardrobeProfileProperty.visibleStretchCue,
    WardrobeProfileProperty.sportyCues,
    WardrobeProfileProperty.formalCues,
    WardrobeProfileProperty.footwearConstruction,
    WardrobeProfileProperty.footwearFastening,
    WardrobeProfileProperty.soleProfile,
    WardrobeProfileProperty.visibleTread,
    WardrobeProfileProperty.footwearUpperHeight,
    WardrobeProfileProperty.warmth,
    WardrobeProfileProperty.formality,
    WardrobeProfileProperty.layerRole,
    WardrobeProfileProperty.supportedLayerRoles,
    WardrobeProfileProperty.mobility,
    WardrobeProfileProperty.breathability,
    WardrobeProfileProperty.windProtection,
    WardrobeProfileProperty.rainProtection,
    WardrobeProfileProperty.walkingComfort,
    WardrobeProfileProperty.traction,
    WardrobeProfileProperty.rainSuitability,
    WardrobeProfileProperty.outdoorSuitability,
    WardrobeProfileProperty.seasons,
    WardrobeProfileProperty.occasions,
    WardrobeProfileProperty.activities,
    WardrobeProfileProperty.terrain,
  };
}

final class _Candidate<T> {
  const _Candidate({
    required this.evidence,
    required this.value,
    required this.valueKey,
    required this.authority,
    required this.quality,
  });

  final ProfileEvidence evidence;
  final T? value;
  final String valueKey;
  final int authority;
  final int quality;
}

final class _PropertyPolicy {
  const _PropertyPolicy({
    this.verifiedProduct = 85,
    this.label = 82,
    this.visual = 70,
    this.ai = 65,
    this.kb = 30,
    this.legacy = 15,
  });

  const _PropertyPolicy.visual()
    : verifiedProduct = 86,
      label = 82,
      visual = 92,
      ai = 68,
      kb = 25,
      legacy = 15;

  const _PropertyPolicy.capability()
    : verifiedProduct = 88,
      label = 92,
      visual = 82,
      ai = 68,
      kb = 30,
      legacy = 15;

  const _PropertyPolicy.technicalCapability()
    : verifiedProduct = 92,
      label = 95,
      visual = 78,
      ai = 65,
      kb = 25,
      legacy = 15;

  const _PropertyPolicy.suitability()
    : verifiedProduct = 85,
      label = 65,
      visual = 55,
      ai = 70,
      kb = 30,
      legacy = 15;

  final int verifiedProduct;
  final int label;
  final int visual;
  final int ai;
  final int kb;
  final int legacy;

  int authorityFor(EvidenceSource source) => switch (source) {
    EvidenceSource.userCorrection => 100,
    EvidenceSource.verifiedProductMetadata => verifiedProduct,
    EvidenceSource.labelMetadata => label,
    EvidenceSource.visualObservation => visual,
    EvidenceSource.aiInference => ai,
    EvidenceSource.knowledgeBasePrior => kb,
    EvidenceSource.legacyFallback => legacy,
  };
}
