"use strict";

const MAX_HISTORY = 50;
const MAX_COLLECTION = 100;

const TERRAIN_SURFACES = new Set([null, "paved", "trail", "grass", "forest_floor", "rock"]);
const TERRAIN_DIFFICULTIES = new Set([null, "easy", "moderate", "steep", "technical"]);
const TERRAIN_CONDITIONS = new Set([null, "dry", "wet", "muddy", "snow", "ice"]);

function clone(value) { return value == null ? value : JSON.parse(JSON.stringify(value)); }
function deepFreeze(value) {
  if (!value || typeof value !== "object" || Object.isFrozen(value)) return value;
  Object.freeze(value); for (const child of Object.values(value)) deepFreeze(child); return value;
}
function bounded(values, limit = MAX_COLLECTION) { return [...new Set(Array.isArray(values) ? values : [])].slice(-limit); }
function emptyTerrain() { return {surface: null, difficulty: null, condition: null}; }

function createEmptySessionStateV2(chatId) {
  if (typeof chatId !== "string" || !chatId.trim()) throw new TypeError("chatId is required");
  return deepFreeze({
    schemaVersion: 2, chatId: chatId.trim(), revision: 0,
    context: {
      currentLocationObservation: null, destination: null, eventLocation: null, date: null, timeWindow: null,
      activity: null, terrain: emptyTerrain(), weather: null,
      groundingRequirements: {weatherRequired: false, weatherLocationField: null, terrainRequiredFields: []},
    },
    currentOutfit: {itemIds: [], selectionReasonsByItemId: {}, revision: 0, compromises: [], missingWardrobeNeeds: [], selectionReasonHistory: []},
    conversationMemory: {pendingQuestion: null, pendingAction: null, answeredClarificationFields: {}, communicatedWarnings: [], rejectedWardrobeItemIds: [], rejectedShoppingOptionIds: [], userCorrections: [], acceptedCompromises: []},
    shopping: {missingNeed: null, hardConstraints: [], softPreferences: [], size: null, budget: null, brandPreferences: {preferred: [], blocked: []}, rejectedCandidateIds: [], openedReason: null},
    wardrobePreferences: {wardrobeRevision: null, preferencesRevision: null, retrievalCache: null},
    replay: {turns: []},
  });
}

function validateLocationObservation(value, fieldName) {
  if (value == null) return;
  if (typeof value !== "object" || !value.providerId || !value.label) throw new TypeError(`${fieldName} requires providerId and label`);
  if (fieldName === "currentLocationObservation" && !value.observedAt) throw new TypeError("current GPS location requires observedAt freshness metadata");
}

function validateStylistSessionStateV2(state) {
  if (!state || state.schemaVersion !== 2 || typeof state.chatId !== "string") throw new TypeError("invalid StylistSessionStateV2 identity");
  if (!Number.isInteger(state.revision) || state.revision < 0) throw new TypeError("invalid session revision");
  validateLocationObservation(state.context.currentLocationObservation, "currentLocationObservation");
  validateLocationObservation(state.context.destination, "destination");
  validateLocationObservation(state.context.eventLocation, "eventLocation");
  const terrain = state.context.terrain;
  if (!terrain || !TERRAIN_SURFACES.has(terrain.surface) || !TERRAIN_DIFFICULTIES.has(terrain.difficulty) || !TERRAIN_CONDITIONS.has(terrain.condition)) {
    throw new TypeError("terrain must keep surface, difficulty, and condition orthogonal");
  }
  const weather = state.context.weather;
  if (weather != null && (!weather.locationProviderId || !weather.dateKey || !weather.timeWindowKey || !weather.fetchedAt || !weather.source)) {
    throw new TypeError("weather requires location/date/time provenance");
  }
  const grounding = state.context.groundingRequirements;
  if (!grounding || typeof grounding.weatherRequired !== "boolean" ||
      ![null, "currentLocationObservation", "destination", "eventLocation"].includes(grounding.weatherLocationField) ||
      !Array.isArray(grounding.terrainRequiredFields) ||
      grounding.terrainRequiredFields.some((field) => !["surface", "difficulty", "condition"].includes(field)) ||
      new Set(grounding.terrainRequiredFields).size !== grounding.terrainRequiredFields.length) {
    throw new TypeError("invalid material grounding requirements");
  }
  if (grounding.weatherRequired && grounding.weatherLocationField == null) throw new TypeError("weather grounding requires an authoritative location field");
  const outfit = state.currentOutfit;
  if (!Array.isArray(outfit.itemIds) || new Set(outfit.itemIds).size !== outfit.itemIds.length) throw new TypeError("current outfit item IDs must be unique");
  if (outfit.itemIds.length > MAX_COLLECTION || !sameStringMembers(Object.keys(outfit.selectionReasonsByItemId), outfit.itemIds)) throw new TypeError("selection reason keys must exactly match the bounded current outfit");
  for (const itemId of outfit.itemIds) {
    const reason = outfit.selectionReasonsByItemId[itemId];
    if (reason !== null && (typeof reason !== "string" || !reason.trim())) throw new TypeError(`invalid persisted selection reason for ${itemId}`);
  }
  const boundedCollections = [outfit.compromises, outfit.missingWardrobeNeeds, outfit.selectionReasonHistory,
    state.conversationMemory.communicatedWarnings, state.conversationMemory.rejectedWardrobeItemIds,
    state.conversationMemory.rejectedShoppingOptionIds, state.conversationMemory.userCorrections,
    state.conversationMemory.acceptedCompromises, state.shopping.hardConstraints, state.shopping.softPreferences,
    state.shopping.rejectedCandidateIds, state.replay.turns];
  if (boundedCollections.some((values) => !Array.isArray(values) || values.length > MAX_COLLECTION)) throw new TypeError("session collections must be bounded");
  if (state.replay.turns.length > MAX_HISTORY) throw new TypeError("turn replay history is too large");
  if (Object.keys(state.conversationMemory.answeredClarificationFields).length > MAX_COLLECTION ||
      state.shopping.brandPreferences.preferred.length > MAX_COLLECTION || state.shopping.brandPreferences.blocked.length > MAX_COLLECTION) {
    throw new TypeError("session maps and brand collections must be bounded");
  }
  const pendingAction = state.conversationMemory.pendingAction;
  if (pendingAction != null && (pendingAction.type !== "action" || !pendingAction.kind || !pendingAction.actionId)) throw new TypeError("pendingAction requires one typed actionId referent");
  const pendingQuestion = state.conversationMemory.pendingQuestion;
  if (pendingQuestion != null && (pendingQuestion.type !== "question" || !pendingQuestion.field || !pendingQuestion.question || !pendingQuestion.actionId)) throw new TypeError("pendingQuestion requires one typed question referent");
  return deepFreeze(clone(state));
}

function sameStringMembers(left, right) { return left.length === right.length && left.every((value) => right.includes(value)); }

function bootstrapExistingChatV2(input) {
  const state = clone(createEmptySessionStateV2(input.chatId));
  const ids = bounded(input.currentOutfitItemIds);
  const persistedReasons = input.persistedSelectionReasonsByItemId || {};
  state.currentOutfit.itemIds = ids;
  state.currentOutfit.selectionReasonsByItemId = Object.fromEntries(ids.map((itemId) => {
    const reason = persistedReasons[itemId]; return [itemId, typeof reason === "string" && reason.trim() ? reason.trim() : null];
  }));
  state.currentOutfit.revision = ids.length ? 1 : 0;
  const durable = input.knownExplicitDurableChoices || {};
  state.context.activity = durable.activity ? clone(durable.activity) : null;
  state.context.date = durable.date ? clone(durable.date) : null;
  state.context.timeWindow = durable.timeWindow ? clone(durable.timeWindow) : null;
  state.currentOutfit.compromises = bounded(durable.acceptedCompromises);
  state.conversationMemory.acceptedCompromises = bounded(durable.acceptedCompromises);
  state.conversationMemory.rejectedWardrobeItemIds = bounded(durable.rejectedWardrobeItemIds);
  state.conversationMemory.rejectedShoppingOptionIds = bounded(durable.rejectedShoppingOptionIds);
  state.conversationMemory.userCorrections = bounded(durable.userCorrections);
  state.context.destination = null; state.context.terrain = emptyTerrain(); state.context.weather = null;
  state.context.groundingRequirements = {weatherRequired: false, weatherLocationField: null, terrainRequiredFields: []};
  state.conversationMemory.pendingAction = null; state.conversationMemory.pendingQuestion = null;
  return validateStylistSessionStateV2(state);
}

module.exports = {MAX_COLLECTION, MAX_HISTORY, TERRAIN_SURFACES, TERRAIN_DIFFICULTIES, TERRAIN_CONDITIONS,
  bootstrapExistingChatV2, bounded, clone, createEmptySessionStateV2, deepFreeze, emptyTerrain, validateStylistSessionStateV2};
