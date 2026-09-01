"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  SIMPLE_AGENT_MODEL,
  SIMPLE_AGENT_REASONING_EFFORT,
  createSimpleStylistAgentV1,
  createOpenAiSimpleAgentExecutorV1,
  normalizeRequestV1,
  validateAgentResultV1,
} = require("./simple_stylist_agent_v1");

function item({
  id,
  name,
  type,
  family,
  slots,
  layer = "base",
  color,
  accents = [],
  warmth = 4,
  functions = [],
  occasionFit = [],
}) {
  return {
    id,
    name,
    ontologyVersion: "2.0.0",
    canonicalType: type,
    canonicalFamily: family,
    bodySlots: slots,
    layerPosition: layer,
    colorProfile: {
      primary: {family: color, proportion: 0.9},
      secondary: null,
      accents: accents.map((accent) => ({family: accent, proportion: 0.05})),
    },
    warmth,
    formality: 4,
    outfitFunctions: functions,
    occasionFit,
    seasons: ["spring", "summer", "autumn"],
    imageUrl: `https://example.test/${id}.png`,
  };
}

const wardrobe = [
  item({id: "blue-top", name: "modré tričko", type: "t_shirt", family: "tops", slots: ["upper_body"], color: "blue"}),
  item({id: "black-top", name: "čierna košeľa", type: "shirt", family: "tops", slots: ["upper_body"], color: "black"}),
  item({id: "jeans", name: "modré rifle", type: "jeans", family: "bottoms", slots: ["lower_body"], color: "blue"}),
  item({id: "shorts", name: "krátke čierne nohavice", type: "casual_shorts", family: "bottoms", slots: ["lower_body"], color: "black", occasionFit: []}),
  item({id: "trousers", name: "béžové nohavice", type: "trousers", family: "bottoms", slots: ["lower_body"], color: "beige", occasionFit: ["imperfect_unknown"]}),
  item({id: "white-shoes", name: "biele tenisky", type: "sneakers", family: "footwear", slots: ["feet"], layer: "outer", color: "white", accents: ["red"]}),
  item({id: "red-shoes", name: "červené tenisky", type: "sneakers", family: "footwear", slots: ["feet"], layer: "outer", color: "red"}),
  item({id: "hoodie", name: "sivá mikina", type: "hoodie", family: "layers", slots: ["upper_body"], layer: "mid", color: "gray", warmth: 6}),
];

function request(message, currentOutfitItemIds = [], history = []) {
  return {
    message,
    history,
    currentOutfitItemIds,
    wardrobeItems: wardrobe,
    weatherContext: {
      location: "Bratislava",
      today: {noonTempC: 22, willRain: false},
      tomorrow: {noonTempC: 20, willRain: false},
    },
    clientContext: {
      todayDateKey: "2026-09-01",
      tomorrowDateKey: "2026-09-02",
      userGpsLocation: "Bratislava",
    },
    eventContext: {event: "von"},
    preferences: {preferredStyles: ["casual"]},
  };
}

function queuedAgent(results, logs = []) {
  const inputs = [];
  const agent = createSimpleStylistAgentV1({
    executeModel: async (input) => {
      inputs.push(input);
      return {
        weatherContextKey: "current",
        commentGroundingEvidence: [],
        ...results.shift(),
      };
    },
    logger: {
      info: (marker, details) => logs.push({marker, details}),
      warn: (marker, details) => logs.push({marker, details}),
    },
  });
  return {agent, inputs};
}

test("required conversational flow preserves exact IDs across sequential turns", async () => {
  const history = [];
  const outputs = [
    {
      stylistComment: "Ahoj, jasné — zajtra to spolu doladíme.",
      resultingOutfitItemIds: [],
      displayItemIds: [],
      outfitChanged: false,
      outfitRequested: false,
      hardRequirementEvidence: [],
    },
    {
      stylistComment: "Toto je príjemná ležérna kombinácia, ktorá bude zajtra fungovať veľmi dobre.",
      resultingOutfitItemIds: ["blue-top", "jeans", "white-shoes"],
      displayItemIds: ["blue-top", "jeans", "white-shoes"],
      outfitChanged: true,
      outfitRequested: true,
      hardRequirementEvidence: [],
    },
    {
      stylistComment: "Skúsil by som tieto čierne šortky — k tričku a teniskám fungujú veľmi dobre.",
      resultingOutfitItemIds: ["blue-top", "shorts", "white-shoes"],
      displayItemIds: ["shorts"],
      outfitChanged: true,
      outfitRequested: true,
      hardRequirementEvidence: [
        {itemId: "shorts", field: "canonicalType", expectedValue: "casual_shorts"},
      ],
    },
    {
      stylistComment: "Táto sivá mikina by k tomu podľa mňa sadla super. 🙂",
      resultingOutfitItemIds: ["blue-top", "shorts", "white-shoes", "hoodie"],
      displayItemIds: ["blue-top", "shorts", "white-shoes", "hoodie"],
      outfitChanged: true,
      outfitRequested: true,
      hardRequirementEvidence: [
        {itemId: "hoodie", field: "canonicalType", expectedValue: "hoodie"},
      ],
    },
  ];
  const {agent, inputs} = queuedAgent(outputs);

  const hello = await agent.resolve(request("ahoj zajtra idem von", [], history));
  assert.deepEqual(hello.resultingOutfitItemIds, []);
  history.push({role: "user", content: "ahoj zajtra idem von"});
  history.push({role: "assistant", content: hello.reply});

  const full = await agent.resolve(request("potrebujem outfit", [], history));
  assert.deepEqual(full.resultingOutfitItemIds, ["blue-top", "jeans", "white-shoes"]);
  assert.deepEqual(full.displayItemIds, full.resultingOutfitItemIds);
  history.push({role: "user", content: "potrebujem outfit"});
  history.push({role: "assistant", content: full.reply});

  const shorts = await agent.resolve(request(
    "radšej by som chcel krátke gate",
    full.resultingOutfitItemIds,
    history,
  ));
  assert.deepEqual(shorts.resultingOutfitItemIds, ["blue-top", "shorts", "white-shoes"]);
  assert.deepEqual(shorts.displayItemIds, ["shorts"]);
  assert.equal(
    shorts.reply,
    "Skúsil by som tieto čierne šortky — k tričku a teniskám fungujú veľmi dobre.",
  );
  history.push({role: "user", content: "radšej by som chcel krátke gate"});
  history.push({role: "assistant", content: shorts.reply});

  const hoodie = await agent.resolve(request(
    "ukáž mi celý outfit a pridaj mi tam aj mikinu",
    shorts.resultingOutfitItemIds,
    history,
  ));
  assert.deepEqual(hoodie.resultingOutfitItemIds, [
    "blue-top", "shorts", "white-shoes", "hoodie",
  ]);
  assert.deepEqual(hoodie.displayItemIds, hoodie.resultingOutfitItemIds);
  assert.equal(hoodie.reply, "Táto sivá mikina by k tomu podľa mňa sadla super. 🙂");
  assert.deepEqual(inputs[3].model, SIMPLE_AGENT_MODEL);
  assert.equal(inputs[3].reasoningEffort, SIMPLE_AGENT_REASONING_EFFORT);
  const modelPayload = JSON.parse(inputs[3].messages[1].content);
  assert.deepEqual(modelPayload.exactCurrentOutfit.itemIds, shorts.resultingOutfitItemIds);
  assert.equal(modelPayload.wardrobeV2.length, wardrobe.length);
  assert.deepEqual(modelPayload.weatherContext.tomorrow.noonTempC, 20);
  assert.deepEqual(modelPayload.relevantPreferences.preferredStyles, ["casual"]);
});

test("one result changes top bottom and shoes and uses dominant red footwear", async () => {
  const {agent} = queuedAgent([{
    stylistComment: "Takto sa mi to páči viac. Červené tenisky tomu dodajú trochu života.",
    resultingOutfitItemIds: ["black-top", "trousers", "red-shoes"],
    displayItemIds: ["black-top", "trousers", "red-shoes"],
    outfitChanged: true,
    outfitRequested: true,
    hardRequirementEvidence: [
      {itemId: "black-top", field: "included", expectedValue: "true"},
      {itemId: "trousers", field: "included", expectedValue: "true"},
      {itemId: "red-shoes", field: "primaryColor", expectedValue: "red"},
    ],
  }]);
  const result = await agent.resolve(request(
    "vymeň vrch, spodok a topánky mi daj tie červené",
    ["blue-top", "jeans", "white-shoes"],
  ));
  assert.deepEqual(result.resultingOutfitItemIds, ["black-top", "trousers", "red-shoes"]);
  assert.equal(result.resultingOutfitItems[2].colorProfile.primary.family, "red");
  assert.notEqual(result.resultingOutfitItemIds[2], "white-shoes");
  assert.equal(
    result.reply,
    "Takto sa mi to páči viac. Červené tenisky tomu dodajú trochu života.",
  );
});

test("only explicit Wardrobe V2 records are exposed to the agent", async () => {
  const legacyLookalike = {
    ...wardrobe[0],
    id: "legacy-lookalike",
  };
  delete legacyLookalike.ontologyVersion;
  const {agent, inputs} = queuedAgent([{
    stylistComment: "Ahoj.",
    resultingOutfitItemIds: [],
    displayItemIds: [],
    outfitChanged: false,
    outfitRequested: false,
    hardRequirementEvidence: [],
  }]);
  await agent.resolve({
    ...request("ahoj"),
    wardrobeItems: [...wardrobe, legacyLookalike],
  });
  const payload = JSON.parse(inputs[0].messages[1].content);
  assert.equal(payload.wardrobeV2.some((entry) => entry.id === "legacy-lookalike"), false);
});

test("context-only planning turns keep an empty current outfit empty and show no cards", async () => {
  const messages = [
    "ahoj večer pôjdem do mesta",
    "zajtra idem von",
    "večer budem v meste",
    "v sobotu idem na oslavu",
    "po práci idem na kávu",
    "idem do lesa",
    "zajtra idem do Michaloviec",
  ];
  for (const message of messages) {
    const logs = [];
    const {agent, inputs} = queuedAgent([{
      stylistComment: "Jasné 🙂 Keď budeš chcieť, môžeme potom doladiť aj outfit.",
      resultingOutfitItemIds: [],
      displayItemIds: [],
      outfitChanged: false,
      outfitRequested: false,
      weatherContextKey: "current",
      hardRequirementEvidence: [],
      commentGroundingEvidence: [],
    }], logs);
    const result = await agent.resolve(request(message));
    assert.equal(inputs.length, 1, message);
    assert.equal(result.outfitRequested, false, message);
    assert.equal(result.outfitChanged, false, message);
    assert.deepEqual(result.resultingOutfitItemIds, [], message);
    assert.deepEqual(result.displayItemIds, [], message);
    assert.equal(logs.some((entry) => entry.marker === "SIMPLE_AGENT_REPAIR"), false);
  }
});

test("validator rejects an unsolicited outfit and cards on a chat-only turn with empty current", () => {
  const normalized = normalizeRequestV1(request("večer budem v meste"));
  const validation = validateAgentResultV1({
    stylistComment: "Večer môže byť príjemne.",
    resultingOutfitItemIds: ["blue-top", "jeans", "white-shoes"],
    displayItemIds: ["blue-top", "jeans", "white-shoes"],
    outfitChanged: true,
    outfitRequested: false,
    weatherContextKey: "current",
    hardRequirementEvidence: [],
    commentGroundingEvidence: [],
  }, normalized);
  assert.equal(validation.valid, false);
  assert.ok(validation.errors.includes("chat_turn_mutated_current_outfit"));
  assert.ok(validation.errors.includes("chat_turn_display_not_empty"));
});

test("invalid ID gets exactly one repair with precise errors and allowed IDs", async () => {
  const logs = [];
  const {agent, inputs} = queuedAgent([
    {
      stylistComment: "Hotovo.",
      resultingOutfitItemIds: ["blue-top", "shorts", "invented-shoes"],
      displayItemIds: ["shorts", "invented-shoes"],
      outfitChanged: true,
      outfitRequested: true,
      hardRequirementEvidence: [],
    },
    {
      stylistComment: "Hotovo.",
      resultingOutfitItemIds: ["blue-top", "shorts", "white-shoes"],
      displayItemIds: ["shorts"],
      outfitChanged: true,
      outfitRequested: true,
      hardRequirementEvidence: [
        {itemId: "shorts", field: "canonicalType", expectedValue: "casual_shorts"},
      ],
    },
  ], logs);
  const result = await agent.resolve(request(
    "radšej by som chcel krátke gate",
    ["blue-top", "jeans", "white-shoes"],
  ));
  assert.equal(inputs.length, 2);
  const repair = JSON.parse(inputs[1].messages[1].content).repair;
  assert.ok(repair.validationErrors.includes("result_item_not_owned:invented-shoes"));
  assert.ok(repair.allowedItemIds.includes("white-shoes"));
  assert.deepEqual(result.displayItemIds, ["shorts"]);
  assert.equal(logs.filter((entry) => entry.marker === "SIMPLE_AGENT_REPAIR").length, 1);
});

test("hard red evidence rejects white footwear with a red accent", async () => {
  const {agent, inputs} = queuedAgent([
    {
      stylistComment: "Hotovo.",
      resultingOutfitItemIds: ["black-top", "trousers", "white-shoes"],
      displayItemIds: ["black-top", "trousers", "white-shoes"],
      outfitChanged: true,
      outfitRequested: true,
      hardRequirementEvidence: [
        {itemId: "white-shoes", field: "primaryColor", expectedValue: "red"},
      ],
    },
    {
      stylistComment: "Hotovo.",
      resultingOutfitItemIds: ["black-top", "trousers", "red-shoes"],
      displayItemIds: ["black-top", "trousers", "red-shoes"],
      outfitChanged: true,
      outfitRequested: true,
      hardRequirementEvidence: [
        {itemId: "red-shoes", field: "primaryColor", expectedValue: "red"},
      ],
    },
  ]);
  const result = await agent.resolve(request(
    "vymeň vrch, spodok a topánky mi daj tie červené",
    ["blue-top", "jeans", "white-shoes"],
  ));
  assert.equal(inputs.length, 2);
  const repair = JSON.parse(inputs[1].messages[1].content).repair;
  assert.ok(repair.validationErrors.includes(
    "hard_requirement_not_satisfied:white-shoes:primaryColor:red",
  ));
  assert.equal(result.resultingOutfitItemIds[2], "red-shoes");
});

test("descriptive included evidence validates an added real wardrobe layer", async () => {
  const logs = [];
  const {agent, inputs} = queuedAgent([{
    stylistComment: "Čo povieš na túto sivú mikinu? K zvyšku mi sedí veľmi dobre.",
    resultingOutfitItemIds: ["blue-top", "shorts", "white-shoes", "hoodie"],
    displayItemIds: ["blue-top", "shorts", "white-shoes", "hoodie"],
    outfitChanged: true,
    outfitRequested: true,
    hardRequirementEvidence: [
      {itemId: "hoodie", field: "included", expectedValue: "mikina"},
    ],
  }], logs);

  const result = await agent.resolve(request(
    "ukáž mi celý outfit a pridaj mi tam aj mikinu",
    ["blue-top", "shorts", "white-shoes"],
  ));

  assert.equal(inputs.length, 1);
  assert.deepEqual(result.resultingOutfitItemIds, [
    "blue-top", "shorts", "white-shoes", "hoodie",
  ]);
  assert.deepEqual(result.displayItemIds, result.resultingOutfitItemIds);
  assert.equal(logs.some((entry) => entry.marker === "SIMPLE_AGENT_REPAIR"), false);
  assert.equal(
    result.stylistComment,
    "Čo povieš na túto sivú mikinu? K zvyšku mi sedí veľmi dobre.",
  );
});

test("validated Sol comment is the default user-facing reply for every edit shape", async () => {
  const cases = [
    {
      message: "radšej kraťasy",
      comment: "Tieto čierne šortky tomu dodajú ľahší, uvoľnenejší charakter.",
      resultIds: ["blue-top", "shorts", "white-shoes"],
      displayIds: ["shorts"],
    },
    {
      message: "pridaj mikinu",
      comment: "Sivá mikina to príjemne zjemní a na chladnejší večer je akurát.",
      resultIds: ["blue-top", "jeans", "white-shoes", "hoodie"],
      displayIds: ["hoodie"],
    },
    {
      message: "skús niečo úplne iné",
      comment: "Táto verzia pôsobí čistejšie a o niečo výraznejšie. Za mňa veľmi dobrý smer.",
      resultIds: ["black-top", "trousers", "red-shoes"],
      displayIds: ["black-top", "trousers", "red-shoes"],
    },
  ];

  for (const scenario of cases) {
    const {agent} = queuedAgent([{
      stylistComment: scenario.comment,
      resultingOutfitItemIds: scenario.resultIds,
      displayItemIds: scenario.displayIds,
      outfitChanged: true,
      outfitRequested: true,
      hardRequirementEvidence: [],
    }]);
    const result = await agent.resolve(request(
      scenario.message,
      ["blue-top", "jeans", "white-shoes"],
    ));
    assert.equal(result.reply, scenario.comment);
    assert.equal(result.stylistComment, scenario.comment);
    assert.doesNotMatch(result.reply, /Upravil som outfit|Zvyšok outfitu zostáva/);
  }
});

test("missing optional model comment uses a generic non-audit fallback", async () => {
  const {agent, inputs} = queuedAgent([{
    stylistComment: "",
    resultingOutfitItemIds: ["blue-top", "shorts", "white-shoes"],
    displayItemIds: ["shorts"],
    outfitChanged: true,
    outfitRequested: true,
    hardRequirementEvidence: [],
  }]);

  const result = await agent.resolve(request(
    "radšej kraťasy",
    ["blue-top", "jeans", "white-shoes"],
  ));

  assert.equal(inputs.length, 1);
  assert.equal(
    result.reply,
    "Čo povieš na túto verziu? Podľa mňa spolu funguje veľmi dobre.",
  );
  assert.doesNotMatch(result.reply, /Pridal som|Vymenil som|vyradil|zostáva/);
});

test("wrong comment color evidence gets one repair before reaching the user", async () => {
  const logs = [];
  const {agent, inputs} = queuedAgent([
    {
      stylistComment: "Skúsme sivé džínsové šortky, pôsobia ľahšie.",
      resultingOutfitItemIds: ["blue-top", "shorts", "white-shoes"],
      displayItemIds: ["blue-top", "shorts", "white-shoes"],
      outfitChanged: true,
      outfitRequested: true,
      hardRequirementEvidence: [],
      commentGroundingEvidence: [
        {itemId: "shorts", field: "primaryColor", expectedValue: "gray"},
      ],
    },
    {
      stylistComment: "Čierne šortky udržia outfit čistý a pritom príjemne uvoľnený.",
      resultingOutfitItemIds: ["blue-top", "shorts", "white-shoes"],
      displayItemIds: ["blue-top", "shorts", "white-shoes"],
      outfitChanged: true,
      outfitRequested: true,
      hardRequirementEvidence: [],
      commentGroundingEvidence: [
        {itemId: "shorts", field: "included", expectedValue: "true"},
        {itemId: "shorts", field: "primaryColor", expectedValue: "black"},
      ],
    },
  ], logs);

  const result = await agent.resolve(request(
    "toto sa mi nepáči, skús niečo iné",
    ["black-top", "jeans", "red-shoes"],
  ));

  assert.equal(inputs.length, 2);
  assert.equal(
    result.reply,
    "Čierne šortky udržia outfit čistý a pritom príjemne uvoľnený.",
  );
  const repair = JSON.parse(inputs[1].messages[1].content).repair;
  assert.ok(repair.validationErrors.includes(
    "comment_grounding_not_satisfied:shorts:primaryColor:gray",
  ));
  assert.equal(logs.filter((entry) => entry.marker === "SIMPLE_AGENT_REPAIR").length, 1);
});

test("comment evidence cannot refer to a wardrobe item outside the result", () => {
  const normalized = normalizeRequestV1(request(
    "čo povieš na túto mikinu?",
    ["blue-top", "jeans", "white-shoes"],
  ));
  const validation = validateAgentResultV1({
    stylistComment: "Sivá mikina by sa sem hodila.",
    resultingOutfitItemIds: ["blue-top", "jeans", "white-shoes"],
    displayItemIds: [],
    outfitChanged: false,
    outfitRequested: true,
    weatherContextKey: "current",
    hardRequirementEvidence: [],
    commentGroundingEvidence: [
      {itemId: "hoodie", field: "included", expectedValue: "true"},
    ],
  }, normalized);

  assert.equal(validation.valid, false);
  assert.ok(validation.errors.includes("comment_grounding_item_not_in_result:hoodie"));
});

test("second invalid result fails closed and never invokes a third call", async () => {
  const logs = [];
  const invalid = {
    stylistComment: "Hotovo.",
    resultingOutfitItemIds: ["invented"],
    displayItemIds: ["invented"],
    outfitChanged: true,
    outfitRequested: true,
    hardRequirementEvidence: [],
  };
  const {agent, inputs} = queuedAgent([{...invalid}, {...invalid}], logs);
  await assert.rejects(
    agent.resolve(request("potrebujem outfit")),
    /simple_agent_validation_failed/,
  );
  assert.equal(inputs.length, 2);
  assert.equal(logs.filter((entry) => entry.marker === "SIMPLE_AGENT_FAIL_CLOSED").length, 1);
});

test("hard structure and safety validation reject incomplete and unsafe outfits", async () => {
  const unsafeWardrobe = wardrobe.concat([
    item({id: "slides", name: "šľapky", type: "slides", family: "footwear", slots: ["feet"], layer: "outer", color: "black"}),
  ]);
  const {agent, inputs} = queuedAgent([
    {
      stylistComment: "Hotovo.",
      resultingOutfitItemIds: ["blue-top", "jeans", "slides"],
      displayItemIds: ["blue-top", "jeans", "slides"],
      outfitChanged: true,
      outfitRequested: true,
      hardRequirementEvidence: [
        {itemId: "slides", field: "included", expectedValue: "true"},
      ],
    },
    {
      stylistComment: "Hotovo.",
      resultingOutfitItemIds: ["blue-top", "jeans", "white-shoes"],
      displayItemIds: ["blue-top", "jeans", "white-shoes"],
      outfitChanged: true,
      outfitRequested: true,
      hardRequirementEvidence: [],
    },
  ]);
  const result = await agent.resolve({
    ...request("potrebujem outfit"),
    wardrobeItems: unsafeWardrobe,
    weatherContext: {wetGroundRisk: true},
  });
  assert.equal(inputs.length, 2);
  assert.deepEqual(result.resultingOutfitItemIds, ["blue-top", "jeans", "white-shoes"]);
});

test("validator rejects duplicate, detached display, conflicting slots and skin base", () => {
  const skinBase = item({
    id: "skin-base",
    name: "spodná vrstva",
    type: "base_layer_top",
    family: "base_layers",
    slots: ["upper_body"],
    layer: "skin_base",
    color: "black",
  });
  const normalized = normalizeRequestV1({
    ...request("potrebujem outfit"),
    wardrobeItems: [...wardrobe, skinBase],
  });
  const raw = (resultIds, displayIds = resultIds) => ({
    stylistComment: "Hotovo.",
    resultingOutfitItemIds: resultIds,
    displayItemIds: displayIds,
    outfitChanged: true,
    outfitRequested: true,
    weatherContextKey: "current",
    hardRequirementEvidence: [],
    commentGroundingEvidence: [],
  });
  const errorsFor = (resultIds, displayIds = resultIds) =>
    validateAgentResultV1(raw(resultIds, displayIds), normalized).errors;

  assert.ok(errorsFor(
    ["blue-top", "jeans", "white-shoes", "white-shoes"],
  ).includes("resulting_outfit_ids_duplicate_or_invalid"));
  assert.ok(errorsFor(
    ["blue-top", "jeans", "white-shoes"],
    ["blue-top", "hoodie"],
  ).includes("display_item_not_in_result:hoodie"));
  assert.ok(errorsFor(
    ["blue-top", "white-shoes"],
  ).includes("outfit_structure_requires_top_bottom_shoes_or_full_body_shoes"));
  for (const ids of [
    ["blue-top", "black-top", "jeans", "white-shoes"],
    ["blue-top", "jeans", "shorts", "white-shoes"],
    ["blue-top", "jeans", "white-shoes", "red-shoes"],
  ]) {
    assert.ok(errorsFor(ids).includes("outfit_structure_conflicting_core_items"));
  }
  assert.ok(errorsFor(
    ["blue-top", "jeans", "white-shoes", "skin-base"],
  ).includes("outfit_structure_skin_base_not_displayable"));
});

test("hard weather validation uses the day selected from conversation", async () => {
  const wardrobeWithSlides = wardrobe.concat([
    item({id: "slides", name: "šľapky", type: "slides", family: "footwear", slots: ["feet"], layer: "outer", color: "black"}),
  ]);
  const {agent, inputs} = queuedAgent([{
    stylistComment: "Na zajtra je outfit pripravený.",
    resultingOutfitItemIds: ["blue-top", "shorts", "slides"],
    displayItemIds: ["blue-top", "shorts", "slides"],
    outfitChanged: true,
    outfitRequested: true,
    weatherContextKey: "tomorrow",
    hardRequirementEvidence: [],
  }]);
  const result = await agent.resolve({
    ...request("zajtra potrebujem outfit"),
    wardrobeItems: wardrobeWithSlides,
    weatherContext: {
      today: {wetGroundRisk: true},
      tomorrow: {wetGroundRisk: false, noonTempC: 24},
    },
  });
  assert.equal(inputs.length, 1);
  assert.deepEqual(result.resultingOutfitItemIds, ["blue-top", "shorts", "slides"]);
});

test("OpenAI transport binds Sol, medium reasoning and strict JSON schema", async () => {
  const requests = [];
  const execute = createOpenAiSimpleAgentExecutorV1({
    resolveOpenAISecret: () => "test-key",
    fetchImpl: async (url, init) => {
      requests.push({url, body: JSON.parse(init.body)});
      return {
        ok: true,
        json: async () => ({
          output_text: JSON.stringify({
            stylistComment: "Ahoj.",
            resultingOutfitItemIds: [],
            displayItemIds: [],
            outfitChanged: false,
            outfitRequested: false,
            weatherContextKey: "none",
            hardRequirementEvidence: [],
            commentGroundingEvidence: [],
          }),
        }),
      };
    },
  });
  const {agent} = queuedAgent([]);
  const modelInput = agent ? require("./simple_stylist_agent_v1")
    .buildModelInputV1(require("./simple_stylist_agent_v1").normalizeRequestV1(
      request("ahoj"),
    )) : null;
  const output = await execute(modelInput);
  assert.equal(output.stylistComment, "Ahoj.");
  assert.equal(requests[0].body.model, "gpt-5.6-sol");
  assert.equal(requests[0].body.reasoning.effort, "medium");
  assert.equal(requests[0].body.text.format.strict, true);
  assert.equal(requests[0].body.text.format.schema.additionalProperties, false);
});

test("OpenAI transport retries one transient failure and logs only safe provider metadata", async () => {
  const logs = [];
  let calls = 0;
  const execute = createOpenAiSimpleAgentExecutorV1({
    resolveOpenAISecret: () => "test-key",
    sleepImpl: async () => {},
    logger: {warn: (marker, details) => logs.push({marker, details})},
    fetchImpl: async () => {
      calls += 1;
      if (calls === 1) {
        return {
          ok: false,
          status: 429,
          headers: {get: (name) => name === "x-request-id" ? "req_safe_123" : null},
          json: async () => ({
            error: {type: "rate_limit_error", code: "rate_limit_exceeded", message: "secret detail"},
          }),
        };
      }
      return {
        ok: true,
        status: 200,
        headers: {get: () => null},
        json: async () => ({
          output_text: JSON.stringify({
            stylistComment: "Ahoj.",
            resultingOutfitItemIds: [],
            displayItemIds: [],
            outfitChanged: false,
            outfitRequested: false,
            weatherContextKey: "none",
            hardRequirementEvidence: [],
            commentGroundingEvidence: [],
          }),
        }),
      };
    },
  });
  const modelInput = require("./simple_stylist_agent_v1").buildModelInputV1(
    normalizeRequestV1(request("ahoj")),
  );
  const output = await execute(modelInput);
  assert.equal(output.outfitRequested, false);
  assert.equal(calls, 2);
  assert.deepEqual(logs, [{
    marker: "SIMPLE_AGENT_PROVIDER_RETRY",
    details: {
      providerAttempt: 1,
      providerStatus: 429,
      providerErrorType: "rate_limit_error",
      providerErrorCode: "rate_limit_exceeded",
      providerRequestId: "req_safe_123",
    },
  }]);
  assert.equal(JSON.stringify(logs).includes("secret detail"), false);
  assert.equal(JSON.stringify(logs).includes("test-key"), false);
});

test("non-retryable provider failure exposes sanitized diagnostics without response prose", async () => {
  const execute = createOpenAiSimpleAgentExecutorV1({
    resolveOpenAISecret: () => "test-key",
    fetchImpl: async () => ({
      ok: false,
      status: 400,
      headers: {get: (name) => name === "x-request-id" ? "req_bad_400" : null},
      json: async () => ({
        error: {type: "invalid_request_error", code: "invalid_json_schema", message: "sensitive prose"},
      }),
    }),
  });
  const modelInput = require("./simple_stylist_agent_v1").buildModelInputV1(
    normalizeRequestV1(request("ahoj")),
  );
  await assert.rejects(execute(modelInput), (error) => {
    assert.equal(error.code, "simple_agent_provider_failed");
    assert.equal(error.providerStatus, 400);
    assert.equal(error.providerErrorType, "invalid_request_error");
    assert.equal(error.providerErrorCode, "invalid_json_schema");
    assert.equal(error.providerRequestId, "req_bad_400");
    assert.equal(JSON.stringify(error).includes("sensitive prose"), false);
    return true;
  });
});

test("exhausted provider credit fails once without a pointless retry", async () => {
  let calls = 0;
  const logs = [];
  const execute = createOpenAiSimpleAgentExecutorV1({
    resolveOpenAISecret: () => "test-key",
    logger: {warn: (marker, details) => logs.push({marker, details})},
    fetchImpl: async () => {
      calls += 1;
      return {
        ok: false,
        status: 429,
        headers: {get: () => "req_quota"},
        json: async () => ({
          error: {type: "insufficient_quota", code: "credit_balance_exhausted"},
        }),
      };
    },
  });
  const modelInput = require("./simple_stylist_agent_v1").buildModelInputV1(
    normalizeRequestV1(request("ahoj")),
  );
  await assert.rejects(execute(modelInput), (error) => {
    assert.equal(error.providerStatus, 429);
    assert.equal(error.providerErrorCode, "credit_balance_exhausted");
    return true;
  });
  assert.equal(calls, 1);
  assert.deepEqual(logs, []);
});

test("system prompt keeps the personal stylist voice gender-neutral and non-audit", () => {
  const modelInput = require("./simple_stylist_agent_v1").buildModelInputV1(
    normalizeRequestV1(request("potrebujem outfit")),
  );
  const prompt = modelInput.messages[0].content;
  assert.match(prompt, /rodovo neutrálnu stylist personu/);
  assert.match(prompt, /nie systémový log/);
  assert.match(prompt, /Neopisuj mechanicky add\/remove\/replace operácie/);
  assert.match(prompt, /Samotné oznámenie plánu, miesta, času, počasia alebo udalosti nie je požiadavka na outfit/);
  assert.match(prompt, /displayItemIds musí byť prázdne/);
});

test("callable is isolated from every legacy outfit interpretation authority", () => {
  const index = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");
  const start = index.indexOf("exports.stylistSimpleAgentV1");
  const end = index.indexOf("exports.stylistChat", start);
  assert.ok(start >= 0 && end > start);
  const scope = index.slice(start, end);
  assert.match(scope, /simpleStylistAgentV1\.resolve/);
  for (const forbidden of [
    "routeStylistRequest",
    "sanitizeStylistOutfitDirective",
    "sanitizeOutfitEditPlanV1",
    "createFrozenStylistAuthority",
    "outfitDirective",
    "explicit_swap",
  ]) {
    assert.equal(scope.includes(forbidden), false, forbidden);
  }
  const implementation = fs.readFileSync(
    path.join(__dirname, "simple_stylist_agent_v1.js"),
    "utf8",
  );
  assert.equal(implementation.includes("StylistSwapRequest"), false);
  assert.equal(implementation.includes("OutfitEditPlan"), false);
});
