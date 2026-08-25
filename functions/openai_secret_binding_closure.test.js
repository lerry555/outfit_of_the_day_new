"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const source = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");

const openAiConsumers = [
  "analyzeClothingImage",
  "analyzeClothingImageV2Shadow",
  "generateHomeOutfit",
  "finalReviewHomeOutfitCandidates",
  "generateHomeOutfitExplanation",
  "chatWithStylist",
  "analyzeWardrobeSmart",
  "analyzeClothingProductUrl",
  "prepareProductLinkImage",
  "processWardrobeProductLinkImage",
];

function exportSource(name) {
  const start = source.indexOf(`exports.${name} =`);
  assert.notEqual(start, -1, `missing ${name} export`);
  const next = source.indexOf("exports.", start + 1);
  return source.slice(start, next === -1 ? source.length : next);
}

test("all executable OpenAI consumers have an explicit Secret Manager binding", () => {
  for (const name of openAiConsumers) {
    assert.match(
      exportSource(name),
      /secrets:\s*\[[^\]]*OPENAI_API_KEY_SECRET/,
      `${name} must bind OPENAI_API_KEY_SECRET`,
    );
  }
});

test("wardrobe qualification authority retains its existing OpenAI binding", () => {
  const authoritySource = fs.readFileSync(
    path.join(__dirname, "wardrobe_authority_callable_exports.js"),
    "utf8",
  );
  assert.match(
    authoritySource,
    /secrets:\s*\[OPENAI_API_KEY_SECRET, WARDROBE_SHADOW_POLICY_SECRET/,
  );
});

test("legacy OpenAI resolver has no environment or functions.config fallback", () => {
  const resolver = source.match(/function getOpenAiKey\(\)\s*\{([\s\S]*?)\n\}/);
  assert.ok(resolver);
  assert.match(resolver[1], /return resolveOpenAISecret\(\);/);
  assert.doesNotMatch(resolver[1], /process\.env|functions\.config|getConfigValue/);
});

test("Gemini remains primary and OpenAI legacy remains opt-in only", () => {
  const handler = fs.readFileSync(
    path.join(__dirname, "clothing_vision", "analyze_clothing_image_handler.js"),
    "utf8",
  );
  assert.match(handler, /if \(task\.provider === PROVIDERS\.OPENAI_LEGACY\)/);
  assert.match(handler, /GEMINI primary path — no automatic OpenAI fallback/);
  assert.doesNotMatch(
    handler,
    /catch \([^)]*\)\s*\{[\s\S]{0,500}runOpenAiLegacyClothingAnalysis/,
  );
});
