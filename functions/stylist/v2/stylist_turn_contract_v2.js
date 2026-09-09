"use strict";

const {clone, deepFreeze} = require("./stylist_session_state_v2");

const TURN_ACTIONS = new Set([
  "chat", "clarify", "generate_outfit", "edit_outfit",
  "explain_outfit", "show_items", "shop", "stop",
]);
const MUTATING_ACTIONS = new Set(["generate_outfit", "edit_outfit"]);
const REQUEST_KEYS = new Set([
  "chatId", "turnId", "expectedSessionRevision", "latestUserInput",
  "explicitUiActionId", "freshClientObservations", "clientCapabilities",
]);
const RESULT_KEYS = new Set([
  "turnId", "action", "assistantText", "resultingOutfit", "editScope", "clarification",
  "display", "shoppingResult", "quickReplies", "quickReplyPrompt", "resultingSessionRevision",
]);

function assertExactKeys(value, allowed, label) {
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) throw new TypeError(`${label} contains unsupported field ${key}`);
  }
}

function validateTurnRequestV2(request) {
  if (!request || typeof request !== "object") throw new TypeError("turn request is required");
  assertExactKeys(request, REQUEST_KEYS, "turn request");
  for (const field of ["chatId", "turnId"]) {
    if (typeof request[field] !== "string" || !request[field].trim()) throw new TypeError(`${field} is required`);
  }
  if (!Number.isInteger(request.expectedSessionRevision) || request.expectedSessionRevision < 0) {
    throw new TypeError("expectedSessionRevision must be a non-negative integer");
  }
  if (typeof request.latestUserInput !== "string") throw new TypeError("latestUserInput must be a string");
  if (!request.latestUserInput.trim() && !request.explicitUiActionId) {
    throw new TypeError("a user input or explicit UI action is required");
  }
  if (request.clientCapabilities == null || typeof request.clientCapabilities !== "object") {
    throw new TypeError("clientCapabilities is required");
  }
  const observations = request.freshClientObservations || {};
  assertExactKeys(observations, new Set(["currentLocationObservation"]), "freshClientObservations");
  return deepFreeze(clone({
    ...request,
    explicitUiActionId: request.explicitUiActionId || null,
    freshClientObservations: observations,
  }));
}

function normalizeCosmeticsV2(result) {
  const normalized = clone(result);
  normalized.assistantText = String(normalized.assistantText || "").replace(/\s+/g, " ").trim();
  normalized.quickReplies = (normalized.quickReplies || []).map((reply) => ({
    actionId: reply.actionId,
    label: String(reply.label || reply.actionId || "").trim(),
  })).sort((a, b) => a.actionId.localeCompare(b.actionId));
  if (normalized.quickReplyPrompt != null) {
    normalized.quickReplyPrompt = String(normalized.quickReplyPrompt).replace(/\s+/g, " ").trim();
  }
  if (normalized.display) {
    normalized.display.itemIds = [...new Set(normalized.display.itemIds || [])];
  }
  return normalized;
}

function validateTurnResultContractV2(rawResult, previousState) {
  const result = normalizeCosmeticsV2(rawResult);
  assertExactKeys(result, RESULT_KEYS, "turn result");
  if (typeof result.turnId !== "string" || !result.turnId) throw new TypeError("turnId is required in result");
  if (!TURN_ACTIONS.has(result.action)) throw new TypeError("invalid V2 turn action");
  if (!result.assistantText) throw new TypeError("assistantText is required");
  if (!Number.isInteger(result.resultingSessionRevision) || result.resultingSessionRevision < 0) {
    throw new TypeError("resultingSessionRevision is required");
  }
  if (!result.display || !["none", "outfit", "items", "shopping"].includes(result.display.kind)) {
    throw new TypeError("an explicit display directive is required");
  }
  if (!Array.isArray(result.display.itemIds) || !Array.isArray(result.quickReplies || [])) {
    throw new TypeError("display IDs and typed quick replies must be arrays");
  }
  if (result.display.kind === "none" && result.display.itemIds.length !== 0) {
    throw new TypeError("display none cannot contain item IDs");
  }
  if (new Set(result.quickReplies.map((reply) => reply.actionId)).size !== result.quickReplies.length) {
    throw new TypeError("quick reply action IDs must be unique");
  }
  if (result.quickReplyPrompt != null && (!result.quickReplyPrompt || result.quickReplies.length === 0)) {
    throw new TypeError("quickReplyPrompt requires at least one typed quick reply");
  }
  if (previousState && result.resultingSessionRevision !== previousState.revision + 1) {
    throw new TypeError("resulting session revision must advance exactly once");
  }
  for (const reply of result.quickReplies) {
    if (!reply.actionId || !reply.label) throw new TypeError("quick replies require typed actionId and label");
  }
  const priorIds = previousState ? previousState.currentOutfit.itemIds : [];
  const resultingIds = result.resultingOutfit ? result.resultingOutfit.itemIds : priorIds;
  if (!Array.isArray(resultingIds)) throw new TypeError("resulting outfit IDs must be an array");

  if (["chat", "clarify", "explain_outfit", "show_items", "shop", "stop"].includes(result.action) &&
      JSON.stringify(resultingIds) !== JSON.stringify(priorIds)) {
    throw new TypeError(`${result.action} cannot mutate the outfit`);
  }
  if (["chat", "clarify", "explain_outfit", "stop"].includes(result.action) && result.display.kind !== "none") {
    throw new TypeError(`${result.action} displays no cards by default`);
  }
  if (result.action === "clarify") {
    if (!result.clarification || !result.clarification.field || !result.clarification.question ||
        (result.clarification.question.match(/\?/g) || []).length !== 1) {
      throw new TypeError("clarify requires exactly one question");
    }
  } else if (result.clarification != null) {
    throw new TypeError("only clarify may contain a clarification");
  }
  if (MUTATING_ACTIONS.has(result.action)) {
    if (!result.resultingOutfit || resultingIds.length === 0) throw new TypeError("outfit mutation requires an exact outfit");
    for (const itemId of resultingIds) {
      const reason = result.resultingOutfit.selectionReasonsByItemId?.[itemId];
      const preservedUnknown = previousState?.currentOutfit.itemIds.includes(itemId) &&
        previousState.currentOutfit.selectionReasonsByItemId[itemId] === null && reason === null;
      if (!preservedUnknown && (typeof reason !== "string" || !reason.trim())) {
        throw new TypeError(`outfit result lacks selection reason for ${itemId}`);
      }
    }
  }
  if (result.action === "generate_outfit" && result.display.kind !== "outfit") {
    throw new TypeError("generate_outfit must explicitly display the authoritative outfit");
  }
  if (result.action === "edit_outfit" && (!result.editScope || !Array.isArray(result.editScope.replaceItemIds))) {
    throw new TypeError("edit_outfit requires an explicit edit scope");
  }
  if (result.action !== "edit_outfit" && result.editScope != null) {
    throw new TypeError("only edit_outfit may contain an edit scope");
  }
  if (result.action === "show_items" && result.display.kind === "none") {
    throw new TypeError("show_items requires an explicit card display");
  }
  if (result.action === "shop" && !result.shoppingResult) throw new TypeError("shop requires shoppingResult");
  if (result.action !== "shop" && result.shoppingResult != null) {
    throw new TypeError("only shop may contain shoppingResult");
  }
  return deepFreeze(result);
}

module.exports = {
  MUTATING_ACTIONS,
  TURN_ACTIONS,
  normalizeCosmeticsV2,
  validateTurnRequestV2,
  validateTurnResultContractV2,
};
