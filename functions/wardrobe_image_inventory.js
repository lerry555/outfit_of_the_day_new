"use strict";

const crypto = require("crypto");

const DATASET_ID = "current_wardrobe_assets_v1";
const IMAGE_FIELDS = Object.freeze([
  "originalImageUrl",
  "imageUrl",
  "cleanImageUrl",
  "cutoutImageUrl",
  "productImageUrl",
  "thumbnailUrl",
  "photoUrl",
  "image_url",
]);

function buildWardrobeImageInventory(documents, {
  storageMetadataByPath = new Map(),
} = {}) {
  const unique = new Map();
  for (const input of documents || []) {
    const documentId = text(input?.documentId || input?.id);
    if (!documentId || unique.has(documentId)) continue;
    unique.set(documentId, {
      documentId,
      data: isObject(input.data) ? input.data : input,
    });
  }

  const items = [...unique.values()]
    .sort((a, b) => a.documentId.localeCompare(b.documentId))
    .map(({documentId, data}) => inventoryItem(documentId, data,
      storageMetadataByPath));
  const summary = {
    wardrobeItems: items.length,
    usableNormalizedUserPhotos: items.filter((item) =>
      item.preferredImageRole === "normalized_user_photo" &&
      item.datasetStatus !== "missing_image").length,
    derivedOrProductOnly: items.filter((item) =>
      ["background_removed", "normalized_product_image", "product_source_image"]
        .includes(item.preferredImageRole)).length,
    missingImages: items.filter((item) =>
      item.datasetStatus === "missing_image").length,
    privacyReviewRequired: items.filter((item) =>
      item.datasetStatus === "privacy_review_required").length,
  };
  const inventory = {
    inventoryVersion: 1,
    datasetId: DATASET_ID,
    runtimeStatus: "complete_from_local_read_only_input",
    summary,
    items,
  };
  assertCommitSafeInventory(inventory);
  return inventory;
}

function inventoryItem(documentId, data, storageMetadataByPath) {
  const storagePath = text(data.storagePath);
  const availableImages = [];
  for (const field of IMAGE_FIELDS) {
    const value = text(data[field]);
    if (!value) continue;
    const role = classifyImageRole(field, data);
    const actualPath = storagePathForField(field, value, data);
    const metadata = actualPath ? storageMetadataByPath.get(actualPath) : null;
    availableImages.push({
      field,
      role,
      storagePath: actualPath ? redactStoragePath(actualPath) : null,
      exists: metadata?.exists ?? null,
      mimeType: text(metadata?.mimeType),
      sizeBytes: nonNegativeInteger(metadata?.sizeBytes),
      width: positiveInteger(metadata?.width),
      height: positiveInteger(metadata?.height),
      sha256: text(metadata?.sha256),
    });
  }

  const preferred = choosePreferredImage(availableImages);
  const noUsableImage = !preferred || preferred.exists === false;
  return {
    fixtureId: stableFixtureId(documentId),
    categoryKey: text(data.categoryKey || data.category),
    subCategoryKey: text(data.subCategoryKey || data.subCategory),
    availableImages,
    preferredImageField: preferred?.field || null,
    preferredImageRole: preferred?.role || null,
    datasetStatus: noUsableImage ?
      "missing_image" : "privacy_review_required",
    reviewReason: noUsableImage ?
      "no_existing_preferred_image" : "manual_visual_privacy_review_required",
  };
}

function classifyImageRole(field, data) {
  if (field === "cleanImageUrl" || field === "cutoutImageUrl") {
    return "background_removed";
  }
  if (field === "thumbnailUrl") return "thumbnail";
  if (field === "productImageUrl") {
    if (text(data.productStoragePath)) return "normalized_product_image";
    if (text(data.sourceUrl)) return "product_source_image";
    if (same(data.productImageUrl, data.originalImageUrl) &&
        text(data.storagePath)) {
      return "normalized_user_photo";
    }
    return "normalized_product_image";
  }
  if (field === "originalImageUrl" || field === "imageUrl") {
    if (text(data.storagePath) &&
        (!text(data.sourceUrl) || same(data[field], data.originalImageUrl))) {
      return "normalized_user_photo";
    }
    if (text(data.sourceUrl)) return "product_source_image";
    return field === "imageUrl" ? "legacy_unknown" : "unknown_origin";
  }
  return "legacy_unknown";
}

function choosePreferredImage(images) {
  const ranks = new Map([
    ["normalized_user_photo", 0],
    ["unknown_origin", 1],
    ["legacy_unknown", 2],
    ["product_source_image", 3],
    ["background_removed", 4],
    ["normalized_product_image", 5],
    ["thumbnail", 6],
  ]);
  return [...images].sort((a, b) => {
    const existsA = a.exists === false ? 1 : 0;
    const existsB = b.exists === false ? 1 : 0;
    return existsA - existsB ||
      (ranks.get(a.role) ?? 99) - (ranks.get(b.role) ?? 99) ||
      a.field.localeCompare(b.field);
  })[0] || null;
}

function storagePathForField(field, value, data) {
  const explicit = {
    imageUrl: data.storagePath,
    originalImageUrl: data.storagePath,
    cleanImageUrl: data.cleanStoragePath,
    cutoutImageUrl: data.cleanStoragePath,
    productImageUrl: data.productStoragePath,
    thumbnailUrl: data.thumbnailStoragePath,
  }[field];
  return text(explicit) || parseFirebaseStoragePath(value);
}

function parseFirebaseStoragePath(value) {
  const raw = text(value);
  if (!raw) return null;
  if (raw.startsWith("gs://")) {
    const slash = raw.indexOf("/", 5);
    return slash >= 0 ? decodeSafe(raw.slice(slash + 1)) : null;
  }
  const match = raw.match(/firebasestorage\.googleapis\.com\/v0\/b\/[^/]+\/o\/([^?]+)/i);
  if (match) return decodeSafe(match[1]);
  if (!raw.includes("://") &&
      /^(wardrobe|wardrobe_clean|wardrobe_product)\//.test(raw)) {
    return raw;
  }
  return null;
}

function redactStoragePath(value) {
  const parts = String(value).replaceAll("\\", "/").split("/");
  if (parts.length >= 3 &&
      ["wardrobe", "wardrobe_clean", "wardrobe_product"]
        .includes(parts[0])) {
    parts[1] = "{user}";
  }
  return parts.join("/");
}

function stableFixtureId(documentId) {
  const digest = crypto.createHash("sha256")
    .update(`${DATASET_ID}:${documentId}`).digest("hex").slice(0, 16);
  return `wardrobe_fixture_${digest}`;
}

function assertCommitSafeInventory(inventory) {
  const serialized = JSON.stringify(inventory);
  const forbiddenKey = /"(?:uid|email|downloadToken|accessToken|apiKey)"\s*:/i;
  const signedUrl = /[?&](?:token|X-Goog-Signature|X-Goog-Credential)=/i;
  const email = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i;
  const absoluteWindowsPath = /[A-Z]:\\\\Users\\\\/i;
  if (forbiddenKey.test(serialized) || signedUrl.test(serialized) ||
      email.test(serialized) || absoluteWindowsPath.test(serialized)) {
    throw new Error("inventory_contains_sensitive_data");
  }
}

function same(a, b) {
  return text(a) != null && text(a) === text(b);
}
function decodeSafe(value) {
  try {
    return decodeURIComponent(value);
  } catch (_) {
    return null;
  }
}
function text(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed || null;
}
function isObject(value) {
  return value != null && typeof value === "object" && !Array.isArray(value);
}
function nonNegativeInteger(value) {
  const number = Number(value);
  return Number.isInteger(number) && number >= 0 ? number : null;
}
function positiveInteger(value) {
  const number = Number(value);
  return Number.isInteger(number) && number > 0 ? number : null;
}

module.exports = {
  DATASET_ID,
  IMAGE_FIELDS,
  assertCommitSafeInventory,
  buildWardrobeImageInventory,
  choosePreferredImage,
  classifyImageRole,
  parseFirebaseStoragePath,
  redactStoragePath,
  stableFixtureId,
};
