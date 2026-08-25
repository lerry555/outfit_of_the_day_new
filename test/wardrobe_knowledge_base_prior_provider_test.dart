import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_knowledge_base_prior_provider.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_contract.dart';
import 'package:outfitofTheDay/domain/wardrobe_profile/wardrobe_profile_resolver.dart';

void main() {
  const provider = WardrobeKnowledgeBasePriorProvider();
  const resolver = WardrobeProfileResolver();
  final createdAt = DateTime.utc(2026, 7, 27);

  ProfileEvidence evidence({
    required String id,
    required String property,
    required Object value,
    required EvidenceSource source,
    EvidenceNature nature = EvidenceNature.inferred,
  }) => ProfileEvidence(
    id: id,
    property: property,
    value: value,
    source: source,
    nature: nature,
    confidence: 0.8,
    method: 'test',
    createdAt: createdAt,
  );

  test('KB defaults have explicit source, nature and type dependency', () {
    final canonical = evidence(
      id: 'canonical',
      property: WardrobeProfileProperty.canonicalType,
      value: 'hoodie',
      source: EvidenceSource.aiInference,
    );
    final priors = provider.provide(
      document: const {},
      existingEvidence: [canonical],
    );
    final warmth = priors.singleWhere(
      (item) => item.property == WardrobeProfileProperty.warmth,
    );

    expect(warmth.source, EvidenceSource.knowledgeBasePrior);
    expect(warmth.nature, EvidenceNature.defaulted);
    expect(warmth.dependsOnCanonicalType, 'hoodie');
  });

  test('specific evidence prevents a KB default for that property', () {
    final existing = [
      evidence(
        id: 'canonical',
        property: WardrobeProfileProperty.canonicalType,
        value: 'hoodie',
        source: EvidenceSource.aiInference,
      ),
      evidence(
        id: 'visual',
        property: WardrobeProfileProperty.warmth,
        value: 7,
        source: EvidenceSource.visualObservation,
        nature: EvidenceNature.observed,
      ),
    ];
    final priors = provider.provide(
      document: const {},
      existingEvidence: existing,
    );
    final profile = resolver.resolve(
      itemId: 'item-1',
      evidence: [...existing, ...priors],
    );

    expect(
      priors.where((item) => item.property == WardrobeProfileProperty.warmth),
      isEmpty,
    );
    expect(profile.capabilities.warmth.value, 7);
    expect(
      profile.capabilities.warmth.winningSource,
      EvidenceSource.visualObservation,
    );
  });

  test('visual, product and user evidence each block a KB prior', () {
    for (final source in [
      EvidenceSource.visualObservation,
      EvidenceSource.verifiedProductMetadata,
      EvidenceSource.userCorrection,
    ]) {
      final existing = [
        evidence(
          id: 'canonical-${source.name}',
          property: WardrobeProfileProperty.canonicalType,
          value: 'hoodie',
          source: EvidenceSource.aiInference,
        ),
        evidence(
          id: 'warmth-${source.name}',
          property: WardrobeProfileProperty.warmth,
          value: 7,
          source: source,
          nature: source == EvidenceSource.visualObservation
              ? EvidenceNature.observed
              : EvidenceNature.inferred,
        ),
      ];

      final priors = provider.provide(
        document: const {},
        existingEvidence: existing,
      );
      expect(
        priors.where((item) => item.property == WardrobeProfileProperty.warmth),
        isEmpty,
        reason: source.name,
      );
    }
  });

  test('defaulted legacy evidence can be replaced by explicit KB prior', () {
    final existing = [
      evidence(
        id: 'canonical',
        property: WardrobeProfileProperty.canonicalType,
        value: 'hoodie',
        source: EvidenceSource.legacyFallback,
        nature: EvidenceNature.defaulted,
      ),
      evidence(
        id: 'legacy-default',
        property: WardrobeProfileProperty.warmth,
        value: 7,
        source: EvidenceSource.legacyFallback,
        nature: EvidenceNature.defaulted,
      ),
    ];
    final priors = provider.provide(
      document: const {},
      existingEvidence: existing,
    );
    final profile = resolver.resolve(
      itemId: 'item-1',
      evidence: [...existing, ...priors],
    );

    expect(profile.capabilities.warmth.value, 5);
    expect(
      profile.capabilities.warmth.winningSource,
      EvidenceSource.knowledgeBasePrior,
    );
  });

  test('exact category and subcategory create an inferred canonical prior', () {
    final priors = provider.provide(
      document: const {
        'categoryKey': 'mikiny',
        'subCategoryKey': 'mikina_s_kapucnou',
      },
      existingEvidence: const [],
    );
    final canonical = priors.singleWhere(
      (item) => item.property == WardrobeProfileProperty.canonicalType,
    );

    expect(canonical.value, 'hoodie');
    expect(canonical.source, EvidenceSource.knowledgeBasePrior);
    expect(canonical.nature, EvidenceNature.inferred);
    expect(canonical.dependsOnCanonicalType, isNull);
  });

  test('category-only mapping remains unknown', () {
    final priors = provider.provide(
      document: const {'categoryKey': 'mikiny'},
      existingEvidence: const [],
    );

    expect(priors, isEmpty);
  });

  test('structured t-shirt mapping creates a transparent prior', () {
    final priors = provider.provide(
      document: const {
        'mainGroupKey': 'oblecenie',
        'categoryKey': 'tricka_topy',
        'subCategoryKey': 'tricko',
      },
      existingEvidence: const [],
    );

    final canonical = priors.singleWhere(
      (item) => item.property == WardrobeProfileProperty.canonicalType,
    );
    expect(canonical.value, 't_shirt');
    expect(canonical.method, 'kb_prior:structured_taxonomy');
    expect(
      canonical.sourceReference,
      'structured_taxonomy:oblecenie|tricka_topy|tricko',
    );
  });

  test('structured tank top mapping is unambiguous', () {
    final priors = provider.provide(
      document: const {
        'categoryKey': 'tricka_topy',
        'subCategoryKey': 'tielko',
      },
      existingEvidence: const [],
    );

    expect(
      priors
          .singleWhere(
            (item) => item.property == WardrobeProfileProperty.canonicalType,
          )
          .value,
      'tank_top',
    );
  });

  test('structured shorts mapping uses the existing taxonomy family', () {
    final priors = provider.provide(
      document: const {
        'categoryKey': 'sortky_sukne',
        'subCategoryKey': 'sortky',
      },
      existingEvidence: const [],
    );

    expect(
      priors
          .singleWhere(
            (item) => item.property == WardrobeProfileProperty.canonicalType,
          )
          .value,
      'shorts',
    );
  });

  test('structured hoodie and sweatshirt mappings stay taxonomy-only', () {
    for (final entry in const {
      'mikina_s_kapucnou': 'hoodie',
      'mikina_klasicka': 'sweatshirt',
    }.entries) {
      final priors = provider.provide(
        document: {
          'name': 'text that must not be inspected',
          'categoryKey': 'mikiny',
          'subCategoryKey': entry.key,
        },
        existingEvidence: const [],
      );
      expect(
        priors
            .singleWhere(
              (item) => item.property == WardrobeProfileProperty.canonicalType,
            )
            .value,
        entry.value,
      );
    }
  });

  test('structured footwear subtype maps without a display name', () {
    final priors = provider.provide(
      document: const {
        'categoryKey': 'cizmy',
        'subCategoryKey': 'cizmy_clenkove',
      },
      existingEvidence: const [],
    );

    expect(
      priors
          .singleWhere(
            (item) => item.property == WardrobeProfileProperty.canonicalType,
          )
          .value,
      'chelsea_boots',
    );
  });

  test('generic pants and jacket remain unknown', () {
    for (final document in const [
      {'categoryKey': 'nohavice_rifle', 'subCategoryKey': 'nohavice'},
      {'categoryKey': 'bundy_kabaty', 'subCategoryKey': 'bunda'},
    ]) {
      expect(
        provider.provide(document: document, existingEvidence: const []),
        isEmpty,
      );
    }
  });

  test('conflicting structured taxonomy and primary type remain unknown', () {
    final priors = provider.provide(
      document: const {
        'categoryKey': 'tricka_topy',
        'subCategoryKey': 'tielko',
        'primary_type': 'hoodie',
      },
      existingEvidence: const [],
    );

    expect(priors, isEmpty);
  });

  test('conflicting structured aliases remain unknown', () {
    final priors = provider.provide(
      document: const {
        'categoryKey': 'mikiny',
        'category': 'bundy_kabaty',
        'subCategoryKey': 'mikina_na_zips',
        'subCategory': 'bunda_prechodna',
      },
      existingEvidence: const [],
    );

    expect(priors, isEmpty);
  });

  test('item name cannot change a structured mapping', () {
    const structured = {
      'categoryKey': 'tricka_topy',
      'subCategoryKey': 'tricko',
    };
    final first = provider.provide(
      document: const {...structured, 'name': 'Zimná bunda'},
      existingEvidence: const [],
    );
    final second = provider.provide(
      document: const {...structured, 'name': 'Bežecké tenisky'},
      existingEvidence: const [],
    );

    expect(
      first.map((item) => item.toMap()).toList(),
      second.map((item) => item.toMap()).toList(),
    );
  });

  test('provider output is deterministic', () {
    const document = {
      'categoryKey': 'mikiny',
      'subCategoryKey': 'mikina_s_kapucnou',
    };

    final first = provider
        .provide(document: document, existingEvidence: const [])
        .map((item) => item.toMap())
        .toList();
    final second = provider
        .provide(document: document, existingEvidence: const [])
        .map((item) => item.toMap())
        .toList();

    expect(second, first);
  });
}
