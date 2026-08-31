"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {resolveOutfitAction} = require("./outfit_decision");

test("known routine city walk cannot clarify the already grounded destination", () => {
  const state = {
    groundingStatus: "sufficient",
    unresolvedMaterialFields: [],
    routineLocalOutfit: true,
    activityLocationKnown: true,
    activityLocationLabel: "Martin",
    activityHint: "city_walk",
    clarifiedMaterialFields: [],
  };

  assert.equal(
    resolveOutfitAction("clarify", {impactFields: ["destination"]}, state),
    "generate_outfit",
  );
});

test("location and destination are the same clarification target", () => {
  const state = {
    groundingStatus: "sufficient",
    unresolvedMaterialFields: [],
    activityLocationKnown: false,
    clarifiedMaterialFields: ["location"],
  };

  assert.equal(
    resolveOutfitAction("clarify", {impactFields: ["destination"]}, state),
    "chat",
  );
});

test("a genuinely unknown destination still allows one clarification", () => {
  const state = {
    groundingStatus: "sufficient",
    unresolvedMaterialFields: [],
    activityLocationKnown: false,
    clarifiedMaterialFields: [],
  };

  assert.equal(
    resolveOutfitAction("clarify", {impactFields: ["location"]}, state),
    "clarify",
  );
});
