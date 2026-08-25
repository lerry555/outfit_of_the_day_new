"use strict";

/**
 * Production-capable Firebase Storage metadata adapter.
 *
 * Builds TrustedSourceObjectSnapshot/v1 from Storage object metadata only.
 * Does not download bytes, mint signed URLs, or accept client metadata.
 *
 * Not wired into the repository or production Cloud Function entry points in
 * this phase. Injectable storageMetadataClient keeps tests offline.
 */

const {
  SNAPSHOT_CONTRACT,
  decodeTrustedSourceObjectSnapshot,
} = require("./trusted_source_object_snapshot");

const ADAPTER_ID = "TrustedStorageMetadataAdapter";
const ADAPTER_VERSION = "trusted-storage-metadata-adapter-v1";

/**
 * @typedef {object} StorageMetadataClient
 * @property {(path: string) => Promise<object|null>} getMetadata
 *   Returns null/404-equivalent for missing objects, or GCS-like metadata:
 *   generation, metageneration, size, contentType, updated, md5Hash, crc32c,
 *   name.
 */

/**
 * @param {{
 *   uid: string,
 *   itemId: string,
 *   sourceStoragePath: string,
 *   storageMetadataClient: StorageMetadataClient,
 * }} input
 * @returns {Promise<Readonly<object>>} TrustedSourceObjectSnapshot/v1
 */
async function fetchTrustedSourceObjectSnapshot(input) {
  if (input == null || typeof input !== "object" || Array.isArray(input)) {
    fail("storage_adapter_input_not_object");
  }
  if (input.clientMetadata != null || input.clientProvided === true) {
    fail("client_storage_metadata_rejected");
  }

  const uid = requireNonEmpty(input.uid, "uid");
  const itemId = requireNonEmpty(input.itemId, "itemId");
  const sourceStoragePath = requireNonEmpty(
    input.sourceStoragePath, "sourceStoragePath");
  validateOwnedWardrobePath(sourceStoragePath, uid);

  const client = input.storageMetadataClient;
  if (client == null || typeof client.getMetadata !== "function") {
    fail("storage_metadata_client_required");
  }

  let rawMetadata;
  try {
    rawMetadata = await client.getMetadata(sourceStoragePath);
  } catch (error) {
    const code = error && error.code;
    if (code === 404 || code === "404" || code === "storage/object-not-found") {
      fail("source_object_missing");
    }
    fail(`storage_metadata_read_failed:${error && error.message ?
      error.message : "unknown"}`);
  }

  if (rawMetadata == null || rawMetadata.exists === false) {
    fail("source_object_missing");
  }

  const snapshotInput = mapMetadataToSnapshotInput(
    sourceStoragePath, rawMetadata);
  // Decode enforces generation/path/backendVerified invariants.
  const snapshot = decodeTrustedSourceObjectSnapshot(snapshotInput);
  if (!snapshot.exists || snapshot.generation == null) {
    fail("source_object_missing");
  }

  // itemId is accepted for future binding/audit; unused in snapshot v1 body.
  void itemId;
  return snapshot;
}

function mapMetadataToSnapshotInput(sourceStoragePath, metadata) {
  if (metadata == null || typeof metadata !== "object" ||
      Array.isArray(metadata)) {
    fail("storage_metadata_malformed");
  }
  if (metadata.mediaLink != null || metadata.downloadToken != null ||
      metadata.signedUrl != null || metadata.downloadURL != null) {
    fail("storage_download_or_signed_url_rejected");
  }

  const generation = normalizeGeneration(metadata.generation);
  if (generation == null) fail("storage_generation_invalid");

  const sizeRaw = metadata.size ?? metadata.sizeBytes;
  let sizeBytes = null;
  if (sizeRaw != null) {
    const asNumber = typeof sizeRaw === "string" ? Number(sizeRaw) : sizeRaw;
    if (!Number.isInteger(asNumber) || asNumber < 0) {
      fail("storage_size_invalid");
    }
    sizeBytes = asNumber;
  }

  const updatedRaw = metadata.updated ?? metadata.updatedAt ?? metadata.timeUpdated;
  const updatedAt = updatedRaw == null ? null : normalizeUtc(updatedRaw);

  return {
    contractVersion: 1,
    backendVerified: true,
    exists: true,
    sourceStoragePath,
    generation,
    metageneration: metadata.metageneration == null ? null :
      normalizeGeneration(metadata.metageneration),
    sha256: null,
    md5Hash: optionalTrimmed(metadata.md5Hash),
    crc32c: optionalTrimmed(metadata.crc32c),
    sizeBytes,
    contentType: optionalTrimmed(metadata.contentType),
    updatedAt,
  };
}

function validateOwnedWardrobePath(sourceStoragePath, uid) {
  if (!sourceStoragePath.startsWith("wardrobe/") ||
      sourceStoragePath.startsWith("wardrobe_clean/") ||
      sourceStoragePath.startsWith("wardrobe_product/") ||
      sourceStoragePath.includes("://") ||
      sourceStoragePath.includes("\\") ||
      sourceStoragePath.includes("..")) {
    fail("source_storage_path_invalid");
  }
  const expectedPrefix = `wardrobe/${uid}/`;
  if (!sourceStoragePath.startsWith(expectedPrefix)) {
    fail("source_storage_path_uid_mismatch");
  }
  if (sourceStoragePath.length <= expectedPrefix.length) {
    fail("source_storage_path_invalid");
  }
}

function normalizeGeneration(value) {
  if (value == null) return null;
  const text = String(value).trim();
  if (!/^\d+$/.test(text)) return null;
  return text;
}

function normalizeUtc(value) {
  const text = String(value).trim();
  if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(text)) {
    return text;
  }
  const parsed = Date.parse(text);
  if (Number.isNaN(parsed)) fail("storage_updated_invalid");
  return new Date(parsed).toISOString();
}

function optionalTrimmed(value) {
  if (value == null) return null;
  const text = String(value).trim();
  return text || null;
}

/**
 * Fake Storage metadata client for offline tests.
 * @param {Record<string, object|null>} byPath
 */
function createFakeStorageMetadataClient(byPath) {
  return {
    async getMetadata(storagePath) {
      if (!Object.prototype.hasOwnProperty.call(byPath, storagePath)) {
        const error = new Error("not_found");
        error.code = 404;
        throw error;
      }
      return byPath[storagePath];
    },
  };
}

function requireNonEmpty(value, label) {
  if (typeof value !== "string") fail(`${label}_not_string`);
  const text = value.trim();
  if (!text) fail(`${label}_empty`);
  return text;
}

function fail(code) {
  throw new Error(code);
}

module.exports = {
  ADAPTER_ID,
  ADAPTER_VERSION,
  SNAPSHOT_CONTRACT,
  createFakeStorageMetadataClient,
  fetchTrustedSourceObjectSnapshot,
  mapMetadataToSnapshotInput,
  validateOwnedWardrobePath,
};
