# AI Stylist V2 Phase 1

Phase 1 adds durable server-owned session persistence without routing production Stylist traffic through V2.

## Durable authority

Canonical state lives at:

`users/{uid}/stylistSessionsV2/{chatId}`

The document stores the validated `StylistSessionStateV2`, its revision, owner binding, and timestamps.

Accepted turn receipts live at:

`users/{uid}/stylistSessionsV2/{chatId}/turns/{turnId}`

Turn receipts are immutable idempotency records. A retry with the same `turnId` replays the accepted result instead of executing a second semantic mutation.

## Commit semantics

`stylist_session_repository_v2.js` provides matching in-memory and Admin Firestore repositories.

A turn commit requires:

- the expected previous session revision,
- a next state at exactly `expectedRevision + 1`,
- an accepted result whose `turnId` and resulting revision match that state,
- the exact same result recorded in the bounded state replay history.

The Firestore adapter commits the canonical session and immutable turn receipt in one transaction. Different turns racing from the same revision cannot both win.

Expensive model, wardrobe, location, weather, and Shopping work remains outside the Firestore transaction. A later V2 coordinator integration will compute the authoritative result and then perform the short compare-and-swap commit.

## Existing-chat bootstrap

`ensureFromLegacy` uses the Phase-0 `bootstrapExistingChatV2` contract. It preserves only data that the caller can recover as explicit durable truth, including exact current outfit IDs and persisted selection reasons.

It deliberately does not infer destination, terrain, weather, or pending actions from prose. A production extractor from existing `stylistChats` is not introduced in this phase.

## Firestore access boundary

The owner may read the canonical session document. Clients cannot create, update, or delete it. Turn receipts are server-only.

The broad `/users/{uid}/{firstSegment}/{document=**}` rule explicitly excludes `stylistSessionsV2`, because overlapping Firestore allow rules are ORed and a specific deny cannot override a broader allow.

## Tests

Phase 1 adds:

- pure repository tests for bootstrap, CAS revisions, idempotent turn replay, conflict handling, and malformed-state rejection;
- Firestore emulator tests for persistence across fresh repository instances, concurrent turn serialization, and client access rules;
- dedicated V2 CI for Phase-0 contracts plus Phase-1 persistence/rules checks.

## Not in Phase 1

- no production V2 callable;
- no `StylistChatScreen` routing change;
- no live model/weather/Shopping adapter;
- no automatic legacy-chat extraction;
- no Firebase deployment;
- no user is switched to V2 yet.
