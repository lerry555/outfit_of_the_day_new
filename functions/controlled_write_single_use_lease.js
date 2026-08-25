"use strict";

const CONTRACT_ID = "ControlledWriteSingleUseLease/v1";
const CONTRACT_VERSION = 1;
const PURPOSE = "controlled_write_canary";

async function consumeControlledWriteLease(input, store) {
  if (!store || typeof store.consumeAtomically !== "function") {
    return denied("controlled_write_lease_missing");
  }
  try {
    return await store.consumeAtomically(input.leaseId, (raw) => {
      const lease = decodeLease(raw);
      const mismatch = bindingMismatch(lease, input);
      if (mismatch) return denied(mismatch);
      const now = Date.parse(input.now);
      if (!Number.isFinite(now)) return denied("controlled_write_lease_invalid");
      if (lease.status !== "fresh" || lease.acceptedRequestCount !== 0) {
        return denied("controlled_write_lease_consumed");
      }
      if (now < Date.parse(lease.validFrom) || now >= Date.parse(lease.expiresAt)) {
        return denied("controlled_write_lease_expired");
      }
      return {result: Object.freeze({ok: true, contractId: CONTRACT_ID,
        reasonCode: "controlled_write_lease_consumed"}), next: {...lease,
        acceptedRequestCount: 1, status: "consumed",
        consumedAt: new Date(now).toISOString(),
        consumedByInvocationId: String(input.invocationId)}};
    });
  } catch (_) { return denied("controlled_write_lease_invalid"); }
}

function decodeLease(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) fail();
  const keys = ["contractVersion", "leaseId", "policyFingerprint", "allowedUid",
    "allowedItemId", "allowedAction", "validFrom", "expiresAt",
    "maxAcceptedRequests", "acceptedRequestCount", "status", "consumedAt",
    "consumedByInvocationId", "purpose", "expectedMode", "createdAt"];
  if (Object.keys(raw).some((key) => !keys.includes(key))) fail();
  if (raw.contractVersion !== 1 || !text(raw.leaseId) ||
      !/^[a-f0-9]{64}$/.test(String(raw.policyFingerprint)) ||
      !text(raw.allowedUid) || !text(raw.allowedItemId) ||
      !text(raw.allowedAction) || !text(raw.purpose) || !text(raw.expectedMode) ||
      raw.maxAcceptedRequests !== 1 ||
      !Number.isInteger(raw.acceptedRequestCount) ||
      raw.acceptedRequestCount < 0 || raw.acceptedRequestCount > 1 ||
      !["fresh", "consumed"].includes(raw.status) ||
      !Number.isFinite(Date.parse(raw.validFrom)) ||
      !Number.isFinite(Date.parse(raw.expiresAt)) ||
      Date.parse(raw.expiresAt) <= Date.parse(raw.validFrom)) fail();
  return raw;
}

function bindingMismatch(lease, input) {
  if (lease.purpose !== PURPOSE || lease.expectedMode !== "controlled_write") {
    return "controlled_write_lease_binding_mismatch";
  }
  for (const key of ["policyFingerprint", "allowedUid", "allowedItemId",
    "allowedAction"]) if (lease[key] !== input[key]) {
    return "controlled_write_lease_binding_mismatch";
  }
  return null;
}

function createMemoryControlledWriteLeaseStore(seed) {
  let value = seed == null ? null : structuredClone(seed);
  let queue = Promise.resolve();
  return {consumeAtomically(id, callback) { const run = queue.then(() => {
    if (!value || value.leaseId !== id) return denied("controlled_write_lease_missing");
    const decision = callback(structuredClone(value));
    if (decision.next) value = structuredClone(decision.next);
    return decision.result || decision;
  }); queue = run.catch(() => {}); return run; },
  snapshot: () => value == null ? null : structuredClone(value)};
}
function denied(reasonCode) { return Object.freeze({ok: false,
  contractId: CONTRACT_ID, reasonCode}); }
function text(value) { return typeof value === "string" && value.trim(); }
function fail() { throw new Error("controlled_write_lease_invalid"); }

module.exports = {CONTRACT_ID, CONTRACT_VERSION, PURPOSE,
  consumeControlledWriteLease, createMemoryControlledWriteLeaseStore, decodeLease};
