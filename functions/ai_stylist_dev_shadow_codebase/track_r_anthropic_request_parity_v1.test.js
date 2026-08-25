"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {buildAnthropicRequest, toAnthropicWireSchema} =
  require("../../tool/benchmarks/ai_stylist/adapters/anthropic.cjs");
const {
  ANTHROPIC_UNSUPPORTED_CONSTRAINTS,
  EXPLANATION_SCHEMA,
  anthropicBody,
  simplifyAnthropicSchema,
} = require("./role_transport_v1");

function containsKey(value, key) {
  if (Array.isArray(value)) return value.some((item) => containsKey(item, key));
  if (!value || typeof value !== "object") return false;
  return Object.entries(value).some(([name, item]) => name === key || containsKey(item, key));
}

test("DEV-shadow Claude request uses preserved Track R Anthropic wire semantics", () => {
  const benchmark = buildAnthropicRequest({
    modelId: "claude-sonnet-5", systemPrompt: "known-good system", userPrompt: "known-good user",
    apiKey: "synthetic-only", maxOutputTokens: 600, temperature: 0,
    outputSchema: EXPLANATION_SCHEMA,
  });
  const dev = anthropicBody({canonicalPayload: {effectiveAction: "select_candidate"}});
  assert.equal(benchmark.url, "https://api.anthropic.com/v1/messages");
  assert.equal(benchmark.url, "https://api.anthropic.com/v1/messages");
  assert.equal(benchmark.headers["anthropic-version"], "2023-06-01");
  assert.equal(dev.model, benchmark.body.model);
  assert.equal(dev.system.length > 0, true);
  assert.deepEqual(dev.messages.map((item) => item.role), ["user"]);
  assert.equal(dev.output_config.effort, "low");
  assert.equal(dev.output_config.format.type, "json_schema");
  assert.equal(Object.hasOwn(dev, "temperature"), false);
  assert.equal(dev.output_config.format.schema.additionalProperties, false);
  assert.deepEqual(dev.output_config.format.schema,
    toAnthropicWireSchema(EXPLANATION_SCHEMA));
  for (const unsupported of ANTHROPIC_UNSUPPORTED_CONSTRAINTS) {
    assert.equal(containsKey(dev.output_config.format.schema, unsupported), false, unsupported);
  }
});

test("Anthropic wire transform preserves object closure while removing only unsupported constraints", () => {
  const canonical = {
    type: "object", additionalProperties: false, required: ["value"],
    properties: {value: {type: "array", minItems: 1, uniqueItems: true,
      items: {oneOf: [{type: "string"}, {type: "null"}]}}},
  };
  const wire = simplifyAnthropicSchema(canonical);
  assert.equal(wire.additionalProperties, false);
  assert.equal(containsKey(wire, "oneOf"), false);
  assert.equal(containsKey(wire, "anyOf"), true);
  assert.equal(containsKey(wire, "minItems"), false);
  assert.equal(containsKey(wire, "uniqueItems"), false);
  assert.equal(canonical.properties.value.uniqueItems, true);
});
