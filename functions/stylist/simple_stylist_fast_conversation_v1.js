"use strict";

const FAST_CONVERSATION_MODEL = "gpt-5.6-luna";
const FAST_CONVERSATION_REASONING_EFFORT = "low";

const FAST_CONVERSATION_SCHEMA = Object.freeze({
  type: "object",
  additionalProperties: false,
  required: [
    "route",
    "stylistComment",
    "quickReplyMode",
    "weatherContextKey",
    "shoppingHandoff",
    "shoppingNeedText",
    "shoppingNeedLabel",
  ],
  properties: {
    route: {type: "string", enum: ["fast_reply", "full_stylist"]},
    stylistComment: {type: "string", maxLength: 500},
    quickReplyMode: {type: "string", enum: ["none", "yes_no"]},
    weatherContextKey: {
      type: "string",
      enum: ["current", "today", "tomorrow", "none"],
    },
    shoppingHandoff: {
      type: "string",
      enum: ["none", "ask_permission", "start_search"],
    },
    shoppingNeedText: {type: "string", maxLength: 160},
    shoppingNeedLabel: {type: "string", maxLength: 160},
  },
});

function cleanText(value, max = 500) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function normalizeHistory(raw) {
  if (!Array.isArray(raw)) return [];
  return raw.slice(-8).map((entry) => {
    const role = entry?.role === "user" || entry?.role === "assistant" ?
      entry.role : null;
    const content = cleanText(entry?.content, 1800);
    return role && content ? {role, content} : null;
  }).filter(Boolean);
}

function buildFastConversationInputV1(input) {
  const shoppingEnabled = input?.shoppingEnabled === true;
  const system = [
    "Si rýchla konverzačná vetva osobného stylistu. Rozumieš prirodzenému jazyku; nie si regexový parser.",
    "Tvojou prvou úlohou je bezpečne rozhodnúť route. Pri neistote vždy zvoľ full_stylist.",
    "full_stylist zvoľ pri každej žiadosti vytvoriť, vybrať, zmeniť, pridať, odobrať alebo ukázať outfit či kus; tiež keď odpoveď potrebuje porovnávať konkrétne kúsky šatníka alebo overovať ich vlastnosti.",
    "fast_reply zvoľ iba keď outfit zostáva bez zmeny a netreba zobrazovať karty: pozdrav, bežná konverzácia, oznámenie plánu, otázka na počasie, odmietnutie, súhlas s predchádzajúcou ponukou rady alebo nadviazanie na už pomenovaný chýbajúci kus.",
    "Ak asistent v bezprostrednej histórii už pomenoval chýbajúci vhodný kus a používateľ iba potvrdí, že taký kus nemá, je to VŽDY fast_reply. Používateľovo potvrdenie neoveruj znovu proti šatníku, nevyberaj outfit a nevoľ full_stylist.",
    "Pri full_stylist vráť prázdny stylistComment, quickReplyMode=none, weatherContextKey=none, shoppingHandoff=none a prázdne shopping texty. O outfite nerozhoduj.",
    "Pri fast_reply píš prirodzene po slovensky, kamarátsky a profesionálne, zvyčajne 1–2 krátke vety. Nevymýšľaj vlastnosti kúskov ani netvrď, že si prehľadal obchody.",
    "Ak používateľ oznámi, že nemá chýbajúci odporučený kus, neostaň pri opakovaní problému. Ponúkni jeden praktický ďalší krok.",
    shoppingEnabled ?
      "Ak ide o reálne chýbajúci kúpiteľný kus a používateľ ešte nákup neodmietol, nastav shoppingHandoff=ask_permission, stručne vyplň shoppingNeedText (napr. turistické topánky) a shoppingNeedLabel. Ak posledná správa je súhlas s bezprostredne predchádzajúcou ponukou pozrieť možnosti v obchodoch, nastav namiesto toho shoppingHandoff=start_search a z histórie vyplň ten istý chýbajúci kus. Text odpovede môže byť prázdny; server vytvorí pravdivý Shopping krok." :
      "Vyhľadávanie obchodov nie je dostupné. Pri chýbajúcom kuse sa opýtaj, či chce poradiť, aký kus hľadať; nastav quickReplyMode=yes_no. Po Áno rovno daj konkrétne kritériá, po Nie tému ukonči.",
    "quickReplyMode=yes_no použi iba ak posledná veta stylistComment je skutočná otázka zodpovedateľná áno alebo nie. Inak none.",
    "Pri počasí použi iba dodané údaje pre správny deň. Ak poznáš ráno/obed/večer, nepridávaj ešte denný rozsah; stručne spomeň aj dážď a vietor, ak sú známe.",
    "O sebe nepoužívaj rodovo značené minulé tvary.",
  ].join("\n");
  return Object.freeze({
    model: FAST_CONVERSATION_MODEL,
    reasoningEffort: FAST_CONVERSATION_REASONING_EFFORT,
    maxOutputTokens: 700,
    schemaName: "simple_stylist_fast_conversation_v1",
    schema: FAST_CONVERSATION_SCHEMA,
    messages: Object.freeze([
      Object.freeze({role: "system", content: system}),
      Object.freeze({role: "user", content: JSON.stringify({
        wardrobeV2: [],
        latestUserMessage: cleanText(input?.message, 3000),
        recentConversationHistory: normalizeHistory(input?.history),
        hasCurrentOutfit: Array.isArray(input?.currentOutfitItemIds) &&
          input.currentOutfitItemIds.length > 0,
        weatherContext: input?.weatherContext && typeof input.weatherContext === "object" ?
          input.weatherContext : {},
        dateLocationContext: input?.clientContext && typeof input.clientContext === "object" ?
          input.clientContext : {},
        shoppingEnabled,
      })}),
    ]),
  });
}

function hasTerminalYesNoQuestion(text) {
  return /\?\s*(?:[\p{Extended_Pictographic}\uFE0F\u200D\s]*)$/u.test(text);
}

function validateFastConversationDecisionV1(raw) {
  const route = cleanText(raw?.route, 30);
  const stylistComment = cleanText(raw?.stylistComment, 500);
  const quickReplyMode = cleanText(raw?.quickReplyMode, 20);
  const weatherContextKey = cleanText(raw?.weatherContextKey, 20);
  const shoppingHandoff = cleanText(raw?.shoppingHandoff, 30);
  const shoppingNeedText = cleanText(raw?.shoppingNeedText, 160);
  const shoppingNeedLabel = cleanText(raw?.shoppingNeedLabel, 160);
  const errors = [];
  if (!FAST_CONVERSATION_SCHEMA.properties.route.enum.includes(route)) {
    errors.push("fast_route_invalid");
  }
  if (!FAST_CONVERSATION_SCHEMA.properties.quickReplyMode.enum.includes(quickReplyMode)) {
    errors.push("fast_quick_reply_invalid");
  }
  if (!FAST_CONVERSATION_SCHEMA.properties.weatherContextKey.enum
    .includes(weatherContextKey)) {
    errors.push("fast_weather_key_invalid");
  }
  if (!FAST_CONVERSATION_SCHEMA.properties.shoppingHandoff.enum
    .includes(shoppingHandoff)) {
    errors.push("fast_shopping_handoff_invalid");
  }
  if (route === "full_stylist" && (stylistComment || quickReplyMode !== "none" ||
      weatherContextKey !== "none" || shoppingHandoff !== "none" ||
      shoppingNeedText || shoppingNeedLabel)) {
    errors.push("fast_full_route_must_not_answer");
  }
  if (route === "fast_reply" && shoppingHandoff === "none" && !stylistComment) {
    errors.push("fast_reply_comment_required");
  }
  if (quickReplyMode === "yes_no" && !hasTerminalYesNoQuestion(stylistComment)) {
    errors.push("fast_yes_no_question_required");
  }
  if (["ask_permission", "start_search"].includes(shoppingHandoff) &&
      (!shoppingNeedText || !shoppingNeedLabel || quickReplyMode !== "none")) {
    errors.push("fast_shopping_need_invalid");
  }
  return Object.freeze({
    valid: errors.length === 0,
    errors: Object.freeze(errors),
    value: Object.freeze({route, stylistComment, quickReplyMode, weatherContextKey,
      shoppingHandoff, shoppingNeedText, shoppingNeedLabel}),
  });
}

function createFastConversationRouterV1({executeModel, logger = console} = {}) {
  if (typeof executeModel !== "function") {
    throw new Error("fast_conversation_execute_model_required");
  }
  return Object.freeze({
    async resolve(input) {
      const started = Date.now();
      try {
        const raw = await executeModel(buildFastConversationInputV1(input),
          {modelAttempt: 1});
        const validation = validateFastConversationDecisionV1(raw);
        const log = validation.valid ? logger.info : logger.warn;
        if (typeof log === "function") {
          log.call(logger, "SIMPLE_AGENT_FAST_ROUTE", {
            valid: validation.valid,
            route: validation.value.route,
            shoppingHandoff: validation.value.shoppingHandoff,
            latencyMs: Date.now() - started,
            validationErrors: validation.errors,
          });
        }
        return validation.valid ? validation.value : Object.freeze({
          route: "full_stylist", stylistComment: "", quickReplyMode: "none",
          weatherContextKey: "none", shoppingHandoff: "none",
          shoppingNeedText: "", shoppingNeedLabel: "",
        });
      } catch (error) {
        if (typeof logger.warn === "function") {
          logger.warn("SIMPLE_AGENT_FAST_ROUTE_FALLBACK", {
            code: cleanText(error?.code || error?.message || "fast_route_failed", 100),
            latencyMs: Date.now() - started,
          });
        }
        return Object.freeze({
          route: "full_stylist", stylistComment: "", quickReplyMode: "none",
          weatherContextKey: "none", shoppingHandoff: "none",
          shoppingNeedText: "", shoppingNeedLabel: "",
        });
      }
    },
  });
}

module.exports = {
  FAST_CONVERSATION_MODEL,
  FAST_CONVERSATION_REASONING_EFFORT,
  FAST_CONVERSATION_SCHEMA,
  buildFastConversationInputV1,
  validateFastConversationDecisionV1,
  createFastConversationRouterV1,
};
