"use strict";

const {
  parseCjShoppingFeedRecord,
  parseXmlShoppingItems,
  iterateCsvRecords,
} = require("../cj/cj_product_feed_parser");
const {EXPECTED_CURRENCY} = require("./reserved_cj_constants");

/**
 * Local feed-sample validator for owner-supplied CJ/Reserved samples.
 * Does not upload, log full raw feed, or persist to repo.
 */
function validateCjFeedSample(input, {
  expectedCurrency = EXPECTED_CURRENCY,
  format = "auto",
} = {}) {
  const records = loadRecords(input, format);
  const fieldPresence = Object.create(null);
  const productIds = new Set();
  const groupIds = new Set();
  const currencies = new Set();
  const issues = [];
  let gtinCount = 0;
  let colorCount = 0;
  let sizeCount = 0;
  let availabilityCount = 0;
  let saleCount = 0;
  let imageCount = 0;
  let additionalImageRows = 0;
  let priceCount = 0;

  for (let i = 0; i < records.length; i++) {
    let parsed;
    try {
      parsed = typeof records[i].id === "string" && records[i].network === "cj" ?
        records[i] :
        parseCjShoppingFeedRecord(records[i], {rowIndex: i + 1});
    } catch (error) {
      issues.push({
        rowIndex: i + 1,
        code: error.code || "INVALID_PAYLOAD",
        message: error.message,
      });
      continue;
    }

    for (const key of parsed.rawKeysPresent || []) {
      fieldPresence[key] = (fieldPresence[key] || 0) + 1;
    }
    if (productIds.has(parsed.id)) {
      issues.push({rowIndex: i + 1, code: "DUPLICATE_ID", message: parsed.id});
    }
    productIds.add(parsed.id);
    if (parsed.itemGroupId) groupIds.add(parsed.itemGroupId);
    if (parsed.gtin) gtinCount++;
    if (parsed.color) colorCount++;
    if (parsed.size) sizeCount++;
    if (parsed.availability) availabilityCount++;
    if (parsed.salePrice) saleCount++;
    if (parsed.imageLink) imageCount++;
    if (parsed.additionalImageLinks?.length) additionalImageRows++;
    if (parsed.price) {
      priceCount++;
      currencies.add(parsed.price.currency);
      if (expectedCurrency && parsed.price.currency !== expectedCurrency) {
        issues.push({
          rowIndex: i + 1,
          code: "CURRENCY_MISMATCH",
          message: parsed.price.currency,
        });
      }
    }
    if (parsed.link) {
      try {
        // eslint-disable-next-line no-new
        new URL(parsed.link);
      } catch (_) {
        issues.push({
          rowIndex: i + 1,
          code: "BAD_URL",
          message: "link",
        });
      }
    }
  }

  const n = records.length || 1;
  const pct = (count) => Math.round((count / n) * 1000) / 10;

  return {
    recordCount: records.length,
    uniqueProductIds: productIds.size,
    uniqueItemGroupIds: groupIds.size,
    currencies: [...currencies].sort(),
    expectedCurrency,
    population: {
      gtinPct: pct(gtinCount),
      colorPct: pct(colorCount),
      sizePct: pct(sizeCount),
      availabilityPct: pct(availabilityCount),
      pricePct: pct(priceCount),
      salePricePct: pct(saleCount),
      imagePct: pct(imageCount),
      additionalImageRowPct: pct(additionalImageRows),
    },
    fieldPresence,
    issueCount: issues.length,
    // Cap issues in report — never dump raw feed.
    issuesSample: issues.slice(0, 50),
    sanitized: true,
  };
}

function loadRecords(input, format) {
  if (Array.isArray(input)) return input;
  if (input && typeof input === "object" && Array.isArray(input.records)) {
    return input.records;
  }
  if (typeof input !== "string") {
    throw new Error("sample_input_invalid");
  }
  const trimmed = input.trim();
  const detected = format === "auto" ?
    (trimmed.startsWith("<") ? "xml" : "csv") : format;
  if (detected === "xml") return parseXmlShoppingItems(trimmed);
  if (detected === "csv") {
    const rows = [];
    for (const {record} of iterateCsvRecords(trimmed)) {
      rows.push(record);
    }
    return rows;
  }
  throw new Error("sample_format_unsupported");
}

module.exports = {
  validateCjFeedSample,
};
