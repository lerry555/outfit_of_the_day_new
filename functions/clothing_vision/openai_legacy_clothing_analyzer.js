"use strict";

/**
 * Emergency / kill-switch OpenAI gpt-4o-mini clothing analyzer.
 * Explicit provider routing only — never auto-invoked after Gemini failure.
 */

const {
  ALLOWED_SEASONS,
  ALLOWED_PATTERNS,
  ALLOWED_STYLES,
  ALLOWED_COLORS,
  ALLOWED_FIT,
  ALLOWED_VIBE,
  ALLOWED_LOGO_PROMINENCE,
  ALLOWED_OCCASION_FIT,
  COLOR_MAP,
  PATTERN_MAP,
  SEASON_MAP,
  LAYER_ROLE_MAP,
} = require("./production_allowlists");

const OPENAI_LEGACY_MODEL = "gpt-4o-mini";
const OPENAI_LEGACY_ANALYZER_VERSION = "clothing-vision-openai-legacy-v1";
const OPENAI_LEGACY_PROMPT_VERSION = "analyzeClothingImage_openai_legacy_inline_v1";

// Production CF historically allowed only upper-stack roles from the model.
const OPENAI_ALLOWED_LAYER_ROLE = ["base_layer", "mid_layer", "outer_layer"];

function toStringArray(value) {
  if (Array.isArray(value)) {
    return value.map((v) => String(v ?? "").trim()).filter(Boolean);
  }
  if (value == null || value === "") return [];
  return [String(value).trim()].filter(Boolean);
}

function normalizeToAllowed(raw, allowed, map) {
  const s = String(raw || "").trim();
  if (!s) return null;
  if (allowed.includes(s)) return s;
  const lower = s.toLowerCase();
  for (const a of allowed) {
    if (a.toLowerCase() === lower) return a;
  }
  if (map && map[lower]) return map[lower];
  return null;
}

function normalizeScalar(raw, allowed, map, fallback) {
  return normalizeToAllowed(raw, allowed, map) || fallback;
}

function normalizeFormality(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 5;
  return Math.max(1, Math.min(10, Math.round(n)));
}

function normalizeWarmthLevel(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 5;
  return Math.max(1, Math.min(10, Math.round(n)));
}

function normalizeConfidence(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 0;
  return Math.max(0, Math.min(100, Math.round(n)));
}

function stripCodeFences(text) {
  let raw = String(text || "").trim();
  if (raw.startsWith("```")) {
    const firstNl = raw.indexOf("\n");
    if (firstNl !== -1) raw = raw.substring(firstNl + 1);
  }
  if (raw.endsWith("```")) {
    raw = raw.substring(0, raw.lastIndexOf("```")).trim();
  }
  return raw.trim();
}

function buildOpenAiLegacySystemPrompt() {
  return `
Si profesionálny módny stylista a expert na rozpoznávanie oblečenia z fotiek pre mobilnú aplikáciu.
Vráť STRICTNE jeden JSON objekt. Nepíš žiadny iný text. Žiadny markdown.

MUSÍŠ vrátiť VŽDY všetky tieto kľúče:
{
  "type": "krátky názov v slovenčine",
  "type_pretty": "detailnejší názov v slovenčine",
  "canonical_type": "technický kľúč v angličtine",
  "brand": "značka alebo prázdny string",
  "colors": ["zoznam farieb"],
  "styles": ["zoznam štýlov"],
  "patterns": ["max 1 vzor"],
  "seasons": ["zoznam sezón"],
  "debug_reason": "stručný dôvod",
  "fit": "jedna z povolených hodnôt fit",
  "formality": "číslo 1–10",
  "vibe": "jedna z povolených hodnôt vibe",
  "logo_prominence": "jedna z povolených hodnôt",
  "occasion_fit": ["zoznam príležitostí"],
  "material_feel": "krátka fráza",
  "visual_description": "jedna krátka praktická veta",
  "primary_type": "najlepší odhad",
  "secondary_type": "alternatíva alebo prázdny string",
  "layer_role": "base_layer|mid_layer|outer_layer",
  "warmth_level": "číslo 1–10",
  "confidence": "číslo 0–100",
  "visual_identity": "identita alebo prázdny string",
  "identity_confidence": "číslo 0–100"
}

FARBY: ${JSON.stringify(ALLOWED_COLORS)}
ŠTÝLY: ${JSON.stringify(ALLOWED_STYLES)}
VZORY: ${JSON.stringify(ALLOWED_PATTERNS)}
SEZÓNY: ${JSON.stringify(ALLOWED_SEASONS)}
FIT: ${JSON.stringify(ALLOWED_FIT)}
VIBE: ${JSON.stringify(ALLOWED_VIBE)}
LOGO: ${JSON.stringify(ALLOWED_LOGO_PROMINENCE)}
OCCASION: ${JSON.stringify(ALLOWED_OCCASION_FIT)}
LAYER: ${JSON.stringify(OPENAI_ALLOWED_LAYER_ROLE)}
`.trim();
}

function normalizeOpenAiLegacyParsed(parsed) {
  const p = parsed && typeof parsed === "object" ? parsed : {};
  const colors = [];
  for (const c of toStringArray(p.colors)) {
    const mapped = normalizeToAllowed(c, ALLOWED_COLORS, COLOR_MAP);
    if (mapped && !colors.includes(mapped)) colors.push(mapped);
  }
  const styles = [];
  for (const s of toStringArray(p.styles)) {
    const mapped = normalizeToAllowed(s, ALLOWED_STYLES, null);
    if (mapped && !styles.includes(mapped)) styles.push(mapped);
  }
  let patterns = [];
  for (const pat of toStringArray(p.patterns)) {
    const mapped = normalizeToAllowed(pat, ALLOWED_PATTERNS, PATTERN_MAP);
    if (mapped) {
      patterns = [mapped];
      break;
    }
  }
  let seasons = [];
  for (const sea of toStringArray(p.seasons)) {
    const mapped = normalizeToAllowed(sea, ALLOWED_SEASONS, SEASON_MAP);
    if (mapped && !seasons.includes(mapped)) seasons.push(mapped);
  }
  const hasAllFour = ["jar", "leto", "jeseň", "zima"].every((x) => seasons.includes(x));
  if (seasons.includes("celoročne") || hasAllFour) seasons = ["celoročne"];

  const fit = normalizeScalar(p.fit, ALLOWED_FIT, null, "unknown");
  const formality = normalizeFormality(p.formality);
  const vibe = normalizeScalar(p.vibe, ALLOWED_VIBE, null, "unknown");
  const logo_prominence = normalizeScalar(
    p.logo_prominence, ALLOWED_LOGO_PROMINENCE, null, "unknown",
  );
  const occasion_fit = toStringArray(p.occasion_fit)
    .map((v) => normalizeToAllowed(v, ALLOWED_OCCASION_FIT, null))
    .filter(Boolean);
  const material_feel = String(p.material_feel || "").trim() || "unknown";
  const visual_description = String(p.visual_description || "").trim();
  const typeFallback = String(p.type || p.type_pretty || "");
  let primary_type = String(p.primary_type || "").trim() || typeFallback;
  let secondary_type = String(p.secondary_type || "").trim();
  const mappedLayer = LAYER_ROLE_MAP[String(p.layer_role || "").toLowerCase()] ||
    p.layer_role;
  const layer_role =
    normalizeScalar(mappedLayer, OPENAI_ALLOWED_LAYER_ROLE, null, "") || "";
  const warmth_level = normalizeWarmthLevel(p.warmth_level);
  const confidence = normalizeConfidence(p.confidence);
  if (secondary_type && secondary_type.toLowerCase() === primary_type.toLowerCase()) {
    secondary_type = "";
  }
  let identity_confidence = normalizeConfidence(p.identity_confidence);
  let visual_identity = String(p.visual_identity || "").trim();
  if (identity_confidence < 80) visual_identity = "";

  if (!patterns.length) {
    const visualBlob = [visual_description, visual_identity, p.brand].join(" ").toLowerCase();
    const logoSuggestsGraphic =
      logo_prominence === "medium" || logo_prominence === "large";
    const textSuggestsGraphic =
      /\b(logo|potla|grafik|print|brand)\b/.test(visualBlob) ||
      (identity_confidence >= 80 && visual_identity.length > 0);
    patterns = (logoSuggestsGraphic || textSuggestsGraphic) ?
      ["grafické"] : ["jednofarebné"];
  }

  return {
    type: String(p.type || p.type_pretty || ""),
    type_pretty: String(p.type_pretty || p.type || ""),
    canonical_type: String(p.canonical_type || ""),
    brand: String(p.brand || ""),
    colors,
    styles,
    patterns,
    seasons,
    debug_reason: String(p.debug_reason || ""),
    fit,
    formality,
    vibe,
    logo_prominence,
    occasion_fit,
    material_feel,
    visual_description,
    primary_type,
    secondary_type,
    layer_role,
    warmth_level,
    confidence,
    visual_identity,
    identity_confidence,
    analyzerVersion: OPENAI_LEGACY_ANALYZER_VERSION,
    analyzerProvider: "OPENAI_LEGACY",
    analyzerModel: OPENAI_LEGACY_MODEL,
    analyzerPromptVersion: OPENAI_LEGACY_PROMPT_VERSION,
  };
}

/**
 * @param {{
 *   imageDataUrl: string,
 *   getApiKey: () => string,
 *   fetchImpl?: Function,
 * }} args
 */
async function runOpenAiLegacyClothingAnalysis(args) {
  const fetchImpl = args.fetchImpl || fetch;
  const apiKey = args.getApiKey && args.getApiKey();
  if (!apiKey) {
    const err = new Error("openai_api_key_missing");
    err.code = "openai_api_key_missing";
    throw err;
  }
  const started = Date.now();
  const openAiBody = {
    model: OPENAI_LEGACY_MODEL,
    temperature: 0.1,
    messages: [
      {role: "system", content: buildOpenAiLegacySystemPrompt()},
      {
        role: "user",
        content: [
          {
            type: "text",
            text: "Analyzuj tento jeden kus oblečenia na fotke a vráť JSON podľa inštrukcií.",
          },
          {type: "image_url", image_url: {url: args.imageDataUrl}},
        ],
      },
    ],
  };
  const response = await fetchImpl("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(openAiBody),
  });
  if (!response.ok) {
    const err = new Error(`openai_upstream_${response.status}`);
    err.code = `openai_upstream_${response.status}`;
    err.httpStatus = response.status;
    throw err;
  }
  const data = await response.json();
  const text = data?.choices?.[0]?.message?.content;
  if (!text) {
    const err = new Error("openai_empty_content");
    err.code = "openai_empty_content";
    throw err;
  }
  let parsed = null;
  try {
    parsed = JSON.parse(stripCodeFences(text));
  } catch (_) {
    parsed = {};
  }
  const normalized = normalizeOpenAiLegacyParsed(parsed);
  const usage = data.usage || null;
  return {
    response: normalized,
    telemetry: {
      provider: "OPENAI_LEGACY",
      model: OPENAI_LEGACY_MODEL,
      analyzerVersion: OPENAI_LEGACY_ANALYZER_VERSION,
      promptVersion: OPENAI_LEGACY_PROMPT_VERSION,
      promptHash: null,
      inputTokens: usage && usage.prompt_tokens,
      outputTokens: usage && usage.completion_tokens,
      estimatedCostUsd: null,
      latencyMs: Date.now() - started,
      retryCount: 0,
      parserStatus: parsed && Object.keys(parsed).length ? "ok" : "empty_parse",
      success: true,
      truncationRecovered: false,
    },
  };
}

module.exports = {
  OPENAI_LEGACY_MODEL,
  OPENAI_LEGACY_ANALYZER_VERSION,
  OPENAI_LEGACY_PROMPT_VERSION,
  normalizeOpenAiLegacyParsed,
  runOpenAiLegacyClothingAnalysis,
  stripCodeFences,
  buildOpenAiLegacySystemPrompt,
};
