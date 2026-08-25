"use strict";

const {EVENT_TYPES, isPositiveEvent} =
  require("../monitoring/wishlist_monitoring_engine");
const {
  WISHLIST_PUSH_GROUP_DETAIL_MAX_V1,
  WISHLIST_PUSH_GROUP_SUMMARY_THRESHOLD_V1,
} = require("../monitoring/wishlist_monitoring_constants");

function notificationForItem(item, events) {
  const deliverable = events.filter((event) => shouldNotify(item, event));
  if (!deliverable.length) return null;
  const positive = deliverable.some(isPositiveEvent);
  const negative = deliverable.some((event) =>
    !isPositiveEvent(event) &&
    event.type !== EVENT_TYPES.LOW_STOCK_ENTERED);
  const informational = deliverable.some((event) =>
    event.type === EVENT_TYPES.LOW_STOCK_ENTERED);
  const name = productName(deliverable[0]);
  const parts = [];
  const conditions = [];

  const pricePositive = deliverable.find((event) =>
    event.type === EVENT_TYPES.PRICE_TARGET_SATISFIED);
  const priceNegative = deliverable.find((event) =>
    event.type === EVENT_TYPES.PRICE_TARGET_UNSATISFIED);
  const sizePositive = deliverable.filter((event) =>
    event.type === EVENT_TYPES.SIZE_AVAILABLE).map((event) => event.sizeKey);
  const sizeNegative = deliverable.filter((event) =>
    event.type === EVENT_TYPES.SIZE_UNAVAILABLE).map((event) => event.sizeKey);
  const lowStock = deliverable.find((event) =>
    event.type === EVENT_TYPES.LOW_STOCK_ENTERED);

  if (pricePositive) {
    conditions.push("PRICE_TARGET_SATISFIED");
    parts.push(`cena dosiahla ${money(pricePositive.effectivePrice)}` +
      couponCopy(pricePositive.coupon) +
      ` a spĺňa tvoj cieľ ${money(pricePositive.targetPrice)}`);
  }
  if (priceNegative) {
    conditions.push("PRICE_TARGET_UNSATISFIED");
    parts.push(`cena je ${money(priceNegative.effectivePrice)}` +
      ` a je opäť nad cieľom ${money(priceNegative.targetPrice)}`);
  }
  if (sizePositive.length) {
    conditions.push("SIZE_AVAILABLE");
    parts.push(`veľkosť ${joinSizes(sizePositive)} je dostupná`);
  }
  if (sizeNegative.length) {
    conditions.push("SIZE_UNAVAILABLE");
    parts.push(`veľkosť ${joinSizes(sizeNegative)} už nie je dostupná`);
  }
  if (lowStock) {
    conditions.push("LOW_STOCK_ENTERED");
    parts.push("zásoby sú nízke");
  }

  const title = positive && negative ? "Wishlist má zmiešané zmeny" :
    (positive ? "Cieľ vo Wishliste bol dosiahnutý" :
      (informational && !negative ? "Informácia o Wishliste" :
        "Zmena vo Wishliste"));
  return {
    title,
    body: `${name}: ${sentence(parts)}.`,
    eventIds: deliverable.map((event) => event.eventId),
    conditions,
    polarity: positive && negative ? "MIXED" :
      (positive ? "POSITIVE" : (negative ? "NEGATIVE" : "INFO")),
    data: {
      type: "WISHLIST_V2_ITEM",
      wishlistItemId: item.wishlistItemId,
      variantId: item.variantId || "",
    },
  };
}

function groupedNotification(itemNotifications, {syncRunId = ""} = {}) {
  if (itemNotifications.length === 1) {
    return {
      ...itemNotifications[0],
      data: {
        ...itemNotifications[0].data,
        syncRunId: String(syncRunId || ""),
      },
    };
  }
  const eventIds = itemNotifications.flatMap((value) => value.eventIds);
  const count = itemNotifications.length;
  if (count >= WISHLIST_PUSH_GROUP_SUMMARY_THRESHOLD_V1) {
    return {
      title: "Nové zmeny vo Wishliste",
      body: `${count} položiek vo Wishliste má nové zmeny.`,
      eventIds,
      data: {
        type: "WISHLIST_V2_LIST",
        syncRunId: String(syncRunId || ""),
      },
    };
  }
  const detail = itemNotifications
    .slice(0, WISHLIST_PUSH_GROUP_DETAIL_MAX_V1)
    .map((value) => value.body)
    .join(" ");
  return {
    title: "Nové zmeny vo Wishliste",
    body: detail || `${count} položiek vo Wishliste má nové zmeny.`,
    eventIds,
    data: {
      type: "WISHLIST_V2_LIST",
      syncRunId: String(syncRunId || ""),
    },
  };
}

function shouldNotify(item, event) {
  if (event.type === EVENT_TYPES.PRICE_TARGET_SATISFIED ||
      event.type === EVENT_TYPES.PRICE_TARGET_UNSATISFIED) {
    return item.priceMonitoringEnabled === true;
  }
  if (event.type === EVENT_TYPES.SIZE_AVAILABLE ||
      event.type === EVENT_TYPES.SIZE_UNAVAILABLE) {
    return item.sizeMonitoringEnabled === true;
  }
  if (event.type === EVENT_TYPES.LOW_STOCK_ENTERED) {
    return true;
  }
  return false;
}

function productName(event) {
  return [event.brand, event.displayName].filter(Boolean).join(" ") ||
    "Položka vo Wishliste";
}
function money(value) {
  if (!value || !Number.isSafeInteger(value.amountMinor) || !value.currency) {
    return "neoverená cena";
  }
  const amount = (value.amountMinor / 100).toFixed(2).replace(".", ",");
  return `${amount} ${value.currency === "EUR" ? "€" : value.currency}`;
}
function couponCopy(coupon) {
  return coupon?.required === true && coupon.code ?
    ` s kódom ${coupon.code}` : "";
}
function joinSizes(values) {
  const unique = [...new Set(values)].sort();
  if (unique.length < 2) return unique[0] || "";
  return `${unique.slice(0, -1).join(", ")} a ${unique.at(-1)}`;
}
function sentence(parts) {
  if (parts.length < 2) return parts[0] || "nastala zmena";
  return `${parts.slice(0, -1).join(", ")} a ${parts.at(-1)}`;
}

module.exports = {
  WISHLIST_PUSH_GROUP_DETAIL_MAX_V1,
  WISHLIST_PUSH_GROUP_SUMMARY_THRESHOLD_V1,
  groupedNotification,
  notificationForItem,
  shouldNotify,
};
