"use strict";

/**
 * Adapter-neutral retry/backoff. Bounded attempts; honors Retry-After.
 * Do not retry AUTH / schema / fatal configuration aggressively.
 */
const PARTNER_RETRY_POLICY_V1 = Object.freeze({
  name: "PARTNER_RETRY_POLICY_V1",
  maxAttempts: 4,
  baseDelayMs: 250,
  maxDelayMs: 8000,
  jitterRatio: 0.2,
});

function computeBackoffMs(attempt, policy = PARTNER_RETRY_POLICY_V1, {
  retryAfterMs = null,
  random = Math.random,
} = {}) {
  if (retryAfterMs != null) {
    const parsed = Number(retryAfterMs);
    if (Number.isFinite(parsed) && parsed >= 0) {
      return Math.min(policy.maxDelayMs, Math.floor(parsed));
    }
  }
  const exp = Math.min(
    policy.maxDelayMs,
    policy.baseDelayMs * (2 ** Math.max(0, attempt - 1)),
  );
  const jitter = exp * policy.jitterRatio * random();
  return Math.min(policy.maxDelayMs, Math.floor(exp + jitter));
}

async function withPartnerRetry(operation, {
  policy = PARTNER_RETRY_POLICY_V1,
  isRetryable,
  sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  random = Math.random,
  onRetry,
} = {}) {
  if (typeof operation !== "function") {
    throw new Error("partner_retry_operation_required");
  }
  let attempt = 0;
  let lastError = null;
  while (attempt < policy.maxAttempts) {
    attempt += 1;
    try {
      return await operation({attempt});
    } catch (error) {
      lastError = error;
      const retryable = typeof isRetryable === "function" ?
        isRetryable(error) : false;
      if (!retryable || attempt >= policy.maxAttempts) throw error;
      const delayMs = computeBackoffMs(attempt, policy, {
        retryAfterMs: error.retryAfterMs,
        random,
      });
      if (typeof onRetry === "function") {
        onRetry({attempt, delayMs, error});
      }
      await sleep(delayMs);
    }
  }
  throw lastError;
}

module.exports = {
  PARTNER_RETRY_POLICY_V1,
  computeBackoffMs,
  withPartnerRetry,
};
