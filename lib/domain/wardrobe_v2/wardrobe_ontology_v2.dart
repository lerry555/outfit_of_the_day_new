import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

abstract final class WardrobeOntologyV2Values {
  static const ontologyVersion = '2.0.0';
  static const taxonomyVersion = '2.0.0';
  static const kbVersion = '2.0.0';
  static const bodySlots = <String>{
    'upper_body',
    'lower_body',
    'full_body',
    'feet',
    'head',
    'face_eyes',
    'neck',
    'ears',
    'wrist',
    'hands',
    'fingers',
    'waist',
    'ankle',
    'hair',
    'lapel',
    'chest',
    'pocket',
    'carried',
    'shoulder_carried',
    'back_carried',
  };
  static const layerPositions = <String>{
    'skin_base',
    'base',
    'mid',
    'outer',
    'shell',
    'not_applicable',
  };
  static const compositionRoles = <String>{
    'core',
    'conditional',
    'functional',
    'finishing',
    'accent',
  };
  static const metalTones = <String>{
    'gold',
    'silver',
    'rose_gold',
    'gunmetal',
    'bronze',
    'mixed_metal',
    'none',
    'unknown',
  };
}

class WardrobeTypeV2 {
  const WardrobeTypeV2({
    required this.canonicalType,
    required this.canonicalFamily,
    required this.parentType,
    required this.aliases,
    required this.uiProjection,
    required this.defaultBodySlots,
    required this.defaultLayerPosition,
    required this.supportedLayerPositions,
    required this.outfitFunctions,
    required this.accessoryGroup,
    required this.multiplicity,
    required this.allowedAttributes,
    this.formalityMin,
    this.formalityMax,
    this.formalityTypical,
    this.warmthMin,
    this.warmthMax,
    this.warmthTypical,
  });
  final String canonicalType, canonicalFamily;
  final String defaultLayerPosition;
  final String? parentType, accessoryGroup;
  final List<String> aliases,
      defaultBodySlots,
      supportedLayerPositions,
      outfitFunctions,
      allowedAttributes;
  final Map<String, dynamic> uiProjection, multiplicity;
  final int? formalityMin, formalityMax, formalityTypical;
  final int? warmthMin, warmthMax, warmthTypical;
  factory WardrobeTypeV2.fromMap(Map<String, dynamic> m) {
    int? rangeValue(String rangeKey, String field) {
      final raw = m[rangeKey];
      if (raw is! Map) return null;
      final value = raw[field];
      if (value is num) return value.round();
      return int.tryParse((value ?? '').toString());
    }

    return WardrobeTypeV2(
      canonicalType: m['canonicalType'] as String,
      canonicalFamily: m['canonicalFamily'] as String,
      parentType: m['parentType'] as String?,
      aliases: List<String>.from(m['aliases'] as List),
      uiProjection: Map<String, dynamic>.from(m['uiProjection'] as Map),
      defaultBodySlots: List<String>.from(m['defaultBodySlots'] as List),
      defaultLayerPosition: m['defaultLayerPosition'] as String,
      supportedLayerPositions: List<String>.from(
        m['supportedLayerPositions'] as List,
      ),
      outfitFunctions: List<String>.from(m['outfitFunctions'] as List),
      accessoryGroup: m['accessoryGroup'] as String?,
      multiplicity: Map<String, dynamic>.from(m['multiplicity'] as Map),
      allowedAttributes: List<String>.from(m['allowedAttributes'] as List),
      formalityMin: rangeValue('formalityRange', 'min'),
      formalityMax: rangeValue('formalityRange', 'max'),
      formalityTypical: rangeValue('formalityRange', 'typical'),
      warmthMin: rangeValue('warmthRange', 'min'),
      warmthMax: rangeValue('warmthRange', 'max'),
      warmthTypical: rangeValue('warmthRange', 'typical'),
    );
  }
}

class WardrobeOntologyV2 {
  WardrobeOntologyV2._(this.types, this.aliases);
  final Map<String, WardrobeTypeV2> types;
  final Map<String, String> aliases;
  static WardrobeOntologyV2? _cached;
  static WardrobeOntologyV2? get cached => _cached;
  static Future<WardrobeOntologyV2> load() async {
    if (_cached case final value?) return value;
    return _cached = fromJsonString(
      await rootBundle.loadString('assets/data/wardrobe_ontology_v2.json'),
    );
  }

  static WardrobeOntologyV2 fromJsonString(String source) {
    final raw = jsonDecode(source) as Map<String, dynamic>;
    if (raw['ontologyVersion'] != WardrobeOntologyV2Values.ontologyVersion) {
      throw StateError('wardrobe_ontology_version_mismatch');
    }
    final definitions = <String, WardrobeTypeV2>{},
        aliasIndex = <String, String>{};
    for (final entry in raw['items'] as List) {
      final d = WardrobeTypeV2.fromMap(Map<String, dynamic>.from(entry as Map));
      definitions[d.canonicalType] = d;
      for (final a in d.aliases) {
        aliasIndex.putIfAbsent(_norm(a), () => d.canonicalType);
      }
    }
    return WardrobeOntologyV2._(
      Map.unmodifiable(definitions),
      Map.unmodifiable(aliasIndex),
    );
  }

  WardrobeTypeV2? definition(String canonicalType) =>
      types[canonicalType.trim().toLowerCase()];
  String? resolveAlias(String value) {
    final key = _norm(value);
    return types.containsKey(key) ? key : aliases[key];
  }

  static String _norm(String v) =>
      v.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
}
