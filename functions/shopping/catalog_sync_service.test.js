"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {AVAILABILITY, LIFECYCLE, effectivePublicPrice} =
  require("./catalog_contract");
const {createFixturePartnerAdapter} =
  require("./adapters/fixture_partner_adapter");
const {COLLECTIONS, createMemoryCatalogRepository} =
  require("./catalog_repository");
const {SNAPSHOT_SCOPE, syncFixtureSnapshot} =
  require("./catalog_sync_service");
const fixtures = require("./fixtures/fixture_catalog");

function adapter(id = "store-a", domain = "store-a.fixture.test") {
  return createFixturePartnerAdapter(fixtures.fixturePartnerConfig(id, domain));
}

function record(record, domain = "store-a.fixture.test") {
  return fixtures.withUrl(record, domain);
}

test("same verified product/variant across stores aggregates offers", async () => {
  const repository = createMemoryCatalogRepository();
  await syncFixtureSnapshot({
    adapter: adapter("store-a"),
    rawRecords: [record(fixtures.navyRecord)],
    repository, snapshotScope: SNAPSHOT_SCOPE.FULL, runId: "run-a",
  });
  await syncFixtureSnapshot({
    adapter: adapter("store-b", "store-b.fixture.test"),
    rawRecords: [record(fixtures.navyCouponRecord, "store-b.fixture.test")],
    repository, snapshotScope: SNAPSHOT_SCOPE.FULL, runId: "run-b",
  });
  const dump = repository.dump();
  assert.equal(Object.keys(dump.products).length, 1);
  assert.equal(Object.keys(dump.variants).length, 1);
  assert.equal(Object.keys(dump.offers).length, 2);
});

test("weakly similar products do not merge", async () => {
  const repository = createMemoryCatalogRepository();
  await syncFixtureSnapshot({
    adapter: adapter(),
    rawRecords: [
      record(fixtures.weakSimilarA),
      record(fixtures.weakSimilarB),
    ],
    repository, snapshotScope: SNAPSHOT_SCOPE.FULL, runId: "weak",
  });
  const dump = repository.dump();
  assert.equal(Object.keys(dump.products).length, 2);
  assert.equal(Object.keys(dump.variants).length, 2);
});

test("same full fixture sync is idempotent", async () => {
  const repository = createMemoryCatalogRepository();
  const input = [record(fixtures.navyRecord), record(fixtures.whiteRecord)];
  await syncFixtureSnapshot({
    adapter: adapter(), rawRecords: input, repository,
    snapshotScope: SNAPSHOT_SCOPE.FULL, runId: "first",
  });
  const first = repository.dump();
  await syncFixtureSnapshot({
    adapter: adapter(), rawRecords: input, repository,
    snapshotScope: SNAPSHOT_SCOPE.FULL, runId: "second",
  });
  const second = repository.dump();
  assert.equal(Object.keys(second.products).length, Object.keys(first.products).length);
  assert.equal(Object.keys(second.variants).length, Object.keys(first.variants).length);
  assert.equal(Object.keys(second.offers).length, Object.keys(first.offers).length);
  assert.equal(Object.keys(second.sizes).length, Object.keys(first.sizes).length);
});

test("different color remains isolated from navy offer and size facts", async () => {
  const repository = createMemoryCatalogRepository();
  await syncFixtureSnapshot({
    adapter: adapter(),
    rawRecords: [record(fixtures.navyRecord), record(fixtures.whiteRecord)],
    repository, snapshotScope: SNAPSHOT_SCOPE.FULL, runId: "colors",
  });
  const dump = repository.dump();
  const variants = Object.values(dump.variants);
  const navy = variants.find((variant) => variant.exactColorName === "Navy");
  const white = variants.find((variant) => variant.exactColorName === "White");
  const navyOffers = Object.values(dump.offers).filter((offer) => offer.variantId === navy.variantId);
  const whiteOffers = Object.values(dump.offers).filter((offer) => offer.variantId === white.variantId);
  assert.equal(navyOffers[0].regularPrice.amountMinor, 4900);
  assert.equal(whiteOffers[0].regularPrice.amountMinor, 2900);
  assert.equal(dump.sizes[`${navyOffers[0].offerId}:M`].exactQuantity, 3);
  assert.equal(dump.sizes[`${whiteOffers[0].offerId}:M`].exactQuantity, null);
});

test("public coupon persists while member price remains excluded", async () => {
  const repository = createMemoryCatalogRepository();
  await syncFixtureSnapshot({
    adapter: adapter(),
    rawRecords: [
      record(fixtures.navyCouponRecord),
      record(fixtures.memberOnlyRecord),
    ],
    repository, snapshotScope: SNAPSHOT_SCOPE.FULL, runId: "prices",
  });
  const offers = Object.values(repository.dump().offers);
  const coupon = offers.find((offer) => offer.partnerListingId === "navy-b");
  const member = offers.find((offer) => offer.partnerListingId === "member-only");
  assert.equal(effectivePublicPrice(coupon).price.amountMinor, 3900);
  assert.equal(effectivePublicPrice(coupon).couponCode, "FIXTURE10");
  assert.equal(effectivePublicPrice(member).price.amountMinor, 5500);
});

test("partial omission preserves offer while full omission discontinues it", async () => {
  const repository = createMemoryCatalogRepository();
  const adapterValue = adapter();
  await syncFixtureSnapshot({
    adapter: adapterValue, rawRecords: [record(fixtures.navyRecord)], repository,
    snapshotScope: SNAPSHOT_SCOPE.FULL, runId: "seed",
  });
  const offerId = Object.keys(repository.dump().offers)[0];
  await syncFixtureSnapshot({
    adapter: adapterValue, rawRecords: [], repository,
    snapshotScope: SNAPSHOT_SCOPE.PARTIAL, runId: "partial",
  });
  assert.equal(repository.get(COLLECTIONS.offers, offerId).lifecycleState, LIFECYCLE.ACTIVE);
  await syncFixtureSnapshot({
    adapter: adapterValue, rawRecords: [], repository,
    snapshotScope: SNAPSHOT_SCOPE.FULL, runId: "full",
  });
  assert.equal(repository.get(COLLECTIONS.offers, offerId).lifecycleState, LIFECYCLE.DISCONTINUED);
});

test("failed malformed sync preserves last known catalog truth", async () => {
  const repository = createMemoryCatalogRepository();
  const adapterValue = adapter();
  await syncFixtureSnapshot({
    adapter: adapterValue, rawRecords: [record(fixtures.navyRecord)], repository,
    snapshotScope: SNAPSHOT_SCOPE.FULL, runId: "seed",
  });
  const before = repository.dump();
  await assert.rejects(
    syncFixtureSnapshot({
      adapter: adapterValue,
      rawRecords: [{...record(fixtures.navyRecord), fixtureRegularPrice: {amountMinor: 1.2, currency: "EUR"}}],
      repository, snapshotScope: SNAPSHOT_SCOPE.FULL, runId: "bad",
    }),
    /amount_minor/,
  );
  const afterOffer = Object.values(repository.dump().offers)[0];
  const beforeOffer = Object.values(before.offers)[0];
  assert.equal(afterOffer.regularPrice.amountMinor, beforeOffer.regularPrice.amountMinor);
  assert.equal(afterOffer.overallAvailability, beforeOffer.overallAvailability);
  assert.equal(afterOffer.lifecycleState, beforeOffer.lifecycleState);
  const syncState = repository.get(COLLECTIONS.syncStates, "store-a");
  assert.equal(syncState.status, "FAILED");
  assert.equal(syncState.lastSuccessfulRunId, "seed");
  assert.equal(Object.values(repository.dump().offers)[0].freshness.stale, true);
});

test("reintroduced verified offer returns from discontinued", async () => {
  const repository = createMemoryCatalogRepository();
  const adapterValue = adapter();
  await syncFixtureSnapshot({
    adapter: adapterValue, rawRecords: [record(fixtures.navyRecord)], repository,
    snapshotScope: SNAPSHOT_SCOPE.FULL, runId: "seed",
  });
  await syncFixtureSnapshot({
    adapter: adapterValue, rawRecords: [], repository,
    snapshotScope: SNAPSHOT_SCOPE.FULL, runId: "gone",
  });
  await syncFixtureSnapshot({
    adapter: adapterValue, rawRecords: [record(fixtures.navyRecord)], repository,
    snapshotScope: SNAPSHOT_SCOPE.FULL, runId: "back",
  });
  const offer = Object.values(repository.dump().offers)[0];
  assert.equal(offer.lifecycleState, LIFECYCLE.ACTIVE);
  assert.equal(offer.overallAvailability, AVAILABILITY.AVAILABLE);
});

test("adapter rejects dangerous URL, missing facts, and invalid money", () => {
  const adapterValue = adapter();
  assert.throws(
    () => adapterValue.normalize({...fixtures.navyRecord, fixtureUrl: "http://store-a.fixture.test/item"}),
    /requires_https/,
  );
  assert.throws(
    () => adapterValue.normalize({...fixtures.navyRecord, fixtureUrl: "https://foreign.example/item"}),
    /domain_not_allowed/,
  );
  assert.throws(
    () => adapterValue.normalize({...fixtures.navyRecord, fixtureUrl: "javascript:alert(1)"}),
    /requires_https/,
  );
  assert.throws(
    () => adapterValue.normalize({...fixtures.navyRecord, fixtureUrl: "https://store-a.fixture.test/item", fixtureRegularPrice: {amountMinor: 1.5, currency: "EUR"}}),
    /amount_minor/,
  );
  const normalized = adapterValue.normalize({
    ...fixtures.navyRecord,
    fixtureUrl: "https://store-a.fixture.test/item",
    fixtureSizes: [{
      normalizedSizeKey: "M", partnerSizeLabel: "M", sizeSystem: "INTL",
    }],
  });
  assert.equal(normalized.sizes[0].availability, AVAILABILITY.UNKNOWN);
  assert.equal(normalized.sizes[0].exactQuantity, null);
});
