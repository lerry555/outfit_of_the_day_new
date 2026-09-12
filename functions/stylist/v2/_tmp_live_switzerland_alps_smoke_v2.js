"use strict";

const assert = require("node:assert/strict");
const admin = require("firebase-admin");
const {hashValue} = require("../../costs/ai_usage_v1");

const PROJECT_ID = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "outfitoftheday-4d401";
const API_KEY = String(process.env.FIREBASE_WEB_API_KEY || "").trim();

function bratislavaDateKeys() {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Europe/Bratislava", year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(new Date());
  const value = Object.fromEntries(parts
    .filter((part) => part.type !== "literal")
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
  if (!response.ok) {
    throw new Error(`firebase_token_exchange_failed:${response.status}:${json?.error?.message || "unknown"}`);
  }
  assert.ok(json.idToken, "firebase_id_token_missing");
  return json.idToken;
}

async function callCallable(idToken, data) {
  const response = await fetch(`https://us-east1-${PROJECT_ID}.cloudfunctions.net/stylistChatV2`, {
    method: "POST",
    headers: {"Content-Type": "application/json", Authorization: `Bearer ${idToken}`},
    body: JSON.stringify({data}),
  });
  const json = await response.json().catch(() => ({}));
  if (!response.ok || !json.result) {
    throw new Error(`callable_failed:${response.status}:${JSON.stringify(json).slice(0, 1200)}`);
  }
  return json.result;
}

function visible(result) {
  return {
    action: result?.action || null,
    failClosed: result?.failClosed === true,
    modelPath: result?.modelPath || null,
    reply: String(result?.reply || result?.stylistComment || "").slice(0, 700),
    resultingOutfitItemIds: Array.isArray(result?.resultingOutfitItemIds) ? result.resultingOutfitItemIds : [],
    displayItemIds: Array.isArray(result?.displayItemIds) ? result.displayItemIds : [],
    quickReplyMode: result?.quickReplyMode || null,
    quickReplyPrompt: result?.quickReplyPrompt || null,
  };
}

async function deleteQueryDocs(query) {
  const snap = await query.get().catch(() => null);
  if (!snap) return;
  for (const doc of snap.docs) await doc.ref.delete().catch(() => {});
}

async function main() {
  if (!admin.apps.length) admin.initializeApp({projectId: PROJECT_ID});
  const db = admin.firestore();
  const auth = admin.auth();
  const stamp = Date.now();
  const uid = `stylist_live_alps_${stamp}`;
  const chatId = `live_alps_${stamp}`;
  const userRef = db.collection("users").doc(uid);
  const serverRootRef = db.collection("stylistSessionsV2Server").doc(uid);
  const dates = bratislavaDateKeys();

  const wardrobe = [
    ["shirt", {
      name: "Čierne tričko", category: "tops", canonicalType: "t_shirt", canonicalFamily: "tops",
      bodySlots: ["upper_body"], layerPosition: "base",
      colorProfile: {primary: {family: "black", proportion: 1}}, colors: ["black"],
      warmth: 2, formality: 2, outfitFunctions: ["base_layer"],
      seasons: ["spring", "summer", "autumn"],
    }],
    ["pants", {
      name: "Sivé tepláky", category: "bottoms", canonicalType: "joggers", canonicalFamily: "bottoms",
      bodySlots: ["lower_body"], layerPosition: "base",
      colorProfile: {primary: {family: "gray", proportion: 1}}, colors: ["gray"],
      warmth: 4, formality: 1, outfitFunctions: ["casual"], seasons: ["spring", "autumn"],
    }],
    ["sneakers", {
      name: "Športové tenisky", category: "footwear", canonicalType: "running_shoes", canonicalFamily: "footwear",
      bodySlots: ["feet"], layerPosition: "base",
      colorProfile: {primary: {family: "white", proportion: 1}}, colors: ["white"],
      warmth: 2, formality: 1, outfitFunctions: ["sport"], seasons: ["spring", "summer", "autumn"],
    }],
    ["hoodie", {
      name: "Svetlomodrá mikina", category: "tops", canonicalType: "hoodie", canonicalFamily: "tops",
      bodySlots: ["upper_body"], layerPosition: "mid",
      colorProfile: {primary: {family: "blue", proportion: 1}}, colors: ["blue"],
      warmth: 5, formality: 1, outfitFunctions: ["mid_layer"], seasons: ["spring", "autumn", "winter"],
    }],
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
    const base = (turnId, message) => ({
      v2SessionId: chatId,
      turnId,
      message,
      history: [],
      currentOutfitItemIds: [],
      currentSelectionReasons: [],
      shoppingEnabled: false,
      clientContext: {
        ...dates,
        timezoneOffsetMinutes: -new Date().getTimezoneOffset(),
      },
    });

    const first = await callCallable(
      idToken,
      base(`t1_${stamp}`, "ahoj za dva dni idem do švajciarska na turu a neviem co si mam obliect"),
    );
    console.log(`LIVE_TURN_1 ${JSON.stringify(visible(first))}`);
    assert.equal(first.failClosed, false, `turn1_fail_closed:${JSON.stringify(visible(first))}`);
    assert.equal(first.action, "clarify", `turn1_not_clarify:${JSON.stringify(visible(first))}`);
    assert.match(String(first.reply || ""), /Kam približne|oblasť|pohorie/i);

    const second = await callCallable(idToken, base(`t2_${stamp}`, "do Alp"));
    console.log(`LIVE_TURN_2 ${JSON.stringify(visible(second))}`);
    assert.notEqual(second.failClosed, true, `turn2_fail_closed:${JSON.stringify(visible(second))}`);
    assert.equal(second.modelPath, "stylist_v2_one_brain", `turn2_wrong_path:${JSON.stringify(visible(second))}`);
    assert.notEqual(second.action, "clarify", `turn2_second_question:${JSON.stringify(visible(second))}`);
    assert.equal(second.action, "generate_outfit", `turn2_not_outfit:${JSON.stringify(visible(second))}`);
    assert.ok(
      Array.isArray(second.resultingOutfitItemIds) && second.resultingOutfitItemIds.length >= 2,
      `turn2_missing_outfit:${JSON.stringify(visible(second))}`,
    );
    assert.ok(
      Array.isArray(second.displayItemIds) && second.displayItemIds.length >= 2,
      `turn2_missing_display:${JSON.stringify(visible(second))}`,
    );

    console.log("LIVE_SWITZERLAND_ALPS_SMOKE_OK");
  } finally {
    await deleteQueryDocs(db.collection("aiUsageEventsV1").where("userKey", "==", hashValue(uid)));
    if (typeof db.recursiveDelete === "function") {
      await db.recursiveDelete(userRef).catch(() => {});
      await db.recursiveDelete(serverRootRef).catch(() => {});
    } else {
      for (const [id] of wardrobe) {
        await userRef.collection("wardrobe").doc(id).delete().catch(() => {});
      }
      const sessions = await serverRootRef.collection("sessions").get().catch(() => null);
      if (sessions) {
        for (const session of sessions.docs) {
          const turns = await session.ref.collection("turns").get().catch(() => null);
          if (turns) for (const turn of turns.docs) await turn.ref.delete().catch(() => {});
          await session.ref.delete().catch(() => {});
        }
      }
      await serverRootRef.delete().catch(() => {});
      await userRef.delete().catch(() => {});
    }
    await auth.deleteUser(uid).catch(() => {});
  }
}

main().catch((error) => {
  console.error(`LIVE_SWITZERLAND_ALPS_SMOKE_FAILED ${error?.stack || error?.message || error}`);
  process.exitCode = 1;
});
