"use strict";

const {MAX_HISTORY, bounded, clone, validateStylistSessionStateV2} = require("./stylist_session_state_v2");
const {validateTurnRequestV2} = require("./stylist_turn_contract_v2");
const {highestPriorityMissingGroundingV2, runPreflightV2} = require("./stylist_preflight_v2");
const {RepairableStructuralTurnError, validateAuthoritativeTurnV2} = require("./stylist_turn_validator_v2");

const GREETINGS = new Set(["ahoj", "čau", "cau", "dobrý deň", "dobry den"]);
const LOCATION_FRESHNESS_MS = 30 * 60 * 1000;
const MAX_PENDING_LOCATION_ATTEMPTS = 6;
const TOOL_REQUEST_KEYS = new Set(["kind", "requests", "statePatch"]);
const FINAL_ENVELOPE_KEYS = new Set(["kind", "result", "statePatch"]);
const TOOL_REQUEST_SCOPES = new Set(["current_outfit", "current_outfit_plus_category", "category", "full_relevant"]);
const WARDROBE_REQUEST_KEYS = new Set(["tool", "scope", "category", "editScope"]);
const LOCATION_REQUEST_KEYS = new Set(["tool", "query", "targetField"]);

function isFreshLocationObservation(observation, nowMs) {
  if (!observation?.observedAt) return false;
  const observedMs = Date.parse(observation.observedAt);
  return Number.isFinite(observedMs) && observedMs <= nowMs && nowMs - observedMs <= LOCATION_FRESHNESS_MS;
}

function cleanLocationAnswerFragmentV2(value) {
  const raw = String(value || "").trim().replace(/[.!?]+$/g, "").replace(/\s+/g, " ");
  if (!raw) return "";
  const stripped = raw.replace(/^(?:(?:ja\s+)?(?:idem|ideme|pojdem|pojdeme|chystam\s+sa|chystáme\s+sa|chystame\s+sa)\s+)?(?:do|na|v|vo|k|ku|to|in|at)\s+/iu, "").trim();
  return stripped || raw;
}

function pendingLocationResolutionQueriesV2(pendingQuestion, latestUserInput) {
  const raw = String(latestUserInput || "").trim().replace(/[.!?]+$/g, "").replace(/\s+/g, " ");
  const cleaned = cleanLocationAnswerFragmentV2(raw);
  const attempts = Array.isArray(pendingQuestion?.attemptedAnswers) ? pendingQuestion.attemptedAnswers : [];
  const previous = attempts.length ? cleanLocationAnswerFragmentV2(attempts[attempts.length - 1]) : "";
  const combined = previous && cleaned && previous.toLocaleLowerCase("sk-SK") !== cleaned.toLocaleLowerCase("sk-SK") ?
    `${cleaned}, ${previous}` : "";
  return [...new Set([combined, raw, cleaned].filter(Boolean))];
}

async function resolvePendingLocationAnswerV2(locationResolver, pendingQuestion, latestUserInput) {
  const queries = pendingLocationResolutionQueriesV2(pendingQuestion, latestUserInput);
  for (const query of queries) {
    const resolved = await locationResolver.resolve(query);
    if (resolved) return {resolved, query, queries};
  }
  return {resolved: null, query: null, queries};
}

function rememberPendingLocationAttemptV2(state, field, latestUserInput) {
  const pending = state.conversationMemory.pendingQuestion;
  const answer = String(latestUserInput || "").trim().replace(/\s+/g, " ").slice(0, 300);
  if (!pending || pending.field !== field || !answer) return [];
  pending.attemptedAnswers = bounded([
    ...(Array.isArray(pending.attemptedAnswers) ? pending.attemptedAnswers : []),
    answer,
  ], MAX_PENDING_LOCATION_ATTEMPTS);
  return [...pending.attemptedAnswers];
}

function unresolvedLocationClarificationDecision(field, latestUserInput, attemptedAnswers = []) {
  const candidate = String(latestUserInput || "").trim().replace(/[.!?]+$/g, "").replace(/\s+/g, " ").slice(0, 180);
  const attempts = Array.isArray(attemptedAnswers) ? attemptedAnswers : [];
  const question = attempts.length > 1 ?
    `Rozumiem, teraz myslíš „${candidate}“. Stále to neviem jednoznačne priradiť k miestu; skús prosím presnejší názov alebo najbližšie mesto/obec.` :
    `Rozumiem: „${candidate}“. Toto miesto som nevedel jednoznačne nájsť. Skús prosím presnejší názov, najbližšie mesto/obec alebo konkrétny bod.`;
  const actionId = field === "eventLocation" ? "clarify_event_location" : "clarify_destination";
  return {action: "clarify", assistantText: question, clarification: {field, question, actionId}, display: {kind: "none", itemIds: []}};
}

function unchangedOutfit(state) {
  return {itemIds: [...state.currentOutfit.itemIds], selectionReasonsByItemId: {...state.currentOutfit.selectionReasonsByItemId}};
}

function normalizeDecision(decision, state, resultingRevision, turnId) {
  const raw = clone(decision);
  raw.turnId = turnId;
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
  for (const key of ["activity", "date", "timeWindow", "terrain", "groundingRequirements"]) {
    if (Object.prototype.hasOwnProperty.call(context, key)) next.context[key] = clone(context[key]);
  }
  const memory = statePatch.conversationMemory || {};
  for (const key of ["communicatedWarnings", "rejectedWardrobeItemIds", "rejectedShoppingOptionIds", "userCorrections", "acceptedCompromises"]) {
    if (Object.prototype.hasOwnProperty.call(memory, key)) next.conversationMemory[key] = bounded(memory[key]);
  }
  if (Object.prototype.hasOwnProperty.call(statePatch, "pendingAction")) next.conversationMemory.pendingAction = clone(statePatch.pendingAction);
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
      ...removed.map((itemId) => ({itemId, reason: old.selectionReasonsByItemId[itemId], outfitRevision: old.revision})),
    ].slice(-MAX_HISTORY);
    next.currentOutfit.itemIds = [...incoming.itemIds];
    next.currentOutfit.selectionReasonsByItemId = {...incoming.selectionReasonsByItemId};
    next.currentOutfit.revision = old.revision + 1;
    next.currentOutfit.compromises = bounded(incoming.compromises || old.compromises);
    next.currentOutfit.missingWardrobeNeeds = bounded(incoming.missingWardrobeNeeds || old.missingWardrobeNeeds);
  }
  if (result.action === "clarify") {
    const previousPending = next.conversationMemory.pendingQuestion;
    const pendingQuestion = {
      type: "question", actionId: result.clarification.actionId, field: result.clarification.field,
      question: result.clarification.question, acceptsYesNo: Boolean(result.clarification.acceptsYesNo),
    };
    if (previousPending?.field === pendingQuestion.field && Array.isArray(previousPending.attemptedAnswers)) {
      pendingQuestion.attemptedAnswers = bounded(previousPending.attemptedAnswers, MAX_PENDING_LOCATION_ATTEMPTS);
    }
    next.conversationMemory.pendingQuestion = pendingQuestion;
  } else {
    next.conversationMemory.pendingQuestion = null;
  }
  if (result.action === "shop") next.conversationMemory.pendingAction = null;
  next.replay.turns = [...next.replay.turns, {turnId: result.turnId, result: clone(result)}].slice(-MAX_HISTORY);
  return validateStylistSessionStateV2(next);
}

function clarificationDecision(field) {
  const definitions = {
    currentLocationObservation: ["Kde sa budeš nachádzať, keď budeš outfit nosiť?", "clarify_current_location"],
    destination: ["Kam presne ideš?", "clarify_destination"],
    eventLocation: ["Kde presne sa podujatie koná?", "clarify_event_location"],
    date: ["Na ktorý deň outfit potrebuješ?", "clarify_date"],
    timeWindow: ["V ktorej časti dňa ho budeš potrebovať?", "clarify_time_window"],
    "terrain.surface": ["Po akom povrchu pôjdeš?", "clarify_terrain_surface"],
    "terrain.difficulty": ["Aká náročná bude trasa?", "clarify_terrain_difficulty"],
    "terrain.condition": ["Bude trasa suchá, mokrá, blatistá alebo zasnežená?", "clarify_terrain_condition"],
  };
  const [question, actionId] = definitions[field] || ["Čo ešte potrebuješ upresniť?", "clarify_context"];
  return {action: "clarify", assistantText: question, clarification: {field, question, actionId}, display: {kind: "none", itemIds: []}};
}

function greetingDecision() {
  return {action: "chat", assistantText: "Ahoj! Ako ti môžem pomôcť s outfitom?", display: {kind: "none", itemIds: []}};
}
function declinedPendingDecision() {
  return {action: "chat", assistantText: "Dobre, nechám to tak.", display: {kind: "none", itemIds: []}};
}

async function refreshWeatherIfGrounded(state, weatherTool) {
  const next = clone(state);
  const {date, timeWindow, weather, groundingRequirements} = next.context;
  if (!groundingRequirements.weatherRequired) return next;
  const location = next.context[groundingRequirements.weatherLocationField];
  if (!location || !date || !timeWindow) return next;
  if (weather?.locationProviderId === location.providerId && weather.dateKey === date.dateKey && weather.timeWindowKey === timeWindow.key) return next;
  next.context.weather = await weatherTool.getForecast({location, date, timeWindow});
  return next;
}

function shoppingContext(state, pending) {
  return {
    actionId: pending.actionId, activity: clone(state.context.activity), destination: clone(state.context.destination),
    eventLocation: clone(state.context.eventLocation), weather: clone(state.context.weather), terrain: clone(state.context.terrain),
    missingNeed: clone(state.shopping.missingNeed || state.currentOutfit.missingWardrobeNeeds[0] || null),
    hardConstraints: clone(state.shopping.hardConstraints), softPreferences: clone(state.shopping.softPreferences),
    size: clone(state.shopping.size), budget: clone(state.shopping.budget), brandPreferences: clone(state.shopping.brandPreferences),
    rejectedCandidateIds: clone(state.shopping.rejectedCandidateIds), openedReason: state.shopping.openedReason,
    currentOutfit: unchangedOutfit(state),
  };
}

function assertExactKeys(value, allowed, label) {
  if (!value || typeof value !== "object") throw new RepairableStructuralTurnError(`${label} is required`);
  for (const key of Object.keys(value)) if (!allowed.has(key)) throw new RepairableStructuralTurnError(`${label} contains unsupported field ${key}`);
}

function validatePlanningEnvelope(envelope, state) {
  if (envelope?.kind === "final") {
    assertExactKeys(envelope, FINAL_ENVELOPE_KEYS, "planning final envelope");
    if (!["chat", "clarify", "stop"].includes(envelope.result?.action)) {
      throw new RepairableStructuralTurnError("planning phase may finalize only a no-wardrobe chat, clarification, or stop");
    }
    return;
  }
  if (envelope?.kind !== "tool_request") throw new RepairableStructuralTurnError("planning phase must return final or tool_request");
  assertExactKeys(envelope, TOOL_REQUEST_KEYS, "tool request envelope");
  if (!Array.isArray(envelope.requests) || envelope.requests.length === 0) throw new RepairableStructuralTurnError("tool request envelope requires at least one request");
  const wardrobeRequests = envelope.requests.filter((request) => request.tool === "wardrobe");
  const locationRequests = envelope.requests.filter((request) => request.tool === "location");
  if (wardrobeRequests.length > 1 || locationRequests.length > 1 || envelope.requests.length !== wardrobeRequests.length + locationRequests.length) {
    throw new RepairableStructuralTurnError("only one wardrobe and one location request are allowed");
  }
  if (wardrobeRequests.some((request) => !TOOL_REQUEST_SCOPES.has(request.scope) || request.scope === "current_outfit_plus_category" && !request.category)) {
    throw new RepairableStructuralTurnError("invalid wardrobe retrieval request");
  }
  if (locationRequests.some((request) => !request.query || !["destination", "eventLocation"].includes(request.targetField))) {
    throw new RepairableStructuralTurnError("invalid location resolution request");
  }
  for (const request of wardrobeRequests) assertExactKeys(request, WARDROBE_REQUEST_KEYS, "wardrobe tool request");
  for (const request of locationRequests) assertExactKeys(request, LOCATION_REQUEST_KEYS, "location tool request");
  if (state.currentOutfit.itemIds.length && wardrobeRequests.some((request) => request.scope === "category")) {
    throw new RepairableStructuralTurnError("category-only retrieval omits the current outfit");
  }
}

function validateFinalEnvelope(envelope) {
  if (envelope?.kind !== "final") throw new RepairableStructuralTurnError("final model phase must return one authoritative result");
  assertExactKeys(envelope, FINAL_ENVELOPE_KEYS, "final envelope");
  if (!envelope.result || typeof envelope.result !== "object") throw new RepairableStructuralTurnError("final envelope requires a result");
}

function modelInput(request, state, preflight, phase, toolResults = null) {
  return {
    phase,
    request: {chatId: request.chatId, turnId: request.turnId, latestUserInput: request.latestUserInput,
      explicitUiActionId: request.explicitUiActionId, clientCapabilities: request.clientCapabilities},
    session: clone(state),
    preflightResolution: preflight.kind === "pending" ? {kind: preflight.pendingKind, answer: preflight.answer, actionId: preflight.pending.actionId} : null,
    toolResults: clone(toolResults),
  };
}

function createStylistTurnCoordinatorV2({sessionRepository, wardrobeTool, locationResolver, weatherTool, shoppingTool, stylistModel, clock = () => Date.now()}) {
  if (!sessionRepository || !wardrobeTool || !locationResolver || !weatherTool || !shoppingTool || !stylistModel) throw new TypeError("all Phase-0 ports are required");
  return {
    async resolveTurn(untrustedRequest) {
      const request = validateTurnRequestV2(untrustedRequest);
      const originalState = validateStylistSessionStateV2(await sessionRepository.read(request.chatId));
      const preflight = runPreflightV2(originalState, request);
      if (preflight.kind === "replay") return clone(preflight.result);

      let workingState = clone(originalState);
      const observation = request.freshClientObservations.currentLocationObservation;
      if (observation && isFreshLocationObservation(observation, clock())) workingState.context.currentLocationObservation = clone(observation);

      let decision = null;
      let wardrobeItems = [];
      const toolResults = {wardrobeItems: [], resolvedLocations: [], weather: null, authorizedEditScope: null};

      if (preflight.kind === "pending" && preflight.answer === "no") {
        if (preflight.pendingKind === "question") workingState.conversationMemory.pendingQuestion = null;
        else workingState.conversationMemory.pendingAction = null;
        decision = declinedPendingDecision();
      } else if (preflight.kind === "pending" && preflight.pendingKind !== "question" && preflight.pending.kind === "shopping") {
        const context = shoppingContext(workingState, preflight.pending);
        const shoppingResult = await shoppingTool.search(context);
        decision = {action: "shop", assistantText: shoppingResult.reply || "Pozrel som možnosti podľa tvojich uložených požiadaviek.",
          display: {kind: "shopping", itemIds: shoppingResult.candidateIds || []}, shoppingResult};
      }

      const pendingQuestion = workingState.conversationMemory.pendingQuestion;
      const pendingField = pendingQuestion?.field;
      if (!decision && ["destination", "eventLocation"].includes(pendingField)) {
        const resolution = await resolvePendingLocationAnswerV2(locationResolver, pendingQuestion, request.latestUserInput);
        if (!resolution.resolved) {
          const attemptedAnswers = rememberPendingLocationAttemptV2(workingState, pendingField, request.latestUserInput);
          decision = unresolvedLocationClarificationDecision(pendingField, request.latestUserInput, attemptedAnswers);
        } else {
          workingState.context[pendingField] = resolution.resolved;
          workingState.conversationMemory.answeredClarificationFields[pendingField] = clone(resolution.resolved);
          workingState.conversationMemory.pendingQuestion = null;
          workingState = await refreshWeatherIfGrounded(workingState, weatherTool);
          const missing = highestPriorityMissingGroundingV2(workingState);
          if (missing) decision = clarificationDecision(missing);
        }
      }

      const normalizedInput = request.latestUserInput.trim().toLocaleLowerCase("sk-SK").replace(/[.!?]+$/g, "");
      if (!decision && preflight.kind === "continue" && GREETINGS.has(normalizedInput)) decision = greetingDecision();

      if (!decision) {
        let planningToolResults = null;
        if (stylistModel.planningNeedsCurrentOutfit === true && workingState.currentOutfit.itemIds.length) {
          const currentFacts = await wardrobeTool.retrieve({scope: "current_outfit", itemIds: workingState.currentOutfit.itemIds, category: null});
          planningToolResults = {wardrobeItems: clone(currentFacts), resolvedLocations: [], weather: clone(workingState.context.weather), authorizedEditScope: null};
        }
        const planningEnvelope = await stylistModel.turn(modelInput(request, workingState, preflight, "plan", planningToolResults));
        validatePlanningEnvelope(planningEnvelope, workingState);
        workingState = applySafeStatePatch(workingState, planningEnvelope.statePatch);

        if (planningEnvelope.kind === "final") decision = planningEnvelope.result;
        else {
          const locationRequest = planningEnvelope.requests.find((entry) => entry.tool === "location");
          if (locationRequest) {
            const resolved = await locationResolver.resolve(locationRequest.query);
            if (!resolved) decision = clarificationDecision(locationRequest.targetField);
            else {
              workingState.context[locationRequest.targetField] = resolved;
              workingState.conversationMemory.answeredClarificationFields[locationRequest.targetField] = clone(resolved);
              toolResults.resolvedLocations.push({targetField: locationRequest.targetField, location: clone(resolved)});
            }
          }

          workingState = await refreshWeatherIfGrounded(workingState, weatherTool);
          toolResults.weather = clone(workingState.context.weather);
          const missing = highestPriorityMissingGroundingV2(workingState);
          if (!decision && missing) decision = clarificationDecision(missing);

          const wardrobeRequest = planningEnvelope.requests.find((entry) => entry.tool === "wardrobe");
          if (!decision && wardrobeRequest) {
            if (wardrobeRequest.scope === "current_outfit" && planningToolResults?.wardrobeItems) {
              wardrobeItems = clone(planningToolResults.wardrobeItems);
            } else {
              wardrobeItems = await wardrobeTool.retrieve({scope: wardrobeRequest.scope, itemIds: workingState.currentOutfit.itemIds, category: wardrobeRequest.category || null});
            }
            toolResults.wardrobeItems = clone(wardrobeItems);
            toolResults.authorizedEditScope = clone(wardrobeRequest.editScope || null);
          }

          if (!decision) {
            const finalEnvelope = await stylistModel.turn(modelInput(request, workingState, preflight, "final", toolResults));
            validateFinalEnvelope(finalEnvelope);
            workingState = applySafeStatePatch(workingState, finalEnvelope.statePatch);
            decision = finalEnvelope.result;
          }
        }
      }

      const rawResult = normalizeDecision(decision, workingState, originalState.revision + 1, request.turnId);
      const validatedResult = validateAuthoritativeTurnV2({rawResult, previousState: originalState, proposedState: workingState,
        wardrobeItems, authorizedEditScope: toolResults.authorizedEditScope});
      const nextState = applyAcceptedResult(workingState, validatedResult);
      await sessionRepository.write(nextState);
      return clone(validatedResult);
    },
  };
}

module.exports = {
  LOCATION_FRESHNESS_MS,
  MAX_PENDING_LOCATION_ATTEMPTS,
  cleanLocationAnswerFragmentV2,
  createStylistTurnCoordinatorV2,
  isFreshLocationObservation,
  pendingLocationResolutionQueriesV2,
  resolvePendingLocationAnswerV2,
  unresolvedLocationClarificationDecision,
  validateFinalEnvelope,
  validatePlanningEnvelope,
};
