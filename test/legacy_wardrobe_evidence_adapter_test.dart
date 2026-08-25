import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/legacy_wardrobe_evidence_adapter.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';

void main() {
  const adapter = LegacyWardrobeEvidenceAdapter();
  final timestamp = DateTime.utc(2026, 7, 27, 12);

  List<ProfileEvidence> adapt(Map<String, dynamic> document) =>
      adapter.adapt(document, evidenceTimestamp: timestamp);

  ProfileEvidence evidenceFor(
    List<ProfileEvidence> evidence,
    String property, {
    String? sourceReference,
  }) => evidence.singleWhere(
    (item) =>
        item.property == property &&
        (sourceReference == null || item.sourceReference == sourceReference),
  );

  test('adapts a complete modern legacy document without resolving it', () {
    final evidence = adapt({
      'name': 'Čierna mikina',
      'brand': 'Nike',
      'canonical_type': 'hoodie',
      'mainGroupKey': 'oblecenie',
      'categoryKey': 'mikiny',
      'subCategoryKey': 'mikina_s_kapucnou',
      'colors': ['čierna'],
      'baseColors': ['black'],
      'styles': ['športový'],
      'patterns': ['bez vzoru'],
      'seasons': ['jeseň', 'zima'],
      'fit': 'regular',
      'vibe': 'sporty',
      'occasion_fit': ['voľný čas'],
      'material_feel': 'soft cotton',
      'visual_description': 'Čierna mikina s kapucňou.',
      'layer_role': 'mid_layer',
      'warmth_level': 6,
      'formality': 2,
      'primary_type': 'mikina',
      'secondary_type': 'športová bunda',
      'confidence': 91,
    });

    expect(
      evidenceFor(evidence, WardrobeProfileProperty.canonicalType).value,
      'hoodie',
    );
    expect(evidenceFor(evidence, WardrobeProfileProperty.warmth).value, 6);
    expect(
      evidenceFor(evidence, WardrobeProfileProperty.materialFeel).value,
      'soft cotton',
    );
    expect(evidenceFor(evidence, WardrobeProfileProperty.occasions).value, [
      'voľný čas',
    ]);
    expect(
      evidence.every((item) => item.source == EvidenceSource.legacyFallback),
      isTrue,
    );
    expect(
      evidence.every((item) => item.nature == EvidenceNature.unknown),
      isTrue,
    );
    expect(evidence.every((item) => item.confidence == 0), isTrue);
  });

  test('adapts a very old category/subcategory/name document', () {
    final evidence = adapt({
      'name': 'Modré rifle',
      'category': 'nohavice',
      'subCategory': 'rifle',
    });

    expect(evidence, hasLength(3));
    expect(
      evidenceFor(evidence, WardrobeProfileProperty.displayName).value,
      'Modré rifle',
    );
    expect(
      evidenceFor(evidence, WardrobeProfileProperty.category).value,
      'nohavice',
    );
    expect(
      evidenceFor(evidence, WardrobeProfileProperty.subcategory).value,
      'rifle',
    );
  });

  test('does not invent canonical type when it is missing', () {
    final evidence = adapt({
      'name': 'Neznámy kus',
      'categoryKey': 'vrchne_diely',
      'subCategoryKey': 'ine',
    });

    expect(
      evidence.where(
        (item) => item.property == WardrobeProfileProperty.canonicalType,
      ),
      isEmpty,
    );
  });

  test('keeps canonical type, warmth and formality as separate evidence', () {
    final evidence = adapt({
      'canonicalType': 'softshell_jacket',
      'warmth_level': '4',
      'formality': 3.0,
    });

    expect(
      evidenceFor(evidence, WardrobeProfileProperty.canonicalType).value,
      'softshell_jacket',
    );
    expect(evidenceFor(evidence, WardrobeProfileProperty.warmth).value, 4);
    expect(evidenceFor(evidence, WardrobeProfileProperty.formality).value, 3);
  });

  test('preserves conflict between top-level and hidden AI metadata', () {
    final evidence = adapt({
      'canonical_type': 'softshell_jacket',
      'hiddenAiMetadata': {'canonical_type': 'hoodie', 'confidence': 82},
    });

    final topLevel = evidenceFor(
      evidence,
      WardrobeProfileProperty.canonicalType,
      sourceReference: 'top_level.canonical_type',
    );
    final hidden = evidenceFor(
      evidence,
      WardrobeProfileProperty.canonicalType,
      sourceReference: 'hiddenAiMetadata.canonical_type',
    );

    expect(topLevel.value, 'softshell_jacket');
    expect(topLevel.source, EvidenceSource.legacyFallback);
    expect(topLevel.nature, EvidenceNature.unknown);
    expect(hidden.value, 'hoodie');
    expect(hidden.source, EvidenceSource.aiInference);
    expect(hidden.nature, EvidenceNature.inferred);
    expect(hidden.confidence, closeTo(0.82, 0.0001));
  });

  test('missing and explicit unknown values produce no evidence', () {
    final evidence = adapt({
      'canonical_type': '',
      'fit': 'unknown',
      'colors': <String>[],
      'warmth_level': null,
    });

    expect(evidence, isEmpty);
  });

  test('ignores malformed legacy value types instead of coercing them', () {
    final evidence = adapt({
      'name': 42,
      'colors': 'black',
      'styles': ['casual', 7],
      'warmth_level': {'value': 5},
      'formality': 12,
      'hiddenAiMetadata': {
        1: 'non-string map key',
        'canonical_type': true,
        'patterns': {'striped': true},
      },
    });

    expect(evidence, isEmpty);
  });

  test('same input and timestamp produce deterministic ordered output', () {
    final document = <String, dynamic>{
      'name': 'Biele tenisky',
      'canonical_type': 'fashion_sneakers',
      'colors': ['biela'],
      'aiMetadata': {'canonical_type': 'running_shoes', 'confidence': 0.7},
    };

    final first = adapt(document).map((item) => item.toMap()).toList();
    final second = adapt(document).map((item) => item.toMap()).toList();

    expect(second, first);
  });

  test('KB migration markers downgrade generated fields to defaults', () {
    final evidence = adapt({
      'canonical_type': 'hoodie',
      'layer_role': 'mid_layer',
      'warmth_level': 5,
      'formality': 2,
      'kb_migration_version': 2,
    });

    for (final property in [
      WardrobeProfileProperty.canonicalType,
      WardrobeProfileProperty.layerRole,
      WardrobeProfileProperty.warmth,
      WardrobeProfileProperty.formality,
    ]) {
      final item = evidenceFor(evidence, property);
      expect(item.source, EvidenceSource.legacyFallback);
      expect(item.nature, EvidenceNature.defaulted);
      expect(
        item.method,
        contains(
          'quality=${LegacyEvidenceQuality.probableAutomaticDefault.name}',
        ),
      );
    }
  });

  test('unmarked top-level item value remains usable with unknown origin', () {
    final item = evidenceFor(
      adapt({'canonical_type': 'hoodie', 'warmth_level': 7}),
      WardrobeProfileProperty.warmth,
    );

    expect(item.source, EvidenceSource.legacyFallback);
    expect(item.nature, EvidenceNature.unknown);
    expect(
      item.method,
      contains('quality=${LegacyEvidenceQuality.unknownOrigin.name}'),
    );
  });

  test('hidden AI KB fingerprint is not presented as item observation', () {
    final evidence = adapt({
      'hiddenAiMetadata': {
        'canonical_type': 'hoodie',
        'layer_role': 'mid_layer',
        'warmth_level': 5,
        'formality': 2,
        'confidence': 0.95,
      },
    });

    final canonical = evidenceFor(
      evidence,
      WardrobeProfileProperty.canonicalType,
    );
    expect(canonical.source, EvidenceSource.aiInference);
    expect(canonical.nature, EvidenceNature.inferred);

    for (final property in [
      WardrobeProfileProperty.layerRole,
      WardrobeProfileProperty.warmth,
      WardrobeProfileProperty.formality,
    ]) {
      final item = evidenceFor(evidence, property);
      expect(item.source, EvidenceSource.legacyFallback);
      expect(item.nature, EvidenceNature.defaulted);
      expect(item.dependsOnCanonicalType, 'hoodie');
    }
  });
}
