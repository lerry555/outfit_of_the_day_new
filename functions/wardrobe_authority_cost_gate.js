"use strict";

/**
 * Cost / rate-limit gate for wardrobe authority Vision path.
 * In-memory only (per Functions instance). Fail-closed on abuse.
 */

const COST_GATE_ID = "WardrobeAuthorityCostGate";
const COST_GATE_VERSION = "wardrobe-authority-cost-gate-v1";

const DEFAULTS = Object.freeze({
  perUserPerMinute: 6,
  perItemPerMinute: 2,
  maxViews: 4,
  maxImageBytes: 8 * 1024 * 1024,
  inFlightTtlMs: 120_000,
});

function createWardrobeAuthorityCostGate(options = {}) {
  const limits = Object.freeze({...DEFAULTS, ...(options.limits || {})});
  const clock = typeof options.now === "function" ? options.now : () => Date.now();
  const userBuckets = new Map();
  const itemBuckets = new Map();
  const inFlight = new Map();

  function prune(map, now, windowMs = 60_000) {
    for (const [key, entry] of map.entries()) {
      if (now - entry.windowStart >= windowMs) map.delete(key);
    }
  }

  function bump(map, key, limit, now) {
    prune(map, now);
    const entry = map.get(key);
    if (!entry || now - entry.windowStart >= 60_000) {
      map.set(key, {windowStart: now, count: 1});
      return {ok: true, count: 1};
    }
    if (entry.count >= limit) {
      return {ok: false, count: entry.count, reasonCode: "rate_limited"};
    }
    entry.count += 1;
    return {ok: true, count: entry.count};
  }

  function begin({uid, itemId, viewCount, imageBytes}) {
    const now = clock();
    if (viewCount != null && Number(viewCount) > limits.maxViews) {
      return Object.freeze({
        ok: false,
        reasonCode: "max_views_exceeded",
        gateId: COST_GATE_ID,
      });
    }
    if (imageBytes != null && Number(imageBytes) > limits.maxImageBytes) {
      return Object.freeze({
        ok: false,
        reasonCode: "max_image_bytes_exceeded",
        gateId: COST_GATE_ID,
      });
    }
    const userKey = String(uid || "");
    const itemKey = `${uid}|${itemId}`;
    if (!userKey || !itemId) {
      return Object.freeze({
        ok: false,
        reasonCode: "cost_gate_identity_required",
        gateId: COST_GATE_ID,
      });
    }
    if (inFlight.has(itemKey)) {
      const started = inFlight.get(itemKey);
      if (now - started < limits.inFlightTtlMs) {
        return Object.freeze({
          ok: false,
          reasonCode: "duplicate_in_flight",
          gateId: COST_GATE_ID,
        });
      }
      inFlight.delete(itemKey);
    }
    const user = bump(userBuckets, userKey, limits.perUserPerMinute, now);
    if (!user.ok) {
      return Object.freeze({
        ok: false,
        reasonCode: "user_rate_limited",
        gateId: COST_GATE_ID,
      });
    }
    const item = bump(itemBuckets, itemKey, limits.perItemPerMinute, now);
    if (!item.ok) {
      return Object.freeze({
        ok: false,
        reasonCode: "item_rate_limited",
        gateId: COST_GATE_ID,
      });
    }
    inFlight.set(itemKey, now);
    return Object.freeze({
      ok: true,
      reasonCode: "cost_gate_ok",
      gateId: COST_GATE_ID,
      gateVersion: COST_GATE_VERSION,
      release() {
        inFlight.delete(itemKey);
      },
    });
  }

  return Object.freeze({
    gateId: COST_GATE_ID,
    gateVersion: COST_GATE_VERSION,
    limits,
    begin,
    _debugState() {
      return {
        users: userBuckets.size,
        items: itemBuckets.size,
        inFlight: inFlight.size,
      };
    },
  });
}

module.exports = {
  COST_GATE_ID,
  COST_GATE_VERSION,
  DEFAULTS,
  createWardrobeAuthorityCostGate,
};
