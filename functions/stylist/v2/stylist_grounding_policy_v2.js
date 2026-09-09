"use strict";

function clone(value) { return value == null ? value : JSON.parse(JSON.stringify(value)); }

function normalizeSemanticTextV2(value) {
  return String(value || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function locationQueryIsUserGroundedV2(query, latestUserInput) {
  const normalizedQuery = normalizeSemanticTextV2(query);
  const normalizedInput = normalizeSemanticTextV2(latestUserInput);
  if (!normalizedQuery || !normalizedInput) return false;
  return ` ${normalizedInput} `.includes(` ${normalizedQuery} `);
}

const OUTFIT_TERMS = /\b(outfit|outfity|look|styling|oblecenie|oblecenia|obliect|na seba|kombinacia|kombinaciu)\b/;
const REQUEST_TERMS = /\b(potrebujem|potreboval|potrebovala|chcem|chcel|chcela|vyber|navrhni|daj|sprav|zostav|co si mam|co mam)\b/;
const OPINION_TERMS = /\b(je to ok|je v poriadku|co povies|co si myslis|ako vyzera|hodnot|paci sa)\b/;
const CONTINUITY_TERMS = /\b(iny|inu|ine|dalsi|dalsiu|dalsie|tento|tuto|toto|ten isty|tu istu|este|zmen|vymen|nahra|swap)\b/;
const EVENT_TERMS = /\b(svadba|svadbu|wedding|koncert|concert|festival|ples|oslava|oslavu|party|rande|date|vecera|dinner|restauracia|restaurant|pohovor|interview|promocia|promocie|stuzkova|krst|pohreb|funeral|ceremonia|ceremony|divadlo|theatre|opera|galavecer|event|podujatie)\b/;
const OUTDOOR_TERMS = /\b(tura|turu|turistika|hiking|hike|trek|treking|hory|horach|les|lese|huby|hubarcenie|vylet|prechadzka|beh|behanie|running|bicykel|bicykli|bike|cycling|cyklistika|gril|grilovacka|piknik|plaz|beach|kupanie|kemp|camping|stanovacka|lyzovanie|lyze|skiing|snowboard|korculovanie|golf|ryby|rybarcenie|futbal|football|tenis|tennis|outdoor|vonku|priroda|prirode)\b/;
const TRAVEL_TERMS = /\b(idem|ideme|pojdem|pojdeme|chystam sa|chystame sa|cestujem|cestujeme|letim|letime|vyrazam|vyrazime|budem na|budeme na|going to|travel|travelling|trip)\b/;
const LOCAL_ROUTINE_TERMS = /\b(do prace|v praci|do skoly|v skole|do fitka|vo fitku|do posilnovne|v posilnovni|gym|work|school|na nakup|na nakupy|kino|cinema|do kina|v kine|doma|home office)\b/;
const VIRTUAL_TERMS = /\b(online|zoom|teams|videohovor|video call|remote|z domu|home office)\b/;
const PENDING_META_OR_SKIP_TERMS = /\b(naco ti to je|preco to potrebujes|na co ti to je|neviem|netusim|je mi to jedno|preskoc|preskocme|neries|bez pocasia|daj mi proste|proste mi daj|vyber proste)\b/;

function isConcreteOutfitRequestV2(value) {
  const text = normalizeSemanticTextV2(value);
  if (!text || !OUTFIT_TERMS.test(text)) return false;
  if (OPINION_TERMS.test(text) && !REQUEST_TERMS.test(text)) return false;
  return REQUEST_TERMS.test(text) || EVENT_TERMS.test(text) || OUTDOOR_TERMS.test(text) ||
    TRAVEL_TERMS.test(text) || /\boutfit na\b/.test(text) || text.startsWith("outfit ");
}

function inferMandatoryGroundingV2({latestUserInput, state}) {
  const text = normalizeSemanticTextV2(latestUserInput);
  // A reply to an existing question is not automatically a brand-new outfit
  // request just because it contains the word "outfit". In particular, meta
  // replies and explicit "just give me something" skips must keep the pending
  // conversation intact so the coordinator can handle them naturally.
  if (state?.conversationMemory?.pendingQuestion && PENDING_META_OR_SKIP_TERMS.test(text)) {
    return {active: false, scope: "pending_followup", resetContext: false, requirements: null};
  }
  if (!isConcreteOutfitRequestV2(text)) {
    return {active: false, scope: "none", resetContext: false, requirements: null};
  }

  const virtual = VIRTUAL_TERMS.test(text);
  const event = EVENT_TERMS.test(text);
  const outdoor = OUTDOOR_TERMS.test(text);
  const travel = TRAVEL_TERMS.test(text);
  const localRoutine = LOCAL_ROUTINE_TERMS.test(text);
  const continuity = CONTINUITY_TERMS.test(text) && Boolean(state?.currentOutfit?.itemIds?.length);

  if (virtual || localRoutine && !event && !outdoor) {
    return {
      active: true,
      scope: "style_only",
      resetContext: !continuity,
      requirements: {weatherRequired: false, weatherLocationField: null, terrainRequiredFields: []},
    };
  }

  const weatherLocationField = event ? "eventLocation" : outdoor || travel ? "destination" : "currentLocationObservation";
  return {
    active: true,
    scope: event ? "event" : outdoor || travel ? "destination" : "local",
    resetContext: !continuity,
    requirements: {weatherRequired: true, weatherLocationField, terrainRequiredFields: []},
  };
}

function uniqueTerrainFields(...groups) {
  const allowed = new Set(["surface", "difficulty", "condition"]);
  return [...new Set(groups.flatMap((value) => Array.isArray(value) ? value : []).filter((field) => allowed.has(field)))];
}

function mergeGroundingRequirementsV2(current, incoming, mandatory = null) {
  const base = current && typeof current === "object" ? current : {weatherRequired: false, weatherLocationField: null, terrainRequiredFields: []};
  const patch = incoming && typeof incoming === "object" ? incoming : {};
  const must = mandatory && typeof mandatory === "object" ? mandatory : null;
  let locationField = patch.weatherLocationField ?? base.weatherLocationField ?? null;
  if (must?.weatherLocationField === "destination" || must?.weatherLocationField === "eventLocation") {
    locationField = must.weatherLocationField;
  } else if (must?.weatherLocationField === "currentLocationObservation") {
    if (!["destination", "eventLocation"].includes(locationField)) locationField = "currentLocationObservation";
  }
  const weatherRequired = Boolean(base.weatherRequired || patch.weatherRequired || must?.weatherRequired);
  if (!weatherRequired) locationField = null;
  return {
    weatherRequired,
    weatherLocationField: locationField,
    terrainRequiredFields: uniqueTerrainFields(base.terrainRequiredFields, patch.terrainRequiredFields, must?.terrainRequiredFields),
  };
}

function applyMandatoryGroundingV2(state, policy) {
  if (!policy?.active) return clone(state);
  const next = clone(state);
  if (policy.resetContext) {
    next.context.activity = null;
    next.context.destination = null;
    next.context.eventLocation = null;
    next.context.date = null;
    next.context.timeWindow = null;
    next.context.weather = null;
    next.context.terrain = {surface: null, difficulty: null, condition: null};
    const answered = next.conversationMemory?.answeredClarificationFields;
    if (answered && typeof answered === "object") {
      for (const key of ["destination", "eventLocation", "date", "timeWindow", "terrain.surface", "terrain.difficulty", "terrain.condition"]) delete answered[key];
    }
    // A clearly new style-only/event request supersedes a clarification from
    // the previous task. Do not let stale pending state turn the new message
    // into a location-parser input.
    if (["style_only", "event"].includes(policy.scope)) {
      next.conversationMemory.pendingQuestion = null;
      next.conversationMemory.pendingAction = null;
    }
  }
  next.context.groundingRequirements = mergeGroundingRequirementsV2(
    policy.resetContext ? {weatherRequired: false, weatherLocationField: null, terrainRequiredFields: []} : next.context.groundingRequirements,
    null,
    policy.requirements,
  );
  return next;
}

function applyEnvelopeContextPatchV2(state, statePatch, mandatory) {
  const next = clone(state);
  const context = statePatch?.context && typeof statePatch.context === "object" ? statePatch.context : {};
  for (const key of ["activity", "date", "timeWindow", "terrain"]) {
    if (Object.prototype.hasOwnProperty.call(context, key)) next.context[key] = clone(context[key]);
  }
  next.context.groundingRequirements = mergeGroundingRequirementsV2(
    next.context.groundingRequirements,
    context.groundingRequirements,
    mandatory,
  );
  return next;
}

function missingGroundingFieldV2(state) {
  const grounding = state?.context?.groundingRequirements;
  if (!grounding) return null;
  if (grounding.weatherLocationField && !state.context[grounding.weatherLocationField]) return grounding.weatherLocationField;
  if (grounding.weatherRequired) {
    if (!state.context.date) return "date";
    if (!state.context.timeWindow) return "timeWindow";
  }
  const terrain = state.context.terrain || {};
  const missingTerrain = (grounding.terrainRequiredFields || []).find((field) => terrain[field] == null);
  return missingTerrain ? `terrain.${missingTerrain}` : null;
}

function clarificationForFieldV2(field) {
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
  return {
    action: "clarify",
    assistantText: question,
    clarification: {field, question, actionId, acceptsYesNo: false},
    display: {kind: "none", itemIds: []},
  };
}

function mandatoryLocationFieldV2(policy) {
  const field = policy?.requirements?.weatherLocationField;
  return ["destination", "eventLocation"].includes(field) ? field : null;
}

function finalClarificationEnvelopeV2(out, field) {
  return {
    kind: "final",
    result: clarificationForFieldV2(field),
    statePatch: clone(out.statePatch || {}),
  };
}

function enforceEnvelopeGroundingV2(envelope, input, policy) {
  if (!envelope || typeof envelope !== "object") return envelope;
  const out = clone(envelope);
  const latestUserInput = input?.request?.latestUserInput || "";

  if (out.kind === "tool_request" && Array.isArray(out.requests)) {
    const locationRequests = out.requests.filter((request) => request?.tool === "location");
    const unsupportedLocation = locationRequests.find((request) =>
      !locationQueryIsUserGroundedV2(request?.query, latestUserInput));
    if (unsupportedLocation) {
      const requiredField = mandatoryLocationFieldV2(policy) ||
        (["destination", "eventLocation"].includes(unsupportedLocation.targetField) ? unsupportedLocation.targetField : "destination");
      out.statePatch = out.statePatch && typeof out.statePatch === "object" ? out.statePatch : {};
      out.statePatch.context = out.statePatch.context && typeof out.statePatch.context === "object" ? out.statePatch.context : {};
      if (policy?.active) {
        out.statePatch.context.groundingRequirements = mergeGroundingRequirementsV2(
          input?.session?.context?.groundingRequirements,
          out.statePatch.context.groundingRequirements,
          policy.requirements,
        );
      }
      return finalClarificationEnvelopeV2(out, requiredField);
    }
  }

  if (!policy?.active) return out;
  out.statePatch = out.statePatch && typeof out.statePatch === "object" ? out.statePatch : {};
  out.statePatch.context = out.statePatch.context && typeof out.statePatch.context === "object" ? out.statePatch.context : {};
  out.statePatch.context.groundingRequirements = mergeGroundingRequirementsV2(
    input?.session?.context?.groundingRequirements,
    out.statePatch.context.groundingRequirements,
    policy.requirements,
  );

  const shadow = applyEnvelopeContextPatchV2(input.session, out.statePatch, policy.requirements);
  const missing = missingGroundingFieldV2(shadow);

  if (out.kind === "tool_request") {
    if (["destination", "eventLocation"].includes(missing)) {
      const hasGroundedResolverRequest = Array.isArray(out.requests) && out.requests.some((request) =>
        request?.tool === "location" && request.targetField === missing &&
        locationQueryIsUserGroundedV2(request.query, latestUserInput));
      if (!hasGroundedResolverRequest) return finalClarificationEnvelopeV2(out, missing);
    }
    return out;
  }

  if (out.kind !== "final" || !missing || out.result?.action === "stop") return out;
  if (input.phase === "plan" || ["generate_outfit", "edit_outfit"].includes(out.result?.action)) {
    out.result = clarificationForFieldV2(missing);
  }
  return out;
}

function createGroundingEnforcedStylistModelV2(stylistModel, policy) {
  if (!stylistModel || typeof stylistModel.turn !== "function") throw new TypeError("stylistModel.turn is required");
  return Object.freeze({
    planningNeedsCurrentOutfit: stylistModel.planningNeedsCurrentOutfit === true,
    shouldPreloadCurrentOutfit: typeof stylistModel.shouldPreloadCurrentOutfit === "function" ?
      (input) => stylistModel.shouldPreloadCurrentOutfit(input) : undefined,
    async turn(input) {
      const envelope = await stylistModel.turn(input);
      return enforceEnvelopeGroundingV2(envelope, input, policy);
    },
  });
}

function isGreetingV2(value) {
  return new Set(["ahoj", "cau", "cauko", "nazdar", "dobry den", "servus", "hello", "hi", "hey"]).has(normalizeSemanticTextV2(value));
}

module.exports = {
  applyEnvelopeContextPatchV2,
  applyMandatoryGroundingV2,
  clarificationForFieldV2,
  createGroundingEnforcedStylistModelV2,
  enforceEnvelopeGroundingV2,
  inferMandatoryGroundingV2,
  isConcreteOutfitRequestV2,
  isGreetingV2,
  locationQueryIsUserGroundedV2,
  mergeGroundingRequirementsV2,
  missingGroundingFieldV2,
  normalizeSemanticTextV2,
};
