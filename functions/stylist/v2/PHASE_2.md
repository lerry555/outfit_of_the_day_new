# AI Stylist V2 Phase 2

Phase 2 turns the Phase-0 coordinator and Phase-1 persistence layer into one durable authoritative turn engine while keeping production traffic on the existing Stylist path.

## Authoritative turn engine

`stylist_turn_engine_v2.js` is the Phase-2 entry point. It binds a user and chat to the durable `StylistSessionStateV2` repository, then runs exactly one coordinator against that canonical state.

A turn now follows this boundary:

1. validate the V2 turn request;
2. atomically ensure or reuse the durable canonical session;
3. run deterministic preflight and the existing single-authority coordinator;
4. validate and apply the accepted result;
5. commit the complete next state plus exact turn receipt with compare-and-swap revision protection;
6. return the committed authoritative result.

The coordinator itself still owns the semantic result. The engine owns durability, owner/chat binding, conflict handling, and canonical replay behavior.

## Concurrency and replay

Different turns starting from the same session revision cannot both overwrite state. A Firestore or in-memory `SESSION_CONFLICT` is translated into `StaleSessionRevisionError` with the latest known revision so a future callable can return a clean retry contract.

If the same `turnId` races twice, the Phase-1 immutable receipt wins. The second caller receives the already committed result rather than its locally computed alternative. Sequential retries are normally answered by the bounded session replay before model or tool work runs again.

The durable receipt remains the final idempotency authority. The bounded session replay intentionally keeps only recent turns, so a very old duplicate outside that replay window is a later production-boundary optimization rather than a reason to weaken state bounds.

## Existing chat bootstrap

The engine may receive an explicit legacy bootstrap payload on the first V2 turn. Phase 1 still decides what is safe to preserve: exact current outfit IDs, persisted item-bound selection reasons, and other explicit durable choices. Destination, terrain, weather, and pending actions are not inferred from prose.

## Tests

Phase 2 adds focused tests for:

- durable state across fresh engine instances;
- exact replay without another model call;
- compare-and-swap protection for two different concurrent turns;
- one canonical result for a duplicate same-turn race;
- exact legacy outfit/reason bootstrap preservation.

The V2 CI runs these tests together with all Phase-0 contracts, Phase-1 persistence tests, and the Firestore rules regression bundle.

## Not in Phase 2

- no production callable or `functions/index.js` export;
- no `StylistChatScreen` routing change;
- no live OpenAI model adapter;
- no live wardrobe/location/weather/Shopping adapters;
- no Firebase deployment;
- no user is switched to V2.

Those production adapters and controlled routing belong to a later phase after this durable engine remains green under review.
