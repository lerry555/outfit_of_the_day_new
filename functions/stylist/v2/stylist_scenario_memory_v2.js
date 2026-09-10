"use strict";

const {MAX_SCENARIO_SNAPSHOTS, bounded, clone, emptyTerrain} = require("./stylist_session_state_v2");

const RELEVANT_ANSWERED_FIELDS = [
  "destination", "eventLocation", "date", "timeWindow",
  "terrain.surface", "terrain.difficulty", "terrain.condition",
];

function normalizeSemanticTextV2(value) {
  return String(value || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
    .replace(/[^a-z0-9]+/g, " ").replace(/\s+/g, " ").trim();
}
function cleanSignalV2(value, max = 180) {
  const text = String(value || "").trim().replace(/\s+/g, " ");
  return text ? text.slice(0, max) : "";
}
function snapshotReferenceSignalsV2(state) {
  const context = state?.context || {};
  const raw = [context.activity?.id, context.activity?.label, context.destination?.label,
    context.eventLocation?.label, context.date?.dateKey, context.timeWindow?.key, context.timeWindow?.label]
    .map((value) => cleanSignalV2(value)).filter(Boolean);
  return [...new Set(raw)].slice(0, 20);
}
function scenarioLabelV2(state) {
  const context = state?.context || {};
  const parts = [context.activity?.label || context.activity?.id, context.eventLocation?.label || context.destination?.label,
    context.date?.dateKey, context.timeWindow?.label || context.timeWindow?.key]
    .map((value) => cleanSignalV2(value, 100)).filter(Boolean);
  return parts.join(" · ").slice(0, 280) || "outfit scenario";
}
function snapshotFromStateV2(state, id) {
  const weather = state?.context?.weather;
  return {
    id, label: scenarioLabelV2(state), referenceSignals: snapshotReferenceSignalsV2(state),
    context: {
      activity: clone(state.context.activity), date: clone(state.context.date), timeWindow: clone(state.context.timeWindow),
      destination: clone(state.context.destination), eventLocation: clone(state.context.eventLocation),
      terrain: clone(state.context.terrain || emptyTerrain()), environment: state.context.environment ?? null,
      groundingRequirements: clone(state.context.groundingRequirements),
    },
    weatherReference: weather ? {locationProviderId: weather.locationProviderId, dateKey: weather.dateKey,
      timeWindowKey: weather.timeWindowKey, fetchedAt: weather.fetchedAt, source: weather.source} : null,
    outfit: {itemIds: [...state.currentOutfit.itemIds], selectionReasonsByItemId: {...state.currentOutfit.selectionReasonsByItemId},
      compromises: bounded(state.currentOutfit.compromises), missingWardrobeNeeds: bounded(state.currentOutfit.missingWardrobeNeeds)},
    updatedAtRevision: state.revision,
  };
}
function scenarioIdForTurnV2(state, turnId) {
  const safeTurn = cleanSignalV2(turnId, 100).replace(/[^A-Za-z0-9_-]/g, "_");
  const seed = safeTurn || `r${Number.isInteger(state?.revision) ? state.revision : 0}`;
  let candidate = `scenario_${seed}`;
  const ids = new Set(state.scenarioMemory.snapshots.map((snapshot) => snapshot.id));
  let suffix = 2;
  while (ids.has(candidate)) candidate = `scenario_${seed}_${suffix++}`;
  return candidate;
}
function upsertScenarioSnapshotV2(state, {turnId = null} = {}) {
  const next = clone(state);
  if (!next.currentOutfit?.itemIds?.length) return next;
  const snapshots = Array.isArray(next.scenarioMemory?.snapshots) ? [...next.scenarioMemory.snapshots] : [];
  const activeId = next.scenarioMemory?.activeScenarioId;
  const activeIndex = activeId ? snapshots.findIndex((snapshot) => snapshot.id === activeId) : -1;
  const id = activeIndex >= 0 ? activeId : scenarioIdForTurnV2(next, turnId);
  const snapshot = snapshotFromStateV2(next, id);
  if (activeIndex >= 0) snapshots.splice(activeIndex, 1);
  snapshots.push(snapshot);
  next.scenarioMemory = {activeScenarioId: id, snapshots: snapshots.slice(-MAX_SCENARIO_SNAPSHOTS)};
  return next;
}
function clearScenarioClarificationsV2(next) {
  const answered = next.conversationMemory?.answeredClarificationFields;
  if (answered && typeof answered === "object") for (const key of RELEVANT_ANSWERED_FIELDS) delete answered[key];
  next.conversationMemory.pendingQuestion = null;
  next.conversationMemory.pendingAction = null;
}
function beginNewScenarioV2(state) {
  const next = clone(state);
  const currentLocationObservation = clone(next.context.currentLocationObservation);
  next.context = {currentLocationObservation, destination: null, eventLocation: null, date: null, timeWindow: null,
    activity: null, environment: null, terrain: emptyTerrain(), weather: null,
    groundingRequirements: {weatherRequired: false, weatherLocationField: null, terrainRequiredFields: []}};
  next.currentOutfit = {...next.currentOutfit, itemIds: [], selectionReasonsByItemId: {}, compromises: [], missingWardrobeNeeds: []};
  next.scenarioMemory = next.scenarioMemory || {activeScenarioId: null, snapshots: []};
  next.scenarioMemory.activeScenarioId = null;
  clearScenarioClarificationsV2(next);
  return next;
}
function restoreScenarioSnapshotV2(state, scenarioId) {
  const next = clone(state);
  const snapshot = next.scenarioMemory?.snapshots?.find((entry) => entry.id === scenarioId);
  if (!snapshot) return next;
  const context = snapshot.context || {};
  next.context.activity = clone(context.activity); next.context.date = clone(context.date);
  next.context.timeWindow = clone(context.timeWindow); next.context.destination = clone(context.destination);
  next.context.eventLocation = clone(context.eventLocation); next.context.terrain = clone(context.terrain || emptyTerrain());
  next.context.environment = context.environment ?? null;
  next.context.groundingRequirements = clone(context.groundingRequirements || {weatherRequired: false, weatherLocationField: null, terrainRequiredFields: []});
  next.context.weather = null;
  next.currentOutfit.itemIds = [...snapshot.outfit.itemIds];
  next.currentOutfit.selectionReasonsByItemId = {...snapshot.outfit.selectionReasonsByItemId};
  next.currentOutfit.compromises = bounded(snapshot.outfit.compromises);
  next.currentOutfit.missingWardrobeNeeds = bounded(snapshot.outfit.missingWardrobeNeeds);
  clearScenarioClarificationsV2(next);
  const answered = next.conversationMemory.answeredClarificationFields;
  if (next.context.destination) answered.destination = clone(next.context.destination);
  if (next.context.eventLocation) answered.eventLocation = clone(next.context.eventLocation);
  if (next.context.date) answered.date = clone(next.context.date);
  if (next.context.timeWindow) answered.timeWindow = clone(next.context.timeWindow);
  for (const field of ["surface", "difficulty", "condition"]) if (next.context.terrain?.[field] != null) answered[`terrain.${field}`] = next.context.terrain[field];
  next.scenarioMemory.activeScenarioId = snapshot.id;
  return next;
}
function rootsForTextV2(value) {
  return new Set(normalizeSemanticTextV2(value).split(" ").filter((token) => token.length >= 4).map((token) => token.slice(0, 3)));
}
function hasExplicitScenarioBackreferenceV2({latestUserInput, state}) {
  const memory = state?.scenarioMemory;
  if (!memory || !Array.isArray(memory.snapshots) || !memory.snapshots.length) return false;
  const candidates = memory.snapshots.filter((snapshot) => snapshot.id !== memory.activeScenarioId);
  if (!candidates.length) return false;
  const text = normalizeSemanticTextV2(latestUserInput);
  if (!text) return false;
  if (/\b(vratme sa|vrat sa|spat k|spat ku|predchadzajuc|stars scenar|co sme riesili|co sme mali)\b/.test(text)) return true;
  if (!/\b(ten|tento|tato|tuto|tu|to|tamten|tamtu|predchadzajuci|predchadzajucu|starsiu|starsi)\b/.test(text)) return false;
  const messageRoots = rootsForTextV2(text);
  return candidates.some((snapshot) => {
    const snapshotRoots = rootsForTextV2([snapshot.label, ...(snapshot.referenceSignals || [])].join(" "));
    return [...messageRoots].some((root) => snapshotRoots.has(root));
  });
}
module.exports = {beginNewScenarioV2, hasExplicitScenarioBackreferenceV2, restoreScenarioSnapshotV2,
  scenarioLabelV2, snapshotReferenceSignalsV2, upsertScenarioSnapshotV2};
