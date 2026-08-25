"use strict";

/**
 * Admin Storage metadata client boundary (injectable).
 * Metadata-only — no download, no signed URL.
 */

const CLIENT_ID = "WardrobeAdminStorageMetadataClient";
const CLIENT_VERSION = "wardrobe-admin-storage-metadata-client-v1";

/**
 * @param {{
 *   getMetadata?: (path: string) => Promise<object|null>,
 *   bucketName?: string,
 * }} options
 */
function createAdminStorageMetadataClient(options = {}) {
  const getMetadata = options.getMetadata;
  if (typeof getMetadata !== "function") {
    fail("admin_storage_get_metadata_required");
  }
  return Object.freeze({
    clientId: CLIENT_ID,
    clientVersion: CLIENT_VERSION,
    bucketName: options.bucketName || null,
    async getMetadata(storagePath) {
      if (typeof storagePath !== "string" || !storagePath.trim()) {
        fail("storage_path_empty");
      }
      if (storagePath.includes("://") || storagePath.includes("..")) {
        fail("storage_path_invalid");
      }
      const metadata = await getMetadata(storagePath.trim());
      if (metadata == null) return null;
      // `mediaLink` is a standard provider metadata field returned by the
      // trusted Google Cloud Storage Admin SDK. It is not a signed URL and is
      // deliberately omitted from the normalized metadata-only result below.
      if (metadata.signedUrl != null || metadata.downloadURL != null ||
          metadata.downloadToken != null) {
        fail("storage_download_or_signed_url_rejected");
      }
      if (metadata._downloadedBytes != null || metadata.buffer != null) {
        fail("storage_media_download_rejected");
      }
      return {
        generation: metadata.generation,
        metageneration: metadata.metageneration,
        size: metadata.size,
        contentType: metadata.contentType,
        updated: metadata.updated || metadata.timeUpdated,
        md5Hash: metadata.md5Hash,
        crc32c: metadata.crc32c,
        name: metadata.name,
      };
    },
  });
}

/**
 * Fake Admin metadata source for offline tests.
 * @param {Record<string, object|null>} byPath
 */
function createFakeAdminStorageMetadataSource(byPath) {
  return async function getMetadata(storagePath) {
    if (!Object.prototype.hasOwnProperty.call(byPath, storagePath)) {
      return null;
    }
    return byPath[storagePath];
  };
}

function fail(code) {
  throw new Error(code);
}

module.exports = {
  CLIENT_ID,
  CLIENT_VERSION,
  createAdminStorageMetadataClient,
  createFakeAdminStorageMetadataSource,
};
