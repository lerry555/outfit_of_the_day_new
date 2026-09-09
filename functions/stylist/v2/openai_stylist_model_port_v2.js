"use strict";

const PLAN_MODEL = "gpt-5.6-luna";
const PLAN_REASONING = "low";
const FINAL_MODEL = "gpt-5.6-terra";
const FINAL_REASONING = "low";
const FINAL_REASONING_ESCALATED = "medium";
// Backward-compatible exports for diagnostics that previously expected one model.
const MODEL = FINAL_MODEL;
const REASONING = FINAL_REASONING;

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
      type: "array", maxItems: 3,
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
    assistantText: {type: "string"},
    clarificationField: {type: ["string", "null"]},
    clarificationQuestion: {type: ["string", "null"]},
    locationQuery: {type: ["string", "null"]},
    locationTargetField: {type: "string", enum: ["none", "destination", "eventLocation"]},
    wardrobeScope: {type: "string", enum: WARDROBE_SCOPES},
    wardrobeCategory: {type: ["string", "null"]},
    replaceItemIds: {type: "array", maxItems: 12, items: {type: "string"}},
    retainItemIds: {type: "array", maxItems: 12, items: {type: "string"}},
    allowedSlots: {type: "array", maxItems: 8, items: {type: "string"}},
    allowedCategories: {type: "array", maxItems: 8, items: {type: "string"}},
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
    assistantText: {type: "string"},
    resultingOutfitItemIds: {type: "array", maxItems: 12, items: {type: "string"}},
    selectionReasons: {
      type: "array", maxItems: 12,
      items: {
        type: "object", additionalProperties: false, required: ["itemId", "reason"],
        properties: {
          itemId: {type: "string"},
          reason: {type: "string"},
        },
      },
    },
    displayKind: {type: "string", enum: ["none", "outfit", "items"]},
    displayItemIds: {type: "array", maxItems: 12, items: {type: "string"}},
    editReplaceItemIds: {type: "array", maxItems: 12, items: {type: "string"}},
    editRetainItemIds: {type: "array", maxItems: 12, items: {type: "string"}},
    editAllowedSlots: {type: "array", maxItems: 8, items: {type: "string"}},
    editAllowedCategories: {type: "array", maxItems: 8, items: {type: "string"}},
    editAllowRemovalOnly: {type: "boolean"},
    clarificationField: {type: ["string", "null"]},
    clarificationQuestion: {type: ["string", "null"]},
    offerShopping: {type: "boolean"},
    shoppingNeedLabel: {type: ["string", "null"]},
    shoppingNeedCanonicalType: {type: ["string", "null"]},
    shoppingHardConstraints: {type: "array", maxItems: 12, items: {type: "string"}},
    shoppingSoftPreferences: {type: "array", maxItems: 12, items: {type: "string"}},
  },
};

function clean(value, max = 900) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function list(value, max = 20) {
  return Array.isArray(value) ? [...new Set(value.map((x) => clean(String(x), 180)).filter(Boolean))].slice(0, max) : [];
}

function normalizeIntentTextV2(value) {
  return clean(value, 1200)
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function finalReasoningForInputV2(input) {
  const terrain = input?.session?.context?.terrain || {};
  const condition = clean(terrain.condition, 40).toLowerCase();
  const difficulty = clean(terrain.difficulty, 40).toLowerCase();
  const surface = clean(terrain.surface, 40).toLowerCase();
  const latest = normalizeIntentTextV2(input?.request?.latestUserInput);
  const safetySensitive = ["wet", "muddy", "snow", "ice"].includes(condition) ||
    ["steep", "technical"].includes(difficulty) || surface === "rock";
  const formalSensitive = /\b(svadba|wedding|pohovor|interview|ples|pohreb|funeral|ceremonia)\b/.test(latest);
  return safetySensitive || formalSensitive ? FINAL_REASONING_ESCALATED : FINAL_REASONING;
}

function stripTrailingShoppingQuestionV2(value) {
  const original = clean(value);
  if (!original) return original;
  const stripped = original
    .replace(/\s*(?:chceš|chces|mám ti|mam ti)\b[^?]{0,320}\?\s*$/iu, "")
    .trim();
  return stripped || original;
}

function shouldPreloadCurrentOutfitV2(input) {
  const currentIds = input?.session?.currentOutfit?.itemIds || [];
  if (!currentIds.length) return false;
  const text = normalizeIntentTextV2(input?.request?.latestUserInput);
  if (!text) return false;
  const edit = /\b(vymen|vymenit|nahra|nahrad|zmen|zmenit|odober|odstran|pridaj|pridat|ine topanky|iny vrch|iny spodok|swap|replace)\b/.test(text);
  const currentPiece = /\b(outfit|rifle|nohavice|sortky|kratasy|tricko|kosela|mikina|sveter|bunda|kabat|topanky|tenisky|obuv|doplnok)\b/.test(text);
  const opinion = /\b(je to ok|su v poriadku|co povies|co si myslis|hodi sa|sedi to|pasuje)\b/.test(text);
  return edit || currentPiece && opinion;
}

function plannerPrompt() {
  return [
    "Si plánovacia fáza jedného autoritatívneho AI Stylistu V2. Používateľ komunikuje po slovensky.",
    "HLAVNÉ PRAVIDLO: HELP FIRST, CLARIFY ONLY WHEN NECESSARY. Najprv sa snaž pomôcť z faktov, ktoré už máš; otázku polož iba ak odpoveď materiálne zmení výsledok alebo bezpečnosť.",
    "Najnovšia správa má prioritu; starší kontext používaj ako pamäť, nie ako formulár, ktorý musíš znovu vypĺňať.",
    "pendingQuestion je iba kontext. Ak používateľ odpovie otázkou typu 'načo ti to je?', 'prečo?', povie 'neviem', 'je mi to jedno', 'preskoč to' alebo 'daj mi proste outfit', NESMIEŠ tú vetu interpretovať ako hodnotu pending poľa.",
    "V tejto fáze NESMIEŠ vybrať finálny nový outfit. Môžeš skončiť iba chat/clarify/stop alebo vyžiadať nástroje.",
    "GPS/currentLocationObservation a destination/eventLocation sú rôzne fakty. Nikdy nepovýš GPS na cieľ výletu či udalosti.",
    "Pri vzdialenej aktivite sa na miesto pýtaj iba ak ho naozaj potrebuješ pre relevantné počasie. Mesto, horská oblasť, stredisko alebo konkrétny bod sú zvyčajne dostatočné; nežiadaj presnú trasu bez bezpečnostného dôvodu.",
    "Ak používateľ uvedie iba veľmi širokú krajinu (napr. USA), vypýtaj si mesto, štát alebo región. Po užitočnom spresnení sa na miesto znovu nepýtaj.",
    "Ak miesto používateľ uviedol v tej istej správe, vyžiadaj location tool s presným kandidátom; nepýtaj ho znova otázkou.",
    "Počasie pri remote/event outfite musí používať destination/eventLocation. Pri jasne lokálnom rutinnom outfite môže používať currentLocationObservation.",
    "Chýbajúca časť dňa NIE JE dôvod na ďalšiu otázku. Ak je dátum známy a používateľ nepovedal čas, pracuj s celodenným oknom 'day'.",
    "Výrazy túra/les/huby samy osebe NEZNAMENAJÚ mokro, blato, strmosť, skaly, sneh ani ľad. Terrain fakt nastav len z explicitného tvrdenia.",
    "Terrain clarification vyžaduj len keď konkrétna neznáma vlastnosť skutočne mení bezpečnosť obuvi; najviac jednu otázku na turn.",
    "Relative date: používaj clientCapabilities.todayDateKey/tomorrowDateKey. Nevymýšľaj iný kalendárny deň.",
    "replaceGroundingRequirements=true nastav iba keď tento turn zakladá alebo mení outfitový kontext; pri bežnom follow-upe ponechaj false.",
    "Pre nový outfit vyžiadaj full_relevant. Pre obyčajný chat wardrobe nežiadaj. Pri konzultácii aktuálneho outfitu používaj už prednačítané current outfit facts iba keď sú skutočne relevantné.",
    "Pri editácii jedného slotu vyžiadaj current_outfit_plus_category a zmraz presný edit scope.",
    "Ak používateľ len chce pridať vrstvu, nepremieňaj to na úplný rebuild; zachovaj ostatné kusy a vyžiadaj príslušnú kategóriu.",
    "Karty sa nezobrazujú pri obyčajnej konzultácii alebo vysvetlení.",
    "Ak payload obsahuje userStylePreferences, rešpektuj ich ako mäkké preferencie; nesmú prebiť bezpečnosť ani explicitnú požiadavku.",
    "Nepoužívaj technické výrazy validator/fail-closed/metadata v assistantText.",
  ].join("\n");
}

function finalPrompt() {
  return [
    "Si finálna fáza toho istého autoritatívneho AI Stylistu V2. Odpovedaj prirodzene po slovensky.",
    "HLAVNÉ PRAVIDLO: HELP FIRST, CLARIFY ONLY WHEN NECESSARY. Keď vieš bezpečne odporučiť rozumný outfit, urob to namiesto ďalšej otázky.",
    "Vyberaj iba item IDs, ktoré sú v toolResults.wardrobeItems. Nikdy nevymýšľaj ID.",
    "Účel a bezpečnosť > počasie/tepelná vhodnosť > celkový štýl > dominantné farby > malé detaily.",
    "Ak payload obsahuje userStylePreferences, používaj ich ako mäkké preferencie po splnení účelu, bezpečnosti a explicitných požiadaviek.",
    "Primary/dominant color nie je to isté ako accent. Nevymýšľaj logo, potlač ani umiestnenie detailu bez dôkazu v dátach.",
    "Pri zachovanom kuse zachovaj jeho persistovaný selection reason PRESNE; nový dôvod patrí len novému kusu.",
    "Ak používateľ chce meniť iba jednu vec, všetko mimo autorizovaného edit scope musí zostať rovnaké.",
    "Pri vysvetlení alebo otázke typu 'A rifle sú v poriadku?' outfit nemeníš a displayKind=none.",
    "Ak ide o bežnú turistiku a NIE JE známy mokrý, blatistý, zasnežený, ľadový, skalnatý, strmý alebo technický terén, absencia turistických topánok nesmie zablokovať outfit. Vyber najpraktickejšie vhodné tenisky, ktoré používateľ vlastní, otvorene ich označ ako kompromis a ponúkni doplnenie turistickej obuvi.",
    "Neznámy terén nie je dôkaz nebezpečného terénu. Zároveň nikdy netvrď, že tenisky sú bezpečné na explicitne mokrý/strmý/technický/snehový/ľadový terén.",
    "Zimnú obuv nevyberaj len preto, že ide o les alebo túru. Potrebuje mráz, sneh/ľad alebo iný skutočný dôvod. V teple je praktická teniska lepší fallback než zimná topánka.",
    "Ak vhodný ideálny kus chýba, vyber najlepší prijateľný kus zo šatníka, vysvetli limit a offerShopping=true, ak by doplnenie šatníka bolo užitočné. Pri offerShopping vždy vyplň shoppingNeedLabel a shoppingNeedCanonicalType, ak ho poznáš.",
    "Text píš ako 2 až 4 krátke, úplné a gramaticky prirodzené vety s normálnou interpunkciou. Nepíš surový inline zoznam oddelený pomlčkami; karty pod správou už zobrazia jednotlivé kúsky.",
    "Najprv jednou vetou zhrň podmienky, potom jednou až dvoma vetami vysvetli kombináciu a prípadný kompromis. Neopakuj názov každého kúsku, ak to nepridáva užitočné vysvetlenie.",
    "Ak ponúkneš nákup, assistantText NESMIE obsahovať otázku Áno/Nie ani vetu 'Chceš, aby som...'. UI zobrazí samostatnú nákupnú otázku až POD kartami outfitu. Nastav iba offerShopping=true a shoppingNeedLabel.",
    "Ak sa predchádzajúce odporúčanie ukáže ako zlé, pokojne to priznaj a oprav. Nevymýšľaj historický dôvod, ktorý nebol uložený.",
    "Text, resultingOutfitItemIds a displayItemIds musia opisovať ten istý výsledok.",
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
  const canonicalNeed = clean(raw.shoppingNeedCanonicalType, 100);
  const needLabel = clean(raw.shoppingNeedLabel, 180) || canonicalNeed.replace(/_/g, " ");
  if (raw.offerShopping === true) {
    result.assistantText = stripTrailingShoppingQuestionV2(result.assistantText);
  }
  if (raw.offerShopping === true && needLabel) {
    const actionId = `shop_${String(input.request.turnId).replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 120)}`;
    statePatch.pendingAction = {type: "action", kind: "shopping", actionId};
    result.quickReplies = [
      {actionId: `${actionId}_yes`, label: "Áno"},
      {actionId: `${actionId}_no`, label: "Nie"},
    ];
    result.resultingOutfit.missingWardrobeNeeds = [needLabel];
    statePatch.shopping = {
      missingNeed: {
        label: needLabel,
        canonicalType: canonicalNeed || null,
      },
      hardConstraints: list(raw.shoppingHardConstraints, 12),
      softPreferences: list(raw.shoppingSoftPreferences, 12),
      openedReason: needLabel,
    };
  }
  return {kind: "final", result, statePatch};
}

// Kept as an export for compatibility. Grounding is now enforced generically by
// stylist_grounding_policy_v2 and the coordinator instead of a hike-specific
// hard-coded question in the model adapter.
function enforceHighConfidenceGrounding(raw, input) {
  const message = normalizeIntentTextV2(input?.request?.latestUserInput);
  const outfitRequest = /\b(outfit|oblecenie|obliect|co si mam dat|co mam na seba|vyber mi|navrhni mi|zostav mi)\b/.test(message);
  const hasLocationRequest = raw?.kind === "tool_request" &&
    clean(raw?.locationQuery) &&
    ["destination", "eventLocation"].includes(raw?.locationTargetField);
  const hasWardrobeRequest = raw?.kind === "tool_request" &&
    WARDROBE_SCOPES.includes(raw?.wardrobeScope) &&
    raw.wardrobeScope !== "none";
  if (!outfitRequest || !hasLocationRequest || hasWardrobeRequest) return raw;

  // One planning phase may ask for location + wardrobe together. The coordinator
  // resolves location/grounding first and skips the wardrobe read if another
  // material fact is still missing, so this avoids an unnecessary second model
  // phase without wasting a full wardrobe read.
  return {
    ...raw,
    wardrobeScope: "full_relevant",
    wardrobeCategory: null,
  };
}

function createOpenAiStylistModelPortV2({executeStructured, userStylePreferences = null}) {
  if (typeof executeStructured !== "function") throw new TypeError("v2_structured_model_executor_required");
  return Object.freeze({
    planningNeedsCurrentOutfit: false,
    shouldPreloadCurrentOutfit: shouldPreloadCurrentOutfitV2,
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
      const reasoningEffort = phase === "plan" ? PLAN_REASONING : finalReasoningForInputV2(input);
      const model = phase === "plan" ? PLAN_MODEL : FINAL_MODEL;
      const startedAt = Date.now();
      let raw;
      try {
        raw = await executeStructured({
          model,
          reasoningEffort,
          schema: phase === "plan" ? PLAN_SCHEMA : FINAL_SCHEMA,
          schemaName: phase === "plan" ? "stylist_v2_plan" : "stylist_v2_final",
          maxOutputTokens: phase === "plan" ? 1200 : 1800,
          messages: [
            {role: "system", content: phase === "plan" ? plannerPrompt() : finalPrompt()},
            {role: "user", content: JSON.stringify(payload)},
          ],
        }, {modelAttempt: 1});
      } finally {
        console.info("STYLIST_V2_MODEL_LATENCY", {
          phase,
          model,
          reasoningEffort,
          durationMs: Date.now() - startedAt,
          wardrobeItemCount: wardrobeV2.length,
        });
      }
      return phase === "plan" ? planEnvelope(enforceHighConfidenceGrounding(raw, input), input) : finalEnvelope(raw, input);
    },
  });
}

module.exports = {
  FINAL_MODEL,
  FINAL_REASONING,
  FINAL_REASONING_ESCALATED,
  FINAL_SCHEMA,
  MODEL,
  PLAN_MODEL,
  PLAN_REASONING,
  PLAN_SCHEMA,
  REASONING,
  createOpenAiStylistModelPortV2,
  enforceHighConfidenceGrounding,
  finalEnvelope,
  finalReasoningForInputV2,
  planEnvelope,
  shouldPreloadCurrentOutfitV2,
  stripTrailingShoppingQuestionV2,
};
