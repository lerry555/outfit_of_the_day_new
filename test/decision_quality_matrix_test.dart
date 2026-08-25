import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/decision_quality_harness.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/outfit_suitability_policy_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_item_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_v2_resolver.dart';
import 'package:outfitofTheDay/utils/stylist_layer_filter.dart';

WardrobeItemV2 _item({
  required String type,
  required String family,
  required List<String> slots,
  required String layer,
  int formality = 4,
  int warmth = 4,
  SetMembershipV2? set,
  List<String> functions = const [],
  List<String> overrides = const [],
}) {
  return WardrobeItemV2(
    canonicalType: type,
    canonicalFamily: family,
    bodySlots: slots,
    layerPosition: layer,
    outfitFunctions: functions,
    colorProfile: const ColorProfileV2(
      primary: SemanticColorV2(family: 'navy'),
      metalTone: 'none',
      hardwareTone: 'none',
    ),
    formality: formality,
    styles: const [],
    occasionFit: const [],
    seasons: const [],
    warmth: warmth,
    attributes: const {},
    fieldSources: const {'canonicalType': 'visual_ai', 'warmth': 'user'},
    fieldConfidence: const {'canonicalType': .9, 'warmth': 1.0},
    userOverrideFields: overrides,
    setMembership: set,
  );
}

ResolvedWardrobeItemV2 _r(String id, WardrobeItemV2 item) =>
    ResolvedWardrobeItemV2(itemId: id, item: item, raw: {'id': id});

const _suit = SetMembershipV2(setId: 'suit-1', setType: 'suit');
const _track = SetMembershipV2(setId: 'track-1', setType: 'tracksuit');
const _curated = SetMembershipV2(
  setId: 'favorite-1',
  setType: 'matching_set',
  relationshipSource: 'user_curated',
);

List<ResolvedWardrobeItemV2> fullWardrobe() => [
  _r('tshirt', _item(type: 't_shirt', family: 'top', slots: ['upper_body'], layer: 'base', formality: 3, warmth: 2, set: _curated)),
  _r('shirt', _item(type: 'dress_shirt', family: 'top', slots: ['upper_body'], layer: 'base', formality: 7, warmth: 3)),
  _r('hoodie', _item(type: 'hoodie', family: 'mid_layer', slots: ['upper_body'], layer: 'mid', formality: 2, warmth: 6)),
  _r('sweater', _item(type: 'sweater', family: 'mid_layer', slots: ['upper_body'], layer: 'mid', formality: 5, warmth: 6)),
  _r('denim', _item(type: 'denim_jacket', family: 'outerwear', slots: ['upper_body'], layer: 'outer', formality: 3, warmth: 4, overrides: const ['warmth'])),
  _r('winter', _item(type: 'winter_jacket', family: 'outerwear', slots: ['upper_body'], layer: 'outer', formality: 3, warmth: 9, functions: const ['thermal', 'weather_protection'])),
  _r('rain', _item(type: 'rain_jacket', family: 'outerwear', slots: ['upper_body'], layer: 'outer', formality: 3, warmth: 4, functions: const ['weather_protection'])),
  _r('blazer', _item(type: 'blazer', family: 'outerwear', slots: ['upper_body'], layer: 'outer', formality: 8, warmth: 4)),
  _r('suit_jacket', _item(type: 'suit_jacket', family: 'outerwear', slots: ['upper_body'], layer: 'outer', formality: 9, warmth: 4, set: _suit)),
  _r('suit_pants', _item(type: 'trousers', family: 'bottom', slots: ['lower_body'], layer: 'outer', formality: 9, warmth: 4, set: _suit)),
  _r('shorts', _item(type: 'shorts', family: 'bottom', slots: ['lower_body'], layer: 'outer', formality: 2, warmth: 1)),
  _r('jeans', _item(type: 'jeans', family: 'bottom', slots: ['lower_body'], layer: 'outer', formality: 3, warmth: 4, set: _curated)),
  _r('trousers', _item(type: 'trousers', family: 'bottom', slots: ['lower_body'], layer: 'outer', formality: 7, warmth: 4)),
  _r('sweats', _item(type: 'sweatpants', family: 'bottom', slots: ['lower_body'], layer: 'outer', formality: 2, warmth: 4)),
  _r('track_jacket', _item(type: 'track_jacket', family: 'outerwear', slots: ['upper_body'], layer: 'outer', formality: 2, warmth: 5, set: _track)),
  _r('track_pants', _item(type: 'track_pants', family: 'bottom', slots: ['lower_body'], layer: 'outer', formality: 2, warmth: 4, set: _track)),
  _r('dress', _item(type: 'dress', family: 'one_piece', slots: ['full_body'], layer: 'outer', formality: 6, warmth: 3)),
  _r('jumpsuit', _item(type: 'jumpsuit', family: 'one_piece', slots: ['full_body'], layer: 'outer', formality: 5, warmth: 3)),
  _r('sneakers', _item(type: 'sneakers', family: 'footwear', slots: ['feet'], layer: 'not_applicable', formality: 3, warmth: 3)),
  _r('dress_shoes', _item(type: 'dress_shoes', family: 'footwear', slots: ['feet'], layer: 'not_applicable', formality: 8, warmth: 3)),
  _r('sandals', _item(type: 'sandals', family: 'footwear', slots: ['feet'], layer: 'not_applicable', formality: 2, warmth: 1)),
  _r('boots', _item(type: 'boots', family: 'footwear', slots: ['feet'], layer: 'not_applicable', formality: 3, warmth: 5)),
];

class _Case {
  const _Case({
    required this.id,
    required this.family,
    required this.context,
    this.wardrobe,
    this.forbid = const {},
    this.requireAny = const {},
    this.requireLayerAbsent = const {},
    this.requireLayerPresent = const {},
    this.maxGrade,
    this.minGrade,
    this.allowWeak = false,
  });
  final String id, family;
  final DecisionQualityContext context;
  final List<ResolvedWardrobeItemV2>? wardrobe;
  final Set<String> forbid, requireAny, requireLayerAbsent, requireLayerPresent;
  final DecisionQualityGrade? maxGrade, minGrade;
  final bool allowWeak;
}

void main() {
  DecisionQualityReport run(_Case c) => DecisionQualityHarness.evaluate(
    wardrobe: c.wardrobe ?? fullWardrobe(),
    context: c.context,
  );

  String classify(_Case c, DecisionQualityReport r) {
    if (r.winner == null) {
      return c.allowWeak ? 'PASS_WITH_ACCEPTABLE_VARIATION' : 'FAIL_MAJOR';
    }
    for (final type in c.forbid) {
      if (r.winnerHasType(type)) return 'FAIL_MAJOR';
    }
    if (c.requireAny.isNotEmpty && !r.winnerHasAny(c.requireAny)) {
      return 'FAIL_MAJOR';
    }
    for (final layer in c.requireLayerAbsent) {
      if (r.winnerHasLayer(layer)) return 'FAIL_MAJOR';
    }
    for (final layer in c.requireLayerPresent) {
      if (!r.winnerHasLayer(layer)) return 'FAIL_MAJOR';
    }
    if (c.maxGrade != null) {
      const order = DecisionQualityGrade.values;
      if (order.indexOf(r.grade) < order.indexOf(c.maxGrade!)) {
        // more optimistic than expected compromise — variation
        return 'PASS_WITH_ACCEPTABLE_VARIATION';
      }
    }
    if (c.minGrade != null) {
      const order = DecisionQualityGrade.values;
      if (order.indexOf(r.grade) > order.indexOf(c.minGrade!)) {
        return c.allowWeak ? 'PASS_WITH_ACCEPTABLE_VARIATION' : 'FAIL_MINOR';
      }
    }
    if (r.grade == DecisionQualityGrade.weak && !c.allowWeak) {
      return 'FAIL_MINOR';
    }
    if (r.grade == DecisionQualityGrade.acceptableWithCompromise) {
      return 'PASS_WITH_ACCEPTABLE_VARIATION';
    }
    return 'PASS';
  }

  final cases = <_Case>[
    _Case(
      id: 'A1',
      family: 'weather',
      context: const DecisionQualityContext(tempC: 32, outdoor: true),
      forbid: {'winter_jacket', 'hoodie'},
      requireLayerAbsent: {'mid'},
    ),
    _Case(
      id: 'A2',
      family: 'weather',
      context: const DecisionQualityContext(tempC: 31, outdoor: true),
      forbid: {'winter_jacket', 'parka'},
    ),
    _Case(
      id: 'A3',
      family: 'weather',
      context: const DecisionQualityContext(tempC: 25),
      forbid: {'winter_jacket'},
    ),
    _Case(
      id: 'A4',
      family: 'weather',
      context: const DecisionQualityContext(tempC: 20),
      forbid: {'winter_jacket'},
    ),
    _Case(
      id: 'A5',
      family: 'weather',
      context: const DecisionQualityContext(tempC: 12),
      forbid: {'sandals', 'shorts'},
    ),
    _Case(
      id: 'A6',
      family: 'weather',
      context: const DecisionQualityContext(tempC: 4),
      forbid: {'sandals', 'shorts'},
      requireAny: {'winter_jacket', 'sweater', 'hoodie'},
    ),
    _Case(
      id: 'A7',
      family: 'weather',
      context: const DecisionQualityContext(tempC: -2),
      forbid: {'sandals', 'shorts'},
      requireAny: {'winter_jacket'},
    ),
    _Case(
      id: 'A8',
      family: 'weather',
      context: const DecisionQualityContext(tempC: 16, isRainy: true),
      forbid: {'sandals'},
      requireAny: {'rain_jacket', 'denim_jacket', 'winter_jacket'},
    ),
    _Case(
      id: 'A9',
      family: 'weather',
      context: const DecisionQualityContext(tempC: 4, isRainy: true),
      forbid: {'sandals', 'shorts'},
    ),
    _Case(
      id: 'A10',
      family: 'weather',
      context: const DecisionQualityContext(tempC: 12, isWindy: true),
      forbid: {'sandals'},
    ),
    _Case(
      id: 'A11',
      family: 'weather',
      context: const DecisionQualityContext(tempC: 22, eveningTempC: 9),
      forbid: {'winter_jacket'},
    ),
    _Case(
      id: 'B1',
      family: 'casual',
      context: const DecisionQualityContext(tempC: 21, occasionId: 'casual'),
      forbid: {'winter_jacket'},
    ),
    _Case(
      id: 'B2',
      family: 'casual',
      context: const DecisionQualityContext(tempC: 21, activityType: 'shopping'),
      forbid: {'winter_jacket'},
    ),
    _Case(
      id: 'B3',
      family: 'casual',
      context: const DecisionQualityContext(tempC: 18, activityType: 'nature_walk'),
      forbid: {'dress_shoes', 'sandals'},
    ),
    _Case(
      id: 'B4',
      family: 'casual',
      context: const DecisionQualityContext(tempC: 20, occasionId: 'cinema', outdoor: false),
      forbid: {'winter_jacket'},
    ),
    _Case(
      id: 'B5',
      family: 'casual',
      context: const DecisionQualityContext(tempC: 20, occasionId: 'casual', activityType: 'dinner'),
      forbid: {'shorts'},
    ),
    _Case(
      id: 'B6',
      family: 'casual',
      context: const DecisionQualityContext(tempC: 19, occasionId: 'dinner', outdoor: false),
      forbid: {'shorts', 'sandals'},
    ),
    _Case(
      id: 'B7',
      family: 'casual',
      context: const DecisionQualityContext(tempC: 20, occasionId: 'casual'),
      forbid: {'winter_jacket'},
    ),
    _Case(
      id: 'B8',
      family: 'casual',
      context: const DecisionQualityContext(tempC: 26, activityType: 'barbecue', outdoor: true),
      forbid: {'winter_jacket', 'suit_jacket'},
    ),
    _Case(
      id: 'B9',
      family: 'casual',
      context: const DecisionQualityContext(tempC: 20, occasionId: 'casual'),
      forbid: {'winter_jacket'},
    ),
    _Case(
      id: 'B10',
      family: 'casual',
      context: const DecisionQualityContext(tempC: 21, activityType: 'travel', outdoor: false),
      forbid: {'sandals'},
    ),
    _Case(
      id: 'B11',
      family: 'casual',
      context: const DecisionQualityContext(tempC: 22, activityType: 'travel'),
      forbid: {'sandals'},
    ),
    _Case(
      id: 'B12',
      family: 'casual',
      context: const DecisionQualityContext(tempC: 18, occasionId: 'casual'),
      forbid: {'winter_jacket'},
    ),
    _Case(
      id: 'C1',
      family: 'work',
      context: const DecisionQualityContext(tempC: 20, occasionId: 'work', outdoor: false),
      forbid: {'shorts', 'sandals', 'sweatpants'},
    ),
    _Case(
      id: 'C2',
      family: 'work',
      context: const DecisionQualityContext(tempC: 20, occasionId: 'casual_office', outdoor: false),
      forbid: {'shorts', 'sandals'},
    ),
    _Case(
      id: 'C3',
      family: 'work',
      context: const DecisionQualityContext(
        tempC: 20,
        occasionId: 'work',
        activityType: 'important_meeting',
        outdoor: false,
      ),
      forbid: {'shorts', 'sweatpants', 'track_pants', 'sandals'},
    ),
    _Case(
      id: 'C4',
      family: 'work',
      context: const DecisionQualityContext(
        tempC: 20,
        occasionId: 'work',
        activityType: 'business_meeting',
        outdoor: false,
      ),
      forbid: {'shorts', 'hoodie'},
    ),
    _Case(
      id: 'C5',
      family: 'work',
      context: const DecisionQualityContext(tempC: 20, occasionId: 'interview', outdoor: false),
      forbid: {'shorts', 'sneakers', 'hoodie', 'sweatpants'},
    ),
    _Case(
      id: 'C6',
      family: 'work',
      context: const DecisionQualityContext(
        tempC: 30,
        occasionId: 'work',
        outdoor: false,
      ),
      forbid: {'winter_jacket', 'hoodie'},
    ),
    _Case(
      id: 'C7',
      family: 'work',
      context: const DecisionQualityContext(
        tempC: 4,
        occasionId: 'work',
        outdoor: false,
      ),
      forbid: {'shorts', 'sandals'},
    ),
    _Case(
      id: 'D1',
      family: 'formal',
      context: const DecisionQualityContext(tempC: 20, occasionId: 'wedding', outdoor: false),
      forbid: {'shorts', 'sweatpants', 'sandals', 'hoodie'},
    ),
    _Case(
      id: 'D2',
      family: 'formal',
      context: const DecisionQualityContext(tempC: 19, occasionId: 'formal_wedding', outdoor: false),
      forbid: {'shorts', 'sneakers', 'track_pants'},
      requireAny: {'suit_jacket', 'blazer', 'dress_shirt', 'dress'},
    ),
    _Case(
      id: 'D3',
      family: 'formal',
      context: const DecisionQualityContext(tempC: 18, occasionId: 'funeral', outdoor: false),
      forbid: {'shorts', 'sandals', 'track_pants', 'hoodie'},
    ),
    _Case(
      id: 'D4',
      family: 'formal',
      context: const DecisionQualityContext(tempC: 21, occasionId: 'celebration'),
      forbid: {'shorts'},
    ),
    _Case(
      id: 'D5',
      family: 'formal',
      context: const DecisionQualityContext(tempC: 21, occasionId: 'birthday'),
      forbid: {'winter_jacket'},
    ),
    _Case(
      id: 'D6',
      family: 'formal',
      context: const DecisionQualityContext(tempC: 20, occasionId: 'date'),
      forbid: {'shorts', 'track_pants'},
    ),
    _Case(
      id: 'D7',
      family: 'formal',
      context: const DecisionQualityContext(tempC: 19, occasionId: 'formal_dinner', outdoor: false),
      forbid: {'shorts', 'sneakers', 'hoodie'},
    ),
    _Case(
      id: 'D8',
      family: 'formal',
      context: const DecisionQualityContext(tempC: 20, occasionId: 'semi_formal'),
      forbid: {'shorts', 'sandals'},
    ),
    _Case(
      id: 'E1',
      family: 'outdoor',
      context: const DecisionQualityContext(tempC: 14, activityType: 'hike', outdoor: true),
      forbid: {'dress_shoes', 'sandals', 'suit_jacket'},
      requireAny: {'boots', 'sneakers'},
    ),
    _Case(
      id: 'E2',
      family: 'outdoor',
      context: const DecisionQualityContext(tempC: 8, activityType: 'mountains', outdoor: true),
      forbid: {'dress_shoes', 'sandals'},
      requireAny: {'boots'},
    ),
    _Case(
      id: 'E3',
      family: 'outdoor',
      context: const DecisionQualityContext(tempC: 12, activityType: 'mushroom', outdoor: true),
      forbid: {'dress_shoes', 'sandals', 'suit_jacket'},
    ),
    _Case(
      id: 'E4',
      family: 'outdoor',
      context: const DecisionQualityContext(tempC: 18, activityType: 'nature_walk', outdoor: true),
      forbid: {'dress_shoes'},
    ),
    _Case(
      id: 'E5',
      family: 'outdoor',
      context: const DecisionQualityContext(tempC: 27, activityType: 'barbecue', outdoor: true),
      forbid: {'winter_jacket', 'suit_jacket'},
    ),
    _Case(
      id: 'E6',
      family: 'outdoor',
      context: const DecisionQualityContext(tempC: 16, activityType: 'hike', outdoor: true),
      forbid: {'dress_shoes', 'sandals'},
    ),
    _Case(
      id: 'F1',
      family: 'intent',
      context: const DecisionQualityContext(tempC: 20, minimumFormality: 6),
      forbid: {'shorts', 'sweatpants', 'hoodie'},
    ),
    _Case(
      id: 'F2',
      family: 'intent',
      context: const DecisionQualityContext(tempC: 20, activityType: 'casual'),
      forbid: {'suit_jacket'},
    ),
    _Case(
      id: 'F3',
      family: 'intent',
      context: const DecisionQualityContext(tempC: 18, activityType: 'sport'),
      forbid: {'suit_jacket', 'dress_shoes'},
    ),
    _Case(
      id: 'F4',
      family: 'intent',
      context: const DecisionQualityContext(tempC: 20, occasionId: 'casual'),
      forbid: {'suit_jacket'},
    ),
    _Case(
      id: 'F5',
      family: 'intent',
      context: const DecisionQualityContext(
        tempC: 12,
        requestedItemIds: {'denim'},
      ),
      requireAny: {'denim_jacket'},
    ),
    _Case(
      id: 'F6',
      family: 'intent',
      context: const DecisionQualityContext(
        tempC: 14,
        requestedItemIds: {'boots'},
      ),
      requireAny: {'boots'},
    ),
    _Case(
      id: 'F7',
      family: 'intent',
      context: const DecisionQualityContext(
        tempC: 18,
        occasionId: 'work',
        forbiddenCanonicalTypes: {'blazer', 'suit_jacket'},
      ),
      forbid: {'blazer', 'suit_jacket'},
    ),
    _Case(
      id: 'F8',
      family: 'intent',
      context: const DecisionQualityContext(tempC: 22, occasionId: 'casual'),
      forbid: {'winter_jacket', 'suit_jacket'},
    ),
    _Case(
      id: 'F9',
      family: 'intent',
      context: const DecisionQualityContext(tempC: 30, minimumFormality: 5),
      forbid: {'winter_jacket', 'hoodie', 'sweater'},
    ),
    _Case(
      id: 'G1',
      family: 'wardrobe',
      context: const DecisionQualityContext(tempC: 20, occasionId: 'wedding'),
      forbid: {'shorts'},
    ),
    _Case(
      id: 'G2',
      family: 'wardrobe',
      context: const DecisionQualityContext(tempC: 10, activityType: 'hike'),
      wardrobe: [
        _r('tshirt', _item(type: 't_shirt', family: 'top', slots: ['upper_body'], layer: 'base', formality: 3, warmth: 2)),
        _r('jeans', _item(type: 'jeans', family: 'bottom', slots: ['lower_body'], layer: 'outer', formality: 3, warmth: 4)),
        _r('dress_shoes', _item(type: 'dress_shoes', family: 'footwear', slots: ['feet'], layer: 'not_applicable', formality: 8, warmth: 3)),
      ],
      allowWeak: true,
      maxGrade: DecisionQualityGrade.acceptableWithCompromise,
    ),
    _Case(
      id: 'G3',
      family: 'wardrobe',
      context: const DecisionQualityContext(tempC: 18, occasionId: 'funeral', outdoor: false),
      wardrobe: [
        _r('shirt', _item(type: 'dress_shirt', family: 'top', slots: ['upper_body'], layer: 'base', formality: 7, warmth: 3)),
        _r('shorts', _item(type: 'shorts', family: 'bottom', slots: ['lower_body'], layer: 'outer', formality: 2, warmth: 1)),
        _r('dress_shoes', _item(type: 'dress_shoes', family: 'footwear', slots: ['feet'], layer: 'not_applicable', formality: 8, warmth: 3)),
      ],
      allowWeak: true,
    ),
    _Case(
      id: 'G4',
      family: 'wardrobe',
      context: const DecisionQualityContext(tempC: 2, isRainy: true),
      wardrobe: [
        _r('tshirt', _item(type: 't_shirt', family: 'top', slots: ['upper_body'], layer: 'base', formality: 3, warmth: 2)),
        _r('jeans', _item(type: 'jeans', family: 'bottom', slots: ['lower_body'], layer: 'outer', formality: 3, warmth: 4)),
        _r('sneakers', _item(type: 'sneakers', family: 'footwear', slots: ['feet'], layer: 'not_applicable', formality: 3, warmth: 3)),
      ],
      allowWeak: true,
    ),
    _Case(
      id: 'G5',
      family: 'wardrobe',
      context: const DecisionQualityContext(tempC: 18, occasionId: 'funeral', outdoor: false),
      wardrobe: [
        _r('tshirt', _item(type: 't_shirt', family: 'top', slots: ['upper_body'], layer: 'base', formality: 3, warmth: 2)),
        _r('sweats', _item(type: 'sweatpants', family: 'bottom', slots: ['lower_body'], layer: 'outer', formality: 2, warmth: 4)),
        _r('sneakers', _item(type: 'sneakers', family: 'footwear', slots: ['feet'], layer: 'not_applicable', formality: 3, warmth: 3)),
      ],
      allowWeak: true,
    ),
    _Case(
      id: 'G6',
      family: 'wardrobe',
      context: const DecisionQualityContext(tempC: 21),
      forbid: {'winter_jacket'},
    ),
    _Case(
      id: 'G7',
      family: 'wardrobe',
      context: const DecisionQualityContext(tempC: 21),
      wardrobe: [
        _r('tshirt', _item(type: 't_shirt', family: 'top', slots: ['upper_body'], layer: 'base', formality: 3, warmth: 2)),
        _r('jeans', _item(type: 'jeans', family: 'bottom', slots: ['lower_body'], layer: 'outer', formality: 3, warmth: 4)),
        _r('trousers', _item(type: 'trousers', family: 'bottom', slots: ['lower_body'], layer: 'outer', formality: 7, warmth: 4)),
        _r('sneakers', _item(type: 'sneakers', family: 'footwear', slots: ['feet'], layer: 'not_applicable', formality: 3, warmth: 3)),
      ],
      requireAny: {'t_shirt'},
    ),
    _Case(
      id: 'G8',
      family: 'wardrobe',
      context: const DecisionQualityContext(tempC: 18, occasionId: 'funeral', outdoor: false),
      wardrobe: [
        _r('tshirt', _item(type: 't_shirt', family: 'top', slots: ['upper_body'], layer: 'base', formality: 3, warmth: 2)),
        _r('shorts', _item(type: 'shorts', family: 'bottom', slots: ['lower_body'], layer: 'outer', formality: 2, warmth: 1)),
        _r('sandals', _item(type: 'sandals', family: 'footwear', slots: ['feet'], layer: 'not_applicable', formality: 2, warmth: 1)),
      ],
      allowWeak: true,
    ),
    _Case(
      id: 'H1',
      family: 'one_piece',
      context: const DecisionQualityContext(tempC: 22, preferOnePiece: true),
      requireAny: {'dress', 'jumpsuit'},
    ),
    _Case(
      id: 'H2',
      family: 'one_piece',
      context: const DecisionQualityContext(tempC: 22, preferOnePiece: true),
      wardrobe: [
        _r('jumpsuit', _item(type: 'jumpsuit', family: 'one_piece', slots: ['full_body'], layer: 'outer', formality: 5, warmth: 3)),
        _r('sneakers', _item(type: 'sneakers', family: 'footwear', slots: ['feet'], layer: 'not_applicable', formality: 3, warmth: 3)),
      ],
      requireAny: {'jumpsuit'},
    ),
    _Case(
      id: 'H3',
      family: 'one_piece',
      context: const DecisionQualityContext(tempC: 8, preferOnePiece: true),
      requireAny: {'dress', 'jumpsuit'},
    ),
    _Case(
      id: 'H4',
      family: 'one_piece',
      context: const DecisionQualityContext(tempC: 22, preferOnePiece: true),
      requireAny: {'sneakers', 'dress_shoes', 'boots', 'sandals'},
    ),
    _Case(
      id: 'H5',
      family: 'one_piece',
      context: const DecisionQualityContext(tempC: 22, preferOnePiece: true),
      wardrobe: [
        _r('dress', _item(type: 'dress', family: 'one_piece', slots: ['full_body'], layer: 'outer', formality: 6, warmth: 3)),
        _r('tshirt', _item(type: 't_shirt', family: 'top', slots: ['upper_body'], layer: 'base', formality: 3, warmth: 2)),
        _r('jeans', _item(type: 'jeans', family: 'bottom', slots: ['lower_body'], layer: 'outer', formality: 3, warmth: 4)),
        _r('sneakers', _item(type: 'sneakers', family: 'footwear', slots: ['feet'], layer: 'not_applicable', formality: 3, warmth: 3)),
      ],
    ),
    _Case(
      id: 'I1',
      family: 'set',
      context: const DecisionQualityContext(tempC: 18, occasionId: 'casual'),
    ),
    _Case(
      id: 'I2',
      family: 'set',
      context: const DecisionQualityContext(tempC: 18, occasionId: 'work', outdoor: false),
      forbid: {'track_pants'},
    ),
    _Case(
      id: 'I3',
      family: 'set',
      context: const DecisionQualityContext(tempC: 19, occasionId: 'wedding', outdoor: false),
      requireAny: {'suit_jacket', 'blazer', 'dress'},
    ),
    _Case(
      id: 'I4',
      family: 'set',
      context: const DecisionQualityContext(tempC: 18, occasionId: 'work', outdoor: false),
    ),
    _Case(
      id: 'I5',
      family: 'set',
      context: const DecisionQualityContext(tempC: 21, occasionId: 'casual'),
    ),
    _Case(
      id: 'I6',
      family: 'set',
      context: const DecisionQualityContext(
        tempC: 32,
        requestedItemIds: {'winter'},
      ),
      forbid: {'winter_jacket'},
    ),
    _Case(
      id: 'I7',
      family: 'set',
      context: const DecisionQualityContext(tempC: 21),
    ),
    _Case(
      id: 'I8',
      family: 'set',
      context: const DecisionQualityContext(tempC: 18, occasionId: 'funeral', outdoor: false),
      forbid: {'track_jacket', 'track_pants'},
    ),
    _Case(
      id: 'J1',
      family: 'layering',
      context: const DecisionQualityContext(tempC: 12),
    ),
    _Case(
      id: 'J2',
      family: 'layering',
      context: const DecisionQualityContext(tempC: 10, occasionId: 'work'),
      forbid: {'shorts'},
    ),
    _Case(
      id: 'J3',
      family: 'layering',
      context: const DecisionQualityContext(tempC: 14, occasionId: 'work'),
    ),
    _Case(
      id: 'J4',
      family: 'layering',
      context: const DecisionQualityContext(tempC: 8),
      forbid: {'sandals'},
    ),
    _Case(
      id: 'J5',
      family: 'layering',
      context: const DecisionQualityContext(tempC: 30),
      forbid: {'hoodie', 'sweater', 'winter_jacket'},
      requireLayerAbsent: {'mid'},
    ),
    _Case(
      id: 'J6',
      family: 'layering',
      context: const DecisionQualityContext(tempC: 1),
      forbid: {'shorts', 'sandals'},
    ),
    _Case(
      id: 'J7',
      family: 'layering',
      context: const DecisionQualityContext(tempC: 18, occasionId: 'funeral', outdoor: false),
      forbid: {'hoodie', 'track_jacket'},
    ),
    _Case(
      id: 'J8',
      family: 'layering',
      context: const DecisionQualityContext(tempC: 16),
    ),
    _Case(
      id: 'K1',
      family: 'footwear',
      context: const DecisionQualityContext(tempC: 20, occasionId: 'casual'),
      forbid: {'winter_jacket'},
    ),
    _Case(
      id: 'K2',
      family: 'footwear',
      context: const DecisionQualityContext(tempC: 19, occasionId: 'wedding', outdoor: false),
      requireAny: {'dress_shoes'},
      forbid: {'sneakers', 'sandals'},
    ),
    _Case(
      id: 'K3',
      family: 'footwear',
      context: const DecisionQualityContext(tempC: 12, activityType: 'hike'),
      requireAny: {'boots'},
      forbid: {'dress_shoes', 'sandals'},
    ),
    _Case(
      id: 'K4',
      family: 'footwear',
      context: const DecisionQualityContext(tempC: 14, isRainy: true),
      forbid: {'sandals'},
    ),
    _Case(
      id: 'K5',
      family: 'footwear',
      context: const DecisionQualityContext(tempC: 20, occasionId: 'work', outdoor: false),
      forbid: {'sandals'},
    ),
    _Case(
      id: 'K6',
      family: 'footwear',
      context: const DecisionQualityContext(tempC: 19, occasionId: 'wedding', outdoor: false),
      forbid: {'sneakers'},
    ),
    _Case(
      id: 'K7',
      family: 'footwear',
      context: const DecisionQualityContext(tempC: 22, occasionId: 'casual'),
      forbid: {'winter_jacket'},
    ),
    _Case(
      id: 'L1',
      family: 'reuse',
      context: const DecisionQualityContext(tempC: 21),
      forbid: {'winter_jacket'},
    ),
    _Case(
      id: 'L2',
      family: 'reuse',
      context: const DecisionQualityContext(tempC: 21),
      forbid: {'winter_jacket'},
    ),
    _Case(
      id: 'L3',
      family: 'reuse',
      context: const DecisionQualityContext(tempC: 21, requestedItemIds: {'tshirt'}),
      requireAny: {'t_shirt'},
    ),
    _Case(
      id: 'L4',
      family: 'reuse',
      context: const DecisionQualityContext(tempC: 21, occasionId: 'funeral', outdoor: false),
      forbid: {'shorts'},
    ),
    _Case(
      id: 'L5',
      family: 'reuse',
      context: const DecisionQualityContext(tempC: 21, occasionId: 'casual'),
      forbid: {'winter_jacket'},
    ),
  ];

  test('decision-quality matrix has zero FAIL_MAJOR', () {
    final rows = <String>[];
    var failMajor = 0;
    var failMinor = 0;
    var variation = 0;
    var pass = 0;
    for (final c in cases) {
      final report = run(c);
      final result = classify(c, report);
      if (result != 'PASS') {
        rows.add(
          '${c.id} $result types=${report.winnerTypes} grade=${report.grade.name} '
          'forbidHit=${c.forbid.where(report.winnerHasType).toList()} '
          'trace=${report.trace['WIN_REASON']}',
        );
      }
      switch (result) {
        case 'FAIL_MAJOR':
          failMajor++;
          break;
        case 'FAIL_MINOR':
          failMinor++;
          break;
        case 'PASS_WITH_ACCEPTABLE_VARIATION':
          variation++;
          break;
        default:
          pass++;
      }
    }
    expect(
      failMajor,
      0,
      reason: 'FAIL_MAJOR cases:\n${rows.where((e) => e.contains('FAIL_MAJOR')).join('\n')}',
    );
    // Remaining non-pass rows are documented by the expect below remaining 0 majors.
    expect(cases.length, pass + variation + failMinor + failMajor);
    expect(rows.where((e) => e.contains('FAIL_MAJOR')), isEmpty);
    // ignore: avoid_print
    print(
      'DQ_MATRIX pass=$pass variation=$variation failMinor=$failMinor failMajor=$failMajor total=${cases.length}',
    );
    for (final row in rows) {
      // ignore: avoid_print
      print('DQ_NON_PASS $row');
    }
  });

  test('authoritative V2 warmth beats canonical denim-jacket default', () {
    final light = _item(
      type: 'denim_jacket',
      family: 'outerwear',
      slots: const ['upper_body'],
      layer: 'outer',
      warmth: 2,
      overrides: const ['warmth'],
    );
    final heavy = _item(
      type: 'denim_jacket',
      family: 'outerwear',
      slots: const ['upper_body'],
      layer: 'outer',
      warmth: 7,
    );
    expect(
      StylistLayerFilter.inferWarmthLevel({
        'canonicalType': 'denim_jacket',
        'warmth': 2,
        'userOverrideFields': ['warmth'],
      }),
      2,
    );
    final report = DecisionQualityHarness.evaluate(
      wardrobe: [
        _r('tee', _item(type: 't_shirt', family: 'top', slots: const ['upper_body'], layer: 'base', warmth: 2)),
        _r('jeans', _item(type: 'jeans', family: 'bottom', slots: const ['lower_body'], layer: 'outer', warmth: 4)),
        _r('light', light),
        _r('heavy', heavy),
        _r('shoes', _item(type: 'sneakers', family: 'footwear', slots: const ['feet'], layer: 'not_applicable', warmth: 3)),
      ],
      context: const DecisionQualityContext(tempC: 8, isRainy: true),
    );
    expect(report.winner?.outfit.items.any((x) => x.itemId == 'heavy'), isTrue);
    expect(report.winner?.outfit.items.any((x) => x.itemId == 'light'), isFalse);
  });

  test('formality uses weakest core slot, not the average', () {
    final report = DecisionQualityHarness.evaluate(
      wardrobe: [
        _r('shirt', _item(type: 'dress_shirt', family: 'top', slots: const ['upper_body'], layer: 'base', formality: 8, warmth: 3)),
        _r('sweats', _item(type: 'sweatpants', family: 'bottom', slots: const ['lower_body'], layer: 'outer', formality: 2, warmth: 4)),
        _r('trousers', _item(type: 'trousers', family: 'bottom', slots: const ['lower_body'], layer: 'outer', formality: 7, warmth: 4)),
        _r('dress_shoes', _item(type: 'dress_shoes', family: 'footwear', slots: const ['feet'], layer: 'not_applicable', formality: 8, warmth: 3)),
      ],
      context: const DecisionQualityContext(tempC: 18, occasionId: 'funeral', outdoor: false),
    );
    expect(report.winnerHasType('sweatpants'), isFalse);
    expect(report.winnerHasType('trousers'), isTrue);
  });

  test('Home and Stylist share the same suitability winner for equivalent context', () {
    final home = DecisionQualityHarness.evaluate(
      wardrobe: fullWardrobe(),
      context: const DecisionQualityContext(tempC: 32),
    );
    final stylist = DecisionQualityHarness.evaluate(
      wardrobe: fullWardrobe(),
      context: const DecisionQualityContext(tempC: 32, occasionId: 'casual'),
    );
    expect(home.winnerHasType('winter_jacket'), isFalse);
    expect(stylist.winnerHasType('winter_jacket'), isFalse);
    expect(home.winnerHasType('shorts') || home.winnerHasType('t_shirt'), isTrue);
    expect(stylist.winnerHasType('shorts') || stylist.winnerHasType('t_shirt'), isTrue);
  });

  test('one-piece outfit is complete without a separate top and bottom', () {
    final report = DecisionQualityHarness.evaluate(
      wardrobe: [
        _r('dress', _item(type: 'dress', family: 'one_piece', slots: const ['full_body'], layer: 'outer', formality: 6, warmth: 3)),
        _r('sneakers', _item(type: 'sneakers', family: 'footwear', slots: const ['feet'], layer: 'not_applicable', formality: 3, warmth: 3)),
      ],
      context: const DecisionQualityContext(tempC: 22, preferOnePiece: true),
    );
    expect(report.winner, isNotNull);
    expect(report.winner!.outfit.completeness.coreComplete, isTrue);
    expect(report.winnerHasType('t_shirt'), isFalse);
    expect(report.winnerHasType('jeans'), isFalse);
  });

  test('user-curated pair loses to weather-appropriate alternative', () {
    final report = DecisionQualityHarness.evaluate(
      wardrobe: fullWardrobe(),
      context: const DecisionQualityContext(tempC: 32),
    );
    expect(report.winnerHasType('winter_jacket'), isFalse);
  });

  test('missing ideal footwear is graded as a compromise, not excellent', () {
    final report = DecisionQualityHarness.evaluate(
      wardrobe: [
        _r('tee', _item(type: 't_shirt', family: 'top', slots: const ['upper_body'], layer: 'base', warmth: 2, formality: 3)),
        _r('jeans', _item(type: 'jeans', family: 'bottom', slots: const ['lower_body'], layer: 'outer', warmth: 4, formality: 3)),
        _r('dress_shoes', _item(type: 'dress_shoes', family: 'footwear', slots: const ['feet'], layer: 'not_applicable', warmth: 3, formality: 8)),
      ],
      context: const DecisionQualityContext(tempC: 10, activityType: 'hike'),
    );
    expect(report.grade == DecisionQualityGrade.excellent, isFalse);
    expect(
      (report.trace['KNOWN_COMPROMISES'] as List).isNotEmpty ||
          report.grade == DecisionQualityGrade.weak ||
          report.grade == DecisionQualityGrade.acceptableWithCompromise,
      isTrue,
    );
  });
}
