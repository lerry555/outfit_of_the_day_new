"use strict";

/**
 * Per-partner rate limit contract. Orchestrator honors adapter/config limits;
 * never hardcodes one retailer's behavior globally.
 */
const DEFAULT_RATE_LIMIT = Object.freeze({
  requestsPerSecond: 5,
  requestsPerMinute: 120,
  concurrency: 1,
  pageSize: 100,
  maxPagesPerRun: 10000,
});

function normalizeRateLimit(raw = {}) {
  const requestsPerSecond = intOr(
    raw.requestsPerSecond, DEFAULT_RATE_LIMIT.requestsPerSecond, 1, 10000,
  );
  const requestsPerMinute = intOr(
    raw.requestsPerMinute, DEFAULT_RATE_LIMIT.requestsPerMinute, 1, 1000000,
  );
  const concurrency = intOr(
    raw.concurrency, DEFAULT_RATE_LIMIT.concurrency, 1, 8,
  );
  const pageSize = intOr(
    raw.pageSize, DEFAULT_RATE_LIMIT.pageSize, 1, 500,
  );
  const maxPagesPerRun = intOr(
    raw.maxPagesPerRun, DEFAULT_RATE_LIMIT.maxPagesPerRun, 1, 100000,
  );
  return {
    requestsPerSecond,
    requestsPerMinute,
    concurrency,
    pageSize,
    maxPagesPerRun,
  };
}

function createRateLimiter(limits, {now = () => Date.now()} = {}) {
  const config = normalizeRateLimit(limits);
  const minuteWindow = [];
  let lastRequestAt = 0;
  let waits = 0;

  async function acquire({
    sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  } = {}) {
    // Serial concurrency=1 is enforced by orchestrator; limiter tracks pacing.
    const minInterval = Math.ceil(1000 / config.requestsPerSecond);
    for (;;) {
      const t = now();
      while (minuteWindow.length && t - minuteWindow[0] >= 60000) {
        minuteWindow.shift();
      }
      const sinceLast = t - lastRequestAt;
      if (sinceLast < minInterval) {
        waits += 1;
        await sleep(minInterval - sinceLast);
        continue;
      }
      if (minuteWindow.length >= config.requestsPerMinute) {
        const waitMs = 60000 - (t - minuteWindow[0]) + 1;
        waits += 1;
        await sleep(Math.max(1, waitMs));
        continue;
      }
      lastRequestAt = now();
      minuteWindow.push(lastRequestAt);
      return;
    }
  }

  return {
    config,
    acquire,
    stats() {
      return {waits, inWindow: minuteWindow.length};
    },
  };
}

function intOr(value, fallback, min, max) {
  if (value == null) return fallback;
  if (!Number.isSafeInteger(value) || value < min || value > max) {
    const error = new Error("partner_rate_limit_invalid");
    error.code = "FATAL_CONFIGURATION";
    throw error;
  }
  return value;
}

module.exports = {
  DEFAULT_RATE_LIMIT,
  createRateLimiter,
  normalizeRateLimit,
};
