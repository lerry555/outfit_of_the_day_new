"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildGeminiWardrobeAnalyzerV2Schema,
  normalizeGeminiWardrobeAnalyzerV2Transport,
} = require("./gemini_wardrobe_analyzer_v2_transport");
const {validateAnalyzerV2} = require("../wardrobe_analyzer_v2_contract");

function transport(overrides = {}) {
  return {
    contractVersion: "wardrobe-analyzer-v2",
    canonicalType: "trousers",
    candidateTypes: [{canonicalType: "trousers", confidence: 0.94}],
    identityConfidence: 0.94,
    primaryColor: {family: "gray", hex: "#808080", proportion: 0.9},
    secondaryColor: {family: "", hex: "", proportion: 0},
    accentColors: [],
    metalTone: "none",
    hardwareTone: "none",
    patterns: ["solid"],
    materialAppearance: "smooth woven",
    fit: "straight",
    visualScale: "medium",
    formality: 6,
    warmth: 4,
    styles: ["classic"],
    occasionFit: ["business_casual"],
    attributes: [],
    visibleRegions: ["front"],
    fieldConfidence: [
      {field: "canonicalType", confidence: 0.94},
      {field: "primaryColor", confidence: 0.98},
    ],
    ...overrides,
  };
}

test("Gemini projection is compact, flat, enum-light and nullable-free", () => {
  const schema = buildGeminiWardrobeAnalyzerV2Schema();
  const serialized = JSON.stringify(schema);
  assert.ok(Buffer.byteLength(serialized) < 6000);
  assert.equal(schema.properties.canonicalType.enum, undefined);
  assert.equal(schema.properties.candidateTypes.items.properties.canonicalType.enum, undefined);
  assert.equal(schema.properties.identity, undefined);
  assert.equal(serialized.includes('"null"'), false);
  assert.equal(serialized.includes("additionalProperties"), false);
});

test("transport normalization restores strict provider-neutral V2 contract", () => {
  const domain = normalizeGeminiWardrobeAnalyzerV2Transport(transport());
  assert.equal(domain.identity.canonicalType, "trousers");
  assert.equal(domain.observed.colorProfile.secondary, null);
  assert.equal(domain.evidence.fieldConfidence.canonicalType, 0.94);
  assert.equal(validateAnalyzerV2(domain).ok, true);
});

test("strict server validator rejects unknown identity and invalid confidence", () => {
  const unknown = normalizeGeminiWardrobeAnalyzerV2Transport(transport({canonicalType: "invented_pants"}));
  assert.equal(validateAnalyzerV2(unknown).ok, false);
  const invalid = normalizeGeminiWardrobeAnalyzerV2Transport(transport({
    candidateTypes: [{canonicalType: "trousers", confidence: 1.2}],
  }));
  assert.equal(validateAnalyzerV2(invalid).ok, false);
});

test("strict server validator rejects family-disallowed attributes", () => {
  const domain = normalizeGeminiWardrobeAnalyzerV2Transport(transport({
    attributes: [{key: "accessory.watchStyle", value: "sport"}],
  }));
  assert.equal(validateAnalyzerV2(domain).ok, false);
});
