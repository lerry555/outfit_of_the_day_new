"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {buildOpenAiRequest} = require("../../tool/benchmarks/ai_stylist/adapters/openai.cjs");
const {
  OPENAI_CONTEXT_WIRE_SCHEMA,
  createOpenAiRoleTransport,
  openAiBody,
} = require("./role_transport_v1");

function containsKey(value, key) {
  if (Array.isArray(value)) return value.some((item) => containsKey(item, key));
  if (!value || typeof value !== "object") return false;
  return Object.entries(value).some(([name, item]) => name === key || containsKey(item, key));
}

test("DEV-shadow GPT-4o context request matches known-good Track U OpenAI semantics", async () => {
  const benchmark = buildOpenAiRequest({
    modelId: "gpt-4o", systemPrompt: "known-good system", userPrompt: "known-good user",
    apiKey: "synthetic-only", maxOutputTokens: 450, temperature: 0,
  });
  const devBody = openAiBody({role: "contextClarification", canonicalPayload: {
    knownFacts: {activity: "city_walk"}, unresolvedMaterialFactKeys: [],
  }});
  let dispatchedRequest = null;
  const client = createOpenAiRoleTransport({
    role: "contextClarification", credentialProvider: async () => "synthetic-only",
    execute: async (request) => {
      dispatchedRequest = request;
      return {status: 200, json: {model: "gpt-4o-2024-08-06", choices: [{message: {
        content: JSON.stringify({action: "proceed", clarificationFactKey: null,
          acceptedKnownFactKeys: null}),
      }}]}};
    },
  });
  assert.equal((await client.run({knownFacts: {activity: "city_walk"}})).ok, true);

  assert.equal(benchmark.url, dispatchedRequest.url);
  assert.equal(benchmark.body.model, devBody.model);
  assert.deepEqual(benchmark.body.messages.map((item) => item.role), devBody.messages.map((item) => item.role));
  assert.equal(benchmark.body.response_format.type, devBody.response_format.type);
  assert.equal(benchmark.body.response_format.json_schema.strict, true);
  assert.equal(devBody.response_format.json_schema.strict, true);
  assert.equal(benchmark.body.max_tokens, 450);
  assert.equal(devBody.max_tokens, 400); // bounded smoke size; same GPT-4o parameter family.
  assert.equal(benchmark.body.temperature, devBody.temperature);
  assert.equal(Object.hasOwn(devBody, "max_completion_tokens"), false);
  assert.equal(Object.hasOwn(devBody, "reasoning_effort"), false);
  assert.equal(Boolean(dispatchedRequest.headers.Authorization), true);

  assert.deepEqual(OPENAI_CONTEXT_WIRE_SCHEMA.required.sort(),
    Object.keys(OPENAI_CONTEXT_WIRE_SCHEMA.properties).sort());
  assert.deepEqual(OPENAI_CONTEXT_WIRE_SCHEMA.properties.clarificationFactKey.type,
    ["string", "null"]);
  assert.deepEqual(OPENAI_CONTEXT_WIRE_SCHEMA.properties.acceptedKnownFactKeys.type,
    ["array", "null"]);
  assert.equal(containsKey(OPENAI_CONTEXT_WIRE_SCHEMA, "oneOf"), false);
  assert.equal(containsKey(OPENAI_CONTEXT_WIRE_SCHEMA, "uniqueItems"), false);
  assert.equal(containsKey(OPENAI_CONTEXT_WIRE_SCHEMA, "additionalProperties"), true);
});
