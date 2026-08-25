"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {
  evaluateWishlistMonitoring,
  EVENT_TYPES,
} = require("./wishlist_monitoring_engine");

const fixturePath = path.join(
  __dirname,
  "../../../test/fixtures/wishlist_tracking_parity_cases.json",
);

function mapPrice(state) {
  return String(state || "UNKNOWN").toUpperCase();
}
function mapSize(state) {
  return String(state || "UNKNOWN").toUpperCase();
}
function mapEventType(type) {
  const table = {
    priceTargetSatisfied: EVENT_TYPES.PRICE_TARGET_SATISFIED,
    priceTargetUnsatisfied: EVENT_TYPES.PRICE_TARGET_UNSATISFIED,
    sizeAvailable: EVENT_TYPES.SIZE_AVAILABLE,
    sizeUnavailable: EVENT_TYPES.SIZE_UNAVAILABLE,
    PRICE_TARGET_SATISFIED: EVENT_TYPES.PRICE_TARGET_SATISFIED,
    PRICE_TARGET_UNSATISFIED: EVENT_TYPES.PRICE_TARGET_UNSATISFIED,
    SIZE_AVAILABLE: EVENT_TYPES.SIZE_AVAILABLE,
    SIZE_UNAVAILABLE: EVENT_TYPES.SIZE_UNAVAILABLE,
  };
  return table[type] || type;
}

test("dart/node parity fixtures produce matching transitions", () => {
  const cases = JSON.parse(fs.readFileSync(fixturePath, "utf8"));
  assert.ok(Array.isArray(cases) && cases.length > 0);
  for (const entry of cases) {
    const selectedSizes = Object.keys(entry.previous.sizeStates || {});
    const item = {
      ownerUid: "parity",
      wishlistItemId: entry.wishlistItemId || "wish_parity",
      variantId: entry.variantId || "variant_parity",
      selectedSizes,
      preferredSize: entry.preferredSizeKey || selectedSizes[0] || null,
      targetPrice: entry.targetPrice,
      priceMonitoringEnabled: true,
      sizeMonitoringEnabled: true,
      tracking: {
        evaluatedPriceState: mapPrice(entry.previous.priceState),
        evaluatedSizeStates: Object.fromEntries(
          Object.entries(entry.previous.sizeStates || {}).map(([key, value]) =>
            [key, mapSize(value)])),
        lastEventIds: [],
        highlight: {state: "NONE", eventIds: [], occurredAt: null},
        lifecycleState: entry.previous.lifecycleState || "ACTIVE",
      },
    };
    const sizeStates = Object.fromEntries(
      Object.entries(entry.observation.sizeStates || {}).map(([key, value]) =>
        [key, mapSize(value)]));
    const sizeEvidence = entry.observation.sizeEvidence ||
      Object.fromEntries(Object.keys(sizeStates).map((key) => {
        const value = sizeStates[key];
        return [key, value === "AVAILABLE" || value === "UNAVAILABLE"];
      }));
    const result = evaluateWishlistMonitoring({
      item,
      facts: {
        successfulVerification: entry.observation.successful !== false,
        priceState: mapPrice(entry.observation.priceState),
        sizeStates,
        sizeEvidence,
        effectivePrice: entry.observation.effectivePublicPrice || null,
        lifecycleState: entry.observation.lifecycleState ||
          entry.previous.lifecycleState || "ACTIVE",
        reliableQuantities: {},
      },
      catalogRevision: entry.catalogRevision || "parity_rev",
      syncRunId: entry.syncRunId || "parity_sync",
      now: 1,
      baseline: entry.baseline === true,
    });
    const expectedTypes = (entry.expectedEventTypes || []).map(mapEventType);
    assert.deepEqual(
      result.events
        .filter((event) => event.type !== EVENT_TYPES.LOW_STOCK_ENTERED)
        .map((event) => event.type),
      expectedTypes,
      entry.id,
    );
    assert.equal(result.newlyGold, entry.expectedGold === true, entry.id);
    if (entry.expectedSizeStates) {
      for (const [key, value] of Object.entries(entry.expectedSizeStates)) {
        assert.equal(
          result.item.tracking.evaluatedSizeStates[key],
          mapSize(value),
          `${entry.id}:${key}`,
        );
      }
    }
  }
});
