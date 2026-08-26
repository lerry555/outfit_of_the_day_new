"use strict";

const {artifact} = require("../wardrobe_ontology_v2");

const FIELD_CONFIDENCE_KEYS = [
  "canonicalType", "primaryColor", "pattern", "materialAppearance", "fit",
  "formality", "warmth", "metalTone", "hardwareTone",
];

function buildGeminiWardrobeAnalyzerV2Schema() {
  const stringArray = {type: "array", items: {type: "string"}};
  const color = {
    type: "object",
    properties: {
      family: {type: "string"},
      hex: {type: "string"},
      proportion: {type: "number"},
    },
    required: ["family", "hex", "proportion"],
  };
  return {
    type: "object",
    properties: {
      contractVersion: {type: "string", enum: ["wardrobe-analyzer-v2"]},
      canonicalType: {type: "string"},
      candidateTypes: {
        type: "array",
        items: {
          type: "object",
          properties: {
            canonicalType: {type: "string"},
            confidence: {type: "number"},
          },
          required: ["canonicalType", "confidence"],
        },
      },
      identityConfidence: {type: "number"},
      primaryColor: color,
      secondaryColor: color,
      accentColors: {type: "array", items: color},
      metalTone: {type: "string", enum: artifact.enums.metalTones},
      hardwareTone: {type: "string", enum: artifact.enums.metalTones},
      patterns: stringArray,
      materialAppearance: {type: "string"},
      fit: {type: "string"},
      visualScale: {type: "string"},
      formality: {type: "integer"},
      warmth: {type: "integer", minimum: 1, maximum: 10},
      styles: stringArray,
      occasionFit: stringArray,
      attributes: {
        type: "array",
        items: {
          type: "object",
          properties: {key: {type: "string"}, value: {type: "string"}},
          required: ["key", "value"],
        },
      },
      visibleRegions: stringArray,
      fieldConfidence: {
        type: "array",
        items: {
          type: "object",
          properties: {
            field: {type: "string", enum: FIELD_CONFIDENCE_KEYS},
            confidence: {type: "number"},
          },
          required: ["field", "confidence"],
        },
      },
    },
    required: [
      "contractVersion", "canonicalType", "candidateTypes",
      "identityConfidence", "primaryColor", "secondaryColor", "accentColors",
      "metalTone", "hardwareTone", "patterns", "materialAppearance", "fit",
      "visualScale", "formality", "warmth", "styles", "occasionFit",
      "attributes", "visibleRegions", "fieldConfidence",
    ],
  };
}

function normalizeColor(value, {optional = false} = {}) {
  if (!value || typeof value !== "object") return optional ? null : value;
  if (optional && !String(value.family || "").trim()) return null;
  return {
    family: String(value.family || "").trim() || null,
    hex: String(value.hex || "").trim() || null,
    proportion: typeof value.proportion === "number" ? value.proportion : null,
  };
}

function normalizeGeminiWardrobeAnalyzerV2Transport(raw, provenance = {}) {
  const attributes = {};
  for (const pair of Array.isArray(raw?.attributes) ? raw.attributes : []) {
    if (pair && typeof pair.key === "string" && !Object.hasOwn(attributes, pair.key)) {
      attributes[pair.key] = pair.value;
    }
  }
  const fieldConfidence = {};
  for (const entry of Array.isArray(raw?.fieldConfidence) ? raw.fieldConfidence : []) {
    if (entry && FIELD_CONFIDENCE_KEYS.includes(entry.field)) {
      fieldConfidence[entry.field] = entry.confidence;
    }
  }
  return {
    contractVersion: "wardrobe-analyzer-v2",
    analyzerVersion: provenance.analyzerVersion || "clothing-vision-gemini-v2",
    modelVersion: provenance.modelVersion || "gemini-3.5-flash",
    taxonomyVersion: artifact.taxonomyVersion,
    identity: {
      canonicalType: raw?.canonicalType,
      candidateTypes: raw?.candidateTypes,
      confidence: raw?.identityConfidence,
    },
    observed: {
      colorProfile: {
        primary: normalizeColor(raw?.primaryColor),
        secondary: normalizeColor(raw?.secondaryColor, {optional: true}),
        accents: (Array.isArray(raw?.accentColors) ? raw.accentColors : [])
          .map((value) => normalizeColor(value)),
        metalTone: raw?.metalTone,
        hardwareTone: raw?.hardwareTone,
      },
      patterns: raw?.patterns,
      materialAppearance: String(raw?.materialAppearance || "").trim() || null,
      fit: String(raw?.fit || "").trim() || null,
      visualScale: String(raw?.visualScale || "").trim() || null,
      attributes,
    },
    inferred: {
      formality: raw?.formality,
      styles: raw?.styles,
      occasionFit: raw?.occasionFit,
      warmth: raw?.warmth,
    },
    evidence: {visibleRegions: raw?.visibleRegions, fieldConfidence},
  };
}

module.exports = {
  FIELD_CONFIDENCE_KEYS,
  buildGeminiWardrobeAnalyzerV2Schema,
  normalizeGeminiWardrobeAnalyzerV2Transport,
};
