# OOTD cost controls — first rollout

This change keeps **gpt-5.6-sol / medium** and the simple-agent contract,
validators, one-repair limit, clothing metadata and selection reasons intact.
No legacy intent parser or outfit authority is reintroduced.

## Implemented

| Feature | Change | Activation requires deployment of |
| --- | --- | --- |
| Stylist chat | Two explicit provider-cache boundaries: instructions and complete sorted Wardrobe V2. Dynamic turn/history/weather follow them. | `stylistSimpleAgentV1` |
| Stylist chat | Server-only transactional job admission before wardrobe/model reads. Same job+payload replays its result; conflicts and in-flight duplicates do not launch another AI call. | `stylistSimpleAgentV1` |
| Wardrobe analysis | 24-hour exact-result cache after reading current wardrobe and constructing the complete provider input. Invalid/fallback answers are not cached. | `analyzeWardrobeSmart` |
| Clothing recognition | Correct Gemini Flash rates; include both truncation attempts and thoughts; record unknown usage honestly. | `analyzeClothingImage` |
| Home | Meter generation, candidate review and explanation calls without changing existing outfit/cache decisions. | `generateHomeOutfit`, `finalReviewHomeOutfitCandidates`, `generateHomeOutfitExplanation` |

Changing checked-in code does **not** activate it in existing deployed functions.
Deploy only explicitly approved functions, not all exports. Follow the repository
branch/protected-ref and production-approval rules before any deployment.

## What is measured

Each provider attempt produces a server-side `AI_USAGE_V1` log and a document in
`aiUsageEventsV1`. Fields include a hashed user identity, feature, model, attempt,
input/output/cached/cache-write/reasoning counters and versioned USD estimates.
No prompt, photo, image URL, message text or credentials are saved in usage events.
Ledger write failures are logged and do not force a second paid call.
Deduplicate log exports by `eventId` before aggregation.

Missing usage is `null`, not zero. An absent GPT-5.6 cache-write counter produces
a minimum/maximum estimate, not a false exact figure. OpenAI reasoning tokens
are already part of output tokens; Gemini thoughts are separately billed.
Gemini retry telemetry includes a known-attempt subtotal when other attempts
have unknown usage. These estimates exclude Firebase, storage/network traffic,
other providers, tax, exchange rates, store fees and uninstrumented legacy paths.
They cannot reconstruct historical spending or replace provider billing exports.
The GPT-5.6 launch-price estimate expires after 2026-11-21 pending rate review.

Sources checked 2026-09-02:

- https://developers.openai.com/api/docs/guides/prompt-caching
- https://developers.openai.com/api/docs/models/gpt-5.6-sol
- https://developers.openai.com/api/docs/models/gpt-5.6-terra
- https://developers.openai.com/api/docs/models/gpt-5.6-luna
- https://developers.openai.com/api/docs/models/gpt-4o-mini
- https://ai.google.dev/gemini-api/docs/pricing

## Safety and limits

- Cache validity uses actual content, not item counts. Same-count edits,
  replacement, deletion and added items alter the model prefix. No attributes
  (including secondary/accent colors) are removed.
- The provider cache is temporary and cache hits are not guaranteed. It does
  not provide free permanent model memory. GPT-5.6 cache writes also cost money.
- **Normal new chat turns still read the authoritative Firestore wardrobe.**
  Skipping those reads requires an atomic per-user wardrobe revision covering
  every client/backend writer and deletion path. An asynchronous trigger alone
  can lag a write and is not a correctness guarantee. That migration is deferred.
- Current wardrobe limits (200 chat / 80 Home) are unchanged.
- Exact-analysis caching saves AI calls, not its initial wardrobe DB read.
  Same-instance concurrent misses are coalesced; separate cold instances can
  still perform simultaneous analysis. The cache stores one entry per user/feature.
- Private roots `aiTaskRunsV1`, `aiUsageEventsV1`, `aiExactResultCachesV1` rely on
  the existing default-deny rules. Never place authoritative records inside the
  broad owner-writable `users/*` catch-all. Emulator tests verify this boundary.
- A running/failed job is **not** automatically reclaimed after a timeout:
  the provider may already have charged. Existing client job recovery remains
  active. A genuinely new user turn gets a new job ID. Old clients lacking IDs
  work but cannot obtain retry deduplication.
- The ledger has no automatic deletion policy in this change. Task records must
  not expire casually: deleting one permits the same job to execute again.
  Include these hashed-user records in a future account-erasure/retention policy.
- No production data migration, rules deployment, background-removal quality
  change, try-on implementation, store search redesign, image regeneration or
  blanket model downgrade is included.

## Cheaper-model evaluation

`node functions/stylist/simple_stylist_cost_eval_v1.js` is a free offline plan.
`--live` requires a normally configured `OPENAI_API_KEY`; it never retrieves
deployed secrets. It uses synthetic wardrobe fixtures, the same production
contract/validator and an evaluation-only model override. Default limits are
24 provider requests and a conservative $3 reservation budget including retries
and repairs. Reservation is an estimate, not a provider billing cap.

The suite compares Sol/Terra/Luna for conversation-only, weather-only, original
choice explanation, red accent matching, adding and removing layers. It prints
usage, outputs and structural/exact-ID results for **human style review**.
One passing run is not evidence of equal quality: repeat trials, larger wardrobes,
typos, multi-slot edits, hard-weather cases and blind review are still needed.
There is no automatic model promotion or production model override.

## Verification

`stylist-cost-controls-ci.yml` runs Node 20 regressions, real Firestore emulator
transactions/rules and existing vision regressions. The latter need the generated
Dart knowledge-base artifacts; CI builds them from the checked-in source of truth.
The workflow does not deploy, use production credentials or call paid AI.

Live acceptance after authorized deployment must include natural Slovak replies,
choice continuity, accent grounding, wardrobe changes, duplicate job replay and
actual provider usage/cache-hit counters. Unit tests alone do not prove savings
or unchanged model output quality. Model-price/quality comparison still requires
configured API access and a paid evaluation run.
