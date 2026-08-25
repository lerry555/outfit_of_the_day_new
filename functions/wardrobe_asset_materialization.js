"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const sharp = require("sharp");
const {
  redactStoragePath,
  stableFixtureId,
} = require("./wardrobe_image_inventory");

const DEFAULT_MAX_ASSETS = 20;
const DEFAULT_MAX_TOTAL_BYTES = 100 * 1024 * 1024;
const MAX_OBJECT_BYTES = 4 * 1024 * 1024;
const ALLOWED_MIME = new Set(["image/jpeg", "image/png"]);

function buildCandidatePlan(documents, metadataObjects, {
  maxAssets = DEFAULT_MAX_ASSETS,
  maxTotalBytes = DEFAULT_MAX_TOTAL_BYTES,
} = {}) {
  validateLimits(maxAssets, maxTotalBytes);
  const metadataByPath = new Map((metadataObjects || [])
    .map((item) => [item.storagePath, item]));
  const eligible = [];
  for (const document of documents || []) {
    const storagePath = text(document.fields?.storagePath);
    if (!storagePath) continue;
    const redactedStoragePath = redactStoragePath(storagePath);
    const metadata = metadataByPath.get(redactedStoragePath);
    if (!metadata?.exists || !ALLOWED_MIME.has(metadata.contentType) ||
        !Number.isSafeInteger(metadata.sizeBytes) ||
        metadata.sizeBytes < 1 || metadata.sizeBytes > MAX_OBJECT_BYTES) {
      continue;
    }
    eligible.push({
      fixtureId: stableFixtureId(document.documentId),
      documentId: document.documentId,
      storagePath,
      redactedStoragePath,
      contentType: metadata.contentType,
      sizeBytes: metadata.sizeBytes,
      categoryKey: text(document.fields.categoryKey),
      subCategoryKey: text(document.fields.subCategoryKey),
      sourceRole: "normalized_user_upload",
      candidateScenarioRoles: scenarioRoles(document.fields),
    });
  }
  eligible.sort((a, b) =>
    taxonomyKey(a).localeCompare(taxonomyKey(b)) ||
    a.fixtureId.localeCompare(b.fixtureId));

  const selected = [];
  const deferred = [];
  const seenTaxonomy = new Set();
  let totalBytes = 0;
  for (const candidate of eligible) {
    const key = taxonomyKey(candidate);
    if (seenTaxonomy.has(key)) {
      deferred.push(candidate);
      continue;
    }
    if (canAdd(candidate, selected, totalBytes, maxAssets, maxTotalBytes)) {
      selected.push(candidate);
      seenTaxonomy.add(key);
      totalBytes += candidate.sizeBytes;
    }
  }
  for (const candidate of deferred) {
    if (!canAdd(candidate, selected, totalBytes, maxAssets, maxTotalBytes)) {
      continue;
    }
    selected.push(candidate);
    totalBytes += candidate.sizeBytes;
  }
  return {
    eligibleCount: eligible.length,
    selected,
    selectedBytes: totalBytes,
    additionalAssetsRequired: Math.max(0,
      Math.min(eligible.length, maxAssets) - selected.length),
  };
}

async function downloadCandidatePlan({
  plan,
  bucket,
  accessToken,
  outputDirectory,
  fetchImpl = fetch,
}) {
  fs.mkdirSync(outputDirectory, {recursive: true});
  const index = [];
  let downloadedBytes = 0;
  for (let i = 0; i < plan.selected.length; i++) {
    const candidate = plan.selected[i];
    const extension = candidate.contentType === "image/png" ? ".png" : ".jpg";
    const anonymizedAssetId =
      `wardrobe_asset_${String(i + 1).padStart(3, "0")}`;
    const filePath = path.join(outputDirectory,
      `${anonymizedAssetId}${extension}`);
    const endpoint =
      `https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(bucket)}` +
      `/o/${encodeURIComponent(candidate.storagePath)}?alt=media`;
    const response = await fetchImpl(endpoint, {
      method: "GET",
      headers: {Authorization: `Bearer ${accessToken}`},
    });
    if (!response.ok) {
      throw new Error(`storage_media_read_failed:${response.status}`);
    }
    const bytes = Buffer.from(await response.arrayBuffer());
    if (bytes.length !== candidate.sizeBytes ||
        bytes.length > MAX_OBJECT_BYTES) {
      throw new Error("downloaded_size_mismatch");
    }
    const sniffed = sniffMime(bytes);
    if (sniffed !== candidate.contentType) {
      throw new Error("downloaded_mime_mismatch");
    }
    const metadata = await sharp(bytes).metadata();
    fs.writeFileSync(filePath, bytes, {flag: "wx"});
    downloadedBytes += bytes.length;
    index.push({
      anonymizedAssetId,
      relativePath: path.basename(filePath),
      wardrobeFixtureId: candidate.fixtureId,
      redactedStoragePath: candidate.redactedStoragePath,
      sha256: sha256(bytes),
      mimeType: sniffed,
      width: metadata.width || null,
      height: metadata.height || null,
      byteSize: bytes.length,
      sourceRole: candidate.sourceRole,
      candidateScenarioRoles: candidate.candidateScenarioRoles,
      privacyReviewState: hasSensitiveMetadata(metadata) ?
        "sensitive_metadata_rejected" : "manual_privacy_review_required",
      provenanceState: "approved_user_owned_test_source",
      metadataClean: !hasPrivateMetadata(metadata),
    });
  }
  return {index, downloadedBytes};
}

async function normalizeApprovedCandidate({
  sourcePath,
  outputPath,
  review,
}) {
  if (review?.privacyReviewed !== true) {
    throw new Error("privacy_review_required");
  }
  if (review?.provenanceApproved !== true) {
    throw new Error("provenance_review_required");
  }
  if (review?.redistributionAllowed !== true) {
    throw new Error("redistribution_approval_required");
  }
  if (review?.sourceRole !== "normalized_user_upload") {
    throw new Error("source_role_not_automatically_eligible");
  }
  const before = sha256(fs.readFileSync(sourcePath));
  fs.mkdirSync(path.dirname(outputPath), {recursive: true});
  await sharp(sourcePath)
    .rotate()
    .resize(2048, 2048, {fit: "inside", withoutEnlargement: true})
    .jpeg({quality: 86, chromaSubsampling: "4:4:4"})
    .toFile(outputPath);
  if (sha256(fs.readFileSync(sourcePath)) !== before) {
    throw new Error("source_asset_mutated");
  }
  const metadata = await sharp(outputPath).metadata();
  if (hasPrivateMetadata(metadata)) {
    throw new Error("normalized_private_metadata_present");
  }
  return {
    sha256: sha256(fs.readFileSync(outputPath)),
    mimeType: "image/jpeg",
    width: metadata.width,
    height: metadata.height,
    byteSize: fs.statSync(outputPath).size,
    metadataClean: true,
  };
}

function publicPlan(plan) {
  return {
    eligibleCount: plan.eligibleCount,
    selectedBytes: plan.selectedBytes,
    additionalAssetsRequired: plan.additionalAssetsRequired,
    selected: plan.selected.map((item) => ({
      wardrobeFixtureId: item.fixtureId,
      redactedStoragePath: item.redactedStoragePath,
      sourceRole: item.sourceRole,
      sizeBytes: item.sizeBytes,
      contentType: item.contentType,
      candidateScenarioRoles: item.candidateScenarioRoles,
    })),
  };
}

function scenarioRoles(fields) {
  const combined =
    `${text(fields.categoryKey) || ""} ${text(fields.subCategoryKey) || ""}`
      .toLowerCase();
  const roles = [
    "front_only_garment_review",
    "cropped_upper",
    "cropped_lower",
    "fabric_detail_only",
    "dark_low_contrast",
    "blurred_item",
    "conflicting_multi_view_candidate",
  ];
  if (/shoe|footwear|sneaker|obuv|tenisk/.test(combined)) {
    roles.push("shoe_without_outsole_review");
  }
  return roles.sort();
}

function hasPrivateMetadata(metadata) {
  return Boolean(metadata.exif || metadata.iptc || metadata.xmp);
}
function hasSensitiveMetadata(metadata) {
  if (metadata.iptc || metadata.xmp) return true;
  const tags = exifIfd0Tags(metadata.exif);
  return [
    0x010e, // ImageDescription
    0x010f, // Make
    0x0110, // Model
    0x013b, // Artist
    0x8298, // Copyright
    0x8825, // GPSInfo IFD pointer
  ].some((tag) => tags.has(tag));
}
function exifIfd0Tags(exif) {
  const result = new Set();
  if (!Buffer.isBuffer(exif) || exif.length < 14 ||
      exif.subarray(0, 6).toString("binary") !== "Exif\u0000\u0000") {
    return result;
  }
  const start = 6;
  const little = exif.subarray(start, start + 2).toString("ascii") === "II";
  const read16 = (offset) => little ?
    exif.readUInt16LE(offset) : exif.readUInt16BE(offset);
  const read32 = (offset) => little ?
    exif.readUInt32LE(offset) : exif.readUInt32BE(offset);
  try {
    const ifd = start + read32(start + 4);
    const count = read16(ifd);
    for (let index = 0; index < count; index++) {
      result.add(read16(ifd + 2 + (index * 12)));
    }
  } catch (_) {
    return new Set([0x8825]);
  }
  return result;
}
function sniffMime(bytes) {
  if (bytes[0] === 0xff && bytes[1] === 0xd8) return "image/jpeg";
  if (bytes.subarray(0, 8)
    .equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) {
    return "image/png";
  }
  return null;
}
function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}
function taxonomyKey(item) {
  return `${item.categoryKey || "~"}|${item.subCategoryKey || "~"}`;
}
function canAdd(candidate, selected, totalBytes, maxAssets, maxTotalBytes) {
  return selected.length < maxAssets &&
    totalBytes + candidate.sizeBytes <= maxTotalBytes;
}
function validateLimits(maxAssets, maxTotalBytes) {
  if (!Number.isInteger(maxAssets) || maxAssets < 1 ||
      maxAssets > DEFAULT_MAX_ASSETS) {
    throw new Error("max_assets_out_of_range");
  }
  if (!Number.isSafeInteger(maxTotalBytes) || maxTotalBytes < 1 ||
      maxTotalBytes > DEFAULT_MAX_TOTAL_BYTES) {
    throw new Error("max_total_bytes_out_of_range");
  }
}
function text(value) {
  if (typeof value !== "string") return null;
  return value.trim() || null;
}

module.exports = {
  ALLOWED_MIME,
  DEFAULT_MAX_ASSETS,
  DEFAULT_MAX_TOTAL_BYTES,
  MAX_OBJECT_BYTES,
  buildCandidatePlan,
  downloadCandidatePlan,
  hasPrivateMetadata,
  hasSensitiveMetadata,
  normalizeApprovedCandidate,
  publicPlan,
  scenarioRoles,
  sniffMime,
};
