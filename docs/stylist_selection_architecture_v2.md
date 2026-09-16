# Stylist selection architecture V2

## Reason for the change

The September 2026 diagnostic showed that images alone did not fix outfit quality. In the
owner's synthetic A/B/C comparison, image-only selection repeatedly preferred visually dark
winter boots, while authoritative metadata and metadata plus images preferred the seasonally
more appropriate available sneakers. The architectural gap was not schema validity: one large
conversational response still owned subjective ranking, explanations, and user-facing prose,
with no independent quality review.

No private diagnostic records, wardrobe snapshots, or image URLs are committed with this change.

## Bounded production flow

1. The existing One-Brain (`gpt-5.6-terra`, medium) owns conversation intent, context, tools,
   clarification, state, and edit semantics. For a ready generate/edit turn it emits a compact
   `selectionAction`, intent summary, and explicit constraints. It does not choose outfit IDs.
2. The selection-context builder projects only material context, current/edit authorization,
   and authorized candidates. It applies ontology-backed structural normalization in memory.
3. The Selector (`gpt-5.6-terra`, medium) receives all candidate metadata and at most 24
   low-detail candidate images. It returns only IDs, reasons, compromises, and missing needs.
4. The independent Judge (`gpt-5.6-terra`, medium) receives the same authority, the proposed
   outfit and reasons, and at most 16 prioritized selected/alternative images. It returns pass
   or retry plus compact feedback. It cannot mutate IDs or state.
5. A retry verdict permits exactly one more Selector call. A valid first result is retained if
   the Judge or retry transport fails. There is no recursive stage and no open-ended loop.
6. The selected IDs and their attached facts are deep-frozen before language generation.
7. The Language stage (`gpt-5.6-luna`, low) can output only `assistantText`. It cannot return or
   change outfit IDs. Invalid phrasing or transport failure uses a concise deterministic fallback.

## Metadata and images

Metadata is authoritative for canonical type/family, body role, layer position, warmth,
seasonality, function, occasion metadata, and safety. Images are supplemental evidence for
silhouette, apparent material, pattern, condition, palette, and visual coherence. Image absence
does not exclude or penalize a candidate.

The deterministic first step narrows edit candidates only by the existing authorization scope.
For generation, all valid candidate metadata remains visible. A structural round-robin supplies
visual evidence across body roles up to the image budget, so a 51-item wardrobe is not converted
into 51 images while metadata-only candidates remain selectable.

Image URLs exist only in the in-memory provider request. Stage telemetry records counts, routing,
latency, verdicts, retry state, and selected IDs, but never image URLs or request bodies.

## Wardrobe integrity

The projection uses the existing Wardrobe V2 ontology. It distinguishes structural invariants
from item-specific facts. Unknown canonical types are diagnosed. Item family, body slots, and
layer position are projected from the canonical definition; when a child definition conflicts
with its parent's broad family, the parent structural definition is used and a diagnostic is
emitted. Color, warmth, formality, seasons, material, and occasion fit are preserved.

This is an in-memory Stylist projection. It does not update Firestore or mutate the raw object.
A persisted ontology/data migration should be reviewed and executed separately.

## Calls, latency, and failure bounds

The normal generate/edit path uses four logical model calls: Brain tool decision, Selector,
Judge, and Language. The old path normally used Brain tool decision plus Brain answer. The new
path therefore trades two additional sequential calls for independent selection and quality
assessment. A Judge-requested Selector retry raises the normal path to five logical calls. A
Brain structural repair and a Selector retry together raise the turn maximum to six logical
calls. The shared provider transport may retry one transient HTTP failure once; no semantic stage
calls itself recursively.

Normal visual input is capped at 24 low-detail images for Selector plus 16 for Judge. A quality
retry may add another 24. Exact token, image, and dollar cost depends on the selected model's live
pricing and image tokenization, and should be measured in a separately approved paid benchmark.
At implementation time, the repository's usage ledger matches the published standard API rates:
Terra costs $2 per million input tokens, $0.20 cached, and $12 per million output tokens; Luna
costs $0.20, $0.02, and $1.20 respectively. Ignoring input and image tokens, the configured normal
output ceilings (850 Brain + 1,000 Selector + 700 Judge + 500 Language) imply a $0.0312 ceiling.
One Selector retry adds at most $0.012 of output-token ceiling plus its repeated input/images.
These are ceilings from configuration, not expected or measured per-turn charges.

Failure behavior is explicit:

- invalid Selector IDs/edit scope receive at most one Selector repair, then fail closed;
- Judge failure preserves the structurally valid Selector result;
- failed or invalid Judge-requested retry preserves the first valid result;
- Language failure preserves frozen IDs and uses deterministic Slovak prose;
- final deterministic shell validation and compare-and-swap session commit remain authoritative.

## Non-goals

This change adds no wedding, interview, country, month, dinner, or other scenario-specific winner
rule. It does not weaken App Check, Firebase security, ownership checks, weather provenance,
clarification limits, or edit authorization. It does not deploy, migrate data, or claim that the
new architecture is empirically superior before a separately approved live evaluation.
