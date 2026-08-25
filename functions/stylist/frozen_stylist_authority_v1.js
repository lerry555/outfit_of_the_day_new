"use strict";

// Production authority for the U/D/R Stylist path.  This module deliberately
// accepts candidate IDs only: it can reject an unsafe/invalid candidate but it
// can never substitute candidate zero (or any other positional fallback).

const {
  createOpenAiRoleTransport,
  createAnthropicExplanationTransport,
} = require("./ai_stylist_role_transport_v1");

const CONTRACT_VERSION = 1;
const MAX_CANDIDATES = 12;
const MAX_ITEMS_PER_CANDIDATE = 8;

function cleanText(value, max = 160) {
  const text = typeof value === "string" ? value.trim() : "";
  return text.slice(0, max);
}

function cleanStringList(value, maxItems = 24, maxLength = 120) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map((item) => cleanText(item, maxLength)).filter(Boolean))]
    .slice(0, maxItems);
}

function safeContext(value) {
  const source = value && typeof value === "object" && !Array.isArray(value) ? value : {};
  const context = {};
  for (const key of ["activity", "occasion", "environment", "weather", "formality", "terrain"]) {
    const text = cleanText(source[key]);
    if (text) context[key] = text;
  }
  if (source.relevantKnownTimingFacts && typeof source.relevantKnownTimingFacts === "object" &&
      !Array.isArray(source.relevantKnownTimingFacts)) {
    const timing = {};
    for (const [key, value] of Object.entries(source.relevantKnownTimingFacts)) {
      const safeKey = cleanText(key, 80);
      const safeValue = cleanText(value);
      if (safeKey && safeValue) timing[safeKey] = safeValue;
    }
    if (Object.keys(timing).length) context.relevantKnownTimingFacts = timing;
  }
  return Object.freeze(context);
}

function normalizeCandidate(value, ownedItemIds) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const candidateId = cleanText(value.candidateId, 100);
  const itemIds = cleanStringList(value.itemIds, MAX_ITEMS_PER_CANDIDATE, 100);
  if (!candidateId || !itemIds.length) return null;
  const suppliedEvidence = value.hardConstraintEvidence && typeof value.hardConstraintEvidence === "object" ?
    value.hardConstraintEvidence : {};
  const deterministicPassed = suppliedEvidence.deterministicPassed === true;
  const violationCodes = cleanStringList(suppliedEvidence.violationCodes, 16, 80);
  const owned = itemIds.every((id) => ownedItemIds.has(id));
  const compromise = value.compromiseClassification && typeof value.compromiseClassification === "object" ?
    value.compromiseClassification : {};
  const level = ["none", "acceptable_compromise", "material_compromise", "reject_all"].includes(compromise.level) ?
    compromise.level : "material_compromise";
  const eligible = deterministicPassed && owned && violationCodes.length === 0 && level !== "reject_all";
  return Object.freeze({
    candidateId,
    itemIds,
    hardConstraintEvidence: Object.freeze({
      deterministicPassed,
      ownershipPassed: owned,
      passed: eligible,
      violationCodes: Object.freeze([
        ...violationCodes,
        ...(owned ? [] : ["wardrobe_ownership_failed"]),
        ...(deterministicPassed ? [] : ["deterministic_candidate_validation_failed"]),
      ]),
    }),
    compromiseClassification: Object.freeze({
      level,
      reasonCodes: cleanStringList(compromise.reasonCodes, 16, 80),
    }),
    eligible,
  });
}

function normalizeRequest(data, ownedItemIds) {
  if (!data || typeof data !== "object" || Array.isArray(data) || data.contractVersion !== CONTRACT_VERSION) {
    const error = new Error("invalid_frozen_stylist_request"); error.code = "invalid-argument"; throw error;
  }
  const sourceCandidates = Array.isArray(data.frozenCandidates) ? data.frozenCandidates : [];
  if (!sourceCandidates.length || sourceCandidates.length > MAX_CANDIDATES) {
    const error = new Error("invalid_frozen_candidates"); error.code = "invalid-argument"; throw error;
  }
  const candidates = sourceCandidates.map((candidate) => normalizeCandidate(candidate, ownedItemIds));
  if (candidates.some((candidate) => candidate === null) ||
      new Set(candidates.map((candidate) => candidate.candidateId)).size !== candidates.length) {
    const error = new Error("invalid_frozen_candidates"); error.code = "invalid-argument"; throw error;
  }
  return Object.freeze({resolvedContext: safeContext(data.resolvedContext), frozenCandidates: Object.freeze(candidates)});
}

function rejectAll(reasonCode, requested = null) {
  return Object.freeze({
    action: "reject_all", selectedCandidateId: null, requestedAction: requested && requested.action || null,
    requestedSelectedCandidateId: requested && requested.selectedCandidateId || null,
    requestedDecisionAccepted: requested && requested.action === "reject_all" && requested.selectedCandidateId == null,
    reasonCodes: Object.freeze([reasonCode]),
  });
}

function validateDecision(candidates, attempt) {
  const eligible = candidates.filter((candidate) => candidate.eligible);
  if (!eligible.length) return rejectAll("no_valid_frozen_candidates", attempt);
  if (!attempt || typeof attempt !== "object") return rejectAll("decision_provider_failure");
  if (attempt.action === "reject_all" && attempt.selectedCandidateId == null) {
    return rejectAll("decision_reject_all", attempt);
  }
  if (attempt.action !== "select_candidate") return rejectAll("invalid_decision_contract", attempt);
  const selectedCandidateId = cleanText(attempt.selectedCandidateId, 100);
  const selected = candidates.find((candidate) => candidate.candidateId === selectedCandidateId);
  if (!selected) return rejectAll("selected_candidate_outside_frozen_set", attempt);
  if (!selected.eligible) return rejectAll("selected_candidate_failed_hard_constraints", attempt);
  return Object.freeze({
    action: "select_candidate", selectedCandidateId: selected.candidateId,
    requestedAction: attempt.action, requestedSelectedCandidateId: selectedCandidateId,
    requestedDecisionAccepted: true, reasonCodes: Object.freeze([]),
  });
}

function explanationPayload(normalized, decision) {
  const selected = normalized.frozenCandidates.find((candidate) => candidate.candidateId === decision.selectedCandidateId) || null;
  return Object.freeze({
    contractVersion: "FrozenOutfitExplanationRequestV1",
    effectiveAction: decision.action,
    effectiveSelectedCandidateId: decision.selectedCandidateId,
    selectedFrozenItemIds: selected ? selected.itemIds : [],
    hardConstraintEvidence: selected ? selected.hardConstraintEvidence : null,
    compromiseClassification: selected ? selected.compromiseClassification :
      {level: "reject_all", reasonCodes: decision.reasonCodes},
    decisionReasons: decision.reasonCodes,
    resolvedContext: normalized.resolvedContext,
  });
}

function deterministicExplanation(decision) {
  return decision.action === "reject_all" ?
    "Z dostupných možností teraz neviem bezpečne potvrdiť vhodný outfit." :
    "Vybraný outfit prešiel kontrolou známych podmienok.";
}

function createFrozenStylistAuthority({resolveOpenAISecret, resolveAnthropicSecret, execute}) {
  if (typeof resolveOpenAISecret !== "function" || typeof resolveAnthropicSecret !== "function" ||
      typeof execute !== "function") throw new Error("frozen_stylist_authority_dependencies_missing");
  const decisionClient = createOpenAiRoleTransport({
    role: "finalCandidateDecision", credentialProvider: resolveOpenAISecret, execute,
  });
  const explanationClient = createAnthropicExplanationTransport({
    credentialProvider: resolveAnthropicSecret, execute,
  });
  return Object.freeze({
    async resolve({data, ownedItemIds}) {
      const normalized = normalizeRequest(data, ownedItemIds);
      const eligible = normalized.frozenCandidates.filter((candidate) => candidate.eligible);
      let decision = eligible.length ? null : rejectAll("no_valid_frozen_candidates");
      let decisionProviderFailure = null;
      if (!decision) {
        const result = await decisionClient.run({
          contractVersion: "FrozenOutfitDecisionRequestV1",
          resolvedContext: normalized.resolvedContext,
          frozenCandidates: normalized.frozenCandidates.map((candidate) => ({
            candidateId: candidate.candidateId, itemIds: candidate.itemIds,
            deterministicEvidence: candidate.hardConstraintEvidence,
            compromiseClassification: candidate.compromiseClassification,
          })),
          allowedActions: ["select_candidate", "reject_all"],
        });
        if (!result.ok) {
          decisionProviderFailure = result.failureCode || "decision_provider_failure";
          decision = rejectAll("decision_provider_failure");
        } else {
          decision = validateDecision(normalized.frozenCandidates, result.value);
        }
      }
      const explanationResult = await explanationClient.run(explanationPayload(normalized, decision));
      const explanation = explanationResult.ok ? explanationResult.value.explanation : deterministicExplanation(decision);
      return Object.freeze({
        contractVersion: CONTRACT_VERSION,
        action: decision.action,
        selectedCandidateId: decision.selectedCandidateId,
        reasonCodes: decision.reasonCodes,
        requestedDecisionAccepted: decision.requestedDecisionAccepted,
        explanation,
        explanationFallback: !explanationResult.ok,
        decisionProviderFailure,
        explanationProviderFailure: explanationResult.ok ? null : explanationResult.failureCode || "explanation_provider_failure",
      });
    },
  });
}

module.exports = {
  CONTRACT_VERSION, normalizeRequest, validateDecision, explanationPayload,
  createFrozenStylistAuthority,
};
