"use strict";

/**
 * M11.1 Phase 5.3B-9C-R — Firestore Rules emulator tests against merged
 * authoritative baseline: ../firestore.rules
 *
 * Does not deploy. Does not use production project data.
 */

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, collection} =
  require("firebase/firestore");

const PROJECT_ID = "demo-ootd-rules-9cr";
const RULES_PATH = path.resolve(__dirname, "../firestore.rules");
const OWNER = "owner-uid";
const FOREIGN = "foreign-uid";

/** @type {import("@firebase/rules-unit-testing").RulesTestEnvironment} */
let testEnv;

function rulesText() {
  return fs.readFileSync(RULES_PATH, "utf8");
}

function wardrobePath(uid, itemId) {
  return `users/${uid}/wardrobe/${itemId}`;
}

test.before(async () => {
  assert.ok(fs.existsSync(RULES_PATH), "firestore.rules must exist");
  const text = rulesText();
  assert.match(text, /qualificationAuthority/);
  assert.match(text, /wardrobeProfile/);
  assert.match(text, /wardrobeBackendOwnedKeys/);
  assert.match(text, /firstSegment != 'wardrobe'/);
  assert.doesNotMatch(text, /security_rules_baseline_missing/);
  assert.doesNotMatch(text, /isWardrobeItemCatchAllPath/);

  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {rules: text},
  });
});

test.after(async () => {
  if (testEnv) await testEnv.cleanup();
});

test.beforeEach(async () => {
  await testEnv.clearFirestore();
});

async function seedOwnerItem(itemId, data) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, wardrobePath(OWNER, itemId)), data);
  });
}

function ownerDb() {
  return testEnv.authenticatedContext(OWNER).firestore();
}

function foreignDb() {
  return testEnv.authenticatedContext(FOREIGN).firestore();
}

function unauthDb() {
  return testEnv.unauthenticatedContext().firestore();
}

// ---------------------------------------------------------------------------
// READ
// ---------------------------------------------------------------------------

test("1 owner read own item", async () => {
  await seedOwnerItem("i1", {name: "Hoodie"});
  await assertSucceeds(getDoc(doc(ownerDb(), wardrobePath(OWNER, "i1"))));
});

test("2 owner list own wardrobe", async () => {
  await seedOwnerItem("i1", {name: "A"});
  await seedOwnerItem("i2", {name: "B"});
  await assertSucceeds(getDocs(collection(ownerDb(), `users/${OWNER}/wardrobe`)));
});

test("3 foreign user read denied", async () => {
  await seedOwnerItem("i1", {name: "Hoodie"});
  await assertFails(getDoc(doc(foreignDb(), wardrobePath(OWNER, "i1"))));
});

test("4 unauthenticated read denied", async () => {
  await seedOwnerItem("i1", {name: "Hoodie"});
  await assertFails(getDoc(doc(unauthDb(), wardrobePath(OWNER, "i1"))));
});

// ---------------------------------------------------------------------------
// CREATE
// ---------------------------------------------------------------------------

test("5 owner create legacy user-photo item", async () => {
  await assertSucceeds(setDoc(doc(ownerDb(), wardrobePath(OWNER, "new1")), {
    name: "Blue Hoodie",
    brand: "X",
    categoryKey: "tops",
    colors: ["blue"],
    storagePath: `wardrobe/${OWNER}/a.jpg`,
    imageUrl: "https://example.test/a.jpg",
  }));
});

test("6 owner create product-link item", async () => {
  await assertSucceeds(setDoc(doc(ownerDb(), wardrobePath(OWNER, "pl1")), {
    name: "Product Item",
    productLinkSku: "SKU-1",
    imageProcessingStatus: "processing",
    sourceUrl: "https://shop.example/item",
  }));
});

test("7 foreign path create denied", async () => {
  await assertFails(setDoc(doc(foreignDb(), wardrobePath(OWNER, "x")), {
    name: "Nope",
  }));
});

test("8 unauthenticated create denied", async () => {
  await assertFails(setDoc(doc(unauthDb(), wardrobePath(OWNER, "x")), {
    name: "Nope",
  }));
});

test("9 create with qualificationAuthority denied", async () => {
  await assertFails(setDoc(doc(ownerDb(), wardrobePath(OWNER, "bad-qa")), {
    name: "Hoodie",
    qualificationAuthority: {imageRevision: 1},
  }));
});

test("10 create with wardrobeProfile denied", async () => {
  await assertFails(setDoc(doc(ownerDb(), wardrobePath(OWNER, "bad-wp")), {
    name: "Hoodie",
    wardrobeProfile: {metadata: {revision: 1}},
  }));
});

test("11 create with nested machineEvidence denied", async () => {
  await assertFails(setDoc(doc(ownerDb(), wardrobePath(OWNER, "bad-me")), {
    name: "Hoodie",
    wardrobeProfile: {machineEvidence: [{id: "e1"}]},
  }));
});

test("12 create with both backend maps denied", async () => {
  await assertFails(setDoc(doc(ownerDb(), wardrobePath(OWNER, "bad-both")), {
    name: "Hoodie",
    qualificationAuthority: {v: 1},
    wardrobeProfile: {r: 1},
  }));
});

// ---------------------------------------------------------------------------
// UPDATE
// ---------------------------------------------------------------------------

test("13 owner update allowed UX field", async () => {
  await seedOwnerItem("u1", {name: "A", brand: "X"});
  await assertSucceeds(updateDoc(doc(ownerDb(), wardrobePath(OWNER, "u1")), {
    name: "B",
  }));
});

test("14 owner update multiple UX fields", async () => {
  await seedOwnerItem("u2", {name: "A", brand: "X", colors: ["red"]});
  await assertSucceeds(updateDoc(doc(ownerDb(), wardrobePath(OWNER, "u2")), {
    name: "B",
    brand: "Y",
    colors: ["blue"],
    styles: ["casual"],
  }));
});

test("15 foreign update denied", async () => {
  await seedOwnerItem("u3", {name: "A"});
  await assertFails(updateDoc(doc(foreignDb(), wardrobePath(OWNER, "u3")), {
    name: "Hacked",
  }));
});

test("16 unauthenticated update denied", async () => {
  await seedOwnerItem("u4", {name: "A"});
  await assertFails(updateDoc(doc(unauthDb(), wardrobePath(OWNER, "u4")), {
    name: "Hacked",
  }));
});

test("17 add qualificationAuthority denied", async () => {
  await seedOwnerItem("u5", {name: "A"});
  await assertFails(updateDoc(doc(ownerDb(), wardrobePath(OWNER, "u5")), {
    qualificationAuthority: {imageRevision: 1},
  }));
});

test("18 change qualificationAuthority denied", async () => {
  await seedOwnerItem("u6", {
    name: "A",
    qualificationAuthority: {imageRevision: 1},
  });
  await assertFails(updateDoc(doc(ownerDb(), wardrobePath(OWNER, "u6")), {
    qualificationAuthority: {imageRevision: 2},
  }));
});

test("19 remove qualificationAuthority denied", async () => {
  await seedOwnerItem("u7", {
    name: "A",
    qualificationAuthority: {imageRevision: 1},
  });
  await assertFails(setDoc(doc(ownerDb(), wardrobePath(OWNER, "u7")), {
    name: "A",
  }));
});

test("20 add wardrobeProfile denied", async () => {
  await seedOwnerItem("u8", {name: "A"});
  await assertFails(updateDoc(doc(ownerDb(), wardrobePath(OWNER, "u8")), {
    wardrobeProfile: {metadata: {revision: 1}},
  }));
});

test("21 change wardrobeProfile denied", async () => {
  await seedOwnerItem("u9", {
    name: "A",
    wardrobeProfile: {metadata: {revision: 1}},
  });
  await assertFails(updateDoc(doc(ownerDb(), wardrobePath(OWNER, "u9")), {
    wardrobeProfile: {metadata: {revision: 2}},
  }));
});

test("22 remove wardrobeProfile denied", async () => {
  await seedOwnerItem("u10", {
    name: "A",
    wardrobeProfile: {metadata: {revision: 1}},
  });
  await assertFails(setDoc(doc(ownerDb(), wardrobePath(OWNER, "u10")), {
    name: "A",
  }));
});

test("23 nested machineEvidence mutation denied", async () => {
  await seedOwnerItem("u11", {
    name: "A",
    wardrobeProfile: {machineEvidence: []},
  });
  await assertFails(updateDoc(doc(ownerDb(), wardrobePath(OWNER, "u11")), {
    wardrobeProfile: {machineEvidence: [{id: "x"}]},
  }));
});

test("24 nested profile revision mutation denied", async () => {
  await seedOwnerItem("u12", {
    name: "A",
    wardrobeProfile: {metadata: {revision: 1}},
  });
  await assertFails(updateDoc(doc(ownerDb(), wardrobePath(OWNER, "u12")), {
    wardrobeProfile: {metadata: {revision: 99}},
  }));
});

test("25 unchanged backend maps + UX update allowed", async () => {
  await seedOwnerItem("u13", {
    name: "A",
    qualificationAuthority: {imageRevision: 1},
    wardrobeProfile: {metadata: {revision: 1}},
  });
  // merge-style set that preserves backend maps
  await assertSucceeds(setDoc(doc(ownerDb(), wardrobePath(OWNER, "u13")), {
    name: "B",
    qualificationAuthority: {imageRevision: 1},
    wardrobeProfile: {metadata: {revision: 1}},
  }, {merge: true}));
});

test("26 backend map set to null denied", async () => {
  await seedOwnerItem("u14", {
    name: "A",
    wardrobeProfile: {metadata: {revision: 1}},
  });
  await assertFails(updateDoc(doc(ownerDb(), wardrobePath(OWNER, "u14")), {
    wardrobeProfile: null,
  }));
});

test("27 partial update field injection denied", async () => {
  await seedOwnerItem("u15", {
    name: "A",
    wardrobeProfile: {metadata: {revision: 1}},
  });
  await assertFails(updateDoc(doc(ownerDb(), wardrobePath(OWNER, "u15")), {
    name: "B",
    wardrobeProfile: {metadata: {revision: 2}},
  }));
});

test("28 unknown root UX field update allowed (baseline contract)", async () => {
  await seedOwnerItem("u16", {name: "A", customFutureField: true});
  await assertSucceeds(updateDoc(doc(ownerDb(), wardrobePath(OWNER, "u16")), {
    customFutureField: false,
    anotherUxField: 1,
  }));
});

// ---------------------------------------------------------------------------
// DELETE
// ---------------------------------------------------------------------------

test("29 owner whole-document delete allowed", async () => {
  await seedOwnerItem("d1", {name: "Gone"});
  await assertSucceeds(deleteDoc(doc(ownerDb(), wardrobePath(OWNER, "d1"))));
});

test("30 foreign delete denied", async () => {
  await seedOwnerItem("d2", {name: "Stay"});
  await assertFails(deleteDoc(doc(foreignDb(), wardrobePath(OWNER, "d2"))));
});

test("31 unauthenticated delete denied", async () => {
  await seedOwnerItem("d3", {name: "Stay"});
  await assertFails(deleteDoc(doc(unauthDb(), wardrobePath(OWNER, "d3"))));
});

// ---------------------------------------------------------------------------
// SPECIAL / regression
// ---------------------------------------------------------------------------

test("32 derivative field update allowed (current client/Admin transitional UX)", async () => {
  await seedOwnerItem("s1", {
    name: "A",
    storagePath: `wardrobe/${OWNER}/a.jpg`,
  });
  await assertSucceeds(updateDoc(doc(ownerDb(), wardrobePath(OWNER, "s1")), {
    cleanImageUrl: "https://example.test/clean.jpg",
    cutoutImageUrl: "https://example.test/clean.jpg",
    productImageUrl: "https://example.test/product.jpg",
  }));
});

test("33 classification edit allowed (transitional client contract)", async () => {
  await seedOwnerItem("s2", {
    name: "Old",
    categoryKey: "tops",
    subCategoryKey: "hoodie",
    colors: ["red"],
  });
  await assertSucceeds(updateDoc(doc(ownerDb(), wardrobePath(OWNER, "s2")), {
    name: "New",
    categoryKey: "tops",
    subCategoryKey: "sweater",
    colors: ["navy"],
    styles: ["smart"],
    patterns: ["solid"],
    seasons: ["winter"],
  }));
});

test("34 nested userCorrections direct-write denied", async () => {
  await seedOwnerItem("s3", {
    name: "A",
    wardrobeProfile: {userCorrections: {}},
  });
  await assertFails(updateDoc(doc(ownerDb(), wardrobePath(OWNER, "s3")), {
    wardrobeProfile: {
      userCorrections: {
        fit: {property: "fit", action: "set", value: "loose"},
      },
    },
  }));
});

test("35 Admin setup bypass works via withSecurityRulesDisabled", async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await assertSucceeds(setDoc(doc(db, wardrobePath(OWNER, "admin1")), {
      name: "Seed",
      qualificationAuthority: {imageRevision: 1},
      wardrobeProfile: {machineEvidence: [{id: "e"}]},
    }));
  });
  const snap = await getDoc(doc(ownerDb(), wardrobePath(OWNER, "admin1")));
  assert.equal(snap.exists(), true);
  assert.equal(snap.data().qualificationAuthority.imageRevision, 1);
});

test("36 non-wardrobe user subcollection still owner-writable", async () => {
  await assertSucceeds(setDoc(doc(ownerDb(), `users/${OWNER}/trips/t1`), {
    title: "Weekend",
  }));
  await assertSucceeds(updateDoc(doc(ownerDb(), `users/${OWNER}/trips/t1`), {
    title: "Long weekend",
  }));
});

test("37 foreign non-wardrobe subcollection denied", async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `users/${OWNER}/trips/t2`), {
      title: "Private",
    });
  });
  await assertFails(getDoc(doc(foreignDb(), `users/${OWNER}/trips/t2`)));
});

const shadowLeasePath = "wardrobeAuthorityShadowLeases/test-lease";
async function seedShadowLease() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), shadowLeasePath), {status: "fresh"});
  });
}

test("38 unauthenticated shadow lease read denied", async () => {
  await seedShadowLease();
  await assertFails(getDoc(doc(unauthDb(), shadowLeasePath)));
});
test("39 authenticated owner shadow lease read denied", async () => {
  await seedShadowLease();
  await assertFails(getDoc(doc(ownerDb(), shadowLeasePath)));
});
test("40 authenticated non-owner shadow lease read denied", async () => {
  await seedShadowLease();
  await assertFails(getDoc(doc(foreignDb(), shadowLeasePath)));
});
test("41 shadow lease client create denied", async () => {
  await assertFails(setDoc(doc(ownerDb(), shadowLeasePath), {status: "fresh"}));
});
test("42 shadow lease client update denied", async () => {
  await seedShadowLease();
  await assertFails(updateDoc(doc(ownerDb(), shadowLeasePath), {status: "consumed"}));
});
test("43 shadow lease client delete denied", async () => {
  await seedShadowLease();
  await assertFails(deleteDoc(doc(ownerDb(), shadowLeasePath)));
});
test("44 existing wardrobe owner rule remains allowed", async () => {
  await assertSucceeds(setDoc(doc(ownerDb(), wardrobePath(OWNER, "unchanged")),
    {name: "Still allowed"}));
});
