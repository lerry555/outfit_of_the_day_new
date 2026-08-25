import '../../data/clothing_knowledge_base.dart';
import 'wardrobe_profile_contract.dart';

enum LegacyEvidenceQuality {
  probableItemSpecific,
  probableAutomaticDefault,
  unknownOrigin,
}

/// Converts the currently deployed wardrobe document shapes into evidence.
///
/// This adapter deliberately does not resolve aliases or conflicts. Every valid
/// legacy assertion remains separate so the future resolver can apply authority
/// and precedence rules in one place.
final class LegacyWardrobeEvidenceAdapter {
  const LegacyWardrobeEvidenceAdapter();

  static final DateTime _unknownLegacyTimestamp = DateTime.utc(1970);

  List<ProfileEvidence> adapt(
    Map<String, dynamic> document, {
    DateTime? evidenceTimestamp,
  }) {
    final timestamp = evidenceTimestamp?.toUtc() ?? _unknownLegacyTimestamp;
    final evidence = <ProfileEvidence>[];

    _readContainer(
      document,
      document: document,
      containerPath: 'top_level',
      source: EvidenceSource.legacyFallback,
      defaultNature: EvidenceNature.unknown,
      timestamp: timestamp,
      evidence: evidence,
      useContainerConfidence: false,
    );

    for (final entry in const <(String, EvidenceSource)>[
      ('_hiddenAiMetadata', EvidenceSource.aiInference),
      ('hiddenAiMetadata', EvidenceSource.aiInference),
      ('aiMetadata', EvidenceSource.aiInference),
      ('metadata', EvidenceSource.legacyFallback),
    ]) {
      final nested = document[entry.$1];
      if (nested is! Map) continue;
      final nestedValues = <String, dynamic>{
        for (final nestedEntry in nested.entries)
          if (nestedEntry.key is String)
            nestedEntry.key as String: nestedEntry.value,
      };
      _readContainer(
        nestedValues,
        document: document,
        containerPath: entry.$1,
        source: entry.$2,
        defaultNature: entry.$2 == EvidenceSource.aiInference
            ? EvidenceNature.inferred
            : EvidenceNature.unknown,
        timestamp: timestamp,
        evidence: evidence,
        useContainerConfidence: entry.$2 == EvidenceSource.aiInference,
      );
    }

    return List<ProfileEvidence>.unmodifiable(evidence);
  }

  void _readContainer(
    Map<String, dynamic> values, {
    required Map<String, dynamic> document,
    required String containerPath,
    required EvidenceSource source,
    required EvidenceNature defaultNature,
    required DateTime timestamp,
    required List<ProfileEvidence> evidence,
    required bool useContainerConfidence,
  }) {
    final confidence = useContainerConfidence
        ? _readConfidence(values['confidence'])
        : 0.0;

    for (final mapping in _mappings) {
      final rawValue = values[mapping.legacyKey];
      final value = mapping.reader(rawValue);
      if (value == null) continue;

      final evidenceSource =
          source == EvidenceSource.aiInference && mapping.directlyVisual
          ? EvidenceSource.visualObservation
          : source;
      final nature =
          source == EvidenceSource.aiInference && mapping.directlyVisual
          ? EvidenceNature.observed
          : defaultNature;
      final sourcePath = '$containerPath.${mapping.legacyKey}';
      final quality = _classifyQuality(
        document: document,
        values: values,
        containerPath: containerPath,
        mapping: mapping,
        source: evidenceSource,
      );
      final classifiedSource =
          quality == LegacyEvidenceQuality.probableAutomaticDefault
          ? EvidenceSource.legacyFallback
          : evidenceSource;
      final classifiedNature =
          quality == LegacyEvidenceQuality.probableAutomaticDefault
          ? EvidenceNature.defaulted
          : nature;
      final dependentCanonical =
          quality == LegacyEvidenceQuality.probableAutomaticDefault &&
              _canonicalDependentProperties.contains(mapping.property)
          ? _canonicalForDependency(values, document)
          : null;

      evidence.add(
        ProfileEvidence(
          id: 'legacy:$sourcePath:${mapping.property}',
          property: mapping.property,
          value: value,
          source: classifiedSource,
          nature: classifiedNature,
          confidence: confidence,
          method: 'legacy_adapter:$sourcePath:quality=${quality.name}',
          createdAt: timestamp,
          sourceReference: sourcePath,
          dependsOnCanonicalType: dependentCanonical,
        ),
      );
    }
  }

  LegacyEvidenceQuality _classifyQuality({
    required Map<String, dynamic> document,
    required Map<String, dynamic> values,
    required String containerPath,
    required _LegacyFieldMapping mapping,
    required EvidenceSource source,
  }) {
    if (containerPath == 'top_level' &&
        _isMigrationDefault(document, mapping.property)) {
      return LegacyEvidenceQuality.probableAutomaticDefault;
    }

    // The current analysis/save flow replaces these three AI outputs with KB
    // values whenever a KB type matches. Require the complete KB fingerprint;
    // a single coincidentally matching number is not enough.
    if (source == EvidenceSource.aiInference &&
        _isKbFingerprint(values) &&
        _kbDefaultProperties.contains(mapping.property)) {
      return LegacyEvidenceQuality.probableAutomaticDefault;
    }

    if (source == EvidenceSource.aiInference) {
      return LegacyEvidenceQuality.probableItemSpecific;
    }
    return LegacyEvidenceQuality.unknownOrigin;
  }

  static bool _isMigrationDefault(
    Map<String, dynamic> document,
    String property,
  ) {
    final kbMigration =
        _positiveInt(document['kb_migration_version']) != null ||
        document['kb_migrated_at'] != null;
    if (kbMigration && _kbMigrationProperties.contains(property)) return true;

    final mikinaMigration =
        _positiveInt(document['mikina_mid_layer_migration_version']) != null ||
        document['mikina_mid_layer_migrated_at'] != null;
    return mikinaMigration && property == WardrobeProfileProperty.layerRole;
  }

  static bool _isKbFingerprint(Map<String, dynamic> values) {
    final canonical = _firstString(values, const [
      'canonical_type',
      'canonicalType',
    ]);
    if (canonical == null) return false;
    final kb = ClothingKnowledgeBase.findByCanonicalType(canonical);
    if (kb == null) return false;
    return _sameString(
          values['layer_role'] ?? values['layerRole'],
          kb.layerRole,
        ) &&
        _sameLevel(
          values['warmth_level'] ?? values['warmthLevel'],
          kb.warmthDefault,
        ) &&
        _sameLevel(values['formality'], kb.formalityDefault);
  }

  static String? _canonicalForDependency(
    Map<String, dynamic> values,
    Map<String, dynamic> document,
  ) =>
      _firstString(values, const ['canonical_type', 'canonicalType']) ??
      _firstString(document, const ['canonical_type', 'canonicalType']);

  static String? _firstString(Map<String, dynamic> values, List<String> keys) {
    for (final key in keys) {
      final value = values[key];
      if (value is! String) continue;
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  static int? _positiveInt(Object? value) {
    final parsed = switch (value) {
      int number => number,
      num number when number.isFinite && number == number.roundToDouble() =>
        number.toInt(),
      String text => int.tryParse(text.trim()),
      _ => null,
    };
    return parsed != null && parsed > 0 ? parsed : null;
  }

  static bool _sameString(Object? value, String expected) =>
      value is String &&
      value.trim().toLowerCase() == expected.trim().toLowerCase();

  static bool _sameLevel(Object? value, int expected) =>
      _level(value) == expected;

  static double _readConfidence(Object? value) {
    final number = switch (value) {
      num n => n.toDouble(),
      String s => double.tryParse(s.trim()),
      _ => null,
    };
    if (number == null || !number.isFinite || number < 0) return 0;
    if (number <= 1) return number;
    if (number <= 100) return number / 100;
    return 0;
  }

  static Object? _string(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty || trimmed.toLowerCase() == 'unknown'
        ? null
        : trimmed;
  }

  static Object? _stringList(Object? value) {
    if (value is! Iterable || value is String) return null;
    final result = <String>[];
    for (final element in value) {
      if (element is! String) return null;
      final trimmed = element.trim();
      if (trimmed.isNotEmpty && trimmed.toLowerCase() != 'unknown') {
        result.add(trimmed);
      }
    }
    return result.isEmpty ? null : List<String>.unmodifiable(result);
  }

  static Object? _level(Object? value) {
    final number = switch (value) {
      int n => n,
      num n when n.isFinite && n == n.roundToDouble() => n.toInt(),
      String s => int.tryParse(s.trim()),
      _ => null,
    };
    return number != null && number >= 1 && number <= 10 ? number : null;
  }

  static const List<_LegacyFieldMapping> _mappings = [
    _LegacyFieldMapping('name', WardrobeProfileProperty.displayName, _string),
    _LegacyFieldMapping(
      'canonical_type',
      WardrobeProfileProperty.canonicalType,
      _string,
    ),
    _LegacyFieldMapping(
      'canonicalType',
      WardrobeProfileProperty.canonicalType,
      _string,
    ),
    _LegacyFieldMapping(
      'primary_type',
      WardrobeProfileProperty.primaryType,
      _string,
    ),
    _LegacyFieldMapping(
      'primaryType',
      WardrobeProfileProperty.primaryType,
      _string,
    ),
    _LegacyFieldMapping(
      'secondary_type',
      WardrobeProfileProperty.secondaryType,
      _string,
    ),
    _LegacyFieldMapping(
      'secondaryType',
      WardrobeProfileProperty.secondaryType,
      _string,
    ),
    _LegacyFieldMapping(
      'mainGroupKey',
      WardrobeProfileProperty.mainCategory,
      _string,
    ),
    _LegacyFieldMapping(
      'mainGroup',
      WardrobeProfileProperty.mainCategory,
      _string,
    ),
    _LegacyFieldMapping(
      'categoryKey',
      WardrobeProfileProperty.category,
      _string,
    ),
    _LegacyFieldMapping('category', WardrobeProfileProperty.category, _string),
    _LegacyFieldMapping(
      'subCategoryKey',
      WardrobeProfileProperty.subcategory,
      _string,
    ),
    _LegacyFieldMapping(
      'subCategory',
      WardrobeProfileProperty.subcategory,
      _string,
    ),
    _LegacyFieldMapping('brand', WardrobeProfileProperty.brand, _string),
    _LegacyFieldMapping(
      'colors',
      WardrobeProfileProperty.colors,
      _stringList,
      directlyVisual: true,
    ),
    _LegacyFieldMapping(
      'baseColors',
      WardrobeProfileProperty.baseColors,
      _stringList,
      directlyVisual: true,
    ),
    _LegacyFieldMapping(
      'base_colors',
      WardrobeProfileProperty.baseColors,
      _stringList,
      directlyVisual: true,
    ),
    _LegacyFieldMapping('styles', WardrobeProfileProperty.styles, _stringList),
    _LegacyFieldMapping(
      'patterns',
      WardrobeProfileProperty.patterns,
      _stringList,
      directlyVisual: true,
    ),
    _LegacyFieldMapping(
      'fit',
      WardrobeProfileProperty.fit,
      _string,
      directlyVisual: true,
    ),
    _LegacyFieldMapping('vibe', WardrobeProfileProperty.vibe, _string),
    _LegacyFieldMapping(
      'logo_prominence',
      WardrobeProfileProperty.logoProminence,
      _string,
      directlyVisual: true,
    ),
    _LegacyFieldMapping(
      'logoProminence',
      WardrobeProfileProperty.logoProminence,
      _string,
      directlyVisual: true,
    ),
    _LegacyFieldMapping(
      'visual_identity',
      WardrobeProfileProperty.visualIdentity,
      _string,
      directlyVisual: true,
    ),
    _LegacyFieldMapping(
      'visualIdentity',
      WardrobeProfileProperty.visualIdentity,
      _string,
      directlyVisual: true,
    ),
    _LegacyFieldMapping(
      'visual_description',
      WardrobeProfileProperty.visualDescription,
      _string,
      directlyVisual: true,
    ),
    _LegacyFieldMapping(
      'visualDescription',
      WardrobeProfileProperty.visualDescription,
      _string,
      directlyVisual: true,
    ),
    _LegacyFieldMapping(
      'material_feel',
      WardrobeProfileProperty.materialFeel,
      _string,
      directlyVisual: true,
    ),
    _LegacyFieldMapping(
      'materialFeel',
      WardrobeProfileProperty.materialFeel,
      _string,
      directlyVisual: true,
    ),
    _LegacyFieldMapping(
      'layer_role',
      WardrobeProfileProperty.layerRole,
      _string,
    ),
    _LegacyFieldMapping(
      'layerRole',
      WardrobeProfileProperty.layerRole,
      _string,
    ),
    _LegacyFieldMapping('warmth_level', WardrobeProfileProperty.warmth, _level),
    _LegacyFieldMapping('warmthLevel', WardrobeProfileProperty.warmth, _level),
    _LegacyFieldMapping('formality', WardrobeProfileProperty.formality, _level),
    _LegacyFieldMapping(
      'seasons',
      WardrobeProfileProperty.seasons,
      _stringList,
    ),
    _LegacyFieldMapping(
      'occasion_fit',
      WardrobeProfileProperty.occasions,
      _stringList,
    ),
    _LegacyFieldMapping(
      'occasionFit',
      WardrobeProfileProperty.occasions,
      _stringList,
    ),
  ];

  static const Set<String> _kbDefaultProperties = {
    WardrobeProfileProperty.layerRole,
    WardrobeProfileProperty.warmth,
    WardrobeProfileProperty.formality,
  };

  static const Set<String> _kbMigrationProperties = {
    WardrobeProfileProperty.canonicalType,
    WardrobeProfileProperty.mainCategory,
    WardrobeProfileProperty.category,
    WardrobeProfileProperty.subcategory,
    WardrobeProfileProperty.layerRole,
    WardrobeProfileProperty.warmth,
    WardrobeProfileProperty.formality,
  };

  static const Set<String> _canonicalDependentProperties = {
    WardrobeProfileProperty.layerRole,
    WardrobeProfileProperty.warmth,
    WardrobeProfileProperty.formality,
    WardrobeProfileProperty.seasons,
  };
}

typedef _LegacyValueReader = Object? Function(Object? value);

final class _LegacyFieldMapping {
  const _LegacyFieldMapping(
    this.legacyKey,
    this.property,
    this.reader, {
    this.directlyVisual = false,
  });

  final String legacyKey;
  final String property;
  final _LegacyValueReader reader;
  final bool directlyVisual;
}
