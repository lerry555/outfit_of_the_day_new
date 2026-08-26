import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/flexible_candidate_matrix_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/outfit_suitability_policy_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_item_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_v2_resolver.dart';

WardrobeItemV2 _item({
  required String type,
  required String family,
  required List<String> slots,
  required int warmth,
  required int formality,
  required List<String> seasons,
}) => WardrobeItemV2(
  canonicalType: type,
  canonicalFamily: family,
  bodySlots: slots,
  layerPosition: slots.contains('feet') ? 'not_applicable' : 'base',
  outfitFunctions: const [],
  colorProfile: const ColorProfileV2(
    primary: SemanticColorV2(family: 'black'),
    metalTone: 'none',
    hardwareTone: 'none',
  ),
  formality: formality,
  styles: const [],
  occasionFit: const [],
  seasons: seasons,
  warmth: warmth,
  attributes: const {},
  fieldSources: const {'canonicalType': 'fixture'},
  fieldConfidence: const {'canonicalType': 1.0},
  userOverrideFields: const [],
);

ResolvedWardrobeItemV2 _resolved(String id, WardrobeItemV2 item) =>
    ResolvedWardrobeItemV2(itemId: id, item: item, raw: {'id': id});

final _winterBoots = _item(
  type: 'winter_boots',
  family: 'footwear',
  slots: const ['feet'],
  warmth: 9,
  formality: 4,
  seasons: const ['zima'],
);
final _sneakers = _item(
  type: 'sneakers',
  family: 'footwear',
  slots: const ['feet'],
  warmth: 3,
  formality: 4,
  seasons: const ['jar', 'leto', 'jeseň'],
);
final _formalShoes = _item(
  type: 'dress_shoes',
  family: 'footwear',
  slots: const ['feet'],
  warmth: 3,
  formality: 8,
  seasons: const ['celoročne'],
);
final _blackAnkleBoots = _item(
  // A genuinely warm Chelsea/ankle boot remains thermally unsuitable for a
  // warm late-summer restaurant candidate. Calendar season is not the gate.
  type: 'chelsea_boots',
  family: 'footwear',
  slots: const ['feet'],
  warmth: 6,
  formality: 5,
  seasons: const ['jeseň', 'zima'],
);

List<ResolvedWardrobeItemV2> _wardrobe({bool formal = false}) => [
  _resolved(
    'shirt',
    _item(
      type: formal ? 'dress_shirt' : 't_shirt',
      family: 'top',
      slots: const ['upper_body'],
      warmth: 3,
      formality: formal ? 8 : 3,
      seasons: const ['celoročne'],
    ),
  ),
  _resolved(
    'trousers',
    _item(
      type: 'trousers',
      family: 'bottom',
      slots: const ['lower_body'],
      warmth: 3,
      formality: formal ? 8 : 4,
      seasons: const ['celoročne'],
    ),
  ),
  _resolved(
    'winter-boots',
    formal
        ? _item(
            type: 'winter_boots',
            family: 'footwear',
            slots: const ['feet'],
            warmth: 9,
            formality: 6,
            seasons: const ['zima'],
          )
        : _winterBoots,
  ),
  _resolved('sneakers', _sneakers),
  if (formal) _resolved('formal-shoes', _formalShoes),
];

List<ResolvedWardrobeItemV2> _lateSummerRestaurantWardrobe() => [
  _resolved(
    'restaurant-shirt',
    _item(
      type: 'dress_shirt',
      family: 'top',
      slots: const ['upper_body'],
      warmth: 3,
      formality: 6,
      seasons: const ['celoročne'],
    ),
  ),
  _resolved(
    'restaurant-trousers',
    _item(
      type: 'trousers',
      family: 'bottom',
      slots: const ['lower_body'],
      warmth: 3,
      formality: 6,
      seasons: const ['celoročne'],
    ),
  ),
  _resolved('black-ankle-boots', _blackAnkleBoots),
  _resolved('formal-shoes', _formalShoes),
];

void main() {
  test(
    'warm rain excludes winter-only high-warmth boots before candidates',
    () {
      final matrix = V2FlexibleCandidateMatrix.generate(
        wardrobe: _wardrobe(),
        context: const V2CandidateMatrixContext(
          tempC: 22,
          isRainy: true,
          weatherProtectionRequired: true,
        ),
      );

      expect(matrix, isNotEmpty);
      expect(
        matrix.every(
          (candidate) => candidate.outfit.items.every(
            (item) => item.itemId != 'winter-boots',
          ),
        ),
        isTrue,
      );
      expect(
        matrix.first.outfit.items.map((item) => item.itemId),
        contains('sneakers'),
      );
    },
  );

  test('winter-only boots are unsuitable at 20C even when dry', () {
    expect(
      OutfitSuitabilityPolicyV2.isFootwearPhysicallyUnsuitableForConditions(
        _winterBoots,
        tempC: 20,
      ),
      isTrue,
    );
  });

  test(
    'warm late-summer rain excludes thermally heavy Chelsea ankle boots before frozen candidates',
    () {
      final matrix = V2FlexibleCandidateMatrix.generate(
        wardrobe: _lateSummerRestaurantWardrobe(),
        context: const V2CandidateMatrixContext(
          tempC: 22,
          seasonKey: 'let',
          isRainy: true,
          weatherProtectionRequired: true,
          minimumFormality: 5,
          scoringFormalityFloor: 5,
          occasionId: 'restaurant_evening',
        ),
      );

      expect(matrix, isNotEmpty);
      expect(
        matrix.every(
          (candidate) => candidate.outfit.items.every(
            (item) => item.itemId != 'black-ankle-boots',
          ),
        ),
        isTrue,
      );
      expect(
        matrix.first.outfit.items.map((item) => item.itemId),
        contains('formal-shoes'),
      );
    },
  );

  test('light all-season Chelsea boots remain valid at 14C', () {
    final chelsea = _item(
      type: 'chelsea_boots',
      family: 'footwear',
      slots: const ['feet'],
      warmth: 4,
      formality: 6,
      seasons: const ['celoročne'],
    );
    expect(
      OutfitSuitabilityPolicyV2.isFootwearPhysicallyUnsuitableForConditions(
        chelsea,
        tempC: 14,
      ),
      isFalse,
    );
  });

  test('winter boots remain valid in cold conditions', () {
    expect(
      OutfitSuitabilityPolicyV2.isFootwearPhysicallyUnsuitableForConditions(
        _winterBoots,
        tempC: 5,
      ),
      isFalse,
    );
  });

  test('warm formal rain keeps formal shoes ahead of winter boots', () {
    final matrix = V2FlexibleCandidateMatrix.generate(
      wardrobe: _wardrobe(formal: true),
      context: const V2CandidateMatrixContext(
        tempC: 22,
        isRainy: true,
        weatherProtectionRequired: true,
        minimumFormality: 6,
        scoringFormalityFloor: 7,
      ),
    );

    expect(matrix, isNotEmpty);
    expect(
      matrix.first.outfit.items.map((item) => item.itemId),
      contains('formal-shoes'),
    );
    expect(
      matrix.every(
        (candidate) => candidate.outfit.items.every(
          (item) => item.itemId != 'winter-boots',
        ),
      ),
      isTrue,
    );
  });
}
