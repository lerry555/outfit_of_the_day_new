"use strict";

const {compactContextForModelV2, compactWardrobeForModelV2} =
  require("./openai_stylist_model_port_v2");
const {projectWardrobeForStylistV2} = require("./wardrobe_integrity_projection_v2");

const DEFAULT_VISUAL_EVIDENCE_LIMIT = 24;

function clean(value, max = 1200) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function list(value, max = 20) {
  return [...new Set((Array.isArray(value) ? value : [])
    .map((entry) => clean(String(entry), 180)).filter(Boolean))].slice(0, max);
}

function imageUrlV2(item) {
  for (const field of ["productImageUrl", "cutoutImageUrl", "cleanImageUrl", "imageUrl"]) {
    const value = clean(item?.[field], 3000);
    if (value) return value;
  }
  return null;
}

function structuralBucketV2(item) {
  const slots = list(item?.bodySlots, 8);
  if (slots.includes("feet")) return "feet";
  if (slots.includes("full_body")) return "full_body";
  if (slots.includes("lower_body")) return "lower_body";
  if (slots.includes("upper_body")) return `upper_body:${clean(item?.layerPosition, 40) || "unknown"}`;
  if (slots.length) return slots[0];
  return `family:${clean(item?.canonicalFamily, 60) || "unknown"}`;
}

function itemMatchesEditScopeV2(item, editScope, currentIds) {
  if (!item || typeof item !== "object") return false;
  if (!editScope) return true;
  if (currentIds.includes(item.id)) return true;
  if (editScope.allowRemovalOnly === true) return false;
  const slots = list(editScope.allowedSlots, 8);
  const categories = list(editScope.allowedCategories, 8).map((entry) => entry.toLowerCase());
  const slotMatch = !slots.length || list(item.bodySlots, 8).some((slot) => slots.includes(slot));
  const categoryValues = [item.category, item.subCategory, item.mainGroup,
    item.canonicalType, item.canonicalFamily].map((entry) => clean(entry, 100).toLowerCase()).filter(Boolean);
  const categoryMatch = !categories.length || categories.some((entry) => categoryValues.includes(entry));
  return slotMatch && categoryMatch;
}

function balancedVisualEvidenceV2(items, priorityIds, limit = DEFAULT_VISUAL_EVIDENCE_LIMIT) {
  const byId = new Map(items.map((item) => [item.id, item]));
  const selected = [];
  const seen = new Set();
  const add = (item) => {
    if (!item || seen.has(item.id) || !imageUrlV2(item) || selected.length >= limit) return;
    seen.add(item.id);
    selected.push({id: item.id, imageUrl: imageUrlV2(item)});
  };
  for (const id of list(priorityIds, 20)) add(byId.get(id));

  const buckets = new Map();
  for (const item of items) {
    const key = structuralBucketV2(item);
    if (!buckets.has(key)) buckets.set(key, []);
    buckets.get(key).push(item);
  }
  let index = 0;
  while (selected.length < limit) {
    let added = false;
    for (const bucket of buckets.values()) {
      if (index < bucket.length) {
        const before = selected.length;
        add(bucket[index]);
        if (selected.length > before) added = true;
      }
      if (selected.length >= limit) break;
    }
    if (!added && [...buckets.values()].every((bucket) => index >= bucket.length - 1)) break;
    index += 1;
  }
  return selected;
}

function buildSelectionContextV2({action, intentSummary, requestedConstraints, request,
  session, toolResults, wardrobeItems, userStylePreferences = null, logger = console,
  visualEvidenceLimit} = {}) {
  if (!["generate_outfit", "edit_outfit"].includes(action)) {
    throw new TypeError("selection_context_action_invalid");
  }
  const projection = projectWardrobeForStylistV2(wardrobeItems, {logger});
  const currentIds = list(session?.currentOutfit?.itemIds, 12);
  const editScope = action === "edit_outfit" ? toolResults?.authorizedEditScope || null : null;
  const eligible = projection.items.filter((item) => item?.id &&
    itemMatchesEditScopeV2(item, editScope, currentIds));
  const candidateMetadata = compactWardrobeForModelV2(eligible);
  const visualEvidence = balancedVisualEvidenceV2(
    eligible,
    [...currentIds, ...list(editScope?.replaceItemIds, 12)],
    Number.isSafeInteger(visualEvidenceLimit) ? visualEvidenceLimit : DEFAULT_VISUAL_EVIDENCE_LIMIT,
  );
  return {
    selection: {
      action,
      intentSummary: clean(intentSummary, 800) || clean(request?.latestUserInput, 800),
      requestedConstraints: list(requestedConstraints, 16),
      userStylePreferences: userStylePreferences && typeof userStylePreferences === "object" ?
        userStylePreferences : null,
      context: compactContextForModelV2(session?.context),
      currentOutfit: {
        itemIds: currentIds,
        selectionReasonsByItemId: session?.currentOutfit?.selectionReasonsByItemId || {},
      },
      authorizedEditScope: editScope,
      candidateItems: candidateMetadata,
    },
    candidateItems: eligible,
    visualEvidence,
    diagnostics: projection.diagnostics,
  };
}

module.exports = {
  DEFAULT_VISUAL_EVIDENCE_LIMIT,
  balancedVisualEvidenceV2,
  buildSelectionContextV2,
  imageUrlV2,
  itemMatchesEditScopeV2,
  structuralBucketV2,
};
