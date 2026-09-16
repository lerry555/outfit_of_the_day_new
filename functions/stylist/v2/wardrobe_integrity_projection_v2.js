"use strict";

const {artifact, canonicalDefinition} = require("../../wardrobe_ontology_v2");

const ONTOLOGY_TYPES = new Map(artifact.items.map((entry) => [entry.canonicalType, entry]));

function clean(value, max = 180) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function uniqueStrings(value, max = 12) {
  return [...new Set((Array.isArray(value) ? value : [])
    .map((entry) => clean(String(entry), 100)).filter(Boolean))].slice(0, max);
}

function sameStrings(left, right) {
  return JSON.stringify(uniqueStrings(left)) === JSON.stringify(uniqueStrings(right));
}

function trustedStructuralDefinitionV2(canonicalType) {
  const leaf = canonicalDefinition(canonicalType);
  if (!leaf) return {leaf: null, trusted: null, conflict: null};
  const parent = leaf.parentType ? ONTOLOGY_TYPES.get(leaf.parentType) || null : null;
  const familyConflict = parent && parent.canonicalFamily !== leaf.canonicalFamily;
  return {
    leaf,
    trusted: familyConflict ? parent : leaf,
    conflict: familyConflict ? {
      code: "ontology_parent_family_conflict",
      canonicalType: leaf.canonicalType,
      parentType: parent.canonicalType,
    } : null,
  };
}

function projectWardrobeItemForStylistV2(raw) {
  const source = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
  const itemId = clean(source.id || source.itemId);
  const canonicalType = clean(source.canonicalType, 100);
  const {leaf, trusted, conflict} = trustedStructuralDefinitionV2(canonicalType);
  const diagnostics = [];
  if (!leaf) {
    diagnostics.push({code: "unknown_canonical_type", itemId, canonicalType});
    return {item: {...source}, diagnostics};
  }
  if (conflict) diagnostics.push({...conflict, itemId});

  const expectedFamily = trusted.canonicalFamily;
  const expectedSlots = uniqueStrings(trusted.defaultBodySlots, 8);
  const sourceLayer = clean(source.layerPosition, 80);
  const supportedLayers = uniqueStrings(trusted.supportedLayerPositions, 8);
  const expectedLayer = supportedLayers.includes(sourceLayer) ? sourceLayer : trusted.defaultLayerPosition;
  if (clean(source.canonicalFamily, 100) !== expectedFamily) {
    diagnostics.push({code: "canonical_family_normalized", itemId, canonicalType});
  }
  if (!sameStrings(source.bodySlots, expectedSlots)) {
    diagnostics.push({code: "body_slots_normalized", itemId, canonicalType});
  }
  if (sourceLayer !== expectedLayer) {
    diagnostics.push({code: "layer_position_normalized", itemId, canonicalType});
  }

  // This is an in-memory safety projection only. The raw Firestore document is
  // never mutated or written back by the stylist pipeline.
  return {
    item: {
      ...source,
      canonicalFamily: expectedFamily,
      bodySlots: expectedSlots,
      layerPosition: expectedLayer,
      outfitFunctions: uniqueStrings(source.outfitFunctions?.length ?
        source.outfitFunctions : trusted.outfitFunctions, 16),
    },
    diagnostics,
  };
}

function projectWardrobeForStylistV2(items, {logger = console} = {}) {
  const projectedItems = [];
  const diagnostics = [];
  for (const raw of Array.isArray(items) ? items : []) {
    const projected = projectWardrobeItemForStylistV2(raw);
    projectedItems.push(projected.item);
    diagnostics.push(...projected.diagnostics);
  }
  if (diagnostics.length) {
    logger?.warn?.("STYLIST_V2_WARDROBE_INTEGRITY", {
      itemCount: projectedItems.length,
      diagnosticCount: diagnostics.length,
      diagnostics,
    });
  }
  return {items: projectedItems, diagnostics};
}

module.exports = {
  projectWardrobeForStylistV2,
  projectWardrobeItemForStylistV2,
  trustedStructuralDefinitionV2,
};
