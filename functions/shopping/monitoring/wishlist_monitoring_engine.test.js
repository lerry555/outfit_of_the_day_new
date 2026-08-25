"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  EVENT_TYPES,
  LOW_STOCK_QUANTITY_POLICY_V1,
  acknowledgeHighlight,
  evaluateWishlistMonitoring,
  sortWishlistItems,
} = require("./wishlist_monitoring_engine");
const {
  USER_TRACKING_OPTION_COUNT,
  LOW_STOCK_TRACKING_OPTION_COUNT,
  USER_LOW_STOCK_MONITORING_OPTION_COUNT,
  PARTNER_POLLING_COUNT,
  WISHLIST_LAST_EVENT_IDS_CAP_V1,
} = require("./wishlist_monitoring_constants");

function item({
  priceState = "UNKNOWN",
  sizes = {M: "UNKNOWN"},
  target = 2000,
  lifecycle = "ACTIVE",
  lowStockState = "UNKNOWN",
  lowStockEpisode = null,
} = {}) {
  return {
    schemaVersion: 2,
    ownerUid: "u1",
    wishlistItemId: "wish_1",
    variantId: "navy",
    selectedSizes: Object.keys(sizes),
    preferredSize: Object.keys(sizes)[0] || null,
    targetPrice: {amountMinor: target, currency: "EUR"},
    priceMonitoringEnabled: true,
    sizeMonitoringEnabled: true,
    tracking: {
      evaluatedPriceState: priceState,
      evaluatedSizeStates: sizes,
      lifecycleState: lifecycle,
      lowStockState,
      lowStockEpisode,
      lastEventIds: [],
      highlight: {state: "NONE", eventIds: [], occurredAt: null},
    },
  };
}

function facts({
  price = 2500,
  priceState,
  sizes = {M: "UNAVAILABLE"},
  sizeEvidence,
  success = true,
  quantities = {},
  lifecycle = "ACTIVE",
  partnerLowStock = false,
  coupon = null,
} = {}) {
  const resolvedPriceState = priceState ||
    (price <= 2000 ? "SATISFIED" : "UNSATISFIED");
  const evidence = sizeEvidence || Object.fromEntries(
    Object.entries(sizes).map(([key, value]) =>
      [key, value === "AVAILABLE" || value === "UNAVAILABLE"]));
  return {
    successfulVerification: success,
    priceState: resolvedPriceState,
    sizeStates: sizes,
    sizeEvidence: evidence,
    effectivePrice: {amountMinor: price, currency: "EUR"},
    reliableQuantities: quantities,
    partnerReliableLowStockSignal: partnerLowStock,
    lifecycleState: lifecycle,
    coupon,
    priceVerifiedAt: "2026-08-15T10:00:00.000Z",
    availabilityVerifiedAt: "2026-08-15T10:00:00.000Z",
    lastSuccessfulVerification: "2026-08-15T10:00:00.000Z",
    product: {brand: "Brand", normalizedModelIdentity: "Mikina"},
  };
}

function evaluate(value, snapshot, revision, baseline = false) {
  return evaluateWishlistMonitoring({
    item: value,
    facts: snapshot,
    catalogRevision: `rev_${revision}`,
    syncRunId: `sync_${revision}`,
    now: 1_700_000_000_000 + revision,
    baseline,
  });
}

test("tracking option counts remain locked", () => {
  assert.equal(USER_TRACKING_OPTION_COUNT, 2);
  assert.equal(LOW_STOCK_TRACKING_OPTION_COUNT, 0);
  assert.equal(USER_LOW_STOCK_MONITORING_OPTION_COUNT, 0);
  assert.equal(PARTNER_POLLING_COUNT, 0);
  assert.equal(LOW_STOCK_QUANTITY_POLICY_V1.maxInclusiveQuantity, 3);
  assert.equal(WISHLIST_LAST_EVENT_IDS_CAP_V1, 20);
});

test("baseline satisfied+available creates no event or gold", () => {
  const result = evaluate(item(), facts({
    price: 1800, sizes: {M: "AVAILABLE"},
  }), 1, true);
  assert.equal(result.item.tracking.evaluatedPriceState, "SATISFIED");
  assert.equal(result.item.tracking.evaluatedSizeStates.M, "AVAILABLE");
  assert.deepEqual(result.events, []);
  assert.equal(result.newlyGold, false);
});

test("PRICE matrix: 50→21 no event; 21→20 gold; 20→18 no; 18→22 neg; 22→19 gold", () => {
  let current = evaluate(item(), facts({price: 5000}), 1, true).item;
  const steps = [
    [2100, []],
    [2000, [EVENT_TYPES.PRICE_TARGET_SATISFIED]],
    [1800, []],
    [2200, [EVENT_TYPES.PRICE_TARGET_UNSATISFIED]],
    [1900, [EVENT_TYPES.PRICE_TARGET_SATISFIED]],
  ];
  for (let index = 0; index < steps.length; index++) {
    const [price, expected] = steps[index];
    const result = evaluate(current, facts({price}), index + 2);
    assert.deepEqual(result.events.map((event) => event.type), expected);
    if (expected[0] === EVENT_TYPES.PRICE_TARGET_SATISFIED) {
      assert.equal(result.newlyGold, true);
      assert.equal(result.item.tracking.highlightState, "GOLD");
    }
    if (expected[0] === EVENT_TYPES.PRICE_TARGET_UNSATISFIED) {
      assert.equal(result.newlyGold, false);
    }
    current = result.item;
  }
});

test("SIZE unavailable→available gold; available→unavailable no gold", () => {
  let current = evaluate(item({sizes: {M: "UNKNOWN"}}),
    facts({sizes: {M: "UNAVAILABLE"}}), 1, true).item;
  let result = evaluate(current, facts({sizes: {M: "AVAILABLE"}}), 2);
  assert.deepEqual(result.events.map((event) => event.type),
    [EVENT_TYPES.SIZE_AVAILABLE]);
  assert.equal(result.newlyGold, true);
  current = result.item;
  result = evaluate(current, facts({sizes: {M: "UNAVAILABLE"}}), 3);
  assert.deepEqual(result.events.map((event) => event.type),
    [EVENT_TYPES.SIZE_UNAVAILABLE]);
  assert.equal(result.newlyGold, false);
});

test("UNKNOWN size never emits transition", () => {
  const current = item({sizes: {M: "UNKNOWN"}});
  const result = evaluate(current, facts({sizes: {M: "AVAILABLE"}}), 1);
  assert.deepEqual(result.events, []);
  assert.equal(result.item.tracking.evaluatedSizeStates.M, "AVAILABLE");
});

test("secondary selected size available while preferred unavailable", () => {
  const current = evaluate(item({sizes: {M: "UNKNOWN", L: "UNKNOWN"}}),
    facts({sizes: {M: "UNAVAILABLE", L: "UNAVAILABLE"}}), 1, true).item;
  const result = evaluate(current, facts({
    sizes: {M: "UNAVAILABLE", L: "AVAILABLE"},
  }), 2);
  assert.equal(result.events.length, 1);
  assert.equal(result.events[0].type, EVENT_TYPES.SIZE_AVAILABLE);
  assert.equal(result.events[0].sizeKey, "L");
  assert.equal(result.newlyGold, true);
});

test("A) UNKNOWN + ACTIVE→DISCONTINUED keeps UNKNOWN, no SIZE_UNAVAILABLE", () => {
  const current = item({sizes: {M: "UNKNOWN"}, lifecycle: "ACTIVE"});
  const result = evaluate(current, facts({
    lifecycle: "DISCONTINUED",
    sizes: {},
    sizeEvidence: {M: false},
    priceState: "UNKNOWN",
  }), 2);
  assert.equal(result.item.tracking.evaluatedSizeStates.M, "UNKNOWN");
  assert.equal(result.item.tracking.lifecycleState, "DISCONTINUED");
  assert.equal(result.events.some((event) =>
    event.type === EVENT_TYPES.SIZE_UNAVAILABLE), false);
  assert.equal(result.newlyGold, false);
});

test("B) AVAILABLE + size UNAVAILABLE evidence + discontinued emits SIZE_UNAVAILABLE", () => {
  const current = evaluate(item({sizes: {M: "UNKNOWN"}}),
    facts({sizes: {M: "AVAILABLE"}}), 1, true).item;
  const result = evaluate(current, facts({
    lifecycle: "DISCONTINUED",
    sizes: {M: "UNAVAILABLE"},
    sizeEvidence: {M: true},
    priceState: "UNKNOWN",
  }), 2);
  assert.deepEqual(result.events.map((event) => event.type),
    [EVENT_TYPES.SIZE_UNAVAILABLE]);
  assert.equal(result.newlyGold, false);
});

test("C) UNAVAILABLE + DISCONTINUED does not duplicate SIZE_UNAVAILABLE", () => {
  const current = evaluate(item({sizes: {M: "UNKNOWN"}}),
    facts({sizes: {M: "UNAVAILABLE"}}), 1, true).item;
  const result = evaluate(current, facts({
    lifecycle: "DISCONTINUED",
    sizes: {M: "UNAVAILABLE"},
    sizeEvidence: {M: true},
    priceState: "UNKNOWN",
  }), 2);
  assert.deepEqual(result.events, []);
});

test("D) DISCONTINUED→ACTIVE still UNAVAILABLE has no SIZE_AVAILABLE", () => {
  const current = item({
    sizes: {M: "UNAVAILABLE"}, lifecycle: "DISCONTINUED",
  });
  const result = evaluate(current, facts({
    lifecycle: "ACTIVE",
    sizes: {M: "UNAVAILABLE"},
  }), 2);
  assert.deepEqual(result.events, []);
});

test("E) DISCONTINUED→ACTIVE + UNAVAILABLE→AVAILABLE gold", () => {
  const current = item({
    sizes: {M: "UNAVAILABLE"}, lifecycle: "DISCONTINUED",
  });
  const result = evaluate(current, facts({
    lifecycle: "ACTIVE",
    sizes: {M: "AVAILABLE"},
  }), 2);
  assert.deepEqual(result.events.map((event) => event.type),
    [EVENT_TYPES.SIZE_AVAILABLE]);
  assert.equal(result.newlyGold, true);
});

test("F) lifecycle alone cannot manufacture UNKNOWN→UNAVAILABLE", () => {
  const current = item({sizes: {M: "UNKNOWN"}, lifecycle: "ACTIVE"});
  const result = evaluate(current, facts({
    lifecycle: "DISCONTINUED",
    sizes: {M: "UNAVAILABLE"},
    sizeEvidence: {M: false},
    priceState: "UNKNOWN",
  }), 2);
  assert.equal(result.item.tracking.evaluatedSizeStates.M, "UNKNOWN");
  assert.deepEqual(result.events, []);
});

test("refresh failure preserves state and emits no events", () => {
  const current = evaluate(item(), facts({price: 1800, sizes: {M: "AVAILABLE"}}),
    1, true).item;
  const result = evaluate(current, facts({success: false}), 2);
  assert.equal(result.item.tracking.evaluatedPriceState, "SATISFIED");
  assert.equal(result.item.tracking.evaluatedSizeStates.M, "AVAILABLE");
  assert.equal(result.item.tracking.freshness.stale, true);
  assert.deepEqual(result.events, []);
});

test("event identity is stable across retries without wall-clock", () => {
  const current = evaluate(item(), facts({price: 2500}), 1, true).item;
  const first = evaluate(current, facts({price: 1900}), 2);
  const second = evaluate(current, facts({price: 1900}), 2);
  assert.equal(first.events[0].eventId, second.events[0].eventId);
  assert.equal(first.events[0].syncRunId, "sync_2");
});

test("same-item combined price+size positive events", () => {
  const current = evaluate(item({sizes: {M: "UNKNOWN"}}),
    facts({price: 2500, sizes: {M: "UNAVAILABLE"}}), 1, true).item;
  const result = evaluate(current, facts({
    price: 1800, sizes: {M: "AVAILABLE"},
  }), 2);
  assert.deepEqual(result.events.map((event) => event.type).sort(), [
    EVENT_TYPES.PRICE_TARGET_SATISFIED,
    EVENT_TYPES.SIZE_AVAILABLE,
  ].sort());
  assert.equal(result.newlyGold, true);
});

test("low stock episode notifies once; 3→2→1 no repeat; replenish closes", () => {
  let current = evaluate(item(), facts({price: 2500, quantities: {M: 10}}),
    1, true).item;
  let result = evaluate(current, facts({price: 2500, quantities: {M: 3}}), 2);
  assert.equal(result.events.some((event) =>
    event.type === EVENT_TYPES.LOW_STOCK_ENTERED), true);
  assert.equal(result.newlyGold, false);
  current = result.item;
  result = evaluate(current, facts({price: 2500, quantities: {M: 1}}), 3);
  assert.equal(result.events.some((event) =>
    event.type === EVENT_TYPES.LOW_STOCK_ENTERED), false);
  current = result.item;
  result = evaluate(current, facts({price: 2500, quantities: {M: 8}}), 4);
  assert.equal(result.item.tracking.lowStockEpisode.status, "CLOSED");
  current = result.item;
  result = evaluate(current, facts({price: 2500, quantities: {M: 2}}), 5);
  assert.equal(result.events.some((event) =>
    event.type === EVENT_TYPES.LOW_STOCK_ENTERED), true);
});

test("30 gold items all remain gold tier when sorting", () => {
  const items = Array.from({length: 30}, (_, index) => ({
    wishlistItemId: `w${String(index).padStart(2, "0")}`,
    updatedAt: index,
    tracking: {
      highlightState: "GOLD",
      highlight: {state: "UNACKNOWLEDGED", eventIds: [`e${index}`]},
      sortTier: 0,
      sortEventAt: index,
      lowStockState: "NORMAL",
    },
  })).concat([{
    wishlistItemId: "low",
    updatedAt: 999,
    tracking: {sortTier: 1, lowStockState: "LOW_STOCK", highlightState: "NONE"},
  }, {
    wishlistItemId: "normal",
    updatedAt: 1000,
    tracking: {sortTier: 2, lowStockState: "NORMAL", highlightState: "NONE"},
  }]);
  const sorted = sortWishlistItems(items);
  assert.equal(sorted.slice(0, 30).every((value) =>
    value.tracking.highlightState === "GOLD"), true);
  assert.equal(sorted[30].wishlistItemId, "low");
  assert.equal(sorted[31].wishlistItemId, "normal");
});

test("acknowledge clears gold novelty idempotently", () => {
  let current = evaluate(item(), facts({price: 2500}), 1, true).item;
  current = evaluate(current, facts({price: 1800}), 2).item;
  assert.equal(current.tracking.highlightState, "GOLD");
  current = acknowledgeHighlight(current, 99);
  assert.equal(current.tracking.highlightState, "NONE");
  current = acknowledgeHighlight(current, 100);
  assert.equal(current.tracking.highlight.state, "ACKNOWLEDGED");
});
