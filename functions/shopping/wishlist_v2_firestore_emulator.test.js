"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {assertFails, initializeTestEnvironment} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc} = require("firebase/firestore");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {createFirestoreCatalogSearchRepository} = require("./catalog_search_repository");
const {
  createFirestoreWishlistV2Repository,
  createWishlistV2Service,
} = require("./wishlist_v2_service");

const PROJECT_ID = "demo-ootd-rules-9cr";
const RULES_PATH = path.resolve(__dirname, "../../firestore.rules");
let environment;
let app;
let db;
let service;

test.before(async () => {
  environment = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {rules: fs.readFileSync(RULES_PATH, "utf8")},
  });
  await environment.clearFirestore();
  app = initializeApp({projectId: PROJECT_ID}, "wishlist-v2-emulator");
  db = getFirestore(app);
  await seedCatalog();
  service = createWishlistV2Service({
    repository: createFirestoreWishlistV2Repository(db),
    catalogRepository: createFirestoreCatalogSearchRepository(db),
    now: () => 1000,
  });
});

test.after(async () => {
  await deleteApp(app);
  await environment.cleanup();
});

test("Admin service persists baseline while owner and foreign clients cannot access V2 directly", async () => {
  const result = await service.dispatch({uid: "owner"}, {
    operation: "ADD_OR_UPSERT",
    variantId: "v",
    selectedSizes: ["M"],
    preferredSize: "M",
    targetPrice: {amountMinor: 2000, currency: "EUR"},
    priceMonitoringEnabled: true,
    sizeMonitoringEnabled: true,
  });
  assert.equal(result.item.tracking.evaluatedPriceState, "SATISFIED");
  const ref = db.collection("users").doc("owner").collection("wishlistV2")
    .doc(result.item.wishlistItemId);
  const stored = await ref.get();
  assert.equal(stored.exists, true);
  assert.equal(stored.data().tracking.highlightState, "NONE");

  const ownerClient = environment.authenticatedContext("owner").firestore();
  const foreignClient = environment.authenticatedContext("foreign").firestore();
  const relative = `users/owner/wishlistV2/${result.item.wishlistItemId}`;
  await assertFails(getDoc(doc(ownerClient, relative)));
  await assertFails(getDoc(doc(foreignClient, relative)));
  await assertFails(setDoc(doc(ownerClient, relative), {
    tracking: {evaluatedPriceState: "SATISFIED", highlightState: "GOLD"},
  }));
});

test("reverse subscriptions, events, and refresh leases are client-denied", async () => {
  const itemId = "wish_test";
  await db.collection("wishlistSubscriptions").doc("v")
    .collection("subscribers").doc(`owner_${itemId}`).set({
      userId: "owner",
      wishlistItemId: itemId,
      variantId: "v",
      informationalEnabled: true,
    });
  await db.collection("wishlistEvents").doc("wev_test").set({
    eventId: "wev_test",
    ownerUid: "owner",
    delivery: {status: "PENDING"},
  });
  await db.collection("wishlistRefreshLeases").doc("owner").set({
    ownerUid: "owner",
    operationId: "op",
  });

  const ownerClient = environment.authenticatedContext("owner").firestore();
  await assertFails(getDoc(doc(ownerClient,
    `wishlistSubscriptions/v/subscribers/owner_${itemId}`)));
  await assertFails(setDoc(doc(ownerClient,
    `wishlistSubscriptions/v/subscribers/forged`), {userId: "owner"}));
  await assertFails(getDoc(doc(ownerClient, "wishlistEvents/wev_test")));
  await assertFails(setDoc(doc(ownerClient, "wishlistEvents/forged"), {
    gold: true,
  }));
  await assertFails(getDoc(doc(ownerClient, "wishlistRefreshLeases/owner")));
});

test("ADD creates server subscription doc that clients cannot read", async () => {
  const result = await service.dispatch({uid: "owner2"}, {
    operation: "ADD_OR_UPSERT",
    variantId: "v",
    selectedSizes: ["M"],
    preferredSize: "M",
    targetPrice: {amountMinor: 2000, currency: "EUR"},
    priceMonitoringEnabled: false,
    sizeMonitoringEnabled: false,
  });
  const subId = `owner2_${result.item.wishlistItemId}`;
  const sub = await db.collection("wishlistSubscriptions").doc("v")
    .collection("subscribers").doc(subId).get();
  assert.equal(sub.exists, true);
  assert.equal(sub.data().informationalEnabled, true);
  const ownerClient = environment.authenticatedContext("owner2").firestore();
  await assertFails(getDoc(doc(ownerClient,
    `wishlistSubscriptions/v/subscribers/${subId}`)));
});

test("deterministic identity prevents duplicates and cross-owner remove cannot affect owner", async () => {
  const input = {
    operation: "ADD_OR_UPSERT", variantId: "v", selectedSizes: ["M"],
    preferredSize: "M", targetPrice: {amountMinor: 1000, currency: "EUR"},
    priceMonitoringEnabled: false, sizeMonitoringEnabled: true,
  };
  const one = await service.dispatch({uid: "owner"}, input);
  const two = await service.dispatch({uid: "owner"}, input);
  assert.equal(one.item.wishlistItemId, two.item.wishlistItemId);
  const snapshot = await db.collection("users").doc("owner").collection("wishlistV2").get();
  assert.equal(snapshot.size, 1);
  const foreign = await service.dispatch({uid: "foreign"}, {operation: "REMOVE", variantId: "v"});
  assert.equal(foreign.status, "NOT_FOUND");
  assert.equal((await db.collection("users").doc("owner").collection("wishlistV2").get()).size, 1);
});

async function seedCatalog() {
  await db.collection("catalogPartners").doc("store").set({
    partnerId: "store", publicStoreName: "Fixture Store", allowedDomains: ["fixture.test"],
  });
  await db.collection("catalogProducts").doc("p").set({
    productId: "p", normalizedModelIdentity: "Hoodie", brand: "Brand",
    canonicalType: "hoodie", canonicalFamily: "top",
  });
  await db.collection("catalogVariants").doc("v").set({
    variantId: "v", productId: "p", lifecycleState: "ACTIVE",
    exactColorName: "Navy", colorProfile: {primary: {family: "navy"}},
  });
  await db.collection("catalogSearchVariants").doc("v").set({variantId: "v"});
  await db.collection("catalogOffers").doc("o").set({
    offerId: "o", variantId: "v", partnerId: "store",
    url: "https://fixture.test/v", regularPrice: {amountMinor: 1800, currency: "EUR"},
    promotions: [], overallAvailability: "AVAILABLE", lifecycleState: "ACTIVE",
    lastVerifiedAt: "2026-08-15T10:00:00.000Z", freshness: {stale: false},
  });
  await db.collection("catalogOffers").doc("o").collection("sizes").doc("M").set({
    offerId: "o", normalizedSizeKey: "M", partnerSizeLabel: "M",
    availability: "AVAILABLE", quantityReliability: "EXACT", exactQuantity: 3,
  });
}
