import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/add_clothing_analyzer_mapper.dart';
import 'package:outfitofTheDay/Services/color_naming_service.dart';
import 'package:outfitofTheDay/Services/native_wardrobe_v2_runtime.dart';
import 'package:outfitofTheDay/Services/wardrobe_v2_edit_prepopulation.dart';
import 'package:outfitofTheDay/Services/wardrobe_v2_user_override.dart';
import 'package:outfitofTheDay/constants/app_constants.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_item_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_ontology_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_v1_retirement.dart';

import 'add_clothing_analyzer_fixtures.dart';

void main() {
  late WardrobeOntologyV2 ontology;

  setUpAll(() {
    ontology = WardrobeOntologyV2.fromJsonString(
      File('assets/data/wardrobe_ontology_v2.json').readAsStringSync(),
    );
  });

  Map<String, dynamic> v2Of(Map<String, dynamic> response) =>
      Map<String, dynamic>.from(response['wardrobeV2'] as Map);

  Map<String, dynamic> saveMerge({
    required Map<String, dynamic> originalV2,
    required AddClothingAnalyzerMapperResult mapped,
    required WardrobeV2UserOverrideResult override,
  }) {
    final hidden = Map<String, dynamic>.from(mapped.hiddenAiMetadata)
      ..remove('wardrobeV2');
    if (override.typeOverrideApplied) hidden.remove('formality');
    return WardrobeV1Retirement.stripRetiredFields({
      ...override.payload,
      'name': mapped.suggestedName,
      'brand': mapped.brand,
      'seasons': mapped.seasons,
      'styles': mapped.styles,
      'patterns': mapped.patterns,
      ...hidden,
    });
  }

  group('type override', () {
    test('untouched hoodie keeps the original V2 identity', () {
      final original = v2Of(addClothingAnalyzerHoodieFixture());
      final result = WardrobeV2UserOverride.apply(
        original: original,
        ontology: ontology,
      );
      expect(result.typeOverrideApplied, isFalse);
      expect(result.colorOverrideApplied, isFalse);
      expect(result.payload['canonicalType'], 'hoodie');
      expect(result.payload['canonicalFamily'], original['canonicalFamily']);
      expect(result.payload['bodySlots'], original['bodySlots']);
      expect(result.payload['layerPosition'], original['layerPosition']);
      expect(result.payload['colorProfile'], original['colorProfile']);
      expect(result.payload['warmth'], original['warmth']);
      expect(result.payload['formality'], original['formality']);
      expect(result.payload['userOverrideFields'], isEmpty);
    });

    test('hoodie → denim jacket rebuilds outerwear identity', () {
      final original = v2Of(addClothingAnalyzerHoodieFixture());
      final result = WardrobeV2UserOverride.apply(
        original: original,
        ontology: ontology,
        typeEdited: true,
        selectedSubcategory: 'bunda_riflova',
        selectedCategory: 'bundy_kabaty',
        currentCanonicalType: 'hoodie',
      );
      expect(result.typeOverrideApplied, isTrue);
      expect(result.payload['canonicalType'], 'denim_jacket');
      expect(result.payload['canonicalFamily'], 'outerwear');
      expect(result.payload['bodySlots'], ['upper_body']);
      expect(result.payload['layerPosition'], 'outer');
      expect(result.payload['canonicalType'], isNot('hoodie'));
      expect(result.payload['canonicalFamily'], isNot('mid_layer'));
      expect(result.payload['layerPosition'], isNot('mid'));
      expect(result.payload['colorProfile'], original['colorProfile']);
      expect(result.payload['fieldSources']['canonicalType'], 'user_correction');
      expect(result.payload['userOverrideFields'], contains('canonicalType'));
    });

    test('jacket → hoodie rebuilds mid-layer identity', () {
      final original = v2Of(addClothingAnalyzerV2DenimJacketVsHoodieGuardFixture());
      final result = WardrobeV2UserOverride.apply(
        original: original,
        ontology: ontology,
        typeEdited: true,
        selectedSubcategory: 'mikina_s_kapucnou',
        selectedCategory: 'mikiny',
        currentCanonicalType: 'denim_jacket',
      );
      expect(result.payload['canonicalType'], 'hoodie');
      expect(result.payload['canonicalFamily'], 'mid_layer');
      expect(result.payload['bodySlots'], ['upper_body']);
      expect(result.payload['layerPosition'], 'mid');
    });

    test('top → trousers updates body-slot and family', () {
      final original = v2Of(addClothingAnalyzerTShirtFixture());
      final result = WardrobeV2UserOverride.apply(
        original: original,
        ontology: ontology,
        typeEdited: true,
        selectedSubcategory: 'nohavice_klasicke',
        selectedCategory: 'nohavice_rifle',
        currentCanonicalType: 't_shirt',
      );
      expect(result.payload['canonicalType'], 'trousers');
      expect(result.payload['canonicalFamily'], 'bottom');
      expect(result.payload['bodySlots'], ['lower_body']);
      expect(result.payload['layerPosition'], 'outer');
    });

    test('sneakers → running shoes stay footwear', () {
      final original = v2Of(addClothingAnalyzerSneakersFixture());
      final result = WardrobeV2UserOverride.apply(
        original: original,
        ontology: ontology,
        typeEdited: true,
        selectedSubcategory: 'tenisky_bezecke',
        selectedCategory: 'tenisky',
        currentCanonicalType: 'sneakers',
      );
      expect(result.payload['canonicalType'], 'running_shoes');
      expect(result.payload['canonicalFamily'], 'footwear');
      expect(result.payload['bodySlots'], ['feet']);
      expect(result.payload['layerPosition'], 'not_applicable');
    });

    test('unsupported mixed-slot subcategory preserves prior identity', () {
      final original = v2Of(addClothingAnalyzerHoodieFixture());
      final result = WardrobeV2UserOverride.apply(
        original: original,
        ontology: ontology,
        typeEdited: true,
        selectedSubcategory: 'undershirt',
        currentCanonicalType: 'hoodie',
      );
      expect(result.typeOverrideApplied, isFalse);
      expect(result.unresolvedTypeReason, contains('undershirt'));
      expect(result.payload['canonicalType'], 'hoodie');
      expect(result.payload['canonicalFamily'], 'mid_layer');
      expect(result.payload['bodySlots'], original['bodySlots']);
    });

    test('unknown subcategory does not guess a V2 type', () {
      final original = v2Of(addClothingAnalyzerHoodieFixture());
      final result = WardrobeV2UserOverride.apply(
        original: original,
        ontology: ontology,
        typeEdited: true,
        selectedSubcategory: 'not_a_real_subcategory',
        currentCanonicalType: 'hoodie',
      );
      expect(result.typeOverrideApplied, isFalse);
      expect(result.payload['canonicalType'], 'hoodie');
    });
  });

  group('color override', () {
    test('untouched white profile stays byte-identical', () {
      final original = v2Of(addClothingAnalyzerTShirtFixture());
      final result = WardrobeV2UserOverride.apply(
        original: original,
        ontology: ontology,
        selectedDisplayColors: const ['biela', 'čierna'],
      );
      expect(result.colorOverrideApplied, isFalse);
      expect(result.payload['colorProfile'], original['colorProfile']);
    });

    test('white → red rebuilds colorProfile as red', () {
      final original = v2Of(addClothingAnalyzerTShirtFixture());
      final result = WardrobeV2UserOverride.apply(
        original: original,
        ontology: ontology,
        colorEdited: true,
        selectedDisplayColors: const ['červená'],
      );
      expect(result.colorOverrideApplied, isTrue);
      expect(result.payload['colorProfile']['primary']['family'], 'red');
      expect(result.payload['colorProfile']['secondary'], isNull);
      expect(result.payload['colorProfile']['accents'], isEmpty);
      expect(
        WardrobeV2EditPrepopulation.displayColorsFromProfile(
          result.payload['colorProfile'],
        ),
        ['červená'],
      );
      expect(result.payload['fieldSources']['colorProfile'], 'user_correction');
    });

    test('single → multicolor writes primary, secondary, accent', () {
      final original = v2Of(addClothingAnalyzerHoodieFixture());
      final result = WardrobeV2UserOverride.apply(
        original: original,
        ontology: ontology,
        colorEdited: true,
        selectedDisplayColors: const ['čierna', 'biela', 'červená'],
      );
      final profile = result.payload['colorProfile'] as Map;
      expect(profile['primary']['family'], 'black');
      expect(profile['secondary']['family'], 'white');
      expect(profile['accents'], hasLength(1));
      expect(profile['accents'].first['family'], 'red');
      expect(
        WardrobeV2EditPrepopulation.colorFamiliesFromProfile(profile),
        ['black', 'white', 'red'],
      );
    });

    test('multicolor → one color drops removed families', () {
      final original = v2Of(addClothingAnalyzerMulticolorTopFixture());
      final result = WardrobeV2UserOverride.apply(
        original: original,
        ontology: ontology,
        colorEdited: true,
        selectedDisplayColors: const ['modrá'],
      );
      final profile = result.payload['colorProfile'] as Map;
      expect(profile['primary']['family'], 'blue');
      expect(profile['secondary'], isNull);
      expect(profile['accents'], isEmpty);
      expect(
        WardrobeV2EditPrepopulation.colorFamiliesFromProfile(profile),
        ['blue'],
      );
    });

    test('Slovak display names map back to canonical V2 families', () {
      expect(
        ColorNamingService.instance.canonicalFamilyFromDisplay('tmavomodrá'),
        'navy',
      );
      expect(ColorNamingService.instance.canonicalFamilyFromDisplay('biela'), 'white');
      final original = v2Of(addClothingAnalyzerTShirtFixture());
      final result = WardrobeV2UserOverride.apply(
        original: original,
        ontology: ontology,
        colorEdited: true,
        selectedDisplayColors: const ['tmavomodrá'],
      );
      expect(result.payload['colorProfile']['primary']['family'], 'navy');
      expect(
        WardrobeV2EditPrepopulation.displayColorsFromProfile(
          result.payload['colorProfile'],
        ),
        ['tmavomodrá'],
      );
    });
  });

  group('combined and edit persistence', () {
    test('hoodie+black → denim jacket+red is coherent for both edits', () {
      final original = v2Of(addClothingAnalyzerHoodieFixture());
      final result = WardrobeV2UserOverride.apply(
        original: original,
        ontology: ontology,
        typeEdited: true,
        colorEdited: true,
        selectedSubcategory: 'bunda_riflova',
        selectedCategory: 'bundy_kabaty',
        selectedDisplayColors: const ['červená'],
        currentCanonicalType: 'hoodie',
      );
      expect(result.payload['canonicalType'], 'denim_jacket');
      expect(result.payload['canonicalFamily'], 'outerwear');
      expect(result.payload['layerPosition'], 'outer');
      expect(result.payload['colorProfile']['primary']['family'], 'red');
      expect(result.payload['colorProfile']['primary']['family'], isNot('black'));
      expect(result.payload['userOverrideFields'], containsAll(['canonicalType', 'colorProfile']));
    });

    test('edit existing item persists type and color correction', () {
      final document = {
        ...v2Of(addClothingAnalyzerHoodieFixture()),
        'name': 'Čierna mikina s kapucňou',
        'brand': 'Nike',
      };
      final loaded = WardrobeV2EditPersistence.authoritativePayloadFromDocument(
        document,
      );
      final edited = WardrobeV2EditPersistence.applyIdentityOverride(
        payload: loaded,
        ontology: ontology,
        typeEdited: true,
        colorEdited: true,
        selectedSubcategory: 'bunda_riflova',
        selectedCategory: 'bundy_kabaty',
        selectedDisplayColors: const ['červená'],
        currentCanonicalType: 'hoodie',
      );
      expect(edited.payload['canonicalType'], 'denim_jacket');
      expect(edited.payload['colorProfile']['primary']['family'], 'red');
      final brandOnly = WardrobeV2EditPersistence.applyBrandEdit(
        payload: edited.payload,
        originalBrand: 'Nike',
        editedBrand: 'Adidas',
      );
      expect(brandOnly['canonicalType'], 'denim_jacket');
      expect(brandOnly['userOverrideFields'], contains('brand'));
      expect((brandOnly['fieldSources'] as Map)['brand'], 'user_correction');
    });

    test('brand-only edit preserves V2 identity', () {
      final document = {
        ...v2Of(addClothingAnalyzerHoodieFixture()),
        'brand': 'Nike',
      };
      final loaded = WardrobeV2EditPersistence.authoritativePayloadFromDocument(
        document,
      );
      final unchanged = WardrobeV2EditPersistence.applyIdentityOverride(
        payload: loaded,
        ontology: ontology,
      );
      expect(unchanged.payload['canonicalType'], 'hoodie');
      expect(unchanged.payload['colorProfile'], loaded['colorProfile']);
      final branded = WardrobeV2EditPersistence.applyBrandEdit(
        payload: unchanged.payload,
        originalBrand: 'Nike',
        editedBrand: 'Adidas',
      );
      expect(branded['canonicalType'], 'hoodie');
      expect(branded['canonicalFamily'], loaded['canonicalFamily']);
      expect(branded['colorProfile'], loaded['colorProfile']);
      expect(branded['userOverrideFields'], ['brand']);
    });

    test('untouched AI fill still saves original V2 after override helper', () {
      final response = addClothingAnalyzerHoodieFixture();
      final mapped = AddClothingAnalyzerMapper.map(response);
      final original = Map<String, dynamic>.from(mapped.wardrobeV2!);
      final override = WardrobeV2UserOverride.apply(
        original: original,
        ontology: ontology,
      );
      final saved = saveMerge(
        originalV2: original,
        mapped: mapped,
        override: override,
      );
      expect(saved['canonicalType'], original['canonicalType']);
      expect(saved['canonicalFamily'], original['canonicalFamily']);
      expect(saved['bodySlots'], original['bodySlots']);
      expect(saved['layerPosition'], original['layerPosition']);
      expect(saved['colorProfile'], original['colorProfile']);
      expect(saved['warmth'], original['warmth']);
      expect(saved['formality'], original['formality']);
    });
  });

  group('warmth and formality policy', () {
    test('hoodie → sweatshirt-compatible jacket keeps in-range warmth', () {
      final original = v2Of(addClothingAnalyzerHoodieFixture());
      expect(original['warmth'], 5);
      final result = WardrobeV2UserOverride.apply(
        original: original,
        ontology: ontology,
        typeEdited: true,
        selectedSubcategory: 'bunda_riflova',
        currentCanonicalType: 'hoodie',
      );
      expect(result.payload['warmth'], 5);
      expect(result.payload['formality'], 2);
    });

    test('t-shirt → winter jacket snaps warmth onto the new range', () {
      final original = v2Of(addClothingAnalyzerTShirtFixture());
      expect(original['warmth'], 2);
      final result = WardrobeV2UserOverride.apply(
        original: original,
        ontology: ontology,
        typeEdited: true,
        selectedSubcategory: 'bunda_zimna',
        selectedCategory: 'bundy_kabaty',
        currentCanonicalType: 't_shirt',
      );
      expect(result.payload['canonicalType'], 'winter_jacket');
      expect(result.payload['warmth'], 9);
      expect(result.payload['formality'], 3);
    });
  });

  group('downstream V2 runtime', () {
    test('corrected jacket resolves as outerwear for outfit engines', () {
      final original = v2Of(addClothingAnalyzerHoodieFixture());
      final result = WardrobeV2UserOverride.apply(
        original: original,
        ontology: ontology,
        typeEdited: true,
        selectedSubcategory: 'bunda_riflova',
        currentCanonicalType: 'hoodie',
      );
      final resolved = NativeWardrobeV2Runtime.resolveAll(
        [
          {'id': 'jacket-1', ...result.payload},
        ],
        ontology: ontology,
      );
      expect(resolved, hasLength(1));
      expect(resolved.single.item.canonicalType, 'denim_jacket');
      expect(resolved.single.item.canonicalFamily, 'outerwear');
      expect(resolved.single.item.layerPosition, 'outer');
      expect(resolved.single.item.bodySlots, ['upper_body']);
    });

    test('corrected footwear resolves as footwear', () {
      final original = v2Of(addClothingAnalyzerSneakersFixture());
      final result = WardrobeV2UserOverride.apply(
        original: original,
        ontology: ontology,
        typeEdited: true,
        selectedSubcategory: 'tenisky_bezecke',
        currentCanonicalType: 'sneakers',
      );
      final resolved = NativeWardrobeV2Runtime.resolveAll(
        [
          {'id': 'shoe-1', ...result.payload},
        ],
        ontology: ontology,
      );
      expect(resolved.single.item.canonicalFamily, 'footwear');
      expect(resolved.single.item.bodySlots, ['feet']);
      expect(
        WardrobeItemV2Validator(ontology).validate(resolved.single.item),
        isEmpty,
      );
    });
  });

  test('production picker keys either resolve or stay explicitly unresolved', () {
    final unresolved = <String>[];
    final resolved = <String, String>{};
    for (final subs in subCategoryTree.values) {
      for (final sub in subs) {
        final type = WardrobeV2UserOverride.canonicalTypeForUiSelection(
          ontology: ontology,
          subcategory: sub,
        );
        if (type == null) {
          unresolved.add(sub);
        } else {
          resolved[sub] = type;
        }
      }
    }
    expect(resolved['mikina_s_kapucnou'], 'hoodie');
    expect(resolved['bunda_riflova'], 'denim_jacket');
    expect(resolved['bunda_zimna'], 'winter_jacket');
    expect(resolved['nohavice_klasicke'], 'trousers');
    expect(resolved['tenisky_bezecke'], 'running_shoes');
    expect(resolved['tenisky_fashion'], 'sneakers');
    expect(unresolved, contains('undershirt'));
    for (final sub in unresolved) {
      final candidates = ontology.types.values
          .where((type) => type.uiProjection['subcategory'] == sub)
          .toList();
      final families = candidates.map((type) => type.canonicalFamily).toSet();
      final slots = candidates
          .map((type) => type.defaultBodySlots.join('|'))
          .toSet();
      expect(
        families.length > 1 || slots.length > 1 || candidates.isEmpty,
        isTrue,
        reason: 'unexpectedly unresolved $sub → $candidates',
      );
    }
  });
}
