"use strict";

const {buildChatSystemPrompt} = require("./chat_prompts");
const {getStylistRoleModelConfig} = require("./ai_model_registry");
const {
  buildConversationBrainResponsesBodyV1,
  extractConversationBrainResponseTextV1,
  extractConversationBrainWebResearchV1,
} = require("./openai_responses_web_search_v1");

const ALLOWED_ACTIONS = new Set([
  "chat",
  "clarify",
  "generate_outfit",
  "show_items",
]);
const PUBLIC_RESEARCH_KEYS = new Set([
  "performer",
  "dressCode",
  "eventStartHour",
  "eventEndHour",
  "durationMinutes",
]);
const DRESS_CODE_KEYS = new Set([
  "id",
  "labelSk",
  "formalityTarget",
  "venueType",
]);
const INTERNAL_REPLY_PATTERN = /\b(?:candidateId|validator|deterministic|pipeline|provider|reasoning_effort|web_search_call)\b/i;
const URL_PATTERN = /(?:https?:\/\/|www\.)/i;

const SMOKE_SCENARIOS = Object.freeze([
  Object.freeze({
    id: "current-public-event-needs-web",
    turns: Object.freeze([
      Object.freeze({
        message: "O tri týždne idem do Michaloviec na koncert AC/DC. Čo si mám obliecť?",
        outfitContextState: Object.freeze({
          activityLocationLabel: "Michalovce",
          activityLocationKnown: true,
          activityHint: "concert",
          groundingStatus: "sufficient",
          unresolvedMaterialFields: Object.freeze([]),
        }),
        expect: Object.freeze({webUsed: true}),
      }),
    ]),
  }),
  Object.freeze({
    id: "unknown-public-term-needs-web-before-clarify",
    turns: Object.freeze([
      Object.freeze({
        message: "Na pozvánke na verejné podujatie mám dress code 'Neo Alpine Formal 2026'. Čo to znamená pre outfit?",
        outfitContextState: Object.freeze({
          groundingStatus: "needs_grounding",
          unresolvedMaterialFields: Object.freeze(["activity"]),
        }),
        expect: Object.freeze({webUsed: true}),
      }),
    ]),
  }),
  Object.freeze({
    id: "common-fashion-does-not-need-web",
    turns: Object.freeze([
      Object.freeze({
        message: "Hodí sa biele tričko k tmavomodrým džínsom?",
        outfitContextState: Object.freeze({
          groundingStatus: "sufficient",
          unresolvedMaterialFields: Object.freeze([]),
        }),
        expect: Object.freeze({webUsed: false, actions: Object.freeze(["chat"])}),
      }),
    ]),
  }),
  Object.freeze({
    id: "private-shorthand-must-not-use-web",
    turns: Object.freeze([
      Object.freeze({
        message: "S kamarátmi máme súkromnú skratku 'modrý režim'. Zajtra ideme na modrý režim, čo si mám obliecť?",
        outfitContextState: Object.freeze({
          groundingStatus: "needs_grounding",
          unresolvedMaterialFields: Object.freeze(["activity", "destination"]),
        }),
        expect: Object.freeze({
          webUsed: false,
          actions: Object.freeze(["clarify", "chat"]),
        }),
      }),
    ]),
  }),
  Object.freeze({
    id: "private-place-must-not-use-web",
    turns: Object.freeze([
      Object.freeze({
        message: "Zajtra idem s Katkou na naše miesto. Čo si mám dať?",
        outfitContextState: Object.freeze({
          groundingStatus: "needs_grounding",
          unresolvedMaterialFields: Object.freeze(["activity", "destination"]),
        }),
        expect: Object.freeze({
          webUsed: false,
          actions: Object.freeze(["clarify", "chat"]),
        }),
      }),
    ]),
  }),
  Object.freeze({
    id: "topic-switch-does-not-carry-stale-research",
    turns: Object.freeze([
      Object.freeze({
        message: "O tri týždne idem do Michaloviec na koncert AC/DC. Čo si mám obliecť?",
        outfitContextState: Object.freeze({
          activityLocationLabel: "Michalovce",
          activityLocationKnown: true,
          activityHint: "concert",
          groundingStatus: "sufficient",
          unresolvedMaterialFields: Object.freeze([]),
        }),
        expect: Object.freeze({webUsed: true}),
      }),
      Object.freeze({
        message: "Inak nechaj koncert tak. Hodí sa všeobecne čierne tričko k sivým nohaviciam?",
        outfitContextState: Object.freeze({
          groundingStatus: "sufficient",
          unresolvedMaterialFields: Object.freeze([]),
        }),
        expect: Object.freeze({
          webUsed: false,
          actions: Object.freeze(["chat"]),
          replyMustNotContain: Object.freeze(["AC/DC", "Michalov"]),
        }),
      }),
    ]),
  }),
]);

function cleanString(value, max = 4000) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function buildLiveQaUserContent({message, outfitContextState, nowIso}) {
  return [
    `Najnovšia správa používateľa:\n${cleanString(message, 12000)}`,
    `Client context (dátum/čas):\n${JSON.stringify({
      timezone: "Europe/Bratislava",
      nowIso: cleanString(nowIso, 80),
    })}`,
    `Outfit context state:\n${JSON.stringify(outfitContextState || {})}`,
    "Šatník používateľa:\n- (live QA neposkytuje súkromný šatník)",
  ].join("\n\n");
}

function buildLiveQaMessages({history = [], message, outfitContextState, nowIso}) {
  return [
    {role: "system", content: buildChatSystemPrompt("brain_v1")},
    ...history,
    {
      role: "user",
      content: buildLiveQaUserContent({message, outfitContextState, nowIso}),
    },
  ];
}

function parseBrainJson(text) {
  const raw = cleanString(text, 20000);
  if (!raw) throw new Error("brain_live_qa_empty_response_text");
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (_) {
    const start = raw.indexOf("{");
    const end = raw.lastIndexOf("}");
    if (start < 0 || end <= start) throw new Error("brain_live_qa_invalid_json");
    try {
      parsed = JSON.parse(raw.slice(start, end + 1));
    } catch (_) {
      throw new Error("brain_live_qa_invalid_json");
    }
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("brain_live_qa_invalid_json_object");
  }
  return parsed;
}

function publicResearchViolations(parsed, webUsed) {
  const violations = [];
  const eventContext = parsed && parsed.eventContext;
  const raw = eventContext && typeof eventContext === "object" && !Array.isArray(eventContext) ?
    eventContext.publicResearch : null;
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return violations;

  if (!webUsed) violations.push("publicResearch_without_web_search");
  for (const key of Object.keys(raw)) {
    if (!PUBLIC_RESEARCH_KEYS.has(key)) {
      violations.push(`publicResearch_forbidden_key:${key}`);
    }
  }
  if (raw.dressCode && typeof raw.dressCode === "object" && !Array.isArray(raw.dressCode)) {
    for (const key of Object.keys(raw.dressCode)) {
      if (!DRESS_CODE_KEYS.has(key)) {
        violations.push(`publicResearch_dressCode_forbidden_key:${key}`);
      }
    }
  }
  return violations;
}

function safeSourceHosts(webResearch) {
  const hosts = [];
  const seen = new Set();
  for (const source of Array.isArray(webResearch && webResearch.sources) ? webResearch.sources : []) {
    try {
      const host = new URL(source.url).hostname.toLowerCase();
      if (host && !seen.has(host)) {
        seen.add(host);
        hosts.push(host);
      }
    } catch (_) {
      // Invalid URLs are already filtered by the production adapter.
    }
  }
  return hosts.slice(0, 12);
}

function compactUsage(json) {
  const usage = json && json.usage && typeof json.usage === "object" ? json.usage : {};
  const numberOrNull = (value) => Number.isFinite(Number(value)) ? Number(value) : null;
  return {
    inputTokens: numberOrNull(usage.input_tokens),
    outputTokens: numberOrNull(usage.output_tokens),
    totalTokens: numberOrNull(usage.total_tokens),
  };
}

function evaluateLiveQaTurn({parsed, webResearch, rawResponse, durationMs, expect = {}}) {
  const failures = [];
  const reply = cleanString(parsed.reply, 12000);
  const action = cleanString(parsed.action, 80);
  const webUsed = webResearch && webResearch.used === true;
  const callCount = Number(webResearch && webResearch.callCount || 0);

  if (!reply) failures.push("reply_missing");
  if (!ALLOWED_ACTIONS.has(action)) failures.push(`action_invalid:${action || "missing"}`);
  if (URL_PATTERN.test(reply)) failures.push("reply_contains_url");
  if (INTERNAL_REPLY_PATTERN.test(reply)) failures.push("reply_exposes_internal_pipeline");
  if (callCount < 0 || callCount > 3) failures.push(`web_call_count_out_of_bounds:${callCount}`);
  if (typeof expect.webUsed === "boolean" && webUsed !== expect.webUsed) {
    failures.push(`web_used_expected_${expect.webUsed}_actual_${webUsed}`);
  }
  if (Array.isArray(expect.actions) && expect.actions.length && !expect.actions.includes(action)) {
    failures.push(`action_expected_${expect.actions.join("|")}_actual_${action}`);
  }
  for (const needle of Array.isArray(expect.replyMustNotContain) ? expect.replyMustNotContain : []) {
    if (needle && reply.toLowerCase().includes(String(needle).toLowerCase())) {
      failures.push(`reply_contains_stale_term:${needle}`);
    }
  }
  failures.push(...publicResearchViolations(parsed, webUsed));

  return Object.freeze({
    passed: failures.length === 0,
    failures: Object.freeze(failures),
    action,
    replyLength: reply.length,
    webUsed,
    webCallCount: callCount,
    sourceHosts: Object.freeze(safeSourceHosts(webResearch)),
    publicContextKeys: Object.freeze(Object.keys(webResearch && webResearch.publicContext || {})),
    usage: Object.freeze(compactUsage(rawResponse)),
    durationMs: Math.max(0, Math.round(Number(durationMs) || 0)),
  });
}

async function callOpenAiResponses({apiKey, body, fetchImpl = global.fetch}) {
  if (typeof fetchImpl !== "function") throw new Error("brain_live_qa_fetch_unavailable");
  const response = await fetchImpl("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(body),
  });
  if (!response || response.ok !== true) {
    const status = Number(response && response.status || 0);
    const error = new Error(`brain_live_qa_openai_http_${status || "unknown"}`);
    error.code = "brain_live_qa_openai_http_error";
    throw error;
  }
  return response.json();
}

async function runLiveQaScenario({
  scenario,
  apiKey,
  fetchImpl = global.fetch,
  now = () => new Date(),
}) {
  const model = getStylistRoleModelConfig("conversationBrain");
  if (!model || !model.webModelId) throw new Error("brain_live_qa_model_config_missing");
  const history = [];
  const turnReports = [];

  for (const turn of scenario.turns) {
    const nowIso = now().toISOString();
    const messages = buildLiveQaMessages({
      history,
      message: turn.message,
      outfitContextState: turn.outfitContextState,
      nowIso,
    });
    const body = buildConversationBrainResponsesBodyV1({
      model: model.webModelId,
      messages,
      maxOutputTokens: model.webMaxTokens,
      reasoningEffort: model.reasoningEffort,
      searchContextSize: model.searchContextSize,
    });
    const startedAt = Date.now();
    const json = await callOpenAiResponses({apiKey, body, fetchImpl});
    const durationMs = Date.now() - startedAt;
    const rawText = extractConversationBrainResponseTextV1(json);
    const parsed = parseBrainJson(rawText);
    const webResearch = extractConversationBrainWebResearchV1(json);
    const report = evaluateLiveQaTurn({
      parsed,
      webResearch,
      rawResponse: json,
      durationMs,
      expect: turn.expect,
    });
    turnReports.push(report);

    history.push({role: "user", content: turn.message});
    history.push({role: "assistant", content: cleanString(parsed.reply, 12000)});
    if (history.length > 8) history.splice(0, history.length - 8);
  }

  return Object.freeze({
    id: scenario.id,
    passed: turnReports.every((turn) => turn.passed),
    turns: Object.freeze(turnReports),
  });
}

function selectScenarios(scenarios, filter) {
  const normalized = cleanString(filter, 120).toLowerCase();
  if (!normalized) return scenarios;
  return scenarios.filter((scenario) => scenario.id.toLowerCase().includes(normalized));
}

async function runLiveQaSuite({
  scenarios = SMOKE_SCENARIOS,
  apiKey,
  fetchImpl = global.fetch,
  now = () => new Date(),
  filter = "",
} = {}) {
  const selected = selectScenarios(scenarios, filter);
  if (!selected.length) throw new Error("brain_live_qa_no_scenarios_selected");
  const reports = [];
  for (const scenario of selected) {
    reports.push(await runLiveQaScenario({scenario, apiKey, fetchImpl, now}));
  }
  return Object.freeze({
    model: getStylistRoleModelConfig("conversationBrain").webModelId,
    reasoningEffort: getStylistRoleModelConfig("conversationBrain").reasoningEffort,
    searchContextSize: getStylistRoleModelConfig("conversationBrain").searchContextSize,
    passed: reports.every((scenario) => scenario.passed),
    scenarioCount: reports.length,
    requestCount: reports.reduce((sum, scenario) => sum + scenario.turns.length, 0),
    scenarios: Object.freeze(reports),
  });
}

function resolveLiveQaApiKey(env = process.env) {
  const direct = cleanString(env.OPENAI_API_KEY, 10000);
  if (direct) return direct;
  throw new Error("brain_live_qa_openai_api_key_missing");
}

function assertLiveQaOptIn(env = process.env) {
  if (String(env.BRAIN_LIVE_QA || "").trim() !== "1") {
    throw new Error("brain_live_qa_requires_explicit_opt_in");
  }
}

function printSafeReport(suite, log = console.log) {
  log(`Brain Live QA | model=${suite.model} | scenarios=${suite.scenarioCount} | requests=${suite.requestCount}`);
  for (const scenario of suite.scenarios) {
    log(`CASE ${scenario.id}: ${scenario.passed ? "PASS" : "FAIL"}`);
    scenario.turns.forEach((turn, index) => {
      const failures = turn.failures.length ? ` | failures=${turn.failures.join(",")}` : "";
      const hosts = turn.sourceHosts.length ? ` | sources=${turn.sourceHosts.join(",")}` : "";
      const publicKeys = turn.publicContextKeys.length ? ` | public=${turn.publicContextKeys.join(",")}` : "";
      log(
        `  turn=${index + 1} action=${turn.action} web=${turn.webUsed} calls=${turn.webCallCount}` +
        ` durationMs=${turn.durationMs}${hosts}${publicKeys}${failures}`,
      );
    });
  }
  log(`RESULT: ${suite.passed ? "PASS" : "FAIL"}`);
}

async function main() {
  assertLiveQaOptIn();
  const apiKey = resolveLiveQaApiKey();
  const suite = await runLiveQaSuite({
    apiKey,
    filter: process.env.BRAIN_LIVE_QA_FILTER || "",
  });
  printSafeReport(suite);
  if (!suite.passed) process.exitCode = 1;
}

if (require.main === module) {
  main().catch((error) => {
    console.error(`Brain Live QA aborted: ${error && error.message ? error.message : "unknown_error"}`);
    process.exitCode = 1;
  });
}

module.exports = {
  SMOKE_SCENARIOS,
  buildLiveQaUserContent,
  buildLiveQaMessages,
  parseBrainJson,
  publicResearchViolations,
  evaluateLiveQaTurn,
  runLiveQaScenario,
  runLiveQaSuite,
  resolveLiveQaApiKey,
  assertLiveQaOptIn,
  printSafeReport,
};
