"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  parseXmlShoppingItems,
  parseCjShoppingFeedRecord,
} = require("./cj/cj_product_feed_parser");
const {
  CJ_AUTH_MODEL,
  CJ_PRODUCT_SEARCH_ENDPOINT,
  FIELD_STATUS,
} = require("./cj/cj_product_feed_schema");
const {
  CJ_PERSONAL_ACCESS_TOKEN_SECRET_NAME,
  NEW_LEGACY_FUNCTIONS_CONFIG_USAGE_COUNT,
} = require("./cj/cj_auth_contract");
const {
  createReservedCjAdapter,
  ADAPTER_KEY,
  PARTNER_ID,
  PRODUCTION_SYNC_STATUS,
  ReservedCjFeedProfile,
  validateCjFeedSample,
  syntheticReservedCsv,
  syntheticReservedXmlSnippet,
  evaluateMvpGate,
  DATA_USAGE_RIGHTS,
  IMAGE_USAGE_RIGHTS,
  DEFAULT_RIGHTS_STATE,
  OOTD_IMAGE_PREFLIGHT_CONTRACT,
  SIZE_MONITORING_READINESS,
  buildReservedPrivatePartnerTemplate,
} = require("./reserved");
const {createPartnerAdapter, OWNER_APPROVED_FIRST_PARTNER_ID} =
  require("./registry");
const {SYNC_MODE} = require("./partner_adapter_contract");

test("CJ auth contract uses PAT secret name only; no legacy config", () => {
  assert.equal(CJ_PERSONAL_ACCESS_TOKEN_SECRET_NAME, "CJ_PERSONAL_ACCESS_TOKEN");
  assert.equal(CJ_AUTH_MODEL.type, "bearer_personal_access_token");
  assert.equal(CJ_PRODUCT_SEARCH_ENDPOINT, "https://ads.api.cj.com/query");
  assert.equal(NEW_LEGACY_FUNCTIONS_CONFIG_USAGE_COUNT, 0);
});

test("CJ CSV parser streams synthetic Reserved-shaped rows", () => {
  const {iterateCsvRecords} = require("./cj/cj_product_feed_parser");
  const good = [];
  for (const {rowIndex, record} of iterateCsvRecords(syntheticReservedCsv())) {
    try {
      good.push(parseCjShoppingFeedRecord(record, {rowIndex}));
    } catch (_) {
      // intentional malformed row in fixture
    }
  }
  assert.ok(good.length >= 4);
  const navyM = good.find((r) => r.id === "rsv-navy-m");
  assert.equal(navyM.price.currency, "EUR");
  assert.equal(navyM.salePrice.amountMinor, 1999);
  assert.equal(navyM.color, "Navy");
  assert.equal(navyM.size, "M");
  assert.equal(navyM.itemGroupId, "rsv-tee-01");
  assert.equal(navyM.imageRole, null);
});

test("CJ XML parser extracts shopping item", () => {
  const records = parseXmlShoppingItems(syntheticReservedXmlSnippet());
  assert.equal(records.length, 1);
  assert.equal(records[0].id, "rsv-xml-1");
  assert.equal(records[0].additionalImageLinks.length, 1);
});

test("CJ parser rejects unknown availability as schema drift", () => {
  assert.throws(
    () => parseCjShoppingFeedRecord({
      id: "x",
      price: "10.00 EUR",
      availability: "maybe",
    }),
    (err) => err.code === "SCHEMA_CHANGED",
  );
});

test("Reserved adapter is registered and fail-closed for sync", async () => {
  assert.equal(OWNER_APPROVED_FIRST_PARTNER_ID, "reserved_sk");
  assert.equal(PARTNER_ID, "reserved_sk");
  assert.equal(ADAPTER_KEY, "reserved_cj");
  assert.equal(PRODUCTION_SYNC_STATUS, "DISABLED");

  const adapter = createPartnerAdapter("reserved_cj");
  assert.equal(adapter.partnerId(), "reserved_sk");
  assert.equal(adapter.productionSyncStatus(), "DISABLED");
  assert.equal(adapter.feedProfile().profileStatus, "PENDING_SAMPLE");

  await assert.rejects(
    () => adapter.fetchFullSnapshot({}),
    (err) => err.message === "RESERVED_FEED_PROFILE_UNCONFIRMED",
  );
  assert.throws(
    () => adapter.normalizeProduct({}),
    (err) => err.message === "RESERVED_FEED_PROFILE_UNCONFIRMED",
  );

  const disappearance = adapter.classifyDisappearance({
    mode: SYNC_MODE.FULL,
    completenessGuaranteed: true,
    failed: false,
  });
  assert.equal(disappearance, "MUST_NOT_DISCONTINUE");
});

test("Reserved field registry marks merchant fields SAMPLE_REQUIRED", () => {
  assert.equal(
    ReservedCjFeedProfile.fields.productId.status,
    FIELD_STATUS.SAMPLE_REQUIRED,
  );
  assert.equal(
    ReservedCjFeedProfile.fields.sizeAvailability.status,
    FIELD_STATUS.SAMPLE_REQUIRED,
  );
  assert.equal(
    ReservedCjFeedProfile.fields.imageRole.status,
    FIELD_STATUS.UNSUPPORTED,
  );
  assert.equal(
    ReservedCjFeedProfile.fields.quantity.status,
    FIELD_STATUS.UNAVAILABLE,
  );
});

test("sample validator reports population without raw dump", () => {
  const report = validateCjFeedSample(syntheticReservedCsv());
  assert.ok(report.recordCount >= 4);
  assert.ok(report.uniqueProductIds >= 4);
  assert.equal(report.sanitized, true);
  assert.ok(report.population.colorPct > 0);
  assert.ok(report.issueCount >= 1); // bad money row
  assert.ok(report.issuesSample.length <= 50);
});

test("MVP gate evaluates synthetic sample", () => {
  const report = validateCjFeedSample(syntheticReservedCsv());
  // Filter only valid currency rows for gate: re-run without bad row by XML
  const xmlReport = validateCjFeedSample(syntheticReservedXmlSnippet());
  const gate = evaluateMvpGate(xmlReport);
  assert.ok(["GO", "GO_WITH_LIMITATIONS"].includes(gate.decision));
  assert.equal(SIZE_MONITORING_READINESS.status, "SAMPLE_REQUIRED");
  void report;
});

test("rights remain UNKNOWN; preflight contract prepared", () => {
  assert.equal(DEFAULT_RIGHTS_STATE.dataUsage, DATA_USAGE_RIGHTS.UNKNOWN);
  assert.equal(DEFAULT_RIGHTS_STATE.imageUsage, IMAGE_USAGE_RIGHTS.UNKNOWN);
  assert.equal(OOTD_IMAGE_PREFLIGHT_CONTRACT.rules.aiRequestCountNow, 0);
  assert.equal(
    OOTD_IMAGE_PREFLIGHT_CONTRACT.rules.noGenerativeReconstruction,
    true,
  );
  const priv = buildReservedPrivatePartnerTemplate();
  assert.equal(priv.status, "DISABLED_PENDING_ACCESS");
  assert.equal(priv.productionSyncStatus, "DISABLED");
});

test("createReservedCjAdapter direct factory matches registry", () => {
  const a = createReservedCjAdapter();
  assert.equal(a.partnerId(), "reserved_sk");
});
