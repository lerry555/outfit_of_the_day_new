"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildConversationBrainExplanationBodyV1,
  createConversationBrainExplanationTransportV1,
  explanationSystemPrompt,
} = require("./conversation_brain_v1");
const {getStylistRoleModelConfig} = require("./ai_model_registry");

const payload = {
  effectiveAction: "select_candidate",
  userFacingSelectedOutfit: [
    {name: "čierne tričko", canonicalType: "t_shirt", primaryColor: "black"},
    {name: "modré rifle", canonicalType: "jeans", primaryColor: "blue"},
    {name: "čierne čižmy", canonicalType: "winter_boots", primaryColor: "black"},
  ],
  userFacingContext: {activity: "hike", weather: "12C wetGround=true"},
  userFacingCompromises: [{
    itemName: "čierne čižmy",
    tier: "strongCompromise",
    missingCapabilities: ["hiking_footwear", "traction"],
    idealReplacementDescription: "turistická obuv s lepším gripom",
  }],
};

test("Brain V1 uses the swappable conversationBrain registry role", () => {
  const body = buildConversationBrainExplanationBodyV1(payload);
  assert.equal(body.model, getStylistRoleModelConfig("conversationBrain").id);
  assert.equal(body.model, "gpt-4o");
  assert.equal(body.response_format.type, "json_schema");
});

test("Brain V1 explanation keeps the validated outfit immutable and conversation-friendly", () => {
  const prompt = explanationSystemPrompt();
  assert.match(prompt, /jedným schopným kamarátom/);
  assert.match(prompt, /nemenné/);
  assert.match(prompt, /Nesmieš outfit zmeniť/);
  assert.match(prompt, /najlepšiu dostupnú vlastnenú možnosť/);
  assert.match(prompt, /nájdeš vhodnejšiu náhradu/);
  assert.match(prompt, /Nezačínaj novým pozdravom/);
});

test("Brain V1 explanation transport uses OpenAI and validates strict output", async () => {
  let request;
  const client = createConversationBrainExplanationTransportV1({
    credentialProvider: () => "test-credential",
    execute: async (value) => {
      request = value;
      return {
        ok: true,
        status: 200,
        json: {
          model: "gpt-4o",
          choices: [{message: {content: JSON.stringify({
            explanation: "Toto je z tvojich vecí najlepšia voľba. Čižmy sú však na turistiku kompromis — lepšia by bola turistická obuv s gripom. Ak chceš, pozriem ti vhodnejšiu náhradu.",
            warnings: [],
          })}}],
        },
      };
    },
  });

  const result = await client.run(payload);
  assert.equal(request.url, "https://api.openai.com/v1/chat/completions");
  assert.equal(request.body.model, "gpt-4o");
  assert.equal(request.url.includes("anthropic"), false);
  assert.equal(result.ok, true);
  assert.match(result.value.explanation, /kompromis/);
});

test("Brain V1 fails closed on malformed user-facing output", async () => {
  const client = createConversationBrainExplanationTransportV1({
    credentialProvider: () => "test-credential",
    execute: async () => ({
      ok: true,
      status: 200,
      json: {choices: [{message: {content: "{}"}}]},
    }),
  });
  const result = await client.run(payload);
  assert.equal(result.ok, false);
  assert.equal(result.failureCode, "structured_output_invalid");
});
