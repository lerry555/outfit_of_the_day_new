import 'wardrobe_set_v2.dart';

class WardrobeSetMutationPlanV2 {
  const WardrobeSetMutationPlanV2({
    required this.remainingMemberIds,
    required this.dissolve,
  });
  final List<String> remainingMemberIds;
  final bool dissolve;
}

abstract final class WardrobeSetPolicyV2 {
  static WardrobeSetMutationPlanV2 removeMember(
    Iterable<String> memberIds,
    String removedId,
  ) {
    final remaining = memberIds
        .where((id) => id != removedId)
        .toSet()
        .toList(growable: false);
    return WardrobeSetMutationPlanV2(
      remainingMemberIds: remaining,
      dissolve: remaining.length < 2,
    );
  }

  static bool canComplete(Iterable<String> memberIds) =>
      memberIds.toSet().length >= 2;

  static bool canAddInInitialUi(Iterable<String> memberIds) =>
      memberIds.toSet().length < 6;

  static double contextualCompatibility({
    required WardrobeSetTypeV2 setType,
    required WardrobeSetRelationshipSourceV2 source,
    required int minimumFormality,
    required bool comparableAlternative,
  }) {
    final base = source == WardrobeSetRelationshipSourceV2.userCurated
        ? 2.2
        : 1.8;
    if (setType == WardrobeSetTypeV2.suit && minimumFormality >= 7) return 3;
    return comparableAlternative ? base : base * .75;
  }
}
