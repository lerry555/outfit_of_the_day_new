"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  STYLE_PREFERENCE_RULES,
  appendStylePreferencesSection,
  formatStylePreferencesBlock,
  sanitizeUserStylePreferences,
} = require("./style_preferences_context");

test("missing and empty preferences produce no block", () => {
  assert.equal(sanitizeUserStylePreferences(null), null);
  assert.equal(sanitizeUserStylePreferences({}), null);
  assert.equal(sanitizeUserStylePreferences({
    favoriteColors: [],
    preferredStyles: [],
  }), null);
  assert.equal(formatStylePreferencesBlock(null), "");
  assert.equal(appendStylePreferencesSection("base", null), "base");
});

test("preferred style is represented as a user preference", () => {
  const block = formatStylePreferencesBlock({preferredStyles: ["casual"]});
  assert.match(block, /preferredStyles: casual/);
  assert.match(block, /positive style preference/);
});

test("avoided color is a strong avoid, not an absolute safety constraint", () => {
  const block = formatStylePreferencesBlock({avoidedColors: ["red"]});
  assert.match(block, /avoidedColors: red/);
  assert.match(block, /not an absolute safety constraint/);
  assert.match(STYLE_PREFERENCE_RULES, /nie tvrdé bezpečnostné pravidlo/);
});

test("favorite color is a soft preference", () => {
  const block = formatStylePreferencesBlock({favoriteColors: ["blue"]});
  assert.match(block, /favoriteColors: blue/);
  assert.match(block, /soft preference, not required/);
});

test("favorite brand is a weak wardrobe-conditional preference", () => {
  const block = formatStylePreferencesBlock({favoriteBrands: ["Zara"]});
  assert.match(block, /favoriteBrands: Zara/);
  assert.match(block, /weak preference only when a wardrobe item actually has that brand/);
});

test("outfit presentation is explicit authority, not inferred from wardrobe", () => {
  const block = formatStylePreferencesBlock({stylingPresentation: "menswear"});
  assert.match(block, /stylingPresentation: menswear/);
  assert.match(block, /wardrobe contents do not override it/);
  assert.equal(
    sanitizeUserStylePreferences({stylingPresentation: "invented"}),
    null,
  );
});

test("current-turn request outranks saved avoid preferences", () => {
  assert.match(STYLE_PREFERENCE_RULES, /aktuálna správa používateľa/);
  assert.match(STYLE_PREFERENCE_RULES, /prebiť/);
  assert.match(
    formatStylePreferencesBlock({avoidedColors: ["black"]}),
    /current message > occasion/,
  );
});

test("suitability and dress code outrank saved taste", () => {
  assert.match(STYLE_PREFERENCE_RULES, /dress code \/ príležitosť/);
  assert.match(STYLE_PREFERENCE_RULES, /svadba, pohreb, pohovor/);
  assert.match(STYLE_PREFERENCE_RULES, /suitability vyhrá/);
});

test("unrelated fields and sizes are stripped", () => {
  const clean = sanitizeUserStylePreferences({
    favoriteColors: ["blue"],
    shoeSize: "42",
    topSize: "M",
    email: "a@b.c",
    fcmTokens: ["secret"],
    isPremium: true,
  });
  assert.deepEqual(Object.keys(clean).sort(), [
    "avoidedColors",
    "favoriteBrands",
    "favoriteColors",
    "preferredStyles",
  ]);
  assert.deepEqual(clean.favoriteColors, ["blue"]);
  assert.equal(JSON.stringify(clean).includes("42"), false);
  assert.equal(JSON.stringify(clean).includes("secret"), false);
  assert.equal(JSON.stringify(clean).includes("a@b.c"), false);
});
