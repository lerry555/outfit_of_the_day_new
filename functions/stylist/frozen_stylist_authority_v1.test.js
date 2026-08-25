"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {normalizeRequest, validateDecision} = require("./frozen_stylist_authority_v1");

const owned = new Set(["top", "bottom", "shoes"]);
const request = () => ({contractVersion: 1, resolvedContext: {activity: "walk"}, frozenCandidates: [{
  candidateId: "candidate-a", itemIds: ["top", "bottom", "shoes"],
  hardConstraintEvidence: {deterministicPassed: true, violationCodes: []},
  compromiseClassification: {level: "none"},
}]});

test("frozen authority selects only an eligible candidate ID", () => {
  const normalized = normalizeRequest(request(), owned);
  assert.equal(validateDecision(normalized.frozenCandidates, {
    action: "select_candidate", selectedCandidateId: "candidate-a",
  }).selectedCandidateId, "candidate-a");
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
