import 'wardrobe_observation_contract.dart';

export 'wardrobe_observation_contract.dart';

/// M11.0 runtime contract for one resolved wardrobe item.
///
/// This file intentionally contains no Firestore, UI, resolver, knowledge-base,
/// or outfit-engine dependencies.
abstract final class WardrobeProfileVersions {
  static const int schema = 1;
  static const int taxonomy = 1;
  static const int resolver = 1;
  static const int capabilityContract = 1;
  static const int situationRequirementsContract = 1;
}

/// Stable property identifiers used by evidence and the future resolver.
abstract final class WardrobeProfileProperty {
  static const String displayName = 'identity.displayName';
  static const String family = 'identity.family';
  static const String canonicalType = 'identity.canonicalType';
  static const String primaryType = 'identity.primaryType';
  static const String secondaryType = 'identity.secondaryType';
  static const String mainCategory = 'identity.mainCategory';
  static const String category = 'identity.category';
  static const String subcategory = 'identity.subcategory';
  static const String brand = 'identity.brand';

  static const String colors = 'visual.colors';
  static const String baseColors = 'visual.baseColors';
  static const String patterns = 'visual.patterns';
  static const String styles = 'visual.styles';
  static const String fit = 'visual.fit';
  static const String vibe = 'visual.vibe';
  static const String logoProminence = 'visual.logoProminence';
  static const String visualIdentity = 'visual.visualIdentity';
  static const String visualDescription = 'visual.visualDescription';
  static const String materialFeel = 'visual.materialFeel';
  static const String coverage = 'visual.coverage';
  static const String hasHood = 'visual.observations.hasHood';
  static const String frontClosure = 'visual.observations.frontClosure';
  static const String visibleBulk = 'visual.observations.visibleBulk';
  static const String surfaceAppearance =
      'visual.observations.surfaceAppearance';
  static const String necklineShape = 'visual.observations.necklineShape';
  static const String visiblePocketStructure =
      'visual.observations.visiblePocketStructure';
  static const String visibleStretchCue =
      'visual.observations.visibleStretchCue';
  static const String sportyCues = 'visual.observations.sportyCues';
  static const String formalCues = 'visual.observations.formalCues';
  static const String footwearConstruction =
      'visual.observations.footwearConstruction';
  static const String footwearFastening =
      'visual.observations.footwearFastening';
  static const String soleProfile = 'visual.observations.soleProfile';
  static const String visibleTread = 'visual.observations.visibleTread';
  static const String footwearUpperHeight =
      'visual.observations.footwearUpperHeight';

  static const String warmth = 'capabilities.warmth';
  static const String formality = 'capabilities.formality';
  static const String layerRole = 'capabilities.layerRole';
  static const String supportedLayerRoles = 'capabilities.supportedLayerRoles';
  static const String mobility = 'capabilities.mobility';
  static const String breathability = 'capabilities.breathability';
  static const String windProtection = 'capabilities.windProtection';
  static const String rainProtection = 'capabilities.rainProtection';
  static const String walkingComfort = 'capabilities.walkingComfort';
  static const String traction = 'capabilities.traction';

  /// M11.0 compatibility property. New matching code should prefer
  /// [rainProtection].
  static const String rainSuitability = 'capabilities.rainSuitability';

  /// M11.0 compatibility property. It must not be treated as a substitute for
  /// the concrete M11.1 capabilities.
  static const String outdoorSuitability = 'capabilities.outdoorSuitability';

  static const String seasons = 'suitability.seasons';
  static const String occasions = 'suitability.occasions';
  static const String activities = 'suitability.activities';
  static const String terrain = 'suitability.terrain';
}

enum EvidenceSource {
  userCorrection,
  verifiedProductMetadata,
  labelMetadata,
  visualObservation,
  aiInference,
  knowledgeBasePrior,
  legacyFallback;

  String get wireName => switch (this) {
    EvidenceSource.userCorrection => 'user_correction',
    EvidenceSource.verifiedProductMetadata => 'verified_product_metadata',
    EvidenceSource.labelMetadata => 'label_metadata',
    EvidenceSource.visualObservation => 'visual_observation',
    EvidenceSource.aiInference => 'ai_inference',
    EvidenceSource.knowledgeBasePrior => 'knowledge_base_prior',
    EvidenceSource.legacyFallback => 'legacy_fallback',
  };

  static EvidenceSource fromWireName(String value) =>
      EvidenceSource.values.firstWhere(
        (source) => source.wireName == value,
        orElse: () => throw ArgumentError.value(
          value,
          'value',
          'Unknown evidence source',
        ),
      );
}

enum EvidenceNature {
  unknown,
  observed,
  inferred,
  defaulted;

  String get wireName => name;

  static EvidenceNature fromWireName(String value) =>
      EvidenceNature.values.firstWhere(
        (nature) => nature.wireName == value,
        orElse: () => throw ArgumentError.value(
          value,
          'value',
          'Unknown evidence nature',
        ),
      );
}

enum CapabilityLevel {
  unknown,
  veryLow,
  low,
  medium,
  high,
  veryHigh;

  String get wireName => switch (this) {
    CapabilityLevel.unknown => 'unknown',
    CapabilityLevel.veryLow => 'very_low',
    CapabilityLevel.low => 'low',
    CapabilityLevel.medium => 'medium',
    CapabilityLevel.high => 'high',
    CapabilityLevel.veryHigh => 'very_high',
  };

  static CapabilityLevel fromWireName(String value) =>
      CapabilityLevel.values.firstWhere(
        (level) => level.wireName == value,
        orElse: () => throw ArgumentError.value(
          value,
          'value',
          'Unknown capability level',
        ),
      );
}

enum RainSuitability {
  unknown,
  unsuitable,
  limited,
  suitable;

  String get wireName => name;
}

enum WardrobeLayerRole {
  unknown,
  baseLayer,
  midLayer,
  outerLayer,
  bottom,
  footwear,
  accessory;

  String get wireName => switch (this) {
    WardrobeLayerRole.unknown => 'unknown',
    WardrobeLayerRole.baseLayer => 'base_layer',
    WardrobeLayerRole.midLayer => 'mid_layer',
    WardrobeLayerRole.outerLayer => 'outer_layer',
    WardrobeLayerRole.bottom => 'bottom',
    WardrobeLayerRole.footwear => 'footwear',
    WardrobeLayerRole.accessory => 'accessory',
  };

  static WardrobeLayerRole fromWireName(String value) =>
      WardrobeLayerRole.values.firstWhere(
        (role) => role.wireName == value,
        orElse: () => throw ArgumentError.value(
          value,
          'value',
          'Unknown wardrobe layer role',
        ),
      );
}

enum EvidenceValueState {
  known,
  unknown,
  notVisible,
  notApplicable;

  String get wireName => switch (this) {
    EvidenceValueState.known => 'known',
    EvidenceValueState.unknown => 'unknown',
    EvidenceValueState.notVisible => 'not_visible',
    EvidenceValueState.notApplicable => 'not_applicable',
  };

  static EvidenceValueState fromWireName(String value) =>
      EvidenceValueState.values.firstWhere(
        (state) => state.wireName == value,
        orElse: () => throw ArgumentError.value(
          value,
          'value',
          'Unknown evidence value state',
        ),
      );
}

/// One compact assertion about one profile property.
///
/// [value] must remain JSON-compatible if this object is persisted later.
class ProfileEvidence {
  const ProfileEvidence({
    required this.id,
    required this.property,
    required this.value,
    required this.source,
    required this.nature,
    required this.confidence,
    required this.method,
    required this.createdAt,
    this.verified = false,
    this.active = true,
    this.modelVersion,
    this.sourceReference,
    this.supersedesEvidenceId,
    this.dependsOnCanonicalType,
    this.valueState = EvidenceValueState.known,
  }) : assert(id != ''),
       assert(property != ''),
       assert(method != ''),
       assert(confidence >= 0 && confidence <= 1),
       assert(
         valueState == EvidenceValueState.known || value == null,
         'Non-value evidence cannot carry a value',
       );

  final String id;
  final String property;
  final Object? value;
  final EvidenceSource source;
  final EvidenceNature nature;
  final double confidence;
  final bool verified;
  final bool active;
  final String method;
  final DateTime createdAt;
  final String? modelVersion;
  final String? sourceReference;
  final String? supersedesEvidenceId;

  /// Canonical type for which a type-derived/defaulted assertion was produced.
  ///
  /// This lets the resolver reject a stale dependent default after a canonical
  /// type correction without embedding a dependency graph in the resolver.
  final String? dependsOnCanonicalType;
  final EvidenceValueState valueState;

  bool get isUserCorrection => source == EvidenceSource.userCorrection;

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'property': property,
    'value': value,
    if (valueState != EvidenceValueState.known)
      'valueState': valueState.wireName,
    'source': source.wireName,
    'nature': nature.wireName,
    'confidence': confidence,
    'verified': verified,
    'active': active,
    'method': method,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (modelVersion != null) 'modelVersion': modelVersion,
    if (sourceReference != null) 'sourceReference': sourceReference,
    if (supersedesEvidenceId != null)
      'supersedesEvidenceId': supersedesEvidenceId,
    if (dependsOnCanonicalType != null)
      'dependsOnCanonicalType': dependsOnCanonicalType,
  };

  factory ProfileEvidence.fromMap(Map<String, dynamic> map) {
    final confidence = (map['confidence'] as num?)?.toDouble();
    final createdAt = DateTime.tryParse(map['createdAt']?.toString() ?? '');
    if (confidence == null || createdAt == null) {
      throw const FormatException('Invalid profile evidence');
    }
    return ProfileEvidence(
      id: map['id']?.toString() ?? '',
      property: map['property']?.toString() ?? '',
      value: map['value'],
      valueState: map['valueState'] == null
          ? EvidenceValueState.known
          : EvidenceValueState.fromWireName(map['valueState'].toString()),
      source: EvidenceSource.fromWireName(map['source']?.toString() ?? ''),
      nature: EvidenceNature.fromWireName(map['nature']?.toString() ?? ''),
      confidence: confidence,
      verified: map['verified'] == true,
      active: map['active'] != false,
      method: map['method']?.toString() ?? '',
      createdAt: createdAt,
      modelVersion: map['modelVersion']?.toString(),
      sourceReference: map['sourceReference']?.toString(),
      supersedesEvidenceId: map['supersedesEvidenceId']?.toString(),
      dependsOnCanonicalType: map['dependsOnCanonicalType']?.toString(),
    );
  }
}

/// Runtime resolution result for one property.
///
enum ResolvedFieldState {
  known,
  unknown,
  notApplicable;

  String get wireName => switch (this) {
    ResolvedFieldState.known => 'known',
    ResolvedFieldState.unknown => 'unknown',
    ResolvedFieldState.notApplicable => 'not_applicable',
  };
}

/// Unknown and not-applicable are distinct and never carry a neutral value.
class ResolvedField<T> {
  const ResolvedField.known({
    required T this.value,
    required this.nature,
    required this.winningSource,
    required this.confidence,
    required this.resolutionReason,
    this.winningEvidenceIds = const <String>[],
    this.conflictingEvidenceIds = const <String>[],
    this.userCorrected = false,
  }) : state = ResolvedFieldState.known,
       assert(confidence >= 0 && confidence <= 1),
       assert(resolutionReason != '');

  const ResolvedField.unknown({
    this.resolutionReason = 'insufficient_evidence',
    this.conflictingEvidenceIds = const <String>[],
  }) : value = null,
       state = ResolvedFieldState.unknown,
       nature = null,
       winningSource = null,
       confidence = 0,
       winningEvidenceIds = const <String>[],
       userCorrected = false,
       assert(resolutionReason != '');

  const ResolvedField.notApplicable({
    required this.nature,
    required this.winningSource,
    required this.confidence,
    required this.resolutionReason,
    this.winningEvidenceIds = const <String>[],
    this.conflictingEvidenceIds = const <String>[],
    this.userCorrected = false,
  }) : value = null,
       state = ResolvedFieldState.notApplicable,
       assert(confidence >= 0 && confidence <= 1),
       assert(resolutionReason != '');

  final T? value;
  final ResolvedFieldState state;
  final EvidenceNature? nature;
  final EvidenceSource? winningSource;
  final double confidence;
  final List<String> winningEvidenceIds;
  final List<String> conflictingEvidenceIds;
  final bool userCorrected;
  final String resolutionReason;

  bool get isKnown => state == ResolvedFieldState.known;
  bool get isUnknown => state == ResolvedFieldState.unknown;
  bool get isNotApplicable => state == ResolvedFieldState.notApplicable;
  bool get hasConflict => conflictingEvidenceIds.isNotEmpty;

  Map<String, Object?> toMap({
    Object? Function(T value)? encodeValue,
  }) => <String, Object?>{
    'value': isKnown
        ? (encodeValue == null ? value : encodeValue(value as T))
        : null,
    'isKnown': isKnown,
    'state': state.wireName,
    if (nature != null) 'nature': nature!.wireName,
    if (winningSource != null) 'winningSource': winningSource!.wireName,
    'confidence': confidence,
    if (winningEvidenceIds.isNotEmpty) 'winningEvidenceIds': winningEvidenceIds,
    if (conflictingEvidenceIds.isNotEmpty)
      'conflictingEvidenceIds': conflictingEvidenceIds,
    'userCorrected': userCorrected,
    'resolutionReason': resolutionReason,
  };

  factory ResolvedField.fromMap(
    Map<String, dynamic> map, {
    required T Function(Object? value) decodeValue,
  }) {
    final rawState = map['state']?.toString();
    final state = switch (rawState) {
      'known' => ResolvedFieldState.known,
      'not_applicable' => ResolvedFieldState.notApplicable,
      'unknown' => ResolvedFieldState.unknown,
      _ =>
        map['isKnown'] == true
            ? ResolvedFieldState.known
            : ResolvedFieldState.unknown,
    };
    final reason =
        map['resolutionReason']?.toString() ?? 'insufficient_evidence';
    final conflicts =
        (map['conflictingEvidenceIds'] as List<dynamic>? ?? const [])
            .map((value) => value.toString())
            .toList(growable: false);
    if (state == ResolvedFieldState.unknown) {
      return ResolvedField<T>.unknown(
        resolutionReason: reason,
        conflictingEvidenceIds: conflicts,
      );
    }

    final nature = EvidenceNature.fromWireName(map['nature']?.toString() ?? '');
    final source = EvidenceSource.fromWireName(
      map['winningSource']?.toString() ?? '',
    );
    final confidence = (map['confidence'] as num?)?.toDouble();
    if (confidence == null) {
      throw const FormatException('Invalid resolved field confidence');
    }
    final winningIds = (map['winningEvidenceIds'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false);
    if (state == ResolvedFieldState.notApplicable) {
      return ResolvedField<T>.notApplicable(
        nature: nature,
        winningSource: source,
        confidence: confidence,
        resolutionReason: reason,
        winningEvidenceIds: winningIds,
        conflictingEvidenceIds: conflicts,
        userCorrected: map['userCorrected'] == true,
      );
    }
    if (!map.containsKey('value') || map['value'] == null) {
      throw const FormatException('Known resolved field must contain a value');
    }
    return ResolvedField<T>.known(
      value: decodeValue(map['value']),
      nature: nature,
      winningSource: source,
      confidence: confidence,
      resolutionReason: reason,
      winningEvidenceIds: winningIds,
      conflictingEvidenceIds: conflicts,
      userCorrected: map['userCorrected'] == true,
    );
  }
}

class WardrobeItemIdentity {
  const WardrobeItemIdentity({
    this.displayName = const ResolvedField<String>.unknown(),
    this.canonicalType = const ResolvedField<String>.unknown(),
    this.primaryType = const ResolvedField<String>.unknown(),
    this.secondaryType = const ResolvedField<String>.unknown(),
    this.mainCategory = const ResolvedField<String>.unknown(),
    this.category = const ResolvedField<String>.unknown(),
    this.subcategory = const ResolvedField<String>.unknown(),
    this.brand = const ResolvedField<String>.unknown(),
  });

  final ResolvedField<String> displayName;
  final ResolvedField<String> canonicalType;
  final ResolvedField<String> primaryType;
  final ResolvedField<String> secondaryType;
  final ResolvedField<String> mainCategory;
  final ResolvedField<String> category;
  final ResolvedField<String> subcategory;
  final ResolvedField<String> brand;

  Map<String, Object?> toMap() => <String, Object?>{
    'displayName': displayName.toMap(),
    'canonicalType': canonicalType.toMap(),
    'primaryType': primaryType.toMap(),
    'secondaryType': secondaryType.toMap(),
    'mainCategory': mainCategory.toMap(),
    'category': category.toMap(),
    'subcategory': subcategory.toMap(),
    'brand': brand.toMap(),
  };
}

class WardrobeItemVisualProfile {
  const WardrobeItemVisualProfile({
    this.colors = const ResolvedField<List<String>>.unknown(),
    this.baseColors = const ResolvedField<List<String>>.unknown(),
    this.patterns = const ResolvedField<List<String>>.unknown(),
    this.styles = const ResolvedField<List<String>>.unknown(),
    this.fit = const ResolvedField<String>.unknown(),
    this.vibe = const ResolvedField<String>.unknown(),
    this.logoProminence = const ResolvedField<String>.unknown(),
    this.visualIdentity = const ResolvedField<String>.unknown(),
    this.visualDescription = const ResolvedField<String>.unknown(),
    this.materialFeel = const ResolvedField<String>.unknown(),
    this.coverage = const ResolvedField<GarmentCoverage>.unknown(),
    this.hasHood = const ResolvedField<bool>.unknown(),
    this.frontClosure = const ResolvedField<FrontClosure>.unknown(),
    this.visibleBulk = const ResolvedField<VisualAmount>.unknown(),
    this.surfaceAppearance = const ResolvedField<SurfaceAppearance>.unknown(),
    this.necklineShape = const ResolvedField<NecklineShape>.unknown(),
    this.visiblePocketStructure =
        const ResolvedField<VisiblePocketStructure>.unknown(),
    this.visibleStretchCue = const ResolvedField<bool>.unknown(),
    this.sportyCues = const ResolvedField<VisualAmount>.unknown(),
    this.formalCues = const ResolvedField<VisualAmount>.unknown(),
    this.footwearConstruction =
        const ResolvedField<FootwearConstruction>.unknown(),
    this.footwearFastening = const ResolvedField<FootwearFastening>.unknown(),
    this.soleProfile = const ResolvedField<SoleProfile>.unknown(),
    this.visibleTread = const ResolvedField<VisibleTread>.unknown(),
    this.footwearUpperHeight =
        const ResolvedField<FootwearUpperHeight>.unknown(),
  });

  final ResolvedField<List<String>> colors;
  final ResolvedField<List<String>> baseColors;
  final ResolvedField<List<String>> patterns;
  final ResolvedField<List<String>> styles;
  final ResolvedField<String> fit;
  final ResolvedField<String> vibe;
  final ResolvedField<String> logoProminence;
  final ResolvedField<String> visualIdentity;
  final ResolvedField<String> visualDescription;
  final ResolvedField<String> materialFeel;
  final ResolvedField<GarmentCoverage> coverage;
  final ResolvedField<bool> hasHood;
  final ResolvedField<FrontClosure> frontClosure;
  final ResolvedField<VisualAmount> visibleBulk;
  final ResolvedField<SurfaceAppearance> surfaceAppearance;
  final ResolvedField<NecklineShape> necklineShape;
  final ResolvedField<VisiblePocketStructure> visiblePocketStructure;
  final ResolvedField<bool> visibleStretchCue;
  final ResolvedField<VisualAmount> sportyCues;
  final ResolvedField<VisualAmount> formalCues;
  final ResolvedField<FootwearConstruction> footwearConstruction;
  final ResolvedField<FootwearFastening> footwearFastening;
  final ResolvedField<SoleProfile> soleProfile;
  final ResolvedField<VisibleTread> visibleTread;
  final ResolvedField<FootwearUpperHeight> footwearUpperHeight;

  Map<String, Object?> toMap() => <String, Object?>{
    'colors': colors.toMap(),
    'baseColors': baseColors.toMap(),
    'patterns': patterns.toMap(),
    'styles': styles.toMap(),
    'fit': fit.toMap(),
    'vibe': vibe.toMap(),
    'logoProminence': logoProminence.toMap(),
    'visualIdentity': visualIdentity.toMap(),
    'visualDescription': visualDescription.toMap(),
    'materialFeel': materialFeel.toMap(),
    'coverage': coverage.toMap(encodeValue: (value) => value.wireName),
    'hasHood': hasHood.toMap(),
    'frontClosure': frontClosure.toMap(encodeValue: (value) => value.wireName),
    'visibleBulk': visibleBulk.toMap(encodeValue: (value) => value.wireName),
    'surfaceAppearance': surfaceAppearance.toMap(
      encodeValue: (value) => value.wireName,
    ),
    'necklineShape': necklineShape.toMap(encodeValue: (value) => value.wireName),
    'visiblePocketStructure': visiblePocketStructure.toMap(
      encodeValue: (value) => value.wireName,
    ),
    'visibleStretchCue': visibleStretchCue.toMap(),
    'sportyCues': sportyCues.toMap(encodeValue: (value) => value.wireName),
    'formalCues': formalCues.toMap(encodeValue: (value) => value.wireName),
    'footwearConstruction': footwearConstruction.toMap(
      encodeValue: (value) => value.wireName,
    ),
    'footwearFastening': footwearFastening.toMap(
      encodeValue: (value) => value.wireName,
    ),
    'soleProfile': soleProfile.toMap(encodeValue: (value) => value.wireName),
    'visibleTread': visibleTread.toMap(encodeValue: (value) => value.wireName),
    'footwearUpperHeight': footwearUpperHeight.toMap(
      encodeValue: (value) => value.wireName,
    ),
  };
}

class WardrobeItemCapabilities {
  const WardrobeItemCapabilities({
    this.warmth = const ResolvedField<int>.unknown(),
    this.formality = const ResolvedField<int>.unknown(),
    this.layerRole = const ResolvedField<WardrobeLayerRole>.unknown(),
    this.supportedLayerRoles =
        const ResolvedField<Set<WardrobeLayerRole>>.unknown(),
    this.mobility = const ResolvedField<CapabilityLevel>.unknown(),
    this.breathability = const ResolvedField<CapabilityLevel>.unknown(),
    this.windProtection = const ResolvedField<CapabilityLevel>.unknown(),
    this.rainProtection = const ResolvedField<CapabilityLevel>.unknown(),
    this.walkingComfort = const ResolvedField<CapabilityLevel>.unknown(),
    this.traction = const ResolvedField<CapabilityLevel>.unknown(),
    this.rainSuitability = const ResolvedField<RainSuitability>.unknown(),
    this.outdoorSuitability = const ResolvedField<CapabilityLevel>.unknown(),
  });

  final ResolvedField<int> warmth;
  final ResolvedField<int> formality;
  final ResolvedField<WardrobeLayerRole> layerRole;
  final ResolvedField<Set<WardrobeLayerRole>> supportedLayerRoles;
  final ResolvedField<CapabilityLevel> mobility;
  final ResolvedField<CapabilityLevel> breathability;
  final ResolvedField<CapabilityLevel> windProtection;
  final ResolvedField<CapabilityLevel> rainProtection;
  final ResolvedField<CapabilityLevel> walkingComfort;
  final ResolvedField<CapabilityLevel> traction;
  final ResolvedField<RainSuitability> rainSuitability;
  final ResolvedField<CapabilityLevel> outdoorSuitability;

  Map<String, Object?> toMap() => <String, Object?>{
    'warmth': warmth.toMap(),
    'formality': formality.toMap(),
    'layerRole': layerRole.toMap(encodeValue: (value) => value.wireName),
    'supportedLayerRoles': supportedLayerRoles.toMap(
      encodeValue: (value) =>
          value.map((role) => role.wireName).toList()..sort(),
    ),
    'mobility': mobility.toMap(encodeValue: (value) => value.wireName),
    'breathability': breathability.toMap(encodeValue: (value) => value.wireName),
    'windProtection': windProtection.toMap(
      encodeValue: (value) => value.wireName,
    ),
    'rainProtection': rainProtection.toMap(
      encodeValue: (value) => value.wireName,
    ),
    'walkingComfort': walkingComfort.toMap(
      encodeValue: (value) => value.wireName,
    ),
    'traction': traction.toMap(encodeValue: (value) => value.wireName),
    'rainSuitability': rainSuitability.toMap(
      encodeValue: (value) => value.wireName,
    ),
    'outdoorSuitability': outdoorSuitability.toMap(
      encodeValue: (value) => value.wireName,
    ),
  };
}

class WardrobeItemSuitability {
  const WardrobeItemSuitability({
    this.seasons = const ResolvedField<Set<String>>.unknown(),
    this.occasions = const ResolvedField<Set<String>>.unknown(),
    this.activities = const ResolvedField<Set<String>>.unknown(),
    this.terrain = const ResolvedField<Set<String>>.unknown(),
  });

  final ResolvedField<Set<String>> seasons;
  final ResolvedField<Set<String>> occasions;
  final ResolvedField<Set<String>> activities;
  final ResolvedField<Set<String>> terrain;

  Map<String, Object?> toMap() => <String, Object?>{
    'seasons': seasons.toMap(
      encodeValue: (value) => value.toList()..sort(),
    ),
    'occasions': occasions.toMap(
      encodeValue: (value) => value.toList()..sort(),
    ),
    'activities': activities.toMap(
      encodeValue: (value) => value.toList()..sort(),
    ),
    'terrain': terrain.toMap(
      encodeValue: (value) => value.toList()..sort(),
    ),
  };
}

class WardrobeProfileMetadata {
  const WardrobeProfileMetadata({
    this.schemaVersion = WardrobeProfileVersions.schema,
    this.taxonomyVersion = WardrobeProfileVersions.taxonomy,
    this.resolverVersion = WardrobeProfileVersions.resolver,
    this.revision = 0,
    this.resolvedAt,
    this.resolutionFingerprint,
  }) : assert(schemaVersion > 0),
       assert(taxonomyVersion > 0),
       assert(resolverVersion > 0),
       assert(revision >= 0);

  final int schemaVersion;
  final int taxonomyVersion;
  final int resolverVersion;
  final int revision;
  final DateTime? resolvedAt;
  final String? resolutionFingerprint;

  Map<String, Object?> toMap() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'taxonomyVersion': taxonomyVersion,
    'resolverVersion': resolverVersion,
    'revision': revision,
    if (resolvedAt != null) 'resolvedAt': resolvedAt!.toUtc().toIso8601String(),
    if (resolutionFingerprint != null)
      'resolutionFingerprint': resolutionFingerprint,
  };
}

class ResolvedWardrobeItemProfile {
  const ResolvedWardrobeItemProfile({
    required this.itemId,
    this.identity = const WardrobeItemIdentity(),
    this.visual = const WardrobeItemVisualProfile(),
    this.capabilities = const WardrobeItemCapabilities(),
    this.suitability = const WardrobeItemSuitability(),
    this.metadata = const WardrobeProfileMetadata(),
    this.evidence = const <ProfileEvidence>[],
  }) : assert(itemId != '');

  final String itemId;
  final WardrobeItemIdentity identity;
  final WardrobeItemVisualProfile visual;
  final WardrobeItemCapabilities capabilities;
  final WardrobeItemSuitability suitability;
  final WardrobeProfileMetadata metadata;

  /// Runtime evidence used to produce the resolved fields. Persistence remains
  /// deliberately unspecified in Phase 0.
  final List<ProfileEvidence> evidence;

  /// Deterministic wire encoding of the exact resolver return value.
  ///
  /// Used by oracle export and tests. Does not include persistence envelopes,
  /// mapper projections, or UI convenience fields.
  Map<String, Object?> toMap() => <String, Object?>{
    'itemId': itemId,
    'identity': identity.toMap(),
    'visual': visual.toMap(),
    'capabilities': capabilities.toMap(),
    'suitability': suitability.toMap(),
    'metadata': metadata.toMap(),
    'evidence': evidence.map((item) => item.toMap()).toList(),
  };
}
