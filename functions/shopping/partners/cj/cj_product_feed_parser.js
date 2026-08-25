"use strict";

const {createPartnerError, PARTNER_ERROR} = require("../partner_errors");
const {CJ_AVAILABILITY_VALUES} = require("./cj_product_feed_schema");

/**
 * Generic CJ shopping-feed record parser (network layer).
 * Accepts already-decoded record objects (from CSV/XML/JSON sample).
 * Does NOT call CJ. Does NOT assume Reserved population.
 */
function parseCjShoppingFeedRecord(raw, {rowIndex = 0} = {}) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw createPartnerError(
      PARTNER_ERROR.INVALID_PAYLOAD,
      "cj_feed_record_invalid",
      {rowIndex},
    );
  }
  const normalized = normalizeKeys(raw);
  const id = text(normalized.id || normalized["g:id"]);
  if (!id) {
    throw createPartnerError(
      PARTNER_ERROR.INVALID_PAYLOAD,
      "cj_feed_id_required",
      {rowIndex},
    );
  }

  const price = parseMoneyField(
    normalized.price || normalized["g:price"], "price",
  );
  const salePriceRaw = normalized.sale_price || normalized["g:sale_price"];
  const salePrice = salePriceRaw == null || String(salePriceRaw).trim() === "" ?
    null : parseMoneyField(salePriceRaw, "sale_price");

  const availability = normalizeAvailability(
    normalized.availability || normalized["g:availability"],
  );

  const additionalImages = collectAdditionalImages(normalized);

  return {
    network: "cj",
    schema: "google_shopping_aligned",
    id,
    title: text(normalized.title || normalized["g:title"]),
    description: text(normalized.description || normalized["g:description"]),
    link: text(normalized.link || normalized["g:link"]),
    imageLink: text(normalized.image_link || normalized["g:image_link"]),
    additionalImageLinks: additionalImages,
    availability,
    price,
    salePrice,
    brand: text(normalized.brand || normalized["g:brand"]),
    gtin: text(normalized.gtin || normalized["g:gtin"]),
    mpn: text(normalized.mpn || normalized["g:mpn"]),
    itemGroupId: text(
      normalized.item_group_id || normalized["g:item_group_id"],
    ),
    color: text(normalized.color || normalized["g:color"]),
    size: text(normalized.size || normalized["g:size"]),
    sizeSystem: text(normalized.size_system || normalized["g:size_system"]),
    googleProductCategory: text(
      normalized.google_product_category ||
      normalized["g:google_product_category"],
    ),
    productType: text(
      normalized.product_type || normalized["g:product_type"],
    ),
    condition: text(normalized.condition || normalized["g:condition"]),
    // Never invent image roles from CJ shopping feed.
    imageRole: null,
    rawKeysPresent: Object.keys(normalized).sort(),
  };
}

/**
 * Stream-friendly CSV line parser (header + rows). Bounded memory: one row at a time.
 */
function* iterateCsvRecords(csvText) {
  if (typeof csvText !== "string") {
    throw createPartnerError(
      PARTNER_ERROR.INVALID_PAYLOAD,
      "cj_csv_text_required",
    );
  }
  const lines = splitCsvLines(csvText);
  if (!lines.length) return;
  const header = parseCsvLine(lines[0]).map((h) => h.trim());
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i];
    if (!String(line || "").trim()) continue;
    const cells = parseCsvLine(line);
    const row = {};
    for (let c = 0; c < header.length; c++) {
      row[header[c]] = cells[c] == null ? "" : cells[c];
    }
    yield {rowIndex: i, record: row};
  }
}

function parseCsvFeed(csvText) {
  const records = [];
  for (const {rowIndex, record} of iterateCsvRecords(csvText)) {
    records.push(parseCjShoppingFeedRecord(record, {rowIndex}));
  }
  return records;
}

/**
 * Minimal XML SHOPITEM / item extractor for Google Shopping–shaped samples.
 * Not a full XML DOM — streaming tag slices for local samples only.
 */
function parseXmlShoppingItems(xmlText) {
  if (typeof xmlText !== "string") {
    throw createPartnerError(
      PARTNER_ERROR.INVALID_PAYLOAD,
      "cj_xml_text_required",
    );
  }
  const items = [];
  const itemRegex = /<(?:item|entry|SHOPITEM)\b[^>]*>([\s\S]*?)<\/(?:item|entry|SHOPITEM)>/gi;
  let match;
  let rowIndex = 0;
  while ((match = itemRegex.exec(xmlText)) !== null) {
    rowIndex += 1;
    const body = match[1];
    const record = {};
    const tagRegex = /<(?:g:)?([a-zA-Z0-9_:-]+)>([\s\S]*?)<\/(?:g:)?\1>/g;
    let tag;
    while ((tag = tagRegex.exec(body)) !== null) {
      const key = tag[1].replace(/^g:/, "").toLowerCase();
      const value = decodeXml(tag[2].trim());
      if (key === "additional_image_link") {
        if (!Array.isArray(record.additional_image_link)) {
          record.additional_image_link = [];
        }
        record.additional_image_link.push(value);
      } else if (record[key] == null) {
        record[key] = value;
      }
    }
    items.push(parseCjShoppingFeedRecord(record, {rowIndex}));
  }
  return items;
}

function normalizeKeys(raw) {
  const out = {};
  for (const [key, value] of Object.entries(raw)) {
    const k = String(key).trim();
    out[k] = value;
    out[k.toLowerCase()] = value;
  }
  return out;
}

function text(value) {
  if (value == null) return null;
  const s = String(value).trim();
  return s === "" ? null : s;
}

function parseMoneyField(raw, field) {
  const s = String(raw || "").trim();
  // Google Shopping: "12.34 EUR" or "12.34USD"
  const match = s.match(/^([0-9]+(?:\.[0-9]+)?)\s*([A-Za-z]{3})$/);
  if (!match) {
    throw createPartnerError(
      PARTNER_ERROR.INVALID_MONEY,
      `cj_feed_invalid_${field}`,
    );
  }
  const major = Number(match[1]);
  if (!Number.isFinite(major) || major < 0) {
    throw createPartnerError(
      PARTNER_ERROR.INVALID_MONEY,
      `cj_feed_invalid_${field}_amount`,
    );
  }
  // Convert to minor units only for 2-decimal currencies in samples.
  // Exact currency minor-unit rules remain SAMPLE_REQUIRED for edge cases.
  const amountMinor = Math.round(major * 100);
  if (!Number.isSafeInteger(amountMinor)) {
    throw createPartnerError(
      PARTNER_ERROR.INVALID_MONEY,
      `cj_feed_invalid_${field}_minor`,
    );
  }
  return {
    amountMinor,
    currency: match[2].toUpperCase(),
    sourceText: s,
  };
}

function normalizeAvailability(raw) {
  if (raw == null || String(raw).trim() === "") return null;
  const value = String(raw).trim().toLowerCase().replace(/\s+/g, "_");
  if (!CJ_AVAILABILITY_VALUES.includes(value)) {
    throw createPartnerError(
      PARTNER_ERROR.SCHEMA_CHANGED,
      "cj_feed_availability_unknown",
      {value},
    );
  }
  return value;
}

function collectAdditionalImages(normalized) {
  const out = [];
  const multi = normalized.additional_image_link ||
    normalized["g:additional_image_link"];
  if (Array.isArray(multi)) {
    for (const item of multi) {
      const t = text(item);
      if (t) out.push(t);
    }
  } else if (multi != null) {
    const t = text(multi);
    if (t) out.push(t);
  }
  for (let i = 1; i <= 10; i++) {
    const t = text(
      normalized[`additional_image_link${i}`] ||
      normalized[`additional_image_link_${i}`],
    );
    if (t) out.push(t);
  }
  return out;
}

function splitCsvLines(text) {
  return text.replace(/^\uFEFF/, "").split(/\r?\n/);
}

function parseCsvLine(line) {
  const result = [];
  let current = "";
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (inQuotes) {
      if (ch === '"') {
        if (line[i + 1] === '"') {
          current += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        current += ch;
      }
    } else if (ch === '"') {
      inQuotes = true;
    } else if (ch === ",") {
      result.push(current);
      current = "";
    } else {
      current += ch;
    }
  }
  result.push(current);
  return result;
}

function decodeXml(value) {
  return value
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&");
}

module.exports = {
  iterateCsvRecords,
  parseCjShoppingFeedRecord,
  parseCsvFeed,
  parseXmlShoppingItems,
};
