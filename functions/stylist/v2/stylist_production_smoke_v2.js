"use strict";

const assert = require("node:assert/strict");
const admin = require("firebase-admin");
const {hashValue} = require("../../costs/ai_usage_v1");

const PROJECT_ID = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "outfitoftheday-4d401";
const API_KEY = String(process.env.FIREBASE_WEB_API_KEY || "").trim();
const MAX_CALL_MS = Number(process.env.STYLIST_PROD_SMOKE_MAX_CALL_MS || 20000);
const MAX_COST_USD = Number(process.env.STYLIST_PROD_SMOKE_MAX_COST_USD || 0.02);

function qualityCheck(text) {
  const value = String(text || "").trim();
  assert.ok(value.length >= 20 && value.length <= 700, `reply_length:${value.length}`);
  assert.doesNotMatch(value, /validator|toolResults|grounding|candidateId|fail-closed/i);
}

async function exchangeCustomToken(customToken) {
  assert.ok(API_KEY, "FIREBASE_WEB_API_KEY is required");
  const response = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${encodeURIComponent(API_KEY)}`, {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({token: customToken, returnSecureToken: true}),
  });
  const json = await response.json();
  if (!response.ok) throw new Error(`firebase_token_exchange_failed:${response.status}:${json?.error?.message || "unknown"}`);
  assert.ok(json.idToken);
  return json.idToken;
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
  assert.ok(latencyMs <= MAX_CALL_MS, `production_callable_latency_budget_exceeded:${latencyMs}`);
  return {result: json.result, latencyMs};
}

async function main() {
  if (!admin.apps.length) admin.initializeApp({projectId: PROJECT_ID});
  const db = admin.firestore();
  const auth = admin.auth();
  const stamp = Date.now();
  const uid = `stylist_smoke_${stamp}`;
  const chatId = `smoke_chat_${stamp}`;
  const userRef = db.collection("users").doc(uid);
  const usageDocs = [];
  const requestKeys = [];

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
    const idToken = await exchangeCustomToken(customToken);
    const base = (turnId, message) => {
      requestKeys.push(hashValue([uid, turnId, "v2"]));
      return {
        v2SessionId: chatId,
        turnId,
        message,
        history: [],
        currentOutfitItemIds: [],
        clientContext: {todayDateKey: "2026-09-09", tomorrowDateKey: "2026-09-10", timezoneOffsetMinutes: 120},
      };
    };

    const first = await callCallable(idToken, base(`t1_${stamp}`, "zajtra idem na túru potrebujem outfit"));
    assert.equal(first.result.failClosed, false);
    assert.equal(first.result.action, "clarify");
    assert.match(first.result.reply, /kam približne/i);

    const why = await callCallable(idToken, base(`t2_${stamp}`, "načo ti to je"));
    assert.equal(why.result.failClosed, false);
    assert.equal(why.result.action, "clarify");
    assert.match(why.result.reply, /počas/i);

    const outfit = await callCallable(idToken, base(`t3_${stamp}`, "do Tatier"));
    assert.equal(outfit.result.failClosed, false);
    assert.equal(outfit.result.action, "generate_outfit");
    assert.ok(Array.isArray(outfit.result.resultingOutfitItemIds) && outfit.result.resultingOutfitItemIds.length >= 3);
    qualityCheck(outfit.result.stylistComment);
    assert.equal(outfit.result.quickReplyMode, "yes_no");
    assert.match(String(outfit.result.quickReplyPrompt || ""), /turistick.*topán/i);

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
    const models = [];
    for (const requestKey of requestKeys) {
      const snap = await db.collection("aiUsageEventsV1").where("requestKey", "==", requestKey).get();
      for (const doc of snap.docs) {
        usageDocs.push(doc.ref);
        const data = doc.data() || {};
        if (data.model) models.push(String(data.model));
        estimatedCost += Number(data.estimatedCostUsd ?? data.estimatedCostUsdMax ?? data.estimatedCostUsdMin ?? 0);
      }
    }
    assert.ok(models.every((model) => model.startsWith("gpt-5.6-luna")), `large_model_used:${models.join(",")}`);
    assert.ok(models.length <= 3, `production_model_call_budget_exceeded:${models.length}`);
    assert.ok(estimatedCost <= MAX_COST_USD, `production_smoke_cost_budget_exceeded:${estimatedCost}`);

    console.log(JSON.stringify({
      ok: true,
      latenciesMs: {clarify: first.latencyMs, why: why.latencyMs, outfit: outfit.latencyMs, opinion: opinion.latencyMs},
      models,
      estimatedCostUsd: Number(estimatedCost.toFixed(6)),
    }));
  } finally {
    for (const ref of usageDocs) await ref.delete().catch(() => {});
    if (typeof db.recursiveDelete === "function") {
      await db.recursiveDelete(userRef).catch(() => {});
    } else {
      for (const [id] of wardrobe) await userRef.collection("wardrobe").doc(id).delete().catch(() => {});
      const sessions = await userRef.collection("stylistSessionsV2").get().catch(() => null);
      if (sessions) for (const doc of sessions.docs) await doc.ref.delete().catch(() => {});
      await userRef.delete().catch(() => {});
    }
    await auth.deleteUser(uid).catch(() => {});
  }
}

main().catch((error) => {
  console.error(`STYLIST_PRODUCTION_SMOKE_FAILED ${error?.message || error}`);
  process.exitCode = 1;
});
