"use strict";

const {ROLE_MODELS} = require("./role_transport_v1");

const CONTRACT_VERSION = 1;
const DETERMINISTIC_REJECT_TEXT =
  "Nenašiel som bezpečný outfit, ktorý by spĺňal všetky podmienky.";

function deterministicSmokeFixture() {
  return deepFreeze({
    fixtureId: "ootd_dev_shadow_minimal_v1",
    knownContext: {
      activity: "city_walk",
      occasion: "casual",
      environment: "outdoor",
      weather: "dry_20c",
      formality: "casual",
      terrain: "paved",
      timing: "daytime",
    },
    unresolvedMaterialFactKeys: [],
    frozenCandidates: [
      {
        candidateId: "fixture-candidate-navy",
        itemIds: ["fixture-top-navy", "fixture-bottom-denim", "fixture-shoes-white"],
        hardConstraintEvidence: {valid: true, ownershipValid: true,
          weatherValid: true, terrainValid: true, dressCodeValid: true},
        compromiseClassification: "none",
      },
      {
        candidateId: "fixture-candidate-olive",
        itemIds: ["fixture-top-olive", "fixture-bottom-black", "fixture-shoes-black"],
        hardConstraintEvidence: {valid: true, ownershipValid: true,
          weatherValid: true, terrainValid: true, dressCodeValid: true},
        compromiseClassification: "none",
      },
    ],
    ownedItemIds: [
      "fixture-top-navy", "fixture-bottom-denim", "fixture-shoes-white",
      "fixture-top-olive", "fixture-bottom-black", "fixture-shoes-black",
    ],
  });
}

async function runControlledDevShadowSmoke({
  runId,
  providers,
  budget,
  legacyResult,
  now = () => Date.now(),
} = {}) {
  if (!runId || !providers || !budget || !legacyResult) {
    throw new Error("smoke_dependencies_missing");
  }
  const fixture = deterministicSmokeFixture();
  const trace = [];
  const contextRequest = deepFreeze({
    contractVersion: CONTRACT_VERSION,
    responsibility: "contextClarification",
    task: "Interpret only supplied facts. Ask only for a listed material uncertainty. Never invent facts.",
    knownFacts: fixture.knownContext,
    unresolvedMaterialFactKeys: fixture.unresolvedMaterialFactKeys,
    allowedActions: ["proceed", "ask_clarification", "stop"],
  });
  const context = await measured(now, () => providers.contextClient.run(contextRequest));
  const contextContract = validateContextOutcome(context.result, fixture);
  trace.push(event({runId, stage: "context", responsibility: "contextClarification",
    requestedModelAlias: ROLE_MODELS.contextClarification.modelId,
    result: context.result, contract: contextContract, latencyMs: context.latencyMs,
    candidateId: null, rejectAll: true, validatorOutcome: contextContract.code}));
  if (!contextContract.ok || contextContract.action !== "proceed") {
    return finalResult({legacyResult, runId, trace, budget,
      effectiveDecision: rejectAll(contextContract.code),
      explanation: DETERMINISTIC_REJECT_TEXT, explanationFallbackUsed: true});
  }

  const decisionRequest = deepFreeze({
    contractVersion: CONTRACT_VERSION,
    responsibility: "finalCandidateDecision",
    task: "Select exactly one candidate ID from frozenCandidates or reject_all. Never use an index.",
    resolvedContext: fixture.knownContext,
    frozenCandidates: fixture.frozenCandidates,
    allowedActions: ["select_candidate", "reject_all"],
  });
  const decision = await measured(now, () => providers.decisionClient.run(decisionRequest));
  const effectiveDecision = validateDecisionOutcome(decision.result, fixture);
  trace.push(event({runId, stage: "final_decision",
    responsibility: "finalCandidateDecision",
    requestedModelAlias: ROLE_MODELS.finalCandidateDecision.modelId,
    result: decision.result,
    contract: {ok: decision.result.ok === true, code: effectiveDecision.validatorOutcome},
    latencyMs: decision.latencyMs,
    candidateId: effectiveDecision.selectedCandidateId,
    rejectAll: effectiveDecision.action === "reject_all",
    validatorOutcome: effectiveDecision.validatorOutcome}));

  const selected = effectiveDecision.selectedCandidateId == null ? null :
    fixture.frozenCandidates.find((candidate) =>
      candidate.candidateId === effectiveDecision.selectedCandidateId) || null;
  const explanationRequest = deepFreeze({
    contractVersion: CONTRACT_VERSION,
    responsibility: "explanation",
    task: "Explain this immutable decision in natural Slovak. Do not change it or invent items.",
    effectiveAction: effectiveDecision.action,
    effectiveSelectedCandidateId: effectiveDecision.selectedCandidateId,
    selectedFrozenCandidate: selected,
    hardConstraintEvidence: selected && selected.hardConstraintEvidence || null,
    compromiseClassification: selected && selected.compromiseClassification || "none",
    resolvedContext: fixture.knownContext,
    decisionReasons: [effectiveDecision.validatorOutcome],
  });
  const explanation = await measured(now,
    () => providers.explanationClient.run(explanationRequest));
  const explanationValid = explanation.result.ok === true;
  const explanationText = explanationValid ? explanation.result.value.explanation :
    deterministicExplanation(effectiveDecision);
  trace.push(event({runId, stage: "explanation", responsibility: "explanation",
    requestedModelAlias: ROLE_MODELS.explanation.modelId,
    result: explanation.result,
    contract: {ok: explanationValid,
      code: explanationValid ? "explanation_contract_valid" :
        explanation.result.failureCode || "explanation_contract_invalid"},
    latencyMs: explanation.latencyMs,
    candidateId: effectiveDecision.selectedCandidateId,
    rejectAll: effectiveDecision.action === "reject_all",
    validatorOutcome: explanationValid ? "immutable_explanation_valid" :
      "deterministic_explanation_fallback",
    fallbackUsed: !explanationValid}));

  return finalResult({legacyResult, runId, trace, budget, effectiveDecision,
    explanation: explanationText, explanationFallbackUsed: !explanationValid});
}

function validateContextOutcome(result, fixture) {
  if (!result || result.ok !== true) {
    return Object.freeze({ok: false, action: "stop",
      code: result && result.failureCode || "context_provider_failure"});
  }
  const value = result.value;
  const known = new Set(Object.keys(fixture.knownContext));
  const accepted = Array.isArray(value.acceptedKnownFactKeys) ?
    value.acceptedKnownFactKeys : [];
  if (accepted.some((key) => !known.has(key))) {
    return Object.freeze({ok: false, action: "stop",
      code: "assumption_promoted_to_fact"});
  }
  if (value.action === "ask_clarification" &&
      !fixture.unresolvedMaterialFactKeys.includes(value.clarificationFactKey)) {
    return Object.freeze({ok: false, action: "stop",
      code: "clarification_not_material_or_unknown"});
  }
  if (value.action === "proceed" && fixture.unresolvedMaterialFactKeys.length > 0) {
    return Object.freeze({ok: false, action: "stop",
      code: "material_uncertainty_unresolved"});
  }
  return Object.freeze({ok: true, action: value.action, code: "context_contract_valid"});
}

function validateDecisionOutcome(result, fixture) {
  if (!result || result.ok !== true) {
    return rejectAll(result && result.failureCode || "decision_provider_failure");
  }
  if (result.value.action === "reject_all") return rejectAll("provider_reject_all");
  const candidate = fixture.frozenCandidates.find((item) =>
    item.candidateId === result.value.selectedCandidateId);
  if (!candidate) return rejectAll("unknown_candidate_id");
  const owned = new Set(fixture.ownedItemIds);
  if (candidate.itemIds.some((itemId) => !owned.has(itemId))) {
    return rejectAll("candidate_ownership_invalid");
  }
  const evidence = candidate.hardConstraintEvidence;
  if (!evidence || evidence.valid !== true || evidence.ownershipValid !== true ||
      evidence.weatherValid !== true || evidence.terrainValid !== true ||
      evidence.dressCodeValid !== true) {
    return rejectAll("deterministic_hard_constraint_veto");
  }
  return Object.freeze({action: "select_candidate",
    selectedCandidateId: candidate.candidateId,
    validatorOutcome: "deterministic_validation_passed"});
}

function rejectAll(reason) {
  return Object.freeze({action: "reject_all", selectedCandidateId: null,
    validatorOutcome: reason});
}
function deterministicExplanation(decision) {
  return decision.action === "reject_all" ? DETERMINISTIC_REJECT_TEXT :
    "Vybral som bezpečný outfit z pripraveného vývojového kandidátskeho setu.";
}
async function measured(now, work) {
  const started = now();
  const result = await work();
  return Object.freeze({result, latencyMs: Math.max(0, now() - started)});
}
function event({runId, stage, responsibility, requestedModelAlias, result,
  contract, latencyMs, candidateId, rejectAll: rejected, validatorOutcome,
  fallbackUsed = false}) {
  return deepFreeze({
    runId, stage, responsibility, requestedModelAlias,
    actualModel: result && result.actualModel || null,
    contractValid: contract.ok === true,
    outcome: result && result.ok === true ? "provider_response" :
      result && result.failureCode || contract.code,
    candidateId: candidateId || null,
    rejectAll: rejected === true,
    validatorOutcome,
    latencyMs,
    fallbackUsed,
    providerCallNumber: Number.isInteger(result && result.providerCallNumber) ?
      result.providerCallNumber : null,
    // This is a deliberately allow-listed diagnostic object. It never carries
    // provider messages, raw response bodies, headers, or credential material.
    providerDiagnostics: result && result.providerDiagnostics || null,
    authority: "shadow",
  });
}
function finalResult({legacyResult, runId, trace, budget, effectiveDecision,
  explanation, explanationFallbackUsed}) {
  return deepFreeze({
    contractVersion: CONTRACT_VERSION,
    runId,
    authority: "shadow",
    authoritative: false,
    authoritativeLegacyResult: legacyResult,
    shadowResult: {
      effectiveDecision,
      explanation,
      explanationFallbackUsed,
      persistenceWrites: 0,
    },
    trace,
    inferenceBudget: budget.snapshot(),
  });
}
function deepFreeze(value) {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    for (const nested of Object.values(value)) deepFreeze(nested);
    Object.freeze(value);
  }
  return value;
}

module.exports = {
  CONTRACT_VERSION,
  DETERMINISTIC_REJECT_TEXT,
  deterministicSmokeFixture,
  runControlledDevShadowSmoke,
  validateContextOutcome,
  validateDecisionOutcome,
};
