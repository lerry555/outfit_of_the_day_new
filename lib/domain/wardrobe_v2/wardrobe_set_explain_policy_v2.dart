import 'wardrobe_item_v2.dart';

abstract final class WardrobeSetExplainPolicyV2 {
  static bool shouldMention({
    required Iterable<WardrobeItemV2> selected,
    required bool deliberatelySplit,
    required bool formalContext,
  }) {
    final memberships = selected
        .map((item) => item.setMembership)
        .whereType<SetMembershipV2>()
        .toList();
    final counts = <String, int>{};
    for (final membership in memberships) {
      counts.update(membership.setId, (value) => value + 1, ifAbsent: () => 1);
    }
    return deliberatelySplit ||
        memberships.any(
          (membership) =>
              (counts[membership.setId] ?? 0) > 1 &&
              (formalContext ||
                  membership.relationshipSource == 'user_curated'),
        );
  }

  static String? reason({
    required SetMembershipV2 membership,
    required bool keptTogether,
    String? splitReason,
  }) {
    if (keptTogether) {
      return membership.relationshipSource == 'user_curated'
          ? 'Použil som tvoju obľúbenú kombináciu.'
          : 'Zvolil som k sebe kúsky z rovnakého setu.';
    }
    if (splitReason?.trim().isNotEmpty == true) {
      return 'Set som tentoraz rozdelil: ${splitReason!.trim()}';
    }
    return null;
  }
}
