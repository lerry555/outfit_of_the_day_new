"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  HOME_TASTE_RULES,
  attachHomeFinalReviewPreferences,
} = require("./home_final_review_preferences");

test("empty prefs are omitted from Home final review", () => {
  const empty = attachHomeFinalReviewPreferences(null);
  assert.equal(empty.prefs, null);
  assert.equal(empty.systemSuffix, "");
  assert.equal(empty.userBlock, "");
});

test("taste-only payload is sanitized and suitability-first", () => {
  const attached = attachHomeFinalReviewPreferences({
    favoriteColors: ["blue"],
    avoidedColors: ["red"],
    preferredStyles: ["casual"],
    favoriteBrands: ["Zara"],
    shoeSize: "42",
    email: "a@b.c",
  });
  assert.deepEqual(Object.keys(attached.prefs).sort(), [
    "avoidedColors",
    "favoriteBrands",
    "favoriteColors",
    "preferredStyles",
  ]);
  assert.match(attached.userBlock, /favoriteColors: blue/);
  assert.match(attached.userBlock, /soft preference/);
  assert.match(attached.userBlock, /not an absolute safety constraint/);
  assert.match(HOME_TASTE_RULES, /Chuť NESMIE vybrať menej vhodný outfit/);
  assert.equal(JSON.stringify(attached.prefs).includes("42"), false);
  assert.equal(JSON.stringify(attached.prefs).includes("a@b.c"), false);
});
