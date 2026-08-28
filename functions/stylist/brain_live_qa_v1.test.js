"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildLiveQaMessages,
  evaluateLiveQaTurn,
  runLiveQaScenario,
  resolveLiveQaApiKey,
  assertLiveQaOptIn,
} = require("./brain_live_qa_v1");

function responseJson({reply, action = "chat", web = false, publicResearch = null} = {}) {
  const payload = {
    reply: reply || "Jasné 🙂",
    action,
    confidence: 0.9,
    decisionRisk: "low",
    assumptions: [],
    clarifyReason: "",
    impactFields: [],
    semanticGrounding: {},
    showItemIds: [],
    eventContext: publicResearch ? {publicResearch} : {},
    excludeItemKeywords: [],
  };
  const output = [];
  if (web) {
    output.push({
      type: "web_search_call",
      action: {
        sources: [{title: "Example", url: "https://example.com/event"}],
      },
    });
  }
  output.push({
    type: "message",
    content: [{type: "output_text", text: JSON.stringify(payload)}],
  });
  return {
    output,
    usage: {input_tokens: 100, output_tokens: 50, total_tokens: 150},
  };
}

function sequenceFetch(jsons, bodies) {
  let index = 0;
  return async (_url, options) => {
    bodies.push(JSON.parse(options.body));
    const json = jsons[index++];
    return {
      ok: true,
      status: 200,
      async json() {
        return json;
      },
    };
  };
}

test("live QA requires explicit opt-in and never invents an API key", () => {
  assert.throws(() => assertLiveQaOptIn({}), /explicit_opt_in/);
  assert.doesNotThrow(() => assertLiveQaOptIn({BRAIN_LIVE_QA: "1"}));
  assert.throws(() => resolveLiveQaApiKey({}), /api_key_missing/);
  assert.equal(resolveLiveQaApiKey({OPENAI_API_KEY: " test-key "}), "test-key");
});

test("live QA messages reuse Brain V1 prompt and preserve chat history", () => {
  const messages = buildLiveQaMessages({
    history: [
      {role: "user", content: "prvá správa"},
      {role: "assistant", content: "prvá odpoveď"},
    ],
    message: "ďalšia správa",
    outfitContextState: {groundingStatus: "sufficient"},
    nowIso: "2026-08-28T18:00:00.000Z",
  });
  assert.equal(messages[0].role, "system");
  assert.match(messages[0].content, /UNIVERZÁLNY WEB RESEARCH/);
  assert.equal(messages[1].content, "prvá správa");
  assert.equal(messages[2].content, "prvá odpoveď");
  assert.match(messages[3].content, /Najnovšia správa používateľa/);
  assert.match(messages[3].content, /ďalšia správa/);
});

test("turn evaluator rejects publicResearch without web and forbidden keys", () => {
  const report = evaluateLiveQaTurn({
    parsed: {
      reply: "Dobre 🙂",
      action: "chat",
      eventContext: {
        publicResearch: {
          performer: "Example Band",
          locationLabel: "Never allowed here",
        },
      },
    },
    webResearch: {used: false, callCount: 0, sources: []},
    rawResponse: {},
    durationMs: 1,
    expect: {webUsed: false},
  });
  assert.equal(report.passed, false);
  assert.ok(report.failures.includes("publicResearch_without_web_search"));
  assert.ok(report.failures.includes("publicResearch_forbidden_key:locationLabel"));
});

test("multi-turn live runner gives every request its own web-search allowance", async () => {
  const bodies = [];
  const fetchImpl = sequenceFetch([
    responseJson({
      reply: "Pozriem si aktuálny verejný kontext 🙂",
      web: true,
      publicResearch: {
        performer: "Example Band",
        dressCode: {formalityTarget: 3, venueType: "indoor_casual"},
      },
    }),
    responseJson({reply: "Áno, čierne tričko k sivým nohaviciam funguje 🙂", web: false}),
  ], bodies);

  const scenario = {
    id: "mock-two-turn",
    turns: [
      {
        message: "Idem na aktuálny verejný koncert.",
        outfitContextState: {groundingStatus: "sufficient"},
        expect: {webUsed: true},
      },
      {
        message: "Inak, hodí sa čierne tričko k sivým nohaviciam?",
        outfitContextState: {groundingStatus: "sufficient"},
        expect: {webUsed: false, actions: ["chat"]},
      },
    ],
  };

  const report = await runLiveQaScenario({
    scenario,
    apiKey: "not-a-real-key",
    fetchImpl,
    now: () => new Date("2026-08-28T18:00:00.000Z"),
  });

  assert.equal(report.passed, true);
  assert.equal(report.turns.length, 2);
  assert.equal(bodies.length, 2);
  assert.equal(bodies[0].max_tool_calls, 3);
  assert.equal(bodies[1].max_tool_calls, 3);
  assert.equal(bodies[0].model, "gpt-5.6-terra");
  assert.equal(bodies[1].model, "gpt-5.6-terra");
  assert.deepEqual(report.turns[0].sourceHosts, ["example.com"]);
  assert.deepEqual(report.turns[1].publicContextKeys, []);
});
