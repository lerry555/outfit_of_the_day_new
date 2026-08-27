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

test("grounding state blocks generation for unresolved material dimensions", () => {
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
    semanticGrounding: null,
    eventContext: null,
  });
});

test("explicit user evidence may resolve a locally unknown activity", () => {
  const parsed = {
    action: "generate_outfit",
    eventContext: {},
    semanticGrounding: {
      activity: {
        value: "hike",
        evidence: "budeme sa motať po vysokohorskom chodníku",
        source: "user_explicit",
      },
    },
  };
  const decision = parseOutfitDecisionFields(parsed);
  const state = {
    groundingStatus: "needs_grounding",
    unresolvedMaterialFields: ["activity"],
    semanticEvidenceTexts: [
      "Zajtra budeme sa motať po vysokohorskom chodníku asi šesť hodín.",
    ],
  };

  assert.equal(resolveOutfitAction("generate_outfit", decision, state), "generate_outfit");
  assert.equal(state.activityHint, "hike");
  assert.equal(state.occasion, "hike");
  assert.deepEqual(state.unresolvedMaterialFields, []);
  assert.equal(state.groundingStatus, "sufficient");
  assert.equal(parsed.eventContext.occasion, "hike");
});

test("verified semantic activity creates transport context when model omits eventContext", () => {
  const parsed = {
    semanticGrounding: {
      activity: {
        value: "hike",
        evidence: "motať po vysokohorskom chodníku",
        source: "user_explicit",
      },
    },
  };
  const decision = parseOutfitDecisionFields(parsed);
  const state = {
    groundingStatus: "needs_grounding",
    unresolvedMaterialFields: ["activity"],
    semanticEvidenceTexts: [
      "budeme sa asi 6 hodín motať po vysokohorskom chodníku",
    ],
  };

  assert.equal(resolveOutfitAction("clarify", decision, state), "chat");
  assert.equal(state.activityHint, "hike");
  assert.equal(parsed.eventContext.occasion, "hike");
  assert.equal(decision.eventContext.occasion, "hike");
  assert.deepEqual(state.unresolvedMaterialFields, []);
});

test("semantic grounding cannot borrow assistant-only or invented evidence", () => {
  for (const evidence of ["ideme na túru", "túra v Tatrách"]) {
    const parsed = {
      eventContext: {},
      semanticGrounding: {
        activity: {value: "hike", evidence, source: "user_explicit"},
      },
    };
    const decision = parseOutfitDecisionFields(parsed);
    const state = {
      groundingStatus: "needs_grounding",
      unresolvedMaterialFields: ["activity"],
      semanticEvidenceTexts: ["Zajtra idem na výlet."],
    };
    assert.equal(resolveOutfitAction("generate_outfit", decision, state), "clarify");
    assert.deepEqual(state.unresolvedMaterialFields, ["activity"]);
  }
});

test("bare generic trip evidence never upgrades to hiking", () => {
  const parsed = {
    eventContext: {},
    semanticGrounding: {
      activity: {
        value: "hike",
        evidence: "idem zajtra na výlet",
        source: "user_explicit",
      },
    },
  };
  const decision = parseOutfitDecisionFields(parsed);
  const state = {
    groundingStatus: "needs_grounding",
    unresolvedMaterialFields: ["activity"],
    semanticEvidenceTexts: ["idem zajtra na výlet"],
  };
  assert.equal(resolveOutfitAction("generate_outfit", decision, state), "clarify");
  assert.equal(state.activityHint, undefined);
});

test("semantic activity does not erase a different unresolved field", () => {
  const parsed = {
    eventContext: {},
    semanticGrounding: {
      activity: {
        value: "hike",
        evidence: "vyšľapeme si hrebeň",
        source: "user_explicit",
      },
    },
  };
  const decision = parseOutfitDecisionFields(parsed);
  const state = {
    groundingStatus: "needs_grounding",
    unresolvedMaterialFields: ["destination", "activity"],
    semanticEvidenceTexts: ["vyšľapeme si hrebeň"],
  };
  assert.equal(resolveOutfitAction("generate_outfit", decision, state), "clarify");
  assert.deepEqual(state.unresolvedMaterialFields, ["destination"]);
  assert.equal(state.activityHint, "hike");
});

test("invalid canonical semantic activity is ignored", () => {
  const decision = parseOutfitDecisionFields({
    semanticGrounding: {
      activity: {
        value: "extreme_mountain_climb",
        evidence: "ideme liezť",
        source: "user_explicit",
      },
    },
  });
  assert.equal(decision.semanticGrounding, null);
});
