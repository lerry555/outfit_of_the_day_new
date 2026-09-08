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
    super("affirmation has no single active referent");
    this.name = "AmbiguousAffirmationError";
    this.code = "AFFIRMATION_WITHOUT_REFERENT";
  }
}

function normalizeUtterance(value) {
  return String(value || "").trim().toLocaleLowerCase("sk-SK").replace(/[.!?]+$/g, "");
}

function isAffirmativeText(value) {
  return new Set(["áno", "ano", "hej", "jasné", "jasne"]).has(normalizeUtterance(value));
}

function findReplay(state, turnId) {
  return state.replay.turns.find((entry) => entry.turnId === turnId) || null;
}

function resolvePendingReferentV2(state, request) {
  const pending = [
    state.conversationMemory.pendingAction,
    state.conversationMemory.pendingQuestion?.acceptsYesNo ? state.conversationMemory.pendingQuestion : null,
  ].filter(Boolean);

  if (request.explicitUiActionId) {
    const match = pending.find((entry) => entry.actionId === request.explicitUiActionId);
    if (!match) throw new AmbiguousAffirmationError();
    return {kind: match.type === "question" ? "question" : "action", pending: match};
  }
  if (!isAffirmativeText(request.latestUserInput)) return null;
  if (pending.length !== 1) throw new AmbiguousAffirmationError();
  return {kind: pending[0].type === "question" ? "question" : "action", pending: pending[0]};
}

function runPreflightV2(state, request) {
  const replay = findReplay(state, request.turnId);
  if (replay) return {kind: "replay", result: replay.result};
  if (request.expectedSessionRevision !== state.revision) {
    throw new StaleSessionRevisionError(request.expectedSessionRevision, state.revision);
  }
  const pendingResolution = resolvePendingReferentV2(state, request);
  if (pendingResolution) {
    return {kind: "pending", pendingKind: pendingResolution.kind, pending: pendingResolution.pending};
  }
  return {kind: "continue"};
}

function highestPriorityMissingGroundingV2(state) {
  if (state.context.activity?.id === "hiking" && !state.context.destination) return "destination";
  if (state.context.activity?.id === "hiking") {
    if (!state.context.date) return "date";
    if (!state.context.timeWindow) return "timeWindow";
    const terrain = state.context.terrain;
    if (terrain.surface == null || terrain.difficulty == null || terrain.condition == null) return "terrain";
  }
  return null;
}

module.exports = {
  AmbiguousAffirmationError,
  StaleSessionRevisionError,
  highestPriorityMissingGroundingV2,
  isAffirmativeText,
  resolvePendingReferentV2,
  runPreflightV2,
};
