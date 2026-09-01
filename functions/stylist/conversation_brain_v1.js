"use strict";

const {getStylistRoleModelConfig} = require("./ai_model_registry");
const {
  CONVERSATION_BRAIN_PERSONA_SK,
  CONVERSATION_BRAIN_VERSION,
} = require("./conversation_brain_persona_v1");

const EXPLANATION_SCHEMA = Object.freeze({
  type: "object",
  additionalProperties: false,
  required: ["explanation", "warnings"],
  properties: {
    explanation: {type: "string"},
    warnings: {type: "array", items: {type: "string"}},
  },
});

function text(value, max = 1600) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function safeJson(value) {
  try {
    return JSON.stringify(value);
  } catch (_) {
    return "{}";
  }
}

function parseJsonText(value) {
  if (value && typeof value === "object" && !Array.isArray(value)) return value;
  if (typeof value !== "string") return null;
  try {
    const parsed = JSON.parse(value);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : null;
  } catch (_) {
    return null;
  }
}

function openAiContent(json) {
  return json && json.choices && json.choices[0] &&
    json.choices[0].message && json.choices[0].message.content;
}

function failure(code) {
  return Object.freeze({ok: false, failureCode: code});
}

function mapProviderFailure(response) {
  const status = Number(response && response.status);
  if (status === 401) return failure("authentication_unavailable");
  if (status === 403) return failure("access_denied");
  if (status === 404) return failure("model_unavailable");
  if (status === 429) return failure("rate_limited");
  if (status >= 500 && status <= 599) return failure("provider_unavailable");
  return failure("transport_error");
}

function explanationSystemPrompt() {
  return [
    CONVERSATION_BRAIN_PERSONA_SK,
    "",
    "TERAZ DOSTÁVAŠ UŽ UZAVRETÝ VÝSLEDOK OUTFIT ENGINE:",
    "- Tvojou úlohou je pokračovať v rovnakom hlasovom štýle a používateľovi tento výsledok prirodzene podať.",
    "- effectiveAction, userFacingSelectedOutfit a userFacingCompromises sú nemenné. Nesmieš outfit zmeniť, doplniť, nahradiť ani potajomky odporučiť iný vlastnený kúsok.",
    "- Pri select_candidate pomenuj iba kúsky z userFacingSelectedOutfit. Vysvetli konkrétne, prečo kombinácia funguje pre situáciu, počasie alebo dress code.",
    "- presentationMode riadi ROZSAH odpovede, nikdy samotný výber kúskov.",
    "- focused_item: JEDNA krátka prirodzená veta. Povedz iba ktorý kúsok odporúčaš k už existujúcemu outfitu. Neopakuj teplotu, dážď, mesto ani opis ostatných kúskov, pokiaľ sa na ne user výslovne nepýta. NIKDY nepíš technické formulácie typu „vymenil som spodok/slot“.",
    "- concise_full: používateľ už outfit videl alebo si ho práve nechal upraviť. Max 1–2 krátke vety. Potvrď iba požadovanú zmenu a neprepisuj znovu počasie ani katalógový opis každého kúsku.",
    "- normal: pri prvom odporúčaní max 2–3 stručné vety. Nevysvetľuj osobitne každý kus; povedz len to, čo je pre rozhodnutie užitočné.",
    "- userFacingContext.userIntentContext obsahuje iba userove vlastné slová k použitiu outfitu. Aktivitu typu prechádzka, stretnutie, večera a pod. smieš pomenovať len ak je v tomto kontexte explicitne podložená. Samotné „idem do mesta“ NIE JE prechádzka ani stretnutie.",
    "- Toto je TVOJE odporúčanie stylistu. Nikdy nepíš používateľovi „si zvolil“, „vybral si“ ani inú formuláciu, ktorá mu pripisuje tvoju voľbu, pokiaľ payload výslovne nehovorí, že ju zvolil používateľ. Použi „odporúčam ti“, „vybral som ti“ alebo „zvolil som“.",
    "- Počasie nie je povinná fráza. V normal režime ho spomeň najviac raz a iba keď reálne vysvetľuje voľbu. Vo focused_item a concise_full ho NEOPAKUJ, ak sa user nepýta na počasie alebo sa podmienky práve nezmenili. Ak teplotu uvedieš, musí byť presne z userFacingContext.weather.",
    "- Neprotireč vlastnému uzavretému výberu: ak payload neoznačuje vybraný outfit/kus ako kompromis, netvrď, že nevybraná alternatíva by bola lepšia alebo príjemnejšia. Ak kompromis existuje, smieš ho pomenovať iba podľa userFacingCompromises.",
    "- Nikdy nepíš, že konkrétne kúsky alebo hotový outfit nevidíš: userFacingSelectedOutfit je presne uzavretý outfit, ktorý sa zobrazuje používateľovi.",
    "- Ak userFacingCompromises nie je prázdne, povedz pravdu: ide o najlepšiu dostupnú vlastnenú možnosť, ale nie ideál. Stručne pomenuj slabinu a idealReplacementDescription, ak je dodaná.",
    "- Keď kompromis prirodzene vedie k nákupu, môžeš ponúknuť, že nájdeš vhodnejšiu náhradu. Nevymýšľaj však konkrétny produkt, cenu, obchod ani dostupnosť, kým ich nedodá shopping systém.",
    "- Pri reject_all krátko a ľudsky povedz, že z dostupných možností teraz nechceš predstierať vhodný outfit. Nevymýšľaj, čo používateľ vlastní.",
    "- Nezačínaj novým pozdravom. Je to pokračovanie existujúceho chatu.",
    "- Nepoužívaj interné výrazy ako candidate, frozen, validator, deterministický, hard constraint, reason code, pipeline, model, provider, score alebo confidence.",
    "- Dĺžku riaď presentationMode; prirodzenosť a presnosť sú dôležitejšie než pevný počet viet.",
    "- Vráť iba strict JSON podľa schémy.",
  ].join("\n");
}

function buildConversationBrainExplanationBodyV1(canonicalPayload) {
  const model = getStylistRoleModelConfig("conversationBrain");
  if (!model || model.provider !== "openai") {
    throw new Error("conversation_brain_model_unavailable");
  }
  const presentationMode = text(canonicalPayload && canonicalPayload.presentationMode, 40);
  const tokenBudget = presentationMode === "focused_item" ? 120 :
    presentationMode === "concise_full" ? 220 : 420;
  return Object.freeze({
    model: model.id,
    max_tokens: Math.min(Number(model.maxTokens) || tokenBudget, tokenBudget),
    temperature: Number.isFinite(model.temperature) ? model.temperature : 0.65,
    response_format: {
      type: "json_schema",
      json_schema: {
        name: "ootd_conversation_brain_explanation_v1",
        strict: true,
        schema: EXPLANATION_SCHEMA,
      },
    },
    messages: [
      {role: "system", content: explanationSystemPrompt()},
      {role: "user", content: safeJson(canonicalPayload)},
    ],
  });
}

function validateExplanation(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const keys = Object.keys(value);
  if (keys.some((key) => !["explanation", "warnings"].includes(key))) return null;
  const explanation = text(value.explanation, 1200);
  if (!explanation) return null;
  const warnings = Array.isArray(value.warnings) ?
    value.warnings.map((item) => text(item, 120)).filter(Boolean).slice(0, 8) : null;
  if (warnings == null) return null;
  return Object.freeze({explanation, warnings: Object.freeze(warnings)});
}

function createConversationBrainExplanationTransportV1({credentialProvider, execute}) {
  if (typeof credentialProvider !== "function" || typeof execute !== "function") {
    throw new Error("conversation_brain_dependencies_missing");
  }
  const model = getStylistRoleModelConfig("conversationBrain");
  return Object.freeze({
    provider: "openai",
    role: "conversationBrainExplanation",
    modelId: model && model.id,
    async run(canonicalPayload) {
      let credential = "";
      try {
        credential = text(await credentialProvider(), 4096);
      } catch (_) {}
      if (!credential) return failure("authentication_unavailable");

      let response;
      try {
        response = await execute(Object.freeze({
          method: "POST",
          url: "https://api.openai.com/v1/chat/completions",
          timeoutMs: 30000,
          headers: {Authorization: `Bearer ${credential}`},
          body: buildConversationBrainExplanationBodyV1(canonicalPayload),
        }));
      } catch (error) {
        if (String(error && error.name || "").toLowerCase() === "aborterror") {
          return failure("timeout");
        }
        return failure("transport_error");
      }
      if (!response || response.ok === false || Number(response.status) >= 400) {
        return mapProviderFailure(response);
      }
      const parsed = parseJsonText(openAiContent(response.json));
      const value = validateExplanation(parsed);
      if (!value) return failure("structured_output_invalid");
      return Object.freeze({
        ok: true,
        value,
        actualModel: text(response && response.json && response.json.model, 80) || null,
      });
    },
  });
}

module.exports = {
  CONVERSATION_BRAIN_VERSION,
  EXPLANATION_SCHEMA,
  explanationSystemPrompt,
  buildConversationBrainExplanationBodyV1,
  createConversationBrainExplanationTransportV1,
};
