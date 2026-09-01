"use strict";

// Production authority for the U/D/R Stylist path. This module deliberately
// accepts candidate IDs only: it can reject an unsafe/invalid candidate but it
// can never substitute candidate zero (or any other positional fallback).

const {
  createOpenAiRoleTransport,
  createAnthropicExplanationTransport,
} = require("./ai_stylist_role_transport_v1");
const {
  createConversationBrainExplanationTransportV1,
} = require("./conversation_brain_v1");
const {
  CONVERSATION_BRAIN_VERSION,
} = require("./conversation_brain_persona_v1");

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
  const userIntentContext = cleanText(source.userIntentContext, 600);
  if (userIntentContext) context.userIntentContext = userIntentContext;
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
  const presentationItems = normalizePresentationItems(value.presentationItems, itemIds);
  if (presentationItems === null) return null;
  const suppliedEvidence = value.hardConstraintEvidence && typeof value.hardConstraintEvidence === "object" ?
    value.hardConstraintEvidence : {};
  const deterministicPassed = suppliedEvidence.deterministicPassed === true;
  const violationCodes = cleanStringList(suppliedEvidence.violationCodes, 16, 80);
  const owned = itemIds.every((id) => ownedItemIds.has(id));
  const compromise = value.compromiseClassification && typeof value.compromiseClassification === "object" ?
    value.compromiseClassification : {};
  const level = ["none", "acceptable_compromise", "material_compromise", "reject_all"].includes(compromise.level) ?
    compromise.level : "material_compromise";
  const compromiseDetails = normalizeCompromiseDetails(value.compromiseDetails);
  const eligible = deterministicPassed && owned && violationCodes.length === 0 && level !== "reject_all";
  return Object.freeze({
    candidateId,
    itemIds,
    presentationItems,
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
    compromiseDetails,
    eligible,
  });
}

function normalizeCompromiseDetails(value) {
  if (!Array.isArray(value)) return Object.freeze([]);
  const allowedTiers = new Set(["acceptableCompromise", "strongCompromise"]);
  return Object.freeze(value.slice(0, MAX_ITEMS_PER_CANDIDATE).map((raw) => {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
    const itemName = cleanText(raw.itemName, 120);
    const tier = cleanText(raw.tier, 40);
    if (!itemName || !allowedTiers.has(tier)) return null;
    return Object.freeze({
      itemName,
      tier,
      reasons: cleanStringList(raw.reasonCodes, 8, 100),
      missingCapabilities: cleanStringList(raw.missingCapabilities, 8, 80),
      idealReplacementDescription: cleanText(raw.idealReplacementDescription, 180) || null,
    });
  }).filter(Boolean));
}

// This snapshot is immutable and must describe precisely the frozen item set.
// It is retained server-side with IDs for correlation, then IDs are removed
// before the payload reaches either user-facing explanation model.
function normalizePresentationItems(value, itemIds) {
  if (value == null) return Object.freeze([]); // Allows already-released clients.
  if (!Array.isArray(value) || value.length !== itemIds.length) return null;
  const byId = new Map();
  for (const raw of value) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
    const itemId = cleanText(raw.itemId, 100);
    const name = cleanText(raw.name, 120);
    const canonicalType = cleanText(raw.canonicalType, 80);
    const primaryColor = cleanText(raw.primaryColor, 80);
    if (!itemId || !name || !canonicalType || !primaryColor || byId.has(itemId)) return null;
    const slot = ["top", "bottom", "shoes", "outerwear"].includes(cleanText(raw.slot, 24)) ?
      cleanText(raw.slot, 24) : "";
    byId.set(itemId, Object.freeze({itemId, name, canonicalType, primaryColor, slot}));
  }
  if (itemIds.some((id) => !byId.has(id))) return null;
  return Object.freeze(itemIds.map((id) => byId.get(id)));
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
  const decisionMode = cleanText(data.decisionMode, 40) === "locked_selection" ?
    "locked_selection" : "select_candidate";
  const presentationMode = ["normal", "focused_item", "concise_full"].includes(
    cleanText(data.presentationMode, 40),
  ) ? cleanText(data.presentationMode, 40) : "normal";
  const focusSlot = ["top", "bottom", "shoes", "outerwear"].includes(
    cleanText(data.focusSlot, 24),
  ) ? cleanText(data.focusSlot, 24) : "";
  const userRequest = cleanText(data.userRequest, 600);
  return Object.freeze({
    resolvedContext: safeContext(data.resolvedContext),
    frozenCandidates: Object.freeze(candidates),
    decisionMode,
    presentationMode,
    focusSlot,
    userRequest,
  });
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
    // Never transmit candidate or item IDs to a user-facing explanation model.
    // It receives only this presentation-safe description of the immutable set.
    userFacingSelectedOutfit: selected ? selected.presentationItems.map((item) => ({
      name: item.name, canonicalType: item.canonicalType, primaryColor: item.primaryColor,
      slot: item.slot,
    })) : [],
    userFacingContext: normalized.resolvedContext,
    presentationMode: normalized.presentationMode,
    focusSlot: normalized.focusSlot,
    userRequest: normalized.userRequest,
    internalCaveat: selected ? selected.compromiseClassification.level : "reject_all",
    userFacingCompromises: selected ? selected.compromiseDetails : [],
  });
}

function listUserFacingItems(items) {
  const names = (Array.isArray(items) ? items : [])
    .map((item) => cleanText(item && item.name, 120))
    .filter(Boolean);
  if (!names.length) return "";
  if (names.length === 1) return names[0];
  if (names.length === 2) return `${names[0]} a ${names[1]}`;
  return `${names.slice(0, -1).join(", ")} a ${names[names.length - 1]}`;
}

function userFacingWeatherSummary(value) {
  const raw = cleanText(value, 240);
  if (!raw) return "";
  const parts = [];
  const temp = raw.match(/(-?\d+(?:\.\d+)?)\s*C\b/i);
  if (temp) parts.push(`približne ${temp[1].replace(".", ",")} °C`);
  if (/\brain=true\b/i.test(raw)) parts.push("s dažďom");
  else if (/\brain=false\b/i.test(raw)) parts.push("bez dažďa");
  if (/\bwind=true\b/i.test(raw)) parts.push("s vetrom");
  return parts.join(", ");
}

function deterministicExplanation(decision, normalized = null) {
  if (decision.action === "reject_all") {
    return "Z toho, čo máš, teraz neviem poskladať outfit, ktorý by som ti s čistým svedomím odporučil. Radšej ti poviem, čo v ňom chýba, než aby som predstieral, že je všetko v poriadku.";
  }
  const selected = normalized && Array.isArray(normalized.frozenCandidates) ?
    normalized.frozenCandidates.find((candidate) =>
      candidate.candidateId === decision.selectedCandidateId) : null;
  if (!selected) {
    return "Z tvojho šatníka som vybral najsilnejšiu dostupnú kombináciu pre túto situáciu.";
  }

  const sentences = [];
  const itemList = listUserFacingItems(selected.presentationItems);
  if (itemList) sentences.push(`Vybral som ${itemList}.`);
  const weather = userFacingWeatherSummary(
    normalized.resolvedContext && normalized.resolvedContext.weather,
  );
  if (weather) sentences.push(`Počítam pritom s ${weather}.`);

  const firstCompromise = selected.compromiseDetails && selected.compromiseDetails[0];
  if (firstCompromise) {
    const itemName = cleanText(firstCompromise.itemName, 120) || "jeden kúsok";
    const ideal = cleanText(firstCompromise.idealReplacementDescription, 180);
    sentences.push(
      ideal ?
        `${itemName} je tu kompromis; ideálnejšia náhrada by bola ${ideal}.` :
        `${itemName} je tu najlepší dostupný kompromis.`,
    );
  } else if (selected.compromiseClassification &&
      selected.compromiseClassification.level !== "none") {
    sentences.push("Je to najlepšia dostupná možnosť, hoci nie úplne bez kompromisu.");
  } else {
    sentences.push("Z toho, čo máš v šatníku, je to pre túto situáciu najsilnejšia dostupná kombinácia.");
  }
  return sentences.join(" ");
}

function isUserFacingExplanationSafe(value) {
  const lower = cleanText(value, 1200).toLowerCase();
  if (!lower) return false;
  return ![
    /candidate\s*id|outfit\s*id|item\s*id|selectedcandidateid/,
    /frozen|validátor|validator|determinist|hard\s*(constraint|check)|violation/,
    /compromiseclassification|reason\s*code|authority|pipeline|confidence|skóre|score/,
    /openai|anthropic|claude|gpt[-\s]?\d/,
  ].some((pattern) => pattern.test(lower));
}

function brainRequested(data) {
  return cleanText(data && data.conversationBrainVersion, 40) ===
    CONVERSATION_BRAIN_VERSION;
}

function createFrozenStylistAuthority({resolveOpenAISecret, resolveAnthropicSecret, execute}) {
  if (typeof resolveOpenAISecret !== "function" || typeof resolveAnthropicSecret !== "function" ||
      typeof execute !== "function") throw new Error("frozen_stylist_authority_dependencies_missing");
  const decisionClient = createOpenAiRoleTransport({
    role: "finalCandidateDecision", credentialProvider: resolveOpenAISecret, execute,
  });
  const legacyExplanationClient = createAnthropicExplanationTransport({
    credentialProvider: resolveAnthropicSecret,
    execute,
  });
  const brainExplanationClient = createConversationBrainExplanationTransportV1({
    credentialProvider: resolveOpenAISecret,
    execute,
  });
  return Object.freeze({
    async resolve({data, ownedItemIds}) {
      const normalized = normalizeRequest(data, ownedItemIds);
      const eligible = normalized.frozenCandidates.filter((candidate) => candidate.eligible);
      let decision = null;
      let decisionProviderFailure = null;
      if (normalized.decisionMode === "locked_selection") {
        if (normalized.frozenCandidates.length !== 1 || eligible.length !== 1) {
          decision = rejectAll("locked_selection_invalid");
        } else {
          const selected = eligible[0];
          decision = Object.freeze({
            action: "select_candidate",
            selectedCandidateId: selected.candidateId,
            requestedAction: "select_candidate",
            requestedSelectedCandidateId: selected.candidateId,
            requestedDecisionAccepted: true,
            reasonCodes: Object.freeze([]),
          });
        }
      } else if (!eligible.length) {
        decision = rejectAll("no_valid_frozen_candidates");
      }
      if (!decision) {
        const result = await decisionClient.run({
          contractVersion: "FrozenOutfitDecisionRequestV1",
          resolvedContext: normalized.resolvedContext,
          frozenCandidates: normalized.frozenCandidates.map((candidate) => ({
            candidateId: candidate.candidateId, itemIds: candidate.itemIds,
            items: candidate.presentationItems.map((item) => ({
              canonicalType: item.canonicalType,
              primaryColor: item.primaryColor,
            })),
            deterministicEvidence: candidate.hardConstraintEvidence,
            compromiseClassification: candidate.compromiseClassification,
            functionalCompromises: candidate.compromiseDetails.map((detail) => ({
              tier: detail.tier,
              reasons: detail.reasons,
              missingCapabilities: detail.missingCapabilities,
            })),
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
      const useBrain = brainRequested(data);
      const explanationClient = useBrain ? brainExplanationClient : legacyExplanationClient;
      const explanationResult = await explanationClient.run(explanationPayload(normalized, decision));
      const explanationValid = explanationResult.ok &&
        isUserFacingExplanationSafe(explanationResult.value.explanation);
      const explanation = explanationValid ? explanationResult.value.explanation :
        deterministicExplanation(decision, normalized);
      return Object.freeze({
        contractVersion: CONTRACT_VERSION,
        action: decision.action,
        selectedCandidateId: decision.selectedCandidateId,
        reasonCodes: decision.reasonCodes,
        requestedDecisionAccepted: decision.requestedDecisionAccepted,
        explanation,
        explanationFallback: !explanationValid,
        decisionProviderFailure,
        explanationProviderFailure: explanationValid ? null :
          explanationResult.ok ? "explanation_user_facing_contract_invalid" :
            explanationResult.failureCode || "explanation_provider_failure",
        conversationBrainVersion: useBrain ? CONVERSATION_BRAIN_VERSION : null,
      });
    },
  });
}

module.exports = {
  CONTRACT_VERSION, normalizeRequest, validateDecision, explanationPayload,
  deterministicExplanation, isUserFacingExplanationSafe, brainRequested,
  createFrozenStylistAuthority,
};
