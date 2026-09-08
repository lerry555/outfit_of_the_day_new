"use strict";

const {validateTurnResultContractV2} = require("./stylist_turn_contract_v2");

class SafetyCriticalTurnError extends Error {
  constructor(message, details = {}) {
    super(message);
    this.name = "SafetyCriticalTurnError";
    this.code = "SAFETY_CRITICAL";
    this.disposition = details.canClarify ? "clarify" : "stop";
    this.details = details;
  }
}

class RepairableStructuralTurnError extends Error {
  constructor(message, details = {}) {
    super(message);
    this.name = "RepairableStructuralTurnError";
    this.code = "REPAIRABLE_STRUCTURAL";
    this.maxFutureCorrectionAttempts = 1;
    this.details = details;
  }
}

function sameMembers(left, right) {
  return left.length === right.length && left.every((value) => right.includes(value));
}

function validateWeatherAuthority(state) {
  const {activity, destination, date, timeWindow, weather} = state.context;
  if (activity?.id !== "hiking") return;
  if (!destination) {
    throw new SafetyCriticalTurnError("hiking generation requires a destination", {canClarify: true, field: "destination"});
  }
  if (!weather || weather.locationProviderId !== destination.providerId ||
      weather.dateKey !== date?.dateKey || weather.timeWindowKey !== timeWindow?.key) {
    throw new SafetyCriticalTurnError("weather provenance does not match destination/date/time", {
      canClarify: true,
      field: "weather",
    });
  }
}

function validateSafetyCriticalFootwear(state, resultingIds, wardrobeItems) {
  const {terrain, activity} = state.context;
  if (activity?.id !== "hiking") return;
  const requiresTechnicalFootwear = ["steep", "technical"].includes(terrain.difficulty) ||
    ["wet", "muddy", "snow", "ice"].includes(terrain.condition) || terrain.surface === "rock";
  if (!requiresTechnicalFootwear) return;
  const selected = wardrobeItems.filter((item) => resultingIds.includes(item.id));
  if (!selected.some((item) => item.category === "footwear" && item.safety?.hikingTechnical === true)) {
    throw new SafetyCriticalTurnError("unsafe footwear violates the terrain hard constraint", {
      canClarify: false,
      field: "footwear",
    });
  }
}

function validateAuthoritativeTurnV2({rawResult, previousState, proposedState, wardrobeItems = []}) {
  let result;
  try {
    result = validateTurnResultContractV2(rawResult, previousState);
  } catch (error) {
    throw new RepairableStructuralTurnError(error.message, {cause: error});
  }

  const resultingIds = result.resultingOutfit?.itemIds || previousState.currentOutfit.itemIds;
  if (result.display.kind === "outfit" &&
      !result.display.itemIds.every((itemId) => resultingIds.includes(itemId))) {
    throw new RepairableStructuralTurnError("display IDs diverge from the authoritative resulting outfit");
  }
  if (result.display.kind === "items") {
    const allowedDisplayIds = result.action === "show_items" ?
      wardrobeItems.map((item) => item.id) : resultingIds;
    if (!result.display.itemIds.every((itemId) => allowedDisplayIds.includes(itemId))) {
      throw new RepairableStructuralTurnError("item cards diverge from the authoritative result scope");
    }
  }
  if (result.display.kind === "outfit" && !sameMembers(result.display.itemIds, resultingIds)) {
    throw new RepairableStructuralTurnError("outfit cards must exactly match authoritative outfit IDs");
  }

  if (["generate_outfit", "edit_outfit"].includes(result.action)) {
    const knownIds = new Set([
      ...previousState.currentOutfit.itemIds,
      ...wardrobeItems.map((item) => item.id),
    ]);
    if (resultingIds.some((itemId) => !knownIds.has(itemId))) {
      throw new SafetyCriticalTurnError("outfit references an unknown wardrobe item");
    }
    validateWeatherAuthority(proposedState);
    validateSafetyCriticalFootwear(proposedState, resultingIds, wardrobeItems);
    for (const itemId of previousState.currentOutfit.itemIds.filter((id) => resultingIds.includes(id))) {
      const oldReason = previousState.currentOutfit.selectionReasonsByItemId[itemId];
      const newReason = result.resultingOutfit.selectionReasonsByItemId[itemId];
      if (oldReason !== newReason) {
        throw new SafetyCriticalTurnError("retained item selection reason cannot be rewritten");
      }
    }
  }

  if (result.action === "edit_outfit") {
    const replaceIds = new Set(result.editScope.replaceItemIds);
    const preserved = previousState.currentOutfit.itemIds.filter((itemId) => !replaceIds.has(itemId));
    if (!preserved.every((itemId) => resultingIds.includes(itemId))) {
      throw new SafetyCriticalTurnError("edit changed an item outside the requested scope");
    }
  }

  if (result.action === "shop") {
    const expected = proposedState.shopping.hardConstraints;
    const applied = result.shoppingResult.appliedHardConstraints || [];
    if (!sameMembers(expected, applied)) {
      throw new SafetyCriticalTurnError("shopping silently relaxed a hard constraint");
    }
  }
  return result;
}

const VALIDATOR_BOUNDARIES_V2 = Object.freeze({
  safetyCritical: "reject mutation and either clarify or stop",
  repairableStructural: "allow at most one constrained correction in a future model runtime",
  cosmetic: "normalize locally without a model call",
  subjectiveQuality: "outside deterministic validation; evaluate with model-quality fixtures",
});

module.exports = {
  RepairableStructuralTurnError,
  SafetyCriticalTurnError,
  VALIDATOR_BOUNDARIES_V2,
  validateAuthoritativeTurnV2,
};
