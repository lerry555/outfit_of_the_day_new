"use strict";

/**
 * Resolve and authorize wardrobe Storage paths for clothing analysis.
 * Rejects arbitrary external URLs.
 */

function fail(code, status = 403) {
  const err = new Error(code);
  err.code = code;
  err.httpStatus = status;
  throw err;
}

/**
 * @param {{
 *   uid: string,
 *   storagePath?: string|null,
 *   imageUrl?: string|null,
 *   allowedBuckets?: string[],
 * }} input
 */
function resolveOwnedWardrobeStoragePath(input) {
  const uid = String(input.uid || "").trim();
  if (!uid) fail("auth_uid_required", 401);

  const direct = String(input.storagePath || "").trim();
  if (direct) {
    assertOwnedWardrobePath(direct, uid);
    return direct;
  }

  const imageUrl = String(input.imageUrl || "").trim();
  if (!imageUrl) fail("storage_path_or_image_url_required", 400);

  const parsed = parseFirebaseStoragePathFromUrl(imageUrl, input.allowedBuckets);
  if (!parsed) fail("external_or_unparseable_image_url_rejected", 403);
  assertOwnedWardrobePath(parsed, uid);
  return parsed;
}

function assertOwnedWardrobePath(storagePath, uid) {
  const path = String(storagePath || "").trim().replace(/^\/+/, "");
  if (!path.startsWith("wardrobe/")) fail("storage_path_not_wardrobe", 403);
  if (path.includes("..") || path.includes("://")) fail("storage_path_invalid", 403);
  const parts = path.split("/");
  // wardrobe/{uid}/file...
  if (parts.length < 3) fail("storage_path_incomplete", 403);
  if (parts[1] !== uid) fail("storage_path_uid_mismatch", 403);
  if (!parts[2]) fail("storage_path_incomplete", 403);
}

/**
 * @param {string} imageUrl
 * @param {string[]} [allowedBuckets]
 * @returns {string|null} storage path
 */
function parseFirebaseStoragePathFromUrl(imageUrl, allowedBuckets) {
  let url;
  try {
    url = new URL(imageUrl);
  } catch (_) {
    return null;
  }

  // https://firebasestorage.googleapis.com/v0/b/{bucket}/o/{encodedPath}?...
  if (url.hostname === "firebasestorage.googleapis.com") {
    const m = url.pathname.match(/^\/v0\/b\/([^/]+)\/o\/(.+)$/);
    if (!m) return null;
    const bucket = decodeURIComponent(m[1]);
    if (Array.isArray(allowedBuckets) && allowedBuckets.length &&
        !allowedBuckets.includes(bucket)) {
      return null;
    }
    return decodeURIComponent(m[2]);
  }

  // https://storage.googleapis.com/{bucket}/wardrobe/...
  if (url.hostname === "storage.googleapis.com") {
    const parts = url.pathname.replace(/^\/+/, "").split("/");
    if (parts.length < 2) return null;
    const bucket = parts[0];
    if (Array.isArray(allowedBuckets) && allowedBuckets.length &&
        !allowedBuckets.includes(bucket)) {
      return null;
    }
    return parts.slice(1).join("/");
  }

  return null;
}

module.exports = {
  resolveOwnedWardrobeStoragePath,
  assertOwnedWardrobePath,
  parseFirebaseStoragePathFromUrl,
};
