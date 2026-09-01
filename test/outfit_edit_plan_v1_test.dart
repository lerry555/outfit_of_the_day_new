import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/flexible_candidate_matrix_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/outfit_edit_executor_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/outfit_edit_plan_v1.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_item_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_v2_resolver.dart';
import 'package:outfitofTheDay/utils/stylist_outfit_edit_routing.dart';
import 'package:outfitofTheDay/utils/stylist_swap_request.dart';

WardrobeItemV2 _item({
  required String type,
  required String family,
  required List<String> slots,
  required String layer,
  String color = 'black',
  int warmth = 4,
}) => WardrobeItemV2(
  canonicalType: type,
  canonicalFamily: family,
  bodySlots: slots,
  layerPosition: layer,
  colorProfile: ColorProfileV2(
    primary: SemanticColorV2(family: color),
    metalTone: 'none',
    hardwareTone: 'none',
  ),
  formality: 4,
  styles: const <String>[],
  occasionFit: const <String>[],
  seasons: const <String>['all_season'],
  warmth: warmth,
  attributes: const <String, dynamic>{},
  fieldSources: const <String, dynamic>{'canonicalType': 'fixture'},
  fieldConfidence: const <String, dynamic>{'canonicalType': 1.0},
  userOverrideFields: const <String>[],
);

ResolvedWardrobeItemV2 _resolved(String id, WardrobeItemV2 item) =>
    ResolvedWardrobeItemV2(
      itemId: id,
      item: item,
      raw: <String, dynamic>{'id': id, 'name': id},
    );

final _wardrobe = <ResolvedWardrobeItemV2>[
  _resolved(
    'top-current',
    _item(
      type: 't_shirt',
      family: 'top',
      slots: const <String>['upper_body'],
      layer: 'base',
      warmth: 2,
    ),
  ),
  _resolved(
    'top-next',
    _item(
      type: 'polo',
      family: 'top',
      slots: const <String>['upper_body'],
      layer: 'base',
      color: 'white',
      warmth: 3,
    ),
  ),
  _resolved(
    'jeans-current',
    _item(
      type: 'jeans',
      family: 'bottom',
      slots: const <String>['lower_body'],
      layer: 'outer',
      color: 'blue',
      warmth: 5,
    ),
  ),
  _resolved(
    'shorts-next',
    _item(
      type: 'shorts',
      family: 'bottom',
      slots: const <String>['lower_body'],
      layer: 'outer',
      color: 'beige',
      warmth: 2,
    ),
  ),
  _resolved(
    'shoes-current',
    _item(
      type: 'sneakers',
      family: 'footwear',
      slots: const <String>['feet'],
      layer: 'not_applicable',
      color: 'white',
      warmth: 3,
    ),
  ),
  _resolved(
    'shoes-red',
    _item(
      type: 'sneakers',
      family: 'footwear',
      slots: const <String>['feet'],
      layer: 'not_applicable',
      color: 'red',
      warmth: 3,
    ),
  ),
  _resolved(
    'shoes-blue',
    _item(
      type: 'sneakers',
      family: 'footwear',
      slots: const <String>['feet'],
      layer: 'not_applicable',
      color: 'blue',
      warmth: 3,
    ),
  ),
  _resolved(
    'hoodie-next',
    _item(
      type: 'hoodie',
      family: 'top',
      slots: const <String>['upper_body'],
      layer: 'mid',
      color: 'gray',
      warmth: 5,
    ),
  ),
];

const _context = V2CandidateMatrixContext(maxCandidates: 8, tempC: 20);
const _currentIds = <String>{'top-current', 'jeans-current', 'shoes-current'};

Map<String, dynamic> _plan(
  List<Map<String, dynamic>> operations, {
  String intent = 'edit_current_outfit',
}) => <String, dynamic>{
  'contractVersion': 'outfit_edit_plan_v1',
  'intent': intent,
  'operations': operations,
  'presentation': intent == 'edit_current_outfit' ? 'concise_full' : 'normal',
};

void main() {
  final current = OutfitEditExecutorV1.restoreCurrent(
    wardrobe: _wardrobe,
    currentItemIds: _currentIds,
    context: _context,
  )!;

  test(
    'canonical multi-slot edit keeps all operations and default preserves',
    () {
      final plan = OutfitEditPlanV1.tryParse(
        _plan(<Map<String, dynamic>>[
          <String, dynamic>{
            'slot': 'top',
            'action': 'replace',
            'constraints': <String, dynamic>{},
          },
          <String, dynamic>{
            'slot': 'bottom',
            'action': 'replace',
            'constraints': <String, dynamic>{},
          },
          <String, dynamic>{
            'slot': 'shoes',
            'action': 'replace',
            'constraints': <String, dynamic>{'color': 'red'},
          },
        ]),
      )!;

      expect(plan.operations, hasLength(7));
      expect(
        plan.operationFor(OutfitEditSlotV1.layers).action,
        OutfitEditActionV1.preserve,
      );
      expect(
        plan.operationFor(OutfitEditSlotV1.shoes).constraints.color,
        'red',
      );
      expect(
        OutfitEditPlanV1.tryParse(
          _plan(<Map<String, dynamic>>[
            <String, dynamic>{
              'slot': 'shoes',
              'action': 'replace',
              'constraints': <String, dynamic>{'colour': 'red'},
            },
          ]),
        ),
        isNull,
      );
    },
  );

  test('add and replace execute atomically while preserving top and shoes', () {
    final plan = OutfitEditPlanV1.tryParse(
      _plan(<Map<String, dynamic>>[
        <String, dynamic>{
          'slot': 'bottom',
          'action': 'replace',
          'constraints': <String, dynamic>{'family': 'shorts'},
        },
        <String, dynamic>{
          'slot': 'layers',
          'action': 'add',
          'constraints': <String, dynamic>{'type': 'hoodie'},
        },
      ]),
    )!;
    final candidates = OutfitEditExecutorV1.generateCandidates(
      plan: plan,
      current: current,
      wardrobe: _wardrobe,
      context: _context,
    );

    expect(candidates, isNotEmpty);
    for (final candidate in candidates) {
      final ids = candidate.outfit.items.map((item) => item.itemId).toSet();
      expect(ids, containsAll(<String>['top-current', 'shoes-current']));
      expect(ids, containsAll(<String>['shorts-next', 'hoodie-next']));
      expect(ids, isNot(contains('jeans-current')));
      expect(candidate.outfit.validate(), isEmpty);
    }
  });

  test(
    'red shoes constraint excludes otherwise valid non-red replacements',
    () {
      final plan = OutfitEditPlanV1.tryParse(
        _plan(<Map<String, dynamic>>[
          <String, dynamic>{
            'slot': 'shoes',
            'action': 'replace',
            'constraints': <String, dynamic>{'color': 'red'},
          },
        ]),
      )!;
      final candidates = OutfitEditExecutorV1.generateCandidates(
        plan: plan,
        current: current,
        wardrobe: _wardrobe,
        context: _context,
      );

      expect(candidates, isNotEmpty);
      expect(
        candidates.every(
          (candidate) =>
              candidate.outfit.items.any((item) => item.itemId == 'shoes-red'),
        ),
        isTrue,
      );
      expect(
        candidates.any(
          (candidate) =>
              candidate.outfit.items.any((item) => item.itemId == 'shoes-blue'),
        ),
        isFalse,
      );
    },
  );

  test('warmer, cooler and excluded-color constraints are hard filters', () {
    final warmerTop = OutfitEditPlanV1.tryParse(
      _plan(<Map<String, dynamic>>[
        <String, dynamic>{
          'slot': 'top',
          'action': 'replace',
          'constraints': <String, dynamic>{
            'thermal': 'warmer',
            'excludedColor': 'black',
          },
        },
      ]),
    )!;
    final warmerCandidates = OutfitEditExecutorV1.generateCandidates(
      plan: warmerTop,
      current: current,
      wardrobe: _wardrobe,
      context: _context,
    );
    expect(warmerCandidates, isNotEmpty);
    expect(
      warmerCandidates.every(
        (candidate) =>
            candidate.outfit.items.any((item) => item.itemId == 'top-next'),
      ),
      isTrue,
    );

    final coolerBottom = OutfitEditPlanV1.tryParse(
      _plan(<Map<String, dynamic>>[
        <String, dynamic>{
          'slot': 'bottom',
          'action': 'replace',
          'constraints': <String, dynamic>{
            'family': 'shorts',
            'thermal': 'cooler',
          },
        },
      ]),
    )!;
    expect(
      OutfitEditExecutorV1.generateCandidates(
        plan: coolerBottom,
        current: current,
        wardrobe: _wardrobe,
        context: _context,
      ),
      isNotEmpty,
    );
  });

  test('remove operation emits only complete atomic candidates', () {
    final layeredCurrent = OutfitEditExecutorV1.restoreCurrent(
      wardrobe: _wardrobe,
      currentItemIds: <String>{..._currentIds, 'hoodie-next'},
      context: _context,
    )!;
    final removeLayer = OutfitEditPlanV1.tryParse(
      _plan(<Map<String, dynamic>>[
        <String, dynamic>{
          'slot': 'layers',
          'action': 'remove',
          'constraints': <String, dynamic>{},
        },
      ]),
    )!;
    final candidates = OutfitEditExecutorV1.generateCandidates(
      plan: removeLayer,
      current: layeredCurrent,
      wardrobe: _wardrobe,
      context: _context,
    );

    expect(candidates, isNotEmpty);
    expect(
      candidates.every(
        (candidate) => candidate.outfit.items.every(
          (item) => item.itemId != 'hoodie-next',
        ),
      ),
      isTrue,
    );
  });

  test('explanation plan has no mutation and never invokes legacy parser', () {
    var legacyCalls = 0;
    final routing = StylistOutfitEditRoutingV1.resolve(
      response: <String, dynamic>{
        'outfitEditPlan': _plan(const <Map<String, dynamic>>[], intent: 'none'),
      },
      userText: 'preco rifle a nie kratasy?',
      legacyResolver: (_, __) {
        legacyCalls++;
        return StylistSwapRequest.parse('daj ine topanky');
      },
    );

    expect(routing.canonicalPlanPresent, isTrue);
    expect(routing.canonicalPlan!.mutatesCurrentOutfit, isFalse);
    expect(routing.legacySwap, isNull);
    expect(legacyCalls, 0);
  });

  test(
    'impossible edit yields no partial candidate and leaves current untouched',
    () {
      final plan = OutfitEditPlanV1.tryParse(
        _plan(<Map<String, dynamic>>[
          <String, dynamic>{
            'slot': 'bottom',
            'action': 'replace',
            'constraints': <String, dynamic>{'family': 'shorts'},
          },
          <String, dynamic>{
            'slot': 'layers',
            'action': 'add',
            'constraints': <String, dynamic>{'type': 'cashmere_cardigan'},
          },
        ]),
      )!;
      final before = current.items.map((item) => item.itemId).toList();
      final candidates = OutfitEditExecutorV1.generateCandidates(
        plan: plan,
        current: current,
        wardrobe: _wardrobe,
        context: _context,
      );

      expect(candidates, isEmpty);
      expect(current.items.map((item) => item.itemId).toList(), before);
      expect(
        current.items.any((item) => item.itemId == 'shorts-next'),
        isFalse,
      );
    },
  );

  test('Brain plan cannot be overwritten by a conflicting legacy parser', () {
    var legacyCalls = 0;
    final routing = StylistOutfitEditRoutingV1.resolve(
      response: <String, dynamic>{
        'outfitEditPlan': _plan(<Map<String, dynamic>>[
          <String, dynamic>{
            'slot': 'shoes',
            'action': 'replace',
            'constraints': <String, dynamic>{'color': 'red'},
          },
        ]),
      },
      userText: 'legacy would choose a bottom',
      legacyResolver: (_, __) {
        legacyCalls++;
        return const StylistSwapRequest(slot: StylistSwapSlot.bottom);
      },
    );

    expect(legacyCalls, 0);
    expect(routing.legacySwap, isNull);
    expect(
      routing.canonicalPlan!
          .operationFor(OutfitEditSlotV1.shoes)
          .constraints
          .color,
      'red',
    );
    expect(
      routing.canonicalPlan!.operationFor(OutfitEditSlotV1.bottom).action,
      OutfitEditActionV1.preserve,
    );
  });
}
