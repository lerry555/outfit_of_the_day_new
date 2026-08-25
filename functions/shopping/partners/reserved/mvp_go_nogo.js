"use strict";

/**
 * MVP go / no-go criteria for Reserved SK feed sample.
 * Size monitoring limitation must be owner-accepted if no per-size stock.
 */

const MVP_GO_CRITERIA = Object.freeze({
  required: [
    "stable listing/product id populated",
    "public SK product or authorized tracking URL",
    "EUR price populated",
    "meaningful exact color (or equivalent variant discriminator)",
    "at least one image_link",
    "recurring feed or Product Search access confirmed",
    "data/image usage rights answered for shopping display",
  ],
});

const MVP_GO_WITH_LIMITATIONS_CRITERIA = Object.freeze({
  when: [
    "size labels present but no authoritative per-size availability",
    "OR size entirely missing → selected size remains UNKNOWN",
    "OR only model/lifestyle images (no packshot metadata)",
    "OR no GTIN (partner-scoped identity only)",
    "OR feed completeness not guaranteed → no absence→discontinued",
  ],
  ownerMustAccept: [
    "Wishlist size monitoring may be unavailable/limited for Reserved",
    "Wardrobe clean garment image may require user photo",
    "Lifecycle discontinue-from-absence disabled",
  ],
});

const MVP_NO_GO_CRITERIA = Object.freeze({
  anyOf: [
    "no stable product/listing id",
    "no usable product URL",
    "non-EUR or missing price for SK market without confirmed EUR feed",
    "no color/variant discriminator and no item_group strategy",
    "no image references",
    "no authorized recurring access",
    "rights forbid in-app catalog display of names/prices/images",
    "only scraping remains as integration path",
  ],
});

const SIZE_MONITORING_READINESS = Object.freeze({
  status: "SAMPLE_REQUIRED",
  note: "Do not advertise size availability tracking for Reserved until sample proves per-size stock truth.",
});

function evaluateMvpGate(sampleReport) {
  if (!sampleReport || sampleReport.recordCount === 0) {
    return {decision: "NO_GO", reasons: ["empty_sample"]};
  }
  const reasons = [];
  if (sampleReport.uniqueProductIds < 1) reasons.push("no_product_ids");
  if ((sampleReport.population?.pricePct || 0) < 80) reasons.push("price_sparse");
  if ((sampleReport.population?.imagePct || 0) < 50) reasons.push("images_sparse");
  if ((sampleReport.population?.colorPct || 0) < 50) {
    reasons.push("color_sparse_limitation");
  }
  if (reasons.some((r) => r === "no_product_ids")) {
    return {decision: "NO_GO", reasons};
  }
  const limitations = [];
  if ((sampleReport.population?.sizePct || 0) < 50 ||
      (sampleReport.population?.availabilityPct || 0) < 50) {
    limitations.push("size_monitoring_limited");
  }
  if ((sampleReport.population?.gtinPct || 0) < 20) {
    limitations.push("gtin_sparse");
  }
  if (reasons.includes("color_sparse_limitation") &&
      sampleReport.uniqueItemGroupIds < 1) {
    return {decision: "NO_GO", reasons: [...reasons, "no_variant_strategy"]};
  }
  if (limitations.length || reasons.includes("color_sparse_limitation")) {
    return {
      decision: "GO_WITH_LIMITATIONS",
      reasons,
      limitations,
    };
  }
  return {decision: "GO", reasons: [], limitations: []};
}

module.exports = {
  MVP_GO_CRITERIA,
  MVP_GO_WITH_LIMITATIONS_CRITERIA,
  MVP_NO_GO_CRITERIA,
  SIZE_MONITORING_READINESS,
  evaluateMvpGate,
};
