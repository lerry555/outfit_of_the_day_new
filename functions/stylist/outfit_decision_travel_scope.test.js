"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  parseOutfitDecisionFields,
  resolveOutfitAction,
} = require("./outfit_decision");

test("unknown travel purpose becomes destination use from explicit unlisted activity", () => {
  const parsed = {
    impactFields: ["trip_scope"],
    semanticGrounding: {
      activity: {
        value: "other",
        label: "prednáška",
        evidence: "idem tam na prednášku",
        source: "user_explicit",
      },
    },
  };
  const decision = parseOutfitDecisionFields(parsed);
  const state = {
    groundingStatus: "needs_grounding",
    unresolvedMaterialFields: ["trip_scope"],
    semanticEvidenceTexts: ["idem tam na prednášku"],
    locationContext: {
      providerAuthorityEnabled: true,
      providerVerified: true,
      needsMoreSpecificity: false,
      weatherLabel: "provider-place",
    },
    travelContext: {
      scope: "unknown",
      scopeNeedsClarification: true,
    },
  };

  assert.equal(resolveOutfitAction("clarify", decision, state), "chat");
  assert.equal(state.travelContext.scope, "destination");
  assert.deepEqual(state.unresolvedMaterialFields, []);
});

test("semantic purpose does not swallow a distinct material clarification", () => {
  const parsed = {
    impactFields: ["trip_scope", "formality"],
    semanticGrounding: {
      activity: {
        value: "other",
        label: "prednáška",
        evidence: "idem tam na prednášku",
        source: "user_explicit",
      },
    },
  };
  const decision = parseOutfitDecisionFields(parsed);
  const state = {
    groundingStatus: "needs_grounding",
    unresolvedMaterialFields: ["trip_scope"],
    semanticEvidenceTexts: ["idem tam na prednášku"],
    locationContext: {
      providerAuthorityEnabled: true,
      providerVerified: true,
      needsMoreSpecificity: false,
      weatherLabel: "provider-place",
    },
    travelContext: {
      scope: "unknown",
      scopeNeedsClarification: true,
    },
  };

  assert.equal(resolveOutfitAction("clarify", decision, state), "clarify");
  assert.equal(state.travelContext.scope, "destination");
  assert.deepEqual(state.unresolvedMaterialFields, []);
});

test("broad destination remains unresolved after purpose is understood", () => {
  const parsed = {
    semanticGrounding: {
      activity: {
        value: "concert",
        evidence: "idem tam na koncert",
        source: "user_explicit",
      },
    },
  };
  const decision = parseOutfitDecisionFields(parsed);
  const state = {
    groundingStatus: "needs_grounding",
    unresolvedMaterialFields: ["trip_scope"],
    semanticEvidenceTexts: ["idem tam na koncert"],
    locationContext: {
      providerAuthorityEnabled: true,
      providerVerified: true,
      needsMoreSpecificity: true,
    },
    travelContext: {
      scope: "unknown",
      scopeNeedsClarification: true,
    },
  };

  assert.equal(resolveOutfitAction("generate_outfit", decision, state), "clarify");
  assert.deepEqual(state.unresolvedMaterialFields, ["destination"]);
});
