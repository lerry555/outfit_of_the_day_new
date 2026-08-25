"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  groupedNotification,
  notificationForItem,
  shouldNotify,
} = require("./wishlist_notification_templates");
const {EVENT_TYPES} = require("../monitoring/wishlist_monitoring_engine");

const item = {
  wishlistItemId: "wish_1",
  variantId: "navy",
  priceMonitoringEnabled: true,
  sizeMonitoringEnabled: true,
};

test("same-item combined notification preserves conditions", () => {
  const note = notificationForItem(item, [
    {
      eventId: "e1",
      type: EVENT_TYPES.PRICE_TARGET_SATISFIED,
      effectivePrice: {amountMinor: 1900, currency: "EUR"},
      targetPrice: {amountMinor: 2000, currency: "EUR"},
      coupon: {required: true, code: "SAVE10"},
      brand: "Brand",
      displayName: "Mikina",
    },
    {
      eventId: "e2",
      type: EVENT_TYPES.SIZE_AVAILABLE,
      sizeKey: "L",
      brand: "Brand",
      displayName: "Mikina",
    },
  ]);
  assert.ok(note.body.includes("SAVE10"));
  assert.ok(note.body.includes("L"));
  assert.equal(note.data.type, "WISHLIST_V2_ITEM");
  assert.deepEqual(note.conditions, [
    "PRICE_TARGET_SATISFIED",
    "SIZE_AVAILABLE",
  ]);
});

test("monitor OFF suppresses tracked push", () => {
  assert.equal(shouldNotify({
    ...item, priceMonitoringEnabled: false,
  }, {type: EVENT_TYPES.PRICE_TARGET_SATISFIED}), false);
  assert.equal(shouldNotify({
    ...item, sizeMonitoringEnabled: false,
  }, {type: EVENT_TYPES.SIZE_UNAVAILABLE}), false);
});

test("grouped notifications use WISHLIST_V2_LIST", () => {
  const one = notificationForItem(item, [{
    eventId: "e1",
    type: EVENT_TYPES.PRICE_TARGET_UNSATISFIED,
    effectivePrice: {amountMinor: 2500, currency: "EUR"},
    targetPrice: {amountMinor: 2000, currency: "EUR"},
  }]);
  const many = groupedNotification([one, one, one, one, one, one], {
    syncRunId: "s1",
  });
  assert.equal(many.data.type, "WISHLIST_V2_LIST");
  assert.ok(many.body.includes("6 položiek"));
});
