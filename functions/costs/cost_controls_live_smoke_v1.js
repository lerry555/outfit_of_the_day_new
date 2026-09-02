"use strict";

// Explicit owner-approved live QA only. Uses an EXISTING selected account and
// wardrobe; no new users, garment writes/deletes, chat writes or notifications.
// Normal callable execution writes the private usage/job/result-cache records.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {randomUUID} = require("node:crypto");
const admin = require("firebase-admin");
const {hashValue} = require("./ai_usage_v1");
const {resolveOwnedWardrobeStoragePath} = require("../clothing_vision/storage_ownership");

async function main() {
  assert.ok(process.argv.includes("--live"), "live_opt_in_required");
  const uid = process.env.STYLIST_QA_UID;
  assert.ok(uid, "existing_qa_uid_required");
  const config = JSON.parse(fs.readFileSync(path.join(__dirname,
    "../../android/app/google-services.json"), "utf8"));
  const projectId = config.project_info.project_id;
  assert.equal(projectId, "outfitoftheday-4d401");
  const app = admin.initializeApp({credential: admin.credential.applicationDefault(), projectId});
  const db = app.firestore();
  try {
    await admin.auth().getUser(uid);
    const snapshot = await db.collection("users").doc(uid).collection("wardrobe").limit(200).get();
    const wardrobe = snapshot.docs.map((doc) => ({...doc.data(), id: doc.id}));
    const byId = new Map(wardrobe.map((item) => [item.id, item]));
    assert.ok(wardrobe.length >= 3, "existing_wardrobe_required");
    const token = await admin.auth().createCustomToken(uid);
    const authResponse = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${config.client[0].api_key[0].current_key}`, {
      method: "POST", headers: {"Content-Type": "application/json"},
      body: JSON.stringify({token, returnSecureToken: true}), signal: AbortSignal.timeout(30000),
    });
    assert.ok(authResponse.ok, "qa_auth_failed");
    const auth = await authResponse.json();
    assert.equal((await admin.auth().verifyIdToken(auth.idToken)).uid, uid);
    const baseUrl = `https://us-east1-${projectId}.cloudfunctions.net/`;
    async function call(name, data, callable = true) {
      const response = await fetch(baseUrl + name, {method: "POST",
        headers: {"Content-Type": "application/json", Authorization: `Bearer ${auth.idToken}`},
        body: JSON.stringify(callable ? {data} : data), signal: AbortSignal.timeout(125000)});
      assert.ok(response.ok, `qa_http_${name}_${response.status}`);
      const body = await response.json();
      assert.ok(!body.error, `qa_callable_error_${name}`);
      return callable ? body.result : body;
    }
    async function usageForUser() {
      const snap = await db.collection("aiUsageEventsV1").where("userKey", "==", hashValue(uid)).get();
      return snap.docs.map((doc) => ({...doc.data(), id: doc.id}));
    }
    const initialUsageIds = new Set((await usageForUser()).map((entry) => entry.id));
    const weather = {morningTempC: 15, noonTempC: 24, eveningTempC: 22,
      minTempC: 12, maxTempC: 25, willRain: false, isWindy: false, fromOpenMeteo: true};
    const initial = {requestId: `cost-qa-${randomUUID()}`, message: "Ahoj, zajtra idem do mesta.",
      history: [], currentOutfitItemIds: [], weatherContext: {location: "Martin", tomorrow: weather},
      clientContext: {todayDateKey: "2026-09-02", tomorrowDateKey: "2026-09-03", userGpsLocation: "Martin"}};
    const hello = await call("stylistSimpleAgentV1", initial);
    assert.equal(hello.failClosed, undefined, "qa_chat_fail_closed");
    assert.equal(hello.outfitRequested, false);
    assert.deepEqual(hello.resultingOutfitItemIds, []);
    const helloUsage = (await usageForUser()).filter((entry) => entry.requestKey === hashValue([uid, initial.requestId]));
    assert.ok(helloUsage.length > 0, "qa_usage_missing");
    const replay = await call("stylistSimpleAgentV1", initial);
    assert.deepEqual(replay, hello, "qa_replayed_result_changed");
    const replayUsage = (await usageForUser()).filter((entry) => entry.requestKey === hashValue([uid, initial.requestId]));
    assert.equal(replayUsage.length, helloUsage.length, "qa_duplicate_was_billed_again");
    console.log(JSON.stringify({scenario: "same_request_replay", passed: true, extraAiCalls: 0,
      reply: hello.stylistComment}));

    const turn = {...initial, requestId: `cost-qa-${randomUUID()}`, message: "Áno, vyber mi outfit na zajtra okolo 14:00.",
      history: [{role: "user", content: initial.message}, {role: "assistant", content: hello.stylistComment}]};
    const outfit = await call("stylistSimpleAgentV1", turn);
    assert.ok(!outfit.failClosed && outfit.resultingOutfitItemIds.length >= 3, "qa_outfit_failed");
    assert.ok(outfit.resultingOutfitItemIds.every((id) => byId.has(id)), "qa_unowned_item");
    assert.ok(outfit.displayItemIds.every((id) => outfit.resultingOutfitItemIds.includes(id)));
    const forecast = await call("stylistSimpleAgentV1", {...turn, requestId: `cost-qa-${randomUUID()}`,
      message: "Koľko bude zajtra stupňov?", currentOutfitItemIds: outfit.resultingOutfitItemIds,
      currentSelectionReasons: outfit.selectionReasons});
    assert.ok(!forecast.failClosed, "qa_weather_failed");
    assert.deepEqual(forecast.resultingOutfitItemIds, outfit.resultingOutfitItemIds);
    console.log(JSON.stringify({scenario: "outfit_and_weather", passed: true,
      outfitReply: outfit.stylistComment, weatherReply: forecast.stylistComment}));

    const analysis = await call("analyzeWardrobeSmart", {});
    assert.ok(Array.isArray(analysis.strengths) && analysis.strengths.length >= 3);
    const cacheKey = hashValue([uid, "wardrobe_structure_analysis"]);
    const cache = (await db.collection("aiExactResultCachesV1").doc(cacheKey).get()).data();
    assert.ok(cache?.expiresAtMs > Date.now(), "qa_analysis_cache_not_written");
    // Verify the actually deployed rules too, not just the checked-in emulator
    // rules. These are read attempts for this QA user's own records only.
    for (const document of [
      `aiUsageEventsV1/${helloUsage[0].id}`,
      `aiTaskRunsV1/${hashValue([uid, "stylist_simple_agent", initial.requestId])}`,
      `aiExactResultCachesV1/${cacheKey}`,
    ]) {
      const denied = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${document}`, {
        headers: {Authorization: `Bearer ${auth.idToken}`}, signal: AbortSignal.timeout(30000),
      });
      assert.equal(denied.status, 403, "qa_private_record_readable_by_client");
    }
    const beforeAnalysisRepeat = (await usageForUser()).filter((e) => e.feature === "wardrobe_structure_analysis").length;
    assert.deepEqual(await call("analyzeWardrobeSmart", {}), analysis, "qa_analysis_result_not_reused");
    const afterAnalysisRepeat = (await usageForUser()).filter((e) => e.feature === "wardrobe_structure_analysis").length;
    assert.equal(afterAnalysisRepeat, beforeAnalysisRepeat, "qa_analysis_repeat_called_ai");
    console.log(JSON.stringify({scenario: "wardrobe_analysis_reuse", passed: true, extraAiCalls: 0}));

    const home = await call("generateHomeOutfit", {date: "2026-09-03", weatherContext: weather});
    assert.ok(!home.fallback && Array.isArray(home.outfitItemIds) && home.outfitItemIds.length >= 3,
      "qa_home_generation_failed");
    const items = outfit.resultingOutfitItemIds.map((id) => {
      const it = byId.get(id);
      const slot = it.bodySlots?.includes("feet") ? "shoes" : it.bodySlots?.includes("lower_body") ? "bottom" :
        ["mid", "outer", "shell"].includes(it.layerPosition) ? "outerwear" : "top";
      return {...it, id, slot, displayName: it.name};
    });
    const review = await call("finalReviewHomeOutfitCandidates", {weatherContext: weather,
      candidates: [{candidateIndex: 0, items, familyAllowed: true, bottomAllowed: true}]});
    assert.ok(!review.fallback && review.selectedCandidateIndex === 0, "qa_home_review_failed");
    const why = await call("generateHomeOutfitExplanation", {weatherContext: weather, outfitItems: items});
    assert.ok(!why.fallback && why.explanation?.length > 0, "qa_home_explanation_failed");

    let imagePath;
    for (const item of wardrobe) {
      try {
        imagePath = resolveOwnedWardrobeStoragePath({uid, storagePath: item.storagePath, imageUrl: item.imageUrl});
        if (imagePath) break;
      } catch (_) { /* Try another already-owned garment, never another owner. */ }
    }
    assert.ok(imagePath, "qa_owned_image_required");
    const vision = await call("analyzeClothingImage", {storagePath: imagePath, contractVersion: "wardrobe-analyzer-v2"}, false);
    assert.ok(vision.wardrobeV2?.canonicalType, "qa_vision_v2_missing");

    const events = (await usageForUser()).filter((entry) => !initialUsageIds.has(entry.id));
    for (const feature of ["stylist_simple_agent", "wardrobe_structure_analysis", "home_outfit",
      "home_review", "home_explanation", "clothing_analysis"]) {
      const featureEvents = events.filter((entry) => entry.feature === feature);
      // A previously warm exact-analysis cache can correctly avoid all new AI.
      if (feature !== "wardrobe_structure_analysis") assert.ok(featureEvents.length, `qa_usage_missing_${feature}`);
      console.log(JSON.stringify({feature, attempts: featureEvents.length,
        inputTokens: featureEvents.map((entry) => entry.inputTokens),
        cachedInputTokens: featureEvents.map((entry) => entry.cachedInputTokens),
        cacheWriteTokens: featureEvents.map((entry) => entry.cacheWriteTokens ?? null),
        estimatedCostUsd: featureEvents.map((entry) => entry.estimatedCostUsd),
        unknownUsageAttempts: featureEvents.filter((entry) => !entry.usageComplete).length}));
    }
    const chatEvents = events.filter((entry) => entry.feature === "stylist_simple_agent");
    const readTokens = chatEvents.reduce((sum, entry) => sum + (entry.cachedInputTokens || 0), 0);
    // Routing/cache availability is not guaranteed by OpenAI. Report measured
    // hits honestly instead of manufacturing a percentage or failing on a miss.
    console.log(JSON.stringify({result: "LIVE_COST_CONTROLS_PASS", providerCacheHitObserved: readTokens > 0,
      cachedInputTokens: readTokens, noWardrobeMutations: true, noNotifications: true}));
  } finally {
    await app.delete();
  }
}

if (require.main === module) main().catch((error) => {
  console.error(String(error.message || "live_qa_failed").slice(0, 180));
  process.exitCode = 1;
});

module.exports = {main};
