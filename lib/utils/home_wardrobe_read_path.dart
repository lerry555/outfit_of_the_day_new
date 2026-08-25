import 'package:flutter/foundation.dart';

import '../domain/wardrobe_profile/legacy_wardrobe_evidence_adapter.dart';
import '../domain/wardrobe_profile/wardrobe_profile_contract.dart';
import '../domain/wardrobe_profile/wardrobe_profile_engine_adapter.dart';
import '../domain/wardrobe_profile/wardrobe_knowledge_base_prior_provider.dart';
import '../domain/wardrobe_profile/wardrobe_profile_resolver.dart';
import '../domain/wardrobe_v2/wardrobe_ontology_v2.dart';
import '../domain/wardrobe_v2/wardrobe_v2_resolver.dart';
import 'home_debug_logging.dart';
import 'home_wardrobe_normalizer.dart';

typedef HomeLegacyWardrobeNormalizer =
    List<Map<String, dynamic>> Function(List<Map<String, dynamic>> rawItems);

typedef HomeResolvedItemProjector =
    HomeResolvedWardrobeItem Function(Map<String, dynamic> raw);

final class HomeResolvedWardrobeItem {
  const HomeResolvedWardrobeItem({
    required this.profile,
    required this.engineMap,
  });

  final ResolvedWardrobeItemProfile profile;
  final Map<String, dynamic> engineMap;
}

final class HomeWardrobeReadPathResult {
  const HomeWardrobeReadPathResult({
    required this.items,
    required this.wardrobeSignature,
    required this.usedResolvedProfiles,
    required this.wholePipelineFallback,
    required this.resolvedWithoutFallback,
    required this.compatibilityFallbackItems,
    required this.canonicalUnknownItems,
    required this.fallbackProperties,
  });

  final List<Map<String, dynamic>> items;
  final String wardrobeSignature;
  final bool usedResolvedProfiles;
  final bool wholePipelineFallback;
  final int resolvedWithoutFallback;
  final int compatibilityFallbackItems;
  final int canonicalUnknownItems;
  final Map<String, int> fallbackProperties;

  List<String> get itemIds => items
      .map(HomeWardrobeReadPath.itemId)
      .where((id) => id.isNotEmpty)
      .toList(growable: false);

  String toLogLine() =>
      '[M11_HOME_READ_PATH] enabled=$usedResolvedProfiles '
      'wholeFallback=$wholePipelineFallback items=${items.length} '
      'resolvedWithoutFallback=$resolvedWithoutFallback '
      'compatibilityFallbackItems=$compatibilityFallbackItems '
      'canonicalUnknownItems=$canonicalUnknownItems '
      'fallbackProperties=${HomeWardrobeReadPath._stableMap(fallbackProperties)} '
      'signature=$wardrobeSignature';
}

/// Controlled Home projection from raw wardrobe documents to the current
/// Outfit Engine map contract.
///
/// Resolved maps are never passed through [HomeWardrobeNormalizer]. Unknown
/// decision-critical properties delegate the complete item to the legacy path
/// and carry explicit compatibility metadata.
final class HomeWardrobeReadPath {
  const HomeWardrobeReadPath({
    this.useResolvedProfiles = kUseResolvedWardrobeProfilesInHome,
    this.legacyNormalizer = _defaultLegacyNormalizer,
    this.itemProjector,
  });

  final bool useResolvedProfiles;
  final HomeLegacyWardrobeNormalizer legacyNormalizer;
  final HomeResolvedItemProjector? itemProjector;

  static const List<String> decisionCriticalProperties = <String>[
    WardrobeProfileProperty.canonicalType,
    WardrobeProfileProperty.warmth,
    WardrobeProfileProperty.formality,
    WardrobeProfileProperty.layerRole,
  ];

  static const Set<String> _profileControlledKeys = <String>{
    'name',
    'brand',
    'canonical_type',
    'canonicalType',
    'mainGroupKey',
    'mainGroup',
    'categoryKey',
    'category',
    'subCategoryKey',
    'subCategory',
    'layer_role',
    'layerRole',
    'warmth_level',
    'warmthLevel',
    'formality',
    'colors',
    'color',
    'baseColors',
    'styles',
    'patterns',
    'fit',
    'vibe',
    'seasons',
    'season',
    'occasion_fit',
    'occasionFit',
  };

  HomeWardrobeReadPathResult build(List<Map<String, dynamic>> rawItems) {
    final rawCopies = rawItems
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    if (!useResolvedProfiles) {
      final legacy = legacyNormalizer(rawCopies);
      return HomeWardrobeReadPathResult(
        items: _immutableItems(legacy),
        wardrobeSignature: legacyWardrobeSignature(rawItems),
        usedResolvedProfiles: false,
        wholePipelineFallback: false,
        resolvedWithoutFallback: 0,
        compatibilityFallbackItems: 0,
        canonicalUnknownItems: 0,
        fallbackProperties: const <String, int>{},
      );
    }

    final ontologyV2 = WardrobeOntologyV2.cached;
    if (ontologyV2 != null) {
      return _buildV2(rawCopies, ontologyV2);
    }

    try {
      final legacy = legacyNormalizer(rawCopies);
      final legacyById = <String, Map<String, dynamic>>{
        for (final item in legacy)
          if (itemId(item).isNotEmpty) itemId(item): item,
      };
      final output = <Map<String, dynamic>>[];
      final fingerprints = <String>[];
      final fallbackCounts = <String, int>{};
      var resolvedWithoutFallback = 0;
      var fallbackItems = 0;
      var canonicalUnknownItems = 0;

      for (final raw in rawCopies) {
        final id = itemId(raw);
        try {
          if (id.isEmpty) throw const FormatException('missing_item_id');
          final resolved = itemProjector?.call(raw) ?? _project(raw);
          final unknownCritical = _unknownCritical(resolved.profile);
          if (!resolved.profile.identity.canonicalType.isKnown) {
            canonicalUnknownItems++;
          }

          if (unknownCritical.isEmpty) {
            final projected = <String, dynamic>{...raw};
            for (final key in _profileControlledKeys) {
              projected.remove(key);
            }
            projected.addAll(resolved.engineMap);
            output.add(Map<String, dynamic>.unmodifiable(projected));
            resolvedWithoutFallback++;
          } else {
            final legacyItem = legacyById[id];
            if (legacyItem == null) {
              throw const FormatException('missing_legacy_item');
            }
            output.add(
              _legacyFallbackItem(
                legacyItem: legacyItem,
                resolvedMap: resolved.engineMap,
                properties: unknownCritical,
                reason: 'decision_critical_unknown',
              ),
            );
            fallbackItems++;
            for (final property in unknownCritical) {
              fallbackCounts.update(
                property,
                (count) => count + 1,
                ifAbsent: () => 1,
              );
            }
          }
          fingerprints.add(
            _itemFingerprint(
              raw: raw,
              profile: resolved.profile,
              resolvedMap: resolved.engineMap,
              effectiveMap: output.last,
              fallbackProperties: unknownCritical,
            ),
          );
        } catch (error) {
          final legacyItem = legacyById[id];
          if (legacyItem == null) rethrow;
          const failureProperty = 'pipeline.itemFailure';
          output.add(
            _legacyFallbackItem(
              legacyItem: legacyItem,
              resolvedMap: const <String, dynamic>{},
              properties: const <String>[failureProperty],
              reason: 'item_pipeline_failure:${error.runtimeType}',
            ),
          );
          fallbackItems++;
          fallbackCounts.update(
            failureProperty,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
          fingerprints.add(
            _fallbackFingerprint(raw, output.last, failureProperty),
          );
        }
      }

      fingerprints.sort();
      final signature =
          'resolved-v${WardrobeProfileVersions.schema}.'
          '${WardrobeProfileVersions.resolver}.'
          '${WardrobeProfileVersions.taxonomy}:'
          '${_fnv1a64(fingerprints.join('||'))}';
      return HomeWardrobeReadPathResult(
        items: _immutableItems(output),
        wardrobeSignature: signature,
        usedResolvedProfiles: true,
        wholePipelineFallback: false,
        resolvedWithoutFallback: resolvedWithoutFallback,
        compatibilityFallbackItems: fallbackItems,
        canonicalUnknownItems: canonicalUnknownItems,
        fallbackProperties: Map<String, int>.unmodifiable(fallbackCounts),
      );
    } catch (error) {
      final legacy = legacyNormalizer(rawCopies);
      return HomeWardrobeReadPathResult(
        items: _immutableItems(legacy),
        wardrobeSignature: legacyWardrobeSignature(rawItems),
        usedResolvedProfiles: false,
        wholePipelineFallback: true,
        resolvedWithoutFallback: 0,
        compatibilityFallbackItems: legacy.length,
        canonicalUnknownItems: 0,
        fallbackProperties: const <String, int>{'pipeline.wholeFailure': 1},
      );
    }
  }

  HomeWardrobeReadPathResult _buildV2(
    List<Map<String, dynamic>> rawItems,
    WardrobeOntologyV2 ontology,
  ) {
    final resolver = WardrobeV2Resolver(ontology);
    final output = <Map<String, dynamic>>[];
    var fallback = 0;
    Map<String, Map<String, dynamic>>? legacyById;
    for (final raw in rawItems) {
      final id = itemId(raw);
      try {
        final resolved = resolver.resolve(id, raw).item;
        final ui = resolved.uiProjection;
        output.add(
          Map.unmodifiable({
            ...raw,
            ...resolved.toMap(),
            // Temporary centralized engine projection. V2 remains authoritative.
            'canonical_type': resolved.canonicalType,
            'mainGroupKey': ui['mainCategory'],
            'categoryKey': ui['category'],
            'subCategoryKey': ui['subcategory'],
            'layer_role': _legacyLayerProjection(
              resolved.bodySlots,
              resolved.layerPosition,
            ),
            '__wardrobeV2': const {'resolved': true, 'legacyFallback': false},
          }),
        );
      } on WardrobeV2DataQualityException catch (error) {
        fallback++;
        legacyById ??= {
          for (final item in legacyNormalizer(rawItems)) itemId(item): item,
        };
        output.add(
          Map.unmodifiable({
            ...?legacyById[id],
            '__wardrobeV2': {
              'resolved': false,
              'legacyFallback': true,
              'errors': error.errors,
            },
          }),
        );
      }
    }
    final signatureParts =
        output
            .map(
              (x) =>
                  '${itemId(x)}:${x['canonicalType']}:${x['taxonomyVersion']}',
            )
            .toList()
          ..sort();
    return HomeWardrobeReadPathResult(
      items: _immutableItems(output),
      wardrobeSignature: 'wardrobe-v2:${_fnv1a64(signatureParts.join('|'))}',
      usedResolvedProfiles: true,
      wholePipelineFallback: false,
      resolvedWithoutFallback: output.length - fallback,
      compatibilityFallbackItems: fallback,
      canonicalUnknownItems: fallback,
      fallbackProperties: fallback == 0
          ? const {}
          : {'v2.dataQuality': fallback},
    );
  }

  static String _legacyLayerProjection(List<String> slots, String layer) {
    if (slots.contains('feet')) return 'footwear';
    if (slots.contains('lower_body')) return 'bottom';
    if (slots.any(
      const {
        'carried',
        'shoulder_carried',
        'back_carried',
        'wrist',
        'neck',
        'ears',
        'waist',
      }.contains,
    )) {
      return 'accessory';
    }
    if (layer == 'outer' || layer == 'shell') return 'outer_layer';
    if (layer == 'mid') return 'mid_layer';
    return 'base_layer';
  }

  HomeResolvedWardrobeItem _project(Map<String, dynamic> raw) {
    const legacyAdapter = LegacyWardrobeEvidenceAdapter();
    const kbProvider = WardrobeKnowledgeBasePriorProvider();
    const resolver = WardrobeProfileResolver();
    const engineAdapter = WardrobeProfileEngineAdapter();
    final legacyEvidence = legacyAdapter.adapt(raw);
    final evidence = <ProfileEvidence>[
      ...legacyEvidence,
      ...kbProvider.provide(document: raw, existingEvidence: legacyEvidence),
    ];
    final profile = resolver.resolve(itemId: itemId(raw), evidence: evidence);
    return HomeResolvedWardrobeItem(
      profile: profile,
      engineMap: engineAdapter.toEngineMap(profile),
    );
  }

  static List<String> _unknownCritical(ResolvedWardrobeItemProfile profile) {
    final unknown = <String>[];
    if (!profile.identity.canonicalType.isKnown) {
      unknown.add(WardrobeProfileProperty.canonicalType);
    }
    if (!profile.capabilities.warmth.isKnown) {
      unknown.add(WardrobeProfileProperty.warmth);
    }
    if (!profile.capabilities.formality.isKnown) {
      unknown.add(WardrobeProfileProperty.formality);
    }
    if (!profile.capabilities.layerRole.isKnown ||
        profile.capabilities.layerRole.value == WardrobeLayerRole.unknown) {
      unknown.add(WardrobeProfileProperty.layerRole);
    }
    return List<String>.unmodifiable(unknown);
  }

  static Map<String, dynamic> _legacyFallbackItem({
    required Map<String, dynamic> legacyItem,
    required Map<String, dynamic> resolvedMap,
    required List<String> properties,
    required String reason,
  }) {
    final resolvedMetadata =
        resolvedMap[WardrobeProfileEngineAdapter.debugMetadataKey];
    return Map<String, dynamic>.unmodifiable(<String, dynamic>{
      ...legacyItem,
      WardrobeProfileEngineAdapter.debugMetadataKey: <String, Object?>{
        'mode': 'legacy_item_fallback',
        'reason': reason,
        'fallbackProperties': List<String>.unmodifiable(properties),
        if (resolvedMetadata is Map)
          'resolvedProjectionMetadata': Map<Object?, Object?>.unmodifiable(
            resolvedMetadata,
          ),
      },
    });
  }

  static String _itemFingerprint({
    required Map<String, dynamic> raw,
    required ResolvedWardrobeItemProfile profile,
    required Map<String, dynamic> resolvedMap,
    required Map<String, dynamic> effectiveMap,
    required List<String> fallbackProperties,
  }) {
    final revision = _profileRevision(raw);
    final decisionFields = <String, Object?>{
      'id': itemId(raw),
      'revision': revision,
      'schema': profile.metadata.schemaVersion,
      'resolver': profile.metadata.resolverVersion,
      'taxonomy': profile.metadata.taxonomyVersion,
      'canonical': resolvedMap['canonical_type'],
      'warmth': resolvedMap['warmth_level'],
      'formality': resolvedMap['formality'],
      'layerRole': resolvedMap['layer_role'],
      'colors': resolvedMap['colors'],
      'styles': resolvedMap['styles'],
      'seasons': resolvedMap['seasons'],
      'effectiveCanonical': effectiveMap['canonical_type'],
      'effectiveWarmth': effectiveMap['warmth_level'],
      'effectiveFormality': effectiveMap['formality'],
      'fallbackProperties': fallbackProperties,
      'userCorrection':
          raw['userCorrection'] ??
          raw['user_correction'] ??
          raw['userCorrections'] ??
          raw['user_corrections'],
    };
    return _stableValue(decisionFields);
  }

  static String _fallbackFingerprint(
    Map<String, dynamic> raw,
    Map<String, dynamic> effective,
    String reason,
  ) => _stableValue(<String, Object?>{
    'id': itemId(raw),
    'revision': _profileRevision(raw),
    'resolver': WardrobeProfileVersions.resolver,
    'taxonomy': WardrobeProfileVersions.taxonomy,
    'reason': reason,
    'canonical': effective['canonical_type'],
    'warmth': effective['warmth_level'],
    'formality': effective['formality'],
    'colors': effective['colors'],
    'styles': effective['styles'],
    'seasons': effective['seasons'],
  });

  static int _profileRevision(Map<String, dynamic> raw) {
    final direct = raw['profileRevision'] ?? raw['profile_revision'];
    if (direct is num && direct >= 0) return direct.toInt();
    if (direct is String) return int.tryParse(direct) ?? 0;
    for (final key in const ['wardrobeProfile', '_wardrobeProfile']) {
      final nested = raw[key];
      if (nested is Map) {
        final revision = nested['revision'];
        if (revision is num && revision >= 0) return revision.toInt();
        if (revision is String) return int.tryParse(revision) ?? 0;
      }
    }
    return 0;
  }

  static String legacyWardrobeSignature(List<Map<String, dynamic>> wardrobe) {
    final ids = wardrobe.map(itemId).where((id) => id.isNotEmpty).toList()
      ..sort();
    return '${wardrobe.length}:${ids.join(",")}';
  }

  static bool sameItemIds(
    List<Map<String, dynamic>> left,
    List<Map<String, dynamic>> right,
  ) {
    final leftIds = left.map(itemId).where((id) => id.isNotEmpty).toList()
      ..sort();
    final rightIds = right.map(itemId).where((id) => id.isNotEmpty).toList()
      ..sort();
    return listEquals(leftIds, rightIds);
  }

  static String itemId(Map<String, dynamic> item) =>
      (item['id'] ?? item['documentId'] ?? '').toString().trim();

  /// Cheap StreamBuilder short-circuit. Field reads only — never run the
  /// resolved profile pipeline. Includes Set membership so Home refreshes
  /// after owner Set create/dissolve without a full projection.
  static String cheapDocumentIdentity(List<Map<String, dynamic>> items) {
    final buffer = StringBuffer(items.length.toString());
    for (final item in items) {
      buffer.write('|');
      buffer.write(itemId(item));
      buffer.write(':');
      buffer.write(item['name'] ?? '');
      buffer.write(':');
      final membership = item['setMembership'];
      if (membership is Map) {
        buffer.write(membership['setId'] ?? '');
      }
      buffer.write(':');
      final pending = item['pendingSetDraft'];
      if (pending is Map) {
        buffer.write(pending['draftId'] ?? 'pending');
      }
      buffer.write(':');
      buffer.write(
        item['productImageUrl'] ??
            item['cleanImageUrl'] ??
            item['cutoutImageUrl'] ??
            item['imageUrl'] ??
            '',
      );
    }
    return buffer.toString();
  }

  static List<Map<String, dynamic>> _defaultLegacyNormalizer(
    List<Map<String, dynamic>> rawItems,
  ) => HomeWardrobeNormalizer.normalizeWardrobeForHome(rawItems);

  static List<Map<String, dynamic>> _immutableItems(
    Iterable<Map<String, dynamic>> items,
  ) => List<Map<String, dynamic>>.unmodifiable(
    items.map(
      (item) =>
          Map<String, dynamic>.unmodifiable(Map<String, dynamic>.from(item)),
    ),
  );

  static String _stableMap(Map<String, int> value) => _stableValue(value);

  static String _stableValue(Object? value) {
    if (value == null) return 'null';
    if (value is Map) {
      final entries =
          value.entries
              .map((entry) => MapEntry(entry.key.toString(), entry.value))
              .toList()
            ..sort((left, right) => left.key.compareTo(right.key));
      return '{${entries.map((entry) => '${entry.key}:${_stableValue(entry.value)}').join(',')}}';
    }
    if (value is Iterable && value is! String) {
      final entries = value.map(_stableValue).toList()..sort();
      return '[${entries.join(',')}]';
    }
    return value.toString().trim().toLowerCase();
  }

  static String _fnv1a64(String input) {
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = BigInt.parse('ffffffffffffffff', radix: 16);
    for (final byte in input.codeUnits) {
      hash ^= BigInt.from(byte);
      hash = (hash * prime) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
