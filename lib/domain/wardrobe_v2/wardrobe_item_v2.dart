import 'wardrobe_ontology_v2.dart';

class SemanticColorV2 {
  const SemanticColorV2({required this.family, this.hex, this.proportion});
  final String family;
  final String? hex;
  final double? proportion;
  Map<String, dynamic> toMap() => {
    'family': family,
    'hex': hex,
    'proportion': proportion,
  };
  factory SemanticColorV2.fromMap(Map<String, dynamic> m) => SemanticColorV2(
    family: (m['family'] ?? '').toString(),
    hex: m['hex']?.toString(),
    proportion: (m['proportion'] as num?)?.toDouble(),
  );
}

class ColorProfileV2 {
  const ColorProfileV2({
    required this.primary,
    this.secondary,
    this.accents = const [],
    this.metalTone = 'unknown',
    this.hardwareTone = 'unknown',
  });
  final SemanticColorV2 primary;
  final SemanticColorV2? secondary;
  final List<SemanticColorV2> accents;
  final String metalTone, hardwareTone;
  Map<String, dynamic> toMap() => {
    'primary': primary.toMap(),
    'secondary': secondary?.toMap(),
    'accents': accents.map((x) => x.toMap()).toList(),
    'metalTone': metalTone,
    'hardwareTone': hardwareTone,
  };
  factory ColorProfileV2.fromMap(Map<String, dynamic> m) => ColorProfileV2(
    primary: SemanticColorV2.fromMap(
      Map<String, dynamic>.from(m['primary'] as Map),
    ),
    secondary: m['secondary'] is Map
        ? SemanticColorV2.fromMap(
            Map<String, dynamic>.from(m['secondary'] as Map),
          )
        : null,
    accents: (m['accents'] as List? ?? const [])
        .whereType<Map>()
        .map((x) => SemanticColorV2.fromMap(Map<String, dynamic>.from(x)))
        .toList(),
    metalTone: (m['metalTone'] ?? 'unknown').toString(),
    hardwareTone: (m['hardwareTone'] ?? 'unknown').toString(),
  );
}

class SetMembershipV2 {
  const SetMembershipV2({
    required this.setId,
    required this.setType,
    this.relationshipSource = 'manufacturer_matching',
    this.authority = 'user_confirmation',
    this.displayName,
  });
  final String setId, setType, relationshipSource, authority;
  final String? displayName;
  Map<String, dynamic> toMap() => {
    'setId': setId,
    'setType': setType,
    'relationshipSource': relationshipSource,
    'authority': authority,
    if (displayName != null) 'displayName': displayName,
  };
  factory SetMembershipV2.fromMap(Map<String, dynamic> m) => SetMembershipV2(
    setId: (m['setId'] ?? '').toString(),
    setType: (m['setType'] ?? '').toString(),
    relationshipSource: (m['relationshipSource'] ?? 'manufacturer_matching')
        .toString(),
    authority: (m['authority'] ?? 'user_confirmation').toString(),
    displayName: m['displayName']?.toString(),
  );
}

class WardrobeItemV2 {
  const WardrobeItemV2({
    required this.canonicalType,
    required this.canonicalFamily,
    required this.bodySlots,
    required this.layerPosition,
    required this.colorProfile,
    required this.formality,
    required this.styles,
    required this.occasionFit,
    required this.seasons,
    required this.warmth,
    required this.attributes,
    required this.fieldSources,
    required this.fieldConfidence,
    required this.userOverrideFields,
    this.outfitFunctions = const [],
    this.uiProjection = const {},
    this.multiplicity = const {},
    this.ontologyVersion = WardrobeOntologyV2Values.ontologyVersion,
    this.taxonomyVersion = WardrobeOntologyV2Values.taxonomyVersion,
    this.kbVersion = WardrobeOntologyV2Values.kbVersion,
    this.accessoryGroup,
    this.setMembership,
    this.analyzerProvenance = const {},
  });
  final String canonicalType, canonicalFamily, layerPosition;
  final List<String> bodySlots,
      outfitFunctions,
      styles,
      occasionFit,
      seasons,
      userOverrideFields;
  final ColorProfileV2 colorProfile;
  final int formality, warmth;
  final Map<String, dynamic> attributes,
      uiProjection,
      multiplicity,
      fieldSources,
      fieldConfidence,
      analyzerProvenance;
  final SetMembershipV2? setMembership;
  final String ontologyVersion, taxonomyVersion, kbVersion;
  final String? accessoryGroup;
  Map<String, dynamic> toMap() => {
    'ontologyVersion': ontologyVersion,
    'taxonomyVersion': taxonomyVersion,
    'kbVersion': kbVersion,
    'canonicalType': canonicalType,
    'canonicalFamily': canonicalFamily,
    'bodySlots': bodySlots,
    'layerPosition': layerPosition,
    'outfitFunctions': outfitFunctions,
    'uiProjection': uiProjection,
    'accessoryGroup': accessoryGroup,
    'multiplicity': multiplicity,
    'colorProfile': colorProfile.toMap(),
    'formality': formality,
    'styles': styles,
    'occasionFit': occasionFit,
    'seasons': seasons,
    'warmth': warmth,
    'attributes': attributes,
    'setMembership': setMembership?.toMap(),
    'fieldSources': fieldSources,
    'fieldConfidence': fieldConfidence,
    'userOverrideFields': userOverrideFields,
    'analyzerProvenance': analyzerProvenance,
  };

  factory WardrobeItemV2.fromMap(Map<String, dynamic> m) {
    List<String> strings(String key) => (m[key] as List? ?? const [])
        .map((x) => x.toString())
        .toList(growable: false);
    Map<String, dynamic> map(String key) => m[key] is Map
        ? Map<String, dynamic>.from(m[key] as Map)
        : <String, dynamic>{};
    return WardrobeItemV2(
      ontologyVersion: (m['ontologyVersion'] ?? '').toString(),
      taxonomyVersion: (m['taxonomyVersion'] ?? '').toString(),
      kbVersion: (m['kbVersion'] ?? '').toString(),
      canonicalType: (m['canonicalType'] ?? '').toString(),
      canonicalFamily: (m['canonicalFamily'] ?? '').toString(),
      bodySlots: strings('bodySlots'),
      layerPosition: (m['layerPosition'] ?? '').toString(),
      outfitFunctions: strings('outfitFunctions'),
      uiProjection: map('uiProjection'),
      accessoryGroup: m['accessoryGroup']?.toString(),
      multiplicity: map('multiplicity'),
      colorProfile: ColorProfileV2.fromMap(map('colorProfile')),
      formality: (m['formality'] as num?)?.toInt() ?? 0,
      styles: strings('styles'),
      occasionFit: strings('occasionFit'),
      seasons: strings('seasons'),
      warmth: (m['warmth'] as num?)?.toInt() ?? 0,
      attributes: map('attributes'),
      fieldSources: map('fieldSources'),
      fieldConfidence: map('fieldConfidence'),
      userOverrideFields: strings('userOverrideFields'),
      analyzerProvenance: map('analyzerProvenance'),
      setMembership: m['setMembership'] is Map
          ? SetMembershipV2.fromMap(
              Map<String, dynamic>.from(m['setMembership'] as Map),
            )
          : null,
    );
  }
}

class WardrobeItemV2Validator {
  const WardrobeItemV2Validator(this.ontology);
  final WardrobeOntologyV2 ontology;
  List<String> validate(WardrobeItemV2 item) {
    final e = <String>[];
    if (item.ontologyVersion != WardrobeOntologyV2Values.ontologyVersion) {
      e.add('ontologyVersion.invalid');
    }
    if (item.taxonomyVersion != WardrobeOntologyV2Values.taxonomyVersion) {
      e.add('taxonomyVersion.invalid');
    }
    if (item.kbVersion.isEmpty) e.add('kbVersion.required');
    final d = ontology.definition(item.canonicalType);
    if (d == null) {
      e.add('canonicalType.unknown');
    } else {
      if (item.canonicalFamily != d.canonicalFamily) {
        e.add('canonicalFamily.kb_mismatch');
      }
      if (!d.supportedLayerPositions.contains(item.layerPosition)) {
        e.add('layerPosition.not_supported');
      }
    }
    if (item.bodySlots.isEmpty ||
        item.bodySlots.any(
          (x) => !WardrobeOntologyV2Values.bodySlots.contains(x),
        )) {
      e.add('bodySlots.invalid');
    }
    if (!WardrobeOntologyV2Values.metalTones.contains(
          item.colorProfile.metalTone,
        ) ||
        !WardrobeOntologyV2Values.metalTones.contains(
          item.colorProfile.hardwareTone,
        )) {
      e.add('colorProfile.tone_invalid');
    }
    if (item.formality < 1 || item.formality > 10) e.add('formality.range');
    if (item.warmth < 1 || item.warmth > 10) e.add('warmth.range');
    for (final f in item.userOverrideFields) {
      final source = item.fieldSources[f];
      final validSetAuthority =
          f == 'setMembership' &&
          (source == 'user_confirmation' || source == 'user_correction');
      if (source != 'user_correction' && !validSetAuthority) {
        e.add('userOverrideFields.source_mismatch:$f');
      }
    }
    return e;
  }
}
