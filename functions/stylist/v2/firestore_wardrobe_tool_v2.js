"use strict";

const HIKING_TECHNICAL_TYPES = new Set(["hiking_shoes", "hiking_boots", "trekking_shoes", "trekking_boots"]);
const MAX_WARDROBE_ITEMS = 200;
const wardrobeCacheByUid = new Map();

function text(value, max = 2000) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function strings(value, max = 24) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map((item) => text(String(item), 120)).filter(Boolean))].slice(0, max);
}

function safeMap(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function cloneItems(items) {
  return JSON.parse(JSON.stringify(Array.isArray(items) ? items : []));
}

function timestampToken(value) {
  if (value == null) return "";
  if (typeof value.toMillis === "function") return String(value.toMillis());
  if (typeof value.toDate === "function") return String(value.toDate().getTime());
  if (value instanceof Date) return String(value.getTime());
  if (Number.isFinite(Number(value))) return String(Number(value));
  return text(String(value), 120);
}

function projectWardrobeItemV2(id, raw = {}) {
  const item = safeMap(raw);
  const bodySlots = strings(item.bodySlots, 8);
  const canonicalType = text(item.canonicalType || item.type, 100).toLowerCase();
  const isFootwear = bodySlots.includes("feet");
  const category = isFootwear ? "footwear" : text(item.category || item.categoryKey, 100).toLowerCase();
  return {
    id: text(id, 180),
    name: text(item.name || item.typePretty || item.type || canonicalType, 160),
    category,
    subCategory: text(item.subCategory || item.subCategoryKey, 100),
    mainGroup: text(item.mainGroup || item.mainGroupKey, 100),
    canonicalType,
    canonicalFamily: text(item.canonicalFamily, 100).toLowerCase(),
    bodySlots,
    layerPosition: text(item.layerPosition, 80).toLowerCase(),
    colorProfile: safeMap(item.colorProfile),
    colors: strings(item.colors, 8),
    warmth: Number.isFinite(Number(item.warmth)) ? Number(item.warmth) : 0,
    formality: Number.isFinite(Number(item.formality)) ? Number(item.formality) : 0,
    outfitFunctions: strings(item.outfitFunctions, 16),
    occasionFit: strings(item.occasionFit, 12),
    seasons: strings(item.seasons, 8),
    accessoryGroup: text(item.accessoryGroup, 80).toLowerCase() || null,
    productImageUrl: text(item.productImageUrl, 2000),
    cutoutImageUrl: text(item.cutoutImageUrl, 2000),
    cleanImageUrl: text(item.cleanImageUrl, 2000),
    imageUrl: text(item.productImageUrl || item.cutoutImageUrl || item.cleanImageUrl || item.imageUrl, 2000),
    safety: {
      // Conservative authority: ordinary/winter boots are NOT promoted to
      // technical hiking footwear merely because the activity is a hike.
      // This does not claim waterproofing, grip, or ice safety.
      hikingTechnical: isFootwear && HIKING_TECHNICAL_TYPES.has(canonicalType),
    },
  };
}

function categoryMatches(item, rawCategory) {
  const category = text(rawCategory, 100).toLowerCase();
  if (!category) return false;
  if (["footwear", "feet", "shoes", "topanky", "topánky"].includes(category)) {
    return item.bodySlots.includes("feet");
  }
  if (["lower_body", "bottom", "bottoms", "nohavice", "rifle", "kraťasy", "kratasy"].includes(category)) {
    return item.bodySlots.includes("lower_body");
  }
  if (["upper_body", "top", "tops", "tricko", "tričko"].includes(category)) {
    return item.bodySlots.includes("upper_body") && !["mid", "outer", "shell"].includes(item.layerPosition);
  }
  if (["layer", "layers", "mikina", "sveter", "bunda", "outerwear"].includes(category)) {
    return item.bodySlots.includes("upper_body") && ["mid", "outer", "shell"].includes(item.layerPosition);
  }
  if (["full_body", "dress"].includes(category)) return item.bodySlots.includes("full_body");
  if (["accessory", "accessories", "doplnok", "doplnky"].includes(category)) {
    return Boolean(item.accessoryGroup) || item.bodySlots.every((slot) =>
      !["upper_body", "lower_body", "full_body", "feet"].includes(slot));
  }
  return item.category === category || item.canonicalFamily === category || item.canonicalType === category;
}

function clearWardrobeCacheV2(uid = null) {
  if (uid == null) wardrobeCacheByUid.clear();
  else wardrobeCacheByUid.delete(String(uid));
}

async function readWardrobeRevisionTokenV2(root) {
  // A count catches add/remove. The newest updatedAt catches ordinary item
  // edits. If either capability is unavailable, return null and deliberately
  // bypass the cache instead of risking a stale wardrobe recommendation.
  if (!root || typeof root.count !== "function" || typeof root.orderBy !== "function") return null;
  try {
    const [countSnapshot, latestSnapshot] = await Promise.all([
      root.count().get(),
      root.orderBy("updatedAt", "desc").limit(1).get(),
    ]);
    const count = Number(countSnapshot?.data?.()?.count);
    if (!Number.isFinite(count) || count < 0) return null;
    if (count === 0) return "0:empty";
    const latestDoc = latestSnapshot?.docs?.[0];
    if (!latestDoc?.exists && !latestDoc?.id) return null;
    const latest = latestDoc.data?.() || {};
    const updated = timestampToken(latest.updatedAt);
    if (!updated) return null;
    const itemRevision = Number.isFinite(Number(latest.wardrobeItemRevision)) ? Number(latest.wardrobeItemRevision) : 0;
    return `${count}:${updated}:${text(latestDoc.id, 180)}:${itemRevision}`;
  } catch (_) {
    return null;
  }
}

async function loadRevisionAwareWardrobeV2({cacheKey, loadRevision, loadItems}) {
  const key = String(cacheKey || "");
  const revision = await loadRevision();
  if (revision != null && key) {
    const cached = wardrobeCacheByUid.get(key);
    if (cached?.revision === revision && Array.isArray(cached.items)) return cloneItems(cached.items);
  }
  const items = await loadItems();
  if (revision != null && key) {
    wardrobeCacheByUid.set(key, {
      revision,
      items: cloneItems(items),
      byId: new Map(items.map((item) => [item.id, cloneItems([item])[0]])),
    });
  } else if (key) {
    wardrobeCacheByUid.delete(key);
  }
  return cloneItems(items);
}

function createFirestoreWardrobeToolV2({db, uid}) {
  if (!db || !uid) throw new TypeError("wardrobe_v2_firestore_dependencies_required");
  const root = db.collection("users").doc(uid).collection("wardrobe");
  const cacheKey = String(uid);

  async function loadExact(ids) {
    const unique = [...new Set((ids || []).map((id) => text(id, 180)).filter(Boolean))].slice(0, 20);
    if (!unique.length) return [];
    const cached = wardrobeCacheByUid.get(cacheKey);
    if (cached?.byId instanceof Map && unique.every((id) => cached.byId.has(id))) {
      return unique.map((id) => cloneItems([cached.byId.get(id)])[0]);
    }
    const snapshots = typeof db.getAll === "function" ?
      await db.getAll(...unique.map((id) => root.doc(id))) :
      await Promise.all(unique.map((id) => root.doc(id).get()));
    return snapshots.filter((snapshot) => snapshot.exists)
      .map((snapshot) => projectWardrobeItemV2(snapshot.id, snapshot.data() || {}));
  }

  async function readAllFromFirestore() {
    const snapshot = await root.limit(MAX_WARDROBE_ITEMS).get();
    return snapshot.docs.map((doc) => projectWardrobeItemV2(doc.id, doc.data() || {}));
  }

  async function loadAll() {
    return loadRevisionAwareWardrobeV2({
      cacheKey,
      loadRevision: () => readWardrobeRevisionTokenV2(root),
      loadItems: readAllFromFirestore,
    });
  }

  return Object.freeze({
    async retrieve({scope, itemIds = [], category = null}) {
      if (scope === "none") return [];
      if (scope === "current_outfit") return loadExact(itemIds);
      if (scope === "current_outfit_plus_category") {
        const [current, all] = await Promise.all([loadExact(itemIds), loadAll()]);
        const byId = new Map(current.map((item) => [item.id, item]));
        for (const item of all) if (categoryMatches(item, category)) byId.set(item.id, item);
        return [...byId.values()];
      }
      if (scope === "category") {
        const all = await loadAll();
        return all.filter((item) => categoryMatches(item, category));
      }
      if (scope === "full_relevant") return loadAll();
      throw new TypeError(`unsupported_wardrobe_scope:${scope}`);
    },

    async materialize(ids, reasonsById = {}) {
      return (await loadExact(ids)).map((item) => ({
        ...item,
        ...(typeof reasonsById[item.id] === "string" && reasonsById[item.id].trim() ?
          {stylistSelectionReason: reasonsById[item.id].trim()} : {}),
      }));
    },
  });
}

module.exports = {
  HIKING_TECHNICAL_TYPES,
  categoryMatches,
  clearWardrobeCacheV2,
  createFirestoreWardrobeToolV2,
  loadRevisionAwareWardrobeV2,
  projectWardrobeItemV2,
  readWardrobeRevisionTokenV2,
};
