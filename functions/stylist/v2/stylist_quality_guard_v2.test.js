"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  applyStylistResponseQualityV2,
  filterWardrobeForStylistQualityV2,
  guardSelectedOutfitQualityV2,
  normalizeStylistVoiceV2,
} = require("./stylist_quality_guard_v2");

function session({
  activity = "dinner",
  environment = "indoor",
  dateKey = "2026-09-18",
  weather = null,
  currentIds = [],
} = {}) {
  return {
    context: {
      activity: {id: activity, label: activity, source: "user"},
      environment,
      date: {dateKey, source: "deterministic_user_text"},
      timeWindow: {key: "day", label: "cez deň", source: "one_brain_default"},
      weather,
    },
    currentOutfit: {
      itemIds: currentIds,
      selectionReasonsByItemId: {},
      compromises: [],
      missingWardrobeNeeds: [],
    },
  };
}

function footwear(id, overrides = {}) {
  return {
    id,
    name: id,
    category: "footwear",
    canonicalFamily: "footwear",
    canonicalType: "sneakers",
    bodySlots: ["feet"],
    layerPosition: "not_applicable",
    warmth: 3,
    formality: 3,
    seasons: ["all_season"],
    outfitFunctions: [],
    ...overrides,
  };
}

function upper(id, overrides = {}) {
  return {
    id,
    name: id,
    category: "top",
    canonicalFamily: "tops",
    canonicalType: "hoodie",
    bodySlots: ["upper_body"],
    layerPosition: "mid",
    warmth: 6,
    formality: 2,
    seasons: ["autumn", "winter"],
    outfitFunctions: [],
    ...overrides,
  };
}

function inputFor(currentSession, latestUserInput = "porad mi outfit", overrides = {}) {
  return {
    session: currentSession,
    request: {latestUserInput},
    toolResults: {},
    runtimeConstraints: {},
    ...overrides,
  };
}

test("September dinner removes winter-only hot boots but keeps transitional boots and sneakers", () => {
  const items = [
    footwear("winter", {canonicalType: "winter_boots", warmth: 8, seasons: ["winter"]}),
    footwear("chelsea", {canonicalType: "chelsea_boots", warmth: 5, seasons: ["autumn", "all_season"]}),
    footwear("sneakers"),
  ];
  const filtered = filterWardrobeForStylistQualityV2(items, inputFor(session()));
  assert.deepEqual(filtered.map((item) => item.id), ["chelsea", "sneakers"]);
});

test("weather authority rejects winter-only hot boots in mild conditions and keeps them in cold conditions", () => {
  const boots = footwear("winter", {canonicalType: "winter_boots", warmth: 8, seasons: ["winter"]});
  const mild = session({
    dateKey: "2026-01-18",
    weather: {snapshot: {representativeTempC: 16}},
  });
  const cold = session({
    dateKey: "2026-01-18",
    weather: {snapshot: {representativeTempC: 2}},
  });
  assert.deepEqual(filterWardrobeForStylistQualityV2([boots], inputFor(mild)), []);
  assert.deepEqual(filterWardrobeForStylistQualityV2([boots], inputFor(cold)).map((item) => item.id), ["winter"]);
});

test("explicit boot request is respected", () => {
  const boots = footwear("winter", {canonicalType: "winter_boots", warmth: 8, seasons: ["winter"]});
  const filtered = filterWardrobeForStylistQualityV2(
    [boots],
    inputFor(session(), "chcem k tomu moje zimné čižmy"),
  );
  assert.deepEqual(filtered.map((item) => item.id), ["winter"]);
});

test("cold outdoor answer candidates remove weaker training outer while preserving a real shell", () => {
  const hoodie = upper("hoodie", {canonicalType: "hoodie", layerPosition: "mid", warmth: 6});
  const trainingJacket = upper("training_jacket", {
    name: "Biela tréningová bunda",
    canonicalType: "track_jacket",
    layerPosition: "outer",
    warmth: 3,
    outfitFunctions: [],
  });
  const shell = upper("rain_shell", {
    name: "Ľahká nepremokavá bunda",
    canonicalType: "rain_shell",
    layerPosition: "shell",
    warmth: 2,
    outfitFunctions: ["weather_protection", "waterproof"],
  });
  const hiking = session({
    activity: "hiking",
    environment: "outdoor",
    weather: {snapshot: {representativeTempC: 12}},
  });
  const filtered = filterWardrobeForStylistQualityV2(
    [hoodie, trainingJacket, shell],
    inputFor(hiking, "idem na túru"),
  );
  assert.deepEqual(filtered.map((item) => item.id), ["hoodie", "rain_shell"]);
});

test("authorized edit preserves current outfit candidates even when a new outfit would filter them", () => {
  const boots = footwear("winter", {canonicalType: "winter_boots", warmth: 8, seasons: ["winter"]});
  const current = session({currentIds: ["winter"]});
  const editInput = inputFor(current, "vymeň mi košeľu", {
    runtimeConstraints: {requiredAnswerAction: "edit_outfit"},
    toolResults: {authorizedEditScope: {replaceItemIds: ["shirt"], retainItemIds: ["winter"]}},
  });
  assert.deepEqual(filterWardrobeForStylistQualityV2([boots], editInput).map((item) => item.id), ["winter"]);
});

test("new outfit does not preserve a stale winter boot merely because it was in the previous outfit", () => {
  const boots = footwear("winter", {canonicalType: "winter_boots", warmth: 8, seasons: ["winter"]});
  const current = session({currentIds: ["winter"]});
  assert.deepEqual(filterWardrobeForStylistQualityV2([boots], inputFor(current)), []);
});

test("pairwise fallback removes non-protective training jacket over warmer hoodie even without forecast", () => {
  const hoodie = upper("hoodie", {
    name: "Svetlomodrá mikina",
    canonicalType: "hoodie",
    layerPosition: "mid",
    warmth: 6,
  });
  const trainingJacket = upper("training_jacket", {
    name: "Biela tréningová bunda",
    canonicalType: "track_jacket",
    layerPosition: "outer",
    warmth: 3,
    outfitFunctions: [],
  });
  const pants = {
    id: "pants",
    name: "Sivé tepláky",
    category: "bottom",
    canonicalFamily: "bottoms",
    canonicalType: "joggers",
    bodySlots: ["lower_body"],
    layerPosition: "not_applicable",
    warmth: 4,
    outfitFunctions: [],
  };
  const hiking = session({activity: "hiking", environment: "outdoor"});
  const input = inputFor(hiking, "idem na túru", {
    toolResults: {wardrobeItems: [hoodie, trainingJacket, pants]},
  });
  const raw = {
    action: "generate_outfit",
    assistantText: "Na túru by som išiel vo vrstvách: mikina, tréningová bunda a tepláky.",
    resultingOutfitItemIds: ["hoodie", "training_jacket", "pants"],
    displayItemIds: ["hoodie", "training_jacket", "pants"],
    selectionReasons: [
      {itemId: "hoodie", reason: "Teplá vrstva."},
      {itemId: "training_jacket", reason: "Ďalšia vrstva."},
      {itemId: "pants", reason: "Pohodlie."},
    ],
  };
  const guarded = guardSelectedOutfitQualityV2(raw, input);
  assert.deepEqual(guarded.resultingOutfitItemIds, ["hoodie", "pants"]);
  assert.deepEqual(guarded.displayItemIds, ["hoodie", "pants"]);
  assert.deepEqual(guarded.selectionReasons.map((entry) => entry.itemId), ["hoodie", "pants"]);
  assert.match(guarded.assistantText, /tréningovú bundu.*vynechávam/i);
  assert.doesNotMatch(guarded.assistantText, /by som išiel/i);
});

test("pairwise fallback keeps a lighter real weather shell over a warmer hoodie", () => {
  const hoodie = upper("hoodie", {canonicalType: "hoodie", layerPosition: "mid", warmth: 6});
  const shell = upper("rain_shell", {
    name: "Nepremokavá bunda",
    canonicalType: "rain_shell",
    layerPosition: "shell",
    warmth: 2,
    outfitFunctions: ["weather_protection", "waterproof"],
  });
  const input = inputFor(session({activity: "hiking", environment: "outdoor"}), "idem na túru", {
    toolResults: {wardrobeItems: [hoodie, shell]},
  });
  const raw = {
    action: "generate_outfit",
    assistantText: "Odporúčam ti mikinu a nepremokavú bundu.",
    resultingOutfitItemIds: ["hoodie", "rain_shell"],
    displayItemIds: ["hoodie", "rain_shell"],
    selectionReasons: [],
  };
  assert.deepEqual(guardSelectedOutfitQualityV2(raw, input), raw);
});

test("Stylist voice recommends clothes to the user instead of dressing itself", () => {
  const hike = normalizeStylistVoiceV2("Jasné, na túru by som išiel radšej vo vrstvách: mikina a bunda.");
  const dinner = normalizeStylistVoiceV2("Jasné, na večeru by som išiel čisto a uhladene: košeľa a rifle.");
  assert.match(hike, /odporúčam ti obliecť sa vo vrstvách/i);
  assert.doesNotMatch(hike, /by som išiel/i);
  assert.match(dinner, /ti odporúčam čistý a uhladený outfit/i);
  assert.doesNotMatch(dinner, /by som išiel/i);
});

test("outdoor outfit with real forecast gets a concise weather reason when model omitted it", () => {
  const hiking = session({
    activity: "hiking",
    environment: "outdoor",
    weather: {
      snapshot: {
        minTempC: 9,
        maxTempC: 14,
        representativeTempC: 12,
        willRain: true,
        willSnow: false,
        isWindy: true,
        maxWindKph: 38,
      },
    },
  });
  const envelope = {
    kind: "final",
    result: {
      action: "generate_outfit",
      assistantText: "Odporúčam ti mikinu, nohavice a športové tenisky.",
    },
  };
  const guarded = applyStylistResponseQualityV2(envelope, inputFor(hiking));
  assert.match(guarded.result.assistantText, /9–14 °C/);
  assert.match(guarded.result.assistantText, /dažď/i);
  assert.match(guarded.result.assistantText, /38 km\/h/);
});

test("indoor dinner does not inject outdoor weather into the answer", () => {
  const dinner = session({
    activity: "dinner",
    environment: "indoor",
    weather: {snapshot: {representativeTempC: 10, willRain: true}},
  });
  const envelope = {
    kind: "final",
    result: {
      action: "generate_outfit",
      assistantText: "Odporúčam ti bielu košeľu a tmavé nohavice.",
    },
  };
  const guarded = applyStylistResponseQualityV2(envelope, inputFor(dinner));
  assert.equal(guarded.result.assistantText, envelope.result.assistantText);
});
