"use strict";

const assert = require("node:assert/strict");
const {createOpenAiSimpleAgentExecutorV1} = require("../simple_stylist_agent_v1");
const {createOpenAiStylistModelPortV2} = require("./openai_stylist_model_port_v2");
const {createStylistChatV2Handler} = require("./stylist_production_bridge_v2");
const {createMemoryStylistSessionRepositoryV2} = require("./stylist_session_repository_v2");

const NOW = Date.parse("2026-09-09T08:30:00.000Z");
const MAX_PROVIDER_CALLS = Number(process.env.STYLIST_SMOKE_MAX_CALLS || 3);
const MAX_PROVIDER_LATENCY_MS = Number(process.env.STYLIST_SMOKE_MAX_PROVIDER_MS || 12000);
const MAX_ESTIMATED_COST_USD = Number(process.env.STYLIST_SMOKE_MAX_COST_USD || 0.01);

const WARDROBE = [
  {id: "shirt", name: "Čierne tričko", category: "tops", canonicalType: "t_shirt", canonicalFamily: "tops",
    bodySlots: ["upper_body"], layerPosition: "base", colorProfile: {primary: {family: "black", proportion: 1}},
    colors: ["black"], warmth: 2, formality: 2, outfitFunctions: ["base_layer"], seasons: ["summer", "spring", "autumn"]},
  {id: "pants", name: "Sivé tepláky", category: "bottoms", canonicalType: "joggers", canonicalFamily: "bottoms",
    bodySlots: ["lower_body"], layerPosition: "base", colorProfile: {primary: {family: "gray", proportion: 1}},
    colors: ["gray"], warmth: 4, formality: 1, outfitFunctions: ["casual"], seasons: ["spring", "autumn"]},
  {id: "sneakers", name: "Športové tenisky", category: "footwear", canonicalType: "running_shoes", canonicalFamily: "footwear",
    bodySlots: ["feet"], layerPosition: "base", colorProfile: {primary: {family: "white", proportion: 1}},
    colors: ["white"], warmth: 2, formality: 1, outfitFunctions: ["sport"], seasons: ["spring", "summer", "autumn"],
    safety: {hikingTechnical: false}},
  {id: "hoodie", name: "Svetlomodrá mikina", category: "tops", canonicalType: "hoodie", canonicalFamily: "tops",
    bodySlots: ["upper_body"], layerPosition: "mid", colorProfile: {primary: {family: "blue", proportion: 1}},
    colors: ["blue"], warmth: 5, formality: 1, outfitFunctions: ["mid_layer"], seasons: ["spring", "autumn", "winter"]},
];

function qualityCheck(text, {allowQuestion = false} = {}) {
  const value = String(text || "").trim();
  assert.ok(value.length >= 20 && value.length <= 700, `reply_length:${value.length}`);
  assert.doesNotMatch(value, /validator|toolResults|grounding|candidateId|fail-closed/i);
  assert.doesNotMatch(value, /(?:^|\s)-\s+\S+(?:\s+-\s+\S+){2,}/m);
  const sentences = (value.match(/[.!?](?=\s|$)/g) || []).length;
  assert.ok(sentences >= 1 && sentences <= 5, `sentence_count:${sentences}`);
  if (!allowQuestion) assert.doesNotMatch(value, /chceš,?\s+aby som/i);
}

async function main() {
  const apiKey = String(process.env.OPENAI_API_KEY || "").trim();
  assert.ok(apiKey, "OPENAI_API_KEY is required for live smoke");

  const providerCalls = [];
  const usage = [];
  async function budgetFetch(url, options = {}) {
    if (!String(url).includes("api.openai.com")) return fetch(url, options);
    const body = JSON.parse(String(options.body || "{}"));
    assert.equal(body.model, "gpt-5.6-luna", `large_model_forbidden:${body.model}`);
    assert.ok(providerCalls.length < MAX_PROVIDER_CALLS, "live_smoke_provider_call_budget_exceeded");
    const started = Date.now();
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), MAX_PROVIDER_LATENCY_MS + 1000);
    try {
      const response = await fetch(url, {...options, signal: controller.signal});
      const latencyMs = Date.now() - started;
      providerCalls.push({model: body.model, reasoning: body.reasoning?.effort || null, latencyMs, status: response.status});
      assert.ok(latencyMs <= MAX_PROVIDER_LATENCY_MS, `provider_latency_budget_exceeded:${latencyMs}`);
      return response;
    } finally {
      clearTimeout(timer);
    }
  }

  const executeStructured = createOpenAiSimpleAgentExecutorV1({
    fetchImpl: budgetFetch,
    resolveOpenAISecret: () => apiKey,
    logger: {info() {}, warn() {}},
    recordUsage: async (event) => usage.push(event),
    cacheScope: "stylist-live-smoke",
    feature: "stylist_v2_live_smoke",
    sleepImpl: async () => {},
  });

  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  const wardrobeTool = {
    async retrieve() { return JSON.parse(JSON.stringify(WARDROBE)); },
    async materialize(ids, reasons = {}) {
      const byId = new Map(WARDROBE.map((item) => [item.id, item]));
      return ids.map((id) => byId.get(id)).filter(Boolean).map((item) => ({...item,
        ...(reasons[item.id] ? {stylistSelectionReason: reasons[item.id]} : {})}));
    },
  };
  const handler = createStylistChatV2Handler({
    db: {}, admin: {}, logger: {info() {}, warn() {}}, resolveOpenAISecret: () => apiKey, clock: () => NOW,
    sessionRepository: repository,
    locationResolver: {async resolve(query) {
      const normalized = String(query || "").toLowerCase();
      return (normalized.includes("tatr") || normalized.includes("tatier")) ?
        {providerId: "live:tatry", label: "Vysoké Tatry", lat: 49.1667, lng: 20.1333,
          source: "live_smoke_fixture", granularity: "locality"} : null;
    }},
    weatherTool: {async getForecast(request) {
      return {
        summary: "sucho a mierne", minTempC: 10, maxTempC: 17, precipitationMm: 0,
        locationProviderId: request.location.providerId,
        dateKey: request.date.dateKey,
        timeWindowKey: request.timeWindow.key,
        fetchedAt: new Date().toISOString(),
        source: "live_smoke",
      };
    }},
    wardrobeToolFactory: () => wardrobeTool,
    shoppingToolFactory: () => ({async search() { return {candidateIds: [], appliedHardConstraints: []}; }}),
    modelFactory: () => createOpenAiStylistModelPortV2({executeStructured}),
  });
  const context = {auth: {uid: "live_smoke_user"}};
  const base = (turnId, message) => ({
    v2SessionId: "live_smoke_chat", turnId, message, history: [], currentOutfitItemIds: [],
    clientContext: {todayDateKey: "2026-09-09", tomorrowDateKey: "2026-09-10", timezoneOffsetMinutes: 120},
  });

  const firstStarted = Date.now();
  const first = await handler(base("live_1", "zajtra idem na túru potrebujem outfit"), context);
  assert.equal(first.failClosed, false);
  assert.equal(first.action, "clarify");
  assert.match(first.reply, /kam približne/i);
  assert.equal(providerCalls.length, 0, "first hiking clarification must not spend AI");
  assert.ok(Date.now() - firstStarted < 1500, "deterministic clarification should be effectively immediate");

  const why = await handler(base("live_2", "načo ti to je"), context);
  assert.equal(why.failClosed, false);
  assert.equal(why.action, "clarify");
  assert.match(why.reply, /počas/i);
  assert.equal(providerCalls.length, 0, "meta explanation must not spend AI");

  const outfitStarted = Date.now();
  const outfit = await handler(base("live_3", "do Tatier"), context);
  const outfitLatencyMs = Date.now() - outfitStarted;
  assert.equal(outfit.failClosed, false);
  assert.equal(outfit.action, "generate_outfit");
  assert.ok(outfit.resultingOutfitItemIds.length >= 3);
  qualityCheck(outfit.stylistComment);
  assert.equal(outfit.quickReplyMode, "yes_no");
  assert.match(String(outfit.quickReplyPrompt || ""), /turistick.*topán/i);
  assert.ok(outfitLatencyMs <= MAX_PROVIDER_LATENCY_MS + 3000,
    `outfit_end_to_end_latency_budget_exceeded:${outfitLatencyMs}`);

  const opinionStarted = Date.now();
  const opinion = await handler({
    ...base("live_4", "a sú tie tepláky v pohode?"),
    currentOutfitItemIds: outfit.resultingOutfitItemIds,
    currentSelectionReasons: outfit.resultingOutfitItems
      .filter((item) => item.stylistSelectionReason)
      .map((item) => ({itemId: item.id, reason: item.stylistSelectionReason})),
  }, context);
  const opinionLatencyMs = Date.now() - opinionStarted;
  assert.equal(opinion.failClosed, false);
  assert.equal(opinion.outfitChanged, false);
  assert.deepEqual(opinion.displayItemIds, []);
  qualityCheck(opinion.stylistComment, {allowQuestion: true});
  assert.ok(opinionLatencyMs <= MAX_PROVIDER_LATENCY_MS + 3000,
    `opinion_end_to_end_latency_budget_exceeded:${opinionLatencyMs}`);

  assert.ok(providerCalls.length <= MAX_PROVIDER_CALLS);
  const estimatedCost = usage.reduce((sum, event) => sum + Number(
    event.estimatedCostUsd ?? event.estimatedCostUsdMax ?? event.estimatedCostUsdMin ?? 0,
  ), 0);
  assert.ok(estimatedCost <= MAX_ESTIMATED_COST_USD,
    `live_smoke_cost_budget_exceeded:${estimatedCost}`);

  console.log(JSON.stringify({
    ok: true,
    providerCalls,
    outfitLatencyMs,
    opinionLatencyMs,
    estimatedCostUsd: Number(estimatedCost.toFixed(6)),
  }));
}

main().catch((error) => {
  console.error(`STYLIST_LIVE_SMOKE_FAILED ${error?.message || error}`);
  process.exitCode = 1;
});
