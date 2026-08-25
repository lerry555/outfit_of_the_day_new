import 'wardrobe_profile_contract.dart';

/// Projects a resolved M11.0 profile into the map shape consumed by the current
/// outfit engine.
///
/// This is intentionally not a resolver: it does not inspect evidence, infer
/// types, call the knowledge base, or manufacture domain values for unknown
/// fields.
final class WardrobeProfileEngineAdapter {
  const WardrobeProfileEngineAdapter();

  static const int adapterVersion = 1;
  static const String debugMetadataKey = '_wardrobeProfileCompatibility';

  Map<String, dynamic> toEngineMap(ResolvedWardrobeItemProfile profile) {
    final result = <String, dynamic>{'id': profile.itemId};
    final unknownProperties = <String>[];
    final delegatedFallbacks = <String, String>{};

    void stringField(
      String engineKey,
      String property,
      ResolvedField<String> field, {
      List<String> aliases = const [],
      String? delegatedFallback,
    }) {
      if (field.isKnown && field.value != null) {
        result[engineKey] = field.value;
        for (final alias in aliases) {
          result[alias] = field.value;
        }
      } else {
        unknownProperties.add(property);
        if (delegatedFallback != null) {
          delegatedFallbacks[engineKey] = delegatedFallback;
        }
      }
    }

    void intField(
      String engineKey,
      String property,
      ResolvedField<int> field, {
      List<String> aliases = const [],
      String? delegatedFallback,
    }) {
      if (field.isKnown && field.value != null) {
        result[engineKey] = field.value;
        for (final alias in aliases) {
          result[alias] = field.value;
        }
      } else {
        unknownProperties.add(property);
        if (delegatedFallback != null) {
          delegatedFallbacks[engineKey] = delegatedFallback;
        }
      }
    }

    void listField(
      String engineKey,
      String property,
      ResolvedField<List<String>> field, {
      List<String> aliases = const [],
    }) {
      if (field.isKnown && field.value != null) {
        final value = List<String>.unmodifiable(field.value!);
        result[engineKey] = value;
        for (final alias in aliases) {
          result[alias] = value;
        }
      } else {
        unknownProperties.add(property);
      }
    }

    void setField(
      String engineKey,
      String property,
      ResolvedField<Set<String>> field, {
      List<String> aliases = const [],
    }) {
      if (field.isKnown && field.value != null) {
        final value = field.value!.toList()
          ..sort(
            (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
          );
        final immutableValue = List<String>.unmodifiable(value);
        result[engineKey] = immutableValue;
        for (final alias in aliases) {
          result[alias] = immutableValue;
        }
      } else {
        unknownProperties.add(property);
      }
    }

    stringField(
      'name',
      WardrobeProfileProperty.displayName,
      profile.identity.displayName,
    );
    stringField('brand', WardrobeProfileProperty.brand, profile.identity.brand);
    stringField(
      'canonical_type',
      WardrobeProfileProperty.canonicalType,
      profile.identity.canonicalType,
      aliases: const ['canonicalType'],
      delegatedFallback: 'legacy_engine_name_category_classification',
    );
    stringField(
      'mainGroupKey',
      WardrobeProfileProperty.mainCategory,
      profile.identity.mainCategory,
      aliases: const ['mainGroup'],
    );
    stringField(
      'categoryKey',
      WardrobeProfileProperty.category,
      profile.identity.category,
      aliases: const ['category'],
    );
    stringField(
      'subCategoryKey',
      WardrobeProfileProperty.subcategory,
      profile.identity.subcategory,
      aliases: const ['subCategory'],
    );

    final layerRole = profile.capabilities.layerRole;
    if (layerRole.isKnown &&
        layerRole.value != null &&
        layerRole.value != WardrobeLayerRole.unknown) {
      final value = layerRole.value!.wireName;
      result['layer_role'] = value;
      result['layerRole'] = value;
    } else {
      unknownProperties.add(WardrobeProfileProperty.layerRole);
      delegatedFallbacks['layer_role'] =
          'legacy_engine_category_then_base_layer';
    }

    intField(
      'warmth_level',
      WardrobeProfileProperty.warmth,
      profile.capabilities.warmth,
      aliases: const ['warmthLevel'],
      delegatedFallback: 'legacy_engine_item_inference_then_5',
    );
    intField(
      'formality',
      WardrobeProfileProperty.formality,
      profile.capabilities.formality,
    );

    listField(
      'colors',
      WardrobeProfileProperty.colors,
      profile.visual.colors,
      aliases: const ['color'],
    );
    listField(
      'baseColors',
      WardrobeProfileProperty.baseColors,
      profile.visual.baseColors,
    );
    listField('styles', WardrobeProfileProperty.styles, profile.visual.styles);
    listField(
      'patterns',
      WardrobeProfileProperty.patterns,
      profile.visual.patterns,
    );
    stringField('fit', WardrobeProfileProperty.fit, profile.visual.fit);
    stringField('vibe', WardrobeProfileProperty.vibe, profile.visual.vibe);
    setField(
      'seasons',
      WardrobeProfileProperty.seasons,
      profile.suitability.seasons,
      aliases: const ['season'],
    );
    setField(
      'occasion_fit',
      WardrobeProfileProperty.occasions,
      profile.suitability.occasions,
      aliases: const ['occasionFit'],
    );

    unknownProperties.sort();
    result[debugMetadataKey] = <String, Object>{
      'adapterVersion': adapterVersion,
      'profileSchemaVersion': profile.metadata.schemaVersion,
      'profileTaxonomyVersion': profile.metadata.taxonomyVersion,
      'profileResolverVersion': profile.metadata.resolverVersion,
      'unknownResolvedProperties': List<String>.unmodifiable(unknownProperties),
      'delegatedFallbacks': Map<String, String>.unmodifiable(
        delegatedFallbacks,
      ),
    };

    return Map<String, dynamic>.unmodifiable(result);
  }
}
