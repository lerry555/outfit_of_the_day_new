# AI Stylist V2 Phase 0

This directory is an isolated, fake-driven contract target. Nothing in a production UI,
Firebase callable, weather service, Shopping runtime, or the Simple Agent V1 imports it.

## Implemented boundary

- `stylist_session_state_v2.js`: canonical bounded state and safe existing-chat bootstrap.
- `stylist_turn_contract_v2.js`: strict request and discriminated authoritative-result contracts.
- `stylist_preflight_v2.js`: replay, revision, pending referent, and material-grounding rules.
- `stylist_turn_coordinator_v2.js`: the single Phase-0 acceptance entry point.
- `stylist_turn_validator_v2.js`: safety-critical, repairable structural, cosmetic, and
  subjective-quality boundaries.
- `fake_ports_v2.js`: ledgered in-memory session, wardrobe, location, weather, Shopping,
  and stylist/model ports.
- `firestore_rules_contract_v2.js`: intended server-write-only policy for the future
  `users/{uid}/stylistSessionsV2/{chatId}` collection. Production `firestore.rules` is unchanged.
- `stylist_v2_backlog.js`: executable disposition of all 30 known problem classes and
  future model-quality eval fixtures.

## Backlog disposition

Deterministic Phase-0 contract tests cover problems:
`1, 2, 3, 6, 7, 8, 10, 11, 12, 14, 15, 19, 20, 22, 26, 27, 28, 29`.

Future production-boundary integration tests are required for problems:
`4, 9, 13, 30`.

Future authoritative-model quality evals are required for problems:
`5, 16, 17, 18, 21, 23, 24, 25`.

The exact mapping, safeguard, eval input, relevant state, expected qualities, and forbidden
behaviors are data in `stylist_v2_backlog.js`, and a contract test ensures all 30 entries have
exactly one disposition.

## Phase-0 limitations

- All ports are deterministic fakes; there are no production adapters or external calls.
- The fake coordinator demonstrates the contract and state transitions, not final model prompting,
  production routing, latency/progress events, or user-visible language quality.
- Location identity and weather snapshots come only from fake fixtures.
- The isolated Firestore policy is a testable intent contract; production rules remain a Phase-1 task.
- Repairable structural errors expose a one-correction allowance, but Phase 0 performs no model repair.
