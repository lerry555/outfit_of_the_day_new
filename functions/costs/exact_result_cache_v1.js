"use strict";

const {hashValue} = require("./ai_usage_v1");
const {stableJson} = require("./idempotent_task_v1");

// One bounded entry per user+feature, and same-instance single flight. The key
// is the COMPLETE current provider request (including prompt/model/settings),
// not an item count. Read authoritative data BEFORE calling this helper.
function createExactResultCacheV1({db, logger = console, now = Date.now}) {
  const inFlight = new Map();
  return async function resolve({uid, feature, input, execute, isCacheable,
    ttlMs = 24 * 60 * 60 * 1000}) {
    const key = hashValue([uid, feature]);
    const fingerprint = hashValue(stableJson(input));
    const flightKey = `${key}:${fingerprint}`;
    if (inFlight.has(flightKey)) return inFlight.get(flightKey);
    const work = (async () => {
      const ref = db.collection("aiExactResultCachesV1").doc(key);
      try {
        const snapshot = await ref.get();
        const entry = snapshot.data();
        if (entry?.fingerprint === fingerprint && entry.expiresAtMs > now() &&
            isCacheable(entry.result)) {
          logger.info?.("AI_EXACT_CACHE_HIT", {feature});
          return entry.result;
        }
      } catch (_) {
        logger.warn?.("AI_EXACT_CACHE_READ_FAILED", {feature});
      }
      const result = await execute();
      if (isCacheable(result)) {
        try {
          await ref.set({fingerprint, result, expiresAtMs: now() + ttlMs});
        } catch (_) {
          logger.warn?.("AI_EXACT_CACHE_WRITE_FAILED", {feature});
        }
      }
      return result;
    })();
    inFlight.set(flightKey, work);
    try { return await work; } finally { inFlight.delete(flightKey); }
  };
}

module.exports = {createExactResultCacheV1};
