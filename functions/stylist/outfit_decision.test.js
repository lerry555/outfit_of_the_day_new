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
  }), "generate_outfit");
  assert.equal(resolveOutfitAction("clarify", {impactFields: ["style"]}, {}), "generate_outfit");
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
