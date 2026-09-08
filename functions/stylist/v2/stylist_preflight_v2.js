"use strict";

class StaleSessionRevisionError extends Error {
  constructor(expected, actual) {
    super(`stale session revision: expected ${expected}, actual ${actual}`);
    this.name = "StaleSessionRevisionError";
    this.code = "STALE_SESSION_REVISION";
    this.expected = expected;
    this.actual = actual;
  }
}

class AmbiguousAffirmationError extends Error {
  constructor() {
    super("binary reply has no single active referent");
    this.name = "AmbiguousAffirmationError";
    this.code = "BINARY_REPLY_WITHOUT_REFERENT";
  }
}

function normalizeUtterance(value) {
  return String(value || "").trim().toLocaleLowerCase("sk-SK")
    .replace(/[,.!?]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}
function isAffirmativeText(value) { return new Set(["áno", "ano", "hej", "jasné", "jasne"]).has(normalizeUtterance(value)); }
function isNegativeText(value) { return new Set(["nie", "nie ďakujem", "nie dakujem", "nechcem"]).has(normalizeUtterance(value)); }
function findReplay(state, turnId) { return state.replay.turns.find((entry) => entry.turnId === turnId) || null; }

function resolvePendingReferentV2(state, request) {
  const pending = [state.conversationMemory.pendingAction,
    state.conversationMemory.pendingQuestion?.acceptsYesNo ? state.conversationMemory.pendingQuestion : null].filter(Boolean);
  if (request.explicitUiActionId) {
    for (const entry of pending) {
      if (request.explicitUiActionId === entry.actionId || request.explicitUiActionId === `${entry.actionId}_yes`) {
        return {kind: entry.type === "question" ? "question" : "action", answer: "yes", pending: entry};
      }
      if (request.explicitUiActionId === `${entry.actionId}_no`) {
        return {kind: entry.type === "question" ? "question" : "action", answer: "no", pending: entry};
      }
    }
    throw new AmbiguousAffirmationError();
  }
  const answer = isAffirmativeText(request.latestUserInput) ? "yes" : isNegativeText(request.latestUserInput) ? "no" : null;
  if (!answer) return null;
  if (pending.length !== 1) throw new AmbiguousAffirmationError();
  return {kind: pending[0].type === "question" ? "question" : "action", answer, pending: pending[0]};
}

function runPreflightV2(state, request) {
  const replay = findReplay(state, request.turnId);
  if (replay) return {kind: "replay", result: replay.result};
  if (request.expectedSessionRevision !== state.revision) throw new StaleSessionRevisionError(request.expectedSessionRevision, state.revision);
  const pendingResolution = resolvePendingReferentV2(state, request);
  if (pendingResolution) return {kind: "pending", pendingKind: pendingResolution.kind, answer: pendingResolution.answer, pending: pendingResolution.pending};
  return {kind: "continue"};
}

function highestPriorityMissingGroundingV2(state) {
  const grounding = state.context.groundingRequirements;
  if (grounding.weatherLocationField && !state.context[grounding.weatherLocationField]) return grounding.weatherLocationField;
  if (grounding.weatherRequired) {
    if (!state.context.date) return "date";
    if (!state.context.timeWindow) return "timeWindow";
  }
  const missingTerrainField = grounding.terrainRequiredFields.find((field) => state.context.terrain[field] == null);
  if (missingTerrainField) return `terrain.${missingTerrainField}`;
  return null;
}

module.exports = {AmbiguousAffirmationError, StaleSessionRevisionError, highestPriorityMissingGroundingV2,
  isAffirmativeText, isNegativeText, resolvePendingReferentV2, runPreflightV2};
