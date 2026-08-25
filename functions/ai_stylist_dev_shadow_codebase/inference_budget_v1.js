"use strict";

const ALLOWED_ROLES = Object.freeze([
  "contextClarification", "finalCandidateDecision", "explanation",
]);

function createSmokeInferenceBudget({maxDispatches = 3} = {}) {
  if (maxDispatches !== 3) throw new Error("smoke_budget_must_equal_three");
  let dispatchCount = 0;
  const roleCounts = new Map(ALLOWED_ROLES.map((role) => [role, 0]));
  return Object.freeze({
    maxDispatches,
    claim(role) {
      if (!roleCounts.has(role)) throw coded("smoke_role_invalid");
      if (dispatchCount >= maxDispatches) throw coded("smoke_budget_exhausted");
      if (roleCounts.get(role) >= 1) throw coded("smoke_role_budget_exhausted");
      dispatchCount += 1;
      roleCounts.set(role, 1);
      return Object.freeze({providerCallNumber: dispatchCount, role});
    },
    snapshot() {
      return Object.freeze({
        maxDispatches,
        dispatchCount,
        remaining: maxDispatches - dispatchCount,
        roleCounts: Object.freeze(Object.fromEntries(roleCounts)),
      });
    },
  });
}

function coded(code) { const error = new Error(code); error.code = code; return error; }

module.exports = {ALLOWED_ROLES, createSmokeInferenceBudget};
