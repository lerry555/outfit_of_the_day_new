"use strict";

const {MAX_HISTORY, bounded, clone, validateStylistSessionStateV2} = require("./stylist_session_state_v2");
const {validateTurnRequestV2} = require("./stylist_turn_contract_v2");
const {highestPriorityMissingGroundingV2, runPreflightV2} = require("./stylist_preflight_v2");
const {RepairableStructuralTurnError, validateAuthoritativeTurnV2} = require("./stylist_turn_validator_v2");
const {locationIsTooBroadForWeatherV2} = require("./open_meteo_ports_v2");

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

function normalizeConversationTextV2(value) {
  return String(value || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase("sk-SK")
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function isFriendlyGreetingV2(value) {
  const normalized = normalizeConversationTextV2(value);
  if (GREETINGS.has(String(value || "").trim().toLocaleLowerCase("sk-SK").replace(/[.!?]+$/g, ""))) return true;
  return /^(ahoj|cau|nazdar|servus|hello|hi|hey)(?:\s+(divocak|kamo|kamarat|stylista))?$/.test(normalized);
}

function pendingLocationReplyDispositionV2(value) {
  const normalized = normalizeConversationTextV2(value);
  if (!normalized) return "conversation";
  if (/^(naco|preco|aky je dovod|na co|a naco|a preco)\b/.test(normalized) ||
      /\b(naco ti to je|preco to potrebujes|na co ti to je)\b/.test(normalized)) return "why";
  if (/\b(neviem|netusim|je mi to jedno|preskoc|preskocme|neries|bez pocasia|daj mi proste|proste mi daj|vyber proste)\b/.test(normalized)) return "skip";
  return "location";
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
    `Rozumiem, teraz myslíš „${candidate}“. Stále to neviem jednoznačne priradiť k miestu. Vieš uviesť presnejší názov alebo najbližšie mesto/obec?` :
    `Rozumiem: „${candidate}“. Toto miesto som nevedel jednoznačne nájsť. Vieš uviesť presnejší názov, najbližšie mesto/obec alebo konkrétny bod?`;
  const actionId = field === "eventLocation" ? "clarify_event_location" : "clarify_destination";
  return {action: "clarify", assistantText: question, clarification: {field, question, actionId}, display: {kind: "none", itemIds: []}};
}

function whyLocationClarificationDecision(field) {
  const event = field === "eventLocation";
  const question = event ?
    "Pomôže mi to zohľadniť počasie priamo na mieste podujatia, nie tvoju aktuálnu polohu. Kde približne sa podujatie koná?" :
    "Pomôže mi to zohľadniť počasie tam, kam ideš, namiesto tvojej aktuálnej polohy. Kam približne ideš?";
  const actionId = event ? "clarify_event_location" : "clarify_destination";
  return {action: "clarify", assistantText: question, clarification: {field, question, actionId}, display: {kind: "none", itemIds: []}};
}

function broadLocationClarificationDecision(field, latestUserInput) {
  const candidate = cleanLocationAnswerFragmentV2(latestUserInput).slice(0, 120) || "toto miesto";
  const event = field === "eventLocation";
  const question = event ?
    `„${candidate}“ je na spoľahlivé miestne počasie príliš široké. V ktorom meste, štáte alebo regióne sa podujatie koná?` :
    `„${candidate}“ je na spoľahlivé miestne počasie príliš široké. Do ktorého mesta, štátu alebo regiónu ideš?`;
  const actionId = event ? "clarify_event_location" : "clarify_destination";
  return {action: "clarify", assistantText: question, clarification: {field, question, actionId}, display: {kind: "none", itemIds: []}};
}

function applyHelpFirstDefaultsV2(state) {
  const next = clone(state);
  const grounding = next.context.groundingRequirements || {};
  if (grounding.weatherRequired && next.context.date && !next.context.timeWindow) {
    next.context.timeWindow = {key: "day", label: "cez deň", source: "help_first_default"};
  }
  return next;
}

function deterministicRemoteOutfitClarificationV2(request, state) {
  if (state.conversationMemory.pendingQuestion || state.conversationMemory.pendingAction) return null;
  const text = normalizeConversationTextV2(request.latestUserInput);
  const asksOutfit = /\b(outfit|oblecenie|obliect|co si mam dat|co mam na seba|vyber mi|navrhni mi|zostav mi)\b/.test(text);
  const hiking = /\b(tura|turu|turistika|hiking|hike|trek|treking)\b/.test(text);
  if (!asksOutfit || !hiking) return null;

  // Keep this deliberately narrow: if the same message already looks like it
  // contains a destination, let the model/tool path resolve it instead of
  // asking a redundant question.
  const hasDestinationCandidate = /\bdo\s+[a-z0-9]/.test(text) ||
    /\b(?:v|vo)\s+[a-z0-9]/.test(text) ||
    /\bna\s+(?!turu\b|turistiku\b)[a-z0-9]/.test(text);
  if (hasDestinationCandidate) return null;

  let dateKey = null;
  if (/\b(zajtra|tomorrow)\b/.test(text)) dateKey = request.clientCapabilities?.tomorrowDateKey || null;
  else if (/\b(dnes|today)\b/.test(text)) dateKey = request.clientCapabilities?.todayDateKey || null;
  if (!dateKey) return null;

  const next = clone(state);
  next.context.activity = {id: "hiking", label: "túra", source: "user"};
  next.context.date = {dateKey, source: "user"};
  next.context.destination = null;
  next.context.eventLocation = null;
  next.context.weather = null;
  next.context.groundingRequirements = {
    weatherRequired: true,
    weatherLocationField: "destination",
    terrainRequiredFields: [],
  };
  return {
    state: applyHelpFirstDefaultsV2(next),
    decision: clarificationDecision("destination"),
  };
}

function disableOptionalWeatherGroundingV2(state) {
  const next = clone(state);
  next.context.weather = null;
  next.context.groundingRequirements = {
    ...next.context.groundingRequirements,
    weatherRequired: false,
    weatherLocationField: null,
  };
  next.conversationMemory.pendingQuestion = null;
  return next;
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
    destination: ["Kam približne ideš?", "clarify_destination"],
    eventLocation: ["Kde približne sa podujatie koná?", "clarify_event_location"],
    date: ["Na ktorý deň outfit potrebuješ?", "clarify_date"],
    timeWindow: ["V ktorej časti dňa ho budeš potrebovať?", "clarify_time_window"],
    "terrain.surface": ["Po akom povrchu pôjdeš?", "clarify_terrain_surface"],
    "terrain.difficulty": ["Aká náročná bude trasa?", "clarify_terrain_difficulty"],
    "terrain.condition": ["Bude trasa suchá, mokrá, blatistá alebo zasnežená?", "clarify_terrain_condition"],
  };
  const [question, actionId] = definitions[field] || ["Čo ešte potrebuješ upresniť?", "clarify_context"];
  return {action: "clarify", assistantText: question, clarification: {field, question, actionId, acceptsYesNo: false}, display: {kind: "none", itemIds: []}};
}

function greetingDecision() {
  return {action: "chat", assistantText: "Ahoj! Ako ti môžem pomôcť s outfitom?", display: {kind: "none", itemIds: []}};
}
function declinedPendingDecision() {
  return {action: "chat", assistantText: "Jasné, zostaneme pri tom, čo už máme.", display: {kind: "none", itemIds: []}};
}

async function refreshWeatherIfGrounded(state, weatherTool) {
  const next = applyHelpFirstDefaultsV2(state);
  const {date, timeWindow, weather, groundingRequirements} = next.context;
  if (!groundingRequirements.weatherRequired) return next;
  const location = next.context[groundingRequirements.weatherLocationField];
  if (!location || !date || !timeWindow || locationIsTooBroadForWeatherV2(location)) return next;
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
      workingState = applyHelpFirstDefaultsV2(workingState);

      let decision = null;
      let wardrobeItems = [];
      let pendingLocationContinuation = false;
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

      if (!decision && preflight.kind === "continue" && isFriendlyGreetingV2(request.latestUserInput)) {
        decision = greetingDecision();
      }

      if (!decision && preflight.kind === "continue") {
        const fastClarification = deterministicRemoteOutfitClarificationV2(request, workingState);
        if (fastClarification) {
          workingState = fastClarification.state;
          decision = fastClarification.decision;
        }
      }

      const pendingQuestion = workingState.conversationMemory.pendingQuestion;
      const pendingField = pendingQuestion?.field;
      if (!decision && ["destination", "eventLocation"].includes(pendingField)) {
        const disposition = pendingLocationReplyDispositionV2(request.latestUserInput);
        if (disposition === "why") {
          decision = whyLocationClarificationDecision(pendingField);
        } else if (disposition === "skip") {
          workingState = disableOptionalWeatherGroundingV2(workingState);
          pendingLocationContinuation = true;
        } else if (disposition === "location") {
          const resolution = await resolvePendingLocationAnswerV2(locationResolver, pendingQuestion, request.latestUserInput);
          if (!resolution.resolved) {
            // Exact weather is optional after the user has already answered the
            // one useful location question. A geocoder miss is a tool failure,
            // not a reason to trap the conversation in another questionnaire.
            rememberPendingLocationAttemptV2(workingState, pendingField, request.latestUserInput);
            workingState = disableOptionalWeatherGroundingV2(workingState);
            pendingLocationContinuation = true;
          } else if (locationIsTooBroadForWeatherV2(resolution.resolved)) {
            rememberPendingLocationAttemptV2(workingState, pendingField, request.latestUserInput);
            decision = broadLocationClarificationDecision(pendingField, request.latestUserInput);
          } else {
            workingState.context[pendingField] = resolution.resolved;
            workingState.conversationMemory.answeredClarificationFields[pendingField] = clone(resolution.resolved);
            workingState.conversationMemory.pendingQuestion = null;
            workingState = applyHelpFirstDefaultsV2(workingState);
            toolResults.resolvedLocations.push({targetField: pendingField, location: clone(resolution.resolved)});
            const missing = highestPriorityMissingGroundingV2(workingState);
            if (missing) decision = clarificationDecision(missing);
            else pendingLocationContinuation = true;
          }
        }
      }

      // The common flow after answering the one location question is a new
      // outfit request. Weather and wardrobe do not depend on one another once
      // the destination/date are grounded, so load them in parallel and then
      // go straight to one final stylist call.
      if (!decision && pendingLocationContinuation && workingState.currentOutfit.itemIds.length === 0) {
        const [weatherState, retrievedWardrobe] = await Promise.all([
          refreshWeatherIfGrounded(workingState, weatherTool),
          wardrobeTool.retrieve({scope: "full_relevant", itemIds: [], category: null}),
        ]);
        workingState = weatherState;
        wardrobeItems = retrievedWardrobe;
        toolResults.wardrobeItems = clone(wardrobeItems);
        toolResults.weather = clone(workingState.context.weather);
        const finalEnvelope = await stylistModel.turn(modelInput(request, workingState, preflight, "final", toolResults));
        validateFinalEnvelope(finalEnvelope);
        workingState = applySafeStatePatch(workingState, finalEnvelope.statePatch);
        workingState = applyHelpFirstDefaultsV2(workingState);
        decision = finalEnvelope.result;
      }

      if (!decision) {
        let planningToolResults = null;
        const preloadRequested = stylistModel.planningNeedsCurrentOutfit === true ||
          (typeof stylistModel.shouldPreloadCurrentOutfit === "function" && stylistModel.shouldPreloadCurrentOutfit({
            request: {latestUserInput: request.latestUserInput}, session: clone(workingState),
          }) === true);
        if (preloadRequested && workingState.currentOutfit.itemIds.length) {
          const currentFacts = await wardrobeTool.retrieve({scope: "current_outfit", itemIds: workingState.currentOutfit.itemIds, category: null});
          planningToolResults = {wardrobeItems: clone(currentFacts), resolvedLocations: [], weather: clone(workingState.context.weather), authorizedEditScope: null};
        }
        const planningEnvelope = await stylistModel.turn(modelInput(request, workingState, preflight, "plan", planningToolResults));
        validatePlanningEnvelope(planningEnvelope, workingState);
        workingState = applySafeStatePatch(workingState, planningEnvelope.statePatch);
        workingState = applyHelpFirstDefaultsV2(workingState);

        if (planningEnvelope.kind === "final") decision = planningEnvelope.result;
        else {
          const locationRequest = planningEnvelope.requests.find((entry) => entry.tool === "location");
          if (locationRequest) {
            const resolved = await locationResolver.resolve(locationRequest.query);
            if (!resolved) decision = clarificationDecision(locationRequest.targetField);
            else if (locationIsTooBroadForWeatherV2(resolved)) {
              workingState.conversationMemory.pendingQuestion = {
                type: "question",
                actionId: locationRequest.targetField === "eventLocation" ? "clarify_event_location" : "clarify_destination",
                field: locationRequest.targetField,
                question: broadLocationClarificationDecision(locationRequest.targetField, locationRequest.query).clarification.question,
                acceptsYesNo: false,
                attemptedAnswers: [locationRequest.query],
              };
              decision = broadLocationClarificationDecision(locationRequest.targetField, locationRequest.query);
            } else {
              workingState.context[locationRequest.targetField] = resolved;
              workingState.conversationMemory.answeredClarificationFields[locationRequest.targetField] = clone(resolved);
              toolResults.resolvedLocations.push({targetField: locationRequest.targetField, location: clone(resolved)});
            }
          }

          workingState = applyHelpFirstDefaultsV2(workingState);
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
            workingState = applyHelpFirstDefaultsV2(workingState);
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
  applyHelpFirstDefaultsV2,
  cleanLocationAnswerFragmentV2,
  createStylistTurnCoordinatorV2,
  deterministicRemoteOutfitClarificationV2,
  disableOptionalWeatherGroundingV2,
  isFriendlyGreetingV2,
  isFreshLocationObservation,
  pendingLocationReplyDispositionV2,
  pendingLocationResolutionQueriesV2,
  resolvePendingLocationAnswerV2,
  unresolvedLocationClarificationDecision,
  validateFinalEnvelope,
  validatePlanningEnvelope,
};