"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  applyHikingShoppingNeedGuardV2,
  isSpecialistHikingFootwearV2,
} = require("./hiking_shopping_guard_v2");

function hikingInput(wardrobeItems) {
  return {
    session: {context: {activity: {id: "hiking", label: "túra"}}},
    toolResults: {wardrobeItems},
  };
}

function outfitRaw(overrides = {}) {
  return {
    action: "generate_outfit",
    resultingOutfitItemIds: ["shirt", "pants", "sneakers"],
    offerShopping: false,
    shoppingNeedLabel: "",
    shoppingNeedCanonicalType: "",
    ...overrides,
  };
}

const sneakers = {
  id: "sneakers",
  category: "footwear",
  canonicalFamily: "footwear",
  canonicalType: "running_shoes",
  bodySlots: ["feet"],
  safety: {hikingTechnical: false},
};

const shirt = {id: "shirt", category: "tops", canonicalType: "t_shirt", bodySlots: ["upper_body"]};
const pants = {id: "pants", category: "bottoms", canonicalType: "joggers", bodySlots: ["lower_body"]};

test("ordinary hiking sneakers stay selected but restore a typed hiking shopping need", () => {
  const guarded = applyHikingShoppingNeedGuardV2(outfitRaw(), hikingInput([shirt, pants, sneakers]));

  assert.deepEqual(guarded.resultingOutfitItemIds, ["shirt", "pants", "sneakers"]);
  assert.equal(guarded.offerShopping, true);
  assert.equal(guarded.shoppingNeedLabel, "turistické topánky");
  assert.equal(guarded.shoppingNeedCanonicalType, "hiking_shoes");
});

test("available specialist hiking footwear prevents a false shopping need", () => {
  const hikingBoots = {
    id: "boots",
    category: "footwear",
    canonicalFamily: "footwear",
    canonicalType: "hiking_boots",
    bodySlots: ["feet"],
    safety: {hikingTechnical: true},
  };
  const raw = outfitRaw();
  const guarded = applyHikingShoppingNeedGuardV2(raw, hikingInput([shirt, pants, sneakers, hikingBoots]));

  assert.equal(guarded, raw);
  assert.equal(isSpecialistHikingFootwearV2(hikingBoots), true);
});

test("non-hiking outfits are never changed by the hiking shopping guard", () => {
  const raw = outfitRaw();
  const input = {
    session: {context: {activity: {id: "work", label: "práca"}}},
    toolResults: {wardrobeItems: [shirt, pants, sneakers]},
  };
  assert.equal(applyHikingShoppingNeedGuardV2(raw, input), raw);
});

test("an explicit model shopping need is preserved instead of overwritten", () => {
  const raw = outfitRaw({
    offerShopping: true,
    shoppingNeedLabel: "nepremokavá bunda",
    shoppingNeedCanonicalType: "rain_jacket",
  });
  assert.equal(applyHikingShoppingNeedGuardV2(raw, hikingInput([shirt, pants, sneakers])), raw);
});
