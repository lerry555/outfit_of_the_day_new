"use strict";

/**
 * TrustedSourceObjectSnapshot/v1
 *
 * Backend Storage adapter output only. Client-supplied snapshots fail closed.
 * Pure / sync / deterministic. No Firebase I/O.
 */

const SNAPSHOT_CONTRACT = "trusted_source_object_snapshot/v1";
const KNOWN_FIELDS = Object.freeze([
  "contractVersion",
  "sourceStoragePath",
  "generation",
  "metageneration",
  "sha256",
  "md5Hash",
  "crc32c",
  "sizeBytes",
  "contentType",
  "updatedAt",
  "exists",
  "backendVerified",
]);

/**
 * @param {object} raw
 * @returns {Readonly<object>}
 */
function decodeTrustedSourceObjectSnapshot(raw) {
  if (raw == null || typeof raw !== "object" || Array.isArray(raw)) {
    fail("source_snapshot_not_object");
  }
  if (raw.clientProvided === true || raw.forgedByClient === true) {
    fail("client_source_snapshot_rejected");
  }
  for (const key of Object.keys(raw)) {
    if (!KNOWN_FIELDS.includes(key)) fail(`source_snapshot_unknown_field:${key}`);
  }
  if (raw.contractVersion !== 1) fail("source_snapshot_contract_unsupported");
  if (raw.backendVerified !== true) fail("source_snapshot_not_backend_verified");
  if (typeof raw.exists !== "boolean") fail("source_snapshot_exists_invalid");

  const sourceStoragePath = requireNonEmpty(
    raw.sourceStoragePath, "sourceStoragePath");
  if (!sourceStoragePath.startsWith("wardrobe/") ||
      sourceStoragePath.startsWith("wardrobe_clean/") ||
      sourceStoragePath.startsWith("wardrobe_product/") ||
      sourceStoragePath.includes("://") ||
      sourceStoragePath.includes("\\") ||
      sourceStoragePath.includes("..")) {
    fail("source_snapshot_path_invalid");
  }

  if (!raw.exists) {
    return deepFreeze({
      contractVersion: 1,
      sourceStoragePath,
      generation: null,
      metageneration: null,
      sha256: null,
      md5Hash: null,
      crc32c: null,
      sizeBytes: null,
      contentType: null,
      updatedAt: null,
      exists: false,
      backendVerified: true,
    });
  }

  const generation = requireGeneration(raw.generation, "generation");
  return deepFreeze({
    contractVersion: 1,
    sourceStoragePath,
    generation,
    metageneration: raw.metageneration == null ? null :
      requireGeneration(raw.metageneration, "metageneration"),
    sha256: raw.sha256 == null ? null : requireSha256(raw.sha256, "sha256"),
    md5Hash: raw.md5Hash == null ? null :
      requireNonEmpty(raw.md5Hash, "md5Hash"),
    crc32c: raw.crc32c == null ? null :
      requireNonEmpty(raw.crc32c, "crc32c"),
    sizeBytes: raw.sizeBytes == null ? null :
      requireNonNegativeInt(raw.sizeBytes, "sizeBytes"),
    contentType: raw.contentType == null ? null :
      requireNonEmpty(raw.contentType, "contentType"),
    updatedAt: raw.updatedAt == null ? null :
      requireUtc(raw.updatedAt, "updatedAt"),
    exists: true,
    backendVerified: true,
  });
}

function requireGeneration(value, label) {
  const text = requireNonEmpty(value, label);
  if (!/^\d+$/.test(text)) fail(`${label}_invalid`);
  return text;
}

function requireSha256(value, label) {
  const text = requireNonEmpty(value, label).toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(text)) fail(`${label}_invalid`);
  return text;
}

function requireNonEmpty(value, label) {
  if (typeof value !== "string") fail(`${label}_not_string`);
  const text = value.trim();
  if (!text) fail(`${label}_empty`);
  return text;
}

function requireNonNegativeInt(value, label) {
  if (!Number.isInteger(value) || value < 0) fail(`${label}_invalid`);
  return value;
}

function requireUtc(value, label) {
  const text = requireNonEmpty(value, label);
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(text)) {
    fail(`${label}_non_utc_timestamp`);
  }
  return text;
}

function deepFreeze(value) {
  if (value == null || typeof value !== "object") return value;
  if (Object.isFrozen(value)) return value;
  for (const child of Object.values(value)) deepFreeze(child);
  return Object.freeze(value);
}

function fail(code) {
  throw new Error(code);
}

module.exports = {
  SNAPSHOT_CONTRACT,
  decodeTrustedSourceObjectSnapshot,
};
