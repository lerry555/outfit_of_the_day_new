"use strict";

/**
 * Gemini responseJsonSchema for production clothing analysis.
 * Production contract fields — not the blind benchmark wire schema.
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
} = require("./production_allowlists");

const REQUIRED_PROPERTIES = Object.freeze([
  "canonical_type",
  "type",
  "type_pretty",
  "primary_type",
  "secondary_type",
  "brand",
  "colors",
  "styles",
  "patterns",
  "seasons",
  "fit",
  "formality",
  "vibe",
  "logo_prominence",
  "occasion_fit",
  "material_feel",
  "visual_description",
  "layer_role",
  "warmth_level",
  "confidence",
  "visual_identity",
  "identity_confidence",
  "debug_reason",
  "identity_slot",
]);

function buildProductionGeminiResponseSchema() {
  return {
    type: "object",
    additionalProperties: false,
    required: [...REQUIRED_PROPERTIES],
    properties: {
      canonical_type: {type: ["string", "null"]},
      type: {type: "string"},
      type_pretty: {type: "string"},
      primary_type: {type: "string"},
      secondary_type: {type: "string"},
      brand: {type: "string"},
      colors: {
        type: "array",
        items: {type: "string", enum: [...ALLOWED_COLORS]},
      },
      styles: {
        type: "array",
        items: {type: "string", enum: [...ALLOWED_STYLES]},
      },
      patterns: {
        type: "array",
        items: {type: "string", enum: [...ALLOWED_PATTERNS]},
      },
      seasons: {
        type: "array",
        items: {type: "string", enum: [...ALLOWED_SEASONS]},
      },
      fit: {type: "string", enum: [...ALLOWED_FIT]},
      formality: {type: "integer", minimum: 1, maximum: 10},
      vibe: {type: "string", enum: [...ALLOWED_VIBE]},
      logo_prominence: {type: "string", enum: [...ALLOWED_LOGO_PROMINENCE]},
      occasion_fit: {
        type: "array",
        items: {type: "string", enum: [...ALLOWED_OCCASION_FIT]},
      },
      material_feel: {type: "string"},
      visual_description: {type: "string"},
      layer_role: {type: "string", enum: [...ALLOWED_LAYER_ROLE]},
      warmth_level: {type: "integer", minimum: 1, maximum: 10},
      confidence: {type: "integer", minimum: 0, maximum: 100},
      visual_identity: {type: "string"},
      identity_confidence: {type: "integer", minimum: 0, maximum: 100},
      debug_reason: {type: "string"},
      identity_slot: {
        type: ["string", "null"],
        enum: [...ALLOWED_IDENTITY_SLOT, null],
      },
    },
  };
}

module.exports = {
  REQUIRED_PROPERTIES,
  buildProductionGeminiResponseSchema,
};
