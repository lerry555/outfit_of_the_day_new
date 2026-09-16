"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  applyStylistResponseQualityV2,
  filterWardrobeForStylistQualityV2,
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

function inputFor(currentSession, latestUserInput = "porad mi outfit") {
  return {session: currentSession, request: {latestUserInput}};
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

test("hiking removes a weaker non-protective training jacket over a warmer hoodie", () => {
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
  const hiking = session({activity: "hiking", environment: "outdoor"});
  const filtered = filterWardrobeForStylistQualityV2(
    [hoodie, trainingJacket, shell],
    inputFor(hiking, "idem na túru"),
  );
  assert.deepEqual(filtered.map((item) => item.id), ["hoodie", "rain_shell"]);
});

test("current outfit items are preserved even when they would be filtered for a new outfit", () => {
  const boots = footwear("winter", {canonicalType: "winter_boots", warmth: 8, seasons: ["winter"]});
  const current = session({currentIds: ["winter"]});
  assert.deepEqual(filterWardrobeForStylistQualityV2([boots], inputFor(current)).map((item) => item.id), ["winter"]);
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
