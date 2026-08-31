from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, got {count}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


replace_once(
    "lib/screens/stylist_chat_screen.dart",
    """        // „Daj mi radšej kraťasy“ is a constrained re-compose: changing
        // the bottom may legitimately require a different top/shoes for a good
        // outfit. Keep strict one-piece swap only when no family was requested.
        requestedSwap: swapRequest.bottomFamily == null ? swapRequest : null,
        // Pri spodku s konkrétnou rodinou necháme generovanie rešpektovať voľbu.
""",
    """        // Explicit single-slot requests keep every other displayed item
        // frozen. A requested family (e.g. jeans -> shorts) only widens which
        // lower-body candidates may replace the current bottom.
        requestedSwap: swapRequest,
        // Pri spodku s konkrétnou rodinou necháme swap rešpektovať voľbu.
""",
)

replace_once(
    "lib/domain/wardrobe_v2/wardrobe_v2_adapters.dart",
    """    Set<String> requiredFunctions = const {},
    Iterable<WardrobeItemV2> remainingOutfit = const [],
  }) => candidates.where((candidate) {
""",
    """    Set<String> requiredFunctions = const {},
    Iterable<WardrobeItemV2> remainingOutfit = const [],
    bool allowCrossFamilySameSlot = false,
  }) => candidates.where((candidate) {
""",
)
replace_once(
    "lib/domain/wardrobe_v2/wardrobe_v2_adapters.dart",
    """    if (candidate.canonicalType == replaced.canonicalType) return true;
    if (candidate.canonicalFamily != replaced.canonicalFamily) return false;
    if (candidate.accessoryGroup != replaced.accessoryGroup) return false;
    if (candidate.bodySlots
        .toSet()
        .intersection(replaced.bodySlots.toSet())
        .isEmpty) {
      return false;
    }
""",
    """    if (candidate.canonicalType == replaced.canonicalType) return true;
    final sharesBodySlot = candidate.bodySlots
        .toSet()
        .intersection(replaced.bodySlots.toSet())
        .isNotEmpty;
    if (!sharesBodySlot) return false;
    if (candidate.canonicalFamily != replaced.canonicalFamily &&
        !allowCrossFamilySameSlot) {
      return false;
    }
    if (candidate.accessoryGroup != replaced.accessoryGroup) return false;
""",
)

replace_once(
    "lib/domain/wardrobe_v2/flexible_candidate_matrix_v2.dart",
    """    required Iterable<ResolvedWardrobeItemV2> wardrobe,
    required V2CandidateMatrixContext context,
  }) {
""",
    """    required Iterable<ResolvedWardrobeItemV2> wardrobe,
    required V2CandidateMatrixContext context,
    bool allowCrossFamilySameSlot = false,
  }) {
""",
)
replace_once(
    "lib/domain/wardrobe_v2/flexible_candidate_matrix_v2.dart",
    """            remainingOutfit: remaining,
          ).isNotEmpty,
""",
    """            remainingOutfit: remaining,
            allowCrossFamilySameSlot: allowCrossFamilySameSlot,
          ).isNotEmpty,
""",
)

replace_once(
    "lib/Services/stylist_chat_outfit_service.dart",
    """            wardrobe: resolved,
            context: context,
          ),
""",
    """            wardrobe: resolved,
            context: context,
            allowCrossFamilySameSlot: requestedSwap.bottomFamily != null,
          ),
""",
)

replace_once(
    "test/brain_v1_v2_offline_bundle_test.dart",
    """    expect(
      screen,
      contains('requestedSwap: swapRequest.bottomFamily == null ? swapRequest : null'),
    );
""",
    """    expect(screen, contains('requestedSwap: swapRequest'));
    final service = _read('lib/Services/stylist_chat_outfit_service.dart');
    final matrix = _read(
      'lib/domain/wardrobe_v2/flexible_candidate_matrix_v2.dart',
    );
    final adapters = _read(
      'lib/domain/wardrobe_v2/wardrobe_v2_adapters.dart',
    );
    expect(
      service,
      contains('allowCrossFamilySameSlot: requestedSwap.bottomFamily != null'),
    );
    expect(matrix, contains('bool allowCrossFamilySameSlot = false'));
    expect(
      adapters,
      contains('candidate.canonicalFamily != replaced.canonicalFamily &&'),
    );
    expect(adapters, contains('!allowCrossFamilySameSlot'));
""",
)
