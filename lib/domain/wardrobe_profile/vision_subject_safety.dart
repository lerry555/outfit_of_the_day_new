import 'wardrobe_observation_contract.dart';

enum VisionSubjectCardinality {
  singleItemSupported,
  singleItemUncertain,
  multipleItems,
  fragmentOnly,
  noWardrobeSubject,
  ambiguousSubject;

  String get wireName => switch (this) {
    VisionSubjectCardinality.singleItemSupported => 'single_item_supported',
    VisionSubjectCardinality.singleItemUncertain => 'single_item_uncertain',
    VisionSubjectCardinality.multipleItems => 'multiple_items',
    VisionSubjectCardinality.fragmentOnly => 'fragment_only',
    VisionSubjectCardinality.noWardrobeSubject => 'no_wardrobe_subject',
    VisionSubjectCardinality.ambiguousSubject => 'ambiguous_subject',
  };

  static VisionSubjectCardinality fromWireName(String value) =>
      values.firstWhere(
        (item) => item.wireName == value,
        orElse: () => throw ArgumentError.value(value, 'value'),
      );
}

enum VisionSameItemConsistency {
  sameItemSupported,
  sameItemUncertain,
  differentItemsSuspected,
  conflictingSubjects,
  notApplicable;

  String get wireName => switch (this) {
    VisionSameItemConsistency.sameItemSupported => 'same_item_supported',
    VisionSameItemConsistency.sameItemUncertain => 'same_item_uncertain',
    VisionSameItemConsistency.differentItemsSuspected =>
      'different_items_suspected',
    VisionSameItemConsistency.conflictingSubjects => 'conflicting_subjects',
    VisionSameItemConsistency.notApplicable => 'not_applicable',
  };

  static VisionSameItemConsistency fromWireName(String value) =>
      values.firstWhere(
        (item) => item.wireName == value,
        orElse: () => throw ArgumentError.value(value, 'value'),
      );
}

enum VisionSubjectDomain {
  garmentUpper,
  garmentLower,
  garmentOuterwear,
  footwear,
  accessory,
  unknown,
  mixed;

  String get wireName => switch (this) {
    VisionSubjectDomain.garmentUpper => 'garment_upper',
    VisionSubjectDomain.garmentLower => 'garment_lower',
    VisionSubjectDomain.garmentOuterwear => 'garment_outerwear',
    _ => name,
  };

  bool get isGarment =>
      this == garmentUpper || this == garmentLower || this == garmentOuterwear;

  static VisionSubjectDomain fromWireName(String value) => values.firstWhere(
    (item) => item.wireName == value,
    orElse: () => throw ArgumentError.value(value, 'value'),
  );
}

enum VisionFramingClass {
  fullItem,
  mostlyVisible,
  partialItem,
  detailOnly,
  ambiguousFraming,
  noItem;

  String get wireName => switch (this) {
    VisionFramingClass.fullItem => 'full_item',
    VisionFramingClass.mostlyVisible => 'mostly_visible',
    VisionFramingClass.partialItem => 'partial_item',
    VisionFramingClass.detailOnly => 'detail_only',
    VisionFramingClass.ambiguousFraming => 'ambiguous_framing',
    VisionFramingClass.noItem => 'no_item',
  };

  static VisionFramingClass fromWireName(String value) => values.firstWhere(
    (item) => item.wireName == value,
    orElse: () => throw ArgumentError.value(value, 'value'),
  );
}

class VisionSubjectAssessment {
  const VisionSubjectAssessment({
    required this.subjectCountEstimate,
    required this.cardinality,
    required this.primarySubjectPresent,
    required this.sameItemConsistency,
    required this.subjectDomain,
    required this.framing,
    this.reasonCodes = const [],
  });

  final int subjectCountEstimate;
  final VisionSubjectCardinality cardinality;
  final bool primarySubjectPresent;
  final VisionSameItemConsistency sameItemConsistency;
  final VisionSubjectDomain subjectDomain;
  final VisionFramingClass framing;
  final List<String> reasonCodes;

  factory VisionSubjectAssessment.fromMap(Map<String, dynamic> map) {
    final count = map['subjectCountEstimate'];
    final reasons = map['reasonCodes'];
    if (count is! int || count < 0 || count > 3 || reasons is! List) {
      throw const FormatException('Invalid subject assessment');
    }
    return VisionSubjectAssessment(
      subjectCountEstimate: count,
      cardinality: VisionSubjectCardinality.fromWireName(
        map['cardinalityState']?.toString() ?? '',
      ),
      primarySubjectPresent: map['primarySubjectPresent'] == true,
      sameItemConsistency: VisionSameItemConsistency.fromWireName(
        map['sameItemConsistency']?.toString() ?? '',
      ),
      subjectDomain: VisionSubjectDomain.fromWireName(
        map['subjectDomain']?.toString() ?? '',
      ),
      framing: VisionFramingClass.fromWireName(
        map['framingClass']?.toString() ?? '',
      ),
      reasonCodes: List.unmodifiable(reasons.map((item) => item.toString())),
    );
  }

  bool get permitsFamily =>
      cardinality == VisionSubjectCardinality.singleItemSupported &&
      sameItemConsistency == VisionSameItemConsistency.sameItemSupported &&
      (framing == VisionFramingClass.fullItem ||
          framing == VisionFramingClass.mostlyVisible ||
          framing == VisionFramingClass.partialItem);

  bool get permitsCanonical =>
      cardinality == VisionSubjectCardinality.singleItemSupported &&
      sameItemConsistency == VisionSameItemConsistency.sameItemSupported &&
      (framing == VisionFramingClass.fullItem ||
          framing == VisionFramingClass.mostlyVisible) &&
      subjectDomain != VisionSubjectDomain.unknown &&
      subjectDomain != VisionSubjectDomain.mixed;

  bool get capsFamilyAtSupported => framing == VisionFramingClass.partialItem;

  Map<String, Object?> toMap() => {
    'subjectCountEstimate': subjectCountEstimate,
    'cardinalityState': cardinality.wireName,
    'primarySubjectPresent': primarySubjectPresent,
    'sameItemConsistency': sameItemConsistency.wireName,
    'subjectDomain': subjectDomain.wireName,
    'framingClass': framing.wireName,
    'permitsFamily': permitsFamily,
    'permitsCanonical': permitsCanonical,
    'reasonCodes': reasonCodes,
  };
}

enum ObservationApplicabilityState { applicable, notApplicable, uncertain }

class ObservationApplicabilityAudit {
  const ObservationApplicabilityAudit({
    required this.property,
    required this.state,
    required this.subjectDomain,
    required this.reasonCodes,
  });

  final String property;
  final ObservationApplicabilityState state;
  final VisionSubjectDomain subjectDomain;
  final List<String> reasonCodes;

  Map<String, Object?> toMap() => {
    'property': property,
    'state': state.name,
    'subjectDomain': subjectDomain.wireName,
    'reasonCodes': reasonCodes,
  };
}

abstract final class VisionPropertyApplicabilityRegistry {
  static const garmentOnly = {
    'coverage',
    'hasHood',
    'frontClosure',
    'visibleBulk',
    'necklineShape',
    'visiblePocketStructure',
  };
  static const footwearOnly = {
    'footwearConstruction',
    'footwearFastening',
    'soleProfile',
    'visibleTread',
    'footwearUpperHeight',
  };
  static const shared = {
    'surfaceAppearance',
    'visibleStretchCue',
    'sportyCues',
    'formalCues',
  };

  static ObservationApplicabilityState stateFor(
    String property,
    VisionSubjectDomain domain,
  ) {
    if (domain == VisionSubjectDomain.unknown ||
        domain == VisionSubjectDomain.mixed) {
      return shared.contains(property)
          ? ObservationApplicabilityState.uncertain
          : ObservationApplicabilityState.notApplicable;
    }
    if (property == 'hasHood' || property == 'necklineShape') {
      return domain == VisionSubjectDomain.garmentUpper ||
              domain == VisionSubjectDomain.garmentOuterwear
          ? ObservationApplicabilityState.applicable
          : ObservationApplicabilityState.notApplicable;
    }
    if (garmentOnly.contains(property)) {
      return domain.isGarment
          ? ObservationApplicabilityState.applicable
          : ObservationApplicabilityState.notApplicable;
    }
    if (footwearOnly.contains(property)) {
      return domain == VisionSubjectDomain.footwear
          ? ObservationApplicabilityState.applicable
          : ObservationApplicabilityState.notApplicable;
    }
    return shared.contains(property)
        ? ObservationApplicabilityState.applicable
        : ObservationApplicabilityState.uncertain;
  }
}

class VisionApplicabilityReport {
  const VisionApplicabilityReport({
    required this.qualifiedBundle,
    required this.properties,
  });

  final ClothingObservationBundle qualifiedBundle;
  final Map<String, ObservationApplicabilityAudit> properties;

  Map<String, Object?> toMap() => {
    'properties': {
      for (final entry in properties.entries) entry.key: entry.value.toMap(),
    },
  };
}

final class VisionPropertyApplicabilityQualifier {
  const VisionPropertyApplicabilityQualifier();

  VisionApplicabilityReport qualify({
    required ClothingObservationBundle bundle,
    required VisionSubjectAssessment subject,
  }) {
    final audits = <String, ObservationApplicabilityAudit>{};

    ObservationValue<T>? property<T>(String name, ObservationValue<T>? raw) {
      if (raw == null) return null;
      final state = VisionPropertyApplicabilityRegistry.stateFor(
        name,
        subject.subjectDomain,
      );
      audits[name] = ObservationApplicabilityAudit(
        property: name,
        state: state,
        subjectDomain: subject.subjectDomain,
        reasonCodes: [
          switch (state) {
            ObservationApplicabilityState.applicable =>
              'property_applicable_to_subject_domain',
            ObservationApplicabilityState.notApplicable =>
              'property_not_applicable_to_subject_domain',
            ObservationApplicabilityState.uncertain =>
              'subject_domain_does_not_authorize_property',
          },
        ],
      );
      return state == ObservationApplicabilityState.applicable
          ? raw
          : ObservationValue<T>.notApplicable();
    }

    return VisionApplicabilityReport(
      qualifiedBundle: ClothingObservationBundle(
        analysisId: bundle.analysisId,
        modelVersion: bundle.modelVersion,
        sourceReference: bundle.sourceReference,
        observedAt: bundle.observedAt,
        quality: bundle.quality,
        coverage: property('coverage', bundle.coverage),
        hasHood: property('hasHood', bundle.hasHood),
        frontClosure: property('frontClosure', bundle.frontClosure),
        visibleBulk: property('visibleBulk', bundle.visibleBulk),
        surfaceAppearance: property(
          'surfaceAppearance',
          bundle.surfaceAppearance,
        ),
        necklineShape: property('necklineShape', bundle.necklineShape),
        visiblePocketStructure: property(
          'visiblePocketStructure',
          bundle.visiblePocketStructure,
        ),
        visibleStretchCue: property(
          'visibleStretchCue',
          bundle.visibleStretchCue,
        ),
        sportyCues: property('sportyCues', bundle.sportyCues),
        formalCues: property('formalCues', bundle.formalCues),
        footwearConstruction: property(
          'footwearConstruction',
          bundle.footwearConstruction,
        ),
        footwearFastening: property(
          'footwearFastening',
          bundle.footwearFastening,
        ),
        soleProfile: property('soleProfile', bundle.soleProfile),
        visibleTread: property('visibleTread', bundle.visibleTread),
        footwearUpperHeight: property(
          'footwearUpperHeight',
          bundle.footwearUpperHeight,
        ),
      ),
      properties: Map.unmodifiable(audits),
    );
  }
}

enum VisionMultiPhotoConsistency {
  sameItemSupported,
  sameItemUncertain,
  differentItemsSuspected,
  conflictingSubjects,
}

enum VisionMultiViewPhysicalIdentityClaim {
  samePhysicalItem,
  differentPhysicalItems,
  undeclared;

  String get wireName => switch (this) {
    VisionMultiViewPhysicalIdentityClaim.samePhysicalItem =>
      'same_physical_item',
    VisionMultiViewPhysicalIdentityClaim.differentPhysicalItems =>
      'different_physical_items',
    VisionMultiViewPhysicalIdentityClaim.undeclared => 'undeclared',
  };

  static VisionMultiViewPhysicalIdentityClaim fromWireName(String value) =>
      values.firstWhere(
        (item) => item.wireName == value,
        orElse: () => throw ArgumentError.value(value, 'value'),
      );
}

enum VisionMultiViewSubjectBindingSource {
  userItemUploadIntent,
  captureDeclaration,
  assetManifestRelationship,
  unknown;

  String get wireName => switch (this) {
    VisionMultiViewSubjectBindingSource.userItemUploadIntent =>
      'user_item_upload_intent',
    VisionMultiViewSubjectBindingSource.captureDeclaration =>
      'capture_declaration',
    VisionMultiViewSubjectBindingSource.assetManifestRelationship =>
      'asset_manifest_relationship',
    VisionMultiViewSubjectBindingSource.unknown => 'unknown',
  };

  static VisionMultiViewSubjectBindingSource fromWireName(String value) =>
      values.firstWhere(
        (item) => item.wireName == value,
        orElse: () => throw ArgumentError.value(value, 'value'),
      );
}

class VisionMultiViewSubjectBinding {
  const VisionMultiViewSubjectBinding({
    required this.physicalIdentityClaim,
    required this.source,
    this.contractVersion = 1,
    this.reasonCodes = const [],
  });

  static const undeclared = VisionMultiViewSubjectBinding(
    physicalIdentityClaim: VisionMultiViewPhysicalIdentityClaim.undeclared,
    source: VisionMultiViewSubjectBindingSource.unknown,
    reasonCodes: ['default_undeclared'],
  );

  static const supportedContractVersion = 1;

  final VisionMultiViewPhysicalIdentityClaim physicalIdentityClaim;
  final VisionMultiViewSubjectBindingSource source;
  final int contractVersion;
  final List<String> reasonCodes;

  factory VisionMultiViewSubjectBinding.fromMap(Map<String, dynamic> map) {
    final version = map['contractVersion'];
    if (version is! int || version != supportedContractVersion) {
      throw FormatException(
        'Unsupported multiViewSubjectBinding contractVersion: $version',
      );
    }
    final reasons = map['reasonCodes'];
    if (reasons != null && reasons is! List) {
      throw const FormatException(
        'Invalid multiViewSubjectBinding reasonCodes',
      );
    }
    return VisionMultiViewSubjectBinding(
      physicalIdentityClaim: VisionMultiViewPhysicalIdentityClaim.fromWireName(
        map['physicalIdentityClaim']?.toString() ?? '',
      ),
      source: VisionMultiViewSubjectBindingSource.fromWireName(
        map['source']?.toString() ?? '',
      ),
      contractVersion: version,
      reasonCodes: reasons is List
          ? List.unmodifiable(reasons.map((item) => item.toString()))
          : const [],
    );
  }

  Map<String, Object?> toMap() => {
    'contractVersion': contractVersion,
    'physicalIdentityClaim': physicalIdentityClaim.wireName,
    'source': source.wireName,
    'reasonCodes': reasonCodes,
  };
}

enum VisionMultiPhotoSemanticAgreement {
  consistent,
  compatible,
  conflicting,
  unknown,
}

class VisionMultiPhotoConsistencyAssessment {
  const VisionMultiPhotoConsistencyAssessment({
    required this.physicalIdentity,
    required this.semanticAgreement,
    required this.binding,
    this.reasonCodes = const [],
  });

  final VisionMultiPhotoConsistency physicalIdentity;
  final VisionMultiPhotoSemanticAgreement semanticAgreement;
  final VisionMultiViewSubjectBinding binding;
  final List<String> reasonCodes;

  bool get sameItemViews =>
      physicalIdentity == VisionMultiPhotoConsistency.sameItemSupported;

  bool get permitsIdentityPromotion =>
      physicalIdentity == VisionMultiPhotoConsistency.sameItemSupported &&
      semanticAgreement == VisionMultiPhotoSemanticAgreement.consistent;

  Map<String, Object?> toMap() => {
    'physicalIdentity': physicalIdentity.name,
    'semanticAgreement': semanticAgreement.name,
    'multiViewSubjectBinding': binding.toMap(),
    'sameItemViews': sameItemViews,
    'permitsIdentityPromotion': permitsIdentityPromotion,
    'reasonCodes': reasonCodes,
  };
}

VisionMultiPhotoSemanticAgreement assessMultiPhotoSemanticAgreement(
  Iterable<VisionSubjectAssessment> assessments,
) {
  final items = assessments.toList();
  if (items.isEmpty) return VisionMultiPhotoSemanticAgreement.unknown;
  final domains = items.map((item) => item.subjectDomain).toSet();
  if (domains.contains(VisionSubjectDomain.mixed)) {
    return VisionMultiPhotoSemanticAgreement.unknown;
  }
  // A single shared domain, including legacy schema `unknown`, is not a
  // cross-view disagreement. Unknown only blocks when domains disagree.
  if (domains.contains(VisionSubjectDomain.unknown) && domains.length > 1) {
    return VisionMultiPhotoSemanticAgreement.unknown;
  }
  if (domains.length <= 1) {
    return VisionMultiPhotoSemanticAgreement.consistent;
  }
  if (_isSoftAdjacentGarmentPair(domains)) {
    return VisionMultiPhotoSemanticAgreement.compatible;
  }
  return VisionMultiPhotoSemanticAgreement.conflicting;
}

bool _isSoftAdjacentGarmentPair(Set<VisionSubjectDomain> domains) =>
    domains.length == 2 &&
    domains.contains(VisionSubjectDomain.garmentUpper) &&
    domains.contains(VisionSubjectDomain.garmentOuterwear);

VisionMultiPhotoConsistencyAssessment assessMultiPhotoConsistency(
  Iterable<VisionSubjectAssessment> assessments, {
  VisionMultiViewSubjectBinding binding =
      VisionMultiViewSubjectBinding.undeclared,
}) {
  final items = assessments.toList();
  final semantic = assessMultiPhotoSemanticAgreement(items);
  final reasons = <String>[];

  if (items.isEmpty) {
    reasons.add('empty_assessments');
    return VisionMultiPhotoConsistencyAssessment(
      physicalIdentity: VisionMultiPhotoConsistency.sameItemUncertain,
      semanticAgreement: semantic,
      binding: binding,
      reasonCodes: List.unmodifiable(reasons),
    );
  }

  if (items.any(
    (item) => item.cardinality != VisionSubjectCardinality.singleItemSupported,
  )) {
    reasons.add('cardinality_veto');
    return VisionMultiPhotoConsistencyAssessment(
      physicalIdentity: VisionMultiPhotoConsistency.differentItemsSuspected,
      semanticAgreement: semantic,
      binding: binding,
      reasonCodes: List.unmodifiable(reasons),
    );
  }

  if (items.any(
    (item) =>
        item.sameItemConsistency ==
            VisionSameItemConsistency.differentItemsSuspected ||
        item.sameItemConsistency ==
            VisionSameItemConsistency.conflictingSubjects,
  )) {
    reasons.add('per_view_subject_conflict_veto');
    return VisionMultiPhotoConsistencyAssessment(
      physicalIdentity: VisionMultiPhotoConsistency.conflictingSubjects,
      semanticAgreement: semantic,
      binding: binding,
      reasonCodes: List.unmodifiable(reasons),
    );
  }

  // Single-view runs have no cross-view identity question.
  if (items.length == 1) {
    if (items.single.sameItemConsistency ==
        VisionSameItemConsistency.sameItemSupported) {
      reasons.add('single_view_local_same_item');
      return VisionMultiPhotoConsistencyAssessment(
        physicalIdentity: VisionMultiPhotoConsistency.sameItemSupported,
        semanticAgreement: semantic,
        binding: binding,
        reasonCodes: List.unmodifiable(reasons),
      );
    }
    reasons.add('single_view_local_uncertain');
    return VisionMultiPhotoConsistencyAssessment(
      physicalIdentity: VisionMultiPhotoConsistency.sameItemUncertain,
      semanticAgreement: semantic,
      binding: binding,
      reasonCodes: List.unmodifiable(reasons),
    );
  }

  switch (binding.physicalIdentityClaim) {
    case VisionMultiViewPhysicalIdentityClaim.differentPhysicalItems:
      reasons.add('binding_different_physical_items');
      return VisionMultiPhotoConsistencyAssessment(
        physicalIdentity: VisionMultiPhotoConsistency.conflictingSubjects,
        semanticAgreement: semantic,
        binding: binding,
        reasonCodes: List.unmodifiable(reasons),
      );
    case VisionMultiViewPhysicalIdentityClaim.samePhysicalItem:
      reasons.add('binding_same_physical_item');
      return VisionMultiPhotoConsistencyAssessment(
        physicalIdentity: VisionMultiPhotoConsistency.sameItemSupported,
        semanticAgreement: semantic,
        binding: binding,
        reasonCodes: List.unmodifiable(reasons),
      );
    case VisionMultiViewPhysicalIdentityClaim.undeclared:
      reasons.add('binding_undeclared_fail_closed');
      return VisionMultiPhotoConsistencyAssessment(
        physicalIdentity: VisionMultiPhotoConsistency.sameItemUncertain,
        semanticAgreement: semantic,
        binding: binding,
        reasonCodes: List.unmodifiable(reasons),
      );
  }
}
