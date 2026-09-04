"use strict";

// Explicitly invoked against an EXISTING owner-selected account. Reads its
// wardrobe; never supplies notifyJobId, so the callable cannot send notifications.
// Choice summaries are passed back as current context, just like the client.
// No chat documents are created or changed. Credentials stay in memory.
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
  let currentSelectionReasons = [];
  const call = async (name, message, current, history, weather = weatherContext) => {
    const response = await fetch(
      `https://us-east1-${projectId}.cloudfunctions.net/stylistSimpleAgentV1`,
      {method: "POST", headers: {"Content-Type": "application/json", Authorization: `Bearer ${auth.idToken}`},
        body: JSON.stringify({data: {message, history, currentOutfitItemIds: current,
          weatherContext: weather, clientContext,
          currentSelectionReasons}}),
        signal: AbortSignal.timeout(125000)},
    );
    if (!response.ok) throw new Error(`qa_callable_http_${response.status}`);
    const result = (await response.json()).result;
    if (!result?.simpleAgent || result.failClosed) throw new Error(`qa_fail_closed_${name}`);
    assert.ok(result.stylistComment.length > 0 && result.stylistComment.length <= 500);
    assert.ok(["none", "yes_no"].includes(result.quickReplyMode),
      "qa_quick_reply_mode_missing_or_invalid");
    if (result.quickReplyMode === "yes_no") {
      assert.match(result.stylistComment,
        /\?\s*(?:(?:\p{Extended_Pictographic}|\uFE0F|\u200D)\s*)*$/u,
        "qa_quick_reply_question_not_terminal");
    }
    assert.ok(result.resultingOutfitItemIds.every((id) => byId.has(id)));
    assert.ok(result.displayItemIds.every((id) => result.resultingOutfitItemIds.includes(id)));
    console.log(JSON.stringify({scenario: name, message, reply: result.stylistComment,
      items: result.resultingOutfitItems.map((item) => item.name),
      selectionReasons: result.selectionReasons,
      footwearAssessment: result.footwearAssessment,
      outfitRequested: result.outfitRequested,
      outfitChanged: result.outfitChanged, quickReplyMode: result.quickReplyMode,
      displayedCount: result.displayItemIds.length,
      // Synthetic weather fixture, NOT a live forecast for the owner.
      weatherFixture: true}));
    currentSelectionReasons = result.selectionReasons || [];
    return result;
  };
  if (process.argv.includes("--quick-replies")) {
    const preserves = (result, ids) => {
      assert.deepEqual(new Set(result.resultingOutfitItemIds), new Set(ids),
        "qa_quick_reply_changed_outfit");
      assert.equal(result.outfitChanged, false, "qa_quick_reply_changed_flag");
      assert.equal(result.outfitRequested, false, "qa_quick_reply_requested_outfit");
      assert.deepEqual(result.displayItemIds, [], "qa_quick_reply_displayed_cards");
    };
    const normalize = (text) => text.normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "").toLowerCase();
    const offerMessage = "Turistickú obuv nemám. Zatiaľ nič nevyberaj; najprv sa ma iba opýtaj, či chcem poradiť, akú obuv hľadať.";
    currentSelectionReasons = initialIds.map((itemId) => ({
      itemId, reason: "Existujúci QA outfit; v tomto turne sa nesmie meniť.",
    }));
    const offer = await call("quick_reply_yes_no_offer", offerMessage, initialIds, []);
    preserves(offer, initialIds);
    assert.equal(offer.quickReplyMode, "yes_no", "qa_yes_no_offer_has_no_buttons");

    const offerHistory = [
      {role: "user", content: offerMessage},
      {role: "assistant", content: offer.stylistComment},
    ];
    const yes = await call("quick_reply_yes", "Áno", initialIds, offerHistory);
    preserves(yes, initialIds);
    assert.equal(yes.quickReplyMode, "none", "qa_yes_started_question_loop");
    assert.match(normalize(yes.stylistComment),
      /podrazk|velkost|nepremok|turistick|trakci|prilnav|vzorok/,
      "qa_yes_did_not_deliver_advice");

    currentSelectionReasons = offer.selectionReasons || [];
    const no = await call("quick_reply_no", "Nie", initialIds, offerHistory);
    preserves(no, initialIds);
    assert.equal(no.quickReplyMode, "none", "qa_no_started_question_loop");
    assert.doesNotMatch(normalize(no.stylistComment),
      /chces.{0,60}(porad|hladat|vyber)|mozem.{0,60}(porad|hladat|vyber)/,
      "qa_declined_offer_repeated");

    currentSelectionReasons = [];
    const open = await call("quick_reply_open_question",
      "Neviem ešte kam pôjdem. Zatiaľ nič nevyberaj a polož mi otvorenú otázku, kam idem, nie otázku áno alebo nie.", [], []);
    preserves(open, []);
    assert.equal(open.quickReplyMode, "none", "qa_open_question_received_yes_no_buttons");
    assert.match(open.stylistComment, /\?/, "qa_open_question_missing");

    const statement = await call("quick_reply_statement", "Len mi stručne napíš, že rozumieš.", [], []);
    preserves(statement, []);
    assert.equal(statement.quickReplyMode, "none", "qa_statement_received_buttons");
    console.log("LIVE_QUICK_REPLIES_PASS: yes/no offer, yes, no, open question and statement; review all replies.");
    return;
  }
  if (process.argv.includes("--conversation")) {
    // Real acceptance includes the response AFTER a recommendation. Lexical
    // gates here are QA only; the runtime never parses Slovak intent this way.
    const {compactWardrobeItemV1} = require("./simple_stylist_agent_v1");
    const compact = (id) => compactWardrobeItemV1({id, ...byId.get(id)});
    const norm = (text) => text.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
    const preserved = (result, ids, cards = []) => {
      assert.deepEqual(new Set(result.resultingOutfitItemIds), new Set(ids), "qa_consultation_changed_outfit");
      assert.equal(result.outfitChanged, false);
      assert.deepEqual(new Set(result.displayItemIds), new Set(cards), "qa_unrequested_cards");
      if (!cards.length) assert.equal(result.outfitRequested, false, "qa_explanation_counted_as_outfit_request");
    };
    const noFootwearRecap = (result) => assert.doesNotMatch(norm(result.stylistComment),
      /tenisk|turistick.{0,25}obuv|chyba.{0,25}obuv/, "qa_unrelated_footwear_recap");
    const noInventedSearch = (result) => assert.doesNotMatch(norm(result.stylistComment),
      /https?:\/\/|www\.|nasiel som|nasla som|pozrel som obchody|pozrela som obchody|prave som vyhladal/,
      "qa_unavailable_search_claim");
    const mild = {location: "Martin", tomorrow: {...weatherContext.tomorrow,
      morningTempC: 14, hourlyTempCByLocalHour: Array.from({length: 24}, (_, h) => h < 12 ? 14 : 24),
      hourlyWeatherCodeByLocalHour: Array(24).fill(0)}};
    const history = [];
    let ids = [];
    const turn = async (name, message) => {
      const result = await call(name, message, ids, history, mild);
      history.push({role: "user", content: message}, {role: "assistant", content: result.stylistComment});
      ids = result.resultingOutfitItemIds;
      return result;
    };
    const first = await turn("conversation_new_forest_outfit",
      "Zajtra pôjdem ráno na huby po ľahkom suchom lesnom chodníku. Odporuč mi outfit s dlhými rifľami.");
    if (["conditional", "missing"].includes(first.footwearAssessment?.status)) {
      assert.match(norm(first.stylistComment),
        /chces.{0,90}(porad|vyber|hladat|obuv)|(?:mozem|pomozem).{0,90}(porad|vyber|hladat)|hladaj|pri vybere/,
        "qa_real_gap_has_no_feasible_next_step");
    }
    const jeans = ids.find((id) => compact(id)?.canonicalType === "jeans");
    assert.ok(jeans, "qa_explicit_jeans_missing");
    const originalIds = [...ids];
    const originalReasons = [...currentSelectionReasons];
    const answer = await turn("conversation_jeans_suitability", "A rifle sú v poriadku?");
    preserved(answer, originalIds); noFootwearRecap(answer);
    assert.match(norm(answer.stylistComment), /rifl|nohavic|dzins/, "qa_question_not_answered");
    const display = await turn("conversation_explicit_jeans_card", "Ukáž mi prosím tie rifle.");
    preserved(display, originalIds, [jeans]); noFootwearRecap(display);
    const showAll = await turn("conversation_explicit_full_outfit", "Ukáž mi celý outfit.");
    preserved(showAll, originalIds, originalIds);
    const wet = await turn("conversation_new_wet_terrain",
      "A sú tie topánky dobré aj do strmého mokrého lesa? Zatiaľ nič nemeň.");
    preserved(wet, originalIds);
    assert.match(norm(wet.stylistComment), /nevhod|nie|neodpor|nestac|neber|nie su|niesu|kompromis|radsej|nevol|nebral/,
      "qa_changed_conditions_not_acknowledged");
    const refusal = await turn("conversation_declined_shopping",
      "Nič kupovať nechcem. Vysvetli mi iba, či ma tie rifle nebudú obmedzovať pri chôdzi.");
    preserved(refusal, originalIds); noFootwearRecap(refusal);
    assert.doesNotMatch(norm(refusal.stylistComment), /chces.{0,60}(kup|obchod|hladat)|mozem.{0,60}(obchod|vyhladat)/,
      "qa_declined_shopping_reoffered");
    // A separate, explicit pending offer ensures that 'yes' tests conversational
    // continuity rather than depending on the wording of a prior random sample.
    currentSelectionReasons = originalReasons;
    const advice = await call("conversation_accept_advice", "Áno, poraď mi.", originalIds, [
      {role: "user", content: "Chodím aj do mokrého strmého lesa a turistickú obuv nemám."},
      {role: "assistant", content: "Chceš poradiť, aký typ obuvi a vlastnosti hľadať?"},
    ], mild);
    preserved(advice, originalIds); noInventedSearch(advice);
    assert.match(norm(advice.stylistComment), /podrazk|velkost|nepremok|turistick|trakci|pri[lľ]nav|vzorok/,
      "qa_accepted_advice_not_delivered");
    assert.doesNotMatch(norm(advice.stylistComment), /chces.{0,50}porad/, "qa_advice_offer_repeated_after_yes");
    const search = await call("conversation_unavailable_store_search",
      "Pozri mi obchody a nájdi turistické topánky do 80 eur.", originalIds, [], mild);
    preserved(search, originalIds); noInventedSearch(search);
    assert.match(norm(search.stylistComment), /neviem|nemam|nedokaz|nie je|nie su|zatial.{0,30}ne|nie.{0,20}pripoj/,
      "qa_search_capability_not_disclosed");
    console.log(JSON.stringify({scenario: "conversation_review_required", firstReply: first.stylistComment,
      review: "Manually check useful jeans tradeoff, non-repetitive replies, a feasible next step on the real gap, and honest search limits."}));
    console.log("LIVE_CONVERSATION_STRUCTURAL_PASS: 8 turns; semantic review of all replies is still required.");
    return;
  }
  if (process.argv.includes("--footwear")) {
    const {compactWardrobeItemV1} = require("./simple_stylist_agent_v1");
    const {isWinterFootwearV1} = require("./simple_stylist_footwear_v1");
    const compact = (id) => compactWardrobeItemV1({id, ...byId.get(id)});
    const owned = [...byId.keys()].map(compact).filter(Boolean);
    const terrainTypes = new Set(["hiking_shoes", "hiking_boots", "trail_running_shoes"]);
    const sneakers = new Set(["sneakers", "running_shoes", "training_shoes", "basketball_shoes"]);
    console.log(JSON.stringify({scenario: "owned_footwear_metadata", items: owned
      .filter((item) => item.bodySlots.includes("feet")).map((item) => ({name: item.name,
        canonicalType: item.canonicalType, warmth: item.warmth, seasons: item.seasons}))}));
    const mild = {location: "Martin", tomorrow: {...weatherContext.tomorrow, morningTempC: 16,
      hourlyTempCByLocalHour: Array.from({length: 24}, (_, h) => h < 12 ? 16 : 24),
      hourlyWeatherCodeByLocalHour: Array(24).fill(0)}};
    for (const [index, message] of [
      "Ahoj, zajtra chceme ísť ráno na huby, čo si obliecť?",
      "Zajtra ráno ideme zbierať hríby do lesa. Navrhni mi oblečenie.",
      "Na zajtrajšiu rannú prechádzku lesom mimo chodníka mi vyber outfit.",
    ].entries()) {
      currentSelectionReasons = [];
      const selected = await call(`mild_forest_${index}`, message, [], [], mild);
      assert.equal(selected.footwearAssessment?.use, "terrain", "qa_terrain_purpose_lost");
      const shoes = selected.resultingOutfitItemIds.map(compact).filter((item) => item.bodySlots.includes("feet"));
      for (const shoe of shoes) {
        assert.ok(!isWinterFootwearV1(shoe), "qa_winter_boots_in_mild_forest");
        assert.ok(terrainTypes.has(shoe.canonicalType) || sneakers.has(shoe.canonicalType), "qa_non_terrain_boots");
        if (!terrainTypes.has(shoe.canonicalType)) assert.equal(selected.footwearAssessment.status, "conditional");
      }
      if (!shoes.length) assert.equal(selected.footwearAssessment.status, "missing");
    }
    currentSelectionReasons = [];
    const wet = await call("wet_steep_forest", "Zajtra ráno pôjdem do strmého blatistého lesa mimo chodníkov. Vyber mi outfit.",
      [], [], {location: "Martin", tomorrow: {...mild.tomorrow, willRain: true, wetGroundRisk: true}});
    if (!owned.some((item) => terrainTypes.has(item.canonicalType))) {
      assert.equal(wet.footwearAssessment?.status, "missing", "qa_difficult_terrain_gap_not_acknowledged");
      assert.ok(wet.resultingOutfitItemIds.every((id) => !compact(id).bodySlots.includes("feet")));
      const followup = await call("partial_weather_preserve", "Koľko bude zajtra stupňov?",
        wet.resultingOutfitItemIds, [], mild);
      assert.deepEqual(followup.resultingOutfitItemIds, wet.resultingOutfitItemIds);
    }
    currentSelectionReasons = [];
    const snow = {location: "Martin", tomorrow: {...mild.tomorrow,
      morningTempC: -3, noonTempC: 1, eveningTempC: -2, minTempC: -5, maxTempC: 1,
      hourlyTempCByLocalHour: Array(24).fill(-3), hourlyWeatherCodeByLocalHour: Array(24).fill(75)}};
    const winter = await call("snowy_morning", "Zajtra ráno idem pešo von, má snežiť a bude mrznúť. Vyber mi outfit.", [], [], snow);
    if (owned.some(isWinterFootwearV1)) {
      assert.ok(winter.resultingOutfitItemIds.map(compact).some(isWinterFootwearV1), "qa_available_winter_pair_not_selected_for_snow");
    }
    console.log("LIVE_FOOTWEAR_PASS: review purpose, gap wording and weather facts; no wardrobe changes or notifications.");
    return;
  }
  if (process.argv.includes("--detail-salience")) {
    const {compactWardrobeItemV1} = require("./simple_stylist_agent_v1");
    const compact = (id) => compactWardrobeItemV1({id, ...byId.get(id)});
    const base = JSON.parse(process.env.STYLIST_QA_SALIENCE_IDS || "[]");
    const paleId = process.env.STYLIST_QA_PALE_HOODIE_ID;
    assert.equal(base.length, 3, "qa_salience_fixture_required");
    assert.ok(base.every((id) => byId.has(id)) && byId.has(paleId), "qa_salience_items_missing");
    const history = [{role: "user", content: "Zajtra popoludní idem von, vyber mi outfit."},
      {role: "assistant", content: "Čierne tričko a šortky tvoria základ, červené tenisky nadviažu na červenú na tričku."}];
    const preservesBase = (selected) => assert.ok(base.every((id) => selected.resultingOutfitItemIds.includes(id)),
      "qa_unrequested_base_changed");
    const metadata = (selected) => selected.resultingOutfitItemIds.filter((id) => !base.includes(id)).map((id) => {
      const it = compact(id);
      return {name: it.name, canonicalType: it.canonicalType, primaryColor: it.primaryColor,
        secondaryColor: it.secondaryColor, accentColors: it.accentColors, colorProportions: it.colorProportions};
    });
    const chosen = await call("reserve_hoodie_free_choice", "Zobral by som si aj mikinu, keby mi bola zima.", base, history);
    preservesBase(chosen);
    assert.equal(chosen.resultingOutfitItemIds.length, 4);
    console.log(JSON.stringify({scenario: "chosen_reserve_layer_metadata", items: metadata(chosen)}));
    currentSelectionReasons = [];
    const requested = await call("reserve_pale_hoodie", "Pridaj mi tú svetlomodrú mikinu ako rezervu, ostatné nechaj.", base, history);
    preservesBase(requested);
    assert.ok(requested.resultingOutfitItemIds.includes(paleId), "qa_requested_pale_hoodie_missing");
    console.log(JSON.stringify({scenario: "pale_layer_metadata", items: metadata(requested)}));
    const explained = await call("pale_hoodie_reason", "Hodí sa tá mikina k tomu najmä kvôli maličkému čiernemu logu?",
      requested.resultingOutfitItemIds, [...history, {role: "assistant", content: requested.stylistComment}]);
    assert.deepEqual(explained.resultingOutfitItemIds, requested.resultingOutfitItemIds);
    assert.equal(explained.outfitChanged, false);
    assert.deepEqual(explained.displayItemIds, [], "qa_explanation_resent_cards");
    // Prose must be reviewed for meaning: mentioning a tiny logo in order to
    // reject it as the main reason is valid and cannot be judged by keyword bans.
    console.log("LIVE_DETAIL_SALIENCE_STRUCTURAL_PASS: human review of whole-palette reasoning is required.");
    return;
  }
  if (process.argv.includes("--color-details")) {
    const {compactWardrobeItemV1} = require("./simple_stylist_agent_v1");
    const compact = (id) => compactWardrobeItemV1({id, ...byId.get(id)});
    const current = JSON.parse(process.env.STYLIST_QA_DETAIL_CURRENT_IDS || "[]");
    const detailId = process.env.STYLIST_QA_DETAIL_ITEM_ID;
    assert.equal(current.length, 3, "qa_detail_fixture_required");
    assert.ok(current.every((id) => byId.has(id)) && byId.has(detailId), "qa_detail_items_missing");
    const detail = compact(detailId);
    console.log(JSON.stringify({scenario: "detail_metadata", item: detail.name,
      primaryColor: detail.primaryColor, secondaryColor: detail.secondaryColor,
      accentColors: detail.accentColors}));
    const topId = current.find((id) => compact(id).bodySlots.includes("upper_body"));
    const bottomId = current.find((id) => compact(id).bodySlots.includes("lower_body"));
    const shoesId = current.find((id) => compact(id).bodySlots.includes("feet"));
    assert.ok(topId && bottomId && shoesId, "qa_detail_roles_missing");
    const history = [
      {role: "user", content: "Zajtra okolo 14:00 idem do mesta. Vyber mi outfit."},
      {role: "assistant", content: "Biele tričko so sivými šortkami a bielymi teniskami vytvorí svetlý, neutrálny outfit na teplé popoludnie."},
    ];
    currentSelectionReasons = [{itemId: topId,
      reason: "Biele tričko vytvára s bielymi teniskami svetlý, neutrálny základ."}];
    const message = "Môžeš mi prosím vymeniť tričko? A chcel by som tie červené topánky.";
    const selected = await call("color_detail_selection", message, current, history);
    assert.ok(selected.resultingOutfitItemIds.includes(bottomId), "qa_unrequested_bottom_changed");
    assert.ok(!selected.resultingOutfitItemIds.includes(topId), "qa_top_not_changed");
    const selectedTop = selected.resultingOutfitItemIds.map(compact)
      .find((item) => item.bodySlots.includes("upper_body") && item.layerPosition === "base");
    const selectedShoes = selected.resultingOutfitItemIds.map(compact)
      .find((item) => item.bodySlots.includes("feet"));
    assert.equal(selectedShoes.primaryColor, "red", "qa_dominant_red_shoes_missing");
    const normalized = (text) => text.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
    const explainsColorLink = (reply) => {
      assert.match(normalized(reply), /cerven/, "qa_color_not_mentioned");
      assert.match(normalized(reply), /detail|akcent|nadv|prep|zopak|opaku|lad|spaj|spoj/,
        "qa_color_link_not_explained");
    };
    const hasRedDetail = (item) => item.secondaryColor === "red" || item.accentColors.includes("red");
    if (hasRedDetail(detail)) {
      assert.ok(hasRedDetail(selectedTop), "qa_available_detail_not_used");
      explainsColorLink(selected.stylistComment);
    }
    console.log(JSON.stringify({scenario: "selected_top_metadata", item: selectedTop.name,
      primaryColor: selectedTop.primaryColor, secondaryColor: selectedTop.secondaryColor,
      accentColors: selectedTop.accentColors}));
    history.push({role: "user", content: message}, {role: "assistant", content: selected.stylistComment});
    const explanation = await call("color_detail_explanation", "Prečo si vybral práve toto tričko k tým teniskám?",
      selected.resultingOutfitItemIds, history);
    assert.deepEqual(explanation.resultingOutfitItemIds, selected.resultingOutfitItemIds);
    assert.equal(explanation.outfitChanged, false);
    assert.deepEqual(explanation.displayItemIds, [], "qa_explanation_resent_cards");
    if (hasRedDetail(selectedTop)) explainsColorLink(explanation.stylistComment);
    // Palette data never proves a logo, lettering, placement or a brand.
    // These regexes are QA checks only; final replies also need semantic review.
    for (const reply of [selected.stylistComment, explanation.stylistComment]) {
      assert.doesNotMatch(normalized(reply), /logo|napis|potlac|levis|levi's/,
        "qa_palette_invented_print_or_brand");
    }
    console.log(`LIVE_COLOR_DETAILS_PASS: redDetailAvailable=${hasRedDetail(detail)}; review prose and palette.`);
    return;
  }
  if (process.argv.includes("--choice-continuity")) {
    const seedReason = (itemId, reason) => {
      currentSelectionReasons = [{itemId, reason}];
    };
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
    const originalBottomId = initialIds.find((id) => byId.get(id).bodySlots?.includes("lower_body"));
    const history = [
      {role: "user", content: "Zajtra idem do mesta a chcem outfit."},
      {role: "assistant", content: "Biele tričko, tmavomodré rifle, čierna rifľová bunda a tenisky sa hodia do mesta a zvládnu aj chladnejšie ráno."},
    ];
    await seedReason(originalBottomId, "Rifle sú zvolené kvôli chladnejšiemu ránu, aby boli zakryté aj nohy.");
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
    await seedReason(originalBottomId, "Rifle sú zvolené pre upravenejší mestský vzhľad oproti kraťasom.");
    const styled = await call("different_original_reason", "rifle by som vymenil za kratasy",
      initialIds, styledHistory, mildWeather);
    originalBasis(styled.stylistComment, jeansMention, /upraven|elegan|uhladen/);
    assert.doesNotMatch(normalized(styled.stylistComment), /chlad|\b15\b/,
      "qa_copied_unavailable_cold_reason");

    const jacketHistory = [history[0], {role: "assistant", content:
      "Čierna rifľová bunda je v návrhu preto, že s tmavomodrými rifľami prepája outfit cez džínsovinu. Biele tričko vytvára medzi nimi svetlý kontrast."}];
    const originalLayerId = initialIds.find((id) => {
      const item = byId.get(id);
      return item.bodySlots?.includes("upper_body") && ["mid", "outer", "shell"].includes(item.layerPosition);
    });
    await seedReason(originalLayerId, "Rifľová bunda je zvolená pre prepojenie outfitu cez džínsovinu s rifľami.");
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
