# Simple-agent footwear and detail salience

This change retains Sol/medium, exact outfit IDs, one repair and fail-closed.
No legacy intent parser, candidate selector or outfit-edit pipeline is used.

## Decision contract

- The model identifies footwear use and the actual wear window from conversation.
  Purpose and practical/weather suitability precede palette and small details.
- `footwearAssessment` is required in new strict model outputs. Its status is
  `suitable`, `conditional`, `missing` or `not_applicable`. Conditional/missing
  requires a visible limitation when a new footwear compromise/gap is selected.
  A retained assessment must not force a repeated warning into an unrelated
  consultation or layer edit; `not_applicable` means no footwear decision in
  this turn, not that the previous limitation has ceased to apply.
  A missing pair may produce top+bottom (or full-body) without footwear; it never
  permits missing other core slots, duplicates or invented items.
- A conservative server check rejects **newly selected** winter footwear when
  the supplied temperatures in the selected window are at least 12 C and no
  wintry evidence is present. This is a product guard, not a medical threshold.
  It never treats calendar winter, rain or an unknown/null temperature as proof
  of winter conditions. Cold or snow permits consideration, not automatic choice.
- Light Chelsea/ankle boots are not relabelled as winter footwear. In terrain,
  generic/fashion boots are not silently promoted to hiking footwear. Sneakers
  are a conditional light/dry-terrain compromise; difficult wet terrain without
  appropriate footwear should return an explicit gap, not a forced full outfit.
- Ground grip, waterproofing and safety on ice cannot be inferred from color,
  footwear category or warmth. The model must not invent them.
- Existing footwear is preserved for unrelated edits; explanation/weather-only
  turns also preserve partial outfits. This is not an automatic closet migration.

## Evidence transport

Original hourly Open-Meteo WMO codes now survive the day snapshot and are sent
with hourly temperatures to the simple agent. No new provider request is added.
UI labels can map snowfall to overcast, so they are deliberately not the source
of snow evidence. Forecast hours are local hours 0–23; window checks never borrow
snow/cold from a different day or an unrelated evening.

WMO mapping source, checked 2026-09-02:
[Open-Meteo documentation](https://open-meteo.com/en/docs#weathervariables).
71/73/75/77/85/86 are snow codes; 56/57/66/67 are freezing precipitation.
The absence of these codes is not proof that existing ground snow is absent.

`colorProportions` preserves estimated primary/secondary/accent coverage.
Invalid or absent proportions remain null. The accent array aligns with
`accentColors`; 1% and 40% details no longer become identical model inputs.
Tiny dark details are not a sufficient principal reason to choose a large pale
blue garment. Coverage is estimated, and neither it nor color proves a logo.

## Verification and activation

- `simple_stylist_footwear_v1.test.js`: weather/day/window isolation, rain vs snow,
  warm winter dates vs cold spring dates, category distinctions, explicit gaps,
  partial-state follow-ups, repair cap and detail coverage.
- Existing stylist/cost regressions still protect transport, cache and IDs.
- `test/stylist_simple_agent_v1_test.dart`: old client compatibility with partial
  outfits and persistence, plus the additive hourly-code snapshot transport.
- After owner-approved deployment, run the existing live smoke with `--footwear`
  and review the actual Slovak replies, not just the structured flags. It uses an
  existing QA wardrobe and synthetic weather, without garment writes or pushes.
  Lack of winter/hiking items in that account limits what a live scenario proves.

Activation needs **only `stylistSimpleAgentV1` deployment** plus a rebuilt Flutter
client for hourly snow-code transport. Older clients still send day temperatures;
they benefit from server rules but cannot supply the newly retained hourly codes.
Do not claim live verification before this deployment and live smoke occur.

## Approved rollout — 2026-09-02

- The owner approved deployment and live verification. Run
  [33622255003](https://github.com/lerry555/outfit_of_the_day_new/actions/runs/33622255003)
  passed all 152 automated checks and deployed **only**
  `stylistSimpleAgentV1` in `us-east1` from `d66d2e9`. The runtime fix is `aac02b7`.
- All 11 live callable turns passed, using the existing QA account's actual
  wardrobe and explicitly synthetic weather. No garment documents were changed.
  This is backend acceptance, not a physical-device UI test.
- The wardrobe contains running shoes, fashion sneakers and actual
  `winter_boots` (warmth 9), but no canonical hiking footwear. Three independent
  forest/mushroom phrasings at 16 C morning / 24 C noon selected either sneakers
  with an explicit easy/dry-terrain limitation or an honest footwear gap, never
  winter boots. Steep muddy terrain produced a gap; a subsequent weather-only
  turn preserved that partial outfit. At -3 C with WMO 75, winter boots were
  selected. Tests do not establish real-world grip or waterproofing.
- The reserve-layer scenario preserved all original outfit IDs. An explicitly
  requested pale-blue sweatshirt (98% blue, 2% black) was explained through its
  main blue color and the blue in the selected shirt. Asked whether its tiny
  black logo was the main reason, the response said: "Nie — čierny detail je len
  drobný bonus, nie hlavný dôvod." This prose was manually reviewed, beyond the
  structural checks. A separate red-shirt-detail/red-sneaker selection and
  explanation regression also passed, with no outfit mutation on explanation.
- The temporary deploy workflow and single-export deployment entry are removed
  after the successful run. Permanent regression CI and the live QA harness
  remain. The protected `brain-v1-experiment` and `master` refs remain unchanged.
- Rebuild the Flutter client to activate the newly retained hourly snow-code
  transport. Removing the temporary repository files does not undeploy the
  successful callable revision; no second deployment is needed for this cleanup.

## Follow-up conversation correction — approved and deployed 2026-09-02

The owner's next physical-device transcript exposed two gaps missed by the
rollout acceptance: `outfitRequested` included explanations, so an unsolicited
jeans card was allowed, and every `conditional` assessment forced its message
into the reply even when the user asked about jeans. The UI faithfully rendered
the server's `displayItemIds`; this was not an image cache problem.

- A suitability/reason/comparison question is text-only: preserve current IDs,
  `outfitRequested=false`, `displayItemIds=[]`. Grounding still validates claims
  about that outfit. Explicit show requests can display cards without edits.
- Warning disclosure is tied to a new footwear decision (changed shoe IDs or a
  first outfit), not any change anywhere in the outfit. New terrain compromises
  remain guarded; existing partial outfits can receive unrelated layer edits.
- The prompt answers the current question, adds a useful tradeoff, and offers
  feasible next-step advice on a genuine gap. Agreement should deliver that
  advice; a declined purchase must not be repeatedly offered.
- The ordinary simple-agent callable has no store-search, URL-reading or price
  lookup tool. Existing legacy shopping code and fixture UI do not make those
  capabilities available to this path. Do not offer or claim real store search;
  give useful selection criteria instead. Connecting shopping is separate work,
  not a reason to restore the legacy intent parser.
- `simple_stylist_conversation_v1.test.js` adds 15 offline contract regressions;
  Flutter adds text-only card/state persistence coverage. These use controlled
  outputs and do not prove live language quality. The `--conversation --live`
  acceptance mode checks eight actual turns including jeans, explicit show,
  new wet terrain, purchase refusal, advice agreement and unavailable search.
  Review every reply semantically, including the first gap's useful next step.
- No additional production AI call, model downgrade or new result field is
  introduced. One repair remains the maximum. The mobile runtime does not change;
  this follow-up needs no Flutter rebuild or client update.

### Deployment findings and corrective verification

- The owner explicitly approved deployment of only `stylistSimpleAgentV1` and
  live acceptance. The first deployment run
  [33627277306](https://github.com/lerry555/outfit_of_the_day_new/actions/runs/33627277306)
  deployed successfully but failed its first live turn. It is not a passing
  acceptance run: the initial provider output could not be parsed and used the
  complete 2,400-token output budget, including 1,779 reasoning tokens. The one
  repair then failed `footwear_limitation_not_in_comment`. Both provider requests
  returned HTTP 200; this was not an App Check or authentication failure.
- The shared output ceiling is now 4,096 tokens, while the user-facing comment
  stays capped at 500 characters. The ceiling includes reasoning and structured
  JSON, not just visible prose, as described in the
  [OpenAI reasoning guide](https://developers.openai.com/api/docs/guides/reasoning).
  Incomplete responses are rejected even when their partial JSON is parseable;
  the existing single repair remains metered. Diagnostic logs record only output
  status, length and token counts, never raw model prose or credentials. A higher
  ceiling is not a fixed usage target or a claim of guaranteed cost savings.
- New footwear-disclosure instructions require an exact current-comment excerpt,
  not a paraphrase or a previous turn's warning. Repair guidance specifically
  explains this contract without appending a second deterministic warning.
- Run
  [33628666985](https://github.com/lerry555/outfit_of_the_day_new/actions/runs/33628666985)
  passed all ten live structural scenarios, but manual review found no practical
  next step in the first gap disclosure. The prompt now requires feasible help
  when a new proposal first names a genuine wardrobe gap, including a conditional
  compromise. The first live reply now has a corresponding acceptance check;
  this text matcher exists only in the QA harness, never in runtime intent logic.
- The final deployment run
  [33629614866](https://github.com/lerry555/outfit_of_the_day_new/actions/runs/33629614866)
  passed **169 automated checks**, deployed only the callable in `us-east1` from
  `b4e945c`, and passed **10 live turns** (eight conversation, two color-detail).
  Actual Slovak replies were manually reviewed in addition to structural checks.
  QA used an existing account's real wardrobe and explicitly synthetic weather,
  without garment writes, notifications or physical-device UI automation.
- The first forest outfit selected sneakers with a dry/easy-terrain limitation
  and concrete footwear-selection advice. "A rifle sú v poriadku?" returned no
  cards and no footwear recap; its answer discussed leg coverage and checking
  freedom of movement. Explicit jeans/full-outfit requests displayed one/four
  cards respectively, without changing the outfit.
- A new wet/steep-terrain question received a fresh limitation while preserving
  all IDs. Declining a purchase returned practical jeans-mobility advice without
  another offer. Accepting pending advice delivered footwear criteria. A store
  search request honestly disclosed that live stores/prices are unavailable and
  offered search terms rather than invented products. Red-detail/red-sneaker
  selection still worked, and its explanation remained text-only.
- Both temporary deployment/diagnostic workflows and the temporary single-export
  entry are removed after successful acceptance. Permanent regression CI and
  live QA modes remain. Cleanup does not undeploy the live callable and needs no
  second deployment. `brain-v1-experiment` and `master` remain unchanged.
