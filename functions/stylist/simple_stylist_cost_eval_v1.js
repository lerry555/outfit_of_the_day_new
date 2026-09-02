"use strict";

// Development-only, synthetic fixtures, never imported by the callable. No
// deployed secrets, production users or Firestore access. Dry-run by default.
const {createSimpleStylistAgentV1, createOpenAiSimpleAgentExecutorV1} =
  require("./simple_stylist_agent_v1");
const {hashValue} = require("../costs/ai_usage_v1");

const MODELS = Object.freeze(["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"]);
function item(id, type, slot, color, layer = "base", accents = []) {
  return {id, name: id, ontologyVersion: "2.0.0", canonicalType: type,
    canonicalFamily: slot === "feet" ? "footwear" : slot === "lower_body" ? "bottoms" : "tops",
    bodySlots: [slot], layerPosition: layer, warmth: 4, formality: 4,
    colorProfile: {primary: {family: color}, accents: accents.map((family) => ({family}))},
    styles: ["casual"], seasons: ["spring", "summer", "autumn"]};
}
const WARDROBE = [
  item("biele-tricko", "t_shirt", "upper_body", "white"),
  item("cierne-tricko-cerveny-detail", "t_shirt", "upper_body", "black", "base", ["red"]),
  item("modre-rifle", "jeans", "lower_body", "blue"),
  item("cierne-sortky", "casual_shorts", "lower_body", "black"),
  item("biele-tenisky", "sneakers", "feet", "white", "outer"),
  item("cervene-tenisky", "sneakers", "feet", "red", "outer"),
  item("svetlomodra-mikina", "hoodie", "upper_body", "blue", "mid"),
  item("cierna-bunda", "denim_jacket", "upper_body", "black", "outer"),
];
const BASE = ["biele-tricko", "modre-rifle", "biele-tenisky"];
const FIXTURES = [
  {name: "chat_without_outfit", message: "Ahoj, zajtra idem do mesta.", current: [], expected: []},
  {name: "weather_without_mutation", message: "Koľko bude zajtra stupňov?", current: BASE, expected: BASE},
  {name: "shorts_with_original_reason", message: "Rifle by som vymenil za kraťasy.", current: BASE,
    expected: ["biele-tricko", "cierne-sortky", "biele-tenisky"],
    reasons: [{itemId: "modre-rifle", reason: "Rifle boli zvolené pre chladnejšie ráno, aby boli zakryté nohy."}]},
  {name: "red_detail_match", message: "Vymeň tričko a daj mi červené tenisky.", current: BASE,
    expected: ["cierne-tricko-cerveny-detail", "modre-rifle", "cervene-tenisky"]},
  {name: "add_hoodie_full_outfit", message: "Ukáž celý outfit a pridaj mikinu.", current: BASE,
    expected: [...BASE, "svetlomodra-mikina"]},
  {name: "remove_layer", message: "Daj preč bundu, ostatné nechaj.", current: [...BASE, "cierna-bunda"],
    expected: BASE},
];

async function runEvaluation({models = MODELS, maxRequests = 24, maxUsd = 3,
  fetchImpl = fetch, apiKey, onResult = () => {}} = {}) {
  if (!models.length || models.some((model) => !MODELS.includes(model))) throw new Error("unsupported_eval_model");
  if (!apiKey) throw new Error("configured_OPENAI_API_KEY_required");
  if (!Number.isInteger(maxRequests) || maxRequests < 1 || maxRequests > 60 ||
      !Number.isFinite(maxUsd) || maxUsd <= 0 || maxUsd > 10) throw new Error("invalid_eval_budget");
  let requests = 0;
  let reservedUsd = 0;
  const outcomes = [];
  for (const model of models) {
    for (const fixture of FIXTURES) {
      const events = [];
      let lastReservation = 0;
      const executor = createOpenAiSimpleAgentExecutorV1({
        resolveOpenAISecret: () => apiKey, logger: {}, cacheScope: `synthetic-eval:${model}`,
        fetchImpl: async (url, init) => {
          // Conservative reservation: all UTF-8 body bytes as input tokens,
          // plus 8192 hidden/protocol tokens; all input at cache-write rate.
          // Reserve BEFORE each transport retry and repair, not just per turn.
          const rates = model === MODELS[0] ? [5, 20] : model === MODELS[1] ? [2.5, 12] : [0.25, 1.2];
          lastReservation = ((Buffer.byteLength(init.body) + 8192) * rates[0] + 2400 * rates[1]) / 1e6;
          if (requests >= maxRequests || reservedUsd + lastReservation > maxUsd) {
            throw new Error("eval_budget_exhausted");
          }
          requests++;
          reservedUsd += lastReservation;
          return fetchImpl(url, {...init, signal: AbortSignal.timeout(110000)});
        },
        recordUsage: async (event) => {
          events.push(event);
          // Unknown usage retains the conservative reservation instead of
          // treating a lost response or failed attempt as a free request.
          if (event.estimatedCostUsdMax !== null) {
            reservedUsd += event.estimatedCostUsdMax - lastReservation;
          }
        },
      });
      const agent = createSimpleStylistAgentV1({logger: {},
        executeModel: (input, attempt) => executor({...input, model}, attempt)});
      let outcome;
      try {
        const result = await agent.resolve({
          message: fixture.message, wardrobeItems: WARDROBE,
          currentOutfitItemIds: fixture.current, currentSelectionReasons: fixture.reasons || [],
          history: [], weatherContext: {tomorrow: {morningTempC: 15, noonTempC: 24,
            eveningTempC: 22, minTempC: 12, maxTempC: 25, willRain: false,
            isWindy: false, fromOpenMeteo: true}},
          clientContext: {todayDateKey: "2026-09-02", tomorrowDateKey: "2026-09-03", userGpsLocation: "Martin"},
        });
        const exactIds = hashValue([...result.resultingOutfitItemIds].sort()) ===
          hashValue([...fixture.expected].sort());
        outcome = {model, fixture: fixture.name, contractPassed: true, exactIds,
          reply: result.stylistComment, selectionReasons: result.selectionReasons};
      } catch (error) {
        if (error.message === "eval_budget_exhausted") throw error;
        // Never print provider messages, authorization headers or credentials.
        outcome = {model, fixture: fixture.name, contractPassed: false,
          code: String(error.code || "evaluation_failed").slice(0, 80)};
      }
      outcome.usage = events;
      outcome.requiresHumanStyleReview = true;
      outcomes.push(outcome);
      onResult(outcome);
    }
  }
  return {requests, reservedOrEstimatedUsd: reservedUsd, outcomes,
    automaticModelPromotion: false};
}

if (require.main === module) {
  if (!process.argv.includes("--live")) {
    console.log(JSON.stringify({dryRun: true, models: MODELS, fixtures: FIXTURES.map((f) => f.name),
      maxRequests: 24, maxUsd: 3, changesProductionModel: false}, null, 2));
  } else {
    runEvaluation({apiKey: process.env.OPENAI_API_KEY,
      onResult: (result) => console.log(JSON.stringify(result))})
      .then(({outcomes, ...summary}) => console.log(JSON.stringify(summary)))
      .catch((error) => { console.error(error.code || "evaluation_stopped_check_configuration_and_budget"); process.exitCode = 1; });
  }
}

module.exports = {MODELS, FIXTURES, runEvaluation};
