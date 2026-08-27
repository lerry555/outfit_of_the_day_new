"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {createFrozenStylistAuthority} = require("./frozen_stylist_authority_v1");

function request({brain = true} = {}) {
  return {
    contractVersion: 1,
    ...(brain ? {conversationBrainVersion: "brain_v1"} : {}),
    resolvedContext: {
      activity: "hike",
      occasion: "výlet do hôr",
      weather: "12C wetGround=true",
      terrain: "wetGround",
    },
    frozenCandidates: [{
      candidateId: "candidate-a",
      itemIds: ["top", "bottom", "shoes"],
      presentationItems: [
        {itemId: "top", name: "čierne tričko", canonicalType: "t_shirt", primaryColor: "black"},
        {itemId: "bottom", name: "modré rifle", canonicalType: "jeans", primaryColor: "blue"},
        {itemId: "shoes", name: "čierne čižmy", canonicalType: "winter_boots", primaryColor: "black"},
      ],
      hardConstraintEvidence: {deterministicPassed: true, violationCodes: []},
      compromiseClassification: {level: "material_compromise", reasonCodes: ["footwear_gap"]},
      compromiseDetails: [{
        itemName: "čierne čižmy",
        tier: "strongCompromise",
        reasonCodes: ["footwear_not_hiking_or_trail_rated"],
        missingCapabilities: ["hiking_footwear", "traction"],
        idealReplacementDescription: "turistická obuv s lepším gripom",
      }],
    }],
  };
}

test("opted-in frozen decision stays authoritative while Brain V1 owns final voice", async () => {
  const calls = [];
  const authority = createFrozenStylistAuthority({
    resolveOpenAISecret: () => "openai-test",
    resolveAnthropicSecret: () => "anthropic-test",
    execute: async (call) => {
      calls.push(call);
      if (calls.length === 1) {
        return {
          ok: true,
          status: 200,
          json: {
            model: "gpt-5.4-mini",
            choices: [{message: {content: JSON.stringify({
              action: "select_candidate",
              selectedCandidateId: "candidate-a",
            })}}],
          },
        };
      }
      return {
        ok: true,
        status: 200,
        json: {
          model: "gpt-4o",
          choices: [{message: {content: JSON.stringify({
            explanation: "Z tvojich vecí je toto najlepšia možnosť. Čižmy sú však na turistiku kompromis, takže ideálna by bola turistická obuv s lepším gripom. Ak chceš, môžem ti takú náhradu pomôcť nájsť.",
            warnings: [],
          })}}],
        },
      };
    },
  });

  const result = await authority.resolve({
    data: request(),
    ownedItemIds: new Set(["top", "bottom", "shoes"]),
  });

  assert.equal(result.action, "select_candidate");
  assert.equal(result.selectedCandidateId, "candidate-a");
  assert.equal(result.explanationFallback, false);
  assert.equal(result.conversationBrainVersion, "brain_v1");
  assert.equal(calls.length, 2);
  assert.equal(calls[0].body.model, "gpt-5.4-mini");
  assert.equal(calls[1].body.model, "gpt-4o");
  assert.ok(calls.every((call) => call.url === "https://api.openai.com/v1/chat/completions"));
});

test("older client without opt-in keeps the Anthropic explanation path", async () => {
  const calls = [];
  const authority = createFrozenStylistAuthority({
    resolveOpenAISecret: () => "openai-test",
    resolveAnthropicSecret: () => "anthropic-test",
    execute: async (call) => {
      calls.push(call);
      if (calls.length === 1) {
        return {
          ok: true,
          status: 200,
          json: {
            model: "gpt-5.4-mini",
            choices: [{message: {content: JSON.stringify({
              action: "select_candidate",
              selectedCandidateId: "candidate-a",
            })}}],
          },
        };
      }
      return {
        ok: true,
        status: 200,
        json: {
          model: "claude-sonnet-5",
          content: [{type: "text", text: JSON.stringify({
            explanation: "Toto je z tvojho šatníka najsilnejšia možnosť; pri turistike sú však čižmy kompromis a vhodnejšia by bola turistická obuv s lepším gripom.",
            warnings: [],
          })}],
        },
      };
    },
  });

  const result = await authority.resolve({
    data: request({brain: false}),
    ownedItemIds: new Set(["top", "bottom", "shoes"]),
  });

  assert.equal(result.action, "select_candidate");
  assert.equal(result.conversationBrainVersion, null);
  assert.equal(result.explanationFallback, false);
  assert.equal(calls[0].body.model, "gpt-5.4-mini");
  assert.equal(calls[1].url, "https://api.anthropic.com/v1/messages");
  assert.equal(calls[1].body.model, "claude-sonnet-5");
});
