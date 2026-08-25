enum ObservationState {
  observed,
  unknown,
  notVisible,
  notApplicable;

  String get wireName => switch (this) {
    ObservationState.observed => 'observed',
    ObservationState.unknown => 'unknown',
    ObservationState.notVisible => 'not_visible',
    ObservationState.notApplicable => 'not_applicable',
  };

  static ObservationState fromWireName(String value) =>
      ObservationState.values.firstWhere(
        (state) => state.wireName == value,
        orElse: () => throw ArgumentError.value(
          value,
          'value',
          'Unknown observation state',
        ),
      );
}

enum ObservationVisibilityScope {
  complete,
  sufficient,
  partial,
  notVisible;

  String get wireName => switch (this) {
    ObservationVisibilityScope.notVisible => 'not_visible',
    _ => name,
  };

  static ObservationVisibilityScope fromWireName(String value) =>
      ObservationVisibilityScope.values.firstWhere(
        (scope) => scope.wireName == value,
        orElse: () => throw ArgumentError.value(
          value,
          'value',
          'Unknown observation visibility scope',
        ),
      );
}

enum ObservationVisualRegion {
  fullSilhouette,
  front,
  side,
  back,
  collar,
  neckline,
  pocketArea,
  footwearUpper,
  fasteningArea,
  soleProfile,
  outsole,
  surfaceDetail;

  String get wireName => switch (this) {
    ObservationVisualRegion.fullSilhouette => 'full_silhouette',
    ObservationVisualRegion.pocketArea => 'pocket_area',
    ObservationVisualRegion.footwearUpper => 'footwear_upper',
    ObservationVisualRegion.fasteningArea => 'fastening_area',
    ObservationVisualRegion.soleProfile => 'sole_profile',
    ObservationVisualRegion.surfaceDetail => 'surface_detail',
    _ => name,
  };

  static ObservationVisualRegion fromWireName(String value) =>
      ObservationVisualRegion.values.firstWhere(
        (region) => region.wireName == value,
        orElse: () => throw ArgumentError.value(
          value,
          'value',
          'Unknown observation visual region',
        ),
      );
}

enum GarmentCoverage {
  minimal,
  partial,
  full;

  String get wireName => name;

  static GarmentCoverage fromWireName(String value) => _enumFromWireName(
    GarmentCoverage.values,
    value,
    (item) => item.wireName,
    'garment coverage',
  );
}

class ObservationValue<T> {
  const ObservationValue.observed({
    required T this.value,
    required this.confidence,
    this.visibilityScope,
    this.visibleRegions = const {},
  }) : state = ObservationState.observed,
       assert(confidence >= 0 && confidence <= 1);

  const ObservationValue.unknown()
    : state = ObservationState.unknown,
      value = null,
      confidence = 0,
      visibilityScope = null,
      visibleRegions = const {};

  const ObservationValue.notVisible()
    : state = ObservationState.notVisible,
      value = null,
      confidence = 0,
      visibilityScope = ObservationVisibilityScope.notVisible,
      visibleRegions = const {};

  const ObservationValue.notApplicable()
    : state = ObservationState.notApplicable,
      value = null,
      confidence = 1,
      visibilityScope = null,
      visibleRegions = const {};

  final ObservationState state;
  final T? value;
  final double confidence;
  final ObservationVisibilityScope? visibilityScope;
  final Set<ObservationVisualRegion> visibleRegions;

  bool get isObserved => state == ObservationState.observed;

  Map<String, Object?> toMap(
    Object? Function(T value) encodeValue,
  ) => <String, Object?>{
    'state': state.wireName,
    if (isObserved) 'value': encodeValue(value as T),
    'confidence': confidence,
    if (visibilityScope != null) 'visibilityScope': visibilityScope!.wireName,
    if (visibleRegions.isNotEmpty)
      'visibleRegions': visibleRegions.map((item) => item.wireName).toList()
        ..sort(),
  };

  factory ObservationValue.fromMap(
    Map<String, dynamic> map, {
    required T Function(Object? value) decodeValue,
  }) {
    final state = ObservationState.fromWireName(map['state']?.toString() ?? '');
    if (state != ObservationState.observed) {
      return switch (state) {
        ObservationState.unknown => ObservationValue<T>.unknown(),
        ObservationState.notVisible => ObservationValue<T>.notVisible(),
        ObservationState.notApplicable => ObservationValue<T>.notApplicable(),
        ObservationState.observed => throw StateError('Unreachable'),
      };
    }
    final confidence = (map['confidence'] as num?)?.toDouble();
    final visibilityRaw = map['visibilityScope'];
    final visibilityScope = visibilityRaw == null
        ? null
        : ObservationVisibilityScope.fromWireName(visibilityRaw.toString());
    final regionsRaw = map['visibleRegions'];
    if (regionsRaw != null &&
        (regionsRaw is! List || regionsRaw.any((item) => item is! String))) {
      throw const FormatException('Invalid observed visible regions');
    }
    final visibleRegions = regionsRaw is List
        ? regionsRaw
              .cast<String>()
              .map(ObservationVisualRegion.fromWireName)
              .toSet()
        : <ObservationVisualRegion>{};
    if (!map.containsKey('value') ||
        map['value'] == null ||
        confidence == null ||
        !confidence.isFinite ||
        confidence < 0 ||
        confidence > 1) {
      throw const FormatException('Invalid observed value');
    }
    return ObservationValue<T>.observed(
      value: decodeValue(map['value']),
      confidence: confidence,
      visibilityScope: visibilityScope,
      visibleRegions: Set.unmodifiable(visibleRegions),
    );
  }
}

enum FrontClosure {
  none,
  partialZip,
  fullZip,
  buttons,
  snaps,
  other;

  String get wireName => switch (this) {
    FrontClosure.none => 'none',
    FrontClosure.partialZip => 'partial_zip',
    FrontClosure.fullZip => 'full_zip',
    FrontClosure.buttons => 'buttons',
    FrontClosure.snaps => 'snaps',
    FrontClosure.other => 'other',
  };

  static FrontClosure fromWireName(String value) => _enumFromWireName(
    FrontClosure.values,
    value,
    (item) => item.wireName,
    'front closure',
  );
}

enum VisualAmount {
  low,
  medium,
  high;

  String get wireName => name;

  static VisualAmount fromWireName(String value) => _enumFromWireName(
    VisualAmount.values,
    value,
    (item) => item.wireName,
    'visual amount',
  );
}

enum SurfaceAppearance {
  knit,
  woven,
  fleeceLike,
  quilted,
  smooth,
  textured,
  mesh,
  leatherLike;

  String get wireName => switch (this) {
    SurfaceAppearance.knit => 'knit',
    SurfaceAppearance.woven => 'woven',
    SurfaceAppearance.fleeceLike => 'fleece_like',
    SurfaceAppearance.quilted => 'quilted',
    SurfaceAppearance.smooth => 'smooth',
    SurfaceAppearance.textured => 'textured',
    SurfaceAppearance.mesh => 'mesh',
    SurfaceAppearance.leatherLike => 'leather_like',
  };

  static SurfaceAppearance fromWireName(String value) => _enumFromWireName(
    SurfaceAppearance.values,
    value,
    (item) => item.wireName,
    'surface appearance',
  );
}

/// Directly visible neckline geometry shared by top, knitwear and shirt
/// families. It deliberately describes shape rather than garment identity.
enum NecklineShape {
  crew,
  vNeck,
  scoop,
  highNeck,
  collared,
  other;

  String get wireName => switch (this) {
    NecklineShape.crew => 'crew',
    NecklineShape.vNeck => 'v_neck',
    NecklineShape.scoop => 'scoop',
    NecklineShape.highNeck => 'high_neck',
    NecklineShape.collared => 'collared',
    NecklineShape.other => 'other',
  };

  static NecklineShape fromWireName(String value) => _enumFromWireName(
    NecklineShape.values,
    value,
    (item) => item.wireName,
    'neckline shape',
  );
}

/// Visible external pocket construction. This supports cargo versus
/// non-cargo families without inferring fabric, function or suitability.
enum VisiblePocketStructure {
  none,
  standard,
  cargo,
  patch,
  other;

  String get wireName => name;

  static VisiblePocketStructure fromWireName(String value) => _enumFromWireName(
    VisiblePocketStructure.values,
    value,
    (item) => item.wireName,
    'visible pocket structure',
  );
}

enum FootwearConstruction {
  open,
  partiallyOpen,
  closed;

  String get wireName => switch (this) {
    FootwearConstruction.open => 'open',
    FootwearConstruction.partiallyOpen => 'partially_open',
    FootwearConstruction.closed => 'closed',
  };

  static FootwearConstruction fromWireName(String value) => _enumFromWireName(
    FootwearConstruction.values,
    value,
    (item) => item.wireName,
    'footwear construction',
  );
}

/// Directly visible footwear fastening/entry construction. It is useful
/// across trainers, Chelsea boots, dress shoes and sandals.
enum FootwearFastening {
  laces,
  zipper,
  elasticSidePanels,
  slipOn,
  straps,
  buckles,
  other;

  String get wireName => switch (this) {
    FootwearFastening.laces => 'laces',
    FootwearFastening.zipper => 'zipper',
    FootwearFastening.elasticSidePanels => 'elastic_side_panels',
    FootwearFastening.slipOn => 'slip_on',
    FootwearFastening.straps => 'straps',
    FootwearFastening.buckles => 'buckles',
    FootwearFastening.other => 'other',
  };

  static FootwearFastening fromWireName(String value) => _enumFromWireName(
    FootwearFastening.values,
    value,
    (item) => item.wireName,
    'footwear fastening',
  );
}

enum SoleProfile {
  thin,
  standard,
  chunky;

  String get wireName => name;

  static SoleProfile fromWireName(String value) => _enumFromWireName(
    SoleProfile.values,
    value,
    (item) => item.wireName,
    'sole profile',
  );
}

enum VisibleTread {
  low,
  moderate,
  pronounced;

  String get wireName => name;

  static VisibleTread fromWireName(String value) => _enumFromWireName(
    VisibleTread.values,
    value,
    (item) => item.wireName,
    'visible tread',
  );
}

enum FootwearUpperHeight {
  lowCut,
  ankle,
  highShaft;

  String get wireName => switch (this) {
    FootwearUpperHeight.lowCut => 'low_cut',
    FootwearUpperHeight.ankle => 'ankle',
    FootwearUpperHeight.highShaft => 'high_shaft',
  };

  static FootwearUpperHeight fromWireName(String value) => _enumFromWireName(
    FootwearUpperHeight.values,
    value,
    (item) => item.wireName,
    'footwear upper height',
  );
}

enum ImageOcclusion {
  none,
  partial,
  substantial;

  String get wireName => name;
}

enum ImageQualityLevel {
  low,
  medium,
  high;

  String get wireName => name;
}

class ObservationImageQuality {
  const ObservationImageQuality({
    this.itemFullyVisible,
    this.occlusion,
    this.backgroundInterference,
    this.clarity,
  });

  final bool? itemFullyVisible;
  final ImageOcclusion? occlusion;
  final ImageQualityLevel? backgroundInterference;
  final ImageQualityLevel? clarity;

  Map<String, Object?> toMap() => <String, Object?>{
    if (itemFullyVisible != null) 'itemFullyVisible': itemFullyVisible,
    if (occlusion != null) 'occlusion': occlusion!.wireName,
    if (backgroundInterference != null)
      'backgroundInterference': backgroundInterference!.wireName,
    if (clarity != null) 'clarity': clarity!.wireName,
  };

  factory ObservationImageQuality.fromMap(Map<String, dynamic> map) =>
      ObservationImageQuality(
        itemFullyVisible: map['itemFullyVisible'] is bool
            ? map['itemFullyVisible'] as bool
            : null,
        occlusion: _optionalEnum(
          map['occlusion'],
          ImageOcclusion.values,
          (item) => item.wireName,
          'image occlusion',
        ),
        backgroundInterference: _optionalEnum(
          map['backgroundInterference'],
          ImageQualityLevel.values,
          (item) => item.wireName,
          'image quality level',
        ),
        clarity: _optionalEnum(
          map['clarity'],
          ImageQualityLevel.values,
          (item) => item.wireName,
          'image quality level',
        ),
      );
}

class ClothingObservationBundle {
  const ClothingObservationBundle({
    required this.analysisId,
    required this.modelVersion,
    required this.sourceReference,
    required this.observedAt,
    this.quality = const ObservationImageQuality(),
    this.coverage,
    this.hasHood,
    this.frontClosure,
    this.visibleBulk,
    this.surfaceAppearance,
    this.necklineShape,
    this.visiblePocketStructure,
    this.visibleStretchCue,
    this.sportyCues,
    this.formalCues,
    this.footwearConstruction,
    this.footwearFastening,
    this.soleProfile,
    this.visibleTread,
    this.footwearUpperHeight,
  }) : assert(analysisId != ''),
       assert(modelVersion != ''),
       assert(sourceReference != '');

  final String analysisId;
  final String modelVersion;
  final String sourceReference;
  final DateTime observedAt;
  final ObservationImageQuality quality;

  final ObservationValue<GarmentCoverage>? coverage;
  final ObservationValue<bool>? hasHood;
  final ObservationValue<FrontClosure>? frontClosure;
  final ObservationValue<VisualAmount>? visibleBulk;
  final ObservationValue<SurfaceAppearance>? surfaceAppearance;
  final ObservationValue<NecklineShape>? necklineShape;
  final ObservationValue<VisiblePocketStructure>? visiblePocketStructure;
  final ObservationValue<bool>? visibleStretchCue;
  final ObservationValue<VisualAmount>? sportyCues;
  final ObservationValue<VisualAmount>? formalCues;
  final ObservationValue<FootwearConstruction>? footwearConstruction;
  final ObservationValue<FootwearFastening>? footwearFastening;
  final ObservationValue<SoleProfile>? soleProfile;
  final ObservationValue<VisibleTread>? visibleTread;
  final ObservationValue<FootwearUpperHeight>? footwearUpperHeight;

  Map<String, Object?> toMap() => <String, Object?>{
    'analysisId': analysisId,
    'modelVersion': modelVersion,
    'sourceReference': sourceReference,
    'observedAt': observedAt.toUtc().toIso8601String(),
    'quality': quality.toMap(),
    if (coverage != null)
      'coverage': coverage!.toMap((value) => value.wireName),
    if (hasHood != null) 'hasHood': hasHood!.toMap((value) => value),
    if (frontClosure != null)
      'frontClosure': frontClosure!.toMap((value) => value.wireName),
    if (visibleBulk != null)
      'visibleBulk': visibleBulk!.toMap((value) => value.wireName),
    if (surfaceAppearance != null)
      'surfaceAppearance': surfaceAppearance!.toMap((value) => value.wireName),
    if (necklineShape != null)
      'necklineShape': necklineShape!.toMap((value) => value.wireName),
    if (visiblePocketStructure != null)
      'visiblePocketStructure': visiblePocketStructure!.toMap(
        (value) => value.wireName,
      ),
    if (visibleStretchCue != null)
      'visibleStretchCue': visibleStretchCue!.toMap((value) => value),
    if (sportyCues != null)
      'sportyCues': sportyCues!.toMap((value) => value.wireName),
    if (formalCues != null)
      'formalCues': formalCues!.toMap((value) => value.wireName),
    if (footwearConstruction != null)
      'footwearConstruction': footwearConstruction!.toMap(
        (value) => value.wireName,
      ),
    if (footwearFastening != null)
      'footwearFastening': footwearFastening!.toMap((value) => value.wireName),
    if (soleProfile != null)
      'soleProfile': soleProfile!.toMap((value) => value.wireName),
    if (visibleTread != null)
      'visibleTread': visibleTread!.toMap((value) => value.wireName),
    if (footwearUpperHeight != null)
      'footwearUpperHeight': footwearUpperHeight!.toMap(
        (value) => value.wireName,
      ),
  };

  factory ClothingObservationBundle.fromMap(Map<String, dynamic> map) {
    final observedAt = DateTime.tryParse(map['observedAt']?.toString() ?? '');
    if (observedAt == null) {
      throw const FormatException('Invalid observation timestamp');
    }
    return ClothingObservationBundle(
      analysisId: map['analysisId']?.toString() ?? '',
      modelVersion: map['modelVersion']?.toString() ?? '',
      sourceReference: map['sourceReference']?.toString() ?? '',
      observedAt: observedAt,
      quality: ObservationImageQuality.fromMap(_map(map['quality'])),
      coverage: _observation(
        map['coverage'],
        (value) => GarmentCoverage.fromWireName(value.toString()),
      ),
      hasHood: _observation(map['hasHood'], _bool),
      frontClosure: _observation(
        map['frontClosure'],
        (value) => FrontClosure.fromWireName(value.toString()),
      ),
      visibleBulk: _observation(
        map['visibleBulk'],
        (value) => VisualAmount.fromWireName(value.toString()),
      ),
      surfaceAppearance: _observation(
        map['surfaceAppearance'],
        (value) => SurfaceAppearance.fromWireName(value.toString()),
      ),
      necklineShape: _observation(
        map['necklineShape'],
        (value) => NecklineShape.fromWireName(value.toString()),
      ),
      visiblePocketStructure: _observation(
        map['visiblePocketStructure'],
        (value) => VisiblePocketStructure.fromWireName(value.toString()),
      ),
      visibleStretchCue: _observation(map['visibleStretchCue'], _bool),
      sportyCues: _observation(
        map['sportyCues'],
        (value) => VisualAmount.fromWireName(value.toString()),
      ),
      formalCues: _observation(
        map['formalCues'],
        (value) => VisualAmount.fromWireName(value.toString()),
      ),
      footwearConstruction: _observation(
        map['footwearConstruction'],
        (value) => FootwearConstruction.fromWireName(value.toString()),
      ),
      footwearFastening: _observation(
        map['footwearFastening'],
        (value) => FootwearFastening.fromWireName(value.toString()),
      ),
      soleProfile: _observation(
        map['soleProfile'],
        (value) => SoleProfile.fromWireName(value.toString()),
      ),
      visibleTread: _observation(
        map['visibleTread'],
        (value) => VisibleTread.fromWireName(value.toString()),
      ),
      footwearUpperHeight: _observation(
        map['footwearUpperHeight'],
        (value) => FootwearUpperHeight.fromWireName(value.toString()),
      ),
    );
  }

  static ObservationValue<T>? _observation<T>(
    Object? value,
    T Function(Object? value) decodeValue,
  ) {
    if (value == null) return null;
    return ObservationValue<T>.fromMap(_map(value), decodeValue: decodeValue);
  }

  static bool _bool(Object? value) {
    if (value is! bool) throw const FormatException('Expected a boolean');
    return value;
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map) throw const FormatException('Expected a map');
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
}

T _enumFromWireName<T>(
  Iterable<T> values,
  String wireName,
  String Function(T value) getWireName,
  String label,
) => values.firstWhere(
  (value) => getWireName(value) == wireName,
  orElse: () => throw ArgumentError.value(wireName, 'value', 'Unknown $label'),
);

T? _optionalEnum<T>(
  Object? raw,
  Iterable<T> values,
  String Function(T value) getWireName,
  String label,
) {
  if (raw == null) return null;
  return _enumFromWireName<T>(values, raw.toString(), getWireName, label);
}
