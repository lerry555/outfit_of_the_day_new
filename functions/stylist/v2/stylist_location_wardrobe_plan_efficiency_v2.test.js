"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {enforceHighConfidenceGrounding} = require("./openai_stylist_model_port_v2");

function rawPlan(overrides = {}) {
  return {
    kind: "tool_request",
    action: "none",
    assistantText: "",
    clarificationField: null,
    clarificationQuestion: null,
    locationQuery: "Bratislava",
    locationTargetField: "eventLocation",
    wardrobeScope: "none",
    wardrobeCategory: null,
    replaceItemIds: [],
    retainItemIds: [],
    allowedSlots: [],
    allowedCategories: [],
    allowRemovalOnly: false,
    patch: {},
    ...overrides,
  };
}

test("explicit-location outfit planning adds the full wardrobe to the same tool phase", () => {
  const raw = rawPlan();
  const result = enforceHighConfidenceGrounding(raw, {
    request: {latestUserInput: "Zajtra idem na koncert do Bratislavy, vyber mi outfit."},
  });

  assert.equal(result.locationQuery, "Bratislava");
  assert.equal(result.locationTargetField, "eventLocation");
  assert.equal(result.wardrobeScope, "full_relevant");
  assert.equal(result.wardrobeCategory, null);
  assert.equal(raw.wardrobeScope, "none");
});

test("location-only non-outfit planning is not forced to read the wardrobe", () => {
  const raw = rawPlan();
  const result = enforceHighConfidenceGrounding(raw, {
    request: {latestUserInput: "Aké býva zajtra počasie v Bratislave?"},
  });
  assert.equal(result.wardrobeScope, "none");
});

test("an existing targeted wardrobe request is preserved", () => {
  const raw = rawPlan({wardrobeScope: "category", wardrobeCategory: "footwear"});
  const result = enforceHighConfidenceGrounding(raw, {
    request: {latestUserInput: "Do Bratislavy mi vyber outfit a zameraj sa na topánky."},
  });
  assert.equal(result.wardrobeScope, "category");
  assert.equal(result.wardrobeCategory, "footwear");
});
