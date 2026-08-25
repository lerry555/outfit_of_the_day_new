import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/stylist_chat_outfit_service.dart';
import 'package:outfitofTheDay/Services/stylist_frozen_candidate_decision_service.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/flexible_candidate_matrix_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_item_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_v2_resolver.dart';

WardrobeItemV2 _item(
  String type,
  String family,
  List<String> slots,
  String layer,
) => WardrobeItemV2(
  canonicalType: type,
  canonicalFamily: family,
  bodySlots: slots,
  layerPosition: layer,
  outfitFunctions: const <String>[],
  colorProfile: const ColorProfileV2(
    primary: SemanticColorV2(family: 'black'),
    metalTone: 'none',
    hardwareTone: 'none',
  ),
  formality: 4,
  styles: const <String>[],
  occasionFit: const <String>[],
  seasons: const <String>[],
  warmth: 4,
  attributes: const <String, dynamic>{},
  fieldSources: const <String, dynamic>{'canonicalType': 'fixture'},
  fieldConfidence: const <String, dynamic>{'canonicalType': 1.0},
  userOverrideFields: const <String>[],
);

ResolvedWardrobeItemV2 _resolved(String id, WardrobeItemV2 item) =>
    ResolvedWardrobeItemV2(itemId: id, item: item, raw: <String, dynamic>{'id': id});

void main() {
  final context = const V2CandidateMatrixContext(preferOnePiece: true);
  final wardrobe = <ResolvedWardrobeItemV2>[
    _resolved('dress-a', _item('dress', 'one_piece', <String>['full_body'], 'outer')),
    _resolved('dress-b', _item('jumpsuit', 'one_piece', <String>['full_body'], 'outer')),
    _resolved('shoes', _item('sneakers', 'footwear', <String>['feet'], 'not_applicable')),
  ];

  test('valid explicit swap returns the deterministic validated replacement', () {
    final matrix = V2FlexibleCandidateMatrix.generate(
      wardrobe: wardrobe,
      context: context,
    );
    final current = matrix.first.outfit;
    final replacement = V2FlexibleSwapOrchestrator.replace(
      current: current,
      itemId: current.items
          .singleWhere((item) => item.item.bodySlots.contains('full_body'))
          .itemId,
      wardrobe: wardrobe,
      context: context,
    );

    final selected = requireExplicitStylistSwapReplacementV1(replacement);

    expect(selected, same(replacement));
    expect(selected.validate(), isEmpty);
    expect(selected.items.any((item) => item.itemId == 'dress-b'), isTrue);
  });

  test('impossible explicit swap never substitutes the first matrix outfit', () {
    final noReplacementWardrobe = <ResolvedWardrobeItemV2>[
      wardrobe.first,
      wardrobe.last,
    ];
    final matrix = V2FlexibleCandidateMatrix.generate(
      wardrobe: noReplacementWardrobe,
      context: context,
    );
    final firstCandidate = matrix.first.outfit;
    final replacement = V2FlexibleSwapOrchestrator.replace(
      current: firstCandidate,
      itemId: firstCandidate.items
          .singleWhere((item) => item.item.bodySlots.contains('full_body'))
          .itemId,
      wardrobe: noReplacementWardrobe,
      context: context,
    );

    expect(replacement, isNull);
    expect(
      () => requireExplicitStylistSwapReplacementV1(replacement),
      throwsA(isA<StylistFrozenDecisionRejectedExceptionV1>()),
    );
    expect(firstCandidate.validate(), isEmpty);
  });

  test('impossible explicit swap fails closed with the Stylist rejection', () {
    expect(
      () => requireExplicitStylistSwapReplacementV1(null),
      throwsA(
        isA<StylistFrozenDecisionRejectedExceptionV1>()
            .having(
              (error) => error.reasonCodes,
              'reasonCodes',
              contains('swap_replacement_unavailable'),
            )
            .having(
              (error) => error.explanation,
              'explanation',
              isNotEmpty,
            ),
      ),
    );
  });
}
