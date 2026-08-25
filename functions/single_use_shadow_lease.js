"use strict";

const CONTRACT_ID = "SingleUseShadowLease/v1"; const CONTRACT_VERSION = 1;

async function consumeSingleUseShadowLease(input, store) {
  if (!store || typeof store.consumeAtomically !== "function") return denied("shadow_lease_store_missing");
  try { return await store.consumeAtomically(input.leaseId, (raw) => {
    const lease = decode(raw); const now = Date.parse(input.now);
    if (!Number.isFinite(now)) return denied("shadow_lease_clock_invalid");
    if (lease.status !== "fresh" || lease.acceptedRequestCount !== 0)
      return denied("shadow_lease_consumed");
    if (now < Date.parse(lease.validFrom) || now >= Date.parse(lease.expiresAt))
      return denied("shadow_lease_expired");
    return {result: Object.freeze({ok: true, contractId: CONTRACT_ID,
      reasonCode: "shadow_lease_consumed", leaseId: lease.leaseId}),
    next: {...lease, acceptedRequestCount: 1, status: "consumed",
      consumedAt: new Date(now).toISOString(),
      consumedByInvocationId: String(input.invocationId)}};
  }); } catch (e) { return denied(e.message || "shadow_lease_invalid"); }
}
function decode(v) { if (!v || v.contractVersion !== 1 || !v.leaseId ||
  v.maxAcceptedRequests !== 1 || !Number.isInteger(v.acceptedRequestCount) ||
  v.acceptedRequestCount < 0 || v.acceptedRequestCount > 1 ||
  !["fresh", "consumed"].includes(v.status) || !Number.isFinite(Date.parse(v.validFrom)) ||
  !Number.isFinite(Date.parse(v.expiresAt)) ||
  Date.parse(v.expiresAt) <= Date.parse(v.validFrom))
    throw new Error("shadow_lease_invalid"); return v; }
function createMemoryShadowLeaseStore(seed) { let value = structuredClone(seed);
  let queue = Promise.resolve(); return {consumeAtomically(id, callback) { const run = queue.then(() => {
    if (!value || value.leaseId !== id) return denied("shadow_lease_missing");
    const decision = callback(structuredClone(value)); if (decision.next) value = decision.next;
    return decision.result || decision; }); queue = run.catch(() => {}); return run; },
  snapshot: () => structuredClone(value)}; }
function denied(reasonCode) { return Object.freeze({ok: false, contractId: CONTRACT_ID, reasonCode}); }
module.exports = {CONTRACT_ID, CONTRACT_VERSION, consumeSingleUseShadowLease,
  createMemoryShadowLeaseStore};
