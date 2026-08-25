"use strict";

/**
 * Raw partner payload retention — privacy/cost minimization.
 * Do NOT store every retailer raw payload by default.
 * Bounded sanitized failure samples only; never credentials/tokens.
 */
const RAW_PAYLOAD_RETENTION_POLICY_V1 = Object.freeze({
  name: "RAW_PAYLOAD_RETENTION_POLICY_V1",
  storeAllRawPayloadsByDefault: false,
  maxFailureSamplesPerRun: 5,
  maxSampleBytes: 2048,
  stripCredentialKeys: true,
  retentionNote:
    "Failure samples are ephemeral diagnostics for the sync run document " +
    "or structured logs. Credentials/tokens must never appear. Prefer " +
    "schema/error codes over raw bodies. Delete samples with sync-run TTL " +
    "or omit in production unless explicitly enabled for a partner.",
});

function sanitizeFailureSample(raw, policy = RAW_PAYLOAD_RETENTION_POLICY_V1) {
  if (raw == null) return null;
  let text;
  try {
    if (typeof raw === "string") text = raw;
    else text = JSON.stringify(redactObject(raw));
  } catch (_) {
    text = "[unserializable]";
  }
  if (text.length > policy.maxSampleBytes) {
    text = `${text.slice(0, policy.maxSampleBytes)}…[truncated]`;
  }
  return text;
}

function redactObject(value, depth = 0) {
  if (depth > 6) return "[max_depth]";
  if (value == null) return value;
  if (Array.isArray(value)) {
    return value.slice(0, 20).map((item) => redactObject(item, depth + 1));
  }
  if (typeof value !== "object") return value;
  const out = {};
  for (const [key, nested] of Object.entries(value)) {
    const lower = key.toLowerCase();
    if (/(secret|password|token|apikey|api_key|authorization|credential)/.test(lower)) {
      out[key] = "[redacted]";
      continue;
    }
    out[key] = redactObject(nested, depth + 1);
  }
  return out;
}

module.exports = {
  RAW_PAYLOAD_RETENTION_POLICY_V1,
  redactObject,
  sanitizeFailureSample,
};
