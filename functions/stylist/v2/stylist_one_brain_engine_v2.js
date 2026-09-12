"use strict";

const {
  MAX_HISTORY,
  bounded,
  clone,
  validateStylistSessionStateV2,
} = require("./stylist_session_state_v2");
const {validateTurnRequestV2} = require("./stylist_turn_contract_v2");
const {
  AmbiguousAffirmationError,
  StaleSessionRevisionError,
  runPreflightV2,
} = require("./stylist_preflight_v2");
const {
  RepairableStructuralTurnError,
  validateAuthoritativeTurnV2,
} = require("./stylist_turn_validator_v2");
const {
  StylistSessionRepositoryV2Error,
} = require("./stylist_session_repository_v2");
const {
  beginNewScenarioV2,
  restoreScenarioSnapshotV2,
  upsertScenarioSnapshotV2,
} = require("./stylist_scenario_memory_v2");
const {locationIsTooBroadForWeatherV2, localCountryLocationHintV2} = require("./open_meteo_ports_v2");
const {categoryMatches} = require("./firestore_wardrobe_tool_v2");
const {ONE_BRAIN_MAX_MODEL_CALLS} = require("./openai_one_brain_model_port_v2");

const TOOL_REQUEST_SCOPES = new Set([
  "current_outfit",
  "current_outfit_plus_category",
  "category",
  "full_relevant",
]);
const SKIP_DIRECTIVE_RE = /\b(neviem|netusim|je mi to jedno|preskoc|preskocme|neries|nechaj tak|nechajme to|kasli na to|zrus to|zabudni na to|bez pocasia|daj mi proste|proste mi daj|vyber proste)\b/;
const EXPLICIT_BEST_EFFORT_RE = /\b(je mi to jedno|preskoc|preskocme|neries|nechaj tak|nechajme to|kasli na to|zrus to|zabudni na to|bez pocasia|daj mi proste|proste mi daj|vyber proste)\b/;
const PENDING_REPLY_DISPOSITIONS = new Set(["none", "answer", "skip", "meta", "unrelated"]);

function normalizeConversationTextV2(value) {
  return String(value || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase("sk-SK")
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function userRequestsBestEffortV2(value) {
  return SKIP_DIRECTIVE_RE.test(normalizeConversationTextV2(value));
}

function userExplicitlyRequestsBestEffortV2(value) {
  return EXPLICIT_BEST_EFFORT_RE.test(normalizeConversationTextV2(value));
}

function pendingLocationQueryV2(value) {
  return String(value || "")
    .trim()
    .replace(/\s*[:;]-?[dDpP)]+\s*$/u, "")
    .trim()
    .slice(0, 160);
}

function explicitStylingDestinationCandidateV2(value) {
  const raw = String(value || "").replace(/\s+/g, " ").trim();
  if (!raw) return null;
  const normalized = normalizeConversationTextV2(raw);
  const stylingSignal = /\b(?:outfit|oblecen\w*|obliec\w*|na seba|tura|turistik\w*|hiking|trek\w*|vylet\w*|dovolen\w*|koncert\w*|festival\w*|svadb\w*|pohovor\w*|ples\w*|lyz\w*)\b/.test(normalized);
  if (!stylingSignal) return null;

  const travel = raw.match(/\b(?:idem|ideme|pojdem|pojdeme|chystam\s+sa|chystám\s+sa|chystame\s+sa|chystáme\s+sa|cestujem|cestujeme|letim|letím|letime|letíme|vyrazam|vyrážam|vyrazame|vyrážame)\s+(?:do|na|v|vo)\s+(.+?)(?=\s+(?:na|za)\s+(?:turu|túru|turistiku|vylet|výlet|vikend|víkend|dovolenku|koncert|festival|svadbu|pohovor|ples|lyzovacku|lyžovačku)\b|\s+(?:a\s+)?(?:ja\s+)?(?:neviem|netusim|netuším|chcem|potrebujem|co|čo)\b|[,!?]|$)/iu);
  const query = String(travel?.[1] || "").trim().replace(/[.]+$/g, "");
  if (!query || query.length > 160) return null;
  const eventLike = /\b(?:koncert\w*|festival\w*|svadb\w*|pohovor\w*|ples\w*|ceremoni\w*|oslava\w*)\b/.test(normalized);
  return {query, targetField: eventLike ? "eventLocation" : "destination"};
}

function pendingReplyDispositionV2(envelope, pendingQuestion) {
  const raw = envelope?.pendingReplyDisposition;
  if (!pendingQuestion) {
    if (raw == null || raw === "none") return "none";
    throw new RepairableStructuralTurnError("pending reply disposition exists without a pending question");
  }
  // Legacy injected test doubles from before this contract are interpreted
  // as answer. Production structured output always supplies the field.
  if (raw == null) return "answer";
  if (!PENDING_REPLY_DISPOSITIONS.has(raw) || raw === "none") {
    throw new RepairableStructuralTurnError("pending reply disposition is missing or invalid");
  }
  return raw;
}

function clearPendingQuestionV2(state) {
  const next = clone(state);
  next.conversationMemory.pendingQuestion = null;
  return next;
}

function selectKnownWardrobeV2(items, request, currentIds) {
  const all = clone(Array.isArray(items) ? items : []);
  if (!request || request.scope === "full_relevant") return all;
  if (request.scope === "current_outfit") {
    return all.filter((item) => currentIds.includes(item.id));
  }
  if (request.scope === "category") {
    return all.filter((item) => categoryMatches(item, request.category));
  }
  if (request.scope === "current_outfit_plus_category") {
    return all.filter((item) => currentIds.includes(item.id) || categoryMatches(item, request.category));
  }
  return all;
}

function requirePort(value, label) {
  if (!value) throw new TypeError(`${label} is required`);
  return value;
}

function latestTurnReplayV2(state, turnId) {
  const matches = (state.replay?.turns || []).filter((entry) => entry.turnId === turnId);
  return matches.length ? matches[matches.length - 1] : null;
}

async function ensureCanonicalSessionV2({durableRepository, uid, request, bootstrapInput}) {
  const ensured = bootstrapInput ?
    await durableRepository.ensureFromLegacy({uid, chatId: request.chatId, bootstrapInput}) :
    await durableRepository.ensure({uid, chatId: request.chatId});
  return validateStylistSessionStateV2(ensured.state);
}

function applyDayDefaultV2(state) {
  const next = clone(state);
  if (next.context.date && !next.context.timeWindow) {
    next.context.timeWindow = {key: "day", label: "cez deň", source: "one_brain_default"};
  }
  return next;
}

function disableWeatherGroundingV2(state) {
  const next = clone(state);
  next.context.weather = null;
  next.context.groundingRequirements = {
    ...(next.context.groundingRequirements || {}),
    weatherRequired: false,
    weatherLocationField: null,
    terrainRequiredFields: [],
  };
  return next;
}

function applySkipToPendingQuestionV2(state) {
  const next = clone(state);
  const pending = next.conversationMemory?.pendingQuestion;
  if (!pending?.field) return next;
  const field = String(pending.field);
  next.conversationMemory.answeredClarificationFields[field] = {
    status: "unknown",
    source: "user",
  };
  next.conversationMemory.pendingQuestion = null;
  if (["currentLocationObservation", "destination", "eventLocation", "date", "timeWindow"].includes(field)) {
    return disableWeatherGroundingV2(next);
  }
  if (field.startsWith("terrain.")) {
    next.context.groundingRequirements = {
      ...(next.context.groundingRequirements || {}),
      terrainRequiredFields: [],
    };
  }
  return next;
}

function cannotClarifyFieldsV2(state) {
  return Object.entries(state?.conversationMemory?.answeredClarificationFields || {})
    .filter(([, value]) => value?.status === "unknown")
    .map(([field]) => field)
    .slice(0, 100);
}

function applyBrainStatePatchV2(state, statePatch = {}) {
  let next = clone(state);
  if (statePatch.scenarioMode === "restore" && statePatch.scenarioReferenceId) {
    next = restoreScenarioSnapshotV2(next, statePatch.scenarioReferenceId);
  } else if (statePatch.scenarioMode === "new") {
    next = beginNewScenarioV2(next);
  }

  const context = statePatch.context || {};
  for (const key of ["activity", "date", "timeWindow", "terrain", "environment"]) {
    if (Object.prototype.hasOwnProperty.call(context, key)) next.context[key] = clone(context[key]);
  }
  if (Object.prototype.hasOwnProperty.call(context, "groundingRequirements")) {
    const incoming = clone(context.groundingRequirements || {});
    next.context.groundingRequirements = {
      weatherRequired: incoming.weatherRequired === true,
      weatherLocationField: incoming.weatherRequired === true ? incoming.weatherLocationField || null : null,
      // The Brain may reason about explicit terrain facts, but it cannot create
      // a questionnaire by promoting unknown terrain metadata to mandatory fields.
      terrainRequiredFields: [],
    };
  }
  if (Object.prototype.hasOwnProperty.call(statePatch, "pendingAction")) {
    next.conversationMemory.pendingAction = clone(statePatch.pendingAction);
  }
  if (statePatch.shopping) next.shopping = {...next.shopping, ...clone(statePatch.shopping)};
  return applyDayDefaultV2(next);
}

function semanticLocationFallbackV2(query, targetField) {
  const label = String(query || "").trim().replace(/\s+/g, " ").slice(0, 240);
  if (!label) return null;
  const safe = normalizeConversationTextV2(label).replace(/\s+/g, "-").slice(0, 120) || "unknown";
  return {
    providerId: `semantic:${targetField}:${safe}`,
    label,
    source: "user_semantic_location",
    granularity: "region",
  };
}

function unchangedOutfitV2(state) {
  return {
    itemIds: [...state.currentOutfit.itemIds],
    selectionReasonsByItemId: {...state.currentOutfit.selectionReasonsByItemId},
  };
}

function normalizeDecisionV2(decision, state, resultingRevision, turnId) {
  const raw = clone(decision);
  raw.turnId = turnId;
  raw.resultingSessionRevision = resultingRevision;
  raw.resultingOutfit = raw.resultingOutfit || unchangedOutfitV2(state);
  raw.quickReplies = raw.quickReplies || [];
  raw.quickReplyPrompt = raw.quickReplyPrompt || null;
  raw.clarification = raw.clarification || null;
  raw.editScope = raw.editScope || null;
  raw.shoppingResult = raw.shoppingResult || null;
  return raw;
}

function applyAcceptedResultV2(state, result, {preservePendingQuestion = false} = {}) {
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
  } else if (!preservePendingQuestion) {
  next.conversationMemory.pendingQuestion = null;
}
if (result.action === "shop") next.conversationMemory.pendingAction = null;
  next.replay.turns = [
    ...next.replay.turns,
    {turnId: result.turnId, result: clone(result)},
  ].slice(-MAX_HISTORY);
  const withScenarioSnapshot = ["generate_outfit", "edit_outfit"].includes(result.action) ?
    upsertScenarioSnapshotV2(next, {turnId: result.turnId}) : next;
  return validateStylistSessionStateV2(withScenarioSnapshot);
}

function validateToolDecisionEnvelopeV2(envelope, {allowClarification, pendingQuestion = null}) {
  const disposition = pendingReplyDispositionV2(envelope, pendingQuestion);
  const pendingField = pendingQuestion?.field || null;
  const locationRequests = Array.isArray(envelope?.requests) ?
    envelope.requests.filter((entry) => entry?.tool === "location") : [];
  if (disposition === "meta" &&
      (envelope?.kind !== "final" || envelope.result?.action !== "chat" ||
       ![undefined, null, "current"].includes(envelope.statePatch?.scenarioMode))) {
    throw new RepairableStructuralTurnError("meta reply must answer conversationally and preserve the pending question");
  }
  if (["skip", "meta"].includes(disposition) &&
      locationRequests.some((entry) => entry.targetField === pendingField)) {
    throw new RepairableStructuralTurnError("skipped or meta pending reply cannot be consumed as the pending location");
  }
  if (disposition === "unrelated" &&
      locationRequests.some((entry) => entry.targetField === pendingField) &&
      envelope.statePatch?.scenarioMode !== "new") {
    throw new RepairableStructuralTurnError("unrelated reply cannot populate the old pending location");
  }
  if (disposition === "answer" && ["destination", "eventLocation"].includes(pendingField) &&
      locationRequests.some((entry) => entry.targetField !== pendingField)) {
    throw new RepairableStructuralTurnError("pending location answer targeted a different location field");
  }
  if (envelope?.kind === "final") {
    if (!["chat", "clarify", "stop"].includes(envelope.result?.action)) {
      throw new RepairableStructuralTurnError("one-brain tool stage may finalize only chat, clarify, or stop");
    }
    if (!allowClarification && envelope.result?.action === "clarify") {
    throw new RepairableStructuralTurnError("one-brain clarification budget already consumed");
  }
  if (pendingQuestion && envelope.result?.action === "clarify" && disposition !== "unrelated") {
    throw new RepairableStructuralTurnError("answered pending question cannot start another questionnaire round");
  }
  if (pendingQuestion && envelope.result?.action === "clarify" && disposition === "unrelated" &&
      envelope.statePatch?.scenarioMode !== "new") {
    throw new RepairableStructuralTurnError("new clarification after topic change requires a new scenario");
  }
    return;
  }
  if (envelope?.kind !== "tool_request" || !Array.isArray(envelope.requests) || envelope.requests.length === 0) {
    throw new RepairableStructuralTurnError("one-brain tool stage requires final or tool_request");
  }
  const wardrobe = envelope.requests.filter((entry) => entry?.tool === "wardrobe");
  const location = envelope.requests.filter((entry) => entry?.tool === "location");
  if (wardrobe.length > 1 || location.length > 1 || wardrobe.length + location.length !== envelope.requests.length) {
    throw new RepairableStructuralTurnError("one-brain allows at most one wardrobe and one location request");
  }
  if (wardrobe.some((entry) => !TOOL_REQUEST_SCOPES.has(entry.scope) ||
      entry.scope === "current_outfit_plus_category" && !entry.category)) {
    throw new RepairableStructuralTurnError("invalid one-brain wardrobe request");
  }
  if (location.some((entry) => !entry.query || !["destination", "eventLocation"].includes(entry.targetField))) {
    throw new RepairableStructuralTurnError("invalid one-brain location request");
  }
}

function validateAnswerEnvelopeV2(envelope) {
  if (envelope?.kind !== "final" || !envelope.result) {
    throw new RepairableStructuralTurnError("one-brain answer stage must return one final result");
  }
  if (envelope.result.action === "clarify") {
    throw new RepairableStructuralTurnError("one-brain answer stage cannot start another questionnaire round");
  }
}

function brainInputV2(request, state, stage, toolResults, runtimeConstraints) {
  return {
    stage,
    request: {
      chatId: request.chatId,
      turnId: request.turnId,
      latestUserInput: request.latestUserInput,
      explicitUiActionId: request.explicitUiActionId,
      clientCapabilities: request.clientCapabilities,
    },
    session: clone(state),
    toolResults: clone(toolResults),
    runtimeConstraints: clone(runtimeConstraints),
  };
}

async function callBrainV2(stylistBrain, input) {
  if (typeof stylistBrain.brainTurn === "function") return stylistBrain.brainTurn(input);
  // Compatibility only for injected legacy test doubles. Production One-Brain
  // uses brainTurn and never enters the old coordinator/grounding path.
  if (typeof stylistBrain.turn === "function") {
    return stylistBrain.turn({...input, phase: input.stage === "answer" ? "final" : "plan"});
  }
  throw new TypeError("stylistBrain.brainTurn is required");
}

function shoppingContextV2(state, pending) {
  return {
    actionId: pending.actionId,
    activity: clone(state.context.activity),
    destination: clone(state.context.destination),
    eventLocation: clone(state.context.eventLocation),
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
    currentOutfit: unchangedOutfitV2(state),
  };
}

function broadLocationClarificationDecisionV2(locationRequest, toolResults) {
  const resolved = (toolResults?.resolvedLocations || [])
    .find((entry) => entry?.targetField === locationRequest?.targetField)?.location;
  const rawLabel = String(resolved?.label || locationRequest?.query || "").trim();
  const label = rawLabel ? `„${rawLabel}“` : "Toto miesto";
  const targetField = locationRequest?.targetField === "eventLocation" ? "eventLocation" : "destination";
  const question = targetField === "eventLocation" ?
    `Jasné 😊 ${label} je ešte dosť široké. Kde približne sa tá udalosť koná?` :
    `Jasné 😊 ${label} je na takýto plán ešte dosť široké. Kam približne tam ideš? Stačí oblasť alebo pohorie.`;
  return {
    action: "clarify",
    assistantText: question,
    clarification: {
      field: targetField,
      question,
      actionId: `clarify_${targetField}_narrow`,
      acceptsYesNo: false,
    },
    display: {kind: "none", itemIds: []},
  };
}

async function executeRequestedToolsV2({envelope, state, wardrobeTool, locationResolver, weatherTool,
  knownWardrobeItems = null}) {
  let workingState = applyBrainStatePatchV2(state, envelope.statePatch);
  const preloadedWardrobe = Array.isArray(knownWardrobeItems) ? clone(knownWardrobeItems) : null;
  const toolResults = {
    wardrobeItems: preloadedWardrobe || [],
    resolvedLocations: [],
    locationStatus: "not_requested",
    weather: null,
    weatherStatus: "not_requested",
    authorizedEditScope: null,
  };
  let wardrobeItems = preloadedWardrobe || [];

  const locationRequest = envelope.requests.find((entry) => entry.tool === "location");
  if (locationRequest) {
    let resolved = null;
    try {
      resolved = await locationResolver.resolve(locationRequest.query);
    } catch (_) {
      resolved = null;
    }
    if (resolved) {
      workingState.context[locationRequest.targetField] = clone(resolved);
      workingState.conversationMemory.answeredClarificationFields[locationRequest.targetField] = clone(resolved);
      toolResults.resolvedLocations.push({
        targetField: locationRequest.targetField,
        location: clone(resolved),
      });
      toolResults.locationStatus = locationIsTooBroadForWeatherV2(resolved) ? "broad" : "resolved";
    } else {
      const semantic = semanticLocationFallbackV2(locationRequest.query, locationRequest.targetField);
      if (semantic) {
        workingState.context[locationRequest.targetField] = semantic;
        workingState.conversationMemory.answeredClarificationFields[locationRequest.targetField] = clone(semantic);
      }
      toolResults.locationStatus = "unavailable";
    }
  }

  const wardrobeRequest = envelope.requests.find((entry) => entry.tool === "wardrobe");
  if (wardrobeRequest) {
    wardrobeItems = preloadedWardrobe ?
      selectKnownWardrobeV2(preloadedWardrobe, wardrobeRequest, workingState.currentOutfit.itemIds) :
      await wardrobeTool.retrieve({
        scope: wardrobeRequest.scope,
        itemIds: workingState.currentOutfit.itemIds,
        category: wardrobeRequest.category || null,
      });
    toolResults.wardrobeItems = clone(wardrobeItems);
    toolResults.authorizedEditScope = clone(wardrobeRequest.editScope || null);
  }

  workingState = applyDayDefaultV2(workingState);
  const grounding = workingState.context.groundingRequirements || {};
  if (grounding.weatherRequired) {
    const location = grounding.weatherLocationField ? workingState.context[grounding.weatherLocationField] : null;
    const usableLocation = location && !locationIsTooBroadForWeatherV2(location) &&
      Number.isFinite(Number(location.lat)) && Number.isFinite(Number(location.lng));
    if (usableLocation && workingState.context.date && workingState.context.timeWindow) {
      try {
        const forecast = await weatherTool.getForecast({
          location,
          date: workingState.context.date,
          timeWindow: workingState.context.timeWindow,
        });
        workingState.context.weather = clone(forecast);
        toolResults.weather = clone(forecast);
        toolResults.weatherStatus = "resolved";
      } catch (_) {
        workingState = disableWeatherGroundingV2(workingState);
        toolResults.weatherStatus = "unavailable";
      }
    } else {
      workingState = disableWeatherGroundingV2(workingState);
      toolResults.weatherStatus = location && locationIsTooBroadForWeatherV2(location) ? "broad_location" : "unavailable";
    }
  }

  return {workingState, toolResults, wardrobeItems};
}

async function commitResultV2({durableRepository, uid, request, originalState, workingState, decision,
  wardrobeItems, authorizedEditScope, preservePendingQuestion = false}) {
  const rawResult = normalizeDecisionV2(decision, workingState, originalState.revision + 1, request.turnId);
  const validatedResult = validateAuthoritativeTurnV2({
    rawResult,
    previousState: originalState,
    proposedState: workingState,
    wardrobeItems,
    authorizedEditScope,
  });
  const nextState = applyAcceptedResultV2(workingState, validatedResult, {preservePendingQuestion});
  try {
    const outcome = await durableRepository.commitTurn({
      uid,
      chatId: request.chatId,
      turnId: request.turnId,
      expectedRevision: request.expectedSessionRevision,
      nextState,
      result: validatedResult,
    });
    return clone(outcome?.replayed ? outcome.result : validatedResult);
  } catch (error) {
    if (error instanceof StylistSessionRepositoryV2Error && error.code === "SESSION_CONFLICT") {
      const latest = await durableRepository.get({uid, chatId: request.chatId});
      throw new StaleSessionRevisionError(
        request.expectedSessionRevision,
        latest?.state?.revision ?? request.expectedSessionRevision,
      );
    }
    throw error;
  }
}

function createStylistOneBrainEngineV2({sessionRepository, wardrobeTool, locationResolver,
  weatherTool, shoppingTool, stylistBrain, clock = () => Date.now()}) {
  const durableRepository = requirePort(sessionRepository, "sessionRepository");
  for (const method of ["ensure", "ensureFromLegacy", "get", "commitTurn"]) {
    requirePort(durableRepository[method], `sessionRepository.${method}`);
  }
  requirePort(wardrobeTool, "wardrobeTool");
  requirePort(locationResolver, "locationResolver");
  requirePort(weatherTool, "weatherTool");
  requirePort(shoppingTool, "shoppingTool");
  requirePort(stylistBrain, "stylistBrain");

  return Object.freeze({
    async resolveTurn({uid, request: untrustedRequest, bootstrapInput = null, knownCanonicalState = null,
    knownWardrobeItems = null}) {
      const request = validateTurnRequestV2(untrustedRequest);
      const originalState = knownCanonicalState ? validateStylistSessionStateV2(knownCanonicalState) :
        await ensureCanonicalSessionV2({durableRepository, uid, request, bootstrapInput});

      const replay = latestTurnReplayV2(originalState, request.turnId);
      if (replay?.result) return clone(replay.result);
      if (request.expectedSessionRevision !== originalState.revision) {
        throw new StaleSessionRevisionError(request.expectedSessionRevision, originalState.revision);
      }

      let workingState = clone(originalState);
      const observation = request.freshClientObservations.currentLocationObservation;
      if (observation?.observedAt) {
        const observed = Date.parse(observation.observedAt);
        const now = clock();
        if (Number.isFinite(observed) && observed <= now && now - observed <= 30 * 60 * 1000) {
          workingState.context.currentLocationObservation = clone(observation);
        }
      }
      workingState = applyDayDefaultV2(workingState);

      const hadPendingQuestion = Boolean(workingState.conversationMemory.pendingQuestion);
      const pendingSkipDirective = hadPendingQuestion && userRequestsBestEffortV2(request.latestUserInput);
      const bestEffortDirective = pendingSkipDirective ||
        (!hadPendingQuestion && userExplicitlyRequestsBestEffortV2(request.latestUserInput));
      if (pendingSkipDirective) {
      workingState = applySkipToPendingQuestionV2(workingState);
    }
    const pendingQuestionAtBrain = clone(workingState.conversationMemory.pendingQuestion);

    let preflight;
      try {
        preflight = runPreflightV2(originalState, request);
      } catch (error) {
        if (!(error instanceof AmbiguousAffirmationError)) throw error;
        preflight = {kind: "continue"};
      }

      if (preflight.kind === "pending" && preflight.pendingKind === "action") {
        let decision;
        if (preflight.answer === "no") {
          workingState.conversationMemory.pendingAction = null;
          decision = {action: "chat", assistantText: "Jasné, zostaneme pri tom, čo už máme.", display: {kind: "none", itemIds: []}};
        } else if (preflight.pending.kind === "shopping") {
          const context = shoppingContextV2(workingState, preflight.pending);
          const shoppingResult = await shoppingTool.search(context);
          decision = {
            action: "shop",
            assistantText: shoppingResult.reply || "Pozrel som možnosti podľa tvojich uložených požiadaviek.",
            display: {kind: "shopping", itemIds: shoppingResult.candidateIds || []},
            shoppingResult,
          };
        }
        if (decision) {
          return commitResultV2({
            durableRepository, uid, request, originalState, workingState, decision,
            wardrobeItems: [], authorizedEditScope: null,
          });
        }
      }

      // Resolve an explicitly named travel destination before the model. The
      // geocoder still decides country/region/locality semantically, but a broad
      // country clarification must not throw away the rest of the user's scenario.
      // We therefore let the Brain parse explicit activity/date/environment into
      // statePatch, then deterministically commit the one useful location question.
      let forcedBroadClarification = null;
      if (!pendingQuestionAtBrain && !bestEffortDirective) {
        const explicitDestination = explicitStylingDestinationCandidateV2(request.latestUserInput);
        if (explicitDestination) {
          // Country-level destinations must be deterministic even when the
          // external geocoder is unavailable or cannot understand an inflected
          // Slovak form such as "Švajčiarska". Resolve a local ISO/ICU country
          // hint first; use the network resolver only for more specific places.
          let resolvedExplicitDestination = localCountryLocationHintV2(explicitDestination.query);
          if (!resolvedExplicitDestination) {
            try {
              resolvedExplicitDestination = await locationResolver.resolve(explicitDestination.query);
            } catch (_) {
              resolvedExplicitDestination = null;
            }
          }
          if (resolvedExplicitDestination) {
            const field = explicitDestination.targetField;
            workingState.context[field] = clone(resolvedExplicitDestination);
            workingState.conversationMemory.answeredClarificationFields[field] = clone(resolvedExplicitDestination);
            if (locationIsTooBroadForWeatherV2(resolvedExplicitDestination)) {
              forcedBroadClarification = {
                field,
                decision: broadLocationClarificationDecisionV2(
                  {tool: "location", query: explicitDestination.query, targetField: field},
                  {resolvedLocations: [{targetField: field, location: resolvedExplicitDestination}]},
                ),
              };
            }
          }
        }
      }

      const runtimeConstraints = {
        maxModelCalls: ONE_BRAIN_MAX_MODEL_CALLS,
        modelCallsRemaining: ONE_BRAIN_MAX_MODEL_CALLS,
        allowClarification: !bestEffortDirective,
      cannotClarifyFields: cannotClarifyFieldsV2(workingState),
      pendingReplyRequired: Boolean(pendingQuestionAtBrain),
      pendingReplyField: pendingQuestionAtBrain?.field || null,
      forcedClarificationField: forcedBroadClarification?.field || null,
      noAutomaticGroundingQuestions: true,
      answerStageMayClarify: false,
      };
      const emptyToolResults = {
      wardrobeItems: Array.isArray(knownWardrobeItems) ? clone(knownWardrobeItems) : [],
        resolvedLocations: [],
        locationStatus: "not_requested",
        weather: clone(workingState.context.weather),
        weatherStatus: workingState.context.weather ? "cached" : "not_requested",
        authorizedEditScope: null,
      };

      let toolEnvelope = await callBrainV2(stylistBrain,
        brainInputV2(request, workingState, "tools", emptyToolResults, runtimeConstraints));
      runtimeConstraints.modelCallsRemaining -= 1;
      try {
        validateToolDecisionEnvelopeV2(toolEnvelope, {...runtimeConstraints, pendingQuestion: pendingQuestionAtBrain});
      } catch (error) {
        if (!(error instanceof RepairableStructuralTurnError) ||
            Number(error.maxFutureCorrectionAttempts || 0) < 1) throw error;
        const repairConstraints = {
          ...runtimeConstraints,
          structuralRepair: {
            attempt: 1,
            code: error.code,
            message: String(error.message || "repairable structural contract error").slice(0, 300),
          },
        };
        toolEnvelope = await callBrainV2(stylistBrain,
          brainInputV2(request, workingState, "tools", emptyToolResults, repairConstraints));
        runtimeConstraints.modelCallsRemaining -= 1;
        validateToolDecisionEnvelopeV2(toolEnvelope, {...repairConstraints, pendingQuestion: pendingQuestionAtBrain});
      }
    const pendingDisposition = pendingReplyDispositionV2(toolEnvelope, pendingQuestionAtBrain);

    // A country preflight must preserve explicit scenario facts parsed from the
    // original message before runtime stops for the one useful location question.
    if (forcedBroadClarification) {
      workingState = applyBrainStatePatchV2(workingState, toolEnvelope.statePatch);
      return commitResultV2({
        durableRepository, uid, request, originalState, workingState,
        decision: forcedBroadClarification.decision,
        wardrobeItems: [], authorizedEditScope: null,
      });
    }

    // If the Brain correctly classifies a pending destination reply as an answer
    // but tries to finish with a bare acknowledgement (for example "Rozumiem."),
    // runtime completes the missing location + wardrobe tool step instead of
    // accepting the dead-end chat response. Classification remains semantic;
    // runtime only guarantees continuation after an acknowledged location answer.
    let effectiveToolEnvelope = toolEnvelope;
    if (pendingQuestionAtBrain && pendingDisposition === "answer" &&
        ["destination", "eventLocation"].includes(pendingQuestionAtBrain.field)) {
      const requests = Array.isArray(toolEnvelope.requests) ? clone(toolEnvelope.requests) : [];
      if (!requests.some((entry) => entry?.tool === "location" &&
          entry.targetField === pendingQuestionAtBrain.field)) {
        requests.push({
          tool: "location",
          query: pendingLocationQueryV2(request.latestUserInput),
          targetField: pendingQuestionAtBrain.field,
        });
      }
      if (!requests.some((entry) => entry?.tool === "wardrobe") && !Array.isArray(knownWardrobeItems)) {
        requests.push({tool: "wardrobe", scope: "full_relevant", category: null, editScope: null});
      }
      effectiveToolEnvelope = {...toolEnvelope, kind: "tool_request", requests,
        pendingReplyDisposition: pendingDisposition};
      validateToolDecisionEnvelopeV2(effectiveToolEnvelope,
        {...runtimeConstraints, pendingQuestion: pendingQuestionAtBrain});
    }

    let preservePendingQuestion = false;
    if (pendingQuestionAtBrain) {
      if (pendingDisposition === "skip") {
        workingState = applySkipToPendingQuestionV2(workingState);
      } else if (["answer", "unrelated"].includes(pendingDisposition)) {
        workingState = clearPendingQuestionV2(workingState);
      } else if (pendingDisposition === "meta") {
        preservePendingQuestion = true;
      }
    }
    workingState = applyBrainStatePatchV2(workingState, effectiveToolEnvelope.statePatch);

    if (effectiveToolEnvelope.kind === "final") {
      return commitResultV2({
        durableRepository, uid, request, originalState, workingState,
        decision: effectiveToolEnvelope.result,
        wardrobeItems: Array.isArray(knownWardrobeItems) ? clone(knownWardrobeItems) : [],
        authorizedEditScope: null,
        preservePendingQuestion,
      });
    }

      const executed = await executeRequestedToolsV2({
        envelope: effectiveToolEnvelope,
        state: workingState,
        wardrobeTool,
        locationResolver,
        weatherTool,
      knownWardrobeItems,
    });
      workingState = executed.workingState;
      const broadLocationRequest = effectiveToolEnvelope.requests.find((entry) => entry?.tool === "location");
      if (!pendingQuestionAtBrain &&
          runtimeConstraints.allowClarification &&
          broadLocationRequest &&
          executed.toolResults.locationStatus === "broad") {
        const decision = broadLocationClarificationDecisionV2(broadLocationRequest, executed.toolResults);
        return commitResultV2({
          durableRepository, uid, request, originalState, workingState, decision,
          wardrobeItems: executed.wardrobeItems,
          authorizedEditScope: executed.toolResults.authorizedEditScope,
        });
      }
      const answerConstraints = {
        ...runtimeConstraints,
        modelCallsRemaining: 1,
        allowClarification: false,
        cannotClarifyFields: cannotClarifyFieldsV2(workingState),
      };
      const answerEnvelope = await callBrainV2(stylistBrain,
        brainInputV2(request, workingState, "answer", executed.toolResults, answerConstraints));
      validateAnswerEnvelopeV2(answerEnvelope);
      workingState = applyBrainStatePatchV2(workingState, answerEnvelope.statePatch);

      return commitResultV2({
        durableRepository,
        uid,
        request,
        originalState,
        workingState,
        decision: answerEnvelope.result,
        wardrobeItems: executed.wardrobeItems,
        authorizedEditScope: executed.toolResults.authorizedEditScope,
      });
    },
  });
}

module.exports = {
  ONE_BRAIN_MAX_MODEL_CALLS,
  applyAcceptedResultV2,
  applyBrainStatePatchV2,
  applySkipToPendingQuestionV2,
  cannotClarifyFieldsV2,
  createStylistOneBrainEngineV2,
  disableWeatherGroundingV2,
  executeRequestedToolsV2,
  explicitStylingDestinationCandidateV2,
  pendingLocationQueryV2,
  pendingReplyDispositionV2,
  selectKnownWardrobeV2,
  semanticLocationFallbackV2,
  userRequestsBestEffortV2,
  validateAnswerEnvelopeV2,
  validateToolDecisionEnvelopeV2,
};
