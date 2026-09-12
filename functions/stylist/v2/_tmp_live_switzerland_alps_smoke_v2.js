"use strict";

const assert = require("node:assert/strict");
const admin = require("firebase-admin");

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

function firestoreValue(value) {
  if (value === null || value === undefined) return {nullValue: null};
  if (value instanceof Date) return {timestampValue: value.toISOString()};
  if (typeof value === "string") return {stringValue: value};
  if (typeof value === "boolean") return {booleanValue: value};
  if (typeof value === "number") {
    return Number.isInteger(value) ? {integerValue: String(value)} : {doubleValue: value};
  }
  if (Array.isArray(value)) {
    return {arrayValue: {values: value.map(firestoreValue)}};
  }
  if (typeof value === "object") {
    return {
      mapValue: {
        fields: Object.fromEntries(Object.entries(value).map(([key, entry]) => [key, firestoreValue(entry)])),
      },
    };
  }
  throw new TypeError(`unsupported_firestore_value:${typeof value}`);
}

function firestoreFields(value) {
  return Object.fromEntries(Object.entries(value).map(([key, entry]) => [key, firestoreValue(entry)]));
}

function firestoreDocumentUrl(path) {
  return `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(PROJECT_ID)}/databases/(default)/documents/${path}`;
}

async function clientWriteDocument(idToken, path, value) {
  const response = await fetch(firestoreDocumentUrl(path), {
    method: "PATCH",
    headers: {"Content-Type": "application/json", Authorization: `Bearer ${idToken}`},
    body: JSON.stringify({fields: firestoreFields(value)}),
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`client_firestore_write_failed:${path}:${response.status}:${text.slice(0, 600)}`);
  }
}

async function clientDeleteDocument(idToken, path) {
  const response = await fetch(firestoreDocumentUrl(path), {
    method: "DELETE",
    headers: {Authorization: `Bearer ${idToken}`},
  });
  if (!response.ok && response.status !== 404) {
    const text = await response.text();
    console.warn(`QA_CLIENT_DELETE_FAILED ${path} ${response.status} ${text.slice(0, 300)}`);
  }
}

async function deleteFirebaseUser(idToken) {
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:delete?key=${encodeURIComponent(API_KEY)}`,
    {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({idToken}),
    },
  );
  if (!response.ok) {
    const text = await response.text();
    console.warn(`QA_AUTH_DELETE_FAILED ${response.status} ${text.slice(0, 300)}`);
  }
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

async function main() {
  if (!admin.apps.length) admin.initializeApp({projectId: PROJECT_ID});
  const auth = admin.auth();
  const stamp = Date.now();
  const uid = `stylist_live_alps_${stamp}`;
  const chatId = `live_alps_${stamp}`;
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

  let idToken = null;
  try {
    const customToken = await auth.createCustomToken(uid);
    idToken = await exchangeCustomToken(customToken);

    await clientWriteDocument(idToken, `users/${uid}`, {
      _qaStylistSmoke: true,
      createdAt: new Date(),
    });
    for (const [id, item] of wardrobe) {
      await clientWriteDocument(idToken, `users/${uid}/wardrobe/${id}`, {
        ...item,
        updatedAt: new Date(),
        wardrobeItemRevision: 1,
      });
    }

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
    if (idToken) {
      for (const [id] of wardrobe) {
        await clientDeleteDocument(idToken, `users/${uid}/wardrobe/${id}`);
      }
      await clientDeleteDocument(idToken, `users/${uid}`);
      await deleteFirebaseUser(idToken);
    }
    // stylistSessionsV2Server is intentionally inaccessible to clients. This
    // one-shot QA leaves only its tiny timestamped server-only session receipt;
    // user-visible profile/wardrobe/Auth data is removed above.
  }
}

main().catch((error) => {
  console.error(`LIVE_SWITZERLAND_ALPS_SMOKE_FAILED ${error?.stack || error?.message || error}`);
  process.exitCode = 1;
});
