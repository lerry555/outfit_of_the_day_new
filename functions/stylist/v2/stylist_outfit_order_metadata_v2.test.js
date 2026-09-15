"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {sortStylistItemIdsV2} = require("./stylist_outfit_order_v2");

test("canonical layer metadata outranks generic upper_body when layerPosition is missing", () => {
  const items = [
    {id: "tee", category: "tops", canonicalType: "t_shirt", bodySlots: ["upper_body"]},
    {id: "hoodie", category: "tops", canonicalType: "hoodie", bodySlots: ["upper_body"]},
    {id: "jacket", category: "tops", canonicalType: "jacket", bodySlots: ["upper_body"]},
    {id: "pants", category: "bottoms", canonicalType: "pants", bodySlots: ["lower_body"]},
    {id: "shoes", category: "footwear", canonicalType: "sneakers", bodySlots: ["feet"]},
  ];

  assert.deepEqual(
    sortStylistItemIdsV2(["tee", "shoes", "jacket", "pants", "hoodie"], items),
    ["jacket", "hoodie", "tee", "pants", "shoes"],
  );
});
