# AI Stylist V2 — Help First Contract

This document freezes the product behavior expected from the OOTD AI Stylist. It is intentionally scenario-based so future fixes cannot optimize one example while breaking the general conversation.

## Primary rule

**HELP FIRST, CLARIFY ONLY WHEN NECESSARY.**

The Stylist should make a useful recommendation from known facts and reasonable low-risk assumptions. It should ask a question only when the missing answer can materially change the recommendation, safety, or requested result.

## Conversation behavior

- Ordinary chat must feel conversational, not like a form.
- Greetings and lightweight conversational turns must not read the wardrobe, weather, or location tools.
- A pending clarification is context, not a parser mode. Replies such as `načo ti to je?`, `neviem`, `je mi to jedno`, `preskoč to`, or `daj mi proste niečo` must be interpreted as conversation and must never be geocoded as place names.
- The Stylist must remember facts already supplied in the same chat and must not ask for them again.
- Exactly one clarification question may be asked in a turn.

## Location behavior

- Current GPS, trip destination, and event location are separate facts.
- Remote trip/event weather must never silently use current GPS.
- A useful place such as a city, resort, mountain area, venue, trailhead, or POI can be accepted when it is sufficient for the recommendation.
- A country-level location such as `USA` is too broad for weather-sensitive advice. Ask for a city/state/region once.
- A refinement such as `do Tatier` -> `Téryho chata` must retain the previous context and must never fall back to the identical generic question.
- When the same outfit request already contains a useful location, planning should request location resolution and the needed wardrobe scope in the same tool phase. The coordinator must still avoid the wardrobe read if another material fact is missing after location resolution.

## Date and time behavior

- Explicit relative dates (`dnes`, `zajtra`) use the client-provided date keys.
- Missing time of day is not a mandatory blocker. Default to a broad `day` window when weather is useful unless the user explicitly gives another window.
- Do not ask for time of day merely because weather is enabled.
- If weather cannot be fetched reliably, prefer a useful style recommendation with an honest limitation over a multi-question interrogation, unless weather is genuinely safety-critical.

## Wardrobe behavior

- Do not read the full wardrobe for greetings, explanations, or unrelated chat.
- The full wardrobe should be cached and reused while its revision token is unchanged.
- A wardrobe change invalidates the cached inventory.
- Cached exact-item reads must also revalidate the wardrobe revision before reuse; stale cached item facts must never leak into a recommendation.
- Current-outfit edits should retrieve only the current outfit plus the relevant category when possible.

## Missing-item behavior

- Always choose the best **acceptable** item the user actually owns when a perfect item is missing.
- Never choose an absurd item merely because it is technically closer to an activity (for example winter boots for a warm summer hike).
- For an ordinary hike with no known technical/wet/snow/ice constraint, practical sneakers may be used as an explicit compromise if they are the best available option.
- Explain the limitation clearly.
- When a useful wardrobe gap is discovered, offer shopping with `Áno` / `Nie` quick replies.
- `Nie` must close the offer naturally without changing the outfit.

## Shopping intent

- Requests such as `potrebujem nové biele tenisky` are shopping intent, not outfit-generation intent.
- Ask once whether the user wants the Stylist to search stores and recommend suitable pieces.
- Until store integrations are live, the positive path may remain a placeholder; the negative path must work normally.

## Outfit-photo review

- If the user supplies a photo and already states the occasion/activity, review it immediately.
- If the activity is genuinely absent, ask one question about where/how the outfit will be used.
- Give a natural opinion in the Stylist's own words.
- When something should change, prefer a concrete replacement from the user's wardrobe.

## Performance and cost budgets

These are regression budgets, not promises about network conditions.

- Greeting/light chat: 0 wardrobe calls, 0 location calls, 0 weather calls; avoid an AI call when a deterministic natural response is sufficient.
- Ordinary conversational follow-up: at most 1 AI call unless repair is required.
- Outfit generation: do not use multiple AI phases unless tools genuinely require a second phase.
- Planning should use a cost-sensitive model; stronger models are reserved for the final stylistic decision or constrained escalation.
- Full wardrobe retrieval must not repeat while the cache revision is unchanged.

## Mandatory golden scenarios

1. `Ahoj divočák` -> immediate conversational reply; no tools.
2. `Zajtra idem na túru, potrebujem outfit` -> ask only for a materially useful destination when none is known.
3. `do Tatier` -> retain destination context; do not ask for time of day by default.
4. `Téryho chata` after Tatry -> refine/accept it; never repeat `Kam presne ideš?`.
5. `Zajtra idem na výlet do USA` -> ask for a narrower place because country-level weather is too broad.
6. `New York` -> accept and continue without another location question.
7. `načo ti to je?` while location is pending -> explain why the location helps; do not call geocoding.
8. `neviem, daj mi proste outfit` -> proceed with safe assumptions where possible.
9. Remote concert/wedding -> event location controls event weather, not current GPS; known date + useful location should continue to the outfit in the same turn.
10. Missing hiking footwear -> best acceptable owned fallback + explicit limitation + shopping offer.
11. User declines shopping -> acknowledge and continue; no shopping search.
12. Photo + stated occasion -> immediate outfit review; no redundant occasion question.
13. Photo without occasion -> one useful occasion/activity question.
14. `potrebujem nové biele tenisky` -> shopping permission flow, not outfit generation.
15. Unchanged wardrobe revision -> no repeated full wardrobe read.
16. Changed wardrobe revision -> cache invalidates before the next wardrobe-dependent recommendation.
