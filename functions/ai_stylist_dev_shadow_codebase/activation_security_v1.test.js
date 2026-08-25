"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {createSmokeInferenceBudget} = require("./inference_budget_v1");
const {
  createDisabledDevShadowProviderFactory,
  createRealDevShadowProviderFactory,
} = require("./provider_factory_v1");
const {
  deterministicSmokeFixture,
  runControlledDevShadowSmoke,
} = require("./smoke_orchestration_v1");
const {
  ENABLED_MODE,
  FIXTURE_ID,
  createDevShadowSmokeHandler,
} = require("./callable_v1");
const {
  OPENAI_SECRET_NAME,
  ANTHROPIC_SECRET_NAME,
  OPENAI_API_KEY_SECRET,
  ANTHROPIC_API_KEY_SECRET,
  resolveOpenAISecret,
  resolveAnthropicSecret,
} = require("./secret_bindings_v1");

const TEST_OPENAI = "test-only-openai-credential";
const TEST_ANTHROPIC = "test-only-anthropic-credential";

function jsonResponse(model, value, providerCallNumber) {
  return {ok: true, status: 200, providerCallNumber, json: {
    model,
    choices: [{message: {content: JSON.stringify(value)}}],
  }};
}
function anthropicResponse(value, providerCallNumber) {
  return {ok: true, status: 200, providerCallNumber, json: {
    model: "claude-sonnet-5",
    content: [{type: "text", text: JSON.stringify(value)}],
  }};
}
function successExecutor({decision = "select", explanation = {explanation: "Bezpečný výber."}} = {}) {
  return async (request) => {
    if (request.body.model === "gpt-4o") {
      return jsonResponse("gpt-4o", {action: "proceed",
        acceptedKnownFactKeys: Object.keys(deterministicSmokeFixture().knownContext)});
    }
    if (request.body.model === "gpt-5.4-mini") {
      const value = decision === "reject" ?
        {action: "reject_all", selectedCandidateId: null} :
        {action: "select_candidate", selectedCandidateId: "fixture-candidate-olive"};
      return jsonResponse("gpt-5.4-mini", value);
    }
    return anthropicResponse(explanation);
  };
}
function realFactory(budget, execute) {
  return createRealDevShadowProviderFactory({
    budget,
    execute,
    resolveOpenAISecret: async () => TEST_OPENAI,
    resolveAnthropicSecret: async () => TEST_ANTHROPIC,
  });
}

test("secret declarations bind names without reading values", () => {
  assert.equal(OPENAI_SECRET_NAME, "OPENAI_API_KEY");
  assert.equal(ANTHROPIC_SECRET_NAME, "ANTHROPIC_API_KEY");
  assert.equal(OPENAI_API_KEY_SECRET.name, OPENAI_SECRET_NAME);
  assert.equal(ANTHROPIC_API_KEY_SECRET.name, ANTHROPIC_SECRET_NAME);
  assert.equal(resolveOpenAISecret({value: () => TEST_OPENAI}), TEST_OPENAI);
  assert.equal(resolveAnthropicSecret({value: () => TEST_ANTHROPIC}), TEST_ANTHROPIC);
});

test("provider factory defaults to no-network disabled clients", async () => {
  const factory = createDisabledDevShadowProviderFactory();
  assert.equal(factory.mode, "disabled");
  assert.equal(factory.fallbackProviderCallsEnabled, false);
  assert.deepEqual(await factory.contextClient.run({}), {
    ok: false, failureCode: "provider_factory_disabled",
  });
});

test("hard budget permits three role dispatches and blocks fourth before executor", async () => {
  const budget = createSmokeInferenceBudget();
  let executorCalls = 0;
  const guarded = async (role) => {
    budget.claim(role);
    executorCalls += 1;
  };
  await guarded("contextClarification");
  await guarded("finalCandidateDecision");
  await guarded("explanation");
  assert.equal(executorCalls, 3);
  assert.throws(() => budget.claim("explanation"), /smoke_budget_exhausted/);
  assert.equal(executorCalls, 3);
});

test("timeout makes one dispatch and never retries or invokes a fallback", async () => {
  const budget = createSmokeInferenceBudget();
  let calls = 0;
  const providers = realFactory(budget, async () => {
    calls += 1;
    const error = new Error("redacted");
    error.name = "AbortError";
    throw error;
  });
  const result = await providers.contextClient.run({contractVersion: 1});
  assert.equal(result.ok, false);
  assert.equal(result.failureCode, "timeout");
  assert.equal(calls, 1);
  assert.equal(budget.snapshot().dispatchCount, 1);
  assert.equal(providers.fallbackProviderCallsEnabled, false);
});

test("malformed provider output makes no repair call", async () => {
  const budget = createSmokeInferenceBudget();
  let calls = 0;
  const providers = realFactory(budget, async () => {
    calls += 1;
    return {ok: true, status: 200, json: {
      model: "gpt-4o", choices: [{message: {content: "not-json"}}],
    }};
  });
  const result = await providers.contextClient.run({contractVersion: 1});
  assert.equal(result.failureCode, "structured_output_invalid");
  assert.equal(calls, 1);
});

test("provider-reported model metadata is allowlisted before observability", async () => {
  const budget = createSmokeInferenceBudget();
  const providers = realFactory(budget, async () => ({
    ok: true,
    status: 200,
    json: {
      model: "model name with unsafe metadata",
      choices: [{message: {content: JSON.stringify({action: "proceed"})}}],
    },
  }));
  const result = await providers.contextClient.run({contractVersion: 1});
  assert.equal(result.ok, true);
  assert.equal(result.actualModel, null);
});

test("full real-transport composition cannot replace legacy selection or explanation", async () => {
  const budget = createSmokeInferenceBudget();
  const legacy = {selectedCandidateId: "legacy-id", explanation: "Legacy text",
    persistenceRevision: "same"};
  const result = await runControlledDevShadowSmoke({
    runId: "dev-shadow-authority-proof",
    providers: realFactory(budget, successExecutor()),
    budget,
    legacyResult: legacy,
  });
  assert.strictEqual(result.authoritativeLegacyResult, legacy);
  assert.equal(result.authoritative, false);
  assert.equal(result.authority, "shadow");
  assert.equal(result.authoritativeLegacyResult.selectedCandidateId, "legacy-id");
  assert.equal(result.authoritativeLegacyResult.explanation, "Legacy text");
  assert.equal(result.authoritativeLegacyResult.persistenceRevision, "same");
  assert.equal(result.shadowResult.effectiveDecision.selectedCandidateId,
    "fixture-candidate-olive");
  assert.equal(result.shadowResult.persistenceWrites, 0);
  assert.equal(result.inferenceBudget.dispatchCount, 3);
  assert.deepEqual(result.trace.map((entry) => entry.providerCallNumber), [1, 2, 3]);
});

test("shadow reject_all never erases the legacy outfit", async () => {
  const budget = createSmokeInferenceBudget();
  const legacy = {selectedCandidateId: "legacy-id", explanation: "Legacy text"};
  const result = await runControlledDevShadowSmoke({
    runId: "dev-shadow-reject-proof",
    providers: realFactory(budget, successExecutor({decision: "reject"})),
    budget,
    legacyResult: legacy,
  });
  assert.strictEqual(result.authoritativeLegacyResult, legacy);
  assert.equal(result.shadowResult.effectiveDecision.action, "reject_all");
  assert.equal(result.shadowResult.effectiveDecision.selectedCandidateId, null);
  assert.equal(result.authoritativeLegacyResult.selectedCandidateId, "legacy-id");
});

test("decision provider failure stays reject_all and cannot select candidate zero", async () => {
  const budget = createSmokeInferenceBudget();
  let call = 0;
  const execute = async (request) => {
    call += 1;
    if (call === 1) return successExecutor()(request);
    if (call === 2) {
      const error = new Error("redacted");
      error.name = "AbortError";
      throw error;
    }
    return anthropicResponse({explanation: "Bez výberu."});
  };
  const legacy = {selectedCandidateId: "legacy-id", explanation: "Legacy text"};
  const result = await runControlledDevShadowSmoke({
    runId: "dev-shadow-failure-proof",
    providers: realFactory(budget, execute), budget, legacyResult: legacy,
  });
  assert.equal(result.shadowResult.effectiveDecision.action, "reject_all");
  assert.equal(result.shadowResult.effectiveDecision.selectedCandidateId, null);
  assert.notEqual(result.shadowResult.effectiveDecision.selectedCandidateId,
    deterministicSmokeFixture().frozenCandidates[0].candidateId);
  assert.strictEqual(result.authoritativeLegacyResult, legacy);
  assert.equal(call, 3);
});

function fakeFunctionsApi() {
  class HttpsError extends Error {
    constructor(code, message) { super(message); this.code = code; }
  }
  return {https: {HttpsError}};
}

test("callable is disabled before factory or credential resolution", async () => {
  let factoryCalls = 0;
  const handler = createDevShadowSmokeHandler({
    functionsApi: fakeFunctionsApi(),
    modeResolver: () => "disabled",
    providerFactory: () => { factoryCalls += 1; throw new Error("must_not_run"); },
    runIdFactory: () => "dev-shadow-disabled",
  });
  await assert.rejects(handler({}, {}), /ai_stylist_dev_shadow_disabled/);
  assert.equal(factoryCalls, 0);
});

test("enabled callable requires auth, App Check, claim and exact fixture input", async () => {
  const base = {
    functionsApi: fakeFunctionsApi(), modeResolver: () => ENABLED_MODE,
    providerFactory: () => { throw new Error("must_not_run"); },
    runIdFactory: () => "dev-shadow-gated",
  };
  const handler = createDevShadowSmokeHandler(base);
  await assert.rejects(handler({}, {}), /auth_required/);
  await assert.rejects(handler({}, {auth: {uid: "dev", token: {} }}),
    /app_check_required/);
  await assert.rejects(handler({}, {auth: {uid: "dev", token: {}}, app: {}}),
    /developer_shadow_claim_required/);
  await assert.rejects(handler({contractVersion: 1, fixtureId: FIXTURE_ID,
    confirmNonAuthoritative: false},
  {auth: {uid: "dev", token: {aiStylistDevShadow: true}}, app: {}}),
  /dev_shadow_fixture_request_invalid/);
});

test("enabled callable composes real transport classes with fake network as shadow only", async () => {
  const logged = [];
  const handler = createDevShadowSmokeHandler({
    functionsApi: fakeFunctionsApi(),
    modeResolver: () => ENABLED_MODE,
    providerFactory: ({budget}) => realFactory(budget, successExecutor()),
    runIdFactory: () => "dev-shadow-callable-proof",
    logger: {info: (name, event) => logged.push({name, event}), error() {}},
  });
  const result = await handler({
    contractVersion: 1,
    fixtureId: FIXTURE_ID,
    confirmNonAuthoritative: true,
  }, {
    auth: {uid: "not-serialized", token: {aiStylistDevShadow: true}},
    app: {appId: "not-serialized"},
  });
  assert.equal(result.authoritative, false);
  assert.equal(result.authority, "shadow");
  assert.equal(result.shadowResult.persistenceWrites, 0);
  assert.equal(result.inferenceBudget.dispatchCount, 3);
  assert.equal(logged.length, 3);
  assert.equal(JSON.stringify({result, logged}).includes("not-serialized"), false);
});

test("alternate Firebase config isolates deploy from dirty default Functions source", () => {
  const repoRoot = path.resolve(__dirname, "..", "..");
  const config = JSON.parse(fs.readFileSync(
    path.join(repoRoot, "firebase.ai-stylist-dev-shadow.json"), "utf8"));
  assert.equal(config.functions.source,
    "functions/ai_stylist_dev_shadow_codebase");
  assert.equal(config.functions.codebase, "ai-stylist-dev-shadow");
  const defaultIndex = fs.readFileSync(path.join(repoRoot, "functions", "index.js"),
    "utf8");
  assert.equal(defaultIndex.includes("aiStylistDevShadowSmoke"), false);
  const isolatedIndex = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
  assert.equal(isolatedIndex.includes("../"), false);
  assert.match(isolatedIndex, /exports\[CALLABLE_NAME\]/);
});

test("trace and source contain no credential or raw provider persistence fields", async () => {
  const budget = createSmokeInferenceBudget();
  const result = await runControlledDevShadowSmoke({
    runId: "dev-shadow-redaction-proof",
    providers: realFactory(budget, successExecutor()), budget,
    legacyResult: {selectedCandidateId: "legacy", explanation: "Legacy"},
  });
  const serialized = JSON.stringify(result);
  for (const forbidden of [TEST_OPENAI, TEST_ANTHROPIC, "Authorization",
    "x-api-key", "email", "uid", "rawResponse", "conversationHistory"] ) {
    assert.equal(serialized.includes(forbidden), false, forbidden);
  }
  const source = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
  assert.equal(/sk-[A-Za-z0-9_-]{16,}/.test(source), false);
  assert.equal(/process\.env\.(OPENAI|ANTHROPIC)/.test(source), false);
});
