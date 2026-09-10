"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {clone, createEmptySessionStateV2, MAX_SCENARIO_SNAPSHOTS, validateStylistSessionStateV2} = require("./stylist_session_state_v2");
const {beginNewScenarioV2, hasExplicitScenarioBackreferenceV2, restoreScenarioSnapshotV2, upsertScenarioSnapshotV2} = require("./stylist_scenario_memory_v2");
const {inferMandatoryGroundingV2} = require("./stylist_grounding_policy_v2");
const {finalEnvelope, guardIndoorWeatherWordingV2, planEnvelope, shouldPreloadCurrentOutfitV2} = require("./openai_stylist_model_port_v2");
const {applySafeStatePatch, greetingDecision} = require("./stylist_turn_coordinator_v2");

function outfitState(chatId, activityId, activityLabel, itemId, options = {}) {
  const state = clone(createEmptySessionStateV2(chatId));
  state.context.activity = {id: activityId, label: activityLabel, source: "user"};
  state.context.date = {dateKey: options.dateKey || "2026-09-11", source: "user"};
  state.context.timeWindow = {key: "day", source: "help_first_default"};
  state.context.destination = options.destination || null;
  state.context.eventLocation = options.eventLocation || null;
  state.context.environment = options.environment ?? null;
  state.currentOutfit.itemIds = [itemId];
  state.currentOutfit.selectionReasonsByItemId = {[itemId]: `reason ${itemId}`};
  state.currentOutfit.revision = 1;
  return state;
}
function addScenario(state, activityId, activityLabel, itemId, options = {}, turnId = "turn") {
  let next = beginNewScenarioV2(state);
  next.context.activity = {id: activityId, label: activityLabel, source: "user"};
  next.context.date = {dateKey: options.dateKey || "2026-09-11", source: "user"};
  next.context.timeWindow = {key: "day", source: "help_first_default"};
  next.context.destination = options.destination || null;
  next.context.eventLocation = options.eventLocation || null;
  next.context.environment = options.environment ?? null;
  next.currentOutfit.itemIds = [itemId];
  next.currentOutfit.selectionReasonsByItemId = {[itemId]: `reason ${itemId}`};
  next.currentOutfit.revision += 1;
  return upsertScenarioSnapshotV2(next, {turnId});
}
function plannerRaw(mode, ref) {
  return {kind: "tool_request", action: "none", assistantText: "", clarificationField: null, clarificationQuestion: null,
    scenarioMode: mode, scenarioReferenceId: ref, locationQuery: null, locationTargetField: "none",
    wardrobeScope: "current_outfit_plus_category", wardrobeCategory: "tops", replaceItemIds: ["hike-shirt"], retainItemIds: [],
    allowedSlots: ["top"], allowedCategories: ["tops"], allowRemovalOnly: false,
    patch: {activityId: null, activityLabel: null, dateKey: null, timeWindowKey: null, environment: "unknown",
      terrainSurface: "unknown", terrainDifficulty: "unknown", terrainCondition: "unknown", replaceGroundingRequirements: false,
      weatherRequired: false, weatherLocationField: "none", terrainRequiredFields: []}};
}

test("A hiking/Tatry -> cinema -> back to hiking restores exact snapshot", () => {
  const tatry = {providerId: "place:tatry", label: "Vysoké Tatry"};
  let state = outfitState("a", "hiking", "túra", "hike-shirt", {destination: tatry, environment: "outdoor"});
  state = upsertScenarioSnapshotV2(state, {turnId: "hike"});
  const hikeId = state.scenarioMemory.activeScenarioId;
  state = addScenario(state, "cinema", "kino", "cinema-shirt", {environment: "indoor"}, "cinema");
  const message = "mohol by si mi ukázať outfit na tú túru ale s iným tričkom?";
  assert.equal(hasExplicitScenarioBackreferenceV2({latestUserInput: message, state}), true);
  const policy = inferMandatoryGroundingV2({latestUserInput: message, state});
  assert.equal(policy.scope, "scenario_reference");
  assert.equal(policy.resetContext, false);
  const envelope = planEnvelope(plannerRaw("restore", hikeId), {session: state, request: {latestUserInput: message}});
  const restored = applySafeStatePatch(state, envelope.statePatch);
  assert.equal(restored.context.activity.id, "hiking");
  assert.equal(restored.context.destination.label, "Vysoké Tatry");
  assert.deepEqual(restored.currentOutfit.itemIds, ["hike-shirt"]);
});

for (const fixture of [
  ["B interview -> dinner -> interview", ["job_interview", "pracovný pohovor", "interview-shirt"], ["dinner", "večera", "dinner-shirt"], "vráťme sa k pohovoru"],
  ["C wedding -> work -> wedding", ["wedding", "svadba", "wedding-shirt"], ["work", "práca", "work-shirt"], "ukáž ten svadobný outfit s inou košeľou"],
  ["D concert -> unrelated -> concert", ["concert", "koncert", "concert-shirt"], ["shopping", "nákup", "shopping-shirt"], "vráťme sa späť ku koncertu"],
]) test(fixture[0], () => {
  let state = outfitState("semantic", ...fixture[1]);
  state = upsertScenarioSnapshotV2(state, {turnId: "old"});
  const oldId = state.scenarioMemory.activeScenarioId;
  state = addScenario(state, ...fixture[2], {}, "current");
  assert.equal(hasExplicitScenarioBackreferenceV2({latestUserInput: fixture[3], state}), true);
  const restored = restoreScenarioSnapshotV2(state, oldId);
  assert.equal(restored.context.activity.id, fixture[1][0]);
  assert.deepEqual(restored.currentOutfit.itemIds, [fixture[1][2]]);
});

test("E/F/G indoor forecast wording is scoped outside", () => {
  for (const [text, forbidden] of [["V kine je 31 °C a sucho.", /v kine je 31/iu], ["V reštaurácii prší.", /reštaurácii prší/iu], ["V kancelárii bude 4 °C, zober si bundu.", /kancelárii bude 4/iu]]) {
    const guarded = guardIndoorWeatherWordingV2(text, "indoor");
    assert.match(guarded, /^Vonku /u); assert.doesNotMatch(guarded, forbidden);
  }
  assert.equal(guardIndoorWeatherWordingV2("V kine môže byť kvôli klimatizácii chladnejšie.", "indoor"), "V kine môže byť kvôli klimatizácii chladnejšie.");
  assert.equal(guardIndoorWeatherWordingV2("V kine bude klimatizácia.", "indoor"), "Vnútri môže byť kvôli klimatizácii chladnejšie.");
});

test("H/I shopping CTA describes store search and is separate", () => {
  const state = clone(createEmptySessionStateV2("shop"));
  const raw = {action: "generate_outfit", assistantText: "Tenisky sú kompromis. Chceš, aby som ti vybral vhodnejšie topánky?",
    resultingOutfitItemIds: ["shoe"], selectionReasons: [{itemId: "shoe", reason: "najpraktickejší dostupný pár"}],
    displayKind: "outfit", displayItemIds: ["shoe"], editReplaceItemIds: [], editRetainItemIds: [], editAllowedSlots: [],
    editAllowedCategories: [], editAllowRemovalOnly: false, clarificationField: null, clarificationQuestion: null,
    offerShopping: true, shoppingNeedLabel: "turistické topánky", shoppingNeedCanonicalType: "hiking_shoes",
    shoppingHardConstraints: [], shoppingSoftPreferences: []};
  const envelope = finalEnvelope(raw, {session: state, request: {turnId: "shop-turn"}, toolResults: {}});
  assert.equal(envelope.result.quickReplyPrompt, "Chceš, aby som ti pozrel vhodné topánky v obchodoch?");
  assert.deepEqual(envelope.result.quickReplies.map((reply) => reply.label), ["Áno", "Nie"]);
  assert.doesNotMatch(envelope.result.assistantText, /Chceš, aby som/iu);
});

test("J greeting is neutral", () => {
  assert.equal(greetingDecision().assistantText, "Ahoj! Ako ti môžem pomôcť?");
  assert.doesNotMatch(greetingDecision().assistantText, /outfit/iu);
});

test("L ordinary current edit does not select old scenario", () => {
  let state = outfitState("edit", "work", "práca", "shirt");
  state = upsertScenarioSnapshotV2(state, {turnId: "work"});
  state = addScenario(state, "dinner", "večera", "dinner-shirt", {}, "dinner");
  const message = "daj mi iné tričko";
  assert.equal(hasExplicitScenarioBackreferenceV2({latestUserInput: message, state}), false);
  assert.equal(shouldPreloadCurrentOutfitV2({request: {latestUserInput: message}, session: state}), true);
});

test("M existing session without scenario memory validates", () => {
  const legacy = clone(createEmptySessionStateV2("legacy"));
  delete legacy.scenarioMemory; delete legacy.context.environment;
  const validated = validateStylistSessionStateV2(legacy);
  assert.deepEqual(validated.scenarioMemory, {activeScenarioId: null, snapshots: []});
  assert.equal(validated.context.environment, null);
});

test("N scenario memory is bounded", () => {
  let state = clone(createEmptySessionStateV2("bounded"));
  for (let i = 0; i < MAX_SCENARIO_SNAPSHOTS + 4; i += 1) state = addScenario(state, `activity-${i}`, `activity ${i}`, `item-${i}`, {}, `turn-${i}`);
  assert.equal(state.scenarioMemory.snapshots.length, MAX_SCENARIO_SNAPSHOTS);
});
