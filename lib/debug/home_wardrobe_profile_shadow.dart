import 'package:flutter/foundation.dart';

import '../domain/wardrobe_profile/legacy_wardrobe_evidence_adapter.dart';
import '../domain/wardrobe_profile/wardrobe_profile_contract.dart';
import '../domain/wardrobe_profile/wardrobe_profile_engine_adapter.dart';
import '../domain/wardrobe_profile/wardrobe_knowledge_base_prior_provider.dart';
import '../domain/wardrobe_profile/wardrobe_profile_resolver.dart';
import '../utils/home_debug_logging.dart';

enum HomeWardrobeShadowDifference {
  same,
  different,
  oldKnownNewUnknown,
  oldFallbackNewUnknown,
  oldValueNewResolvedSpecific,
}

final class HomeWardrobeShadowFieldReport {
  const HomeWardrobeShadowFieldReport({
    required this.property,
    required this.oldValue,
    required this.newValue,
    required this.difference,
  });

  final String property;
  final Object? oldValue;
  final Object? newValue;
  final HomeWardrobeShadowDifference difference;

  bool get differs => difference != HomeWardrobeShadowDifference.same;
}

final class HomeWardrobeShadowItemReport {
  const HomeWardrobeShadowItemReport({
    required this.itemId,
    required this.fields,
    required this.canonicalConflict,
    this.kbPriorWinner = false,
    this.structuredCanonicalPrior,
    this.degradedLegacyDefaults = 0,
    this.unresolvedFields = 0,
    this.error,
  });

  final String itemId;
  final List<HomeWardrobeShadowFieldReport> fields;
  final bool canonicalConflict;
  final bool kbPriorWinner;
  final String? structuredCanonicalPrior;
  final int degradedLegacyDefaults;
  final int unresolvedFields;
  final String? error;

  bool get hasDifference =>
      error != null || fields.any((field) => field.differs);
  bool get hasOldFallbackNewUnknown => fields.any(
    (field) =>
        field.difference == HomeWardrobeShadowDifference.oldFallbackNewUnknown,
  );

  HomeWardrobeShadowFieldReport field(String property) =>
      fields.singleWhere((field) => field.property == property);

  String toLogLine() {
    if (error != null) return '[M11_SHADOW_ITEM] id=$itemId error=$error';
    final differences = fields
        .where((field) => field.differs)
        .map(
          (field) =>
              '${field.property}:${field.difference.name}'
              '(old=${field.oldValue},new=${field.newValue})',
        )
        .join(';');
    return '[M11_SHADOW_ITEM] id=$itemId differences=$differences '
        'canonicalConflict=$canonicalConflict kbPriorWinner=$kbPriorWinner '
        'structuredCanonicalPrior=${structuredCanonicalPrior ?? 'none'} '
        'legacyDefaultsDegraded=$degradedLegacyDefaults '
        'unresolvedFields=$unresolvedFields';
  }
}

final class HomeWardrobeShadowSummary {
  const HomeWardrobeShadowSummary({
    required this.analyzedItems,
    required this.fullyMatchingItems,
    required this.itemsWithDifference,
    required this.oldFallbackNewUnknownItems,
    required this.canonicalConflicts,
    required this.warmthDifferences,
    required this.layerRoleDifferences,
    required this.formalityDifferences,
    required this.kbPriorWinnerItems,
    required this.structuredCanonicalPriorWinnerItems,
    required this.degradedLegacyDefaultItems,
    required this.degradedLegacyDefaults,
    required this.unresolvedFields,
    required this.failedItems,
  });

  final int analyzedItems;
  final int fullyMatchingItems;
  final int itemsWithDifference;
  final int oldFallbackNewUnknownItems;
  final int canonicalConflicts;
  final int warmthDifferences;
  final int layerRoleDifferences;
  final int formalityDifferences;
  final int kbPriorWinnerItems;
  final int structuredCanonicalPriorWinnerItems;
  final int degradedLegacyDefaultItems;
  final int degradedLegacyDefaults;
  final int unresolvedFields;
  final int failedItems;

  String toLogLine() =>
      '[M11_SHADOW_SUMMARY] analyzed=$analyzedItems '
      'matching=$fullyMatchingItems different=$itemsWithDifference '
      'oldFallbackNewUnknown=$oldFallbackNewUnknownItems '
      'canonicalConflicts=$canonicalConflicts '
      'warmthDifferences=$warmthDifferences '
      'layerRoleDifferences=$layerRoleDifferences '
      'formalityDifferences=$formalityDifferences '
      'kbPriorWinnerItems=$kbPriorWinnerItems '
      'structuredCanonicalPriorWinners=$structuredCanonicalPriorWinnerItems '
      'legacyDefaultItems=$degradedLegacyDefaultItems '
      'legacyDefaultsDegraded=$degradedLegacyDefaults '
      'unresolvedFields=$unresolvedFields failed=$failedItems';
}

final class HomeWardrobeShadowRun {
  const HomeWardrobeShadowRun({required this.items, required this.summary});

  final List<HomeWardrobeShadowItemReport> items;
  final HomeWardrobeShadowSummary summary;
}

typedef HomeWardrobeShadowProjector =
    HomeWardrobeShadowProjection Function(Map<String, dynamic> raw);

final class HomeWardrobeProfileShadowRunner {
  const HomeWardrobeProfileShadowRunner({
    this.legacyAdapter = const LegacyWardrobeEvidenceAdapter(),
    this.kbPriorProvider = const WardrobeKnowledgeBasePriorProvider(),
    this.resolver = const WardrobeProfileResolver(),
    this.engineAdapter = const WardrobeProfileEngineAdapter(),
  });

  final LegacyWardrobeEvidenceAdapter legacyAdapter;
  final WardrobeKnowledgeBasePriorProvider kbPriorProvider;
  final WardrobeProfileResolver resolver;
  final WardrobeProfileEngineAdapter engineAdapter;

  static const int maxLoggedItemDifferences = 20;

  HomeWardrobeShadowRun compare({
    required List<Map<String, dynamic>> rawItems,
    required List<Map<String, dynamic>> productionItems,
    HomeWardrobeShadowProjector? projector,
  }) {
    final productionById = <String, Map<String, dynamic>>{
      for (final item in productionItems)
        if (_itemId(item).isNotEmpty) _itemId(item): item,
    };
    final reports = <HomeWardrobeShadowItemReport>[];

    for (final raw in rawItems) {
      final itemId = _itemId(raw);
      try {
        if (itemId.isEmpty) {
          throw const FormatException('missing_item_id');
        }
        final production = productionById[itemId];
        if (production == null) {
          throw const FormatException('missing_production_item');
        }
        final projection = projector?.call(raw) ?? _project(raw);
        reports.add(
          _compareItem(
            itemId: itemId,
            raw: raw,
            production: production,
            shadow: projection.engineMap,
            profile: projection.profile,
          ),
        );
      } catch (error) {
        reports.add(
          HomeWardrobeShadowItemReport(
            itemId: itemId.isEmpty ? '<missing-id>' : itemId,
            fields: const [],
            canonicalConflict: false,
            error: error.runtimeType.toString(),
          ),
        );
      }
    }

    reports.sort((left, right) => left.itemId.compareTo(right.itemId));
    return HomeWardrobeShadowRun(
      items: List<HomeWardrobeShadowItemReport>.unmodifiable(reports),
      summary: _summarize(reports),
    );
  }

  void runAndLog({
    required List<Map<String, dynamic>> rawItems,
    required List<Map<String, dynamic>> productionItems,
  }) {
    if (!kDebugMode || !kHomeWardrobeProfileShadowEnabled) return;
    try {
      final run = compare(rawItems: rawItems, productionItems: productionItems);
      debugPrint(run.summary.toLogLine());
      final differing = run.items.where((item) => item.hasDifference).toList();
      for (final item in differing.take(maxLoggedItemDifferences)) {
        debugPrint(item.toLogLine());
      }
      if (differing.length > maxLoggedItemDifferences) {
        debugPrint(
          '[M11_SHADOW_ITEMS_TRUNCATED] shown=$maxLoggedItemDifferences '
          'total=${differing.length}',
        );
      }
    } catch (error) {
      // Shadow diagnostics must never affect Home.
      debugPrint('[M11_SHADOW_FAILURE] error=${error.runtimeType}');
    }
  }

  HomeWardrobeShadowProjection _project(Map<String, dynamic> raw) {
    final itemId = _itemId(raw);
    final legacyEvidence = legacyAdapter.adapt(raw);
    final evidence = <ProfileEvidence>[
      ...legacyEvidence,
      ...kbPriorProvider.provide(
        document: raw,
        existingEvidence: legacyEvidence,
      ),
    ];
    final profile = resolver.resolve(itemId: itemId, evidence: evidence);
    return HomeWardrobeShadowProjection(
      profile: profile,
      engineMap: engineAdapter.toEngineMap(profile),
    );
  }

  HomeWardrobeShadowItemReport _compareItem({
    required String itemId,
    required Map<String, dynamic> raw,
    required Map<String, dynamic> production,
    required Map<String, dynamic> shadow,
    required ResolvedWardrobeItemProfile profile,
  }) {
    final fallbacks = _compatibilityFallbacks(shadow);
    final fields = <HomeWardrobeShadowFieldReport>[
      _compareField(
        property: WardrobeProfileProperty.canonicalType,
        oldValue: _first(production, const ['canonical_type', 'canonicalType']),
        newValue: _first(shadow, const ['canonical_type', 'canonicalType']),
        newField: profile.identity.canonicalType,
        delegatedFallback: fallbacks.containsKey('canonical_type'),
        oldFallback:
            production['home_kb_applied'] == true ||
            !_hasAny(raw, const ['canonical_type', 'canonicalType']),
      ),
      _compareField(
        property: WardrobeProfileProperty.category,
        oldValue: _first(production, const ['categoryKey', 'category']),
        newValue: _first(shadow, const ['categoryKey', 'category']),
        newField: profile.identity.category,
        oldFallback:
            _oldNormalizerFallback(production) ||
            !_hasAny(raw, const ['categoryKey', 'category']),
      ),
      _compareField(
        property: WardrobeProfileProperty.subcategory,
        oldValue: _first(production, const ['subCategoryKey', 'subCategory']),
        newValue: _first(shadow, const ['subCategoryKey', 'subCategory']),
        newField: profile.identity.subcategory,
        oldFallback:
            _oldNormalizerFallback(production) ||
            !_hasAny(raw, const ['subCategoryKey', 'subCategory']),
      ),
      _compareField(
        property: WardrobeProfileProperty.layerRole,
        oldValue: _first(production, const ['layer_role', 'layerRole']),
        newValue: _first(shadow, const ['layer_role', 'layerRole']),
        newField: profile.capabilities.layerRole,
        delegatedFallback: fallbacks.containsKey('layer_role'),
        oldFallback:
            _oldNormalizerFallback(production) ||
            !_hasAny(raw, const ['layer_role', 'layerRole']),
      ),
      _compareField(
        property: WardrobeProfileProperty.warmth,
        oldValue: _first(production, const ['warmth_level', 'warmthLevel']),
        newValue: _first(shadow, const ['warmth_level', 'warmthLevel']),
        newField: profile.capabilities.warmth,
        delegatedFallback: fallbacks.containsKey('warmth_level'),
        oldFallback:
            _oldNormalizerFallback(production) ||
            !_hasAny(raw, const ['warmth_level', 'warmthLevel']),
      ),
      _compareField(
        property: WardrobeProfileProperty.formality,
        oldValue: production['formality'],
        newValue: shadow['formality'],
        newField: profile.capabilities.formality,
        oldFallback:
            _oldNormalizerFallback(production) ||
            !_hasAny(raw, const ['formality']),
      ),
      _compareField(
        property: WardrobeProfileProperty.colors,
        oldValue: _first(production, const ['colors', 'color']),
        newValue: _first(shadow, const ['colors', 'color']),
        newField: profile.visual.colors,
      ),
      _compareField(
        property: WardrobeProfileProperty.styles,
        oldValue: production['styles'],
        newValue: shadow['styles'],
        newField: profile.visual.styles,
      ),
      _compareField(
        property: WardrobeProfileProperty.seasons,
        oldValue: _first(production, const ['seasons', 'season']),
        newValue: _first(shadow, const ['seasons', 'season']),
        newField: profile.suitability.seasons,
      ),
    ];

    final canonicalWinner = _winningEvidence(
      profile.identity.canonicalType,
      profile.evidence,
    );
    return HomeWardrobeShadowItemReport(
      itemId: itemId,
      fields: List<HomeWardrobeShadowFieldReport>.unmodifiable(fields),
      canonicalConflict: profile.identity.canonicalType.hasConflict,
      kbPriorWinner: _trackedResolvedFields(profile).any(
        (field) =>
            field.isKnown &&
            field.winningSource == EvidenceSource.knowledgeBasePrior,
      ),
      structuredCanonicalPrior:
          canonicalWinner?.method.startsWith('kb_prior:structured_') == true
          ? canonicalWinner?.sourceReference
          : null,
      degradedLegacyDefaults: profile.evidence
          .where(
            (item) =>
                item.nature == EvidenceNature.defaulted &&
                item.method.contains(
                  'quality=${LegacyEvidenceQuality.probableAutomaticDefault.name}',
                ),
          )
          .length,
      unresolvedFields: _trackedResolvedFields(
        profile,
      ).where((field) => !field.isKnown).length,
    );
  }

  HomeWardrobeShadowFieldReport _compareField({
    required String property,
    required Object? oldValue,
    required Object? newValue,
    required ResolvedField<Object?> newField,
    bool delegatedFallback = false,
    bool oldFallback = false,
  }) {
    final oldNormalized = _comparisonValue(oldValue);
    final newNormalized = _comparisonValue(newValue);
    final oldKnown = oldNormalized != null;
    final newKnown = newNormalized != null;
    final difference = switch ((oldKnown, newKnown)) {
      (false, false) => HomeWardrobeShadowDifference.same,
      (true, false) when delegatedFallback || oldFallback =>
        HomeWardrobeShadowDifference.oldFallbackNewUnknown,
      (true, false) => HomeWardrobeShadowDifference.oldKnownNewUnknown,
      (false, true) => HomeWardrobeShadowDifference.oldValueNewResolvedSpecific,
      (true, true) when oldNormalized == newNormalized =>
        HomeWardrobeShadowDifference.same,
      (true, true) when _isSpecific(newField) =>
        HomeWardrobeShadowDifference.oldValueNewResolvedSpecific,
      _ => HomeWardrobeShadowDifference.different,
    };
    return HomeWardrobeShadowFieldReport(
      property: property,
      oldValue: oldValue,
      newValue: newValue,
      difference: difference,
    );
  }

  HomeWardrobeShadowSummary _summarize(
    List<HomeWardrobeShadowItemReport> reports,
  ) {
    int differencesFor(String property) => reports
        .where(
          (item) =>
              item.error == null &&
              item.field(property).difference !=
                  HomeWardrobeShadowDifference.same,
        )
        .length;

    return HomeWardrobeShadowSummary(
      analyzedItems: reports.where((item) => item.error == null).length,
      fullyMatchingItems: reports
          .where((item) => item.error == null && !item.hasDifference)
          .length,
      itemsWithDifference: reports.where((item) => item.hasDifference).length,
      oldFallbackNewUnknownItems: reports
          .where((item) => item.error == null && item.hasOldFallbackNewUnknown)
          .length,
      canonicalConflicts: reports
          .where((item) => item.canonicalConflict)
          .length,
      warmthDifferences: differencesFor(WardrobeProfileProperty.warmth),
      layerRoleDifferences: differencesFor(WardrobeProfileProperty.layerRole),
      formalityDifferences: differencesFor(WardrobeProfileProperty.formality),
      kbPriorWinnerItems: reports.where((item) => item.kbPriorWinner).length,
      structuredCanonicalPriorWinnerItems: reports
          .where((item) => item.structuredCanonicalPrior != null)
          .length,
      degradedLegacyDefaultItems: reports
          .where((item) => item.degradedLegacyDefaults > 0)
          .length,
      degradedLegacyDefaults: reports.fold(
        0,
        (sum, item) => sum + item.degradedLegacyDefaults,
      ),
      unresolvedFields: reports.fold(
        0,
        (sum, item) => sum + item.unresolvedFields,
      ),
      failedItems: reports.where((item) => item.error != null).length,
    );
  }

  static bool _oldNormalizerFallback(Map<String, dynamic> item) =>
      item['home_kb_applied'] == true || item['home_legacy_fallback'] == true;

  static bool _isSpecific(ResolvedField<Object?> field) =>
      field.isKnown &&
      field.winningSource != EvidenceSource.knowledgeBasePrior &&
      field.winningSource != EvidenceSource.legacyFallback;

  static ProfileEvidence? _winningEvidence(
    ResolvedField<Object?> field,
    Iterable<ProfileEvidence> evidence,
  ) {
    if (field.winningEvidenceIds.isEmpty) return null;
    final winningIds = field.winningEvidenceIds.toSet();
    for (final item in evidence) {
      if (winningIds.contains(item.id)) return item;
    }
    return null;
  }

  static List<ResolvedField<Object?>> _trackedResolvedFields(
    ResolvedWardrobeItemProfile profile,
  ) => <ResolvedField<Object?>>[
    profile.identity.canonicalType,
    profile.identity.category,
    profile.identity.subcategory,
    profile.capabilities.layerRole,
    profile.capabilities.warmth,
    profile.capabilities.formality,
    profile.visual.colors,
    profile.visual.styles,
    profile.suitability.seasons,
  ];

  static Object? _first(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (_comparisonValue(value) != null) return value;
    }
    return null;
  }

  static bool _hasAny(Map<String, dynamic> map, List<String> keys) =>
      keys.any((key) => _comparisonValue(map[key]) != null);

  static String? _comparisonValue(Object? value) {
    if (value == null) return null;
    if (value is Iterable && value is! String) {
      final entries =
          value
              .map((item) => item.toString().trim().toLowerCase())
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      return entries.isEmpty ? null : entries.join('|');
    }
    final text = value.toString().trim().toLowerCase();
    return text.isEmpty ? null : text;
  }

  static Map<String, String> _compatibilityFallbacks(
    Map<String, dynamic> shadow,
  ) {
    final metadata = shadow[WardrobeProfileEngineAdapter.debugMetadataKey];
    if (metadata is! Map) return const {};
    final raw = metadata['delegatedFallbacks'];
    if (raw is! Map) return const {};
    return <String, String>{
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }

  static String _itemId(Map<String, dynamic> item) =>
      (item['id'] ?? item['documentId'] ?? '').toString().trim();
}

final class HomeWardrobeShadowProjection {
  const HomeWardrobeShadowProjection({
    required this.profile,
    required this.engineMap,
  });

  final ResolvedWardrobeItemProfile profile;
  final Map<String, dynamic> engineMap;
}
