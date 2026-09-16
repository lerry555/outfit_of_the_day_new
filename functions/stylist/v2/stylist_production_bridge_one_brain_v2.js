"use strict";

const {
  clientCapabilities,
  createShoppingToolV2,
  currentLocationObservation,
  failClosedResponse,
  legacyCompatibleResponse,
  localConversationReplyV2,
  migrateProvisionalSession,
} = require("./stylist_production_bridge_v2");
const {createFirestoreStylistSessionRepositoryV2} = require("./stylist_session_repository_v2");
const {createFirestoreWardrobeToolV2} = require("./firestore_wardrobe_tool_v2");
const {
  createOpenMeteoLocationResolverV2,
  createOpenMeteoWeatherToolV2,
  locationIsTooBroadForWeatherV2,
} = require("./open_meteo_ports_v2");
const {createOpenAiOneBrainModelPortV2} = require("./openai_one_brain_model_port_v2");
const {createOpenAiOutfitSelectorV2} = require("./openai_outfit_selector_v2");
const {createOpenAiOutfitQualityJudgeV2} = require("./openai_outfit_quality_judge_v2");
const {createOpenAiStylistLanguageV2} = require("./openai_stylist_language_v2");
const {createStylistOneBrainEngineV2} = require("./stylist_one_brain_engine_v2");
const {createStylistSelectionPipelineV2} = require("./stylist_selection_pipeline_v2");
const {deterministicRemoteOutfitClarificationV2} = require("./stylist_turn_coordinator_v2");
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
  return [...new Set((Array.isArray(value) ? value : [])
    .map((entry) => clean(String(entry), 180)).filter(Boolean))].slice(0, max);
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

function specificWeatherLocationFieldV2(session) {
  const context = session?.context || {};
  if (!context.date || !context.timeWindow || context.weather) return null;
  for (const field of ["eventLocation", "destination"]) {
    const location = context[field];
    if (!location || locationIsTooBroadForWeatherV2(location)) continue;
    if (Number.isFinite(Number(location.lat)) && Number.isFinite(Number(location.lng))) return field;
  }
  return null;
}

function createDeterministicShellBrainV2(stylistBrain) {
  if (!stylistBrain || typeof stylistBrain.brainTurn !== "function") return stylistBrain;
  return Object.freeze({
    async brainTurn(input) {
      const session = input?.session || null;
      const canOwnMissingDestination = input?.stage === "tools" && session &&
        !session.context?.destination && !session.context?.eventLocation;
      if (canOwnMissingDestination) {
        const fastClarification = deterministicRemoteOutfitClarificationV2(input.request || {}, session);
        if (fastClarification) {
          const fastState = fastClarification.state;
          return {
            kind: "final",
            pendingReplyDisposition: "none",
            result: {
              ...fastClarification.decision,
              clarification: {
                ...fastClarification.decision.clarification,
                resumeAction: "generate_outfit",
              },
            },
            statePatch: {
              context: {
                activity: fastState.context.activity,
                date: fastState.context.date,
                timeWindow: fastState.context.timeWindow,
                groundingRequirements: fastState.context.groundingRequirements,
              },
            },
          };
        }
      }

      const result = await stylistBrain.brainTurn(input);
      const weatherLocationField = input?.stage === "tools" ? specificWeatherLocationFieldV2(session) : null;
      const finalAction = result?.kind === "final" ? result.result?.action : null;
      if (weatherLocationField && ["generate_outfit", "edit_outfit"].includes(finalAction)) {
        return {
          kind: "tool_request",
          pendingReplyDisposition: result.pendingReplyDisposition ?? "none",
          statePatch: result.statePatch || {},
          requests: [{tool: "wardrobe", scope: "full_relevant", category: null, editScope: null}],
        };
      }
      return result;
    },
  });
}

async function writeJobResult({db, admin, uid, notifyJobId, result}) {
  if (!notifyJobId || !db?.collection) return;
  try {
    await db.collection("users").doc(uid).collection("stylistJobs").doc(notifyJobId).set({
      status: "done",
      updatedAt: admin?.firestore?.FieldValue?.serverTimestamp ?
        admin.firestore.FieldValue.serverTimestamp() : new Date(),
      result,
    }, {merge: true});
  } catch (_) {}
}

async function sendPushBestEffort({db, admin, uid, notifyJobId, chatId, result}) {
  if (!notifyJobId || !admin?.messaging || !db?.collection) return;
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
      data: {
        type: "stylist_reply",
        jobId: notifyJobId,
        chatId: chatId || "",
      },
      android: {priority: "high"},
    });
  } catch (_) {}
}

function createStylistChatV2Handler({
  db,
  admin,
  logger = console,
  fetchImpl = fetch,
  resolveOpenAISecret,
  clock = () => Date.now(),
  sessionRepository: repositoryOverride = null,
  locationResolver: locationOverride = null,
  weatherTool: weatherOverride = null,
  brainFactory = null,
  selectorFactory = null,
  judgeFactory = null,
  languageFactory = null,
  wardrobeToolFactory = null,
  shoppingToolFactory = null,
} = {}) {
  if (!db || typeof resolveOpenAISecret !== "function") {
    throw new TypeError("stylist_v2_one_brain_production_dependencies_required");
  }

  const repository = repositoryOverride || createFirestoreStylistSessionRepositoryV2(db, {now: clock});
  const recordUsage = brainFactory ? null : createAiUsageRecorderV1({db, logger});
  const catalogOrchestrator = shoppingToolFactory ? null : createShoppingOrchestrator({
    repository: createFirestoreCatalogSearchRepository(db),
    sessionStore: createFirestoreShoppingSessionStore(db),
  });

  return async function stylistChatV2OneBrain(data, context) {
    const uid = context?.auth?.uid;
    if (!uid) {
      const error = new Error("auth_required");
      error.code = "unauthenticated";
      throw error;
    }

    const notifyJobId = safeId(data?.notifyJobId);
    const sessionId = safeId(data?.v2SessionId || data?.chatId);
    const previousSessionId = safeId(data?.previousV2SessionId);
    const turnId = safeId(data?.turnId || notifyJobId || data?.requestId);
    let message = clean(data?.message, 3000);
    if (!sessionId || !turnId || !message) {
      return failClosedResponse("Tomu úplne nerozumiem 😄 Skús mi napísať, čo riešiš s outfitom.");
    }

    const turnStartedAt = Date.now();
    try {
      await migrateProvisionalSession({repository, uid, previousSessionId, sessionId});
      const existing = await repository.get({uid, chatId: sessionId});

      // Shopping execution remains a typed tool workflow. It does not decide
      // stylist conversation or inject clarification questions above the Brain.
      const clientShoppingContext = safeMap(data?.shoppingContext);
      const shoppingActive = Boolean(
        clientShoppingContext.sessionId ||
        clientShoppingContext.activeClarification ||
        clientShoppingContext.pendingSourceText ||
        clientShoppingContext.pendingNeedText ||
        clientShoppingContext.pendingWishlistOfferVariantId,
      );
      if (catalogOrchestrator && shoppingActive) {
        const shoppingTurn = await handleStylistShoppingTurn({
          auth: {uid},
          message,
          shoppingContext: clientShoppingContext,
          orchestrator: catalogOrchestrator,
        });
        if (shoppingTurn.handled) {
          const shoppingResponse = {
            ...shoppingTurn.response,
            v2: true,
            sessionId,
            sessionRevision: existing?.state?.revision ?? 0,
          };
          await writeJobResult({db, admin, uid, notifyJobId, result: shoppingResponse});
          return shoppingResponse;
        }
        if (shoppingTurn.passThroughMessage) {
          message = clean(shoppingTurn.passThroughMessage, 3000) || message;
        }
      }

      // A deterministic greeting is a zero-intelligence latency shortcut, not
      // a competing conversational brain. Every substantive stylist turn below
      // is owned by the One-Brain model except product-shell clarifications that
      // deterministically protect date/location/session grounding.
      const localReply = !shoppingActive ? localConversationReplyV2(message) : null;
      if (localReply) {
        const response = {
          ok: true,
          simpleAgent: true,
          v2: true,
          failClosed: false,
          contractVersion: 2,
          modelPath: "stylist_v2_local_chat",
          sessionId,
          sessionRevision: existing?.state?.revision ?? 0,
          reply: localReply,
          stylistComment: localReply,
          resultingOutfitItemIds: [],
          displayItemIds: [],
          resultingOutfitItems: [],
          displayItems: [],
          outfitChanged: false,
          quickReplyMode: "none",
          quickReplyPrompt: null,
          action: "chat",
        };
        logger?.info?.("STYLIST_V2_TURN_LATENCY", {
          path: "local_chat",
          totalMs: Date.now() - turnStartedAt,
        });
        await writeJobResult({db, admin, uid, notifyJobId, result: response});
        return response;
      }

      const executeForStage = (feature) => createOpenAiSimpleAgentExecutorV1({
        fetchImpl,
        resolveOpenAISecret,
        logger,
        feature,
        cacheScope: `${uid}:${feature}`,
        recordUsage: (event) => recordUsage?.({
          ...event,
          userKey: hashValue(uid),
          requestKey: hashValue([uid, turnId, feature]),
        }),
      });
      const executeStructured = brainFactory ? null : executeForStage("stylist_v2_one_brain");
      const rawStylistBrain = brainFactory ? brainFactory({uid, turnId, data}) :
        createOpenAiOneBrainModelPortV2({
          userStylePreferences: safeMap(data?.userStylePreferences),
          executeStructured,
        });
      const stylistBrain = createDeterministicShellBrainV2(rawStylistBrain);
      const useSelectionArchitecture = !brainFactory ||
        Boolean(selectorFactory && judgeFactory && languageFactory);
      const selector = useSelectionArchitecture ? (selectorFactory ?
        selectorFactory({uid, turnId, data}) : createOpenAiOutfitSelectorV2({
          executeStructured: executeForStage("stylist_v2_selector"), logger,
        })) : null;
      const judge = useSelectionArchitecture ? (judgeFactory ?
        judgeFactory({uid, turnId, data}) : createOpenAiOutfitQualityJudgeV2({
          executeStructured: executeForStage("stylist_v2_quality_judge"), logger,
        })) : null;
      const languageGenerator = useSelectionArchitecture ? (languageFactory ?
        languageFactory({uid, turnId, data}) : createOpenAiStylistLanguageV2({
          executeStructured: executeForStage("stylist_v2_language"), logger,
        })) : null;
      const selectionPipeline = useSelectionArchitecture ? createStylistSelectionPipelineV2({
        selector, judge, logger,
      }) : null;

      const wardrobeTool = wardrobeToolFactory ?
        wardrobeToolFactory({uid}) : createFirestoreWardrobeToolV2({db, uid});
      const currentIds = uniqueIds(data?.currentOutfitItemIds, 12);
      const persistedReasonsByItemId = reasonsMap(data?.currentSelectionReasons);
      const canonicalCurrentIds = uniqueIds(existing?.state?.currentOutfit?.itemIds, 12);
      let knownWardrobeItems = null;
      if (canonicalCurrentIds.length || currentIds.length) {
        try {
          knownWardrobeItems = await wardrobeTool.retrieve({
            scope: "full_relevant",
            itemIds: canonicalCurrentIds.length ? canonicalCurrentIds : currentIds,
            category: null,
          });
        } catch (_) {
          knownWardrobeItems = null;
        }
      }
      const locationResolver = locationOverride || createOpenMeteoLocationResolverV2({fetchImpl});
      const weatherTool = weatherOverride || createOpenMeteoWeatherToolV2({fetchImpl, clock});
      const shoppingTool = shoppingToolFactory ?
        shoppingToolFactory({uid}) : createShoppingToolV2({uid, orchestrator: catalogOrchestrator});
      const engine = createStylistOneBrainEngineV2({
        sessionRepository: repository,
        wardrobeTool,
        locationResolver,
        weatherTool,
        shoppingTool,
        stylistBrain,
        selectionPipeline,
        languageGenerator,
        userStylePreferences: safeMap(data?.userStylePreferences),
        clock,
        logger,
      });

      const clientContext = safeMap(data?.clientContext);
      const observation = currentLocationObservation(clientContext, clock);
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
        knownWardrobeItems,
        bootstrapInput: existing ? null : {
          currentOutfitItemIds: currentIds,
          persistedSelectionReasonsByItemId: persistedReasonsByItemId,
          knownExplicitDurableChoices: {},
        },
      });
      const engineMs = Date.now() - engineStartedAt;
      const materializeStartedAt = Date.now();
      const materialized = await legacyCompatibleResponse({result, sessionId, wardrobeTool});
      let finalState = null;
      try { finalState = (await repository.get({uid, chatId: sessionId}))?.state || null; } catch (_) {}
      const weather = finalState?.context?.weather || null;
      const weatherField = finalState?.context?.groundingRequirements?.weatherLocationField || null;
      const weatherLocation = weatherField ? finalState?.context?.[weatherField] : null;
      const resolvedContext = {
        targetDateKey: finalState?.context?.date?.dateKey || null,
        dateSource: finalState?.context?.date?.source || null,
        weatherAvailable: Boolean(weather),
        weatherDateKey: weather?.dateKey || null,
        weatherSource: weather?.source || null,
        weatherLocationLabel: weatherLocation?.label || null,
        weatherSummary: weather?.snapshot ? {
          representativeTempC: weather.snapshot.representativeTempC ?? null,
          minTempC: weather.snapshot.minTempC ?? null,
          maxTempC: weather.snapshot.maxTempC ?? null,
          willRain: weather.snapshot.willRain ?? null,
          willSnow: weather.snapshot.willSnow ?? null,
          isWindy: weather.snapshot.isWindy ?? null,
          maxWindKph: weather.snapshot.maxWindKph ?? null,
        } : null,
      };
      const response = {...materialized, modelPath: "stylist_v2_one_brain", resolvedContext};

      logger?.info?.("STYLIST_V2_RESOLVED_CONTEXT", {
        action: result.action,
        targetDateKey: resolvedContext.targetDateKey,
        dateSource: resolvedContext.dateSource,
        weatherAvailable: resolvedContext.weatherAvailable,
        weatherDateKey: resolvedContext.weatherDateKey,
        weatherSource: resolvedContext.weatherSource,
        weatherLocationLabel: resolvedContext.weatherLocationLabel,
      });
      logger?.info?.("STYLIST_V2_TURN_LATENCY", {
        path: "one_brain",
        totalMs: Date.now() - turnStartedAt,
        engineMs,
        materializeMs: Date.now() - materializeStartedAt,
        action: result.action,
      });
      await writeJobResult({db, admin, uid, notifyJobId, result: response});
      await sendPushBestEffort({
        db,
        admin,
        uid,
        notifyJobId,
        chatId: clean(data?.chatId, 160),
        result: response,
      });
      return response;
    } catch (error) {
      logger?.warn?.("STYLIST_V2_ONE_BRAIN_FAIL_CLOSED", {
        code: clean(error?.code || error?.message, 160),
        totalMs: Date.now() - turnStartedAt,
      });
      const response = failClosedResponse();
      await writeJobResult({db, admin, uid, notifyJobId, result: response});
      return response;
    }
  };
}

module.exports = {
  createDeterministicShellBrainV2,
  createStylistChatV2Handler,
  reasonsMap,
  safeId,
  safeMap,
  specificWeatherLocationFieldV2,
  uniqueIds,
};
