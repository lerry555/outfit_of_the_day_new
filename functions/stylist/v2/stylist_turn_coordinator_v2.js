"use strict";

const {
  MAX_HISTORY,
  bounded,
  clone,
  validateStylistSessionStateV2,
} = require("./stylist_session_state_v2");
const {validateTurnRequestV2} = require("./stylist_turn_contract_v2");
const {highestPriorityMissingGroundingV2, runPreflightV2} = require("./stylist_preflight_v2");
const {validateAuthoritativeTurnV2} = require("./stylist_turn_validator_v2");

const GREETINGS = new Set(["ahoj", "čau", "cau", "dobrý deň", "dobry den"]);
const LOCATION_FRESHNESS_MS = 30 * 60 * 1000;

function isFreshLocationObservation(observation, nowMs) {
  if (!observation?.observedAt) return false;
  const observedMs = Date.parse(observation.observedAt);
  return Number.isFinite(observedMs) && observedMs <= nowMs && nowMs - observedMs <= LOCATION_FRESHNESS_MS;
}

function unchangedOutfit(state) {
  return {
    itemIds: [...state.currentOutfit.itemIds],
    selectionReasonsByItemId: {...state.currentOutfit.selectionReasonsByItemId},
  };
}

function normalizeDecision(decision, state, resultingRevision) {
  const raw = clone(decision);
  delete raw.statePatch;
  delete raw.retrievalScope;
  delete raw.retrievalCategory;
  raw.resultingSessionRevision = resultingRevision;
  raw.resultingOutfit = raw.resultingOutfit || unchangedOutfit(state);
  raw.quickReplies = raw.quickReplies || [];
  raw.clarification = raw.clarification || null;
  raw.editScope = raw.editScope || null;
  raw.shoppingResult = raw.shoppingResult || null;
  return raw;
}

function applySafeStatePatch(state, statePatch = {}) {
  const next = clone(state);
  const context = statePatch.context || {};
  for (const key of ["activity", "date", "timeWindow", "terrain", "eventLocation"]) {
    if (Object.prototype.hasOwnProperty.call(context, key)) next.context[key] = clone(context[key]);
  }
  // Destination and weather are intentionally excluded: only their tools may author them.
  const memory = statePatch.conversationMemory || {};
  for (const key of ["communicatedWarnings", "rejectedWardrobeItemIds", "rejectedShoppingOptionIds",
    "userCorrections", "acceptedCompromises"]) {
    if (Object.prototype.hasOwnProperty.call(memory, key)) next.conversationMemory[key] = bounded(memory[key]);
  }
  if (Object.prototype.hasOwnProperty.call(statePatch, "pendingAction")) {
    next.conversationMemory.pendingAction = clone(statePatch.pendingAction);
  }
  if (statePatch.shopping) next.shopping = {...next.shopping, ...clone(statePatch.shopping)};
  return next;
}

function applyAcceptedResult(state, result) {
  const next = clone(state);
  next.revision = result.resultingSessionRevision;
  if (["generate_outfit", "edit_outfit"].includes(result.action)) {
    const old = state.currentOutfit;
    const incoming = result.resultingOutfit;
    const removed = old.itemIds.filter((itemId) => !incoming.itemIds.includes(itemId));
    next.currentOutfit.selectionReasonHistory = [
      ...old.selectionReasonHistory,
      ...removed.map((itemId) => ({
        itemId,
        reason: old.selectionReasonsByItemId[itemId],
        outfitRevision: old.revision,
      })),
    ].slice(-MAX_HISTORY);
    next.currentOutfit.itemIds = [...incoming.itemIds];
    next.currentOutfit.selectionReasonsByItemId = {...incoming.selectionReasonsByItemId};
    next.currentOutfit.revision = old.revision + 1;
    next.currentOutfit.compromises = bounded(incoming.compromises || old.compromises);
    next.currentOutfit.missingWardrobeNeeds = bounded(incoming.missingWardrobeNeeds || old.missingWardrobeNeeds);
  }
  if (result.action === "clarify") {
    next.conversationMemory.pendingQuestion = {
      type: "question",
      actionId: result.clarification.actionId,
      field: result.clarification.field,
      question: result.clarification.question,
      acceptsYesNo: Boolean(result.clarification.acceptsYesNo),
    };
  } else {
    next.conversationMemory.pendingQuestion = null;
  }
  if (result.action === "shop") next.conversationMemory.pendingAction = null;
  next.replay.turns = [...next.replay.turns, {turnId: result.turnId, result: clone(result)}].slice(-MAX_HISTORY);
  return validateStylistSessionStateV2(next);
}

function clarificationDecision(field) {
  if (field === "destination") {
    return {
      action: "clarify",
      assistantText: "Kam presne ideš na túru?",
      clarification: {field, question: "Kam presne ideš na túru?", actionId: "clarify_destination"},
      display: {kind: "none", itemIds: []},
    };
  }
  if (field === "date") {
    return {
      action: "clarify",
      assistantText: "Na ktorý deň outfit potrebuješ?",
      clarification: {field, question: "Na ktorý deň outfit potrebuješ?", actionId: "clarify_date"},
      display: {kind: "none", itemIds: []},
    };
  }
  if (field === "timeWindow") {
    return {
      action: "clarify",
      assistantText: "V ktorej časti dňa budeš na túre?",
      clarification: {field, question: "V ktorej časti dňa budeš na túre?", actionId: "clarify_time_window"},
      display: {kind: "none", itemIds: []},
    };
  }
  return {
    action: "clarify",
    assistantText: "Aký bude povrch, náročnosť a stav trasy?",
    clarification: {field, question: "Aký bude povrch, náročnosť a stav trasy?", actionId: "clarify_terrain"},
    display: {kind: "none", itemIds: []},
  };
}

function greetingDecision() {
  return {
    action: "chat",
    assistantText: "Ahoj! Ako ti môžem pomôcť s outfitom?",
    display: {kind: "none", itemIds: []},
  };
}

async function refreshWeatherIfGrounded(state, weatherTool) {
  const next = clone(state);
  const {destination, date, timeWindow, weather} = next.context;
  if (!destination || !date || !timeWindow) return next;
  if (weather?.locationProviderId === destination.providerId && weather.dateKey === date.dateKey &&
      weather.timeWindowKey === timeWindow.key) return next;
  next.context.weather = await weatherTool.getForecast({location: destination, date, timeWindow});
  return next;
}

function shoppingContext(state, pending) {
  return {
    actionId: pending.actionId,
    activity: clone(state.context.activity),
    destination: clone(state.context.destination),
    weather: clone(state.context.weather),
    terrain: clone(state.context.terrain),
    missingNeed: clone(state.shopping.missingNeed || state.currentOutfit.missingWardrobeNeeds[0] || null),
    hardConstraints: clone(state.shopping.hardConstraints),
    softPreferences: clone(state.shopping.softPreferences),
    size: clone(state.shopping.size),
    budget: clone(state.shopping.budget),
    brandPreferences: clone(state.shopping.brandPreferences),
    rejectedCandidateIds: clone(state.shopping.rejectedCandidateIds),
    openedReason: state.shopping.openedReason,
    currentOutfit: unchangedOutfit(state),
  };
}

function createStylistTurnCoordinatorV2({sessionRepository, wardrobeTool, locationResolver,
  weatherTool, shoppingTool, stylistModel, clock = () => Date.now()}) {
  if (!sessionRepository || !wardrobeTool || !locationResolver || !weatherTool || !shoppingTool || !stylistModel) {
    throw new TypeError("all Phase-0 ports are required");
  }

  return {
    async resolveTurn(untrustedRequest) {
      const request = validateTurnRequestV2(untrustedRequest);
      const originalState = validateStylistSessionStateV2(await sessionRepository.read(request.chatId));
      const preflight = runPreflightV2(originalState, request);
      if (preflight.kind === "replay") return clone(preflight.result);

      let workingState = clone(originalState);
      const observation = request.freshClientObservations.currentLocationObservation;
      if (observation && isFreshLocationObservation(observation, clock())) {
        workingState.context.currentLocationObservation = clone(observation);
      }

      let decision;
      let wardrobeItems = [];

      if (preflight.kind === "pending" && preflight.pendingKind !== "question" &&
          preflight.pending.kind === "shopping") {
        const context = shoppingContext(workingState, preflight.pending);
        const shoppingResult = await shoppingTool.search(context);
        decision = {
          action: "shop",
          assistantText: "Pozrel som možnosti podľa tvojich uložených požiadaviek.",
          display: {kind: "shopping", itemIds: shoppingResult.candidateIds || []},
          shoppingResult,
        };
      } else if (workingState.conversationMemory.pendingQuestion?.field === "destination") {
        const destination = await locationResolver.resolve(request.latestUserInput.trim());
        if (!destination) {
          decision = clarificationDecision("destination");
        } else {
          workingState.context.destination = destination;
          workingState.conversationMemory.answeredClarificationFields.destination = clone(destination);
          workingState.conversationMemory.pendingQuestion = null;
          workingState = await refreshWeatherIfGrounded(workingState, weatherTool);
          decision = clarificationDecision(highestPriorityMissingGroundingV2(workingState) || "terrain");
        }
      } else if (GREETINGS.has(request.latestUserInput.trim().toLocaleLowerCase("sk-SK").replace(/[.!?]+$/g, ""))) {
        decision = greetingDecision();
      } else {
        const modelDecision = await stylistModel.turn({
          request: {
            chatId: request.chatId,
            turnId: request.turnId,
            latestUserInput: request.latestUserInput,
            explicitUiActionId: request.explicitUiActionId,
            clientCapabilities: request.clientCapabilities,
          },
          session: clone(workingState),
          preflightResolution: preflight.kind === "pending" ? {
            kind: preflight.pendingKind,
            actionId: preflight.pending.actionId,
          } : null,
        });
        workingState = applySafeStatePatch(workingState, modelDecision.statePatch);
        workingState = await refreshWeatherIfGrounded(workingState, weatherTool);
        const missing = highestPriorityMissingGroundingV2(workingState);
        if (["generate_outfit", "edit_outfit"].includes(modelDecision.action) && missing) {
          decision = clarificationDecision(missing);
        } else {
          decision = modelDecision;
          const scope = modelDecision.retrievalScope || "none";
          if (scope !== "none") {
            wardrobeItems = await wardrobeTool.retrieve({
              scope,
              itemIds: workingState.currentOutfit.itemIds,
              category: modelDecision.retrievalCategory || null,
            });
          }
        }
      }

      const resultingRevision = originalState.revision + 1;
      const rawResult = normalizeDecision(decision, workingState, resultingRevision);
      rawResult.turnId = request.turnId;
      const validatedResult = validateAuthoritativeTurnV2({
        rawResult,
        previousState: originalState,
        proposedState: workingState,
        wardrobeItems,
      });
      const nextState = applyAcceptedResult(workingState, validatedResult);
      await sessionRepository.write(nextState);
      return clone(validatedResult);
    },
  };
}

module.exports = {
  LOCATION_FRESHNESS_MS,
  createStylistTurnCoordinatorV2,
  isFreshLocationObservation,
};
