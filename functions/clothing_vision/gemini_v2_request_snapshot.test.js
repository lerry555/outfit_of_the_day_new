"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const {createGeminiClothingAnalyzerClient} = require("./gemini_clothing_analyzer_client");
const {getClothingAnalyzerGeminiPromptV2} = require("./prompts/clothing_analyzer_gemini_v2");

test("sanitized deterministic Gemini V2 request snapshot", () => {
  const prompt = getClothingAnalyzerGeminiPromptV2();
  const client = createGeminiClothingAnalyzerClient({
    contractVersion: "wardrobe-analyzer-v2",
    getApiKey: () => "not-used",
  });
  const body = client.buildRequestBody({
    prompt: prompt.prompt,
    mimeType: "image/jpeg",
    base64: "[IMAGE_BYTES_REDACTED]".padEnd(32, "_"),
    schema: prompt.responseSchema,
  });
  const snapshot = {
    model: client.modelId,
    promptVersion: client.promptVersion,
    promptHash: client.promptHash,
    generationConfig: body.generationConfig,
    contents: body.contents.map((content) => ({
      role: content.role,
      parts: content.parts.map((part) => part.text ?
        {textSha256: crypto.createHash("sha256").update(part.text).digest("hex")} :
        {inlineData: {mimeType: part.inlineData.mimeType, data: "[REDACTED]"}}),
    })),
  };
  assert.equal(snapshot.model, "gemini-3.5-flash");
  assert.equal(snapshot.generationConfig.responseMimeType, "application/json");
  assert.equal(snapshot.generationConfig.thinkingConfig.thinkingBudget, 0);
  assert.equal(snapshot.contents[0].parts[1].inlineData.data, "[REDACTED]");
  assert.equal(snapshot.generationConfig.responseJsonSchema.properties.contractVersion.enum[0], "wardrobe-analyzer-v2");
  assert.equal(snapshot.generationConfig.responseJsonSchema.properties.canonicalType.type, "string");
  assert.equal(snapshot.generationConfig.responseJsonSchema.properties.canonicalType.enum, undefined);
  assert.equal(snapshot.generationConfig.responseJsonSchema.properties.attributes.type, "array");
});
