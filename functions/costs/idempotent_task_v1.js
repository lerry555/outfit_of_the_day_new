"use strict";

const {randomUUID} = require("node:crypto");
const {hashValue} = require("./ai_usage_v1");

function stableJson(value) {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().filter((key) => value[key] !== undefined)
      .map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value ?? null);
}

function taskError(code) {
  return Object.assign(new Error(code), {code});
}

// Durable at-most-once admission of a paid operation. This is deliberately not
// an expiring execution lease: after a crash the provider may already have
// charged, so timeout alone is NOT permission to start the same task again.
// Completed request IDs remain bound to their original payload/result.
function createIdempotentTaskRunnerV1({db, logger = console, now = Date.now}) {
  return async function run({uid, requestId, feature, payload, execute}) {
    if (!uid || !feature || typeof requestId !== "string" ||
        !/^[A-Za-z0-9_-]{1,180}$/.test(requestId)) {
      throw taskError("invalid_request_id");
    }
    const key = hashValue([uid, feature, requestId]);
    const fingerprint = hashValue(stableJson(payload));
    // Top-level server-only collection. users/* subcollections currently have
    // broad owner-write rules and CANNOT be trusted as an idempotency ledger.
    const ref = db.collection("aiTaskRunsV1").doc(key);
    const token = randomUUID();
    const admitted = await db.runTransaction(async (tx) => {
      const snapshot = await tx.get(ref);
      if (snapshot.exists) {
        const prior = snapshot.data();
        if (prior.fingerprint !== fingerprint) throw taskError("request_id_conflict");
        if (prior.status === "complete") return {result: prior.result, replayed: true};
        throw taskError(prior.status === "failed" ? "request_previously_failed" :
          "request_in_progress_or_unknown");
      }
      tx.set(ref, {fingerprint, token, status: "running", feature,
        userKey: hashValue(uid), createdAt: new Date(now())});
      return null;
    });
    if (admitted) return admitted;
    let result;
    try {
      result = await execute();
    } catch (error) {
      try {
        await ref.update({status: "failed", finishedAt: new Date(now())});
      } catch (_) {
        logger.warn?.("AI_TASK_FAILURE_PERSIST_FAILED", {key});
      }
      throw error;
    }
    try {
      await ref.update({status: "complete", result, finishedAt: new Date(now())});
    } catch (_) {
      // Return the already-paid result. The running record continues to block
      // duplicate spending even if durable result persistence is unavailable.
      logger.warn?.("AI_TASK_RESULT_PERSIST_FAILED", {key});
    }
    return {result, replayed: false};
  };
}

module.exports = {stableJson, createIdempotentTaskRunnerV1};
