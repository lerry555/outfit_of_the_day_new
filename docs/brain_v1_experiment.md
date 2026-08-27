# AI Stylist Conversation Brain V1

Status: experimental branch only. Do not merge or deploy as production truth until owner-device E2E passes.

## Goal

Make AI Stylist feel like one continuous personal stylist instead of a chain of unrelated model steps, without weakening deterministic outfit authority.

## Phase 1 architecture

User <-> Conversation Brain V1 -> existing deterministic context/wardrobe/weather logic -> Wardrobe V2 candidate generation -> GPT-5.4-mini exact candidateId or reject_all -> deterministic validator -> Conversation Brain V1 user-facing continuation.

The Conversation Brain owns continuity, tone, clarification wording and the final user-facing voice. It does **not** own candidate identity and cannot alter a validated outfit.

## Model strategy

Brain V1 starts with the already-proven `gpt-4o`. This is intentional: first test whether the architecture fixes the product experience. The brain is selected through `STYLIST_ROLE_MODELS.conversationBrain`, so stronger or cheaper models can be A/B tested later without redesigning the pipeline.

Sol is therefore a quality ceiling candidate, not a hard production dependency.

## Preserved invariants

- Candidate identity remains exact `candidateId`, never list index.
- `reject_all` remains first-class.
- Server wardrobe ownership and deterministic validation remain authoritative.
- A user-facing brain may explain an approved outfit, but never add, remove or replace its items.
- Material compromises must be disclosed honestly; a best-owned compromise may be offered together with the ideal replacement direction.
- No internal IDs, validator details, model/provider names or scoring internals may be exposed to the user.
- Home/Calendar/Trip routing is not migrated by this experiment.

## Current scope

Phase 1 wires the same Conversation Brain identity/model into ordinary chat turns and the post-validation outfit explanation. Existing shopping pre-routing remains authoritative and existing photo-rating transport is still isolated. The photo path already supports vision and wardrobe follow-up, but its prompt/state ownership must be consolidated into the Conversation Brain in a later phase before claiming full one-brain photo-to-shopping continuity.

## Manual acceptance focus

Test natural multi-turn dialogue rather than only single prompts: corrections, pronouns/short follow-ups, generic trip clarification, weather-grounded outfit requests, best-owned compromises, rejection, and a follow-up after an outfit explanation. The user should feel they are still talking to the same stylist before and after the outfit engine runs.
