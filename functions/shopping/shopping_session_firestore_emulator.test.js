"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {
  assertFails,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc} = require("firebase/firestore");
const {createMemoryCatalogSearchRepository} = require("./catalog_search_repository");
const {createShoppingOrchestrator} = require("./shopping_orchestration_service");
const {createFirestoreShoppingSessionStore} = require("./shopping_session_store");

const PROJECT_ID = "demo-ootd-rules-9cr";
const RULES_PATH = path.resolve(__dirname, "../../firestore.rules");
let environment;
let appSerial = 0;

function catalog(count = 12) {
  const products = [];
  const variants = [];
  const offers = [];
  const sizes = [];
  for (let index = 0; index < count; index++) {
    products.push({productId: `p${index}`, brand: "Fixture", canonicalType: "hoodie",
      canonicalFamily: "top", normalizedModelIdentity: `hoodie-${index}`});
    variants.push({variantId: `v${index}`, productId: `p${index}`, exactColorName: "Navy",
      colorProfile: {primary: {family: "navy"}}, styles: [], lifecycleState: "ACTIVE"});
    offers.push({offerId: `o${index}`, variantId: `v${index}`, partnerId: "fixture",
      url: `https://fixture.test/${index}`, regularPrice: {amountMinor: 2000 + index, currency: "EUR"},
      promotions: [], overallAvailability: "AVAILABLE", lifecycleState: "ACTIVE", freshness: {stale: false}});
    sizes.push({offerId: `o${index}`, normalizedSizeKey: "M", availability: "AVAILABLE",
      quantityReliability: "EXACT", exactQuantity: 3});
  }
  return {products, variants, offers, sizes};
}
function query(revision = 1) {
  return {queryId: "q", sessionId: "intent", revision, selectedSizeKeys: ["M"],
    preferredSizeKey: "M", constraints: [{field: "canonicalType", operator: "equals",
      value: "hoodie", strength: "hard"}]};
}
function durableService(input = catalog()) {
  const app = initializeApp({projectId: PROJECT_ID}, `shopping-session-${appSerial++}`);
  const db = getFirestore(app);
  return {
    app,
    service: createShoppingOrchestrator({
      repository: createMemoryCatalogSearchRepository(input),
      sessionStore: createFirestoreShoppingSessionStore(db),
    }),
  };
}

test.before(async () => {
  environment = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {rules: fs.readFileSync(RULES_PATH, "utf8")},
  });
});
test.after(async () => { await environment?.cleanup(); });
test.beforeEach(async () => { await environment.clearFirestore(); });

test("direct client session reads and writes are denied", async () => {
  const client = environment.authenticatedContext("owner").firestore();
  await assertFails(getDoc(doc(client, "shoppingSessions/opaque")));
  await assertFails(setDoc(doc(client, "shoppingSessions/opaque"), {
    ownerUid: "owner", pool: {orderedCandidateIds: ["forged"]},
  }));
  await assertFails(getDoc(doc(client, "shoppingSessionIdempotency/opaque")));
});

test("durable session works across fresh services and keeps owner binding", async () => {
  const first = durableService();
  const start = await first.service.dispatch({uid: "owner"}, {
    operation: "START_SEARCH", query: query(), pageSize: 3, idempotencyKey: "same",
  });
  const second = durableService();
  const more = await second.service.dispatch({uid: "owner"}, {
    operation: "SHOW_MORE", sessionId: start.sessionId, pageSize: 3, operationId: "more-1",
  });
  assert.deepEqual(more.candidates.map((item) => item.variantId), ["v3", "v4", "v5"]);
  const retry = await first.service.dispatch({uid: "owner"}, {
    operation: "SHOW_MORE", sessionId: start.sessionId, pageSize: 3, operationId: "more-1",
  });
  assert.deepEqual(retry.candidates.map((item) => item.variantId), ["v3", "v4", "v5"]);
  await assert.rejects(second.service.dispatch({uid: "other"}, {
    operation: "SHOW_MORE", sessionId: start.sessionId, pageSize: 3,
  }), (error) => error.code === "SESSION_FORBIDDEN");
  for (const operation of ["REFINE_QUERY", "FOCUS_CANDIDATE", "GET_CANDIDATE_DETAILS"]) {
    await assert.rejects(second.service.dispatch({uid: "other"}, {
      operation, sessionId: start.sessionId,
      ...(operation === "REFINE_QUERY" ? {
        expectedQueryRevision: 1, query: query(2), pageSize: 1,
      } : operation === "FOCUS_CANDIDATE" ? {variantId: "v0"} : {variantId: "v0"}),
    }), (error) => error.code === "SESSION_FORBIDDEN");
  }
  const durableDoc = await getFirestore(first.app).collection("shoppingSessions")
    .doc(start.sessionId).get();
  const stored = JSON.stringify(durableDoc.data());
  assert.equal(stored.includes("regularPrice"), false);
  assert.equal(stored.includes("https://fixture.test"), false);
  assert.equal(stored.includes("amountMinor"), false);
  const replayStart = await second.service.dispatch({uid: "owner"}, {
    operation: "START_SEARCH", query: query(), pageSize: 3, idempotencyKey: "same",
  });
  assert.equal(replayStart.sessionId, start.sessionId);
  await deleteApp(first.app);
  await deleteApp(second.app);
});

test("concurrent pages serialize without overlap and stale refine conflicts", async () => {
  const fixture = durableService();
  const start = await fixture.service.dispatch({uid: "owner"}, {
    operation: "START_SEARCH", query: query(), pageSize: 2,
  });
  const [left, right] = await Promise.all([
    fixture.service.dispatch({uid: "owner"}, {
      operation: "SHOW_MORE", sessionId: start.sessionId, pageSize: 2, operationId: "left",
    }),
    fixture.service.dispatch({uid: "owner"}, {
      operation: "SHOW_MORE", sessionId: start.sessionId, pageSize: 2, operationId: "right",
    }),
  ]);
  const ids = [...left.candidates, ...right.candidates].map((item) => item.variantId);
  assert.equal(new Set(ids).size, 4);
  const session = await fixture.service.sessionStore.get(start.sessionId);
  await assert.rejects(fixture.service.dispatch({uid: "owner"}, {
    operation: "REFINE_QUERY", sessionId: start.sessionId, expectedVersion: session.version - 1,
    expectedQueryRevision: 1, query: query(2), pageSize: 2, operationId: "stale-refine",
  }), (error) => error.code === "SESSION_CONFLICT");
  await deleteApp(fixture.app);
});

test("duplicate refine replays while refine versus show/focus resolves by conflict", async () => {
  const fixture = durableService();
  const start = await fixture.service.dispatch({uid: "owner"}, {
    operation: "START_SEARCH", query: query(), pageSize: 2,
  });
  const refineRequest = {
    operation: "REFINE_QUERY", sessionId: start.sessionId, expectedQueryRevision: 1,
    query: {...query(2), constraints: [...query().constraints, {
      field: "brand", operator: "equals", value: "Fixture", strength: "hard",
    }]}, pageSize: 2, operationId: "refine-1",
  };
  const refined = await fixture.service.dispatch({uid: "owner"}, refineRequest);
  const retried = await fixture.service.dispatch({uid: "owner"}, refineRequest);
  assert.deepEqual(retried.candidates.map((item) => item.variantId),
    refined.candidates.map((item) => item.variantId));

  const session = await fixture.service.sessionStore.get(start.sessionId);
  const [show, competingRefine] = await Promise.allSettled([
    fixture.service.dispatch({uid: "owner"}, {
      operation: "SHOW_MORE", sessionId: start.sessionId, pageSize: 2,
      expectedVersion: session.version, operationId: "show-race",
    }),
    fixture.service.dispatch({uid: "owner"}, {
      operation: "REFINE_QUERY", sessionId: start.sessionId, pageSize: 2,
      expectedVersion: session.version, expectedQueryRevision: 2,
      query: {...query(3), constraints: query(2).constraints}, operationId: "refine-race",
    }),
  ]);
  assert.equal([show, competingRefine].filter((item) => item.status === "fulfilled").length, 1);
  assert.equal([show, competingRefine].filter((item) => item.status === "rejected")
    .every((item) => item.reason.code === "SESSION_CONFLICT" ||
      item.reason.code === "QUERY_REVISION_CONFLICT"), true);

  const current = await fixture.service.sessionStore.get(start.sessionId);
  const [focus, finalRefine] = await Promise.allSettled([
    fixture.service.dispatch({uid: "owner"}, {
      operation: "FOCUS_CANDIDATE", sessionId: start.sessionId, variantId: "v0",
      expectedVersion: current.version, operationId: "focus-race",
    }),
    fixture.service.dispatch({uid: "owner"}, {
      operation: "REFINE_QUERY", sessionId: start.sessionId, pageSize: 2,
      expectedVersion: current.version, expectedQueryRevision: current.query.revision,
      query: {...current.query, revision: current.query.revision + 1},
      operationId: "final-refine-race",
    }),
  ]);
  assert.equal([focus, finalRefine].filter((item) => item.status === "fulfilled").length, 1);
  await deleteApp(fixture.app);
});

test("expired but physically present session is unusable and malformed data fails closed", async () => {
  let now = 100;
  const app = initializeApp({projectId: PROJECT_ID}, `shopping-session-expiry-${appSerial++}`);
  const store = createFirestoreShoppingSessionStore(getFirestore(app), {now: () => now});
  const service = createShoppingOrchestrator({
    repository: createMemoryCatalogSearchRepository(catalog()),
    sessionStore: store,
  });
  const start = await service.dispatch({uid: "owner"}, {
    operation: "START_SEARCH", query: query(), pageSize: 1,
  });
  now += 30 * 60 * 1000;
  await assert.rejects(service.dispatch({uid: "owner"}, {
    operation: "SHOW_MORE", sessionId: start.sessionId, pageSize: 1,
  }), (error) => error.code === "SESSION_EXPIRED");
  const db = getFirestore(app);
  await db.collection("shoppingSessions").doc("malformed").set({schemaVersion: 999});
  await assert.rejects(store.get("malformed"), (error) => error.code === "SESSION_MALFORMED");
  await deleteApp(app);
});
