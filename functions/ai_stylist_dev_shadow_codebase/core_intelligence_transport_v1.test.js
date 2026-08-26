"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {openAiBody, anthropicBody} = require("./role_transport_v1");

test("final decision treats safe best-owned compromises as selectable", () => {
  const body = openAiBody({
    role: "finalCandidateDecision",
    canonicalPayload: {
      frozenCandidates: [{
        candidateId: "candidate-a",
        items: [{canonicalType: "winter_boots", primaryColor: "black"}],
        compromiseClassification: {level: "material_compromise"},
        functionalCompromises: [{
          tier: "strongCompromise",
          missingCapabilities: ["hiking_footwear", "traction"],
        }],
      }],
    },
  });
  assert.match(body.messages[0].content, /material_compromise remains selectable/);
  assert.match(body.messages[0].content, /reject_all only when no frozen candidate/);
  const payload = JSON.parse(body.messages[1].content);
  assert.equal(payload.frozenCandidates[0].items[0].canonicalType, "winter_boots");
  assert.deepEqual(
    payload.frozenCandidates[0].functionalCompromises[0].missingCapabilities,
    ["hiking_footwear", "traction"],
  );
  assert.equal(JSON.stringify(payload).includes("candidateIndex"), false);
});

test("explanation voice is warm, compromise-honest and gender-neutral", () => {
  const body = anthropicBody({
    canonicalPayload: {
      effectiveAction: "select_candidate",
      userFacingCompromises: [{
        itemName: "čierne čižmy",
        tier: "strongCompromise",
        missingCapabilities: ["hiking_footwear"],
      }],
    },
  });
  assert.match(body.system, /najlepšiu vlastnenú možnosť/);
  assert.match(body.system, /gramatický rod nie je explicitne známy/);
  assert.match(body.system, /outfit nikdy nemeň/);
});
