"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {createStylistOneBrainEngineV2} = require("./stylist_one_brain_engine_v2");
const {createMemoryStylistSessionRepositoryV2} = require("./stylist_session_repository_v2");
const {RepairableStructuralTurnError} = require("./stylist_turn_validator_v2");
const {createOpenAiOneBrainModelPortV2} = require("./openai_one_brain_model_port_v2");
const {finalEnvelope} = require("./openai_stylist_model_port_v2");
const {
  createStylistChatV2Handler,
} = require("./stylist_production_bridge_one_brain_v2");

const NOW = Date.parse("2026-09-10T08:00:00.000Z");

function wardrobeItems() {
  return [
    {id: "tee", category: "tops", bodySlots: ["upper_body"], canonicalType: "t_shirt"},
    {id: "pants", category: "bottoms", bodySlots: ["lower_body"], canonicalType: "pants"},
    {id: "shoes", category: "footwear", bodySlots: ["feet"], canonicalType: "sneakers"},
  ];
}

function request({chatId, turnId, revision, message}) {
  return {
    chatId,
    turnId,
    expectedSessionRevision: revision,
    latestUserInput: message,
    explicitUiActionId: null,
    freshClientObservations: {},
    clientCapabilities: {
      shoppingEnabled: false,
      supportsProgress: true,
      todayDateKey: "2026-09-10",
      tomorrowDateKey: "2026-09-11",
      timezoneOffsetMinutes: 120,
      recentHistory: [],
    },
  };
}

function fakePorts({brain, location = null, calls = {}}) {
  const items = wardrobeItems();
  return {
    wardrobeTool: {
      async retrieve(args) {
        calls.wardrobe = (calls.wardrobe || 0) + 1;
        calls.lastWardrobeArgs = args;
        return items;
      },
      async materialize(ids, reasons) {
        return ids.map((id) => ({id, selectionReason: reasons[id] || null}));
      },
    },
    locationResolver: {
      async resolve(query) {
        calls.location = (calls.location || 0) + 1;
        calls.lastLocationQuery = query;
        return location;
      },
    },
    weatherTool: {
      async getForecast({location: target, date, timeWindow}) {
        calls.weather = (calls.weather || 0) + 1;
        return {
          locationProviderId: target.providerId,
          dateKey: date.dateKey,
          timeWindowKey: timeWindow.key,
          fetchedAt: "2026-09-10T08:00:00.000Z",
          source: "fake-weather",
          snapshot: {representativeTempC: 14, willRain: false, willSnow: false},
        };
      },
    },
    shoppingTool: {
      async search(context) {
        calls.shopping = (calls.shopping || 0) + 1;
        return {candidateIds: [], appliedHardConstraints: context.hardConstraints || [], reply: "Pozrel som možnosti."};
      },
    },
    stylistBrain: brain,
  };
}

test("One Brain: Austria hike -> Alps answer cannot trigger a second clarification", async () => {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  const calls = {brainInputs: []};
  const scripts = [
    {
      kind: "final",
      statePatch: {
        context: {
          activity: {id: "hiking", label: "túra", source: "user"},
          date: {dateKey: "2026-09-11", source: "user"},
          timeWindow: {key: "day", label: "cez deň", source: "one_brain_default"},
          environment: "outdoor",
          groundingRequirements: {
            weatherRequired: true,
            weatherLocationField: "destination",
            terrainRequiredFields: [],
          },
        },
      },
      result: {
        action: "clarify",
        assistantText: "Kam približne v Rakúsku ideš?",
        clarification: {
          field: "destination",
          question: "Kam približne v Rakúsku ideš?",
          actionId: "clarify_destination",
        },
        display: {kind: "none", itemIds: []},
      },
    },
    {
      kind: "tool_request",
      statePatch: {
        context: {
          groundingRequirements: {
            weatherRequired: true,
            weatherLocationField: "destination",
            terrainRequiredFields: [],
          },
        },
      },
      requests: [
        {tool: "location", query: "Alpy, Rakúsko", targetField: "destination"},
        {tool: "wardrobe", scope: "full_relevant", category: null, editScope: null},
      ],
    },
    {
      kind: "final",
      statePatch: {},
      result: {
        action: "generate_outfit",
        assistantText: "Na túru by som išiel do funkčného trička, praktických nohavíc a najlepších tenisiek, ktoré máš. Keďže nepoznáme presný terén, topánky ber ako konzervatívny kompromis a na technickú alebo mokrú trasu by som chcel turistickú obuv.",
        resultingOutfit: {
          itemIds: ["tee", "pants", "shoes"],
          selectionReasonsByItemId: {
            tee: "ľahká vrstva na pohyb",
            pants: "praktický spodný diel",
            shoes: "najpraktickejšia dostupná obuv",
          },
          compromises: ["tenisky namiesto turistickej obuvi"],
          missingWardrobeNeeds: [],
        },
        display: {kind: "outfit", itemIds: ["tee", "pants", "shoes"]},
      },
    },
  ];
  const brain = {
    async brainTurn(input) {
      calls.brainInputs.push(JSON.parse(JSON.stringify(input)));
      return scripts.shift();
    },
  };
  const ports = fakePorts({
    brain,
    calls,
    location: {
      providerId: "openmeteo:alps",
      label: "Alpy, Rakúsko",
      lat: 47.2,
      lng: 12.2,
      source: "fake-location",
      granularity: "region",
    },
  });
  const engine = createStylistOneBrainEngineV2({sessionRepository: repository, ...ports, clock: () => NOW});

  const first = await engine.resolveTurn({
    uid: "u1",
    request: request({
      chatId: "chat_alps",
      turnId: "t1",
      revision: 0,
      message: "zajtra chcem ísť do Rakúska na túru potrebujem outfit",
    }),
    bootstrapInput: {
      currentOutfitItemIds: [],
      persistedSelectionReasonsByItemId: {},
      knownExplicitDurableChoices: {},
    },
  });
  assert.equal(first.action, "clarify");
  assert.equal(first.clarification.field, "destination");

  const second = await engine.resolveTurn({
    uid: "u1",
    request: request({chatId: "chat_alps", turnId: "t2", revision: 1, message: "do Álp"}),
  });
  assert.equal(second.action, "generate_outfit");
  assert.deepEqual(second.resultingOutfit.itemIds, ["tee", "pants", "shoes"]);
  assert.equal(calls.location, 1);
  assert.equal(calls.weather, 1);
  assert.equal(calls.wardrobe, 1);

  const secondTurnInputs = calls.brainInputs.slice(1);
  assert.equal(secondTurnInputs.length, 2);
  assert.equal(secondTurnInputs[0].stage, "tools");
  assert.equal(secondTurnInputs[0].runtimeConstraints.allowClarification, true);
  assert.equal(secondTurnInputs[0].runtimeConstraints.pendingReplyRequired, true);
  assert.equal(secondTurnInputs[1].stage, "answer");
  assert.equal(secondTurnInputs[1].runtimeConstraints.allowClarification, false);
  assert.equal(scripts.length, 0);
});

test("One Brain: country-level hike is narrowed deterministically before the answer stage", async () => {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  const calls = {brainInputs: []};
  const brain = {
    async brainTurn(input) {
      calls.brainInputs.push(JSON.parse(JSON.stringify(input)));
      return {
        kind: "tool_request",
        statePatch: {
          context: {
            activity: {id: "hiking", label: "turistika", source: "user"},
            date: {dateKey: "2026-09-17", source: "user"},
            timeWindow: {key: "day", label: "cez deň", source: "one_brain_default"},
            environment: "outdoor",
            groundingRequirements: {
              weatherRequired: true,
              weatherLocationField: "destination",
              terrainRequiredFields: [],
            },
          },
        },
        requests: [
          {tool: "location", query: "Rakúsko", targetField: "destination"},
          {tool: "wardrobe", scope: "full_relevant", category: null, editScope: null},
        ],
      };
    },
  };
  const ports = fakePorts({
    brain,
    calls,
    location: {
      providerId: "openmeteo:austria",
      label: "Rakúsko",
      lat: 47.5,
      lng: 14.5,
      source: "fake-location",
      granularity: "country",
    },
  });
  const engine = createStylistOneBrainEngineV2({sessionRepository: repository, ...ports, clock: () => NOW});
  const result = await engine.resolveTurn({
    uid: "u_country",
    request: request({
      chatId: "chat_country_hike",
      turnId: "t1",
      revision: 0,
      message: "budúci štvrtok ideme do Rakúska na turistiku a neviem čo si mám obliecť",
    }),
    bootstrapInput: {
      currentOutfitItemIds: [],
      persistedSelectionReasonsByItemId: {},
      knownExplicitDurableChoices: {},
    },
  });
  assert.equal(result.action, "clarify");
  assert.equal(result.clarification.field, "destination");
  assert.match(result.assistantText, /dosť široké/);
  assert.match(result.assistantText, /Kam približne/);
  assert.equal(calls.location, 1);
  assert.equal(calls.wardrobe, 1);
  assert.equal(calls.weather || 0, 0);
  assert.equal(calls.brainInputs.length, 1, "broad country must not spend the answer-stage model call");
});

test("One Brain: neviem permanently consumes the pending field for that continuation", async () => {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  const calls = {brainInputs: []};
  const scripts = [
    {
      kind: "final",
      statePatch: {
        context: {
          activity: {id: "hiking", label: "túra", source: "user"},
          date: {dateKey: "2026-09-11", source: "user"},
          groundingRequirements: {
            weatherRequired: true,
            weatherLocationField: "destination",
            terrainRequiredFields: [],
          },
        },
      },
      result: {
        action: "clarify",
        assistantText: "Kam približne ideš?",
        clarification: {
          field: "destination",
          question: "Kam približne ideš?",
          actionId: "clarify_destination",
        },
        display: {kind: "none", itemIds: []},
      },
    },
    {
      kind: "tool_request",
      statePatch: {
        context: {
          groundingRequirements: {
            weatherRequired: false,
            weatherLocationField: null,
            terrainRequiredFields: [],
          },
        },
      },
      requests: [
        {tool: "wardrobe", scope: "full_relevant", category: null, editScope: null},
      ],
    },
    {
      kind: "final",
      statePatch: {},
      result: {
        action: "generate_outfit",
        assistantText: "Dám ti najpraktickejší turistický outfit z toho, čo máš, bez ďalšieho vypytovania.",
        resultingOutfit: {
          itemIds: ["tee", "pants", "shoes"],
          selectionReasonsByItemId: {
            tee: "ľahká vrstva",
            pants: "praktické nohavice",
            shoes: "najpraktickejšia dostupná obuv",
          },
          compromises: [],
          missingWardrobeNeeds: [],
        },
        display: {kind: "outfit", itemIds: ["tee", "pants", "shoes"]},
      },
    },
  ];
  const brain = {
    async brainTurn(input) {
      calls.brainInputs.push(JSON.parse(JSON.stringify(input)));
      return scripts.shift();
    },
  };
  const ports = fakePorts({brain, calls});
  const engine = createStylistOneBrainEngineV2({sessionRepository: repository, ...ports, clock: () => NOW});

  await engine.resolveTurn({
    uid: "u2",
    request: request({chatId: "chat_skip", turnId: "s1", revision: 0, message: "zajtra túra, potrebujem outfit"}),
    bootstrapInput: {currentOutfitItemIds: [], persistedSelectionReasonsByItemId: {}, knownExplicitDurableChoices: {}},
  });
  const result = await engine.resolveTurn({
    uid: "u2",
    request: request({chatId: "chat_skip", turnId: "s2", revision: 1, message: "neviem"}),
  });

  assert.equal(result.action, "generate_outfit");
  assert.equal(calls.location || 0, 0);
  const input = calls.brainInputs[1];
  assert.equal(input.runtimeConstraints.allowClarification, false);
  assert.ok(input.runtimeConstraints.cannotClarifyFields.includes("destination"));
  const stored = await repository.get({uid: "u2", chatId: "chat_skip"});
  assert.equal(stored.state.conversationMemory.answeredClarificationFields.destination.status, "unknown");
  assert.equal(stored.state.conversationMemory.pendingQuestion, null);
});

test("One Brain: final answer stage is structurally forbidden from asking another question", async () => {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  const scripts = [
    {
      kind: "tool_request",
      statePatch: {},
      requests: [{tool: "wardrobe", scope: "full_relevant", category: null, editScope: null}],
    },
    {
      kind: "final",
      statePatch: {},
      result: {
        action: "clarify",
        assistantText: "Po akom povrchu pôjdeš?",
        clarification: {
          field: "terrain.surface",
          question: "Po akom povrchu pôjdeš?",
          actionId: "clarify_terrain_surface",
        },
        display: {kind: "none", itemIds: []},
      },
    },
  ];
  const ports = fakePorts({brain: {async brainTurn() { return scripts.shift(); }}});
  const engine = createStylistOneBrainEngineV2({sessionRepository: repository, ...ports, clock: () => NOW});

  await assert.rejects(() => engine.resolveTurn({
    uid: "u3",
    request: request({chatId: "chat_no_loop", turnId: "x1", revision: 0, message: "daj mi outfit na túru"}),
    bootstrapInput: {currentOutfitItemIds: [], persistedSelectionReasonsByItemId: {}, knownExplicitDurableChoices: {}},
  }), (error) => error instanceof RepairableStructuralTurnError && /cannot start another questionnaire/.test(error.message));
});

test("production One-Brain bridge uses one substantive Brain and never creates fast-chat routing", async () => {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  let brainCalls = 0;
  const handler = createStylistChatV2Handler({
    db: {},
    admin: {},
    logger: {warn() {}, info() {}},
    resolveOpenAISecret: async () => "unused",
    clock: () => NOW,
    sessionRepository: repository,
    brainFactory: () => ({
      async brainTurn(input) {
        brainCalls += 1;
        assert.equal(input.stage, "tools");
        return {
          kind: "final",
          statePatch: {},
          result: {
            action: "chat",
            assistantText: "K modrej sa hodí biela, sivá aj béžová.",
            display: {kind: "none", itemIds: []},
          },
        };
      },
    }),
    wardrobeToolFactory: () => ({
      async retrieve() { throw new Error("wardrobe_must_not_run"); },
      async materialize() { return []; },
    }),
    locationResolver: {async resolve() { throw new Error("location_must_not_run"); }},
    weatherTool: {async getForecast() { throw new Error("weather_must_not_run"); }},
    shoppingToolFactory: () => ({async search() { throw new Error("shopping_must_not_run"); }}),
  });

  const response = await handler({
    v2SessionId: "one_brain_chat",
    turnId: "one_1",
    message: "Aké farby sa hodia k modrej?",
    history: [],
    currentOutfitItemIds: [],
    currentSelectionReasons: [],
    shoppingEnabled: false,
    clientContext: {},
  }, {auth: {uid: "u4"}});

  assert.equal(response.ok, true);
  assert.equal(response.modelPath, "stylist_v2_one_brain");
  assert.equal(response.action, "chat");
  assert.equal(brainCalls, 1);
});


function pendingDestinationClarifyEnvelope() {
  return {
    kind: "final",
    statePatch: {
      context: {
        activity: {id: "hiking", label: "túra", source: "user"},
        date: {dateKey: "2026-09-11", source: "user"},
        groundingRequirements: {weatherRequired: true, weatherLocationField: "destination", terrainRequiredFields: []},
      },
    },
    result: {
      action: "clarify",
      assistantText: "Kam približne ideš?",
      clarification: {field: "destination", question: "Kam približne ideš?", actionId: "clarify_destination"},
      display: {kind: "none", itemIds: []},
    },
  };
}

function wardrobeToolRequestEnvelope(disposition = "none") {
  return {
    kind: "tool_request",
    pendingReplyDisposition: disposition,
    statePatch: {context: {groundingRequirements: {weatherRequired: false, weatherLocationField: null, terrainRequiredFields: []}}},
    requests: [{tool: "wardrobe", scope: "full_relevant", category: null, editScope: null}],
  };
}

function simpleOutfitEnvelope() {
  return {
    kind: "final",
    statePatch: {},
    result: {
      action: "generate_outfit",
      assistantText: "Vybral som najpraktickejší outfit z tvojho šatníka.",
      resultingOutfit: {
        itemIds: ["tee", "pants", "shoes"],
        selectionReasonsByItemId: {tee: "vrch", pants: "spodok", shoes: "obuv"},
        compromises: [],
        missingWardrobeNeeds: [],
      },
      display: {kind: "outfit", itemIds: ["tee", "pants", "shoes"]},
    },
  };
}

test("One Brain: 'nechaj tak' can never be consumed as a pending destination", async () => {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  const calls = {brainInputs: []};
  const scripts = [pendingDestinationClarifyEnvelope(), wardrobeToolRequestEnvelope("none"), simpleOutfitEnvelope()];
  const ports = fakePorts({
    calls,
    brain: {async brainTurn(input) { calls.brainInputs.push(JSON.parse(JSON.stringify(input))); return scripts.shift(); }},
  });
  const engine = createStylistOneBrainEngineV2({sessionRepository: repository, ...ports, clock: () => NOW});
  await engine.resolveTurn({
    uid: "u_skip_phrase",
    request: request({chatId: "skip_phrase", turnId: "p1", revision: 0, message: "zajtra túra, potrebujem outfit"}),
    bootstrapInput: {currentOutfitItemIds: [], persistedSelectionReasonsByItemId: {}, knownExplicitDurableChoices: {}},
  });
  const result = await engine.resolveTurn({
    uid: "u_skip_phrase",
    request: request({chatId: "skip_phrase", turnId: "p2", revision: 1, message: "nechaj tak"}),
  });
  assert.equal(result.action, "generate_outfit");
  assert.equal(calls.location || 0, 0);
  assert.equal(calls.brainInputs[1].runtimeConstraints.pendingReplyRequired, false);
  const stored = await repository.get({uid: "u_skip_phrase", chatId: "skip_phrase"});
  assert.equal(stored.state.conversationMemory.answeredClarificationFields.destination.status, "unknown");
  assert.equal(stored.state.context.destination, null);
});

test("One Brain: a meta question preserves the pending destination and never geocodes the meta text", async () => {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  const calls = {brainInputs: []};
  const scripts = [
    pendingDestinationClarifyEnvelope(),
    {
      kind: "final",
      pendingReplyDisposition: "meta",
      statePatch: {scenarioMode: "current"},
      result: {action: "chat", assistantText: "Kvôli počasiu v oblasti, aby som vedel lepšie zvoliť vrstvy.", display: {kind: "none", itemIds: []}},
    },
  ];
  const ports = fakePorts({
    calls,
    brain: {async brainTurn(input) { calls.brainInputs.push(JSON.parse(JSON.stringify(input))); return scripts.shift(); }},
  });
  const engine = createStylistOneBrainEngineV2({sessionRepository: repository, ...ports, clock: () => NOW});
  await engine.resolveTurn({
    uid: "u_meta",
    request: request({chatId: "meta", turnId: "m1", revision: 0, message: "zajtra túra, potrebujem outfit"}),
    bootstrapInput: {currentOutfitItemIds: [], persistedSelectionReasonsByItemId: {}, knownExplicitDurableChoices: {}},
  });
  const result = await engine.resolveTurn({
    uid: "u_meta",
    request: request({chatId: "meta", turnId: "m2", revision: 1, message: "načo ti to je?"}),
  });
  assert.equal(result.action, "chat");
  assert.equal(calls.location || 0, 0);
  const stored = await repository.get({uid: "u_meta", chatId: "meta"});
  assert.equal(stored.state.conversationMemory.pendingQuestion.field, "destination");
  assert.equal(stored.state.context.destination, null);
});

test("One Brain: unrelated topic abandons the old pending field instead of treating new text as its value", async () => {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  const calls = {brainInputs: []};
  const scripts = [
    pendingDestinationClarifyEnvelope(),
    {
      kind: "final",
      pendingReplyDisposition: "unrelated",
      statePatch: {scenarioMode: "new"},
      result: {action: "chat", assistantText: "K modrej sa hodí biela, sivá aj béžová.", display: {kind: "none", itemIds: []}},
    },
  ];
  const ports = fakePorts({
    calls,
    brain: {async brainTurn(input) { calls.brainInputs.push(JSON.parse(JSON.stringify(input))); return scripts.shift(); }},
  });
  const engine = createStylistOneBrainEngineV2({sessionRepository: repository, ...ports, clock: () => NOW});
  await engine.resolveTurn({
    uid: "u_topic",
    request: request({chatId: "topic", turnId: "q1", revision: 0, message: "zajtra túra, potrebujem outfit"}),
    bootstrapInput: {currentOutfitItemIds: [], persistedSelectionReasonsByItemId: {}, knownExplicitDurableChoices: {}},
  });
  const result = await engine.resolveTurn({
    uid: "u_topic",
    request: request({chatId: "topic", turnId: "q2", revision: 1, message: "inak aká farba sa hodí k modrej?"}),
  });
  assert.equal(result.action, "chat");
  assert.equal(calls.location || 0, 0);
  const stored = await repository.get({uid: "u_topic", chatId: "topic"});
  assert.equal(stored.state.conversationMemory.pendingQuestion, null);
  assert.equal(stored.state.context.destination, null);
});

test("One Brain: classified destination answer may resolve the pending location but cannot ask a second continuation question", async () => {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  const calls = {brainInputs: []};
  const scripts = [
    pendingDestinationClarifyEnvelope(),
    {
      kind: "tool_request",
      pendingReplyDisposition: "answer",
      statePatch: {context: {groundingRequirements: {weatherRequired: true, weatherLocationField: "destination", terrainRequiredFields: []}}},
      requests: [
        {tool: "location", query: "Alpy, Rakúsko", targetField: "destination"},
        {tool: "wardrobe", scope: "full_relevant", category: null, editScope: null},
      ],
    },
    simpleOutfitEnvelope(),
  ];
  const ports = fakePorts({
    calls,
    location: {providerId: "openmeteo:alps", label: "Alpy, Rakúsko", lat: 47.2, lng: 12.2, source: "test", granularity: "region"},
    brain: {async brainTurn(input) { calls.brainInputs.push(JSON.parse(JSON.stringify(input))); return scripts.shift(); }},
  });
  const engine = createStylistOneBrainEngineV2({sessionRepository: repository, ...ports, clock: () => NOW});
  await engine.resolveTurn({
    uid: "u_answer",
    request: request({chatId: "answer", turnId: "a1", revision: 0, message: "zajtra túra, potrebujem outfit"}),
    bootstrapInput: {currentOutfitItemIds: [], persistedSelectionReasonsByItemId: {}, knownExplicitDurableChoices: {}},
  });
  const result = await engine.resolveTurn({
    uid: "u_answer",
    request: request({chatId: "answer", turnId: "a2", revision: 1, message: "do Álp"}),
  });
  assert.equal(result.action, "generate_outfit");
  assert.equal(calls.location, 1);
  assert.equal(calls.lastLocationQuery, "Alpy, Rakúsko");
  assert.equal(calls.brainInputs[1].runtimeConstraints.pendingReplyRequired, true);
  assert.equal(calls.brainInputs[2].runtimeConstraints.allowClarification, false);
});

test("One Brain model contract classifies pending replies and uses Terra medium", async () => {
  const specs = [];
  const brain = createOpenAiOneBrainModelPortV2({
    executeStructured: async (spec) => {
      specs.push(spec);
      return {
        kind: "final",
        action: "chat",
        assistantText: "Jasné.",
        pendingReplyDisposition: "unrelated",
        clarificationField: null,
        clarificationQuestion: null,
        scenarioMode: "new",
        scenarioReferenceId: null,
        locationQuery: null,
        locationTargetField: "none",
        wardrobeScope: "none",
        wardrobeCategory: null,
        replaceItemIds: [], retainItemIds: [], allowedSlots: [], allowedCategories: [], allowRemovalOnly: false,
        patch: {
          activityId: null, activityLabel: null, dateKey: null, timeWindowKey: null,
          environment: "unknown", terrainSurface: "unknown", terrainDifficulty: "unknown", terrainCondition: "unknown",
          replaceGroundingRequirements: false, weatherRequired: false, weatherLocationField: "none", terrainRequiredFields: [],
        },
      };
    },
  });
  const envelope = await brain.brainTurn({
    stage: "tools",
    request: {chatId: "c", turnId: "t", latestUserInput: "niečo iné", explicitUiActionId: null, clientCapabilities: {}},
    session: {context: {}, currentOutfit: {itemIds: [], selectionReasonsByItemId: {}}, conversationMemory: {pendingQuestion: {field: "destination"}}},
    toolResults: {wardrobeItems: []},
    runtimeConstraints: {allowClarification: true, pendingReplyRequired: true, pendingReplyField: "destination"},
  });
  assert.equal(specs.length, 1);
  assert.equal(specs[0].model, "gpt-5.6-terra");
  assert.equal(specs[0].reasoningEffort, "medium");
  assert.ok(specs[0].schema.required.includes("pendingReplyDisposition"));
  assert.deepEqual(specs[0].schema.properties.pendingReplyDisposition.enum, ["none", "answer", "skip", "meta", "unrelated"]);
  const systemPrompt = specs[0].messages[0].content;
  assert.match(systemPrompt, /priateľský profesionál/);
  assert.match(systemPrompt, /nezačínaj holým rozkazom/);
  assert.match(systemPrompt, /Emoji používaj striedmo/);
  assert.match(systemPrompt, /silno pokazený alebo preklepový/);
  assert.equal(envelope.pendingReplyDisposition, "unrelated");
});

test("shopping need is the authoritative CTA signal even if offerShopping is false", () => {
  const envelope = finalEnvelope({
    action: "generate_outfit",
    assistantText: "Tenisky sú tu najlepší dostupný kompromis.",
    resultingOutfitItemIds: ["tee", "pants", "shoes"],
    selectionReasons: [
      {itemId: "tee", reason: "vrch"},
      {itemId: "pants", reason: "spodok"},
      {itemId: "shoes", reason: "obuv"},
    ],
    displayKind: "outfit",
    displayItemIds: ["tee", "pants", "shoes"],
    editReplaceItemIds: [], editRetainItemIds: [], editAllowedSlots: [], editAllowedCategories: [], editAllowRemovalOnly: false,
    clarificationField: null, clarificationQuestion: null,
    offerShopping: false,
    shoppingNeedLabel: "turistická obuv",
    shoppingNeedCanonicalType: "hiking_shoes",
    shoppingHardConstraints: [], shoppingSoftPreferences: [],
  }, {
    request: {turnId: "cta_1"},
    session: {context: {environment: "outdoor"}, currentOutfit: {itemIds: [], selectionReasonsByItemId: {}}},
    toolResults: {},
  });
  assert.equal(envelope.result.quickReplies.length, 2);
  assert.deepEqual(envelope.result.quickReplies.map((entry) => entry.label), ["Áno", "Nie"]);
  assert.equal(envelope.statePatch.shopping.missingNeed.label, "turistická obuv");
});

test("preloaded full wardrobe is visible to the Brain and reused without another read", async () => {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  const calls = {brainInputs: [], wardrobe: 0};
  const items = wardrobeItems();
  const ports = fakePorts({
    calls,
    brain: {
      async brainTurn(input) {
        calls.brainInputs.push(JSON.parse(JSON.stringify(input)));
        return {kind: "final", pendingReplyDisposition: "none", statePatch: {}, result: {action: "chat", assistantText: "Vidím celý šatník.", display: {kind: "none", itemIds: []}}};
      },
    },
  });
  const engine = createStylistOneBrainEngineV2({sessionRepository: repository, ...ports, clock: () => NOW});
  const result = await engine.resolveTurn({
    uid: "u_preload",
    request: request({chatId: "preload", turnId: "w1", revision: 0, message: "daj mi iné tričko"}),
    bootstrapInput: {currentOutfitItemIds: [], persistedSelectionReasonsByItemId: {}, knownExplicitDurableChoices: {}},
    knownWardrobeItems: items,
  });
  assert.equal(result.action, "chat");
  assert.equal(calls.wardrobe, 0);
  assert.deepEqual(calls.brainInputs[0].toolResults.wardrobeItems.map((item) => item.id), ["tee", "pants", "shoes"]);
});

test("production Firebase entrypoint is wired to the One-Brain bridge", () => {
  const source = fs.readFileSync(path.join(__dirname, "..", "..", "index_v2.js"), "utf8");
  assert.match(source, /stylist_production_bridge_one_brain_v2/);
  assert.doesNotMatch(source, /require\("\.\/stylist\/v2\/stylist_production_bridge_v2"\)/);
});
