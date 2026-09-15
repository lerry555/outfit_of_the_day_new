"use strict";

const {AsyncLocalStorage} = require("node:async_hooks");
const {scopedLocationQueryV2} = require("./guarded_location_resolver_v2");
const {locationIsTooBroadForWeatherV2} = require("./open_meteo_ports_v2");
const {
  createStylistChatV2Handler,
} = require("./stylist_production_bridge_one_brain_v2");

function cleanTextV2(value, max = 3000) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function normalizeActivityFirstLocationOrderV2(value) {
  const raw = cleanTextV2(value);
  if (!raw) return raw;
  const pattern = /\b(idem|ideme|pojdem|pojdeme|chystam\s+sa|chystám\s+sa|chystame\s+sa|chystáme\s+sa)\s+(?:na|za)\s+(turu|túru|turistiku|vylet|výlet|koncert|festival|svadbu|pohovor|ples|lyzovacku|lyžovačku)\s+(do|na|v|vo)\s+(.+?)(?=\s+(?:a\s+)?(?:neviem|netusim|netuším|chcem|potrebujem|co|čo)\b|[,!?]|$)/iu;
  return raw.replace(pattern, (_match, verb, activity, locationPreposition, location) =>
    `${verb} ${locationPreposition} ${String(location).trim()} na ${activity}`);
}

function qualifyPendingLocationQueryV2(query, sessionState) {
  const raw = cleanTextV2(query, 240);
  if (!raw) return raw;
  const pendingField = sessionState?.conversationMemory?.pendingQuestion?.field || null;
  if (!["destination", "eventLocation"].includes(pendingField)) return raw;
  const parent = sessionState?.context?.[pendingField] || null;
  const countryCode = String(parent?.countryCode || "").trim().toUpperCase();
  if (!locationIsTooBroadForWeatherV2(parent) || !/^[A-Z]{2}$/.test(countryCode)) return raw;
  return scopedLocationQueryV2(raw, countryCode);
}

async function existingSessionStateV2(sessionRepository, data, context) {
  const uid = cleanTextV2(context?.auth?.uid, 180);
  if (!uid || !sessionRepository || typeof sessionRepository.get !== "function") return null;
  const ids = [data?.v2SessionId || data?.chatId, data?.previousV2SessionId]
    .map((value) => cleanTextV2(value, 180))
    .filter(Boolean);
  for (const chatId of ids) {
    try {
      const existing = await sessionRepository.get({uid, chatId});
      if (existing?.state) return existing.state;
    } catch (_) {}
  }
  return null;
}

function createGroundedStylistChatV2Handler({
  handlerFactory = createStylistChatV2Handler,
  locationResolver,
  sessionRepository,
  ...dependencies
} = {}) {
  if (!locationResolver || typeof locationResolver.resolve !== "function") {
    throw new TypeError("stylist_v2_grounding_location_resolver_required");
  }
  if (!sessionRepository || typeof sessionRepository.get !== "function") {
    throw new TypeError("stylist_v2_grounding_session_repository_required");
  }
  if (typeof handlerFactory !== "function") {
    throw new TypeError("stylist_v2_grounding_handler_factory_required");
  }

  const turnContext = new AsyncLocalStorage();
  const contextualLocationResolver = Object.freeze({
    async resolve(query) {
      const sessionState = turnContext.getStore()?.sessionState || null;
      const contextualQuery = qualifyPendingLocationQueryV2(query, sessionState);
      if (contextualQuery && contextualQuery !== query) {
        try {
          const contextual = await locationResolver.resolve(contextualQuery);
          if (contextual) return contextual;
        } catch (_) {}
      }
      return locationResolver.resolve(query);
    },
  });
  const handler = handlerFactory({
    ...dependencies,
    locationResolver: contextualLocationResolver,
    sessionRepository,
  });

  return async function groundedStylistChatV2(data, context) {
    const sessionState = await existingSessionStateV2(sessionRepository, data, context);
    const originalMessage = cleanTextV2(data?.message);
    const normalizedMessage = normalizeActivityFirstLocationOrderV2(originalMessage);
    const nextData = normalizedMessage && normalizedMessage !== originalMessage ?
      {...(data || {}), message: normalizedMessage} : data;
    return turnContext.run({sessionState}, () => handler(nextData, context));
  };
}

module.exports = {
  createGroundedStylistChatV2Handler,
  normalizeActivityFirstLocationOrderV2,
  qualifyPendingLocationQueryV2,
};
