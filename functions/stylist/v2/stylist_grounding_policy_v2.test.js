"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  applyMandatoryGroundingV2,
  createGroundingEnforcedStylistModelV2,
  inferMandatoryGroundingV2,
  isConcreteOutfitRequestV2,
  isGreetingV2,
  mergeGroundingRequirementsV2,
} = require("./stylist_grounding_policy_v2");

function baseState() {
  return {
    schemaVersion: 2,
    chatId: "chat_grounding",
    revision: 0,
    context: {
      currentLocationObservation: {
        providerId: "gps:49.05,18.92", label: "Martin", lat: 49.05, lng: 18.92,
        source: "device_gps", observedAt: "2026-09-08T20:00:00.000Z",
      },
      destination: null, eventLocation: null, date: {dateKey: "2026-09-08"}, timeWindow: {key: "day"},
      activity: {id: "old", label: "old"}, terrain: {surface: null, difficulty: null, condition: null},
      weather: {locationProviderId: "gps:49.05,18.92", dateKey: "2026-09-08", timeWindowKey: "day", fetchedAt: "2026-09-08T19:00:00.000Z", source: "open-meteo"},
      groundingRequirements: {weatherRequired: true, weatherLocationField: "currentLocationObservation", terrainRequiredFields: []},
    },
    currentOutfit: {itemIds: [], selectionReasonsByItemId: {}, revision: 0},
    conversationMemory: {answeredClarificationFields: {destination: {label: "Old place"}}},
  };
}

test("global destination grounding is not hike-specific", () => {
  for (const message of ["zajtra idem na túru a potreboval by som outfit", "zajtra idem na návštevu a potrebujem outfit", "cez víkend cestujem preč a chcem outfit", "na dovolenke chcem outfit na výlet"]) {
    const policy = inferMandatoryGroundingV2({latestUserInput: message, state: baseState()});
    assert.equal(policy.active, true, message);
    assert.equal(policy.requirements.weatherLocationField, "destination", message);
  }
});

test("event grounding uses eventLocation across occasions", () => {
  for (const message of ["potrebujem outfit na svadbu", "o tri týždne idem na koncert a potrebujem outfit", "chcem outfit na festival", "vyber mi outfit na pracovný pohovor"]) {
    const policy = inferMandatoryGroundingV2({latestUserInput: message, state: baseState()});
    assert.equal(policy.requirements.weatherLocationField, "eventLocation", message);
  }
});

test("routine indoor request does not over-ground weather", () => {
  const policy = inferMandatoryGroundingV2({latestUserInput: "vyber mi outfit do práce", state: baseState()});
  assert.equal(policy.active, true);
  assert.equal(policy.scope, "style_only");
  assert.equal(policy.requirements.weatherRequired, false);
  assert.equal(policy.requirements.weatherLocationField, null);
});

test("generic local outfit uses GPS and resets stale outing context", () => {
  const policy = inferMandatoryGroundingV2({latestUserInput: "daj mi outfit na zajtra", state: baseState()});
  const next = applyMandatoryGroundingV2(baseState(), policy);
  assert.equal(next.context.groundingRequirements.weatherLocationField, "currentLocationObservation");
  assert.equal(next.context.destination, null);
  assert.equal(next.context.eventLocation, null);
  assert.equal(next.context.date, null);
  assert.equal(next.context.timeWindow, null);
  assert.equal(next.context.weather, null);
  assert.equal(next.context.activity, null);
  assert.equal(next.conversationMemory.answeredClarificationFields.destination, undefined);
});

test("mandatory remote authority cannot be weakened to current GPS", () => {
  const merged = mergeGroundingRequirementsV2(
    {weatherRequired: true, weatherLocationField: "destination", terrainRequiredFields: []},
    {weatherRequired: true, weatherLocationField: "currentLocationObservation", terrainRequiredFields: []},
    {weatherRequired: true, weatherLocationField: "destination", terrainRequiredFields: []},
  );
  assert.equal(merged.weatherLocationField, "destination");
});

test("planner that ignores required destination is converted to clarification", async () => {
  const policy = inferMandatoryGroundingV2({latestUserInput: "zajtra idem na návštevu a potrebujem outfit", state: baseState()});
  const groundedState = applyMandatoryGroundingV2(baseState(), policy);
  const model = createGroundingEnforcedStylistModelV2({async turn() {
    return {kind: "final", statePatch: {context: {groundingRequirements: {weatherRequired: true, weatherLocationField: "currentLocationObservation", terrainRequiredFields: []}}}, result: {action: "chat", assistantText: "Tu je outfit.", display: {kind: "none", itemIds: []}}};
  }}, policy);
  const envelope = await model.turn({phase: "plan", session: groundedState});
  assert.equal(envelope.result.action, "clarify");
  assert.equal(envelope.result.clarification.field, "destination");
  assert.equal(envelope.statePatch.context.groundingRequirements.weatherLocationField, "destination");
});

test("event planner cannot silently substitute GPS for event venue", async () => {
  const policy = inferMandatoryGroundingV2({latestUserInput: "potrebujem outfit na koncert", state: baseState()});
  const groundedState = applyMandatoryGroundingV2(baseState(), policy);
  const model = createGroundingEnforcedStylistModelV2({async turn() {
    return {kind: "tool_request", requests: [{tool: "wardrobe", scope: "full_relevant", category: null, editScope: null}], statePatch: {context: {groundingRequirements: {weatherRequired: true, weatherLocationField: "currentLocationObservation", terrainRequiredFields: []}}}};
  }}, policy);
  const envelope = await model.turn({phase: "plan", session: groundedState});
  assert.equal(envelope.statePatch.context.groundingRequirements.weatherLocationField, "eventLocation");
});

test("opinion and emoji greeting are classified without stealing real requests", () => {
  assert.equal(isConcreteOutfitRequestV2("tento outfit je ok?"), false);
  assert.equal(isGreetingV2("ahoj 💪"), true);
  assert.equal(isGreetingV2("ahoj, potrebujem outfit"), false);
});
