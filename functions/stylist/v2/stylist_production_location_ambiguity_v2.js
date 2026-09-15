"use strict";

const assert = require("node:assert/strict");
const admin = require("firebase-admin");
const {hashValue} = require("../../costs/ai_usage_v1");

const PROJECT_ID = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "outfitoftheday-4d401";
const API_KEY = String(process.env.FIREBASE_WEB_API_KEY || "").trim();
const CALL_TIMEOUT_MS = Number(process.env.STYLIST_MATRIX_CALL_TIMEOUT_MS || 45000);

function bratislavaDateKeys() {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Europe/Bratislava", year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(new Date());
  const value = Object.fromEntries(parts.filter((part) => part.type !== "literal")
    .map((part) => [part.type, part.value]));
  const base = new Date(Date.UTC(Number(value.year), Number(value.month) - 1, Number(value.day)));
  const key = (offset) => new Date(base.getTime() + offset * 86400000).toISOString().slice(0, 10);
  return {todayDateKey: key(0), tomorrowDateKey: key(1)};
}

async function exchangeCustomToken(customToken) {
  assert.ok(API_KEY, "FIREBASE_WEB_API_KEY is required");
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${encodeURIComponent(API_KEY)}`,
    {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({token: customToken, returnSecureToken: true}),
    },
  );
  const json = await response.json();
  if (!response.ok) throw new Error(`firebase_token_exchange_failed:${response.status}:${json?.error?.message || "unknown"}`);
  assert.ok(json.idToken);
  return json.idToken;
}

async function callCallable(idToken, data) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), CALL_TIMEOUT_MS);
  const started = Date.now();
  try {
    const response = await fetch(`https://us-east1-${PROJECT_ID}.cloudfunctions.net/stylistChatV2`, {
      method: "POST",
      headers: {"Content-Type": "application/json", Authorization: `Bearer ${idToken}`},
      body: JSON.stringify({data}),
      signal: controller.signal,
    });
    const latencyMs = Date.now() - started;
    const json = await response.json().catch(() => ({}));
    if (!response.ok || !json.result) {
      throw new Error(`callable_failed:${response.status}:${JSON.stringify(json).slice(0, 300)}`);
    }
    return {result: json.result, latencyMs};
  } finally {
    clearTimeout(timer);
  }
}

const WARDROBE = [
  ["tee_black", {
    name: "Čierne tričko", category: "tops", canonicalType: "t_shirt", canonicalFamily: "tops",
    bodySlots: ["upper_body"], layerPosition: "base", colorProfile: {primary: {family: "black", proportion: 1}},
    colors: ["black"], warmth: 2, formality: 2, outfitFunctions: ["base_layer", "casual"],
    seasons: ["spring", "summer", "autumn"],
  }],
  ["jacket_black", {
    name: "Čierna bunda", category: "tops", canonicalType: "jacket", canonicalFamily: "outerwear",
    bodySlots: ["upper_body"], layerPosition: "outer", colorProfile: {primary: {family: "black", proportion: 1}},
    colors: ["black"], warmth: 6, formality: 3, outfitFunctions: ["outer_layer"],
    seasons: ["spring", "autumn", "winter"],
  }],
  ["joggers_gray", {
    name: "Sivé tepláky", category: "bottoms", canonicalType: "joggers", canonicalFamily: "bottoms",
    bodySlots: ["lower_body"], layerPosition: "base", colorProfile: {primary: {family: "gray", proportion: 1}},
    colors: ["gray"], warmth: 4, formality: 1, outfitFunctions: ["casual", "sport"],
    seasons: ["spring", "autumn"],
  }],
  ["sneakers_white", {
    name: "Biele športové tenisky", category: "footwear", canonicalType: "running_shoes", canonicalFamily: "footwear",
    bodySlots: ["feet"], layerPosition: "base", colorProfile: {primary: {family: "white", proportion: 1}},
    colors: ["white"], warmth: 2, formality: 1, outfitFunctions: ["sport", "casual"],
    seasons: ["spring", "summer", "autumn"], safety: {hikingTechnical: false},
  }],
];

function assertUnitedStatesWeather(result, expectedPlace) {
  assert.equal(result.failClosed, false);
  assert.equal(result.action, "generate_outfit");
  assert.equal(result.resolvedContext?.weatherAvailable, true);
  const label = String(result.resolvedContext?.weatherLocationLabel || "");
  assert.match(label, new RegExp(expectedPlace, "i"), `location_label_missing_${expectedPlace}:${label}`);
  assert.match(label, /spojen[eé]\s+št[aá]ty|united states|\busa\b/i, `location_not_in_usa:${label}`);
  assert.doesNotMatch(label, /braz[ií]l/i, `location_wrongly_in_brazil:${label}`);
}

async function main() {
  if (!admin.apps.length) admin.initializeApp({projectId: PROJECT_ID});
  const db = admin.firestore();
  const auth = admin.auth();
  const stamp = Date.now();
  const dates = bratislavaDateKeys();
  const uid = `stylist_ambiguity_${stamp}`;
  const userRef = db.collection("users").doc(uid);
  const serverSessionRef = db.collection("stylistSessionsV2Server").doc(uid);
  const requestKeys = new Set();
  const usageRefs = [];
  let turnCounter = 0;

  try {
    await userRef.set({_qaStylistAmbiguity: true, createdAt: admin.firestore.FieldValue.serverTimestamp()});
    const batch = db.batch();
    for (const [id, item] of WARDROBE) {
      batch.set(userRef.collection("wardrobe").doc(id), {
        ...item,
        updatedAt: admin.firestore.Timestamp.now(),
        wardrobeItemRevision: 1,
      });
    }
    await batch.commit();

    const customToken = await auth.createCustomToken(uid);
    const idToken = await exchangeCustomToken(customToken);

    async function turn(chatId, message) {
      turnCounter += 1;
      const turnId = `a${turnCounter}_${stamp}`;
      requestKeys.add(hashValue([uid, turnId, "one_brain"]));
      const response = await callCallable(idToken, {
        v2SessionId: chatId,
        turnId,
        message,
        history: [],
        currentOutfitItemIds: [],
        currentSelectionReasons: [],
        clientContext: {...dates, timezoneOffsetMinutes: -new Date().getTimezoneOffset()},
      });
      console.log(`STYLIST_AMBIGUITY_TURN ${chatId} ${JSON.stringify({
        message,
        action: response.result.action || null,
        failClosed: response.result.failClosed ?? null,
        weatherAvailable: response.result.resolvedContext?.weatherAvailable ?? null,
        weatherLocation: response.result.resolvedContext?.weatherLocationLabel || null,
        latencyMs: response.latencyMs,
      })}`);
      return response.result;
    }

    for (const place of ["Colorado", "Georgia"]) {
      const chatId = `usa_${place.toLowerCase()}_${stamp}`;
      const first = await turn(chatId, "zajtra idem na túru do USA, potrebujem outfit");
      assert.equal(first.failClosed, false);
      assert.equal(first.action, "clarify");
      assert.equal(first.resolvedContext?.weatherAvailable, false);

      const second = await turn(chatId, place);
      assertUnitedStatesWeather(second, place);
      assert.equal(second.resolvedContext?.weatherDateKey, dates.tomorrowDateKey);
      assert.equal(second.resolvedContext?.weatherSource, "open-meteo");
      console.log(`STYLIST_AMBIGUITY_PASS usa_then_${place.toLowerCase()}`);
    }

    const franceChat = `festival_fr_${stamp}`;
    const france = await turn(franceChat, "zajtra idem na festival do Francúzska, potrebujem outfit");
    assert.equal(france.failClosed, false);
    assert.equal(france.action, "clarify");
    assert.equal(france.resolvedContext?.weatherAvailable, false);
    console.log("STYLIST_AMBIGUITY_PASS activity_first_france_requires_narrowing");

    const models = [];
    for (const requestKey of requestKeys) {
      const snap = await db.collection("aiUsageEventsV1").where("requestKey", "==", requestKey).get();
      for (const doc of snap.docs) {
        usageRefs.push(doc.ref);
        const model = String(doc.data()?.model || "");
        if (model) models.push(model);
      }
    }
    assert.ok(models.length > 0, "ambiguity_usage_events_missing");
    assert.ok(models.every((model) => model.startsWith("gpt-5.6-terra")),
      `unexpected_model_used:${models.join(",")}`);
    console.log(`STYLIST_AMBIGUITY_RESULT ${JSON.stringify({ok: true, models: [...new Set(models)]})}`);
  } finally {
    for (const ref of usageRefs) await ref.delete().catch(() => {});
    if (typeof db.recursiveDelete === "function") {
      await db.recursiveDelete(userRef).catch(() => {});
      await db.recursiveDelete(serverSessionRef).catch(() => {});
    } else {
      for (const [id] of WARDROBE) await userRef.collection("wardrobe").doc(id).delete().catch(() => {});
      await userRef.delete().catch(() => {});
    }
    await auth.deleteUser(uid).catch(() => {});
  }
}

main().catch((error) => {
  console.error(`STYLIST_PRODUCTION_AMBIGUITY_FAILED ${error?.message || error}`);
  process.exitCode = 1;
});
