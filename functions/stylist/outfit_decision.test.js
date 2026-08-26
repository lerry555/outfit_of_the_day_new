"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  parseOutfitDecisionFields,
  resolveOutfitAction,
} = require("./outfit_decision");

test("minimal clarification allows a distinct second question but blocks loops", () => {
  assert.equal(resolveOutfitAction("clarify", {impactFields: ["terrain"]}, {
    clarifiedMaterialFields: ["route"],
  }), "clarify");
  assert.equal(resolveOutfitAction("clarify", {impactFields: ["terrain"]}, {
    clarifiedMaterialFields: ["terrain"],
  }), "chat");
  assert.equal(resolveOutfitAction("clarify", {impactFields: ["style"]}, {}), "chat");
});

test("grounding state blocks generation for all material event dimensions", () => {
  for (const field of [
    "activity", "activity_type", "outing_type", "trip_type", "trip_scope",
    "duration", "trip_length", "number_of_days", "indoor_outdoor", "intensity",
  ]) {
    assert.equal(resolveOutfitAction("clarify", {impactFields: [field]}, {
      clarifiedMaterialFields: [],
    }), "clarify", field);
  }
  assert.equal(resolveOutfitAction("generate_outfit", {}, {
    groundingStatus: "needs_grounding",
    unresolvedMaterialFields: ["destination", "activity"],
  }), "clarify");
});

test("outfit decision fields are bounded and sanitized", () => {
  assert.deepEqual(parseOutfitDecisionFields({
    confidence: 9,
    decisionRisk: "HIGH",
    assumptions: ["  known  ", ""],
    impactFields: ["weather", null],
  }), {
    confidence: 1,
    decisionRisk: "high",
    assumptions: ["known"],
    clarifyReason: null,
    impactFields: ["weather"],
  });
});
