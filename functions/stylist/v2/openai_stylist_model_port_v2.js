"use strict";

const MODEL = "gpt-5.6-sol";
const REASONING = "medium";

const LOCATION_FIELDS = ["none", "currentLocationObservation", "destination", "eventLocation"];
const TERRAIN_SURFACES = ["unknown", "paved", "trail", "grass", "forest_floor", "rock"];
const TERRAIN_DIFFICULTIES = ["unknown", "easy", "moderate", "steep", "technical"];
const TERRAIN_CONDITIONS = ["unknown", "dry", "wet", "muddy", "snow", "ice"];
const TERRAIN_FIELDS = ["surface", "difficulty", "condition"];
const WARDROBE_SCOPES = ["none", "current_outfit", "current_outfit_plus_category", "category", "full_relevant"];
const ACTIONS = ["chat", "clarify", "generate_outfit", "edit_outfit", "explain_outfit", "show_items", "stop"];

function nullableString() {
  return {type: ["string", "null"]};
}

const PATCH_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "activityId", "activityLabel", "dateKey", "timeWindowKey",
    "terrainSurface", "terrainDifficulty", "terrainCondition",
    "replaceGroundingRequirements", "weatherRequired", "weatherLocationField", "terrainRequiredFields",
  ],
  properties: {
    activityId: nullableString(),
    activityLabel: nullableString(),
    dateKey: nullableString(),
    timeWindowKey: nullableString(),
    terrainSurface: {type: "string", enum: TERRAIN_SURFACES},
    terrainDifficulty: {type: "string", enum: TERRAIN_DIFFICULTIES},
    terrainCondition: {type: "string", enum: TERRAIN_CONDITIONS},
    replaceGroundingRequirements: {type: "boolean"},
    weatherRequired: {type: "boolean"},
    weatherLocationField: {type: "string", enum: LOCATION_FIELDS},
    terrainRequiredFields: {
      type: "array", uniqueItems: true, maxItems: 3,
      items: {type: "string", enum: TERRAIN_FIELDS},
    },
  },
};

const PLAN_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "kind", "action", "assistantText", "clarificationField", "clarificationQuestion",
    "locationQuery", "locationTargetField", "wardrobeScope", "wardrobeCategory",
    "replaceItemIds", "retainItemIds", "allowedSlots", "allowedCategories", "allowRemovalOnly",
    "patch",
  ],
  properties: {
    kind: {type: "string", enum: ["final", "tool_request"]},
    action: {type: "string", enum: ["none", "chat", "clarify", "stop"]},
    assistantText: {type: "string", maxLength: 700},
    clarificationField: {type: ["string", "null"]},
    clarificationQuestion: {type: ["string", "null"]},
    locationQuery: {type: ["string", "null"]},
    locationTargetField: {type: "string", enum: ["none", "destination", "eventLocation"]},
    wardrobeScope: {type: "string", enum: WARDROBE_SCOPES},
    wardrobeCategory: {type: ["string", "null"]},
    replaceItemIds: {type: "array", maxItems: 12, items: {type: "string", maxLength: 180}},
    retainItemIds: {type: "array", maxItems: 12, items: {type: "string", maxLength: 180}},
    allowedSlots: {type: "array", maxItems: 8, items: {type: "string", maxLength: 80}},
    allowedCategories: {type: "array", maxItems: 8, items: {type: "string", maxLength: 100}},
    allowRemovalOnly: {type: "boolean"},
    patch: PATCH_SCHEMA,
  },
};

const FINAL_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "action", "assistantText", "resultingOutfitItemIds", "selectionReasons",
    "displayKind", "displayItemIds", "editReplaceItemIds", "editRetainItemIds",
    "editAllowedSlots", "editAllowedCategories", "editAllowRemovalOnly",
    "clarificationField", "clarificationQuestion", "offerShopping",
    "shoppingNeedLabel", "shoppingNeedCanonicalType", "shoppingHardConstraints",
    "shoppingSoftPreferences",
  ],
  properties: {
    action: {type: "string", enum: ACTIONS},
    assistantText: {type: "string", maxLength: 900},
    resultingOutfitItemIds: {type: "array", maxItems: 12, items: {type: "string", maxLength: 180}},
    selectionReasons: {
      type: "array", maxItems: 12,
      items: {
        type: "object", additionalProperties: false, required: ["itemId", "reason"],
        properties: {
          itemId: {type: "string", maxLength: 180},
          reason: {type: "string", maxLength: 300},
        },
      },
    },
    displayKind: {type: "string", enum: ["none", "outfit", "items"]},
    displayItemIds: {type: "array", maxItems: 12, items: {type: "string", maxLength: 180}},
    editReplaceItemIds: {type: "array", maxItems: 12, items: {type: "string", maxLength: 180}},
    editRetainItemIds: {type: "array", maxItems: 12, items: {type: "string", maxLength: 180}},
    editAllowedSlots: {type: "array", maxItems: 8, items: {type: "string", maxLength: 80}},
    editAllowedCategories: {type: "array", maxItems: 8, items: {type: "string", maxLength: 100}},
    editAllowRemovalOnly: {type: "boolean"},
    clarificationField: {type: ["string", "null"]},
    clarificationQuestion: {type: ["string", "null"]},
    offerShopping: {type: "boolean"},
    shoppingNeedLabel: {type: ["string", "null"]},
    shoppingNeedCanonicalType: {type: ["string", "null"]},
    shoppingHardConstraints: {type: "array", maxItems: 12, items: {type: "string", maxLength: 160}},
    shoppingSoftPreferences: {type: "array", maxItems: 12, items: {type: "string", maxLength: 160}},
  },
};

function clean(value, max = 900) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function list(value, max = 20) {
  return Array.isArray(value) ? [...new Set(value.map((x) => clean(String(x), 180)).filter(Boolean))].slice(0, max) : [];
}

function plannerPrompt() {
  return [
    "Si plánovacia fáza jedného autoritatívneho AI Stylistu V2. Používateľ komunikuje po slovensky.",
    "Najnovšia otázka má prioritu; starší kontext používaj len ako podporu.",
    "Ak session.conversationMemory.pendingQuestion existuje, najnovšiu odpoveď najprv priraď k TOMUTO poľu (date/timeWindow/terrain/location). Nezačínaj pôvodnú tému odznova.",
    "V tejto fáze NESMIEŠ vybrať finálny nový outfit. Môžeš skončiť iba chat/clarify/stop alebo vyžiadať nástroje.",
    "GPS/currentLocationObservation a destination/eventLocation sú rôzne fakty. Nikdy nepovýš GPS na cieľ výletu či udalosti.",
    "Ak používateľ žiada outfit na vzdialenú aktivitu/udalosť a miesto nepoznáme, polož presne JEDNU otázku na miesto a nežiadaj wardrobe.",
    "Ak miesto používateľ uviedol v tej istej správe, vyžiadaj location tool s presným kandidátom; nežiadaj ho znova otázkou.",
    "Počasie pri remote/event outfite musí používať destination/eventLocation. Pri jasne lokálnom rutinnom outfite môže používať currentLocationObservation.",
    "Výrazy túra/les/huby samy osebe NEZNAMENAJÚ mokro, blato, strmosť, skaly, sneh ani ľad. Terrain fakt nastav len z explicitného tvrdenia.",
    "Terrain clarification vyžaduj len keď konkrétna neznáma vlastnosť materiálne mení bezpečnosť obuvi; najviac jednu otázku na turn.",
    "Relative date: používaj clientCapabilities.todayDateKey/tomorrowDateKey. Nevymýšľaj iný kalendárny deň.",
    "replaceGroundingRequirements=true nastav iba keď tento turn zakladá alebo mení outfitový kontext; pri bežnom follow-upe ponechaj false, aby sa kanonické grounding pravidlá nestratili.",
    "Pre nový outfit vyžiadaj full_relevant. Pre konzultáciu o aktuálnom outfite môžeš skončiť v plan fáze bez ďalšieho wardrobe, lebo current outfit facts sú už v toolResults.",
    "Pri editácii jedného slotu vyžiadaj current_outfit_plus_category a zmraz presný edit scope. Z toolResults.current outfit facts vieš určiť exact replaceItemIds.",
    "Ak používateľ len chce pridať vrstvu, nepremieňaj to na úplný rebuild; zachovaj ostatné kusy a vyžiadaj príslušnú kategóriu.",
    "Karty sa nezobrazujú pri obyčajnej konzultácii alebo vysvetlení.",
    "Ak payload obsahuje userStylePreferences, rešpektuj ich ako mäkké preferencie; nesmú prebiť bezpečnosť ani explicitnú požiadavku.",
    "Nepoužívaj technické výrazy validator/fail-closed/metadata v assistantText.",
  ].join("\n");
}

function finalPrompt() {
  return [
    "Si finálna fáza toho istého autoritatívneho AI Stylistu V2. Odpovedaj prirodzene po slovensky.",
    "Vyberaj iba item IDs, ktoré sú v toolResults.wardrobeItems. Nikdy nevymýšľaj ID.",
    "Účel a bezpečnosť > počasie/tepelná vhodnosť > celkový štýl > dominantné farby > malé detaily.",
    "Ak payload obsahuje userStylePreferences, používaj ich ako mäkké preferencie po splnení účelu, bezpečnosti a explicitných požiadaviek.",
    "Primary/dominant color nie je to isté ako accent. Nevymýšľaj logo, potlač ani umiestnenie detailu bez dôkazu v dátach.",
    "Pri zachovanom kuse zachovaj jeho persistovaný selection reason PRESNE; nový dôvod patrí len novému kusu.",
    "Ak používateľ chce meniť iba jednu vec, všetko mimo autorizovaného edit scope musí zostať rovnaké.",
    "Pri vysvetlení alebo otázke typu 'A rifle sú v poriadku?' outfit nemeníš a displayKind=none.",
    "Ak pre bezpečné podmienky chýba vhodná obuv, povedz to otvorene. Neobhajuj zlú voľbu. Ponúkni Shopping len ako užitočný ďalší krok.",
    "Tenisky môžu byť explicitný kompromis iba na ľahký suchý terén. Mokro/strmosť/technický terén nepredstieraj ako bezpečný pre nevhodnú obuv.",
    "Zimnú obuv nevyberaj len preto, že ide o les/túru; potrebuje mráz, sneh/ľad alebo iný skutočný dôvod.",
    "Ak sa predchádzajúce odporúčanie ukáže ako zlé, pokojne to priznaj a oprav. Nevymýšľaj historický dôvod, ktorý nebol uložený.",
    "Text, resultingOutfitItemIds a displayItemIds musia opisovať ten istý výsledok.",
    "Ak ponúkneš nákup, assistantText má prirodzene skončiť jednou áno/nie otázkou a offerShopping=true.",
  ].join("\n");
}

function patchFromRaw(raw, session) {
  const patch = raw?.patch || {};
  const context = {};
  if (clean(patch.activityId, 100)) {
    context.activity = {id: clean(patch.activityId, 100), label: clean(patch.activityLabel, 160) || clean(patch.activityId, 100), source: "user"};
  }
  if (clean(patch.dateKey, 20)) context.date = {dateKey: clean(patch.dateKey, 20), source: "user"};
  if (clean(patch.timeWindowKey, 40)) context.timeWindow = {key: clean(patch.timeWindowKey, 40), source: "user"};
  const terrain = {...(session?.context?.terrain || {surface: null, difficulty: null, condition: null})};
  let terrainChanged = false;
  for (const [rawKey, target] of [["terrainSurface", "surface"], ["terrainDifficulty", "difficulty"], ["terrainCondition", "condition"]]) {
    const value = clean(patch[rawKey], 40);
    if (value && value !== "unknown") {
      terrain[target] = value;
      terrainChanged = true;
    }
  }
  if (terrainChanged) context.terrain = terrain;
  if (patch.replaceGroundingRequirements === true) {
    context.groundingRequirements = {
      weatherRequired: patch.weatherRequired === true,
      weatherLocationField: LOCATION_FIELDS.includes(patch.weatherLocationField) && patch.weatherLocationField !== "none" ? patch.weatherLocationField : null,
      terrainRequiredFields: list(patch.terrainRequiredFields, 3).filter((field) => TERRAIN_FIELDS.includes(field)),
    };
  }
  return {context};
}

function planEnvelope(raw, input) {
  const statePatch = patchFromRaw(raw, input.session);
  if (raw.kind === "final") {
    const action = ["chat", "clarify", "stop"].includes(raw.action) ? raw.action : "stop";
    const result = {
      action,
      assistantText: clean(raw.assistantText) || (action === "clarify" ? "Čo potrebuješ upresniť?" : "Rozumiem."),
      display: {kind: "none", itemIds: []},
    };
    if (action === "clarify") {
      const field = clean(raw.clarificationField, 80) || "context";
      let question = clean(raw.clarificationQuestion) || clean(raw.assistantText);
      if (!question.endsWith("?")) question = `${question.replace(/[.!]+$/g, "")}?`;
      result.assistantText = question;
      result.clarification = {field, question, actionId: `clarify_${field.replace(/[^A-Za-z0-9_-]/g, "_")}`};
    }
    return {kind: "final", result, statePatch};
  }

  const requests = [];
  if (clean(raw.locationQuery) && ["destination", "eventLocation"].includes(raw.locationTargetField)) {
    requests.push({tool: "location", query: clean(raw.locationQuery, 240), targetField: raw.locationTargetField});
  }
  if (WARDROBE_SCOPES.includes(raw.wardrobeScope) && raw.wardrobeScope !== "none") {
    const editScope = raw.replaceItemIds.length || raw.retainItemIds.length || raw.allowedSlots.length || raw.allowedCategories.length ? {
      replaceItemIds: list(raw.replaceItemIds, 12),
      retainItemIds: list(raw.retainItemIds, 12),
      allowedSlots: list(raw.allowedSlots, 8),
      allowedCategories: list(raw.allowedCategories, 8),
      allowRemovalOnly: raw.allowRemovalOnly === true,
    } : null;
    requests.push({
      tool: "wardrobe",
      scope: raw.wardrobeScope,
      category: clean(raw.wardrobeCategory, 100) || null,
      editScope,
    });
  }
  if (!requests.length) {
    return {kind: "final", result: {action: "stop", assistantText: "Potrebujem ešte trochu kontextu, aby som ti poradil správne.", display: {kind: "none", itemIds: []}}, statePatch};
  }
  return {kind: "tool_request", requests, statePatch};
}

function finalEnvelope(raw, input) {
  const ids = list(raw.resultingOutfitItemIds, 12);
  const reasons = {};
  for (const entry of Array.isArray(raw.selectionReasons) ? raw.selectionReasons : []) {
    const id = clean(entry?.itemId, 180);
    const reason = clean(entry?.reason, 300);
    if (id && reason && ids.includes(id)) reasons[id] = reason;
  }
  // Retained reasons are immutable. Fill them from canonical session even if
  // the model forgot to repeat them; this is safe normalization, not new advice.
  for (const id of ids) {
    const previous = input.session?.currentOutfit?.selectionReasonsByItemId?.[id];
    if (previous != null && input.session?.currentOutfit?.itemIds?.includes(id)) reasons[id] = previous;
  }
  const action = ACTIONS.includes(raw.action) ? raw.action : "stop";
  const result = {
    action,
    assistantText: clean(raw.assistantText) || "Rozumiem.",
    resultingOutfit: {itemIds: ids, selectionReasonsByItemId: reasons, compromises: [], missingWardrobeNeeds: []},
    display: {kind: ["none", "outfit", "items"].includes(raw.displayKind) ? raw.displayKind : "none", itemIds: list(raw.displayItemIds, 12)},
  };
  if (action === "edit_outfit") {
    const authorized = input.toolResults?.authorizedEditScope;
    result.editScope = authorized ? JSON.parse(JSON.stringify(authorized)) : {
      replaceItemIds: list(raw.editReplaceItemIds, 12),
      retainItemIds: list(raw.editRetainItemIds, 12),
      allowedSlots: list(raw.editAllowedSlots, 8),
      allowedCategories: list(raw.editAllowedCategories, 8),
      allowRemovalOnly: raw.editAllowRemovalOnly === true,
    };
  }
  if (action === "clarify") {
    const field = clean(raw.clarificationField, 80) || "context";
    let question = clean(raw.clarificationQuestion) || result.assistantText;
    if (!question.endsWith("?")) question = `${question.replace(/[.!]+$/g, "")}?`;
    result.assistantText = question;
    result.clarification = {field, question, actionId: `clarify_${field.replace(/[^A-Za-z0-9_-]/g, "_")}`};
  }

  const statePatch = {};
  if (raw.offerShopping === true && clean(raw.shoppingNeedLabel, 180)) {
    const actionId = `shop_${String(input.request.turnId).replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 120)}`;
    statePatch.pendingAction = {type: "action", kind: "shopping", actionId};
    result.quickReplies = [
      {actionId: `${actionId}_yes`, label: "Áno"},
      {actionId: `${actionId}_no`, label: "Nie"},
    ];
    statePatch.shopping = {
      missingNeed: {
        label: clean(raw.shoppingNeedLabel, 180),
        canonicalType: clean(raw.shoppingNeedCanonicalType, 100) || null,
      },
      hardConstraints: list(raw.shoppingHardConstraints, 12),
      softPreferences: list(raw.shoppingSoftPreferences, 12),
      openedReason: clean(raw.shoppingNeedLabel, 180),
    };
  }
  return {kind: "final", result, statePatch};
}


function enforceHighConfidenceGrounding(raw, input) {
  const message = clean(input?.request?.latestUserInput, 1200).toLocaleLowerCase("sk-SK");
  const outfitRequest = /(outfit|oble[cč]|oblie[cč]|čo si mám dať|co si mam dat|potrebujem.{0,30}(oble|outfit))/i.test(message);
  const outdoorTrip = /(túr|turist|hub(?:y|ár)|do lesa|v lese)/i.test(message);
  const hasDestination = Boolean(input?.session?.context?.destination);
  const requestsDestination = raw?.kind === "tool_request" && clean(raw?.locationQuery) && raw?.locationTargetField === "destination";
  if (!outfitRequest || !outdoorTrip || hasDestination || requestsDestination) return raw;
  const patch = {...(raw?.patch || {})};
  patch.activityId = clean(patch.activityId, 100) || "hiking";
  patch.activityLabel = clean(patch.activityLabel, 160) || "outdoor aktivita";
  patch.replaceGroundingRequirements = true;
  patch.weatherRequired = true;
  patch.weatherLocationField = "destination";
  patch.terrainRequiredFields = [];
  return {
    ...raw, kind: "final", action: "clarify",
    assistantText: "Kam presne ideš?",
    clarificationField: "destination", clarificationQuestion: "Kam presne ideš?",
    locationQuery: null, locationTargetField: "none", wardrobeScope: "none", wardrobeCategory: null,
    replaceItemIds: [], retainItemIds: [], allowedSlots: [], allowedCategories: [], allowRemovalOnly: false,
    patch,
  };
}

function createOpenAiStylistModelPortV2({executeStructured, userStylePreferences = null}) {
  if (typeof executeStructured !== "function") throw new TypeError("v2_structured_model_executor_required");
  return Object.freeze({
    planningNeedsCurrentOutfit: true,
    async turn(input) {
      const phase = input?.phase === "final" ? "final" : "plan";
      const wardrobeV2 = Array.isArray(input?.toolResults?.wardrobeItems) ? input.toolResults.wardrobeItems : [];
      const payload = {
        wardrobeV2,
        request: input.request,
        session: input.session,
        preflightResolution: input.preflightResolution,
        toolResults: input.toolResults,
        userStylePreferences,
      };
      const raw = await executeStructured({
        model: MODEL,
        reasoningEffort: REASONING,
        schema: phase === "plan" ? PLAN_SCHEMA : FINAL_SCHEMA,
        schemaName: phase === "plan" ? "stylist_v2_plan" : "stylist_v2_final",
        maxOutputTokens: phase === "plan" ? 2600 : 3600,
        messages: [
          {role: "system", content: phase === "plan" ? plannerPrompt() : finalPrompt()},
          {role: "user", content: JSON.stringify(payload)},
        ],
      }, {modelAttempt: 1});
      return phase === "plan" ? planEnvelope(enforceHighConfidenceGrounding(raw, input), input) : finalEnvelope(raw, input);
    },
  });
}

module.exports = {
  FINAL_SCHEMA,
  MODEL,
  PLAN_SCHEMA,
  REASONING,
  createOpenAiStylistModelPortV2,
  enforceHighConfidenceGrounding,
  finalEnvelope,
  planEnvelope,
};
