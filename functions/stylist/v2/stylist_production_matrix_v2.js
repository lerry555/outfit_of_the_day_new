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
  ["shirt_white", {
    name: "Biela košeľa", category: "tops", canonicalType: "shirt", canonicalFamily: "tops",
    bodySlots: ["upper_body"], layerPosition: "base", colorProfile: {primary: {family: "white", proportion: 1}},
    colors: ["white"], warmth: 2, formality: 8, outfitFunctions: ["formal", "smart"],
    seasons: ["spring", "summer", "autumn", "winter"],
  }],
  ["hoodie_blue", {
    name: "Svetlomodrá mikina", category: "tops", canonicalType: "hoodie", canonicalFamily: "tops",
    bodySlots: ["upper_body"], layerPosition: "mid", colorProfile: {primary: {family: "blue", proportion: 1}},
    colors: ["blue"], warmth: 5, formality: 1, outfitFunctions: ["mid_layer", "casual"],
    seasons: ["spring", "autumn", "winter"],
  }],
  ["hoodie_black", {
    name: "Čierna mikina", category: "tops", canonicalType: "hoodie", canonicalFamily: "tops",
    bodySlots: ["upper_body"], layerPosition: "mid", colorProfile: {primary: {family: "black", proportion: 1}},
    colors: ["black"], warmth: 5, formality: 1, outfitFunctions: ["mid_layer", "casual"],
    seasons: ["spring", "autumn", "winter"],
  }],
  ["jacket_black", {
    name: "Čierna bunda", category: "tops", canonicalType: "jacket", canonicalFamily: "outerwear",
    bodySlots: ["upper_body"], layerPosition: "outer", colorProfile: {primary: {family: "black", proportion: 1}},
    colors: ["black"], warmth: 6, formality: 3, outfitFunctions: ["outer_layer"],
    seasons: ["spring", "autumn", "winter"],
  }],
  ["jacket_blue", {
    name: "Modrá bunda", category: "tops", canonicalType: "jacket", canonicalFamily: "outerwear",
    bodySlots: ["upper_body"], layerPosition: "outer", colorProfile: {primary: {family: "blue", proportion: 1}},
    colors: ["blue"], warmth: 6, formality: 3, outfitFunctions: ["outer_layer"],
    seasons: ["spring", "autumn", "winter"],
  }],
  ["blazer_navy", {
    name: "Tmavomodré sako", category: "tops", canonicalType: "blazer", canonicalFamily: "outerwear",
    bodySlots: ["upper_body"], layerPosition: "outer", colorProfile: {primary: {family: "navy", proportion: 1}},
    colors: ["navy"], warmth: 3, formality: 9, outfitFunctions: ["formal", "smart", "outer_layer"],
    seasons: ["spring", "summer", "autumn", "winter"],
  }],
  ["joggers_gray", {
    name: "Sivé tepláky", category: "bottoms", canonicalType: "joggers", canonicalFamily: "bottoms",
    bodySlots: ["lower_body"], layerPosition: "base", colorProfile: {primary: {family: "gray", proportion: 1}},
    colors: ["gray"], warmth: 4, formality: 1, outfitFunctions: ["casual", "sport"],
    seasons: ["spring", "autumn"],
  }],
  ["jeans_dark", {
    name: "Tmavé rifle", category: "bottoms", canonicalType: "jeans", canonicalFamily: "bottoms",
    bodySlots: ["lower_body"], layerPosition: "base", colorProfile: {primary: {family: "navy", proportion: 1}},
    colors: ["navy"], warmth: 4, formality: 4, outfitFunctions: ["casual", "smart_casual"],
    seasons: ["spring", "autumn", "winter"],
  }],
  ["chinos_navy", {
    name: "Tmavomodré chinos nohavice", category: "bottoms", canonicalType: "chinos", canonicalFamily: "bottoms",
    bodySlots: ["lower_body"], layerPosition: "base", colorProfile: {primary: {family: "navy", proportion: 1}},
    colors: ["navy"], warmth: 3, formality: 7, outfitFunctions: ["smart", "formal"],
    seasons: ["spring", "summer", "autumn", "winter"],
  }],
  ["sneakers_white", {
    name: "Biele športové tenisky", category: "footwear", canonicalType: "running_shoes", canonicalFamily: "footwear",
    bodySlots: ["feet"], layerPosition: "base", colorProfile: {primary: {family: "white", proportion: 1}},
    colors: ["white"], warmth: 2, formality: 1, outfitFunctions: ["sport", "casual"],
    seasons: ["spring", "summer", "autumn"], safety: {hikingTechnical: false},
  }],
  ["sneakers_black", {
    name: "Čierne tenisky", category: "footwear", canonicalType: "sneakers", canonicalFamily: "footwear",
    bodySlots: ["feet"], layerPosition: "base", colorProfile: {primary: {family: "black", proportion: 1}},
    colors: ["black"], warmth: 2, formality: 3, outfitFunctions: ["casual", "smart_casual"],
    seasons: ["spring", "summer", "autumn"], safety: {hikingTechnical: false},
  }],
  ["dress_shoes_black", {
    name: "Čierne spoločenské topánky", category: "footwear", canonicalType: "dress_shoes", canonicalFamily: "footwear",
    bodySlots: ["feet"], layerPosition: "base", colorProfile: {primary: {family: "black", proportion: 1}},
    colors: ["black"], warmth: 2, formality: 9, outfitFunctions: ["formal", "smart"],
    seasons: ["spring", "summer", "autumn", "winter"],
  }],
];

const KNOWN_IDS = new Set(WARDROBE.map(([id]) => id));
const FORMAL_IDS = new Set(["shirt_white", "blazer_navy", "chinos_navy", "dress_shoes_black"]);

function itemPriority(item) {
  const layer = String(item?.layerPosition || "").toLowerCase();
  const category = String(item?.category || "").toLowerCase();
  const type = String(item?.canonicalType || "").toLowerCase();
  const slots = Array.isArray(item?.bodySlots) ? item.bodySlots : [];
  if (["shell", "outer"].includes(layer) || /jacket|coat|blazer|outerwear/.test(`${category} ${type}`)) return 10;
  if (layer === "mid" || /hoodie|sweatshirt|sweater|cardigan/.test(type)) return 20;
  if (slots.includes("upper_body")) return 30;
  if (slots.includes("full_body")) return 35;
  if (slots.includes("lower_body")) return 40;
  if (slots.includes("feet")) return 50;
  return 70;
}

function assertKnownIds(result) {
  for (const key of ["resultingOutfitItemIds", "displayItemIds"]) {
    for (const id of Array.isArray(result?.[key]) ? result[key] : []) {
      assert.ok(KNOWN_IDS.has(id), `${key}_hallucinated_id:${id}`);
    }
  }
}

function assertCardOrder(result) {
  const items = Array.isArray(result?.resultingOutfitItems) ? result.resultingOutfitItems : [];
  const priorities = items.map(itemPriority);
  for (let i = 1; i < priorities.length; i += 1) {
    assert.ok(priorities[i - 1] <= priorities[i], `card_order_invalid:${priorities.join(",")}`);
  }
}

function assertGenerated(result, dates) {
  assert.equal(result.failClosed, false);
  assert.equal(result.action, "generate_outfit");
  assert.ok(Array.isArray(result.resultingOutfitItemIds) && result.resultingOutfitItemIds.length >= 3,
    "generated_outfit_too_small");
  assertKnownIds(result);
  assertCardOrder(result);
  if (result.resolvedContext?.weatherAvailable) {
    assert.equal(result.resolvedContext.weatherDateKey, dates.tomorrowDateKey);
    assert.equal(result.resolvedContext.weatherSource, "open-meteo");
  }
}

function reasonsFrom(result) {
  return (Array.isArray(result?.resultingOutfitItems) ? result.resultingOutfitItems : [])
    .filter((item) => item?.id && item?.stylistSelectionReason)
    .map((item) => ({itemId: item.id, reason: item.stylistSelectionReason}));
}

function safeSummary(result, latencyMs) {
  return {
    action: result?.action || null,
    failClosed: result?.failClosed ?? null,
    outfitChanged: result?.outfitChanged ?? null,
    ids: Array.isArray(result?.resultingOutfitItemIds) ? result.resultingOutfitItemIds : [],
    displayIds: Array.isArray(result?.displayItemIds) ? result.displayItemIds : [],
    quickReplyMode: result?.quickReplyMode || null,
    weatherLocation: result?.resolvedContext?.weatherLocationLabel || null,
    weatherDateKey: result?.resolvedContext?.weatherDateKey || null,
    latencyMs,
  };
}

async function main() {
  if (!admin.apps.length) admin.initializeApp({projectId: PROJECT_ID});
  const db = admin.firestore();
  const auth = admin.auth();
  const stamp = Date.now();
  const dates = bratislavaDateKeys();
  const uid = `stylist_matrix_${stamp}`;
  const userRef = db.collection("users").doc(uid);
  const usageRefs = [];
  const requestKeys = new Set();
  const failures = [];
  const results = [];
  let turnCounter = 0;

  async function scenario(name, fn) {
    try {
      await fn();
      results.push({name, ok: true});
      console.log(`STYLIST_MATRIX_PASS ${name}`);
    } catch (error) {
      const message = String(error?.message || error).slice(0, 500);
      failures.push({name, message});
      results.push({name, ok: false, message});
      console.error(`STYLIST_MATRIX_FAIL ${name} ${message}`);
    }
  }

  try {
    await userRef.set({_qaStylistMatrix: true, createdAt: admin.firestore.FieldValue.serverTimestamp()});
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

    async function turn({chatId, message, currentIds = [], reasons = [], extra = {}}) {
      turnCounter += 1;
      const turnId = `m${turnCounter}_${stamp}`;
      requestKeys.add(hashValue([uid, turnId, "one_brain"]));
      const response = await callCallable(idToken, {
        v2SessionId: chatId,
        turnId,
        message,
        history: [],
        currentOutfitItemIds: currentIds,
        currentSelectionReasons: reasons,
        clientContext: {...dates, timezoneOffsetMinutes: -new Date().getTimezoneOffset()},
        ...extra,
      });
      console.log(`STYLIST_MATRIX_TURN ${chatId} ${JSON.stringify(safeSummary(response.result, response.latencyMs))}`);
      assert.equal(response.result.failClosed, false, `${chatId}:fail_closed`);
      assertKnownIds(response.result);
      if (["generate_outfit", "edit_outfit"].includes(response.result.action)) assertCardOrder(response.result);
      return response.result;
    }

    await scenario("usa_country_then_colorado", async () => {
      const chatId = `usa_${stamp}`;
      const first = await turn({chatId, message: "zajtra idem na túru do USA, potrebujem outfit"});
      assert.equal(first.action, "clarify");
      assert.equal(first.resolvedContext?.weatherAvailable, false);
      const second = await turn({chatId, message: "Colorado"});
      assertGenerated(second, dates);
      assert.equal(second.resolvedContext?.weatherAvailable, true);
      assert.match(String(second.resolvedContext?.weatherLocationLabel || ""), /colorado/i);
    });

    await scenario("swiss_alps_zermatt", async () => {
      const result = await turn({
        chatId: `zermatt_${stamp}`,
        message: "zajtra idem na túru do švajčiarskych Álp pri Zermatte, potrebujem outfit",
      });
      assertGenerated(result, dates);
      assert.equal(result.resolvedContext?.weatherAvailable, true);
      assert.match(String(result.resolvedContext?.weatherLocationLabel || ""), /zermatt/i);
      assert.match(String(result.resolvedContext?.weatherLocationLabel || ""), /switzerland|schweiz|švajčiarsko/i);
    });

    await scenario("andorra_pyrenees", async () => {
      const result = await turn({
        chatId: `andorra_${stamp}`,
        message: "zajtra idem na túru do Pyrenejí pri Andorre la Vella, potrebujem outfit",
      });
      assertGenerated(result, dates);
      assert.equal(result.resolvedContext?.weatherAvailable, true);
      assert.match(String(result.resolvedContext?.weatherLocationLabel || ""), /andorra/i);
    });

    await scenario("paris_france_not_texas", async () => {
      const result = await turn({
        chatId: `paris_${stamp}`,
        message: "zajtra idem na večeru v Paríži a potrebujem outfit",
      });
      assertGenerated(result, dates);
      const label = String(result.resolvedContext?.weatherLocationLabel || "");
      assert.match(label, /paris|paríž/i);
      assert.match(label, /france|francúzsko/i);
      assert.doesNotMatch(label, /texas/i);
    });

    await scenario("wedding_lyon_formality", async () => {
      const result = await turn({
        chatId: `wedding_${stamp}`,
        message: "zajtra idem na svadbu v Lyone vo Francúzsku a potrebujem outfit",
      });
      assertGenerated(result, dates);
      const label = String(result.resolvedContext?.weatherLocationLabel || "");
      assert.match(label, /lyon/i);
      assert.match(label, /france|francúzsko/i);
      const formalCount = result.resultingOutfitItemIds.filter((id) => FORMAL_IDS.has(id)).length;
      assert.ok(formalCount >= 2, `wedding_formality_too_low:${result.resultingOutfitItemIds.join(",")}`);
    });

    await scenario("interview_berlin_formality", async () => {
      const result = await turn({
        chatId: `interview_${stamp}`,
        message: "zajtra mám pracovný pohovor v Berlíne a potrebujem outfit",
      });
      assertGenerated(result, dates);
      const label = String(result.resolvedContext?.weatherLocationLabel || "");
      assert.match(label, /berlin|berlín/i);
      assert.match(label, /germany|deutschland|nemecko/i);
      const formalCount = result.resultingOutfitItemIds.filter((id) => FORMAL_IDS.has(id)).length;
      assert.ok(formalCount >= 2, `interview_formality_too_low:${result.resultingOutfitItemIds.join(",")}`);
    });

    await scenario("festival_france_requires_narrowing", async () => {
      const chatId = `festival_${stamp}`;
      const first = await turn({chatId, message: "zajtra idem na festival do Francúzska, potrebujem outfit"});
      assert.equal(first.action, "clarify");
      assert.equal(first.resolvedContext?.weatherAvailable, false);
      const second = await turn({chatId, message: "Lyon"});
      assertGenerated(second, dates);
      assert.match(String(second.resolvedContext?.weatherLocationLabel || ""), /lyon/i);
    });

    await scenario("hoodie_edit_preserves_jacket_and_rest", async () => {
      const currentIds = ["jacket_black", "hoodie_blue", "tee_black", "joggers_gray", "sneakers_white"];
      const reasons = currentIds.map((id) => ({itemId: id, reason: `pôvodný dôvod ${id}`}));
      const result = await turn({
        chatId: `edit_hoodie_${stamp}`,
        message: "vymeň mi mikinu za inú, ostatné nechaj",
        currentIds,
        reasons,
      });
      assert.equal(result.action, "edit_outfit");
      assert.equal(result.outfitChanged, true);
      assert.ok(!result.resultingOutfitItemIds.includes("hoodie_blue"), "old_hoodie_not_replaced");
      assert.ok(result.resultingOutfitItemIds.includes("hoodie_black"), "replacement_hoodie_missing");
      for (const id of ["jacket_black", "tee_black", "joggers_gray", "sneakers_white"]) {
        assert.ok(result.resultingOutfitItemIds.includes(id), `preserved_item_missing:${id}`);
      }
      assert.ok(!result.resultingOutfitItemIds.includes("jacket_blue"), "unrequested_jacket_replacement");
    });

    await scenario("bottom_edit_preserves_other_slots", async () => {
      const currentIds = ["hoodie_blue", "tee_black", "joggers_gray", "sneakers_white"];
      const reasons = currentIds.map((id) => ({itemId: id, reason: `pôvodný dôvod ${id}`}));
      const result = await turn({
        chatId: `edit_bottom_${stamp}`,
        message: "vymeň tepláky za niečo vhodnejšie, zvyšok nechaj",
        currentIds,
        reasons,
      });
      assert.equal(result.action, "edit_outfit");
      assert.equal(result.outfitChanged, true);
      assert.ok(!result.resultingOutfitItemIds.includes("joggers_gray"), "old_bottom_not_replaced");
      assert.ok(result.resultingOutfitItemIds.some((id) => ["jeans_dark", "chinos_navy"].includes(id)),
        `compatible_bottom_missing:${result.resultingOutfitItemIds.join(",")}`);
      for (const id of ["hoodie_blue", "tee_black", "sneakers_white"]) {
        assert.ok(result.resultingOutfitItemIds.includes(id), `preserved_item_missing:${id}`);
      }
    });

    await scenario("sneaker_alternatives_question_is_not_edit", async () => {
      const currentIds = ["hoodie_blue", "tee_black", "joggers_gray", "sneakers_white"];
      const reasons = currentIds.map((id) => ({itemId: id, reason: `pôvodný dôvod ${id}`}));
      const result = await turn({
        chatId: `alt_sneakers_${stamp}`,
        message: "aké iné tenisky mám?",
        currentIds,
        reasons,
      });
      assert.notEqual(result.action, "edit_outfit");
      assert.equal(result.outfitChanged, false);
    });

    await scenario("shopping_decline_keeps_outfit", async () => {
      const chatId = `shopping_no_${stamp}`;
      const outfit = await turn({chatId, message: "zajtra idem na túru do Tatier, potrebujem outfit"});
      assertGenerated(outfit, dates);
      assert.equal(outfit.quickReplyMode, "yes_no");
      const declined = await turn({
        chatId,
        message: "Nie",
        currentIds: outfit.resultingOutfitItemIds,
        reasons: reasonsFrom(outfit),
      });
      assert.equal(declined.outfitChanged, false);
      assert.notEqual(declined.action, "edit_outfit");
      assert.equal(declined.quickReplyMode, "none");
    });

    await scenario("new_chat_isolation", async () => {
      const first = await turn({
        chatId: `isolation_paris_${stamp}`,
        message: "zajtra idem na večeru v Paríži, potrebujem outfit",
      });
      assertGenerated(first, dates);
      assert.match(String(first.resolvedContext?.weatherLocationLabel || ""), /paris|paríž/i);
      const second = await turn({
        chatId: `isolation_new_${stamp}`,
        message: "zajtra idem na túru, potrebujem outfit",
      });
      assert.equal(second.action, "clarify");
      assert.equal(second.resolvedContext?.weatherAvailable, false);
      assert.equal(second.resolvedContext?.weatherLocationLabel, null);
    });

    await scenario("pending_skip_proceeds_without_fake_location", async () => {
      const chatId = `skip_${stamp}`;
      const first = await turn({chatId, message: "zajtra idem na túru, potrebujem outfit"});
      assert.equal(first.action, "clarify");
      const second = await turn({chatId, message: "neviem, daj mi proste outfit"});
      assertGenerated(second, dates);
      assert.equal(second.resolvedContext?.weatherAvailable, false);
      assert.equal(second.resolvedContext?.weatherLocationLabel, null);
    });

    await scenario("pending_unrelated_does_not_become_location", async () => {
      const chatId = `unrelated_${stamp}`;
      const first = await turn({chatId, message: "zajtra idem na túru, potrebujem outfit"});
      assert.equal(first.action, "clarify");
      const second = await turn({chatId, message: "inak aká farba sa hodí k modrej?"});
      assert.equal(second.action, "chat");
      assert.equal(second.outfitChanged, false);
      assert.equal(second.resolvedContext?.weatherAvailable, false);
      assert.equal(second.resolvedContext?.weatherLocationLabel, null);
    });

    await scenario("telemetry_uses_only_terra", async () => {
      const models = [];
      let estimatedCost = 0;
      for (const requestKey of requestKeys) {
        const snap = await db.collection("aiUsageEventsV1").where("requestKey", "==", requestKey).get();
        for (const doc of snap.docs) {
          usageRefs.push(doc.ref);
          const data = doc.data() || {};
          if (data.model) models.push(String(data.model));
          estimatedCost += Number(data.estimatedCostUsd ?? data.estimatedCostUsdMax ?? data.estimatedCostUsdMin ?? 0);
        }
      }
      assert.ok(models.length > 0, "matrix_usage_events_missing");
      assert.ok(models.every((model) => model.startsWith("gpt-5.6-terra")),
        `unexpected_model_used:${models.join(",")}`);
      console.log(`STYLIST_MATRIX_TELEMETRY ${JSON.stringify({events: models.length, models: [...new Set(models)], estimatedCostUsd: Number(estimatedCost.toFixed(6))})}`);
    });

    console.log(`STYLIST_MATRIX_RESULT ${JSON.stringify({ok: failures.length === 0, passed: results.filter((r) => r.ok).length, failed: failures.length, failures})}`);
    if (failures.length) {
      throw new Error(`stylist_production_matrix_failed:${failures.map((failure) => `${failure.name}:${failure.message}`).join(" | ")}`);
    }
  } finally {
    for (const ref of usageRefs) await ref.delete().catch(() => {});
    if (typeof db.recursiveDelete === "function") {
      await db.recursiveDelete(userRef).catch(() => {});
    } else {
      for (const [id] of WARDROBE) await userRef.collection("wardrobe").doc(id).delete().catch(() => {});
      const sessions = await userRef.collection("stylistSessionsV2").get().catch(() => null);
      if (sessions) for (const doc of sessions.docs) await doc.ref.delete().catch(() => {});
      await userRef.delete().catch(() => {});
    }
    await auth.deleteUser(uid).catch(() => {});
  }
}

main().catch((error) => {
  console.error(`STYLIST_PRODUCTION_MATRIX_FAILED ${error?.message || error}`);
  process.exitCode = 1;
});
