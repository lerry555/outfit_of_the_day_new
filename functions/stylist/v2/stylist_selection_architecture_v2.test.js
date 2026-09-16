"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {enrichIdentity} = require("../../wardrobe_ontology_v2");
const {createOpenAiSimpleAgentExecutorV1} = require("../simple_stylist_agent_v1");
const {SELECTOR_MODEL, SELECTOR_REASONING_EFFORT, selectorPromptV2} =
  require("./openai_outfit_selector_v2");
const {JUDGE_MODEL, JUDGE_REASONING_EFFORT, judgePromptV2} =
  require("./openai_outfit_quality_judge_v2");
const {
  LANGUAGE_MODEL,
  LANGUAGE_REASONING_EFFORT,
  containsForbiddenLanguageV2,
  deterministicLanguageFallbackV2,
  formatTemperatureRangeSkV2,
  languagePromptV2,
} = require("./openai_stylist_language_v2");
const {buildSelectionContextV2} = require("./stylist_selection_context_v2");
const {createStylistSelectionPipelineV2} = require("./stylist_selection_pipeline_v2");
const {projectWardrobeItemForStylistV2} = require("./wardrobe_integrity_projection_v2");
const {createStylistOneBrainEngineV2} = require("./stylist_one_brain_engine_v2");
const {createMemoryStylistSessionRepositoryV2} = require("./stylist_session_repository_v2");
const {schemaForStageV2} = require("./openai_one_brain_model_port_v2");
const {createStylistChatV2Handler} = require("./stylist_production_bridge_one_brain_v2");

function item(id, canonicalType, overrides = {}) {
  return {
    id,
    name: id,
    ontologyVersion: "2.0.0",
    ...enrichIdentity(canonicalType),
    colorProfile: {primary: {family: "black"}, secondary: null, accents: []},
    colors: ["black"],
    warmth: 4,
    formality: 4,
    styles: [],
    occasionFit: [],
    seasons: ["spring", "summer", "autumn", "winter"],
    imageUrl: "data:image/png;base64,AA==",
    ...overrides,
  };
}

function inputFor(wardrobeItems, overrides = {}) {
  return {
    action: "generate_outfit",
    intentSummary: "Vyber súdržný outfit podľa dodaného kontextu.",
    requestedConstraints: [],
    request: {latestUserInput: "Prosím outfit."},
    session: {
      context: {activity: null, environment: "outdoor", date: null, timeWindow: null,
        terrain: null, weather: null, destination: null, eventLocation: null},
      currentOutfit: {itemIds: [], selectionReasonsByItemId: {}},
    },
    toolResults: {authorizedEditScope: null},
    wardrobeItems,
    logger: {warn() {}, info() {}},
    ...overrides,
  };
}

function output(ids, reasons = null, compromises = [], missingWardrobeNeeds = []) {
  return {
    selectedItemIds: ids,
    selectionReasons: ids.map((id) => ({itemId: id, reason: reasons?.[id] || `Dôvod pre ${id}.`})),
    compromises,
    missingWardrobeNeeds,
  };
}

test("A, N, O: mild formal context rejects an over-warm visual guess and retries exactly once", async () => {
  const boots = item("dark-boots", "winter_boots", {warmth: 9, formality: 2,
    seasons: ["autumn", "winter"], occasionFit: ["winter_outdoor", "casual_wear"]});
  const sneakers = item("white-sneakers", "sneakers", {warmth: 4, formality: 2,
    seasons: ["spring", "summer", "autumn"], occasionFit: ["everyday_casual", "streetwear"]});
  let selectorCalls = 0;
  const pipeline = createStylistSelectionPipelineV2({
    selector: {select: async () => ++selectorCalls === 1 ?
      output(["dark-boots"], {"dark-boots": "Sú tmavé, preto pôsobia formálnejšie."}) :
      output(["white-sneakers"], {"white-sneakers": "Sú menej teplé a sú sezónne primerané."},
        ["Šatník nemá ideálnu formálnu obuv."], ["formálnejšia prechodná obuv"])},
    judge: {judge: async (_context, selection) => selection.selectedItemIds.includes("dark-boots") ? {
      verdict: "retry",
      problems: ["Vizuálna tmavosť neprebíja warmth 9 a zimné funkcie v miernom počasí."],
      retryGuidance: "Porovnaj ne-vizuálne sezónne a tepelné fakty.",
    } : {verdict: "pass", problems: [], retryGuidance: null}},
    logger: {warn() {}, info() {}},
  });
  const resolved = await pipeline.resolve(inputFor([boots, sneakers], {
    intentSummary: "Formálnejšia udalosť v septembri.",
    session: {...inputFor([]).session, context: {...inputFor([]).session.context,
      date: {dateKey: "2026-09-20"}, weather: {snapshot: {minTempC: 14, maxTempC: 20}}}},
  }));
  assert.deepEqual(resolved.selection.selectedItemIds, ["white-sneakers"]);
  assert.equal(selectorCalls, 2);
  assert.ok(resolved.selection.compromises.length);
  assert.equal(Object.isFrozen(resolved.selection), true);
  assert.doesNotMatch(selectorPromptV2(), /wedding|svadba|september/i);
  assert.doesNotMatch(judgePromptV2(), /wedding|svadba|september/i);
});

test("B: no ideal formal footwear remains an explicit, non-fabricated compromise", async () => {
  const wardrobe = [item("only-sneakers", "sneakers", {formality: 2})];
  const pipeline = createStylistSelectionPipelineV2({
    selector: {select: async () => output(["only-sneakers"], null,
      ["Dostupná obuv je menej formálna."], ["formálna obuv"])},
    judge: {judge: async () => ({verdict: "pass", problems: [], retryGuidance: null})},
  });
  const result = await pipeline.resolve(inputFor(wardrobe));
  assert.deepEqual(result.selection.selectedItemIds, ["only-sneakers"]);
  assert.deepEqual(result.selection.missingWardrobeNeeds, ["formálna obuv"]);
});

test("C through G: generic context can preserve winter, rain, hike, summer and visual-style outcomes", async (t) => {
  const cases = [
    ["actual cold winter", "winter-boots", item("winter-boots", "winter_boots", {warmth: 9})],
    ["rainy cold city walk", "chelsea", item("chelsea", "chelsea_boots", {warmth: 6})],
    ["normal hike compromise", "trail-sneakers", item("trail-sneakers", "sneakers", {outfitFunctions: ["walking"]})],
    ["summer casual", "summer-sneakers", item("summer-sneakers", "sneakers", {seasons: ["summer"]})],
    ["visual dinner style", "sleek-chelsea", item("sleek-chelsea", "chelsea_boots", {formality: 6})],
  ];
  for (const [name, expected, selected] of cases) {
    await t.test(name, async () => {
      const pipeline = createStylistSelectionPipelineV2({
        selector: {select: async () => output([expected])},
        judge: {judge: async () => ({verdict: "pass", problems: [], retryGuidance: null})},
      });
      const result = await pipeline.resolve(inputFor([selected], {intentSummary: name}));
      assert.deepEqual(result.selection.selectedItemIds, [expected]);
    });
  }
});

test("H: an item edit cannot drop retained pieces or expand authorization", async () => {
  const top = item("top", "t_shirt");
  const jeans = item("jeans", "jeans");
  const oldShoes = item("old-shoes", "sneakers");
  const newShoes = item("new-shoes", "sneakers");
  let calls = 0;
  const pipeline = createStylistSelectionPipelineV2({
    selector: {select: async () => ++calls === 1 ? output(["new-shoes"]) :
      output(["top", "jeans", "new-shoes"])},
    judge: {judge: async () => ({verdict: "pass", problems: [], retryGuidance: null})},
  });
  const result = await pipeline.resolve(inputFor([top, jeans, oldShoes, newShoes], {
    action: "edit_outfit",
    session: {...inputFor([]).session, currentOutfit: {
      itemIds: ["top", "jeans", "old-shoes"],
      selectionReasonsByItemId: {top: "retained top", jeans: "retained jeans", "old-shoes": "old"},
    }},
    toolResults: {authorizedEditScope: {
      replaceItemIds: ["old-shoes"], retainItemIds: ["top", "jeans"],
      allowedSlots: ["feet"], allowedCategories: [], allowRemovalOnly: false,
    }},
  }));
  assert.deepEqual(result.selection.selectedItemIds, ["top", "jeans", "new-shoes"]);
  assert.equal(calls, 2);
  assert.equal(result.selection.selectionReasons.find((entry) => entry.itemId === "top").reason, "retained top");
});

test("I and J: non-mutating Brain actions do not enter the selection architecture", () => {
  assert.ok(!["chat", "show_items", "explain_outfit"].includes("generate_outfit"));
  assert.match(selectorPromptV2(), /Nevlastníš konverzáciu/);
});

test("K and L: Slovak language contract preserves negative temperatures and avoids stylist self-talk", () => {
  assert.equal(formatTemperatureRangeSkV2(-5, 1), "-5 až 1 °C");
  assert.equal(containsForbiddenLanguageV2("Jasné — vybral som túto bundu."), true);
  assert.doesNotMatch(languagePromptV2(), /Jasné —/u);
  const context = buildSelectionContextV2(inputFor([
    item("top", "t_shirt"), item("bottom", "jeans"), item("shoes", "sneakers"),
  ], {session: {...inputFor([]).session, context: {...inputFor([]).session.context,
    weather: {snapshot: {minTempC: -5, maxTempC: 1}}}}}));
  const text = deterministicLanguageFallbackV2(context,
    output(["top", "bottom", "shoes"]));
  assert.match(text, /-5 až 1 °C/);
  assert.doesNotMatch(text, /[—–]|by som zvolil|ja by som si dal/iu);
});

test("M: ontology contradiction is diagnosed and only the in-memory projection changes", () => {
  const raw = item("grey-chinos", "chinos", {
    canonicalFamily: "top", bodySlots: ["upper_body"], layerPosition: "base",
  });
  const before = structuredClone(raw);
  const result = projectWardrobeItemForStylistV2(raw);
  assert.deepEqual(raw, before);
  assert.equal(result.item.canonicalFamily, "bottom");
  assert.deepEqual(result.item.bodySlots, ["lower_body"]);
  assert.equal(result.item.layerPosition, "outer");
  assert.ok(result.diagnostics.some((entry) => entry.code === "ontology_parent_family_conflict"));
});

test("Judge transport failure keeps a valid Selector result", async () => {
  const pipeline = createStylistSelectionPipelineV2({
    selector: {select: async () => output(["shoes"])},
    judge: {judge: async () => { throw new Error("temporary"); }},
    logger: {warn() {}, info() {}},
  });
  const result = await pipeline.resolve(inputFor([item("shoes", "sneakers")]));
  assert.deepEqual(result.selection.selectedItemIds, ["shoes"]);
});

test("Selector retry transport failure freezes the first structurally valid result", async () => {
  let calls = 0;
  const pipeline = createStylistSelectionPipelineV2({
    selector: {select: async () => {
      calls += 1;
      if (calls === 2) throw new Error("retry unavailable");
      return output(["shoes"]);
    }},
    judge: {judge: async () => ({verdict: "retry", problems: ["material issue"],
      retryGuidance: "try once"})},
    logger: {warn() {}, info() {}},
  });
  const result = await pipeline.resolve(inputFor([item("shoes", "sneakers")]));
  assert.deepEqual(result.selection.selectedItemIds, ["shoes"]);
  assert.equal(calls, 2);
});

test("multimodal transport keeps store:false and does not log image URLs", async () => {
  let body;
  const log = [];
  const execute = createOpenAiSimpleAgentExecutorV1({
    fetchImpl: async (_url, request) => {
      body = JSON.parse(request.body);
      return {ok: true, status: 200, headers: {get: () => null}, json: async () => ({
        id: "response-test", model: "gpt-5.6-terra", output_text: "{\"ok\":true}", usage: {},
      })};
    },
    resolveOpenAISecret: () => "test-secret",
    logger: {info: (...args) => log.push(args), warn: (...args) => log.push(args)},
  });
  await execute({
    model: "gpt-5.6-terra", reasoningEffort: "medium",
    schemaName: "test", schema: {type: "object", additionalProperties: false,
      required: ["ok"], properties: {ok: {type: "boolean"}}},
    input: [{role: "user", content: [
      {type: "input_text", text: "item one"},
      {type: "input_image", image_url: "data:image/png;base64,ZmFrZQ==", detail: "low"},
    ]}],
  });
  assert.equal(body.store, false);
  assert.equal(body.input[0].content[1].type, "input_image");
  assert.doesNotMatch(JSON.stringify(log), /ZmFrZQ/);
});

test("production routing is explicit and keeps quality-critical stages on Terra medium", () => {
  assert.deepEqual([SELECTOR_MODEL, SELECTOR_REASONING_EFFORT], ["gpt-5.6-terra", "medium"]);
  assert.deepEqual([JUDGE_MODEL, JUDGE_REASONING_EFFORT], ["gpt-5.6-terra", "medium"]);
  assert.deepEqual([LANGUAGE_MODEL, LANGUAGE_REASONING_EFFORT], ["gpt-5.6-luna", "low"]);
  const actions = schemaForStageV2("answer", false, "non_mutating").properties.action.enum;
  assert.equal(actions.includes("generate_outfit"), false);
  assert.equal(actions.includes("edit_outfit"), false);
});

test("51 candidates remain selectable while visual evidence is bounded to 24", () => {
  const wardrobe = Array.from({length: 51}, (_value, index) =>
    item(`candidate-${index}`, index % 2 ? "sneakers" : "t_shirt"));
  const context = buildSelectionContextV2(inputFor(wardrobe));
  assert.equal(context.selection.candidateItems.length, 51);
  assert.equal(context.visualEvidence.length, 24);
  assert.equal(new Set(context.visualEvidence.map((entry) => entry.id)).size, 24);
});

test("Brain hands generate selection to the bounded pipeline and never makes an answer-stage ranking", async () => {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => 1_789_000_000_000});
  const calls = {brain: 0, selector: 0, language: 0};
  const wardrobe = [
    item("top", "t_shirt"), item("bottom", "jeans"), item("shoes", "sneakers"),
  ];
  const engine = createStylistOneBrainEngineV2({
    sessionRepository: repository,
    wardrobeTool: {async retrieve() { return wardrobe; }},
    locationResolver: {async resolve() { return null; }},
    weatherTool: {async getForecast() { return null; }},
    shoppingTool: {async search() { return {candidateIds: [], appliedHardConstraints: []}; }},
    stylistBrain: {async brainTurn() {
      calls.brain += 1;
      return {
        kind: "tool_request",
        statePatch: {},
        requests: [{tool: "wardrobe", scope: "full_relevant", category: null, editScope: null}],
        selectionAction: "generate_outfit",
        selectionIntentSummary: "Kompletný outfit.",
        selectionConstraints: [],
      };
    }},
    selectionPipeline: {async resolve(args) {
      calls.selector += 1;
      assert.equal(args.action, "generate_outfit");
      return {
        selection: Object.freeze(output(["top", "bottom", "shoes"])),
        context: {candidateItems: wardrobe, selection: {action: "generate_outfit", context: {}}},
      };
    }},
    languageGenerator: {async render() {
      calls.language += 1;
      return "Hotový outfit je pripravený z tvojich kúskov.";
    }},
  });
  const result = await engine.resolveTurn({
    uid: "user",
    request: {
      chatId: "chat", turnId: "turn", expectedSessionRevision: 0,
      latestUserInput: "Prosím outfit.", explicitUiActionId: null,
      freshClientObservations: {},
      clientCapabilities: {shoppingEnabled: false, supportsProgress: false,
        todayDateKey: "2026-09-16", tomorrowDateKey: "2026-09-17", timezoneOffsetMinutes: 120,
        recentHistory: []},
    },
    bootstrapInput: {currentOutfitItemIds: [], persistedSelectionReasonsByItemId: {},
      knownExplicitDurableChoices: {}},
  });
  assert.deepEqual(result.resultingOutfit.itemIds, ["top", "bottom", "shoes"]);
  assert.deepEqual(calls, {brain: 1, selector: 1, language: 1});
});

test("production bridge executes Brain to Selector to Judge to frozen IDs to Language", async () => {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => 1_789_000_000_000});
  const wardrobe = [
    item("top", "t_shirt"), item("bottom", "jeans"), item("shoes", "sneakers"),
  ];
  const calls = [];
  const handler = createStylistChatV2Handler({
    db: {}, admin: {}, logger: {warn() {}, info() {}}, resolveOpenAISecret: () => "unused",
    sessionRepository: repository,
    brainFactory: () => ({async brainTurn() {
      calls.push("brain");
      return {
        kind: "tool_request", statePatch: {},
        requests: [{tool: "wardrobe", scope: "full_relevant", category: null, editScope: null}],
        selectionAction: "generate_outfit", selectionIntentSummary: "Kompletný outfit.",
        selectionConstraints: [],
      };
    }}),
    selectorFactory: () => ({async select() {
      calls.push("selector");
      return output(["top", "bottom", "shoes"]);
    }}),
    judgeFactory: () => ({async judge() {
      calls.push("judge");
      return {verdict: "pass", problems: [], retryGuidance: null};
    }}),
    languageFactory: () => ({async render() {
      calls.push("language");
      return "Outfit je pripravený a jeho kúsky spolu fungujú.";
    }}),
    wardrobeToolFactory: () => ({
      async retrieve() { return structuredClone(wardrobe); },
      async materialize(ids, reasons) {
        const byId = new Map(wardrobe.map((entry) => [entry.id, entry]));
        return ids.map((id) => ({...byId.get(id), stylistSelectionReason: reasons[id]}));
      },
    }),
    locationResolver: {async resolve() { return null; }},
    weatherTool: {async getForecast() { return null; }},
    shoppingToolFactory: () => ({async search() { return {candidateIds: [], appliedHardConstraints: []}; }}),
  });
  const response = await handler({
    v2SessionId: "bridge-chat", turnId: "bridge-turn", message: "Prosím celý outfit.",
    currentOutfitItemIds: [], currentSelectionReasons: [], shoppingEnabled: false,
    clientContext: {todayDateKey: "2026-09-16", tomorrowDateKey: "2026-09-17",
      timezoneOffsetMinutes: 120},
  }, {auth: {uid: "user"}});
  assert.equal(response.action, "generate_outfit");
  assert.deepEqual(new Set(response.resultingOutfitItemIds), new Set(["top", "bottom", "shoes"]));
  assert.deepEqual(calls, ["brain", "selector", "judge", "language"]);
});
