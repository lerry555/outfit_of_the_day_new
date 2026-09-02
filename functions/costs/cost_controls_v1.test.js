"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {openAiUsageV1, geminiUsageV1, createAiUsageRecorderV1} = require("./ai_usage_v1");
const {createIdempotentTaskRunnerV1} = require("./idempotent_task_v1");
const {createExactResultCacheV1} = require("./exact_result_cache_v1");
const {buildCachedSimpleAgentInputV1} = require("../stylist/simple_stylist_prompt_cache_v1");
const {buildModelInputV1, normalizeRequestV1, createOpenAiSimpleAgentExecutorV1,
  createSimpleStylistAgentV1} = require("../stylist/simple_stylist_agent_v1");
const {createGeminiClothingAnalyzerClient} =
  require("../clothing_vision/gemini_clothing_analyzer_client");

const logger = {info() {}, warn() {}};
const date = Date.parse("2026-09-02T12:00:00Z");
const usage = {input_tokens: 10000, output_tokens: 2000,
  input_tokens_details: {cached_tokens: 6000, cache_write_tokens: 3000},
  output_tokens_details: {reasoning_tokens: 1500}};

test("Sol accounts separately for uncached/read/write tokens without double billing reasoning", () => {
  const result = openAiUsageV1({model: "gpt-5.6-sol", usage, now: date});
  assert.equal(result.estimatedCostUsd, 0.0614);
  assert.equal(result.usageComplete, true);
  assert.equal(result.reasoningTokens, 1500);
});

test("absent or invalid usage is unknown, absent write counter gives an honest range", () => {
  assert.equal(openAiUsageV1({model: "gpt-5.6-sol", now: date}).estimatedCostUsd, null);
  const result = openAiUsageV1({model: "gpt-5.6-sol", now: date,
    usage: {...usage, input_tokens_details: {cached_tokens: 6000}}});
  assert.equal(result.estimatedCostUsd, null);
  assert.equal(result.estimatedCostUsdMin, 0.0584);
  assert.equal(result.estimatedCostUsdMax, 0.0624);
  for (const input of [-1, "10000", NaN, Infinity]) {
    assert.equal(openAiUsageV1({model: "gpt-5.6-sol", now: date,
      usage: {...usage, input_tokens: input}}).estimatedCostUsd, null);
  }
  assert.equal(openAiUsageV1({model: "gpt-5.6-sol", now: date,
    usage: {...usage, input_tokens: 100}}).estimatedCostUsd, null);
});

test("unknown models and expired launch price estimates never pretend to cost zero", () => {
  assert.equal(openAiUsageV1({model: "new-model", usage, now: date}).estimatedCostUsd, null);
  assert.equal(openAiUsageV1({model: "gpt-5.6-sol", usage,
    now: Date.parse("2026-11-22")}).estimatedCostUsd, null);
  assert.equal(openAiUsageV1({model: "gpt-4o-mini-2024-07-18", now: date,
    usage: {prompt_tokens: 1000, completion_tokens: 100,
      prompt_tokens_details: {cached_tokens: 0}}}).estimatedCostUsd, 0.00021);
});

test("Gemini Flash estimate uses Flash rates, cached input and separate thoughts", () => {
  assert.equal(geminiUsageV1({promptTokenCount: 1000, candidatesTokenCount: 100,
    thoughtsTokenCount: 200, cachedContentTokenCount: 400}).estimatedCostUsd, 0.00366);
  assert.equal(geminiUsageV1(null).estimatedCostUsd, null);
  assert.equal(geminiUsageV1({promptTokenCount: 1000}).estimatedCostUsd, null);
});

function inventoryItem(id, color = "black") {
  return {id, name: "Tričko", ontologyVersion: "2.0.0", canonicalType: "t_shirt",
    canonicalFamily: "tops", bodySlots: ["upper_body"], layerPosition: "base",
    colorProfile: {primary: {family: color}, accents: [{family: "red"}]}};
}
function input(overrides = {}) {
  return buildModelInputV1(normalizeRequestV1({message: "ahoj",
    wardrobeItems: [inventoryItem("b"), inventoryItem("a")],
    currentOutfitItemIds: [], ...overrides}));
}
const textOf = (message) => message.content[0].text;

test("cache preserves full inventory including accents and keeps turn/history outside breakpoints", () => {
  const first = input();
  const second = input({message: "vyber mi outfit", history: [{role: "user", content: "ahoj"}],
    weatherContext: {tomorrow: {noonTempC: 24}}});
  const cachedA = buildCachedSimpleAgentInputV1(first, "owner-a");
  const cachedB = buildCachedSimpleAgentInputV1(second, "owner-a");
  assert.deepEqual(cachedA.input.slice(0, 2), cachedB.input.slice(0, 2));
  assert.notEqual(cachedA.input[2].content, cachedB.input[2].content);
  assert.equal(cachedA.input[1].role, "user");
  assert.equal(textOf(cachedA.input[0]), first.messages[0].content);
  const original = JSON.parse(first.messages[1].content);
  const rebuilt = {...JSON.parse(cachedA.input[2].content),
    ...JSON.parse(textOf(cachedA.input[1]))};
  assert.deepEqual(rebuilt, {...original, wardrobeV2: [...original.wardrobeV2].reverse()});
  assert.deepEqual(rebuilt.wardrobeV2[0].accentColors, ["red"]);
  assert.deepEqual(cachedA.prompt_cache_options, {mode: "explicit", ttl: "30m"});
  assert.equal(typeof cachedA.input[2].content, "string");
  assert.ok(!cachedA.prompt_cache_key.includes("owner-a"));
  assert.notEqual(cachedA.prompt_cache_key,
    buildCachedSimpleAgentInputV1(first, "owner-b").prompt_cache_key);
});

test("ordering is stable; edit, add, delete and same-count replacement change inventory prefix", () => {
  const baseline = buildCachedSimpleAgentInputV1(input(), "owner");
  const reordered = buildCachedSimpleAgentInputV1(input({
    wardrobeItems: [inventoryItem("a"), inventoryItem("b")]}), "owner");
  assert.equal(textOf(baseline.input[1]), textOf(reordered.input[1]));
  for (const wardrobeItems of [
    [inventoryItem("a"), inventoryItem("b", "white")],
    [inventoryItem("a"), inventoryItem("b"), inventoryItem("c")],
    [inventoryItem("a")], [inventoryItem("a"), inventoryItem("c")],
  ]) {
    const changed = buildCachedSimpleAgentInputV1(input({wardrobeItems}), "owner");
    assert.notEqual(textOf(baseline.input[1]), textOf(changed.input[1]));
  }
});

test("transport meters paid malformed/repair outputs and sends explicit cache controls", async () => {
  const events = [];
  const requests = [];
  let count = 0;
  const executor = createOpenAiSimpleAgentExecutorV1({logger, resolveOpenAISecret: () => "not-real",
    recordUsage: async (event) => events.push(event), fetchImpl: async (_, options) => {
      requests.push(JSON.parse(options.body));
      return {ok: true, status: 200, json: async () => ({usage,
        output_text: ++count === 1 ? "bad json" : JSON.stringify({stylistComment: "Ahoj!",
          resultingOutfitItemIds: [], displayItemIds: [], outfitRequested: false,
          outfitChanged: false, weatherContextKey: "none", hardRequirementEvidence: [],
          commentGroundingEvidence: []})})};
    }});
  const agent = createSimpleStylistAgentV1({executeModel: executor, logger});
  const result = await agent.resolve({message: "ahoj", wardrobeItems: [], currentOutfitItemIds: []});
  assert.equal(result.stylistComment, "Ahoj!");
  assert.equal(events.length, 2);
  assert.deepEqual(events.map((event) => event.modelAttempt), [1, 2]);
  assert.notEqual(events[0].eventId, events[1].eventId);
  assert.equal(requests[0].model, "gpt-5.6-sol");
  assert.equal(requests[0].reasoning.effort, "medium");
  assert.equal(requests[0].prompt_cache_options.mode, "explicit");
  assert.deepEqual(requests[0].input.slice(0, 2), requests[1].input.slice(0, 2));
  assert.ok(!JSON.stringify(events).includes("not-real"));
  assert.ok(!JSON.stringify(events).includes("stylistComment"));
});

test("network failure and HTTP retry are metered as unknown if usage is absent", async () => {
  for (const networkFailure of [true, false]) {
    const events = [];
    let count = 0;
    const execute = createOpenAiSimpleAgentExecutorV1({logger, resolveOpenAISecret: () => "test",
      sleepImpl: async () => {}, recordUsage: async (event) => events.push(event),
      fetchImpl: async () => {
        count++;
        if (networkFailure) throw new Error("offline");
        return {ok: false, status: 500, json: async () => ({})};
      }});
    await assert.rejects(execute(input()));
    assert.equal(count, networkFailure ? 1 : 2);
    assert.equal(events.length, count);
    assert.ok(events.every((event) => event.estimatedCostUsd === null));
  }
});

// Serialized transactions emulate exclusive Firestore admission across two
// independent runner instances. No global in-memory lock in production code.
function database() {
  const records = new Map();
  let queue = Promise.resolve();
  const db = {collection: (name) => ({doc: (id) => {
    const key = `${name}/${id}`;
    return {key, get: async () => ({exists: records.has(key), data: () => records.get(key)}),
      set: async (value) => records.set(key, structuredClone(value)),
      create: async (value) => {
        if (records.has(key)) throw Object.assign(new Error("exists"), {code: 6});
        records.set(key, structuredClone(value));
      },
      update: async (value) => records.set(key, {...records.get(key), ...structuredClone(value)})};
  }}), runTransaction: (fn) => {
    const work = queue.then(() => fn({get: (ref) => ref.get(), set: (ref, value) => ref.set(value)}));
    queue = work.catch(() => {});
    return work;
  }};
  return {db, records};
}

test("duplicate completed job replays result without another paid call", async () => {
  const {db, records} = database();
  const run = createIdempotentTaskRunnerV1({db, logger});
  let count = 0;
  const task = {uid: "u1", feature: "chat", requestId: "job-1", payload: {message: "hello"},
    execute: async () => ({answer: ++count})};
  assert.deepEqual(await run(task), {result: {answer: 1}, replayed: false});
  assert.deepEqual(await run(task), {result: {answer: 1}, replayed: true});
  assert.equal(count, 1);
  assert.ok([...records.keys()].every((key) => key.startsWith("aiTaskRunsV1/")));
  await assert.rejects(run({...task, payload: {message: "different"}}), {code: "request_id_conflict"});
  await run({...task, uid: "u2"});
  await run({...task, requestId: "job-2"});
  assert.equal(count, 3);
});

test("concurrent requests from separate instances admit only one paid operation", async () => {
  const {db} = database();
  const runA = createIdempotentTaskRunnerV1({db, logger});
  const runB = createIdempotentTaskRunnerV1({db, logger});
  let release;
  const gate = new Promise((resolve) => { release = resolve; });
  let started;
  const admitted = new Promise((resolve) => { started = resolve; });
  let count = 0;
  const task = {uid: "u", feature: "chat", requestId: "job", payload: {},
    execute: async () => { count++; started(); await gate; return {ok: true}; }};
  const first = runA(task);
  await admitted;
  await assert.rejects(runB(task), {code: "request_in_progress_or_unknown"});
  release();
  await first;
  assert.equal((await runB(task)).replayed, true);
  assert.equal(count, 1);
});

test("failed and crash-ambiguous tasks are not automatically charged again", async () => {
  const {db, records} = database();
  const run = createIdempotentTaskRunnerV1({db, logger});
  let count = 0;
  const task = {uid: "u", feature: "chat", requestId: "job", payload: {},
    execute: async () => { count++; throw new Error("provider_ambiguous"); }};
  await assert.rejects(run(task));
  await assert.rejects(run(task), {code: "request_previously_failed"});
  const record = [...records.values()][0];
  record.status = "running";
  record.createdAt = new Date(0);
  await assert.rejects(run(task), {code: "request_in_progress_or_unknown"});
  assert.equal(count, 1);
  await assert.rejects(run({...task, requestId: "../../bad"}), {code: "invalid_request_id"});
});

test("exact analysis cache checks full inputs, identity, prompt/model and expiry", async () => {
  const {db} = database();
  let clock = date;
  const cache = createExactResultCacheV1({db, logger, now: () => clock});
  let calls = 0;
  const query = {uid: "u", feature: "analysis", input: {model: "mini", summary: {red: 1, blue: 1}},
    execute: async () => ({count: ++calls}), isCacheable: (result) => result?.count > 0, ttlMs: 100};
  await cache(query);
  await cache({...query, input: {summary: {blue: 1, red: 1}, model: "mini"}});
  assert.equal(calls, 1);
  await cache({...query, input: {model: "mini", summary: {red: 0, blue: 2}}});
  await cache({...query, input: {...query.input, model: "other"}});
  await cache({...query, uid: "other-user"});
  assert.equal(calls, 4);
  await cache(query);
  clock += 101;
  await cache(query);
  assert.equal(calls, 6);
});

test("analysis single-flight merges concurrent calls but does not retain failures", async () => {
  const {db} = database();
  const cache = createExactResultCacheV1({db, logger});
  let calls = 0;
  const query = {uid: "u", feature: "analysis", input: {},
    execute: async () => { calls++; return null; }, isCacheable: (result) => result != null};
  await Promise.all([cache(query), cache(query)]);
  assert.equal(calls, 1);
  await cache(query);
  assert.equal(calls, 2);
});

test("usage persistence deduplicates events and survives write outages", async () => {
  const {db, records} = database();
  const record = createAiUsageRecorderV1({db, logger});
  const event = {eventId: "e1", estimatedCostUsd: 0.01};
  await record(event);
  await record(event);
  assert.equal(records.size, 1);
  await createAiUsageRecorderV1({db: {collection() { throw new Error("offline"); }}, logger})(event);
});

test("Gemini includes paid truncation attempt and thoughts in total estimate", async () => {
  const events = [];
  let calls = 0;
  const client = createGeminiClothingAnalyzerClient({getApiKey: () => "test",
    logger, recordUsage: async (event) => events.push(event), fetchImpl: async () => {
      calls++;
      return {ok: true, status: 200, json: async () => ({
        candidates: [{finishReason: calls === 1 ? "MAX_TOKENS" : "STOP",
          content: {parts: [{text: calls === 1 ? '{"unfinished":' : '{"ok":true}'}]}}],
        usageMetadata: {promptTokenCount: 1000, candidatesTokenCount: 100, thoughtsTokenCount: 200},
      })};
    }});
  const result = await client.analyze({mimeType: "image/jpeg", imageBase64: "a".repeat(40)});
  assert.equal(events.length, 2);
  assert.equal(result.telemetry.inputTokens, 2000);
  assert.equal(result.telemetry.reasoningTokens, 400);
  assert.equal(result.telemetry.estimatedCostUsd, 0.0084);
  assert.equal(result.telemetry.usageComplete, true);
});

test("Home/analysis metering preserves Response and records failed requests too", async () => {
  const {createMeteredOpenAiFetchV1} = require("./metered_openai_fetch_v1");
  const events = [];
  const payload = {usage, choices: [{message: {content: "private answer"}}]};
  const call = createMeteredOpenAiFetchV1({logger,
    recordUsage: async (event) => events.push(event),
    fetchImpl: async () => new Response(JSON.stringify(payload), {status: 200})});
  const response = await call("https://example.test", {},
    {uid: "owner", feature: "home_outfit", model: "gpt-4o-mini"});
  assert.deepEqual(await response.json(), payload);
  assert.equal(events.length, 1);
  assert.ok(!JSON.stringify(events).includes("private answer"));
  const fail = createMeteredOpenAiFetchV1({logger,
    recordUsage: async (event) => events.push(event),
    fetchImpl: async () => { throw new Error("network"); }});
  await assert.rejects(fail("https://example.test", {},
    {uid: "owner", feature: "home_outfit", model: "gpt-4o-mini"}));
  assert.equal(events[1].estimatedCostUsd, null);
});

test("cheaper-model evaluation is opt-in, bounded and cannot change production model", async () => {
  const {runEvaluation} = require("../stylist/simple_stylist_cost_eval_v1");
  await assert.rejects(runEvaluation({models: ["unknown"], apiKey: "test"}), /unsupported_eval_model/);
  await assert.rejects(runEvaluation({}), /configured_OPENAI_API_KEY_required/);
  await assert.rejects(runEvaluation({apiKey: "test", maxUsd: 100}), /invalid_eval_budget/);
  let calls = 0;
  await assert.rejects(runEvaluation({apiKey: "test", maxRequests: 1,
    fetchImpl: async () => {
      calls++;
      return {ok: true, status: 200, json: async () => ({usage, output_text: JSON.stringify({
        stylistComment: "Ahoj!", resultingOutfitItemIds: [], displayItemIds: [],
        outfitChanged: false, outfitRequested: false, weatherContextKey: "none",
        hardRequirementEvidence: [], commentGroundingEvidence: [], selectionReasons: [],
      })})};
    }}), /eval_budget_exhausted/);
  assert.equal(calls, 1);
  assert.equal(require("../stylist/simple_stylist_agent_v1").SIMPLE_AGENT_MODEL, "gpt-5.6-sol");
});
