/// Realistic `wardrobe-analyzer-v2` client responses for Add Clothing mapper
/// characterization. Shape matches `adaptAnalyzerV2ToClientResponse`.
library;

Map<String, dynamic> _wardrobeV2({
  required String canonicalType,
  required String canonicalFamily,
  required List<String> bodySlots,
  required String layerPosition,
  required Map<String, dynamic> colorProfile,
  required int formality,
  required int warmth,
  List<String> styles = const ['casual'],
  List<String> occasionFit = const ['casual'],
  List<String> seasons = const [],
  Map<String, dynamic> attributes = const {},
}) {
  return {
    'ontologyVersion': '2.0.0',
    'taxonomyVersion': '2.0.0',
    'kbVersion': '2.0.0',
    'canonicalType': canonicalType,
    'canonicalFamily': canonicalFamily,
    'bodySlots': bodySlots,
    'layerPosition': layerPosition,
    'outfitFunctions': <String>[],
    'colorProfile': colorProfile,
    'formality': formality,
    'styles': styles,
    'occasionFit': occasionFit,
    'seasons': seasons,
    'warmth': warmth,
    'attributes': attributes,
    'setMembership': null,
    'fieldSources': {'canonicalType': 'visual_ai'},
    'fieldConfidence': {'canonicalType': 0.98},
    'userOverrideFields': <String>[],
    'analyzerProvenance': {
      'analyzerVersion': 'clothing-vision-gemini-v2',
      'analyzerProvider': 'google',
      'analyzerModel': 'gemini-3.5-flash',
      'analyzerPromptVersion': 'clothing_analyzer_gemini_v2',
      'analyzerPromptHash': 'abc123',
      'taxonomyVersion': '2.0.0',
      'ontologyVersion': '2.0.0',
      'kbVersion': '2.0.0',
    },
  };
}

Map<String, dynamic> _v2Envelope({
  required Map<String, dynamic> wardrobeV2,
  required List<String> colors,
  List<String> styles = const ['casual'],
  List<String> patterns = const [],
  String fit = 'regular',
  Object? extraWardrobeV2,
  Map<String, dynamic> extras = const {},
}) {
  final type = wardrobeV2['canonicalType'].toString();
  return {
    'contractVersion': 'wardrobe-analyzer-v2',
    'canonical_type': type,
    'canonicalType': type,
    'type': type,
    'type_pretty': type,
    'colors': colors,
    'styles': styles,
    'patterns': patterns,
    'seasons': wardrobeV2['seasons'],
    'fit': fit,
    'formality': wardrobeV2['formality'],
    'occasion_fit': wardrobeV2['occasionFit'],
    'material_feel': 'unknown',
    'warmth_level': wardrobeV2['warmth'],
    'confidence': 98,
    'identity_confidence': 0.98,
    'analyzerVersion': 'clothing-vision-gemini-v2',
    'analyzerProvider': 'google',
    'analyzerModel': 'gemini-3.5-flash',
    'analyzerPromptVersion': 'clothing_analyzer_gemini_v2',
    'analyzerPromptHash': 'abc123',
    'wardrobeV2': extraWardrobeV2 ?? wardrobeV2,
    ...extras,
  };
}

Map<String, dynamic> addClothingAnalyzerTShirtFixture() {
  final wardrobeV2 = _wardrobeV2(
    canonicalType: 't_shirt',
    canonicalFamily: 'base_layer',
    bodySlots: ['upper_body'],
    layerPosition: 'base',
    colorProfile: {
      'primary': {'family': 'white', 'hex': '#ffffff', 'proportion': 0.96},
      'secondary': null,
      'accents': [
        {'family': 'black', 'hex': '#000000', 'proportion': 0.04},
      ],
      'metalTone': 'none',
      'hardwareTone': 'none',
    },
    formality: 3,
    warmth: 2,
  );
  return _v2Envelope(
    wardrobeV2: wardrobeV2,
    colors: ['white'],
    patterns: ['plain'],
  );
}

Map<String, dynamic> addClothingAnalyzerHoodieFixture() {
  final wardrobeV2 = _wardrobeV2(
    canonicalType: 'hoodie',
    canonicalFamily: 'mid_layer',
    bodySlots: ['upper_body'],
    layerPosition: 'mid',
    colorProfile: {
      'primary': {'family': 'black', 'hex': '#000000', 'proportion': 1.0},
      'secondary': null,
      'accents': <Map<String, dynamic>>[],
      'metalTone': 'none',
      'hardwareTone': 'none',
    },
    formality: 2,
    warmth: 5,
    styles: ['casual', 'streetwear'],
  );
  return _v2Envelope(
    wardrobeV2: wardrobeV2,
    colors: ['black'],
    styles: ['casual', 'streetwear'],
    patterns: ['logo_print'],
  );
}

Map<String, dynamic> addClothingAnalyzerPufferJacketFixture() {
  final wardrobeV2 = _wardrobeV2(
    canonicalType: 'puffer_jacket',
    canonicalFamily: 'outerwear',
    bodySlots: ['upper_body'],
    layerPosition: 'outer',
    colorProfile: {
      'primary': {'family': 'navy', 'hex': '#000080', 'proportion': 1.0},
      'secondary': null,
      'accents': <Map<String, dynamic>>[],
      'metalTone': 'none',
      'hardwareTone': 'none',
    },
    formality: 3,
    warmth: 9,
  );
  return _v2Envelope(
    wardrobeV2: wardrobeV2,
    colors: ['navy'],
    patterns: ['solid'],
  );
}

Map<String, dynamic> addClothingAnalyzerJeansFixture() {
  final wardrobeV2 = _wardrobeV2(
    canonicalType: 'jeans',
    canonicalFamily: 'bottom',
    bodySlots: ['lower_body'],
    layerPosition: 'not_applicable',
    colorProfile: {
      'primary': {'family': 'blue', 'hex': '#0000ff', 'proportion': 1.0},
      'secondary': null,
      'accents': <Map<String, dynamic>>[],
      'metalTone': 'none',
      'hardwareTone': 'none',
    },
    formality: 3,
    warmth: 5,
  );
  return _v2Envelope(
    wardrobeV2: wardrobeV2,
    colors: ['blue'],
    patterns: ['plain'],
  );
}

Map<String, dynamic> addClothingAnalyzerSneakersFixture() {
  final wardrobeV2 = _wardrobeV2(
    canonicalType: 'sneakers',
    canonicalFamily: 'footwear',
    bodySlots: ['feet'],
    layerPosition: 'not_applicable',
    colorProfile: {
      'primary': {'family': 'white', 'hex': '#ffffff', 'proportion': 0.7},
      'secondary': {'family': 'black', 'hex': '#000000', 'proportion': 0.3},
      'accents': <Map<String, dynamic>>[],
      'metalTone': 'none',
      'hardwareTone': 'none',
    },
    formality: 2,
    warmth: 3,
  );
  return _v2Envelope(
    wardrobeV2: wardrobeV2,
    colors: ['white', 'black'],
    patterns: ['graphic'],
  );
}

Map<String, dynamic> addClothingAnalyzerMulticolorTopFixture() {
  final wardrobeV2 = _wardrobeV2(
    canonicalType: 't_shirt',
    canonicalFamily: 'base_layer',
    bodySlots: ['upper_body'],
    layerPosition: 'base',
    colorProfile: {
      'primary': {'family': 'blue', 'hex': '#0000ff', 'proportion': 0.62},
      'secondary': {'family': 'white', 'hex': '#ffffff', 'proportion': 0.28},
      'accents': [
        {'family': 'red', 'hex': '#ff0000', 'proportion': 0.1},
      ],
      'metalTone': 'none',
      'hardwareTone': 'none',
    },
    formality: 3,
    warmth: 2,
    styles: ['casual', 'streetwear'],
  );
  return _v2Envelope(
    wardrobeV2: wardrobeV2,
    colors: ['blue', 'white'],
    styles: ['casual', 'streetwear'],
    patterns: ['striped'],
  );
}

/// V2 envelope plus legacy type evidence so the jacket→hoodie guard is reachable.
Map<String, dynamic> addClothingAnalyzerJacketHoodieGuardFixture() {
  final wardrobeV2 = _wardrobeV2(
    canonicalType: 'jacket',
    canonicalFamily: 'outerwear',
    bodySlots: ['upper_body'],
    layerPosition: 'outer',
    colorProfile: {
      'primary': {'family': 'grey', 'hex': '#808080', 'proportion': 1.0},
      'secondary': null,
      'accents': <Map<String, dynamic>>[],
      'metalTone': 'none',
      'hardwareTone': 'none',
    },
    formality: 3,
    warmth: 5,
  );
  final envelope = _v2Envelope(
    wardrobeV2: wardrobeV2,
    colors: ['grey'],
  );
  envelope['canonical_type'] = 'jacket';
  envelope['type'] = 'hoodie';
  envelope['type_pretty'] = 'mikina s kapucňou';
  return envelope;
}

Map<String, dynamic> addClothingAnalyzerMissingWardrobeV2Fixture() {
  return {
    'contractVersion': 'wardrobe-analyzer-v2',
    'canonical_type': 't_shirt',
    'type': 't_shirt',
    'type_pretty': 't_shirt',
    'colors': ['white'],
    'styles': ['casual'],
    'patterns': ['plain'],
    'seasons': <String>[],
    'formality': 3,
    'warmth_level': 2,
    'confidence': 90,
  };
}

Map<String, dynamic> addClothingAnalyzerMalformedWardrobeV2Fixture() {
  final base = addClothingAnalyzerTShirtFixture();
  base['wardrobeV2'] = 'not-an-object';
  return base;
}

Map<String, dynamic> addClothingAnalyzerEmptyColorsFixture() {
  final base = addClothingAnalyzerTShirtFixture();
  base['colors'] = <String>[];
  (base['wardrobeV2'] as Map<String, dynamic>)['colorProfile'] = {
    'primary': {'family': '', 'hex': '', 'proportion': 0},
    'secondary': null,
    'accents': <Map<String, dynamic>>[],
    'metalTone': 'none',
    'hardwareTone': 'none',
  };
  return base;
}

Map<String, dynamic> addClothingAnalyzerUnknownCanonicalFixture() {
  final wardrobeV2 = _wardrobeV2(
    canonicalType: 'not_a_real_type',
    canonicalFamily: 'unknown',
    bodySlots: ['upper_body'],
    layerPosition: 'base',
    colorProfile: {
      'primary': {'family': 'white', 'hex': '#ffffff', 'proportion': 1.0},
      'secondary': null,
      'accents': <Map<String, dynamic>>[],
      'metalTone': 'none',
      'hardwareTone': 'none',
    },
    formality: 5,
    warmth: 5,
  );
  return _v2Envelope(
    wardrobeV2: wardrobeV2,
    colors: ['white'],
  );
}

Map<String, dynamic> addClothingAnalyzerMissingBridgeFieldsFixture() {
  final wardrobeV2 = _wardrobeV2(
    canonicalType: 't_shirt',
    canonicalFamily: 'base_layer',
    bodySlots: ['upper_body'],
    layerPosition: 'base',
    colorProfile: {
      'primary': {'family': 'white', 'hex': '#ffffff', 'proportion': 1.0},
      'secondary': null,
      'accents': <Map<String, dynamic>>[],
      'metalTone': 'none',
      'hardwareTone': 'none',
    },
    formality: 3,
    warmth: 2,
  );
  return {
    'contractVersion': 'wardrobe-analyzer-v2',
    'wardrobeV2': wardrobeV2,
  };
}

/// Valid V2 hoodie while bridge/heuristics still say jacket.
Map<String, dynamic> addClothingAnalyzerV2HoodieVsJacketBridgeFixture() {
  final wardrobeV2 = _wardrobeV2(
    canonicalType: 'hoodie',
    canonicalFamily: 'mid_layer',
    bodySlots: ['upper_body'],
    layerPosition: 'mid',
    colorProfile: {
      'primary': {'family': 'black', 'hex': '#000000', 'proportion': 1.0},
      'secondary': null,
      'accents': <Map<String, dynamic>>[],
      'metalTone': 'none',
      'hardwareTone': 'none',
    },
    formality: 2,
    warmth: 5,
    styles: ['casual', 'streetwear'],
  );
  final envelope = _v2Envelope(
    wardrobeV2: wardrobeV2,
    colors: ['grey'],
    styles: ['casual', 'streetwear'],
    patterns: ['logo_print'],
  );
  envelope['canonical_type'] = 'jacket';
  envelope['canonicalType'] = 'jacket';
  envelope['type'] = 'jacket';
  envelope['type_pretty'] = 'bunda';
  return envelope;
}

/// Valid V2 denim jacket while the jacket→hoodie guard evidence is present.
Map<String, dynamic> addClothingAnalyzerV2DenimJacketVsHoodieGuardFixture() {
  final wardrobeV2 = _wardrobeV2(
    canonicalType: 'denim_jacket',
    canonicalFamily: 'outerwear',
    bodySlots: ['upper_body'],
    layerPosition: 'outer',
    colorProfile: {
      'primary': {'family': 'blue', 'hex': '#0000ff', 'proportion': 1.0},
      'secondary': null,
      'accents': <Map<String, dynamic>>[],
      'metalTone': 'none',
      'hardwareTone': 'none',
    },
    formality: 3,
    warmth: 4,
  );
  final envelope = _v2Envelope(
    wardrobeV2: wardrobeV2,
    colors: ['grey'],
    patterns: ['solid'],
  );
  envelope['canonical_type'] = 'jacket';
  envelope['type'] = 'hoodie';
  envelope['type_pretty'] = 'mikina s kapucňou';
  return envelope;
}

/// Valid V2 puffer while jacket-classifier evidence would pick another subtype.
Map<String, dynamic> addClothingAnalyzerV2PufferVsJacketClassifierFixture() {
  final wardrobeV2 = _wardrobeV2(
    canonicalType: 'puffer_jacket',
    canonicalFamily: 'outerwear',
    bodySlots: ['upper_body'],
    layerPosition: 'outer',
    colorProfile: {
      'primary': {'family': 'navy', 'hex': '#000080', 'proportion': 1.0},
      'secondary': null,
      'accents': <Map<String, dynamic>>[],
      'metalTone': 'none',
      'hardwareTone': 'none',
    },
    formality: 3,
    warmth: 9,
  );
  final envelope = _v2Envelope(
    wardrobeV2: wardrobeV2,
    colors: ['red'],
    patterns: ['solid'],
  );
  envelope['canonical_type'] = 'jacket';
  envelope['type'] = 'jacket';
  envelope['type_pretty'] = 'bunda';
  envelope['primary_type'] = 'track jacket';
  envelope['material_feel'] = 'light';
  envelope['vibe'] = 'sport';
  envelope['warmth_level'] = 2;
  return envelope;
}

/// Bridge `colors` conflict with V2 `colorProfile`.
Map<String, dynamic> addClothingAnalyzerV2ColorConflictFixture() {
  final wardrobeV2 = _wardrobeV2(
    canonicalType: 't_shirt',
    canonicalFamily: 'base_layer',
    bodySlots: ['upper_body'],
    layerPosition: 'base',
    colorProfile: {
      'primary': {'family': 'navy', 'hex': '#000080', 'proportion': 1.0},
      'secondary': null,
      'accents': <Map<String, dynamic>>[],
      'metalTone': 'none',
      'hardwareTone': 'none',
    },
    formality: 3,
    warmth: 2,
  );
  return _v2Envelope(
    wardrobeV2: wardrobeV2,
    colors: ['red', 'yellow'],
    patterns: ['plain'],
  );
}

