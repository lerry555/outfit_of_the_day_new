"use strict";

const {
  createOpenAiRoleTransport,
  createAnthropicExplanationTransport,
  ROLE_MODELS,
} = require("./role_transport_v1");

const FACTORY_MODES = Object.freeze({disabled: "disabled", realDevShadow: "real_dev_shadow"});

function createDisabledDevShadowProviderFactory() {
  const disabled = (role) => Object.freeze({
    role,
    modelId: ROLE_MODELS[role].modelId,
    async run() { return Object.freeze({ok: false, failureCode: "provider_factory_disabled"}); },
  });
  return Object.freeze({
    mode: FACTORY_MODES.disabled,
    contextClient: disabled("contextClarification"),
    decisionClient: disabled("finalCandidateDecision"),
    explanationClient: disabled("explanation"),
    fallbackProviderCallsEnabled: false,
  });
}

function createRealDevShadowProviderFactory({
  budget,
  execute,
  resolveOpenAISecret,
  resolveAnthropicSecret,
} = {}) {
  if (!budget || typeof budget.claim !== "function" || typeof execute !== "function" ||
      typeof resolveOpenAISecret !== "function" ||
      typeof resolveAnthropicSecret !== "function") {
    throw new Error("real_dev_shadow_dependencies_missing");
  }
  const budgeted = (role) => async (request) => {
    const claim = budget.claim(role);
    try {
      const response = await execute(request);
      return Object.freeze({...response,
        providerCallNumber: claim.providerCallNumber});
    } catch (error) {
      error.providerCallNumber = claim.providerCallNumber;
      throw error;
    }
  };
  return Object.freeze({
    mode: FACTORY_MODES.realDevShadow,
    contextClient: createOpenAiRoleTransport({
      role: "contextClarification",
      credentialProvider: resolveOpenAISecret,
      execute: budgeted("contextClarification"),
    }),
    decisionClient: createOpenAiRoleTransport({
      role: "finalCandidateDecision",
      credentialProvider: resolveOpenAISecret,
      execute: budgeted("finalCandidateDecision"),
    }),
    explanationClient: createAnthropicExplanationTransport({
      credentialProvider: resolveAnthropicSecret,
      execute: budgeted("explanation"),
    }),
    fallbackProviderCallsEnabled: false,
  });
}

function createNoRetryFetchExecutor({fetchImpl = globalThis.fetch} = {}) {
  if (typeof fetchImpl !== "function") throw new Error("fetch_executor_missing");
  return async (request) => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), request.timeoutMs);
    try {
      const response = await fetchImpl(request.url, {
        method: request.method,
        headers: {...request.headers, "content-type": "application/json"},
        body: JSON.stringify(request.body),
        signal: controller.signal,
      });
      let json = null;
      try { json = await response.json(); } catch (_) {
        return Object.freeze({ok: false, status: response.status,
          code: "structured_output_invalid"});
      }
      return Object.freeze({ok: response.ok, status: response.status, json});
    } finally {
      clearTimeout(timer);
    }
  };
}

module.exports = {
  FACTORY_MODES,
  createDisabledDevShadowProviderFactory,
  createRealDevShadowProviderFactory,
  createNoRetryFetchExecutor,
};
