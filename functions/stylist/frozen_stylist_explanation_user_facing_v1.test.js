"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  normalizeRequest,
  explanationPayload,
  deterministicExplanation,
  isUserFacingExplanationSafe,
} = require("./frozen_stylist_authority_v1");
const {anthropicBody} = require("./ai_stylist_role_transport_v1");

const owned = new Set(["shirt", "trousers", "jacket"]);
const request = () => ({
  contractVersion: 1,
  resolvedContext: {occasion: "večera v reštaurácii", weather: "18C"},
  frozenCandidates: [{
    candidateId: "candidate-internal-only",
    itemIds: ["shirt", "trousers", "jacket"],
    presentationItems: [
      {itemId: "shirt", name: "biela košeľa", canonicalType: "shirt", primaryColor: "white"},
      {itemId: "trousers", name: "sivé nohavice", canonicalType: "trousers", primaryColor: "grey"},
      {itemId: "jacket", name: "červená bomber bunda", canonicalType: "bomber_jacket", primaryColor: "red"},
    ],
    hardConstraintEvidence: {deterministicPassed: true, violationCodes: []},
    compromiseClassification: {level: "acceptable_compromise", reasonCodes: ["internal_reason"]},
  }],
});

test("presentation snapshot is immutable and exactly matches the frozen selected item set", () => {
  const normalized = normalizeRequest(request(), owned);
  const selected = normalized.frozenCandidates[0];
  assert.deepEqual(selected.presentationItems.map((item) => item.itemId), selected.itemIds);
  assert.equal(Object.isFrozen(selected.presentationItems), true);
  assert.equal(Object.isFrozen(selected.presentationItems[0]), true);
  assert.throws(() => { selected.presentationItems[0].name = "invented"; }, TypeError);
  assert.equal(selected.presentationItems[0].name, "biela košeľa");
});

test("Claude receives presentation-safe selected clothes without IDs or authority evidence", () => {
  const normalized = normalizeRequest(request(), owned);
  const payload = explanationPayload(normalized, {
    action: "select_candidate", selectedCandidateId: "candidate-internal-only", reasonCodes: [],
  });
  assert.deepEqual(payload.userFacingSelectedOutfit, [
    {name: "biela košeľa", canonicalType: "shirt", primaryColor: "white"},
    {name: "sivé nohavice", canonicalType: "trousers", primaryColor: "grey"},
    {name: "červená bomber bunda", canonicalType: "bomber_jacket", primaryColor: "red"},
  ]);
  const serialized = JSON.stringify(payload);
  for (const forbidden of ["candidate-internal-only", "itemId", "hardConstraintEvidence", "reasonCodes"]) {
    assert.equal(serialized.includes(forbidden), false);
  }
});

test("Anthropic instructions forbid IDs and validation/scoring jargon", () => {
  const system = anthropicBody({canonicalPayload: {effectiveAction: "reject_all"}}).system;
  for (const forbidden of [
    "candidate ID", "item ID", "validátor", "deterministické pravidlá",
    "hard constraints", "hard checks", "violation codes",
    "compromiseClassification", "reason codes", "confidence",
  ]) {
    assert.equal(system.includes(forbidden), true, forbidden);
  }
});

test("deterministic explanation fallback remains user-facing", () => {
  const selected = deterministicExplanation({action: "select_candidate"});
  assert.equal(selected.includes("kontrolou"), false);
  assert.equal(selected.includes("podmienkam"), true);
  assert.equal(
    deterministicExplanation({action: "reject_all"}).includes("reason code"),
    false,
  );
});

test("implementation jargon is rejected from user-facing explanation prose", () => {
  assert.equal(isUserFacingExplanationSafe("Toto je outfit podľa počasia."), true);
  for (const leaked of [
    "Vybral som candidate ID 3.",
    "Outfit prešiel hard checks validátora.",
    "CompromiseClassification je acceptable_compromise.",
  ]) {
    assert.equal(isUserFacingExplanationSafe(leaked), false, leaked);
  }
});
