"use strict";

const {clone} = require("./stylist_session_state_v2");
const {createFirestoreStylistSessionRepositoryV2} = require("./stylist_session_repository_v2");
const {createStylistTurnEngineV2} = require("./stylist_turn_engine_v2");
const {createFirestoreWardrobeToolV2} = require("./firestore_wardrobe_tool_v2");
const {createOpenMeteoLocationResolverV2, createOpenMeteoWeatherToolV2} = require("./open_meteo_ports_v2");
const {createOpenAiStylistModelPortV2} = require("./openai_stylist_model_port_v2");
const {createStylistFastChatV2, isFastChatEligibleV2} = require("./stylist_fast_chat_v2");
const {createOpenAiSimpleAgentExecutorV1} = require("../simple_stylist_agent_v1");
const {createFirestoreCatalogSearchRepository} = require("../../shopping/catalog_search_repository");
const {createFirestoreShoppingSessionStore} = require("../../shopping/shopping_session_store");
const {createShoppingOrchestrator} = require("../../shopping/shopping_orchestration_service");
const {handleStylistShoppingTurn} = require("../../shopping/stylist_shopping_runtime");
const {createAiUsageRecorderV1, hashValue} = require("../../costs/ai_usage_v1");

function clean(value, max = 3000) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}
function safeId(value) {
  const text = clean(value, 160).replace(/[^A-Za-z0-9_-]/g, "_");
  return text || null;
}
function safeMap(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}
function uniqueIds(value, max = 20) {
  return [...new Set((Array.isArray(value) ? value : []).map((x) => clean(String(x), 180)).filter(Boolean))].slice(0, max);
}

function normalizeLocalConversationTextV2(value) {
  return clean(value, 500)
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function localConversationReplyV2(message) {
  const text = normalizeLocalConversationTextV2(message);
  if (/^(ahoj|cau|cauko|nazdar|servus|hello|hi|hey)(?:\s+(divocak|kamo|kamarat|stylista))?$/.test(text)) {
    return "Ahoj! Ako ti môžem pomôcť?";
  }
  if (/^(ahoj|cau|cauko|nazdar|servus|hello|hi|hey)(?:\s+(divocak|kamo|kamarat|stylista))?\s+(potrebujem|chcem|mohol by si|mozes mi)\s+(poradit|poradis)$/.test(text)) {
    return "Ahoj! Jasné 🙂 S čím ti môžem pomôcť?";
  }
  return null;
}

function reasonsMap(raw) {
  const out = {};
  for (const entry of Array.isArray(raw) ? raw : []) {
    const id = clean(entry?.itemId, 180);
    const reason = clean(entry?.reason, 300);
    if (id && reason) out[id] = reason;
  }
  return out;
}

function currentLocationObservation(clientContext, clock) {
  const context = safeMap(clientContext);
  const lat = Number(context.latitude);
  const lng = Number(context.longitude);
  const label = clean(context.userGpsLocation, 200);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || !label) return null;
  return {
    providerId: `gps:${lat.toFixed(5)},${lng.toFixed(5)}`,
    label,
    lat,
    lng,
    source: "device_gps",
    observedAt: new Date(clock()).toISOString(),
  };
}

function clientCapabilities(data) {
  const context = safeMap(data?.clientContext);
  const recentHistory = (Array.isArray(data?.history) ? data.history : [])
    .slice(-6)
    .map((entry) => ({
      role: entry?.role === "assistant" ? "assistant" : "user",
      content: clean(entry?.content, 700),
    }))
    .filter((entry) => entry.content);
  return {
    shoppingEnabled: data?.shoppingEnabled === true,
    supportsProgress: true,
    todayDateKey: clean(context.todayDateKey, 20) || null,
    tomorrowDateKey: clean(context.tomorrowDateKey, 20) || null,
    timezoneOffsetMinutes: Number.isFinite(Number(context.timezoneOffsetMinutes)) ? Number(context.timezoneOffsetMinutes) : null,
    recentHistory,
  };
}

function extractCandidateIds(response) {
  const ids = [];
  const scan = (value) => {
    if (!value) return;
    if (Array.isArray(value)) return value.forEach(scan);
    if (typeof value !== "object") return;
    for (const key of ["variantId", "candidateId", "id"]) {
      const id = clean(value[key], 180);
      if (id && (/shopping|candidate|variant/i.test(String(value.kind || "")) || key !== "id")) ids.push(id);
    }
    for (const child of Object.values(value)) scan(child);
  };
  scan(response?.messageAttachments);
  return [...new Set(ids)].slice(0, 24);
}

function createShoppingToolV2({uid, orchestrator}) {
  return Object.freeze({
    async search(context) {
      const need = safeMap(context.missingNeed);
      const label = clean(need.canonicalType || need.label || context.openedReason, 180);
      if (!label) {
        return {
          candidateIds: [],
          appliedHardConstraints: clone(context.hardConstraints || []),
          reply: "Najprv potrebujem vedieť, aký kúsok ti v šatníku chýba.",
          legacyResponse: null,
        };
      }
      const turn = await handleStylistShoppingTurn({
        auth: {uid},
        message: "Áno",
        shoppingContext: {
          activeClarification: "SHOPPING_PERMISSION",
          pendingNeedText: `Chcem si kúpiť ${label}`,
        },
        orchestrator,
      });
      const response = turn?.handled ? turn.response : null;
      return {
        candidateIds: extractCandidateIds(response),
        appliedHardConstraints: clone(context.hardConstraints || []),
        reply: clean(response?.reply, 900) || "Pozrel som možnosti, ktoré zodpovedajú tomu, čo ti chýba.",
        legacyResponse: response ? clone(response) : null,
      };
    },
  });
}

async function migrateProvisionalSession({repository, uid, previousSessionId, sessionId}) {
  if (!previousSessionId || previousSessionId === sessionId) return;
  const existingTarget = await repository.get({uid, chatId: sessionId});
  if (existingTarget) return;
  const previous = await repository.get({uid, chatId: previousSessionId});
  if (!previous?.state) return;
  const migrated = clone(previous.state);
  migrated.chatId = sessionId;
  await repository.ensure({uid, chatId: sessionId, bootstrapState: migrated});
}

async function writeJobResult({db, admin, uid, notifyJobId, result}) {
  if (!notifyJobId) return;
  try {
    await db.collection("users").doc(uid).collection("stylistJobs").doc(notifyJobId).set({
      status: "done",
      updatedAt: admin?.firestore?.FieldValue?.serverTimestamp ? admin.firestore.FieldValue.serverTimestamp() : new Date(),
      result,
    }, {merge: true});
  } catch (_) {}
}

async function sendPushBestEffort({db, admin, uid, notifyJobId, chatId, result}) {
  if (!notifyJobId || !admin?.messaging) return;
  try {
    const user = await db.collection("users").doc(uid).get();
    const tokens = uniqueIds(user.data()?.fcmTokens, 50);
    if (!tokens.length) return;
    await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: "Tvoj stylista odpovedal 👗",
        body: clean(result.reply, 140) || "Odpoveď je pripravená.",
      },
      data: {type: "stylist_reply", jobId: notifyJobId, chatId: chatId || ""},
      android: {priority: "high"},
    });
  } catch (_) {}
}

function legacyCompatibleResponse({result, sessionId, wardrobeTool}) {
  return wardrobeTool.materialize(result.resultingOutfit?.itemIds || [], result.resultingOutfit?.selectionReasonsByItemId || {})
    .then(async (resultingItems) => {
      if (result.action === "shop" && result.shoppingResult?.legacyResponse) {
        return {...clone(result.shoppingResult.legacyResponse), v2: true, sessionId, sessionRevision: result.resultingSessionRevision};
      }
      const byId = new Map(resultingItems.map((item) => [item.id, item]));
      const displayIds = ["outfit", "items"].includes(result.display?.kind) ? uniqueIds(result.display.itemIds, 12) : [];
      const displayItems = displayIds.map((id) => byId.get(id)).filter(Boolean);
      const currentIds = result.resultingOutfit?.itemIds || [];
      const quickLabels = (result.quickReplies || []).map((entry) => String(entry.label || "").toLocaleLowerCase("sk-SK"));
      const yesNo = quickLabels.includes("áno") && quickLabels.includes("nie");
      return {
        ok: true,
        simpleAgent: true,
        v2: true,
        failClosed: false,
        contractVersion: 2,
        modelPath: "stylist_v2",
        sessionId,
        sessionRevision: result.resultingSessionRevision,
        reply: result.assistantText,
        stylistComment: result.assistantText,
        resultingOutfitItemIds: currentIds,
        displayItemIds: displayIds,
        outfitChanged: ["generate_outfit", "edit_outfit"].includes(result.action),
        quickReplyMode: yesNo ? "yes_no" : "none",
        quickReplyPrompt: yesNo ? clean(result.quickReplyPrompt, 240) || null : null,
        resultingOutfitItems: resultingItems,
        displayItems,
        action: result.action,
      };
    });
}

function failClosedResponse(message = "Túto požiadavku sa mi nepodarilo bezpečne dokončiť, takže aktuálny outfit nemením.") {
  return {
    ok: false, simpleAgent: true, v2: true, failClosed: true,
    reply: message, stylistComment: message,
    resultingOutfitItemIds: [], displayItemIds: [], resultingOutfitItems: [], displayItems: [],
    outfitChanged: false, quickReplyMode: "none", action: "simple_agent_fail_closed",
  };
}

function createStylistChatV2Handler({db, admin, logger = console, fetchImpl = fetch, resolveOpenAISecret,
  clock = () => Date.now(), sessionRepository: repositoryOverride = null,
  locationResolver: locationOverride = null, weatherTool: weatherOverride = null,
  modelFactory = null, fastChatFactory = null, wardrobeToolFactory = null, shoppingToolFactory = null} = {}) {
  if (!db || typeof resolveOpenAISecret !== "function") throw new TypeError("stylist_v2_production_dependencies_required");
  const repository = repositoryOverride || createFirestoreStylistSessionRepositoryV2(db, {now: clock});
  const recordUsage = modelFactory ? null : createAiUsageRecorderV1({db, logger});
  const catalogOrchestrator = shoppingToolFactory ? null : createShoppingOrchestrator({
    repository: createFirestoreCatalogSearchRepository(db),
    sessionStore: createFirestoreShoppingSessionStore(db),
  });

  return async function stylistChatV2(data, context) {
    const uid = context?.auth?.uid;
    if (!uid) {
      const error = new Error("auth_required"); error.code = "unauthenticated"; throw error;
    }
    const notifyJobId = safeId(data?.notifyJobId);
    const sessionId = safeId(data?.v2SessionId || data?.chatId);
    const previousSessionId = safeId(data?.previousV2SessionId);
    const turnId = safeId(data?.turnId || notifyJobId || data?.requestId);
    let message = clean(data?.message, 3000);
    if (!sessionId || !turnId || !message) return failClosedResponse("Tomu úplne nerozumiem 😄 Skús mi napísať, čo riešiš s outfitom.");
    const turnStartedAt = Date.now();

    try {
      await migrateProvisionalSession({repository, uid, previousSessionId, sessionId});
      const existing = await repository.get({uid, chatId: sessionId});

      const clientShoppingContext = safeMap(data?.shoppingContext);
      const shoppingActive = Boolean(clientShoppingContext.sessionId || clientShoppingContext.activeClarification ||
        clientShoppingContext.pendingSourceText || clientShoppingContext.pendingNeedText ||
        clientShoppingContext.pendingWishlistOfferVariantId);
      if (catalogOrchestrator && shoppingActive) {
        const shoppingTurn = await handleStylistShoppingTurn({
          auth: {uid}, message, shoppingContext: clientShoppingContext, orchestrator: catalogOrchestrator,
        });
        if (shoppingTurn.handled) {
          const shoppingResponse = {...shoppingTurn.response, v2: true, sessionId,
            sessionRevision: existing?.state?.revision ?? 0};
          await writeJobResult({db, admin, uid, notifyJobId, result: shoppingResponse});
          return shoppingResponse;
        }
        if (shoppingTurn.passThroughMessage) message = clean(shoppingTurn.passThroughMessage, 3000) || message;
      }

      const localReply = !shoppingActive ? localConversationReplyV2(message) : null;
      if (localReply) {
        const response = {
          ok: true, simpleAgent: true, v2: true, failClosed: false, contractVersion: 2,
          modelPath: "stylist_v2_local_chat", sessionId, sessionRevision: existing?.state?.revision ?? 0,
          reply: localReply, stylistComment: localReply,
          resultingOutfitItemIds: [], displayItemIds: [], resultingOutfitItems: [], displayItems: [],
          outfitChanged: false, quickReplyMode: "none", quickReplyPrompt: null, action: "chat",
        };
        logger?.info?.("STYLIST_V2_TURN_LATENCY", {path: "local_chat", totalMs: Date.now() - turnStartedAt});
        await writeJobResult({db, admin, uid, notifyJobId, result: response});
        return response;
      }

      const executeStructured = modelFactory ? null : createOpenAiSimpleAgentExecutorV1({
        fetchImpl, resolveOpenAISecret, logger, feature: "stylist_v2", cacheScope: `${uid}:stylist-v2`,
        recordUsage: (event) => recordUsage({...event, userKey: hashValue(uid), requestKey: hashValue([uid, turnId, "v2"])}),
      });
      const fastChat = fastChatFactory ? fastChatFactory({uid, turnId}) :
        (executeStructured ? createStylistFastChatV2({executeStructured}) : null);
      if (fastChat && isFastChatEligibleV2({
        message,
        state: existing?.state || null,
        currentOutfitItemIds: uniqueIds(data?.currentOutfitItemIds, 12),
        shoppingActive,
      })) {
        const fastStartedAt = Date.now();
        const fastResult = await fastChat.turn({message, history: data?.history});
        const response = {
          ok: true, simpleAgent: true, v2: true, failClosed: false, contractVersion: 2,
          modelPath: "stylist_v2_fast_chat", sessionId, sessionRevision: existing?.state?.revision ?? 0,
          reply: fastResult.reply, stylistComment: fastResult.reply,
          resultingOutfitItemIds: [], displayItemIds: [], resultingOutfitItems: [], displayItems: [],
          outfitChanged: false, quickReplyMode: "none", quickReplyPrompt: null, action: "chat",
        };
        logger?.info?.("STYLIST_V2_TURN_LATENCY", {
          path: "fast_chat",
          totalMs: Date.now() - turnStartedAt,
          modelPathMs: Date.now() - fastStartedAt,
        });
        await writeJobResult({db, admin, uid, notifyJobId, result: response});
        await sendPushBestEffort({db, admin, uid, notifyJobId, chatId: clean(data?.chatId, 160), result: response});
        return response;
      }

      const wardrobeTool = wardrobeToolFactory ? wardrobeToolFactory({uid}) : createFirestoreWardrobeToolV2({db, uid});
      const locationResolver = locationOverride || createOpenMeteoLocationResolverV2({fetchImpl});
      const weatherTool = weatherOverride || createOpenMeteoWeatherToolV2({fetchImpl, clock});
      const shoppingTool = shoppingToolFactory ? shoppingToolFactory({uid}) : createShoppingToolV2({uid, orchestrator: catalogOrchestrator});
      const stylistModel = modelFactory ? modelFactory({uid, turnId}) : createOpenAiStylistModelPortV2({
        userStylePreferences: safeMap(data?.userStylePreferences),
        executeStructured,
      });
      const engine = createStylistTurnEngineV2({
        sessionRepository: repository, wardrobeTool, locationResolver, weatherTool, shoppingTool, stylistModel, clock,
      });
      const clientContext = safeMap(data?.clientContext);
      const observation = currentLocationObservation(clientContext, clock);
      const currentIds = uniqueIds(data?.currentOutfitItemIds, 12);
      const persistedReasonsByItemId = reasonsMap(data?.currentSelectionReasons);
      const request = {
        chatId: sessionId,
        turnId,
        expectedSessionRevision: existing?.state?.revision ?? 0,
        latestUserInput: message,
        explicitUiActionId: clean(data?.explicitUiActionId, 160) || null,
        freshClientObservations: observation ? {currentLocationObservation: observation} : {},
        clientCapabilities: clientCapabilities(data),
      };
      const engineStartedAt = Date.now();
      const result = await engine.resolveTurn({
        uid,
        request,
        knownCanonicalState: existing?.state || null,
        bootstrapInput: existing ? null : {
          currentOutfitItemIds: currentIds,
          persistedSelectionReasonsByItemId: persistedReasonsByItemId,
          knownExplicitDurableChoices: {},
        },
      });
      const engineMs = Date.now() - engineStartedAt;
      const materializeStartedAt = Date.now();
      const response = await legacyCompatibleResponse({result, sessionId, wardrobeTool});
      logger?.info?.("STYLIST_V2_TURN_LATENCY", {
        path: "agent",
        totalMs: Date.now() - turnStartedAt,
        engineMs,
        materializeMs: Date.now() - materializeStartedAt,
        action: result.action,
      });
      await writeJobResult({db, admin, uid, notifyJobId, result: response});
      await sendPushBestEffort({db, admin, uid, notifyJobId, chatId: clean(data?.chatId, 160), result: response});
      return response;
    } catch (error) {
      logger?.warn?.("STYLIST_V2_FAIL_CLOSED", {code: clean(error?.code || error?.message, 120), totalMs: Date.now() - turnStartedAt});
      const response = failClosedResponse();
      await writeJobResult({db, admin, uid, notifyJobId, result: response});
      return response;
    }
  };
}

module.exports = {
  clientCapabilities,
  createShoppingToolV2,
  createStylistChatV2Handler,
  currentLocationObservation,
  extractCandidateIds,
  failClosedResponse,
  legacyCompatibleResponse,
  localConversationReplyV2,
  migrateProvisionalSession,
};
