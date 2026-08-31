from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, got {count}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


replace_once(
    "lib/Services/stylist_chat_outfit_service.dart",
    """            allowCrossFamilySameSlot: requestedSwap.bottomFamily != null,\n""",
    """            // Any explicit one-slot swap may consider another compatible\n            // family in the same body slot. This is a global swap invariant,\n            // not a bottom/shorts exception; every other displayed item stays\n            // frozen and the normal suitability guards still apply.\n            allowCrossFamilySameSlot: true,\n""",
)

replace_once(
    "test/brain_v1_v2_offline_bundle_test.dart",
    """    expect(\n      service,\n      contains('allowCrossFamilySameSlot: requestedSwap.bottomFamily != null'),\n    );\n""",
    """    expect(service, contains('allowCrossFamilySameSlot: true'));\n    expect(\n      service,\n      isNot(contains('allowCrossFamilySameSlot: requestedSwap.bottomFamily')),\n      reason: 'Explicit single-slot swaps must be global, not bottom-only.',\n    );\n""",
)
