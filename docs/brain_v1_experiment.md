# AI Stylist Conversation Brain V1

Status: experimental branch only. Do not merge as production truth until owner-device E2E passes.

## Goal

Make AI Stylist feel like one continuous personal stylist instead of a chain of unrelated model steps, without weakening deterministic outfit authority.

## Phase 1 architecture

User <-> Conversation Brain V1 -> existing deterministic context/wardrobe/weather logic -> Wardrobe V2 candidate generation -> GPT-5.4-mini exact candidateId or reject_all -> deterministic validator -> Conversation Brain V1 user-facing continuation.

The Conversation Brain owns continuity, tone, clarification wording and the final user-facing voice. It does **not** own candidate identity and cannot alter a validated outfit.

## Model strategy

Brain V1 starts with the already-proven `gpt-4o`. This is intentional: first test whether the architecture fixes the product experience. The brain is selected through `STYLIST_ROLE_MODELS.conversationBrain`, so stronger or cheaper models can be A/B tested later without redesigning the pipeline.

Sol is therefore a quality ceiling candidate, not a hard production dependency.

## Opt-in isolation

The experiment build sends `conversationBrainVersion=brain_v1` in ordinary Stylist chat context and in the frozen decision/explanation request.

- Opted-in chat requests route to the synthetic `brain_v1` prompt tier and `conversationBrain` model role.
- Chat requests from older clients keep the settled context/clarification model and legacy tiered prompt.
- Opted-in frozen requests use Conversation Brain V1 for the post-validation user-facing explanation.
- Frozen requests from older clients keep the settled Anthropic explanation path.

This makes a selective deploy of the shared callable names suitable for owner-device testing without silently opting older app builds into the experiment.

## Preserved invariants

- Candidate identity remains exact `candidateId`, never list index.
- `reject_all` remains first-class.
- Server wardrobe ownership and deterministic validation remain authoritative.
- A user-facing brain may explain an approved outfit, but never add, remove or replace its items.
- Material compromises must be disclosed honestly; a best-owned compromise may be offered together with the ideal replacement direction.
- No internal IDs, validator details, model/provider names or scoring internals may be exposed to the user.
- Home/Calendar/Trip routing is not migrated by this experiment.

## Current scope

Phase 1 wires the same Conversation Brain identity/model into ordinary text-chat turns and the post-validation outfit explanation. Existing shopping pre-routing remains authoritative. The current `rate_photo` implementation is still an isolated vision transport; do not claim full one-brain photo-to-shopping continuity yet.

## Owner-device deployment scope

Deploy only these shared Stylist callables from the experiment checkout:

```text
stylistChat
resolveStylistFrozenCandidatesV1
```

Do not deploy the whole Functions project for this experiment.

## Manual acceptance focus

Test natural multi-turn dialogue rather than only single prompts: corrections, pronouns/short follow-ups, generic trip clarification, weather-grounded outfit requests, best-owned compromises, rejection, and a follow-up after an outfit explanation. The user should feel they are still talking to the same stylist before and after the outfit engine runs.
