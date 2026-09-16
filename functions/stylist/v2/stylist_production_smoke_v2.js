"use strict";

const assert = require("node:assert/strict");
const admin = require("firebase-admin");
const {hashValue} = require("../../costs/ai_usage_v1");
const {
  deleteQaAuthUserSelf,
  exchangeQaCustomToken,
  runQaCleanupV2,
} = require("./stylist_qa_auth_cleanup_v2");

const PROJECT_ID = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "outfitoftheday-4d401";
const API_KEY = String(process.env.FIREBASE_WEB_API_KEY || "").trim();
const MAX_CALL_MS = Number(process.env.STYLIST_PROD_SMOKE_MAX_CALL_MS || 20000);
const MAX_COST_USD = Number(process.env.STYLIST_PROD_SMOKE_MAX_COST_USD || 0.02);

function bratislavaDateKeys() {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Europe/Bratislava", year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(new Date());
  const value = Object.fromEntries(parts.filter((part) => part.type !== "literal").map((part) => [part.type, part.value]));
  const base = new Date(Date.UTC(Number(value.year), Number(value.month) - 1, Number(value.day)));
  const key = (offset) => new Date(base.getTime() + offset * 86400000).toISOString().slice(0, 10);
  return {todayDateKey: key(0), tomorrowDateKey: key(1)};
}

function qualityCheck(text) {
  const value = String(text || "").trim();
  assert.ok(value.length >= 20 && value.length <= 700, `reply_length:${value.length}`);
  assert.doesNotMatch(value, /validator|toolResults|grounding|candidateId|fail-closed/i);
}

async function callCallable(idToken, data) {
  const started = Date.now();
  const response = await fetch(`https://us-east1-${PROJECT_ID}.cloudfunctions.net/stylistChatV2`, {
    method: "POST",
    headers: {"Content-Type": "application/json", Authorization: `Bearer ${idToken}`},
    body: JSON.stringify({data}),
  });
  const latencyMs = Date.now() - started;
  const json = await response.json().catch(() => ({}));
  if (!response.ok || !json.result) {
    throw new Error(`callable_failed:${response.status}:${JSON.stringify(json).slice(0, 300)}`);
  }
  return {result: json.result, latencyMs};
}

async function main() {
  if (!admin.apps.length) admin.initializeApp({projectId: PROJECT_ID});
  const db = admin.firestore();
  const auth = admin.auth();
  const stamp = Date.now();
  const dates = bratislavaDateKeys();
  const uid = `stylist_smoke_${stamp}`;
  const chatId = `smoke_chat_${stamp}`;
  const userRef = db.collection("users").doc(uid);
  const serverSessionRef = db.collection("stylistSessionsV2Server").doc(uid);
  const userKey = hashValue(uid);
  let tokenExchangeStarted = false;
  let authTokens = null;
  let report = null;
  let cleanupResult = null;

  const wardrobe = [
    ["shirt", {name: "Čierne tričko", category: "tops", canonicalType: "t_shirt", canonicalFamily: "tops",
      bodySlots: ["upper_body"], layerPosition: "base", colorProfile: {primary: {family: "black", proportion: 1}},
      colors: ["black"], warmth: 2, formality: 2, outfitFunctions: ["base_layer"], seasons: ["spring", "summer", "autumn"]}],
    ["pants", {name: "Sivé tepláky", category: "bottoms", canonicalType: "joggers", canonicalFamily: "bottoms",
      bodySlots: ["lower_body"], layerPosition: "base", colorProfile: {primary: {family: "gray", proportion: 1}},
      colors: ["gray"], warmth: 4, formality: 1, outfitFunctions: ["casual"], seasons: ["spring", "autumn"]}],
    ["sneakers", {name: "Športové tenisky", category: "footwear", canonicalType: "running_shoes", canonicalFamily: "footwear",
      bodySlots: ["feet"], layerPosition: "base", colorProfile: {primary: {family: "white", proportion: 1}},
      colors: ["white"], warmth: 2, formality: 1, outfitFunctions: ["sport"], seasons: ["spring", "summer", "autumn"]}],
    ["hoodie", {name: "Svetlomodrá mikina", category: "tops", canonicalType: "hoodie", canonicalFamily: "tops",
      bodySlots: ["upper_body"], layerPosition: "mid", colorProfile: {primary: {family: "blue", proportion: 1}},
      colors: ["blue"], warmth: 5, formality: 1, outfitFunctions: ["mid_layer"], seasons: ["spring", "autumn", "winter"]}],
  ];

  try {
    await userRef.set({_qaStylistSmoke: true, createdAt: admin.firestore.FieldValue.serverTimestamp()});
    const batch = db.batch();
    for (const [id, item] of wardrobe) {
      batch.set(userRef.collection("wardrobe").doc(id), {
        ...item,
        updatedAt: admin.firestore.Timestamp.now(),
        wardrobeItemRevision: 1,
      });
    }
    await batch.commit();

    const customToken = await auth.createCustomToken(uid);
    tokenExchangeStarted = true;
    authTokens = await exchangeQaCustomToken({apiKey: API_KEY, customToken});
    assert.equal(authTokens.localId, uid, "qa_auth_uid_mismatch");
    const idToken = authTokens.idToken;
    const base = (turnId, message) => ({
      v2SessionId: chatId,
      turnId,
      message,
      history: [],
      currentOutfitItemIds: [],
      clientContext: {...dates, timezoneOffsetMinutes: -new Date().getTimezoneOffset()},
    });

    const first = await callCallable(idToken, base(`t1_${stamp}`, "zajtra idem na túru potrebujem outfit"));
    assert.equal(first.result.failClosed, false);
    assert.equal(first.result.action, "clarify");
    assert.match(first.result.reply, /kam približne/i);

    const why = await callCallable(idToken, base(`t2_${stamp}`, "načo ti to je"));
    assert.equal(why.result.failClosed, false);
    assert.equal(why.result.action, "chat");
    assert.equal(why.result.outfitChanged, false);
    assert.deepEqual(why.result.displayItemIds, []);
    assert.match(why.result.reply, /(?:podmienk|teplot|vetr|dažď|dazd|počas|pocas)/i);
    qualityCheck(why.result.reply);

    const outfit = await callCallable(idToken, base(`t3_${stamp}`, "do Tatier"));
    assert.equal(outfit.result.failClosed, false);
    assert.equal(outfit.result.action, "generate_outfit");
    assert.ok(Array.isArray(outfit.result.resultingOutfitItemIds) && outfit.result.resultingOutfitItemIds.length >= 3);
    assert.ok(outfit.result.resultingOutfitItemIds.includes("sneakers"), "hiking_best_effort_sneakers_missing");
    qualityCheck(outfit.result.stylistComment);
    assert.match(outfit.result.stylistComment, /kompromis/i);
    assert.equal(outfit.result.quickReplyMode, "yes_no");
    assert.match(String(outfit.result.quickReplyPrompt || ""), /topán/i);
    assert.equal(outfit.result.resolvedContext?.weatherAvailable, true);
    assert.equal(outfit.result.resolvedContext?.weatherSource, "open-meteo");
    assert.equal(outfit.result.resolvedContext?.weatherDateKey, dates.tomorrowDateKey);
    assert.match(String(outfit.result.resolvedContext?.weatherLocationLabel || ""), /Vysok[eé]\s+Tatry/i);
    assert.match(String(outfit.result.resolvedContext?.weatherLocationLabel || ""), /Slovensko/i);

    const opinion = await callCallable(idToken, {
      ...base(`t4_${stamp}`, "a sú tie tepláky v pohode?"),
      currentOutfitItemIds: outfit.result.resultingOutfitItemIds,
      currentSelectionReasons: (outfit.result.resultingOutfitItems || [])
        .filter((item) => item.stylistSelectionReason)
        .map((item) => ({itemId: item.id, reason: item.stylistSelectionReason})),
    });
    assert.equal(opinion.result.failClosed, false);
    assert.equal(opinion.result.outfitChanged, false);
    assert.deepEqual(opinion.result.displayItemIds, []);
    qualityCheck(opinion.result.stylistComment);

    await new Promise((resolve) => setTimeout(resolve, 1200));
    let estimatedCost = 0;
    const usage = await db.collection("aiUsageEventsV1").where("userKey", "==", userKey).get();
    const usageEvents = usage.docs.map((doc) => doc.data() || {});
    for (const event of usageEvents) {
      estimatedCost += Number(event.estimatedCostUsd ?? event.estimatedCostUsdMax ??
        event.estimatedCostUsdMin ?? 0);
    }
    const expectedModels = new Map([
      ["stylist_v2_one_brain", "gpt-5.6-terra"],
      ["stylist_v2_selector", "gpt-5.6-terra"],
      ["stylist_v2_quality_judge", "gpt-5.6-terra"],
      ["stylist_v2_language", "gpt-5.6-luna"],
    ]);
    const stageModels = {};
    for (const event of usageEvents) {
      const feature = String(event.feature || "");
      const model = String(event.model || "");
      assert.ok(expectedModels.has(feature), `unexpected_usage_feature:${feature || "missing"}`);
      assert.ok(model.startsWith(expectedModels.get(feature)), `unexpected_model_used:${feature}:${model}`);
      (stageModels[feature] ||= []).push(model);
    }
    for (const feature of expectedModels.keys()) {
      assert.ok(stageModels[feature]?.length > 0, `production_usage_stage_missing:${feature}`);
    }
    const providerRetries = usageEvents.filter((event) => Number(event.providerAttempt) > 1).length;
    const modelRetries = usageEvents.filter((event) => Number(event.modelAttempt) > 1).length;

    report = {
      ok: true,
      latenciesMs: {clarify: first.latencyMs, why: why.latencyMs, outfit: outfit.latencyMs, opinion: opinion.latencyMs},
      usageEventCount: usageEvents.length,
      stageModels,
      providerRetries,
      modelRetries,
      estimatedCostUsd: Number(estimatedCost.toFixed(6)),
      configuredBudgets: {maxCallMs: MAX_CALL_MS, maxCostUsd: MAX_COST_USD},
    };
  } finally {
    cleanupResult = await runQaCleanupV2({
      firestoreCleanup: async () => {
        const usage = await db.collection("aiUsageEventsV1").where("userKey", "==", userKey).get();
        for (const doc of usage.docs) await doc.ref.delete();
        if (typeof db.recursiveDelete === "function") {
          await db.recursiveDelete(serverSessionRef);
          await db.recursiveDelete(userRef);
        } else {
          for (const [id] of wardrobe) await userRef.collection("wardrobe").doc(id).delete();
          const clientSessions = await userRef.collection("stylistSessionsV2").get();
          for (const doc of clientSessions.docs) await doc.ref.delete();
          const serverSessions = await serverSessionRef.collection("sessions").get();
          for (const doc of serverSessions.docs) await doc.ref.delete();
          await serverSessionRef.delete();
          await userRef.delete();
        }
        const [remainingUsage, remainingUser, remainingServerSessions] = await Promise.all([
          db.collection("aiUsageEventsV1").where("userKey", "==", userKey).get(),
          userRef.get(),
          serverSessionRef.collection("sessions").limit(1).get(),
        ]);
        assert.equal(remainingUsage.empty, true, "qa_usage_cleanup_incomplete");
        assert.equal(remainingUser.exists, false, "qa_user_cleanup_incomplete");
        assert.equal(remainingServerSessions.empty, true, "qa_server_session_cleanup_incomplete");
      },
      authCleanup: async () => {
        if (!tokenExchangeStarted) return {deleted: false, accountCreated: false};
        assert.ok(authTokens, "qa_auth_tokens_unavailable_for_cleanup");
        return deleteQaAuthUserSelf({apiKey: API_KEY, authTokens});
      },
    });
  }
  console.log(JSON.stringify({
    ...report,
    cleanup: {
      firestore: true,
      authSelfDelete: cleanupResult.auth,
    },
  }));
}

main().catch((error) => {
  console.error(`STYLIST_PRODUCTION_SMOKE_FAILED ${error?.message || error}`);
  process.exitCode = 1;
});
