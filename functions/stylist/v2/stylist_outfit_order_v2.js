"use strict";

function folded(value) {
  return String(value || "").toLowerCase().replace(/[_-]+/g, " ");
}

function itemPriorityV2(item) {
  const layer = folded(item?.layerPosition);
  const slots = Array.isArray(item?.bodySlots) ? item.bodySlots : [];
  const category = folded(item?.category);
  const descriptor = folded([item?.canonicalType, item?.canonicalFamily, item?.subCategory, item?.mainGroup].filter(Boolean).join(" "));

  if (["shell", "outer"].includes(layer)) return 10;
  if (layer === "mid") return 20;

  // Canonical clothing metadata outranks a generic upper_body slot when the
  // layerPosition field is missing. Otherwise a jacket/hoodie with valid
  // bodySlots but incomplete layer metadata can be rendered like a base top.
  if (/\b(jacket|coat|parka|puffer|windbreaker|anorak|outerwear|blazer)\b/.test(`${category} ${descriptor}`)) return 10;
  if (/\b(hoodie|sweatshirt|sweater|cardigan|jumper|pullover|knitwear)\b/.test(descriptor)) return 20;

  if (slots.includes("upper_body")) return 30;
  if (slots.includes("full_body")) return 35;
  if (slots.includes("lower_body")) return 40;
  if (slots.includes("feet")) return 50;
  if (item?.accessoryGroup) return 60;

  if (["top", "tops", "shirt", "shirts"].includes(category)) return 30;
  if (["dress", "dresses", "full body", "fullbody"].includes(category)) return 35;
  if (["bottom", "bottoms", "pants", "trousers", "jeans", "shorts", "skirts"].includes(category)) return 40;
  if (["footwear", "shoes", "shoe", "boots", "sneakers"].includes(category)) return 50;
  if (["accessory", "accessories"].includes(category)) return 60;
  return 70;
}

function sortStylistItemsV2(items) {
  return (Array.isArray(items) ? items : [])
    .map((item, index) => ({item, index}))
    .sort((a, b) => itemPriorityV2(a.item) - itemPriorityV2(b.item) || a.index - b.index)
    .map((entry) => entry.item);
}

function sortStylistItemIdsV2(ids, items) {
  const byId = new Map((Array.isArray(items) ? items : []).map((item) => [item.id, item]));
  return (Array.isArray(ids) ? ids : [])
    .map((id, index) => ({id, item: byId.get(id), index}))
    .sort((a, b) => itemPriorityV2(a.item) - itemPriorityV2(b.item) || a.index - b.index)
    .map((entry) => entry.id);
}

module.exports = {itemPriorityV2, sortStylistItemIdsV2, sortStylistItemsV2};
