"use strict";

const crypto = require("node:crypto");

/**
 * Validate + sanitize Gemini production analyzer output before adapter.
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
  ALLOWED_LAYER_ROLE,
  ALLOWED_IDENTITY_SLOT,
  COLOR_MAP,
  PATTERN_MAP,
  SEASON_MAP,
  LAYER_ROLE_MAP,
} = require("./production_allowlists");
const {REQUIRED_PROPERTIES} = require("./production_schema");
const {createKbIndex, normalizeKey} = require("./kb_index");

const EXACT_FIBER_RE =
  /\b(\d+\s*%|100%\s*cotton|egyptian cotton|polyester|elastane|spandex|viscose|acrylic|nylon\s*fiber|merino\s*wool|\bwool\b|\bcotton\b|\bsilk\b)\b/i;

function boundedEnumTelemetryValue(value) {
  return String(value == null ? "" : value)
    .trim()
    .replace(/[\u0000-\u001f\u007f]/g, "")
    .slice(0, 64);
}

function hashTelemetryValue(value) {
  return crypto.createHash("sha256")
    .update(String(value == null ? "" : value).trim(), "utf8")
    .digest("hex");
}

function enumAction(field, before, after, reason) {
  return Object.freeze({
    field,
    before: boundedEnumTelemetryValue(before),
    after: boundedEnumTelemetryValue(after),
    reason,
  });
}

function freeTextAction(field, before, after, reason) {
  return Object.freeze({
    field,
    beforeHash: hashTelemetryValue(before),
    afterHash: hashTelemetryValue(after),
    reason,
  });
}

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

function clampInt(value, min, max, fallback) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, Math.round(n)));
}

function lengthEvidenceSupports(type, visualDescription) {
  const v = String(visualDescription || "").toLowerCase();
  const t = normalizeKey(type);
  if (t === "midi_skirt") {
    return /midi|mid[-\s]?length|knee|po kolena|stredn/.test(v);
  }
  if (t === "maxi_skirt") {
    return /maxi|ankle|floor|full[-\s]?length|dlh/.test(v);
  }
  if (t === "mini_skirt") {
    return /mini|short skirt|krátk/.test(v);
  }
  if (t === "summer_dress") {
    return /summer|leto|sundress|ľahk|light dress/.test(v);
  }
  if (t === "cocktail_dress") {
    return /cocktail|party dress|evening short|spoločensk/.test(v);
  }
  if (t === "evening_dress") {
    return /evening|gala|formal dress|večern/.test(v);
  }
  return true;
}

function sanitizeMaterialFeel(raw) {
  let text = String(raw || "").trim();
  if (!text) return "unknown";
  if (EXACT_FIBER_RE.test(text)) {
    // Strip fiber chemistry claims; keep observable tokens when possible.
    text = text
      .replace(EXACT_FIBER_RE, " ")
      .replace(/\s+/g, " ")
      .trim();
    if (!text || text.length < 2) return "unknown";
    return text;
  }
  return text;
}

function sanitizeBrand(brand, logoProminence, visualDescription, visualIdentity) {
  const b = String(brand || "").trim();
  if (!b) return "";
  const logo = String(logoProminence || "");
  const blob = `${visualDescription || ""} ${visualIdentity || ""}`.toLowerCase();
  const brandLower = b.toLowerCase();
  const visible =
    logo === "small" || logo === "medium" || logo === "large" ||
    blob.includes(brandLower) ||
    /\b(logo|brand|text|crest|erb)\b/.test(blob);
  if (!visible) return "";
  return b;
}

/**
 * @param {object} parsed
 * @param {{ kbIndex?: object }} [options]
 */
function validateProductionGeminiOutput(parsed, options = {}) {
  const notes = [];
  const sanitizationActions = [];
  const kb = options.kbIndex || createKbIndex(options);
  if (parsed == null || typeof parsed !== "object" || Array.isArray(parsed)) {
    return {
      ok: false,
      parserStatus: "invalid_object",
      errors: ["output_not_object"],
      value: null,
      notes,
    };
  }

  const missing = REQUIRED_PROPERTIES.filter((k) => !(k in parsed));
  if (missing.length) {
    return {
      ok: false,
      parserStatus: "missing_required_fields",
      errors: missing.map((k) => `missing:${k}`),
      value: null,
      notes,
    };
  }

  const canonicalInput = parsed.canonical_type == null ? "" : String(parsed.canonical_type).trim();
  let canonicalRaw = canonicalInput;
  let kbItem = canonicalRaw ? kb.resolveType(canonicalRaw) : null;
  if (!kbItem && canonicalRaw) {
    const parentItem = kb.parentOf(canonicalRaw);
    if (parentItem) {
      notes.push(`safe_parent_collapse:${canonicalRaw}->${parentItem.canonicalType}`);
      sanitizationActions.push(enumAction(
        "canonical_type",
        canonicalInput,
        parentItem.canonicalType,
        "safe_parent_collapse",
      ));
      canonicalRaw = parentItem.canonicalType;
      kbItem = parentItem;
    }
  }
  if (kbItem && kb.isLengthSpecific(kbItem.canonicalType) &&
      !lengthEvidenceSupports(kbItem.canonicalType, parsed.visual_description)) {
    const parentItem = kb.parentOf(kbItem.canonicalType);
    if (parentItem) {
      notes.push(
        `canonical_collapsed_unsupported_specificity:${kbItem.canonicalType}->${parentItem.canonicalType}`,
      );
      sanitizationActions.push(enumAction(
        "canonical_type",
        canonicalInput,
        parentItem.canonicalType,
        "canonical_collapsed_unsupported_specificity",
      ));
      kbItem = parentItem;
      canonicalRaw = parentItem.canonicalType;
    }
  }
  // Never upgrade parent→child here (validator only accepts/collapses).
  if (!kbItem) {
    notes.push("canonical_unresolved");
    canonicalRaw = "";
    sanitizationActions.push(enumAction(
      "canonical_type",
      canonicalInput,
      canonicalRaw,
      "canonical_unresolved",
    ));
  } else {
    canonicalRaw = kbItem.canonicalType;
    if (canonicalRaw !== canonicalInput &&
        !sanitizationActions.some((action) => action.field === "canonical_type")) {
      sanitizationActions.push(enumAction(
        "canonical_type",
        canonicalInput,
        canonicalRaw,
        "alias_normalized",
      ));
    }
  }

  const colors = [];
  for (const c of toStringArray(parsed.colors)) {
    const mapped = normalizeToAllowed(c, ALLOWED_COLORS, COLOR_MAP);
    if (mapped && !colors.includes(mapped)) colors.push(mapped);
  }
  const styles = [];
  for (const s of toStringArray(parsed.styles)) {
    const mapped = normalizeToAllowed(s, ALLOWED_STYLES, null);
    if (mapped && !styles.includes(mapped)) styles.push(mapped);
  }
  let patterns = [];
  for (const p of toStringArray(parsed.patterns)) {
    const mapped = normalizeToAllowed(p, ALLOWED_PATTERNS, PATTERN_MAP);
    if (mapped) {
      patterns = [mapped];
      break;
    }
  }
  if (!patterns.length) patterns = ["jednofarebné"];

  let seasons = [];
  for (const sea of toStringArray(parsed.seasons)) {
    const mapped = normalizeToAllowed(sea, ALLOWED_SEASONS, SEASON_MAP);
    if (mapped && !seasons.includes(mapped)) seasons.push(mapped);
  }
  const hasAllFour = ["jar", "leto", "jeseň", "zima"].every((x) => seasons.includes(x));
  if (seasons.includes("celoročne") || hasAllFour) seasons = ["celoročne"];

  let layerRole = normalizeToAllowed(
    LAYER_ROLE_MAP[String(parsed.layer_role || "").toLowerCase()] || parsed.layer_role,
    ALLOWED_LAYER_ROLE,
    LAYER_ROLE_MAP,
  ) || "";

  // KB dominates impossible AI layer assignments.
  if (kbItem) {
    const kbLayer = kbItem.layerRole;
    if (kbLayer === "bottom" || kbLayer === "footwear" || kbLayer === "accessory") {
      if (layerRole !== kbLayer) {
        notes.push(`layer_overridden_by_kb:${layerRole || "empty"}->${kbLayer}`);
        sanitizationActions.push(enumAction(
          "layer_role", layerRole, kbLayer, "layer_overridden_by_kb",
        ));
      }
      layerRole = kbLayer;
    } else if (!layerRole) {
      sanitizationActions.push(enumAction(
        "layer_role", layerRole, kbLayer, "layer_defaulted_from_kb",
      ));
      layerRole = kbLayer;
    } else if (
      (kbLayer === "outer_layer" && layerRole === "base_layer") ||
      (kbLayer === "base_layer" && layerRole === "outer_layer" &&
        !/jacket|coat|parka|puffer|blazer|windbreaker|softshell/i.test(canonicalRaw))
    ) {
      notes.push(`layer_corrected_toward_kb:${layerRole}->${kbLayer}`);
      sanitizationActions.push(enumAction(
        "layer_role", layerRole, kbLayer, "layer_corrected_toward_kb",
      ));
      layerRole = kbLayer;
    }
  }

  let identitySlot = parsed.identity_slot == null ? null : String(parsed.identity_slot);
  if (identitySlot && !ALLOWED_IDENTITY_SLOT.includes(identitySlot)) {
    notes.push(`identity_slot_invalid:${identitySlot}`);
    identitySlot = null;
  }
  if (kbItem) {
    if (kb.isOnePiece(kbItem.canonicalType)) {
      if (identitySlot && identitySlot !== "one_piece") {
        notes.push(`identity_slot_forced_one_piece:${identitySlot}`);
      }
      identitySlot = "one_piece";
    } else if (kbItem.layerRole === "bottom") {
      if (identitySlot && identitySlot !== "bottoms" && identitySlot !== "one_piece") {
        notes.push(`identity_slot_forced_bottoms:${identitySlot}`);
      }
      identitySlot = "bottoms";
    } else if (kbItem.layerRole === "footwear") {
      identitySlot = "footwear";
    } else if (kbItem.mainCategory === "doplnky") {
      identitySlot = "accessories";
    } else if (kbItem.layerRole === "outer_layer") {
      if (identitySlot === "tops" || identitySlot === "bottoms") {
        notes.push(`identity_slot_forced_outerwear:${identitySlot}`);
        identitySlot = "outerwear";
      }
    }
  }

  const materialFeel = sanitizeMaterialFeel(parsed.material_feel);
  if (materialFeel !== String(parsed.material_feel || "").trim()) {
    notes.push("material_exact_fiber_sanitized");
    sanitizationActions.push(freeTextAction(
      "material_feel",
      parsed.material_feel,
      materialFeel,
      "material_exact_fiber_sanitized",
    ));
  }

  const logo = normalizeToAllowed(parsed.logo_prominence, ALLOWED_LOGO_PROMINENCE, null) || "unknown";
  const brand = sanitizeBrand(
    parsed.brand,
    logo,
    parsed.visual_description,
    parsed.visual_identity,
  );
  if (String(parsed.brand || "").trim() && !brand) {
    notes.push("brand_guess_rejected");
    sanitizationActions.push(freeTextAction(
      "brand", parsed.brand, brand, "brand_guess_rejected",
    ));
  }

  let identityConfidence = clampInt(parsed.identity_confidence, 0, 100, 0);
  let visualIdentity = String(parsed.visual_identity || "").trim();
  if (identityConfidence < 80) visualIdentity = "";

  const value = {
    canonical_type: canonicalRaw,
    type: String(parsed.type || "").trim(),
    type_pretty: String(parsed.type_pretty || "").trim(),
    primary_type: String(parsed.primary_type || "").trim(),
    secondary_type: String(parsed.secondary_type || "").trim(),
    brand,
    colors,
    styles,
    patterns,
    seasons,
    fit: normalizeToAllowed(parsed.fit, ALLOWED_FIT, null) || "unknown",
    formality: clampInt(parsed.formality, 1, 10, 5),
    vibe: normalizeToAllowed(parsed.vibe, ALLOWED_VIBE, null) || "unknown",
    logo_prominence: logo,
    occasion_fit: toStringArray(parsed.occasion_fit)
      .map((v) => normalizeToAllowed(v, ALLOWED_OCCASION_FIT, null))
      .filter(Boolean),
    material_feel: materialFeel,
    visual_description: String(parsed.visual_description || "").trim(),
    layer_role: layerRole,
    warmth_level: clampInt(parsed.warmth_level, 1, 10, kbItem ? kbItem.warmthDefault : 5),
    confidence: clampInt(parsed.confidence, 0, 100, 0),
    visual_identity: visualIdentity,
    identity_confidence: identityConfidence,
    debug_reason: String(parsed.debug_reason || "").trim(),
    identity_slot: identitySlot,
    _kb: kbItem ? {
      canonicalType: kbItem.canonicalType,
      category: kbItem.category,
      subcategory: kbItem.subcategory,
      mainCategory: kbItem.mainCategory,
      layerRole: kbItem.layerRole,
    } : null,
  };

  if (!value.type && value.type_pretty) value.type = value.type_pretty;
  if (!value.type_pretty && value.type) value.type_pretty = value.type;
  if (!value.primary_type) value.primary_type = value.type_pretty || value.type || "";

  return {
    ok: true,
    parserStatus: "ok",
    errors: [],
    value,
    notes,
    sanitizationActions,
  };
}

module.exports = {
  EXACT_FIBER_RE,
  validateProductionGeminiOutput,
  sanitizeMaterialFeel,
  sanitizeBrand,
  lengthEvidenceSupports,
  boundedEnumTelemetryValue,
  createKbIndex,
};
