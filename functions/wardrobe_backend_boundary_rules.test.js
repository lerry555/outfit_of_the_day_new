"use strict";

/**
 * Pure semantics tests for wardrobe backend-owned field boundary.
 * Authoritative Rules live in ../firestore.rules (Phase 5.3B-9C-R).
 * Fragment remains reference-only.
 */

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const RULES_PATH = path.resolve(__dirname, "../firestore.rules");
const FRAGMENT_PATH = path.resolve(
  __dirname, "../firestore/wardrobe_backend_boundary.rules");

function isOwner(authUid, userId) {
  return authUid != null && authUid === userId;
}

function backendOwnedKeys() {
  return ["qualificationAuthority", "wardrobeProfile"];
}

function creatingBackendOwnedMaps(data) {
  return backendOwnedKeys().some((key) =>
    Object.prototype.hasOwnProperty.call(data, key));
}

function affectedBackendKeys(before, after) {
  const affected = [];
  for (const key of backendOwnedKeys()) {
    const beforeHas = Object.prototype.hasOwnProperty.call(before, key);
    const afterHas = Object.prototype.hasOwnProperty.call(after, key);
    if (beforeHas !== afterHas) {
      affected.push(key);
      continue;
    }
    if (beforeHas && JSON.stringify(before[key]) !== JSON.stringify(after[key])) {
      affected.push(key);
    }
  }
  return affected;
}

function allowCreate({authUid, userId, data}) {
  return isOwner(authUid, userId) && !creatingBackendOwnedMaps(data);
}

function allowUpdate({authUid, userId, before, after}) {
  return isOwner(authUid, userId) &&
    affectedBackendKeys(before, after).length === 0;
}

function allowDelete({authUid, userId}) {
  return isOwner(authUid, userId);
}

function allowRead({authUid, userId}) {
  return isOwner(authUid, userId);
}

test("merged baseline exists and fragment is reference-only", () => {
  const text = fs.readFileSync(RULES_PATH, "utf8");
  assert.match(text, /qualificationAuthority/);
  assert.match(text, /wardrobeProfile/);
  assert.match(text, /wardrobeBackendOwnedKeys/);
  assert.doesNotMatch(text, /security_rules_baseline_missing/);
  const fragment = fs.readFileSync(FRAGMENT_PATH, "utf8");
  assert.match(fragment, /reference-only/);
  const firebaseJson = JSON.parse(fs.readFileSync(
    path.resolve(__dirname, "../firebase.json"), "utf8"));
  assert.equal(firebaseJson.firestore.rules, "firestore.rules");
});

test("1 owner can read own item", () => {
  assert.equal(allowRead({authUid: "u1", userId: "u1"}), true);
});

test("2 foreign user cannot read", () => {
  assert.equal(allowRead({authUid: "u2", userId: "u1"}), false);
});

test("3 owner can create legacy item without backend fields", () => {
  assert.equal(allowCreate({
    authUid: "u1", userId: "u1", data: {name: "Hoodie", brand: "X"},
  }), true);
});

test("4 owner cannot create qualificationAuthority", () => {
  assert.equal(allowCreate({
    authUid: "u1", userId: "u1",
    data: {name: "Hoodie", qualificationAuthority: {imageRevision: 1}},
  }), false);
});

test("5 owner cannot create wardrobeProfile", () => {
  assert.equal(allowCreate({
    authUid: "u1", userId: "u1",
    data: {name: "Hoodie", wardrobeProfile: {metadata: {}}},
  }), false);
});

test("6 owner can change allowed UX field", () => {
  assert.equal(allowUpdate({
    authUid: "u1", userId: "u1",
    before: {name: "A", qualificationAuthority: {v: 1}},
    after: {name: "B", qualificationAuthority: {v: 1}},
  }), true);
});

test("7 owner cannot change qualificationAuthority", () => {
  assert.equal(allowUpdate({
    authUid: "u1", userId: "u1",
    before: {name: "A", qualificationAuthority: {v: 1}},
    after: {name: "A", qualificationAuthority: {v: 2}},
  }), false);
});

test("8 owner cannot change wardrobeProfile", () => {
  assert.equal(allowUpdate({
    authUid: "u1", userId: "u1",
    before: {name: "A", wardrobeProfile: {r: 1}},
    after: {name: "A", wardrobeProfile: {r: 2}},
  }), false);
});

test("9 owner cannot remove only backend maps", () => {
  assert.equal(allowUpdate({
    authUid: "u1", userId: "u1",
    before: {name: "A", wardrobeProfile: {r: 1}},
    after: {name: "A"},
  }), false);
});

test("10 owner delete allowed", () => {
  assert.equal(allowDelete({authUid: "u1", userId: "u1"}), true);
});

test("11 server/Admin write is outside rules (documented)", () => {
  assert.equal(allowCreate({
    authUid: "u1", userId: "u1",
    data: {wardrobeProfile: {}},
  }), false);
});

test("12 nested machineEvidence mutation forbidden via wardrobeProfile", () => {
  assert.equal(allowUpdate({
    authUid: "u1", userId: "u1",
    before: {wardrobeProfile: {machineEvidence: []}},
    after: {wardrobeProfile: {machineEvidence: [{id: "x"}]}},
  }), false);
});

test("13 nested userCorrections mutation forbidden via wardrobeProfile", () => {
  assert.equal(allowUpdate({
    authUid: "u1", userId: "u1",
    before: {wardrobeProfile: {userCorrections: {}}},
    after: {wardrobeProfile: {userCorrections: {a: 1}}},
  }), false);
});

test("14 field injection of backend map forbidden", () => {
  assert.equal(allowUpdate({
    authUid: "u1", userId: "u1",
    before: {name: "A"},
    after: {name: "A", qualificationAuthority: {v: 1}},
  }), false);
});

test("15 product-link create without backend maps allowed", () => {
  assert.equal(allowCreate({
    authUid: "u1", userId: "u1",
    data: {
      name: "Item",
      productLinkSku: "sku",
      imageProcessingStatus: "queued",
    },
  }), true);
});

test("16 unknown root UX field policy allows create", () => {
  assert.equal(allowCreate({
    authUid: "u1", userId: "u1",
    data: {name: "A", customFutureField: true},
  }), true);
});

test("17 partial update with backend field denied", () => {
  assert.equal(allowUpdate({
    authUid: "u1", userId: "u1",
    before: {name: "A", wardrobeProfile: {r: 1}},
    after: {name: "B", wardrobeProfile: {r: 2}},
  }), false);
});

test("18 unchanged backend map with UX update allowed", () => {
  assert.equal(allowUpdate({
    authUid: "u1", userId: "u1",
    before: {
      name: "A",
      qualificationAuthority: {imageRevision: 1},
      wardrobeProfile: {revision: 1},
    },
    after: {
      name: "B",
      qualificationAuthority: {imageRevision: 1},
      wardrobeProfile: {revision: 1},
    },
  }), true);
});
