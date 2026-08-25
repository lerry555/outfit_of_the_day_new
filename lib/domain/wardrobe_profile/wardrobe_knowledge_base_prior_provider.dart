import '../../data/clothing_knowledge_base.dart';
import '../../utils/canonical_resolver.dart';
import 'wardrobe_profile_contract.dart';

/// Produces transparent, type-dependent priors from the existing clothing KB.
///
/// The provider does not resolve evidence and never mutates wardrobe data.
final class WardrobeKnowledgeBasePriorProvider {
  const WardrobeKnowledgeBasePriorProvider();

  static final DateTime _timelessPriorTimestamp = DateTime.utc(1970);

  List<ProfileEvidence> provide({
    required Map<String, dynamic> document,
    required Iterable<ProfileEvidence> existingEvidence,
  }) {
    final existing = existingEvidence.toList(growable: false);
    final explicitCanonical = _singleKnownCanonical(existing);
    final hasNonDefaultCanonical = existing.any(
      (item) =>
          item.active &&
          item.property == WardrobeProfileProperty.canonicalType &&
          item.nature != EvidenceNature.defaulted,
    );
    final inferredCanonical = explicitCanonical == null
        ? _structuredCanonicalCandidate(document)
        : null;
    final canonical = explicitCanonical ?? inferredCanonical?.kb.canonicalType;
    if (canonical == null) return const <ProfileEvidence>[];

    final kb = ClothingKnowledgeBase.findByCanonicalType(canonical);
    if (kb == null) return const <ProfileEvidence>[];

    final evidence = <ProfileEvidence>[];
    if (!hasNonDefaultCanonical) {
      evidence.add(
        _evidence(
          property: WardrobeProfileProperty.canonicalType,
          value: kb.canonicalType,
          canonicalType: kb.canonicalType,
          nature: explicitCanonical == null
              ? EvidenceNature.inferred
              : EvidenceNature.defaulted,
          method: explicitCanonical == null
              ? inferredCanonical!.method
              : 'kb_prior:classified_legacy_canonical',
          confidence: explicitCanonical == null ? 0.45 : 0.35,
          typeDependent: false,
          sourceReference: explicitCanonical == null
              ? inferredCanonical!.sourceReference
              : null,
        ),
      );
    }

    void addDefault(String property, Object value) {
      if (!_canSupplyDefault(property, existing)) return;
      evidence.add(
        _evidence(
          property: property,
          value: value,
          canonicalType: kb.canonicalType,
        ),
      );
    }

    addDefault(WardrobeProfileProperty.mainCategory, kb.mainCategory);
    addDefault(WardrobeProfileProperty.category, kb.category);
    addDefault(WardrobeProfileProperty.subcategory, kb.subcategory);
    addDefault(WardrobeProfileProperty.layerRole, kb.layerRole);
    addDefault(WardrobeProfileProperty.warmth, kb.warmthDefault);
    addDefault(WardrobeProfileProperty.formality, kb.formalityDefault);

    return List<ProfileEvidence>.unmodifiable(evidence);
  }

  bool _canSupplyDefault(String property, Iterable<ProfileEvidence> existing) =>
      !existing.any(
        (item) =>
            item.active &&
            item.property == property &&
            item.nature != EvidenceNature.defaulted,
      );

  ProfileEvidence _evidence({
    required String property,
    required Object value,
    required String canonicalType,
    EvidenceNature nature = EvidenceNature.defaulted,
    String method = 'kb_prior:canonical_type_defaults',
    double confidence = 0.35,
    bool typeDependent = true,
    String? sourceReference,
  }) => ProfileEvidence(
    id: 'kb-prior:$canonicalType:$property',
    property: property,
    value: value,
    source: EvidenceSource.knowledgeBasePrior,
    nature: nature,
    confidence: confidence,
    method: method,
    createdAt: _timelessPriorTimestamp,
    sourceReference:
        sourceReference ?? 'clothing_knowledge_base:$canonicalType',
    dependsOnCanonicalType: typeDependent ? canonicalType : null,
  );

  String? _singleKnownCanonical(Iterable<ProfileEvidence> evidence) {
    final values = evidence
        .where(
          (item) =>
              item.active &&
              item.property == WardrobeProfileProperty.canonicalType,
        )
        .map((item) => item.value)
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .map((value) => ClothingKnowledgeBase.findByCanonicalType(value))
        .whereType<ClothingKbItem>()
        .map((item) => item.canonicalType)
        .toSet();
    return values.length == 1 ? values.single : null;
  }

  _StructuredCanonicalCandidate? _structuredCanonicalCandidate(
    Map<String, dynamic> document,
  ) {
    if (_hasAliasConflict(document, const ['mainGroupKey', 'mainGroup']) ||
        _hasAliasConflict(document, const ['categoryKey', 'category']) ||
        _hasAliasConflict(document, const ['subCategoryKey', 'subCategory']) ||
        _hasAliasConflict(document, const ['primary_type', 'primaryType']) ||
        _hasAliasConflict(document, const [
          'secondary_type',
          'secondaryType',
        ])) {
      return null;
    }
    final mainGroup = _firstString(document, const [
      'mainGroupKey',
      'mainGroup',
    ]);
    final category = _firstString(document, const ['categoryKey', 'category']);
    final subcategory = _firstString(document, const [
      'subCategoryKey',
      'subCategory',
    ]);
    final primaryType = _firstString(document, const [
      'primary_type',
      'primaryType',
    ]);
    final secondaryType = _firstString(document, const [
      'secondary_type',
      'secondaryType',
    ]);

    final candidates = <_StructuredCanonicalCandidate>[];
    final taxonomy = CanonicalResolver.resolveStructuredTaxonomy(document);
    if (taxonomy != null) {
      final kb = ClothingKnowledgeBase.findByCanonicalType(
        taxonomy.canonicalType,
      );
      if (kb != null) {
        candidates.add(
          _StructuredCanonicalCandidate(
            kb: kb,
            method: 'kb_prior:structured_taxonomy',
            sourceReference:
                'structured_taxonomy:'
                '${mainGroup ?? ''}|${category ?? ''}|${subcategory ?? ''}',
          ),
        );
      }
    }

    void addStructuredType(String? value, String field) {
      if (value == null) return;
      final kb =
          ClothingKnowledgeBase.findByCanonicalType(value) ??
          ClothingKnowledgeBase.findByAlias(value);
      if (kb == null) return;
      candidates.add(
        _StructuredCanonicalCandidate(
          kb: kb,
          method: 'kb_prior:structured_$field',
          sourceReference: 'structured_$field:$value',
        ),
      );
    }

    addStructuredType(primaryType, 'primary_type');
    addStructuredType(secondaryType, 'secondary_type');
    if (candidates.isEmpty) return null;
    final canonicalTypes = candidates
        .map((candidate) => candidate.kb.canonicalType)
        .toSet();
    if (canonicalTypes.length != 1) return null;
    return candidates.first;
  }

  static String? _firstString(
    Map<String, dynamic> document,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = document[key];
      if (value is! String) continue;
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  static bool _hasAliasConflict(
    Map<String, dynamic> document,
    List<String> keys,
  ) {
    final values = keys
        .map((key) => document[key])
        .whereType<String>()
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    return values.length > 1;
  }
}

final class _StructuredCanonicalCandidate {
  const _StructuredCanonicalCandidate({
    required this.kb,
    required this.method,
    required this.sourceReference,
  });

  final ClothingKbItem kb;
  final String method;
  final String sourceReference;
}
