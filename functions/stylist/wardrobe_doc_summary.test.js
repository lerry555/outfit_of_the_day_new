"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  setMembershipSummaryFragments,
  wardrobeDocToSummaryLine,
} = require("./wardrobe_doc_summary");

const shirt = {
  id: "shirt-1",
  name: "Biela košeľa",
  categoryKey: "kosele",
  setMembership: {
    setId: "set-abc",
    setType: "matching_set",
    relationshipSource: "manufacturer_matching",
    authority: "user_confirmation",
    displayName: "Test set",
  },
};
const jacket = {
  id: "jacket-1",
  name: "Rifľová bunda",
  setMembership: {
    setId: "set-abc",
    setType: "matching_set",
    relationshipSource: "manufacturer_matching",
    authority: "user_confirmation",
  },
};
const hoodie = {
  id: "hoodie-1",
  name: "Mikina",
  setMembership: {
    setId: "set-user",
    setType: "tracksuit",
    relationshipSource: "user_curated",
    authority: "user_confirmation",
  },
};

test("omits set fragments when membership is absent", () => {
  assert.deepEqual(setMembershipSummaryFragments({id: "x", name: "Top"}), []);
});

test("emits setId setType relationshipSource and partners", () => {
  const line = wardrobeDocToSummaryLine(shirt, [shirt, jacket, hoodie]);
  assert.match(line, /setId: set-abc/);
  assert.match(line, /setType: matching_set/);
  assert.match(line, /relationshipSource: manufacturer_matching/);
  assert.match(line, /setPartnerIds: jacket-1/);
  assert.match(line, /setPreference: confirmed_matching_relationship/);
  assert.match(line, /setSignal: preference_not_hard_constraint/);
  assert.doesNotMatch(line, /hoodie-1/);
});

test("marks user_curated as explicit user preference", () => {
  const line = wardrobeDocToSummaryLine(hoodie, [hoodie, shirt]);
  assert.match(line, /relationshipSource: user_curated/);
  assert.match(line, /setPreference: explicit_user_preference/);
  assert.doesNotMatch(line, /setPartnerIds/);
});

test("does not reintroduce retired v1 type/category fields as identity", () => {
  const line = wardrobeDocToSummaryLine({
    id: "x",
    name: "Košeľa",
    categoryKey: "kosele",
    canonicalType: "dress_shirt",
  });
  assert.doesNotMatch(line, / \| type:/);
  assert.match(line, /kategória: kosele/);
});
