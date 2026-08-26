"use strict";

// Deterministic compatibility metadata, not a calendar eligibility policy.
// Actual temperature, precipitation and item thermal facts remain authoritative
// in the shared outfit-suitability policy.
function deriveSeasonCompatibilityV2({
  canonicalType,
  canonicalFamily,
  layerPosition,
  warmth,
  outfitFunctions = [],
} = {}) {
  const type = String(canonicalType || "").trim().toLowerCase();
  const family = String(canonicalFamily || "").trim().toLowerCase();
  const layer = String(layerPosition || "").trim().toLowerCase();
  const safeWarmth = Math.max(1, Math.min(10, Number.isInteger(warmth) ? warmth : 5));
  const functions = new Set(Array.isArray(outfitFunctions) ?
    outfitFunctions.map((value) => String(value || "").trim().toLowerCase()) : []);

  if (/(swim|bikini|short)/.test(type)) return ["jar", "leto"];
  if (/(winter|snow|thermal)/.test(type)) return ["jeseň", "zima"];

  if (family === "footwear") {
    if (type.includes("boot")) return safeWarmth >= 7 ? ["jeseň", "zima"] : ["jar", "jeseň"];
    if (/(sandal|flip_flop|slide|espadrille)/.test(type)) return ["jar", "leto"];
    if (/(sneaker|trainer|running)/.test(type)) return ["jar", "leto", "jeseň"];
    return ["celoročne"];
  }

  if (layer === "outer" || layer === "shell") {
    if (safeWarmth >= 7) return ["jeseň", "zima"];
    if (safeWarmth >= 5) return ["jar", "jeseň", "zima"];
    if (functions.has("weather_protection")) return ["jar", "leto", "jeseň"];
    return ["jar", "leto", "jeseň"];
  }

  if (safeWarmth >= 8) return ["jeseň", "zima"];
  if (safeWarmth >= 6) return ["jar", "jeseň", "zima"];
  if (safeWarmth <= 2) return ["jar", "leto"];
  return ["celoročne"];
}

module.exports = {deriveSeasonCompatibilityV2};
