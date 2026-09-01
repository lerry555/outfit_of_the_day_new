"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  createFrozenStylistAuthority,
  normalizeRequest,
  validateDecision,
} = require("./frozen_stylist_authority_v1");

const owned = new Set(["top", "bottom", "shoes"]);
const request = () => ({contractVersion: 1, resolvedContext: {activity: "walk"}, frozenCandidates: [{
  candidateId: "candidate-a", itemIds: ["top", "bottom", "shoes"],
  presentationItems: [
    {itemId: "top", name: "tričko", canonicalType: "t_shirt", primaryColor: "black"},
    {itemId: "bottom", name: "rifle", canonicalType: "jeans", primaryColor: "blue"},
    {itemId: "shoes", name: "čižmy", canonicalType: "winter_boots", primaryColor: "black"},
  ],
  hardConstraintEvidence: {deterministicPassed: true, violationCodes: []},
  compromiseClassification: {level: "material_compromise"},
  compromiseDetails: [{
    itemName: "čižmy", tier: "strongCompromise",
    reasonCodes: ["footwear_not_hiking_or_trail_rated"],
    missingCapabilities: ["hiking_footwear", "traction"],
    idealReplacementDescription: "turistická obuv s gripom",
  }],
}]});

test("frozen authority selects only an eligible candidate ID", () => {
  const normalized = normalizeRequest(request(), owned);
  assert.equal(validateDecision(normalized.frozenCandidates, {
    action: "select_candidate", selectedCandidateId: "candidate-a",
  }).selectedCandidateId, "candidate-a");
  assert.equal(normalized.frozenCandidates[0].presentationItems[2].canonicalType, "winter_boots");
  assert.deepEqual(
    normalized.frozenCandidates[0].compromiseDetails[0].missingCapabilities,
    ["hiking_footwear", "traction"],
  );
});

test("unknown ID, non-owned candidate, malformed attempt and empty valid set reject all", () => {
  const normalized = normalizeRequest(request(), owned);
  for (const attempt of [null, {action: "select_candidate", selectedCandidateId: "candidate-0"}]) {
    assert.equal(validateDecision(normalized.frozenCandidates, attempt).action, "reject_all");
  }
  const noOwnership = normalizeRequest(request(), new Set());
  assert.equal(validateDecision(noOwnership.frozenCandidates, {
    action: "select_candidate", selectedCandidateId: "candidate-a",
  }).action, "reject_all");
});

test("locked selection request preserves presentation semantics without opening candidate choice", () => {
  const raw = request();
  raw.decisionMode = "locked_selection";
  raw.presentationMode = "focused_item";
  raw.focusSlot = "bottom";
  raw.userRequest = "ktoré kraťasy si mám dať?";
  raw.resolvedContext.userIntentContext = "idem večer do mesta";
  raw.frozenCandidates[0].presentationItems[1].slot = "bottom";
  const normalized = normalizeRequest(raw, owned);
  assert.equal(normalized.decisionMode, "locked_selection");
  assert.equal(normalized.presentationMode, "focused_item");
  assert.equal(normalized.focusSlot, "bottom");
  assert.equal(normalized.userRequest, "ktoré kraťasy si mám dať?");
  assert.equal(normalized.resolvedContext.userIntentContext, "idem večer do mesta");
  assert.equal(normalized.frozenCandidates[0].presentationItems[1].slot, "bottom");
});

test("focused Brain follow-up is deterministic, concise and does not spend an explanation call", async () => {
  const calls = [];
  const authority = createFrozenStylistAuthority({
    resolveOpenAISecret: () => "openai-test",
    resolveAnthropicSecret: () => "anthropic-test",
    execute: async (call) => { calls.push(call); throw new Error("focused mode should not call provider"); },
  });
  const result = await authority.resolve({
    data: {
      contractVersion: 1,
      conversationBrainVersion: "brain_v1",
      decisionMode: "locked_selection",
      presentationMode: "focused_item",
      focusSlot: "bottom",
      userRequest: "radšej by som si dal kraťasy",
      resolvedContext: {weather: "21C rain=false"},
      frozenCandidates: [{
        candidateId: "locked",
        itemIds: ["top", "shorts", "shoes"],
        presentationItems: [
          {itemId: "top", name: "sivé tričko", canonicalType: "t_shirt", primaryColor: "gray", slot: "top"},
          {itemId: "shorts", name: "čierne šortky", canonicalType: "casual_shorts", primaryColor: "black", slot: "bottom"},
          {itemId: "shoes", name: "biele tenisky", canonicalType: "sneakers", primaryColor: "white", slot: "shoes"},
        ],
        hardConstraintEvidence: {deterministicPassed: true, violationCodes: []},
        compromiseClassification: {level: "none", reasonCodes: []},
      }],
    },
    ownedItemIds: new Set(["top", "shorts", "shoes"]),
  });
  assert.equal(calls.length, 0);
  assert.equal(result.action, "select_candidate");
  assert.match(result.explanation, /čierne šortky/);
  assert.doesNotMatch(result.explanation, /21|°C|počas/i);
});
