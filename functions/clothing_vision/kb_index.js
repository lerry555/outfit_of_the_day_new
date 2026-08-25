"use strict";

/**
 * Read-only Clothing KB index for production clothing vision validation.
 * Uses deployed prior artifact — does not invent taxonomy.
 */

const {
  loadClothingKnowledgeBasePriorArtifact,
} = require("../clothing_knowledge_base_prior_loader");

/** Conservative child → supported parent collapses (parents must exist in KB). */
const CHILD_TO_PARENT = Object.freeze({
  maxi_dress: "dress",
  midi_dress: "dress",
  mini_dress: "dress",
  sheath_dress: "dress",
  shirt_dress: "dress",
  faux_leather_jacket: "leather_jacket",
  palazzo_pants: "wide_leg_pants",
  mom_jeans: "jeans",
  flare_jeans: "jeans",
  distressed_jeans: "jeans",
  pencil_skirt: "skirt",
  pleated_skirt: "skirt",
  cable_knit_sweater: "knit_sweater",
  cropped_hoodie: "hoodie",
  long_cardigan: "cardigan",
  open_front_cardigan: "cardigan",
  midi_skirt: "skirt",
  maxi_skirt: "skirt",
  mini_skirt: "skirt",
  summer_dress: "dress",
  cocktail_dress: "dress",
  evening_dress: "dress",
  knit_sweater: "sweater",
  waistcoat: "vest",
  skinny_jeans: "jeans",
  slim_jeans: "jeans",
  straight_jeans: "jeans",
});

const LENGTH_SPECIFIC = new Set([
  "midi_skirt", "maxi_skirt", "mini_skirt",
  "summer_dress", "cocktail_dress", "evening_dress",
]);

const ONE_PIECE_TYPES = new Set([
  "dress", "summer_dress", "cocktail_dress", "evening_dress",
  "jumpsuit", "romper", "swimsuit", "hiking_outfit", "suit",
]);

function normalizeKey(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .replace(/[\s-]+/g, "_");
}

function createKbIndex(options = {}) {
  const artifact = options.artifact || loadClothingKnowledgeBasePriorArtifact(options);
  const byCanonical = new Map();
  const byAlias = new Map();
  for (const item of artifact.items) {
    const key = normalizeKey(item.canonicalType);
    byCanonical.set(key, item);
    for (const alias of item.aliases || []) {
      const a = normalizeKey(alias);
      if (a && !byAlias.has(a)) byAlias.set(a, item);
    }
  }
  return Object.freeze({
    artifact,
    findByCanonical(type) {
      return byCanonical.get(normalizeKey(type)) || null;
    },
    findByAlias(value) {
      return byAlias.get(normalizeKey(value)) || null;
    },
    resolveType(value) {
      const direct = byCanonical.get(normalizeKey(value));
      if (direct) return direct;
      return byAlias.get(normalizeKey(value)) || null;
    },
    parentOf(childType) {
      const parent = CHILD_TO_PARENT[normalizeKey(childType)];
      if (!parent) return null;
      return byCanonical.get(normalizeKey(parent)) || null;
    },
    isLengthSpecific(type) {
      return LENGTH_SPECIFIC.has(normalizeKey(type));
    },
    isOnePiece(type) {
      return ONE_PIECE_TYPES.has(normalizeKey(type));
    },
    childToParent: CHILD_TO_PARENT,
  });
}

module.exports = {
  CHILD_TO_PARENT,
  LENGTH_SPECIFIC,
  ONE_PIECE_TYPES,
  normalizeKey,
  createKbIndex,
};
