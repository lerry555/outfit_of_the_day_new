"use strict";

const ROLE_MODELS = Object.freeze({
  contextClarification: Object.freeze({provider: "openai", modelId: "gpt-4o"}),
  finalCandidateDecision: Object.freeze({provider: "openai", modelId: "gpt-5.4-mini"}),
  explanation: Object.freeze({provider: "anthropic", modelId: "claude-sonnet-5"}),
});

const PROVIDER_FAILURE = Object.freeze({
  timeout: "timeout",
  authenticationUnavailable: "authentication_unavailable",
  accessDenied: "access_denied",
  modelUnavailable: "model_unavailable",
  rateLimited: "rate_limited",
  transportError: "transport_error",
  structuredOutputInvalid: "structured_output_invalid",
  contractInvalid: "contract_invalid",
  providerUnavailable: "provider_unavailable",
  unknown: "unknown_provider_failure",
});

const CONTEXT_SCHEMA = Object.freeze({
  type: "object", additionalProperties: false, required: ["action"],
  properties: {
    action: {type: "string", enum: ["proceed", "ask_clarification", "stop"]},
    clarificationFactKey: {type: "string"},
    acceptedKnownFactKeys: {type: "array", items: {type: "string"}},
  },
});
// OpenAI strict Structured Outputs requires every property of an object to
// appear in `required`. The canonical contract intentionally permits omitted
// optional fields, so the provider wire contract uses null as the only
// wire-level representation of an omitted value. Local validation below still
// accepts the canonical omission and remains authoritative.
const OPENAI_CONTEXT_WIRE_SCHEMA = Object.freeze({
  type: "object", additionalProperties: false,
  required: ["action", "clarificationFactKey", "acceptedKnownFactKeys"],
  properties: {
    action: {type: "string", enum: ["proceed", "ask_clarification", "stop"]},
    clarificationFactKey: {type: ["string", "null"]},
    acceptedKnownFactKeys: {
      type: ["array", "null"], items: {type: "string"},
    },
  },
});
const DECISION_SCHEMA = Object.freeze({
  type: "object", additionalProperties: false,
  required: ["action", "selectedCandidateId"],
  properties: {
    action: {type: "string", enum: ["select_candidate", "reject_all"]},
    selectedCandidateId: {type: ["string", "null"]},
  },
});
const EXPLANATION_SCHEMA = Object.freeze({
  type: "object", additionalProperties: false, required: ["explanation"],
  properties: {
    explanation: {type: "string"},
    warnings: {type: "array", items: {type: "string"}},
  },
});

function fail(code) { const error = new Error(code); error.code = code; throw error; }
function text(value) { return typeof value === "string" ? value.trim() : ""; }
const NORMALIZED_REASON = Object.freeze({
  invalidJsonSchema: "INVALID_JSON_SCHEMA",
  invalidRequest: "INVALID_REQUEST",
  modelNotFound: "MODEL_NOT_FOUND",
  accessDenied: "ACCESS_DENIED",
  rateLimited: "RATE_LIMITED",
  authenticationFailed: "AUTHENTICATION_FAILED",
  modelParameterIncompatible: "MODEL_PARAMETER_INCOMPATIBLE",
  structuredOutputIncompatible: "STRUCTURED_OUTPUT_INCOMPATIBLE",
  transportFailure: "TRANSPORT_FAILURE",
  timeout: "TIMEOUT",
  unknown: "UNKNOWN",
});

function safeProviderIdentifier(value) {
  const candidate = text(value);
  if (!/^[A-Za-z0-9_.:-]{1,80}$/.test(candidate)) return null;
  if (/(?:^|[-_.])(sk|api|token|key)[-_]?[A-Za-z0-9]{8,}/i.test(candidate)) return null;
  return candidate;
}
function safeHttpStatus(value) {
  const status = Number(value);
  return Number.isInteger(status) && status >= 100 && status <= 599 ? status : null;
}
function safeProviderDiagnostics(input, fallbackReason = NORMALIZED_REASON.unknown) {
  const envelope = input && input.json && typeof input.json === "object" ? input.json : {};
  const error = envelope && envelope.error && typeof envelope.error === "object" ? envelope.error : {};
  const providerErrorType = safeProviderIdentifier(error.type || envelope.type);
  const providerErrorCode = safeProviderIdentifier(error.code || envelope.code || input && input.code);
  const offendingParameter = safeProviderIdentifier(error.param || error.parameter ||
    envelope.param || envelope.parameter);
  const httpStatus = safeHttpStatus(input && input.status);
  const lowerType = text(providerErrorType).toLowerCase();
  const lowerCode = text(providerErrorCode).toLowerCase();
  const lowerParameter = text(offendingParameter).toLowerCase();
  let normalizedReason = fallbackReason;
  if (httpStatus === 401) normalizedReason = NORMALIZED_REASON.authenticationFailed;
  else if (httpStatus === 403) normalizedReason = NORMALIZED_REASON.accessDenied;
  else if (httpStatus === 404 || lowerCode.includes("model")) {
    normalizedReason = NORMALIZED_REASON.modelNotFound;
  } else if (httpStatus === 429) normalizedReason = NORMALIZED_REASON.rateLimited;
  else if (lowerCode.includes("json_schema") || lowerCode.includes("schema_invalid")) {
    normalizedReason = NORMALIZED_REASON.invalidJsonSchema;
  } else if (lowerParameter === "response_format" || lowerParameter === "json_schema") {
    normalizedReason = NORMALIZED_REASON.structuredOutputIncompatible;
  } else if (["max_tokens", "max_completion_tokens", "temperature", "reasoning_effort"].includes(lowerParameter)) {
    normalizedReason = NORMALIZED_REASON.modelParameterIncompatible;
  } else if (httpStatus === 400 || lowerType === "invalid_request_error") {
    normalizedReason = NORMALIZED_REASON.invalidRequest;
  } else if (httpStatus != null && httpStatus >= 500) {
    normalizedReason = NORMALIZED_REASON.transportFailure;
  }
  return Object.freeze({httpStatus, providerErrorType, providerErrorCode,
    offendingParameter, normalizedReason});
}
function frozenFailure(code, callNumber = null, diagnostics = null) {
  const result = {ok: false, failureCode: code};
  if (Number.isInteger(callNumber)) result.providerCallNumber = callNumber;
  if (diagnostics) result.providerDiagnostics = diagnostics;
  return Object.freeze(result);
}

function normalizeProviderFailure(input) {
  const status = safeHttpStatus(input && input.status);
  const code = text(input && input.code).toLowerCase();
  const name = text(input && input.name).toLowerCase();
  const callNumber = Number.isInteger(input && input.providerCallNumber) ?
    input.providerCallNumber : null;
  if (name === "aborterror" || code === "timeout" || status === 408 || status === 504) {
    return frozenFailure(PROVIDER_FAILURE.timeout, callNumber,
      safeProviderDiagnostics(input, NORMALIZED_REASON.timeout));
  }
  if (code === "authentication_unavailable" || status === 401) {
    return frozenFailure(PROVIDER_FAILURE.authenticationUnavailable, callNumber,
      safeProviderDiagnostics(input, NORMALIZED_REASON.authenticationFailed));
  }
  if (status === 403) return frozenFailure(PROVIDER_FAILURE.accessDenied, callNumber,
    safeProviderDiagnostics(input, NORMALIZED_REASON.accessDenied));
  if (status === 404 || code.includes("model")) {
    return frozenFailure(PROVIDER_FAILURE.modelUnavailable, callNumber,
      safeProviderDiagnostics(input, NORMALIZED_REASON.modelNotFound));
  }
  if (status === 429) return frozenFailure(PROVIDER_FAILURE.rateLimited, callNumber,
    safeProviderDiagnostics(input, NORMALIZED_REASON.rateLimited));
  if (status >= 500 && status <= 599) {
    return frozenFailure(PROVIDER_FAILURE.providerUnavailable, callNumber,
      safeProviderDiagnostics(input, NORMALIZED_REASON.transportFailure));
  }
  if (code === "structured_output_invalid") {
    return frozenFailure(PROVIDER_FAILURE.structuredOutputInvalid, callNumber,
      safeProviderDiagnostics(input, NORMALIZED_REASON.structuredOutputIncompatible));
  }
  if (code === "contract_invalid") {
    return frozenFailure(PROVIDER_FAILURE.contractInvalid, callNumber,
      safeProviderDiagnostics(input, NORMALIZED_REASON.invalidRequest));
  }
  if (code === "transport_error" || name === "typeerror") {
    return frozenFailure(PROVIDER_FAILURE.transportError, callNumber,
      safeProviderDiagnostics(input, NORMALIZED_REASON.transportFailure));
  }
  const diagnostics = safeProviderDiagnostics(input);
  if (diagnostics.normalizedReason === NORMALIZED_REASON.invalidJsonSchema ||
      diagnostics.normalizedReason === NORMALIZED_REASON.structuredOutputIncompatible) {
    return frozenFailure(PROVIDER_FAILURE.structuredOutputInvalid, callNumber, diagnostics);
  }
  if (diagnostics.normalizedReason === NORMALIZED_REASON.modelParameterIncompatible ||
      diagnostics.normalizedReason === NORMALIZED_REASON.invalidRequest) {
    return frozenFailure(PROVIDER_FAILURE.contractInvalid, callNumber, diagnostics);
  }
  return frozenFailure(PROVIDER_FAILURE.unknown, callNumber, diagnostics);
}
function normalizeLocalContractFailure(error, callNumber) {
  const code = text(error && error.code);
  if (code === PROVIDER_FAILURE.structuredOutputInvalid) {
    return frozenFailure(PROVIDER_FAILURE.structuredOutputInvalid, callNumber);
  }
  if (code === PROVIDER_FAILURE.contractInvalid) {
    return frozenFailure(PROVIDER_FAILURE.contractInvalid, callNumber);
  }
  return normalizeProviderFailure({...error, providerCallNumber: callNumber});
}

function safeJson(value) {
  try { return JSON.stringify(value); } catch (_) { fail("canonical_payload_not_serializable"); }
}

function openAiBody({role, canonicalPayload}) {
  const model = ROLE_MODELS[role];
  if (!model || model.provider !== "openai") fail("openai_role_invalid");
  const schema = role === "contextClarification" ? OPENAI_CONTEXT_WIRE_SCHEMA : DECISION_SCHEMA;
  const body = {
    model: model.modelId,
    response_format: {type: "json_schema", json_schema: {
      name: role === "contextClarification" ?
        "ootd_context_v1" : "ootd_frozen_decision_v1",
      strict: true, schema,
    }},
    messages: [
      {role: "system", content: role === "contextClarification" ?
        "Interpret only supplied context facts and obey the strict response schema." :
        "Select only from the frozen candidate IDs or reject_all; never use an index."},
      {role: "user", content: safeJson(canonicalPayload)},
    ],
  };
  if (role === "contextClarification") {
    body.max_tokens = 400;
    body.temperature = 0;
  } else {
    body.max_completion_tokens = 160;
    body.reasoning_effort = "none";
  }
  return Object.freeze(body);
}

// Kept byte-semantically aligned with the successful Track R Anthropic wire
// transform. In particular, `additionalProperties: false` remains on the
// provider schema; only constraints the constrained decoder does not accept
// are removed. The canonical schema remains authoritative after parsing.
const ANTHROPIC_UNSUPPORTED_CONSTRAINTS = new Set([
  "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf",
  "minLength", "maxLength", "pattern", "format",
  "minItems", "maxItems", "uniqueItems",
]);
function simplifyAnthropicSchema(node) {
  if (Array.isArray(node)) return node.map(simplifyAnthropicSchema);
  if (!node || typeof node !== "object") return node;
  const converted = {};
  for (const [key, value] of Object.entries(node)) {
    if (ANTHROPIC_UNSUPPORTED_CONSTRAINTS.has(key)) continue;
    converted[key === "oneOf" ? "anyOf" : key] = simplifyAnthropicSchema(value);
  }
  return converted;
}

function anthropicBody({canonicalPayload}) {
  return Object.freeze({
    model: ROLE_MODELS.explanation.modelId,
    max_tokens: 500,
    output_config: {format: {
      type: "json_schema", schema: simplifyAnthropicSchema(EXPLANATION_SCHEMA),
    }, effort: "low"},
    system: [
      "Si osobný stylist a píšeš priamo používateľovi prirodzenou slovenčinou.",
      "Vysvetli LEN už vybraný outfit alebo reject_all; outfit nikdy nemeň ani nedopĺňaj.",
      "Pri vybranom outfite napíš zvyčajne 2–4 stručné vety: pomenuj len kusy z userFacingSelectedOutfit a vysvetli, prečo sa hodia k príležitosti, počasiu alebo kontextu.",
      "Ak internalCaveat naznačuje kompromis, prelož ho do bežnej stylistickej rady; neuvádzaj interný názov klasifikácie.",
      "Pri reject_all krátko a ľudsky vysvetli, že z dostupných možností nie je vhodný outfit; môžeš pomenovať potrebný typ kúsku, ale nikdy netvrď, že ho používateľ vlastní.",
      "NIKDY nespomínaj candidate ID, outfit ID, item ID, frozen kandidáta alebo frozen rozhodnutie, validátor, deterministické pravidlá, hard constraints, hard checks, violation codes, compromiseClassification, reason codes, autoritu, pipeline, model, providera, skóre ani confidence.",
      "Nevymýšľaj ani nenahrádzaj kusy, nevypisuj validačné kroky a nevysvetľuj systémové rozhodovanie.",
      "Vráť iba používateľský text v poli explanation.",
    ].join(" "),
    messages: [{role: "user", content: safeJson(canonicalPayload)}],
  });
}

function parseJsonText(value) {
  if (value && typeof value === "object") return value;
  if (typeof value !== "string") fail("structured_output_invalid");
  try { return JSON.parse(value); } catch (_) { fail("structured_output_invalid"); }
}
function exact(value, allowed) {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail("contract_invalid");
  for (const key of Object.keys(value)) if (!allowed.includes(key)) fail("contract_invalid");
}
function validateContext(value) {
  exact(value, ["action", "clarificationFactKey", "acceptedKnownFactKeys"]);
  if (!["proceed", "ask_clarification", "stop"].includes(value.action)) fail("contract_invalid");
  if (value.action === "ask_clarification" && !text(value.clarificationFactKey)) {
    fail("contract_invalid");
  }
  if (value.clarificationFactKey != null && !text(value.clarificationFactKey)) {
    fail("contract_invalid");
  }
  if (value.acceptedKnownFactKeys != null &&
      (!Array.isArray(value.acceptedKnownFactKeys) ||
       value.acceptedKnownFactKeys.some((item) => !text(item)))) {
    fail("contract_invalid");
  }
  return Object.freeze({...value});
}
function validateDecision(value) {
  exact(value, ["action", "selectedCandidateId"]);
  if (value.action === "select_candidate" && text(value.selectedCandidateId)) {
    return Object.freeze({...value});
  }
  if (value.action === "reject_all" && value.selectedCandidateId == null) {
    return Object.freeze({...value});
  }
  fail("contract_invalid");
}
function validateExplanation(value) {
  exact(value, ["explanation", "warnings"]);
  if (!text(value.explanation)) fail("contract_invalid");
  if (value.warnings != null &&
      (!Array.isArray(value.warnings) || value.warnings.some((item) => !text(item)))) {
    fail("contract_invalid");
  }
  return Object.freeze({...value});
}
function openAiContent(json) {
  return json && json.choices && json.choices[0] &&
    json.choices[0].message && json.choices[0].message.content;
}
function anthropicContent(json) {
  const content = json && json.content;
  if (!Array.isArray(content)) return null;
  return content.filter((block) => block && block.type === "text")
    .map((block) => block.text).join("\n");
}
function success(response, value) {
  return Object.freeze({
    ok: true,
    value,
    actualModel: safeModelAlias(response && response.json && response.json.model),
    providerCallNumber: Number.isInteger(response && response.providerCallNumber) ?
      response.providerCallNumber : null,
  });
}
function safeModelAlias(value) {
  const candidate = text(value);
  return /^[a-zA-Z0-9._:-]{1,80}$/.test(candidate) ? candidate : null;
}

function createOpenAiRoleTransport({role, credentialProvider, execute}) {
  if (!["contextClarification", "finalCandidateDecision"].includes(role)) {
    fail("openai_role_invalid");
  }
  if (typeof credentialProvider !== "function" || typeof execute !== "function") {
    fail("openai_dependency_missing");
  }
  const validator = role === "contextClarification" ? validateContext : validateDecision;
  return Object.freeze({
    provider: "openai", role, modelId: ROLE_MODELS[role].modelId,
    async run(canonicalPayload) {
      let credential;
      try { credential = text(await credentialProvider()); } catch (_) { credential = ""; }
      if (!credential) return frozenFailure(PROVIDER_FAILURE.authenticationUnavailable);
      let response;
      try {
        response = await execute(Object.freeze({
          method: "POST",
          url: "https://api.openai.com/v1/chat/completions",
          timeoutMs: 30000,
          headers: {Authorization: `Bearer ${credential}`},
          body: openAiBody({role, canonicalPayload}),
        }));
      } catch (error) {
        return normalizeProviderFailure(error);
      }
      if (!response || response.ok === false || Number(response.status) >= 400) {
        return normalizeProviderFailure(response);
      }
      try {
        return success(response, validator(parseJsonText(openAiContent(response.json))));
      } catch (error) {
        return normalizeLocalContractFailure(error, response.providerCallNumber);
      }
    },
  });
}

function createAnthropicExplanationTransport({credentialProvider, execute}) {
  if (typeof credentialProvider !== "function" || typeof execute !== "function") {
    fail("anthropic_dependency_missing");
  }
  return Object.freeze({
    provider: "anthropic", role: "explanation",
    modelId: ROLE_MODELS.explanation.modelId,
    async run(canonicalPayload) {
      let credential;
      try { credential = text(await credentialProvider()); } catch (_) { credential = ""; }
      if (!credential) return frozenFailure(PROVIDER_FAILURE.authenticationUnavailable);
      let response;
      try {
        response = await execute(Object.freeze({
          method: "POST", url: "https://api.anthropic.com/v1/messages",
          timeoutMs: 30000,
          headers: {"x-api-key": credential, "anthropic-version": "2023-06-01"},
          body: anthropicBody({canonicalPayload}),
        }));
      } catch (error) {
        return normalizeProviderFailure(error);
      }
      if (!response || response.ok === false || Number(response.status) >= 400) {
        return normalizeProviderFailure(response);
      }
      try {
        return success(response,
          validateExplanation(parseJsonText(anthropicContent(response.json))));
      } catch (error) {
        return normalizeLocalContractFailure(error, response.providerCallNumber);
      }
    },
  });
}

module.exports = {
  ROLE_MODELS, PROVIDER_FAILURE, CONTEXT_SCHEMA, DECISION_SCHEMA,
  EXPLANATION_SCHEMA, OPENAI_CONTEXT_WIRE_SCHEMA, NORMALIZED_REASON,
  ANTHROPIC_UNSUPPORTED_CONSTRAINTS, openAiBody, anthropicBody, simplifyAnthropicSchema,
  normalizeProviderFailure, createOpenAiRoleTransport,
  createAnthropicExplanationTransport,
};
