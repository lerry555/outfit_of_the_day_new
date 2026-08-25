"use strict";

/**
 * Adapt validated Gemini output → existing Flutter analyzeClothingImage JSON shape.
 *
 * Extension seam for future Option C (bodySlot/layerPosition): derivedPlacement
 * is computed internally but NOT written into the client contract yet.
 */

const {
  ANALYZER_VERSION,
} = require("./prompts/clothing_analyzer_gemini_v1");

/**
 * @param {object} validatedValue from validateProductionGeminiOutput
 * @param {{
 *   provider: string,
 *   modelId: string,
 *   promptVersion: string,
 *   promptHash: string,
 *   telemetry?: object,
 * }} meta
 */
function adaptToProductionClientResponse(validatedValue, meta) {
  if (!validatedValue || typeof validatedValue !== "object") {
    throw new Error("adapter_input_required");
  }

  // Future Option C hook — do not emit to Firestore/client contract yet.
  const derivedPlacement = derivePlacementHint(validatedValue);

  const response = {
    type: validatedValue.type || "",
    type_pretty: validatedValue.type_pretty || "",
    canonical_type: validatedValue.canonical_type || "",
    brand: validatedValue.brand || "",
    colors: Array.isArray(validatedValue.colors) ? validatedValue.colors : [],
    styles: Array.isArray(validatedValue.styles) ? validatedValue.styles : [],
    patterns: Array.isArray(validatedValue.patterns) ? validatedValue.patterns : [],
    seasons: Array.isArray(validatedValue.seasons) ? validatedValue.seasons : [],
    debug_reason: validatedValue.debug_reason || "",
    fit: validatedValue.fit || "unknown",
    formality: validatedValue.formality,
    vibe: validatedValue.vibe || "unknown",
    logo_prominence: validatedValue.logo_prominence || "unknown",
    occasion_fit: Array.isArray(validatedValue.occasion_fit) ?
      validatedValue.occasion_fit : [],
    material_feel: validatedValue.material_feel || "unknown",
    visual_description: validatedValue.visual_description || "",
    primary_type: validatedValue.primary_type || "",
    secondary_type: validatedValue.secondary_type || "",
    layer_role: validatedValue.layer_role || "",
    warmth_level: validatedValue.warmth_level,
    confidence: validatedValue.confidence,
    visual_identity: validatedValue.visual_identity || "",
    identity_confidence: validatedValue.identity_confidence || 0,
    // New optional metadata — old clients ignore unknown keys safely.
    analyzerVersion: meta.analyzerVersion || ANALYZER_VERSION,
    analyzerProvider: meta.provider,
    analyzerModel: meta.modelId,
    analyzerPromptVersion: meta.promptVersion,
    analyzerPromptHash: meta.promptHash,
  };

  // Non-contract diagnostic bag for server logs/tests only when requested.
  if (meta.includeInternalDiagnostics) {
    response._internal = {
      identity_slot: validatedValue.identity_slot || null,
      derivedPlacement,
      kb: validatedValue._kb || null,
      validationNotes: meta.validationNotes || [],
      telemetry: meta.telemetry || null,
    };
  }

  return response;
}

function derivePlacementHint(value) {
  const layer = value.layer_role || "";
  const slot = value.identity_slot || null;
  // Structured for future bodySlot + layerPosition without emitting them now.
  let bodySlot = null;
  let layerPosition = null;
  if (layer === "bottom" || slot === "bottoms") bodySlot = "bottom";
  else if (layer === "footwear" || slot === "footwear") bodySlot = "footwear";
  else if (layer === "accessory" || slot === "accessories") bodySlot = "accessory";
  else if (slot === "one_piece") bodySlot = "one_piece";
  else if (slot === "outerwear" || layer === "outer_layer") bodySlot = "top";
  else if (slot === "tops" || layer === "base_layer" || layer === "mid_layer") {
    bodySlot = "top";
  }

  if (layer === "base_layer") layerPosition = "base";
  else if (layer === "mid_layer") layerPosition = "mid";
  else if (layer === "outer_layer") layerPosition = "outer";
  else if (layer === "bottom") layerPosition = "outer"; // production semantics today
  else if (layer === "footwear") layerPosition = null;
  else if (layer === "accessory") layerPosition = null;

  return Object.freeze({bodySlot, layerPosition, legacyLayerRole: layer || null});
}

module.exports = {
  adaptToProductionClientResponse,
  derivePlacementHint,
};
