"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {enrichIdentity} = require("../../wardrobe_ontology_v2");
const {createOpenAiSimpleAgentExecutorV1} = require("../simple_stylist_agent_v1");
const {SELECTOR_MODEL, SELECTOR_REASONING_EFFORT, selectorPromptV2} =
  require("./openai_outfit_selector_v2");
const {JUDGE_MODEL, JUDGE_REASONING_EFFORT, judgeInputV2, judgePromptV2, judgeVisualEvidenceV2} =
  require("./openai_outfit_quality_judge_v2");
const {
  LANGUAGE_MODEL,
  LANGUAGE_REASONING_EFFORT,
  containsForbiddenLanguageV2,
  createOpenAiStylistLanguageV2,
  deterministicLanguageFallbackV2,
  formatTemperatureRangeSkV2,
  languagePromptV2,
} = require("./openai_stylist_language_v2");
const {buildSelectionContextV2} = require("./stylist_selection_context_v2");
const {createStylistSelectionPipelineV2, validateSelectionV2} =
  require("./stylist_selection_pipeline_v2");
const {projectWardrobeItemForStylistV2} = require("./wardrobe_integrity_projection_v2");
const {createStylistOneBrainEngineV2} = require("./stylist_one_brain_engine_v2");
const {createMemoryStylistSessionRepositoryV2} = require("./stylist_session_repository_v2");
const {createEmptySessionStateV2} = require("./stylist_session_state_v2");
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

test("generate_outfit repairs missing core coverage before Judge and freezes a complete outfit", async () => {
  const wardrobe = [
    item("shirt", "t_shirt"),
    item("hoodie", "hoodie"),
    item("pants", "jeans"),
    item("shoes", "sneakers"),
  ];
  let selectorCalls = 0;
  let judgeCalls = 0;
  let repairFeedback = null;
  const pipeline = createStylistSelectionPipelineV2({
    selector: {select: async (_context, options) => {
      selectorCalls += 1;
      if (selectorCalls === 1) return output(["shirt", "hoodie"]);
      repairFeedback = options.feedback;
      return output(["shirt", "hoodie", "pants", "shoes"]);
    }},
    judge: {judge: async (_context, selection) => {
      judgeCalls += 1;
      assert.deepEqual(selection.selectedItemIds, ["shirt", "hoodie", "pants", "shoes"]);
      return {verdict: "pass", problems: [], retryGuidance: null};
    }},
    logger: {warn() {}, info() {}},
  });
  const result = await pipeline.resolve(inputFor(wardrobe));
  assert.deepEqual(result.selection.selectedItemIds, ["shirt", "hoodie", "pants", "shoes"]);
  assert.equal(selectorCalls, 2);
  assert.equal(judgeCalls, 1);
  assert.equal(repairFeedback.source, "deterministic_contract");
  assert.deepEqual(repairFeedback.problems, [
    "selection_core_coverage_missing:lower_body",
    "selection_core_coverage_missing:feet",
  ]);
});

test("generate_outfit core coverage is availability-aware and accepts full-body coverage", () => {
  const shoesOnly = buildSelectionContextV2(inputFor([item("shoes", "sneakers")]));
  assert.deepEqual(validateSelectionV2(output(["shoes"]), shoesOnly).errors, []);

  const dress = item("dress", "dress", {bodySlots: ["full_body"]});
  const shoes = item("shoes", "sneakers");
  const fullBody = buildSelectionContextV2(inputFor([dress, shoes]));
  assert.deepEqual(validateSelectionV2(output(["dress", "shoes"]), fullBody).errors, []);
});

test("an incomplete Judge retry cannot replace the first complete frozen selection", async () => {
  const wardrobe = [item("top", "t_shirt"), item("bottom", "jeans"), item("shoes", "sneakers")];
  let selectorCalls = 0;
  const pipeline = createStylistSelectionPipelineV2({
    selector: {select: async () => ++selectorCalls === 1 ?
      output(["top", "bottom", "shoes"]) : output(["top"])},
    judge: {judge: async () => ({verdict: "retry", problems: ["Skontroluj celý outfit."],
      retryGuidance: "Zlepši súdržnosť bez straty základného pokrytia."})},
    logger: {warn() {}, info() {}},
  });
  const result = await pipeline.resolve(inputFor(wardrobe));
  assert.deepEqual(result.selection.selectedItemIds, ["top", "bottom", "shoes"]);
  assert.equal(selectorCalls, 2);
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

test("I and J: production-enabled non-mutating turns bypass every selection stage and preserve outfit", async (t) => {
  const cases = [
    {name: "chat", action: "chat", message: "Ako spolu fungujú farby v tomto outfite?", tool: false},
    {name: "show_items", action: "show_items", message: "Ukáž mi kúsky z aktuálneho outfitu.",
      scope: "current_outfit", displayIds: ["top", "bottom", "shoes"]},
    {name: "explain_outfit", action: "explain_outfit", message: "Vysvetli mi tento outfit.",
      scope: "current_outfit"},
    {name: "alternatives question", action: "show_items", message: "Aké alternatívy mám k týmto topánkam?",
      scope: "full_relevant", displayIds: ["alt-shoes"]},
    {name: "current outfit explanation", action: "explain_outfit",
      message: "Prečo presne tieto kúsky spolu fungujú?", scope: "current_outfit"},
  ];

  for (const scenario of cases) {
    await t.test(scenario.name, async () => {
      const repository = createMemoryStylistSessionRepositoryV2({now: () => 1_789_000_000_000});
      const wardrobe = [
        item("top", "t_shirt"), item("bottom", "jeans"),
        item("shoes", "sneakers"), item("alt-shoes", "sneakers"),
      ];
      const currentIds = ["top", "bottom", "shoes"];
      const reasons = {top: "Pôvodný vrch.", bottom: "Pôvodný spodok.", shoes: "Pôvodná obuv."};
      const calls = {selector: 0, judge: 0, language: 0};
      const handler = createStylistChatV2Handler({
        db: {}, admin: {}, logger: {warn() {}, info() {}}, resolveOpenAISecret: () => "unused",
        sessionRepository: repository,
        brainFactory: () => ({async brainTurn(input) {
          if (!scenario.scope) {
            return {kind: "final", pendingReplyDisposition: "none", statePatch: {},
              selectionHandoffIntent: "non_mutating", selectionAction: null,
              result: {action: scenario.action, assistantText: "Jasné, outfit nemením.",
                display: {kind: "none", itemIds: []}}};
          }
          if (input.stage === "tools") {
            return {kind: "tool_request", pendingReplyDisposition: "none", statePatch: {},
              requests: [{tool: "wardrobe", scope: scenario.scope, category: null, editScope: null}],
              selectionHandoffIntent: "non_mutating", selectionAction: null,
              selectionIntentSummary: null, selectionConstraints: []};
          }
          return {kind: "final", statePatch: {}, result: {
            action: scenario.action,
            assistantText: "Tu je odpoveď bez zmeny outfitu.",
            display: {kind: scenario.displayIds ? "items" : "none", itemIds: scenario.displayIds || []},
          }};
        }}),
        selectorFactory: () => ({async select() { calls.selector += 1; throw new Error("unexpected_selector"); }}),
        judgeFactory: () => ({async judge() { calls.judge += 1; throw new Error("unexpected_judge"); }}),
        languageFactory: () => ({async render() { calls.language += 1; throw new Error("unexpected_language"); }}),
        wardrobeToolFactory: () => ({
          async retrieve() { return structuredClone(wardrobe); },
          async materialize(ids, reasonMap) {
            const byId = new Map(wardrobe.map((entry) => [entry.id, entry]));
            return ids.map((id) => ({...byId.get(id), stylistSelectionReason: reasonMap[id]}));
          },
        }),
        locationResolver: {async resolve() { return null; }},
        weatherTool: {async getForecast() { return null; }},
        shoppingToolFactory: () => ({async search() { return {candidateIds: [], appliedHardConstraints: []}; }}),
      });
      const response = await handler({
        v2SessionId: `non-mutating-${scenario.name.replace(/\s+/g, "-")}`,
        turnId: "turn-1", message: scenario.message,
        currentOutfitItemIds: currentIds,
        currentSelectionReasons: Object.entries(reasons).map(([itemId, reason]) => ({itemId, reason})),
        shoppingEnabled: false,
        clientContext: {todayDateKey: "2026-09-16", tomorrowDateKey: "2026-09-17",
          timezoneOffsetMinutes: 120},
      }, {auth: {uid: "user"}});
      const stored = await repository.get({uid: "user", chatId: response.sessionId});
      assert.equal(["generate_outfit", "edit_outfit"].includes(response.action), false);
      assert.deepEqual(new Set(response.resultingOutfitItemIds), new Set(currentIds));
      assert.deepEqual(stored.state.currentOutfit.itemIds, currentIds);
      assert.deepEqual(stored.state.currentOutfit.selectionReasonsByItemId, reasons);
      assert.deepEqual(calls, {selector: 0, judge: 0, language: 0});
    });
  }
});

test("K and L: deterministic Slovak fallback is direct for weather, negatives, compromises and missing weather", () => {
  assert.equal(formatTemperatureRangeSkV2(-5, 1), "-5 až 1 °C");
  assert.equal(containsForbiddenLanguageV2("Jasné — vybral som túto bundu."), true);
  assert.doesNotMatch(languagePromptV2(), /Jasné —/u);
  const wardrobe = [
    item("top", "t_shirt"), item("bottom", "jeans"), item("shoes", "sneakers"),
  ];
  const ordinary = buildSelectionContextV2(inputFor(wardrobe, {
    session: {...inputFor([]).session, context: {...inputFor([]).session.context,
      weather: {snapshot: {minTempC: 11, maxTempC: 16}}}},
  }));
  const negative = buildSelectionContextV2(inputFor(wardrobe, {
    session: {...inputFor([]).session, context: {...inputFor([]).session.context,
    weather: {snapshot: {minTempC: -5, maxTempC: 1}}}}}));
  const withoutWeather = buildSelectionContextV2(inputFor(wardrobe));
  const selection = output(["top", "bottom", "shoes"]);
  assert.equal(deterministicLanguageFallbackV2(ordinary, selection),
    "Zvoľ top, bottom a shoes. Vonku má byť približne 11 až 16 °C.");
  assert.equal(deterministicLanguageFallbackV2(negative, selection),
    "Zvoľ top, bottom a shoes. Vonku má byť približne -5 až 1 °C.");
  assert.equal(deterministicLanguageFallbackV2(withoutWeather, selection),
    "Zvoľ top, bottom a shoes.");
  assert.equal(deterministicLanguageFallbackV2(withoutWeather,
    output(["top", "bottom", "shoes"], null, ["Dostupná obuv je menej formálna."])),
  "Zvoľ top, bottom a shoes. Najväčší kompromis: Dostupná obuv je menej formálna.");
  for (const text of [deterministicLanguageFallbackV2(ordinary, selection),
    deterministicLanguageFallbackV2(negative, selection)]) {
    assert.doesNotMatch(text, /[—–]|by som zvolil|ja by som si dal/iu);
  }
});

test("Language provider failure and forbidden generated prose use the exact human fallback", async () => {
  const context = buildSelectionContextV2(inputFor([
    item("top", "t_shirt"), item("bottom", "jeans"), item("shoes", "sneakers"),
  ], {session: {...inputFor([]).session, context: {...inputFor([]).session.context,
    weather: {snapshot: {minTempC: 11, maxTempC: 16}}}}}));
  const selection = output(["top", "bottom", "shoes"]);
  const expected = "Zvoľ top, bottom a shoes. Vonku má byť približne 11 až 16 °C.";
  const failed = createOpenAiStylistLanguageV2({
    executeStructured: async () => { throw new Error("provider_unavailable"); },
    logger: {warn() {}, info() {}},
  });
  const forbidden = createOpenAiStylistLanguageV2({
    executeStructured: async () => ({assistantText: "Jasné — ja by som zvolil tento outfit."}),
    logger: {warn() {}, info() {}},
  });
  assert.equal(await failed.render(context, selection), expected);
  assert.equal(await forbidden.render(context, selection), expected);
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
  const toolsSchema = schemaForStageV2("tools", true);
  assert.ok(toolsSchema.required.includes("selectionHandoffIntent"));
  assert.deepEqual(toolsSchema.properties.selectionHandoffIntent.enum,
    ["non_mutating", "generate_outfit", "edit_outfit"]);
});

test("51 candidates remain selectable while visual evidence is bounded to 24", () => {
  const wardrobe = Array.from({length: 51}, (_value, index) =>
    item(`candidate-${index}`, index % 2 ? "sneakers" : "t_shirt"));
  const context = buildSelectionContextV2(inputFor(wardrobe));
  assert.equal(context.selection.candidateItems.length, 51);
  assert.equal(context.visualEvidence.length, 24);
  assert.equal(new Set(context.visualEvidence.map((entry) => entry.id)).size, 24);
});

test("Judge receives a selected image outside the Selector 24-image sample and stays bounded to 16", () => {
  const wardrobe = Array.from({length: 30}, (_value, index) =>
    item(`candidate-${index}`, index % 2 ? "sneakers" : "t_shirt", {
      imageUrl: `https://images.invalid/item-${index}.png`,
    }));
  const context = buildSelectionContextV2(inputFor(wardrobe));
  const selectedId = "candidate-29";
  assert.equal(context.visualEvidence.some((entry) => entry.id === selectedId), false);
  const selection = output([selectedId]);
  const evidence = judgeVisualEvidenceV2(context, selection);
  assert.equal(evidence.length, 16);
  assert.equal(evidence[0].id, selectedId);
  assert.equal(evidence[0].imageUrl, "https://images.invalid/item-29.png");
  const input = judgeInputV2(context, selection);
  const content = input[1].content;
  const selectedLabelIndex = content.findIndex((entry) => entry.type === "input_text" &&
    entry.text.includes(`Vybraný vizuálny dôkaz pre itemId ${selectedId}`));
  assert.ok(selectedLabelIndex > 0);
  assert.equal(content[selectedLabelIndex + 1].image_url, "https://images.invalid/item-29.png");
  assert.equal(content.filter((entry) => entry.type === "input_image").length, 16);
});

test("typed selection handoff preserves generate/edit continuations and blocks answer-stage ranking", async (t) => {
  const requestFor = (chatId, message) => ({
    chatId, turnId: "turn-1", expectedSessionRevision: 0,
    latestUserInput: message, explicitUiActionId: null,
    freshClientObservations: {},
    clientCapabilities: {shoppingEnabled: false, supportsProgress: false,
      todayDateKey: "2026-09-16", tomorrowDateKey: "2026-09-17", timezoneOffsetMinutes: 120,
      recentHistory: []},
  });
  const basePorts = (wardrobe) => ({
    wardrobeTool: {async retrieve() { return structuredClone(wardrobe); }},
    locationResolver: {async resolve() { return null; }},
    weatherTool: {async getForecast() { return null; }},
    shoppingTool: {async search() { return {candidateIds: [], appliedHardConstraints: []}; }},
  });

  for (const action of ["generate_outfit", "edit_outfit"]) {
    await t.test(`${action} pendingResumeAction wins when tool selectionAction is missing`, async () => {
      const chatId = `pending-${action}`;
      const repository = createMemoryStylistSessionRepositoryV2({now: () => 1_789_000_000_000});
      const state = structuredClone(createEmptySessionStateV2(chatId));
      const wardrobe = [item("top", "t_shirt"), item("bottom", "jeans"),
        item("old-shoes", "sneakers"), item("new-shoes", "sneakers")];
      if (action === "edit_outfit") {
        state.currentOutfit.itemIds = ["top", "bottom", "old-shoes"];
        state.currentOutfit.selectionReasonsByItemId = {
          top: "Pôvodný vrch.", bottom: "Pôvodný spodok.", "old-shoes": "Pôvodná obuv.",
        };
        state.currentOutfit.revision = 1;
      } else {
        state.context.terrain.condition = "wet";
      }
      state.conversationMemory.pendingQuestion = {
        type: "question", field: "date", question: "Na ktorý deň?", actionId: "clarify_date",
        acceptsYesNo: false, resumeAction: action,
      };
      await repository.ensure({uid: "user", chatId, bootstrapState: state});
      let selectorCalls = 0;
      const engine = createStylistOneBrainEngineV2({
        sessionRepository: repository,
        ...basePorts(wardrobe),
        stylistBrain: {async brainTurn() {
          return {kind: "tool_request", pendingReplyDisposition: "answer", statePatch: {},
            requests: [{tool: "wardrobe",
              scope: action === "edit_outfit" ? "current_outfit_plus_category" : "full_relevant",
              category: action === "edit_outfit" ? "sneakers" : null,
              editScope: action === "edit_outfit" ? {
                replaceItemIds: ["old-shoes"], retainItemIds: [],
                allowedSlots: ["feet"], allowedCategories: ["sneakers"], allowRemovalOnly: false,
              } : null}],
            selectionHandoffIntent: "non_mutating",
            selectionAction: null,
            selectionIntentSummary: null,
            selectionConstraints: [],
          };
        }},
        selectionPipeline: {async resolve(args) {
          selectorCalls += 1;
          assert.equal(args.action, action);
          const ids = action === "edit_outfit" ? ["top", "bottom", "new-shoes"] :
            ["top", "bottom", "new-shoes"];
          const reasons = action === "edit_outfit" ? {
            top: "Pôvodný vrch.", bottom: "Pôvodný spodok.", "new-shoes": "Nová obuv.",
          } : null;
          return {selection: Object.freeze(output(ids, reasons)),
            context: {candidateItems: wardrobe, selection: {action, context: {}}}};
        }},
        languageGenerator: {async render() { return "Zvoľ pripravenú kombináciu."; }},
      });
      const result = await engine.resolveTurn({
        uid: "user", request: requestFor(chatId, "Budúci týždeň."),
      });
      assert.equal(result.action, action);
      assert.equal(selectorCalls, 1);
      assert.deepEqual(result.resultingOutfit.itemIds, ["top", "bottom", "new-shoes"]);
    });
  }

  await t.test("answer-stage Brain IDs never become authoritative", async () => {
    const repository = createMemoryStylistSessionRepositoryV2({now: () => 1_789_000_000_000});
    const wardrobe = [item("top", "t_shirt"), item("bottom", "jeans"), item("shoes", "sneakers")];
    let calls = 0;
    const engine = createStylistOneBrainEngineV2({
      sessionRepository: repository,
      ...basePorts(wardrobe),
      stylistBrain: {async brainTurn(input) {
        calls += 1;
        if (input.stage === "tools") {
          return {kind: "tool_request", pendingReplyDisposition: "none", statePatch: {},
            requests: [{tool: "wardrobe", scope: "full_relevant", category: null, editScope: null}],
            selectionHandoffIntent: "non_mutating", selectionAction: null,
            selectionIntentSummary: null, selectionConstraints: []};
        }
        return {kind: "final", statePatch: {}, result: {
          action: "generate_outfit", assistantText: "Toto nemá byť autoritatívne.",
          resultingOutfit: {itemIds: ["top", "bottom", "shoes"],
            selectionReasonsByItemId: {top: "x", bottom: "x", shoes: "x"},
            compromises: [], missingWardrobeNeeds: []},
          display: {kind: "outfit", itemIds: ["top", "bottom", "shoes"]},
        }};
      }},
      selectionPipeline: {async resolve() { throw new Error("selector_must_not_run"); }},
      languageGenerator: {async render() { throw new Error("language_must_not_run"); }},
    });
    await assert.rejects(engine.resolveTurn({
      uid: "user",
      request: requestFor("answer-ranking", "Ukáž mi dostupné kúsky."),
      bootstrapInput: {currentOutfitItemIds: [], persistedSelectionReasonsByItemId: {},
        knownExplicitDurableChoices: {}},
    }), /one-brain answer cannot rank outfit IDs/);
    assert.equal(calls, 2);
  });
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
        selectionHandoffIntent: "generate_outfit",
        selectionAction: null,
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
