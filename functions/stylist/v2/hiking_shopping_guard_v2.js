"use strict";

const SPECIALIST_HIKING_TYPES_V2 = new Set([
  "hiking_shoes",
  "hiking_boots",
  "trekking_shoes",
  "trekking_boots",
]);

function clean(value, max = 180) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function isFootwearV2(item) {
  if (!item || typeof item !== "object") return false;
  if (String(item.category || "").trim().toLowerCase() === "footwear") return true;
  if (String(item.canonicalFamily || "").trim().toLowerCase() === "footwear") return true;
  return Array.isArray(item.bodySlots) && item.bodySlots.includes("feet");
}

function isSpecialistHikingFootwearV2(item) {
  if (!isFootwearV2(item)) return false;
  if (item?.safety?.hikingTechnical === true) return true;
  return SPECIALIST_HIKING_TYPES_V2.has(String(item.canonicalType || "").trim().toLowerCase());
}

function applyHikingShoppingNeedGuardV2(raw, input) {
  if (!raw || typeof raw !== "object") return raw;
  if (!["generate_outfit", "edit_outfit"].includes(raw.action)) return raw;
  if (String(input?.session?.context?.activity?.id || "").trim().toLowerCase() !== "hiking") return raw;

  const existingNeed = clean(raw.shoppingNeedLabel) || clean(raw.shoppingNeedCanonicalType);
  if (existingNeed) return raw;

  const wardrobe = Array.isArray(input?.toolResults?.wardrobeItems) ? input.toolResults.wardrobeItems : [];
  if (!wardrobe.length || wardrobe.some(isSpecialistHikingFootwearV2)) return raw;

  const selectedIds = new Set((Array.isArray(raw.resultingOutfitItemIds) ? raw.resultingOutfitItemIds : [])
    .map((id) => clean(String(id), 180)).filter(Boolean));
  const selectedFootwear = wardrobe.filter((item) => selectedIds.has(clean(String(item?.id || ""), 180)) && isFootwearV2(item));
  if (!selectedFootwear.length || selectedFootwear.some(isSpecialistHikingFootwearV2)) return raw;

  return {
    ...raw,
    offerShopping: true,
    shoppingNeedLabel: "turistické topánky",
    shoppingNeedCanonicalType: "hiking_shoes",
  };
}

module.exports = {
  SPECIALIST_HIKING_TYPES_V2,
  applyHikingShoppingNeedGuardV2,
  isFootwearV2,
  isSpecialistHikingFootwearV2,
};
