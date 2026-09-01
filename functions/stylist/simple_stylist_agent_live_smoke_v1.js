"use strict";

// Explicitly invoked against an EXISTING owner-selected account. Reads its
// wardrobe; omits chatId/notifyJobId so the callable cannot persist chat jobs
// or send notifications. Uses normal Firebase Auth; credentials stay in memory.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const admin = require("firebase-admin");

async function main() {
  if (!process.argv.includes("--live")) throw new Error("live_opt_in_required");
  const uid = process.env.STYLIST_QA_UID;
  const initialIds = JSON.parse(process.env.STYLIST_QA_CURRENT_IDS || "[]");
  if (!uid || initialIds.length !== 4) throw new Error("existing_qa_fixture_required");
  const config = JSON.parse(fs.readFileSync(
    path.join(__dirname, "../../android/app/google-services.json"), "utf8",
  ));
  const projectId = config.project_info.project_id;
  assert.equal(projectId, "outfitoftheday-4d401");
  const apiKey = config.client[0].api_key[0].current_key;
  admin.initializeApp({credential: admin.credential.applicationDefault(), projectId});
  await admin.auth().getUser(uid); // Never create an account during QA.
  const snapshot = await admin.firestore().collection("users").doc(uid)
    .collection("wardrobe").limit(200).get();
  const byId = new Map(snapshot.docs.map((doc) => [doc.id, doc.data()]));
  assert.ok(initialIds.every((id) => byId.has(id)), "qa_fixture_items_missing");
  const customToken = await admin.auth().createCustomToken(uid);
  const authResponse = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${apiKey}`,
    {method: "POST", headers: {"Content-Type": "application/json"},
      body: JSON.stringify({token: customToken, returnSecureToken: true}),
      signal: AbortSignal.timeout(30000)},
  );
  if (!authResponse.ok) throw new Error("qa_firebase_signin_failed");
  const auth = await authResponse.json();
  const verifiedIdentity = await admin.auth().verifyIdToken(auth.idToken);
  assert.equal(verifiedIdentity.uid, uid, "qa_auth_identity_mismatch");
  const weatherContext = {
    location: "Martin",
    today: {morningTempC: 10, noonTempC: 18, eveningTempC: 14, willRain: true, isWindy: true, fromOpenMeteo: true},
    tomorrow: {
      morningTempC: 15, noonTempC: 24, eveningTempC: 22,
      minTempC: 12, maxTempC: 25, willRain: false, isWindy: false, fromOpenMeteo: true,
    },
  };
  const clientContext = {
    todayDateKey: "2026-09-01", tomorrowDateKey: "2026-09-02", userGpsLocation: "Martin",
  };
  const call = async (name, message, current, history, weather = weatherContext) => {
    const response = await fetch(
      `https://us-east1-${projectId}.cloudfunctions.net/stylistSimpleAgentV1`,
      {method: "POST", headers: {"Content-Type": "application/json", Authorization: `Bearer ${auth.idToken}`},
        body: JSON.stringify({data: {message, history, currentOutfitItemIds: current,
          weatherContext: weather, clientContext}}),
        signal: AbortSignal.timeout(125000)},
    );
    if (!response.ok) throw new Error(`qa_callable_http_${response.status}`);
    const result = (await response.json()).result;
    if (!result?.simpleAgent || result.failClosed) throw new Error(`qa_fail_closed_${name}`);
    assert.ok(result.stylistComment.length > 0 && result.stylistComment.length <= 500);
    assert.ok(result.resultingOutfitItemIds.every((id) => byId.has(id)));
    assert.ok(result.displayItemIds.every((id) => result.resultingOutfitItemIds.includes(id)));
    console.log(JSON.stringify({scenario: name, message, reply: result.stylistComment,
      items: result.resultingOutfitItems.map((item) => item.name),
      outfitChanged: result.outfitChanged, displayedCount: result.displayItemIds.length,
      // Synthetic weather fixture, NOT a live forecast for the owner.
      weatherFixture: true}));
    return result;
  };
  if (process.argv.includes("--choice-continuity")) {
    // These lexical checks are fixture-specific QA gates, never production
    // language routing. The paired replies must also be reviewed for meaning.
    const normalized = (reply) => reply.normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "").toLowerCase();
    const originalBasis = (reply, previousGarment, reason) => {
      const text = normalized(reply);
      assert.match(text, previousGarment, "qa_original_garment_not_explained");
      assert.match(text, /povod|navrh|odporuc|zvol|vybr|vyber|pocital|pocitali|boli|bola|mal[ai]/,
        "qa_original_choice_not_accounted_for");
      if (reason) assert.match(text, reason, "qa_original_reason_not_preserved");
    };
    const original = await call("generated_initial_choice",
      "Zajtra idem do mesta, poradíš mi outfit?", [], []);
    const priorBottom = original.resultingOutfitItemIds.find((id) =>
      byId.get(id).bodySlots?.includes("lower_body"));
    assert.ok(priorBottom, "qa_generated_bottom_missing");
    const wasShorts = /shorts/.test(byId.get(priorBottom).canonicalType);
    const editMessage = wasShorts ? "Kraťasy by som vymenil za rifle." :
      "Nohavice by som vymenil za kraťasy.";
    const changed = await call("generated_choice_followup", editMessage,
      original.resultingOutfitItemIds, [
        {role: "user", content: "Zajtra idem do mesta, poradíš mi outfit?"},
        {role: "assistant", content: original.stylistComment},
      ]);
    assert.ok(!changed.resultingOutfitItemIds.includes(priorBottom));
    assert.ok(original.resultingOutfitItemIds.filter((id) => id !== priorBottom)
      .every((id) => changed.resultingOutfitItemIds.includes(id)));
    originalBasis(changed.stylistComment,
      wasShorts ? /kratasy|sortk/ : /\brifle\b|rifli|dzins|nohavic/);

    const jeansMention = /\brifle\b|rifli|dzins|nohavic/;
    const history = [
      {role: "user", content: "Zajtra idem do mesta a chcem outfit."},
      {role: "assistant", content: "Biele tričko, tmavomodré rifle, čierna rifľová bunda a tenisky sa hodia do mesta a zvládnu aj chladnejšie ráno."},
    ];
    const cold = await call("reported_jeans_swap", "rifle by som vymenil za kratasy", initialIds, history);
    originalBasis(cold.stylistComment, jeansMention, /rann|rano|chlad/);
    assert.doesNotMatch(normalized(cold.stylistComment), /elegan/,
      "qa_invented_original_elegance_reason");

    // Change the ORIGINAL rationale and remove morning cold: the reply must
    // preserve this different reason instead of copying the cold-morning example.
    const mildWeather = {location: "Martin", tomorrow: {
      morningTempC: 24, noonTempC: 24, eveningTempC: 24,
      minTempC: 24, maxTempC: 24, willRain: false, isWindy: false, fromOpenMeteo: true,
    }};
    const styledHistory = [history[0], {role: "assistant", content:
      "Tmavomodré rifle sú v návrhu pre upravenejší mestský vzhľad oproti kraťasom. S bielym tričkom a čiernou rifľovou bundou zachovajú ležérny štýl."}];
    const styled = await call("different_original_reason", "rifle by som vymenil za kratasy",
      initialIds, styledHistory, mildWeather);
    originalBasis(styled.stylistComment, jeansMention, /upraven|elegan|uhladen/);
    assert.doesNotMatch(normalized(styled.stylistComment), /chlad|\b15\b/,
      "qa_copied_unavailable_cold_reason");

    const jacketHistory = [history[0], {role: "assistant", content:
      "Čierna rifľová bunda je v návrhu preto, že s tmavomodrými rifľami prepája outfit cez džínsovinu. Biele tričko vytvára medzi nimi svetlý kontrast."}];
    const jacket = await call("jacket_choice_followup", "Bundou si nie som istý, radšej mi daj mikinu.",
      initialIds, jacketHistory, mildWeather);
    originalBasis(jacket.stylistComment, /bund/, /dzins|denim|riflov|prepaj/);
    console.log("LIVE_CHOICE_CONTINUITY_GATES_PASS: generated pair and 3 distinct original-rationale fixtures; review paired prose.");
    return;
  }
  const greeting = await call("greeting", "ahoj", [], []);
  assert.deepEqual(greeting.resultingOutfitItemIds, []);
  assert.deepEqual(greeting.displayItemIds, []);
  assert.equal(greeting.outfitChanged, false);
  const history = [
    {role: "user", content: "Zajtra idem do mesta a chcem outfit."},
    {role: "assistant", content: "Biele tričko, tmavomodré rifle, čierna rifľová bunda a tenisky sa hodia do mesta a zvládnu aj chladnejšie ráno."},
  ];
  const shorts = await call("shorts_swap", "rifle by som vymenil za kratasy", initialIds, history);
  const removedBottom = initialIds.find((id) => byId.get(id).bodySlots?.includes("lower_body"));
  assert.ok(removedBottom && !shorts.resultingOutfitItemIds.includes(removedBottom));
  assert.ok(initialIds.filter((id) => id !== removedBottom).every((id) => shorts.resultingOutfitItemIds.includes(id)));
  assert.equal(shorts.resultingOutfitItemIds.length, initialIds.length);
  const newBottom = shorts.resultingOutfitItemIds.find((id) => !initialIds.includes(id));
  assert.match(byId.get(newBottom)?.canonicalType || "", /shorts/);
  history.push({role: "user", content: "rifle by som vymenil za kratasy"},
    {role: "assistant", content: shorts.stylistComment});
  const hoodie = await call("hoodie_full_outfit",
    "môžeš mi ukázať celý outfit? ešte vymeň tú čiernu bundu za nejakú mikinu",
    shorts.resultingOutfitItemIds, history);
  const removedLayer = initialIds.find((id) => {
    const item = byId.get(id);
    return item.bodySlots?.includes("upper_body") && ["mid", "outer", "shell"].includes(item.layerPosition);
  });
  assert.ok(removedLayer && !hoodie.resultingOutfitItemIds.includes(removedLayer));
  assert.ok(shorts.resultingOutfitItemIds.filter((id) => id !== removedLayer)
    .every((id) => hoodie.resultingOutfitItemIds.includes(id)));
  assert.equal(hoodie.resultingOutfitItemIds.length, shorts.resultingOutfitItemIds.length);
  const newLayer = hoodie.resultingOutfitItemIds.find((id) => !shorts.resultingOutfitItemIds.includes(id));
  assert.match(byId.get(newLayer)?.canonicalType || "", /hoodie|sweatshirt/);
  assert.deepEqual(new Set(hoodie.displayItemIds), new Set(hoodie.resultingOutfitItemIds));
  history.push({role: "user", content: "vymeň bundu za mikinu"},
    {role: "assistant", content: hoodie.stylistComment});
  const forecast = await call("weather_dayparts", "super, koľko bude stupňov?", hoodie.resultingOutfitItemIds, history);
  assert.deepEqual(forecast.resultingOutfitItemIds, hoodie.resultingOutfitItemIds);
  assert.deepEqual(forecast.displayItemIds, []);
  assert.equal(forecast.outfitChanged, false);
  for (const value of [15, 24, 22]) assert.match(forecast.stylistComment, new RegExp(`\\b${value}\\b`));
  assert.doesNotMatch(forecast.stylistComment, /\b(?:12|25)\b|bezvetrie/i);
  const wet = await call("weather_rain_wind", "Aké počasie ma zajtra čaká?", hoodie.resultingOutfitItemIds, history, {
    ...weatherContext,
    tomorrow: {...weatherContext.tomorrow, willRain: true, isWindy: true, rainTimeText: "popoludní"},
  });
  assert.deepEqual(wet.resultingOutfitItemIds, hoodie.resultingOutfitItemIds);
  assert.deepEqual(wet.displayItemIds, []);
  assert.doesNotMatch(wet.stylistComment, /\b(?:12|25)\b/);
  console.log("LIVE_SMOKE_STRUCTURAL_PASS: 5 scenarios; review printed prose for quality.");
}

main().catch((error) => {
  // Never print provider bodies, tokens, request objects or credential errors.
  const code = String(error.message || "qa_failed");
  const safeLabel = code.match(/^(?:qa_|existing_|live_)[a-z0-9_]+/);
  console.error(safeLabel ? safeLabel[0] : "qa_check_failed");
  if (/^[a-z0-9_/-]{1,80}$/i.test(String(error.code || ""))) {
    console.error(`qa_error_code:${error.code}`);
  }
  process.exitCode = 1;
}).finally(() => Promise.all(admin.apps.map((app) => app.delete())));
