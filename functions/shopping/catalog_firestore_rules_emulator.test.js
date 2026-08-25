"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc, updateDoc} = require("firebase/firestore");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {createFixturePartnerAdapter} = require("./adapters/fixture_partner_adapter");
const {COLLECTIONS, createFirestoreCatalogRepository} = require("./catalog_repository");
const {createFirestoreCatalogSearchRepository} = require("./catalog_search_repository");
const {executeCatalogSearch} = require("./catalog_search_query_service");
const {SNAPSHOT_SCOPE, syncFixtureSnapshot} = require("./catalog_sync_service");
const fixtures = require("./fixtures/fixture_catalog");

const PROJECT_ID = "demo-ootd-rules-9cr";
const RULES_PATH = path.resolve(__dirname, "../../firestore.rules");
const OWNER = "shopping-owner";
const FOREIGN = "shopping-foreign";
let environment;

function db(uid) {
  return environment.authenticatedContext(uid).firestore();
}

async function seed(pathValue, value) {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), pathValue), value);
  });
}

test.before(async () => {
  environment = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {rules: fs.readFileSync(RULES_PATH, "utf8")},
  });
});

test.after(async () => {
  await environment?.cleanup();
});

test.beforeEach(async () => {
  await environment.clearFirestore();
});

test("authenticated clients can read public catalog but cannot forge truth", async () => {
  await seed("catalogProducts/product-1", {brand: "Fixture"});
  await seed("catalogVariants/variant-1", {productId: "product-1"});
  await seed("catalogOffers/offer-1", {variantId: "variant-1", regularPrice: {amountMinor: 4900, currency: "EUR"}});
  await seed("catalogOffers/offer-1/sizes/M", {availability: "AVAILABLE"});
  await seed("catalogSearchVariants/variant-1", {variantId: "variant-1"});
  await assertSucceeds(getDoc(doc(db(OWNER), "catalogProducts/product-1")));
  await assertSucceeds(getDoc(doc(db(OWNER), "catalogOffers/offer-1/sizes/M")));
  await assertSucceeds(getDoc(doc(db(OWNER), "catalogSearchVariants/variant-1")));
  await assertFails(setDoc(doc(db(OWNER), "catalogProducts/forged-product"), {
    brand: "Forged",
  }));
  await assertFails(setDoc(doc(db(OWNER), "catalogOffers/offer-1"), {
    variantId: "variant-1",
    regularPrice: {amountMinor: 1, currency: "EUR"},
    promotions: [{kind: "PUBLIC_COUPON", code: "FORGED"}],
  }));
  await assertFails(setDoc(doc(db(OWNER), "catalogOffers/offer-1/sizes/M"), {
    availability: "AVAILABLE",
    exactQuantity: 999,
  }));
  await assertFails(updateDoc(doc(db(OWNER), "catalogVariants/variant-1"), {
    lifecycleState: "DISCONTINUED",
  }));
});

test("partner integration, identity index, and sync state are client-private", async () => {
  await seed("partnerIntegrations/fixture", {secret: "not-client-readable"});
  await seed("catalogSyncStates/fixture", {status: "COMPLETED"});
  await seed("catalogSyncRuns/run-1", {status: "COMPLETED"});
  await seed("catalogIdentityIndex/product__gtin", {entityId: "product-1"});
  await assertFails(getDoc(doc(db(OWNER), "partnerIntegrations/fixture")));
  await assertFails(getDoc(doc(db(OWNER), "catalogSyncStates/fixture")));
  await assertFails(getDoc(doc(db(OWNER), "catalogSyncRuns/run-1")));
  await assertFails(getDoc(doc(db(OWNER), "catalogIdentityIndex/product__gtin")));
  await assertFails(setDoc(doc(db(OWNER), "catalogSyncStates/fixture"), {status: "FORGED"}));
});

test("wishlist intent remains owner-scoped while tracking state is backend-only", async () => {
  const intentPath = `users/${OWNER}/wishlist/legacy-intent`;
  await assertSucceeds(setDoc(doc(db(OWNER), intentPath), {
    variantId: "variant-1",
    selectedSizes: ["M"],
    targetPrice: {amountMinor: 2000, currency: "EUR"},
  }));
  await assertFails(setDoc(doc(db(OWNER), `users/${OWNER}/wishlist/forged`), {
    variantId: "variant-1",
    evaluatedPriceState: "SATISFIED",
  }));
  await assertFails(updateDoc(doc(db(OWNER), intentPath), {
    highlightState: "GOLD",
  }));
  await assertFails(setDoc(doc(db(FOREIGN), intentPath), {
    variantId: "variant-1",
  }));
});

test("Wishlist V2 is fully callable-mediated and legacy Wishlist remains untouched", async () => {
  const v2Path = `users/${OWNER}/wishlistV2/wish-1`;
  await seed(v2Path, {
    schemaVersion: 2,
    ownerUid: OWNER,
    variantId: "variant-1",
    tracking: {evaluatedPriceState: "SATISFIED", highlightState: "NONE"},
  });
  await assertFails(getDoc(doc(db(OWNER), v2Path)));
  await assertFails(getDoc(doc(db(FOREIGN), v2Path)));
  await assertFails(setDoc(doc(db(OWNER), `users/${OWNER}/wishlistV2/forged`), {
    schemaVersion: 2,
    ownerUid: OWNER,
    evaluatedPriceState: "SATISFIED",
    highlightState: "GOLD",
  }));
  await assertFails(updateDoc(doc(db(OWNER), v2Path), {
    tracking: {evaluatedPriceState: "SATISFIED", highlightState: "GOLD"},
  }));
  await assertFails(setDoc(doc(db(FOREIGN), `users/${OWNER}/wishlistV2/cross-user`), {
    schemaVersion: 2,
  }));
  await assertSucceeds(getDoc(doc(db(OWNER), `users/${OWNER}/wishlist/legacy-intent`)));
});

test("fixture sync persists normalized Product, Variant, Offer, and Size via Admin Firestore", async () => {
  const app = initializeApp({projectId: PROJECT_ID}, "shopping-phase-2-emulator");
  try {
    const adminDb = getFirestore(app);
    const repository = createFirestoreCatalogRepository(adminDb);
    const partner = createFixturePartnerAdapter(
      fixtures.fixturePartnerConfig("emulator-store", "emulator.fixture.test"),
    );
    const raw = fixtures.withUrl(fixtures.navyRecord, "emulator.fixture.test");
    await syncFixtureSnapshot({
      adapter: partner,
      rawRecords: [raw],
      repository,
      snapshotScope: SNAPSHOT_SCOPE.FULL,
      runId: "emulator-sync-1",
    });
    const offers = await adminDb.collection(COLLECTIONS.offers).get();
    assert.equal(offers.size, 1);
    const offer = offers.docs[0];
    assert.equal(offer.data().regularPrice.amountMinor, 4900);
    assert.equal(offer.data().promotions.length, 0);
    const sizes = await offer.ref.collection("sizes").get();
    assert.equal(sizes.docs[0].data().exactQuantity, 3);
    const products = await adminDb.collection(COLLECTIONS.products).get();
    const variants = await adminDb.collection(COLLECTIONS.variants).get();
    assert.equal(products.size, 1);
    assert.equal(variants.size, 1);
  } finally {
    await deleteApp(app);
  }
});

test("projection-first reader hydrates authoritative catalog facts for a deterministic search", async () => {
  const app = initializeApp({projectId: PROJECT_ID}, "shopping-phase-3-emulator");
  try {
    const adminDb = getFirestore(app);
    const writeRepository = createFirestoreCatalogRepository(adminDb);
    const partner = createFixturePartnerAdapter(
      fixtures.fixturePartnerConfig("search-store", "search.fixture.test"),
    );
    await syncFixtureSnapshot({
      adapter: partner,
      rawRecords: [fixtures.withUrl(fixtures.navyRecord, "search.fixture.test")],
      repository: writeRepository,
      snapshotScope: SNAPSHOT_SCOPE.FULL,
      runId: "search-sync-1",
    });
    const result = await executeCatalogSearch({
      query: {
        queryId: "search-query", sessionId: "fixture-session", revision: 1,
        selectedSizeKeys: ["M"], preferredSizeKey: "M",
        constraints: [
          {field: "canonicalType", operator: "equals", value: "hoodie", strength: "hard"},
          {field: "color", operator: "equals", value: "navy", strength: "hard"},
        ],
      },
      repository: createFirestoreCatalogSearchRepository(adminDb),
    });
    assert.equal(result.candidates.length, 1);
    assert.equal(result.observability.firestoreQueryCount, 6);
    assert.equal(result.completeness, "COMPLETE");
  } finally {
    await deleteApp(app);
  }
});
