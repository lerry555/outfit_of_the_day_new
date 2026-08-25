"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const sharp = require("sharp");

const ASSET_DATASET = "current_pipeline_assets_v1";
const ALLOWED_LICENSES = new Set([
  "user_owned_test_fixture",
  "generated_for_project",
  "public_domain",
]);
const MULTI_PHOTO_IDS = new Set([
  "complementary_multi_view",
  "conflicting_multi_view",
]);

async function validateAssetDataset(manifest, {
  rootDirectory,
  scenarioIds,
}) {
  const errors = [];
  const scenarios = [];
  if (!isObject(manifest) || manifest.manifestVersion !== 1 ||
      manifest.assetDataset !== ASSET_DATASET ||
      !Array.isArray(manifest.scenarios)) {
    return {ok: false, errors: ["asset_manifest.invalid"], scenarios};
  }
  const known = new Set(scenarioIds);
  const ids = new Set();
  for (const scenario of manifest.scenarios) {
    const scenarioErrors = [];
    if (!isObject(scenario) || !text(scenario.id) || ids.has(scenario.id)) {
      errors.push("asset_manifest.scenario_id.invalid");
      continue;
    }
    ids.add(scenario.id);
    if (!known.has(scenario.id)) {
      errors.push(`asset_manifest.unknown_scenario:${scenario.id}`);
    }
    const views = Array.isArray(scenario.views) ? scenario.views : [];
    const ready = scenario.status === "ready_asset";
    if (!ready) {
      scenarios.push({...scenario, effectiveStatus: "missing_asset",
        errors: []});
      continue;
    }
    if (views.length < Number(scenario.requiredViewCount || 1)) {
      scenarioErrors.push("required_views_missing");
    }
    if (MULTI_PHOTO_IDS.has(scenario.id) && views.length < 2) {
      scenarioErrors.push("multi_photo_requires_two_views");
    }
    const viewIds = new Set();
    for (const view of views) {
      await validateView(view, {rootDirectory, errors: scenarioErrors});
      if (!text(view.viewId) || viewIds.has(view.viewId)) {
        scenarioErrors.push("view_id_duplicate_or_invalid");
      } else {
        viewIds.add(view.viewId);
      }
    }
    validateScenarioPolicy(scenario, scenarioErrors);
    scenarios.push({
      ...scenario,
      effectiveStatus: scenarioErrors.length ? "invalid_asset" : "ready_asset",
      errors: [...new Set(scenarioErrors)].sort(),
    });
    errors.push(...scenarioErrors.map((item) => `${scenario.id}:${item}`));
  }
  for (const id of known) {
    if (!ids.has(id)) errors.push(`asset_manifest.scenario_missing:${id}`);
  }
  return {
    ok: errors.length === 0,
    errors: [...new Set(errors)].sort(),
    scenarios,
  };
}

async function validateView(view, {rootDirectory, errors}) {
  if (!isObject(view) || !text(view.assetPath) ||
      path.isAbsolute(view.assetPath) || view.assetPath.includes("..") ||
      view.assetPath.includes("://")) {
    errors.push("asset_path_invalid");
    return;
  }
  const absolute = path.resolve(rootDirectory, view.assetPath);
  if (!fs.existsSync(absolute)) {
    errors.push("asset_missing");
    return;
  }
  if (!/^[a-f0-9]{64}$/.test(String(view.assetSha256 || "")) ||
      sha256File(absolute) !== view.assetSha256) {
    errors.push("asset_sha256_mismatch");
  }
  const expected = mimeFromExtension(view.assetPath);
  if (!expected || expected !== view.mimeType ||
      sniffMime(absolute) !== expected) {
    errors.push("asset_mime_mismatch");
  }
  const stat = fs.statSync(absolute);
  if (stat.size > 4 * 1024 * 1024) errors.push("asset_file_too_large");
  try {
    const metadata = await sharp(absolute).metadata();
    if (!metadata.width || !metadata.height ||
        metadata.width > 2048 || metadata.height > 2048) {
      errors.push("asset_dimensions_invalid");
    }
    if (view.width !== metadata.width || view.height !== metadata.height) {
      errors.push("asset_dimensions_manifest_mismatch");
    }
    if (metadata.exif || metadata.iptc || metadata.xmp) {
      errors.push("asset_private_metadata_present");
    }
  } catch (_) {
    errors.push("asset_decode_failed");
  }
  if (!["original", "derived"].includes(view.sourceType)) {
    errors.push("source_type_invalid");
  }
  if (view.sourceType === "derived" &&
      (!text(view.sourceAsset) || !isObject(view.derivation) ||
       !text(view.derivation.operation) ||
       !isObject(view.derivation.parameters))) {
    errors.push("derived_provenance_invalid");
  }
}

function validateScenarioPolicy(scenario, errors) {
  const license = scenario.license;
  if (!isObject(license) || !ALLOWED_LICENSES.has(license.type)) {
    errors.push("license_type_invalid");
  } else if (license.redistributionAllowed !== true) {
    errors.push("redistribution_not_allowed");
  }
  if (scenario.privacyReviewed !== true) {
    errors.push("privacy_review_required");
  }
  if (!text(scenario.provenance) ||
      !Number.isSafeInteger(scenario.scenarioVersion)) {
    errors.push("scenario_provenance_or_version_invalid");
  }
  if (scenario.id === "complementary_multi_view" &&
      scenario.multiPhoto?.relationship !== "same_source_garment") {
    errors.push("complementary_source_relationship_invalid");
  }
  if (MULTI_PHOTO_IDS.has(scenario.id) &&
      (!Array.isArray(scenario.multiPhoto?.ordering) ||
       scenario.multiPhoto.ordering.length !== scenario.views.length ||
       scenario.multiPhoto.ordering.some(
         (viewId, index) => viewId !== scenario.views[index]?.viewId))) {
    errors.push("multi_photo_ordering_invalid");
  }
  if (scenario.id === "conflicting_multi_view" &&
      !text(scenario.multiPhoto?.conflictContract)) {
    errors.push("conflict_contract_required");
  }
  if (scenario.id === "cross_family_ambiguity" &&
      (!Array.isArray(scenario.ambiguity?.plausibleFamilies) ||
       scenario.ambiguity.plausibleFamilies.length < 2)) {
    errors.push("ambiguity_contract_required");
  }
  if (scenario.id === "non_wardrobe_object" &&
      !["generated_for_project", "user_owned_test_fixture", "public_domain"]
        .includes(scenario.license?.type)) {
    errors.push("non_wardrobe_source_unapproved");
  }
}

async function buildDerivedAsset({
  sourcePath,
  outputPath,
  operation,
  parameters,
}) {
  const before = sha256File(sourcePath);
  let pipeline = sharp(sourcePath).rotate();
  if (operation === "crop") {
    pipeline = pipeline.extract({
      left: integer(parameters.left),
      top: integer(parameters.top),
      width: integer(parameters.width),
      height: integer(parameters.height),
    });
  } else if (operation === "blur") {
    pipeline = pipeline.blur(Number(parameters.sigma));
  } else if (operation === "dark") {
    pipeline = pipeline.modulate({
      brightness: Number(parameters.brightness),
      saturation: Number(parameters.saturation),
    }).linear(Number(parameters.contrast), Number(parameters.offset));
  } else {
    throw new Error(`unsupported_derivation:${operation}`);
  }
  fs.mkdirSync(path.dirname(outputPath), {recursive: true});
  const extension = path.extname(outputPath).toLowerCase();
  if (extension === ".png") {
    await pipeline.png({compressionLevel: 9, adaptiveFiltering: false})
      .toFile(outputPath);
  } else if (extension === ".jpg" || extension === ".jpeg") {
    await pipeline.jpeg({quality: 86, chromaSubsampling: "4:4:4"})
      .toFile(outputPath);
  } else {
    throw new Error("unsupported_output_extension");
  }
  if (sha256File(sourcePath) !== before) {
    throw new Error("source_asset_mutated");
  }
  return sha256File(outputPath);
}

function synchronizeCaptureManifest({
  captureManifest,
  validation,
}) {
  const statusById = new Map(validation.scenarios
    .map((item) => [item.id, item]));
  return {
    ...structuredClone(captureManifest),
    fixtures: captureManifest.fixtures.map((fixture) => {
      const asset = statusById.get(fixture.id);
      if (!asset || asset.effectiveStatus !== "ready_asset") {
        return {...fixture, captureStatus: "missing_asset", views: []};
      }
      return {
        id: fixture.id,
        captureStatus: "pending_capture",
        multiViewSubjectBinding: asset.multiPhoto
          ? bindingFromRelationship(asset.multiPhoto.relationship)
          : bindingFromRelationship(null),
        views: asset.views.map((view) => ({
          viewId: view.viewId,
          assetPath: view.assetPath,
          assetSha256: view.assetSha256,
          mimeType: view.mimeType,
        })),
      };
    }),
  };
}

function bindingFromRelationship(relationship) {
  if (relationship === "same_source_garment") {
    return {
      contractVersion: 1,
      physicalIdentityClaim: "same_physical_item",
      source: "asset_manifest_relationship",
      reasonCodes: ["mapped_from_same_source_garment"],
    };
  }
  if (relationship === "different_garments_intentional_conflict") {
    return {
      contractVersion: 1,
      physicalIdentityClaim: "different_physical_items",
      source: "asset_manifest_relationship",
      reasonCodes: ["mapped_from_different_garments_intentional_conflict"],
    };
  }
  return {
    contractVersion: 1,
    physicalIdentityClaim: "undeclared",
    source: "unknown",
    reasonCodes: ["missing_asset_manifest_relationship"],
  };
}

function datasetSummary(validation, rootDirectory) {
  const ready = validation.scenarios
    .filter((item) => item.effectiveStatus === "ready_asset");
  const views = ready.flatMap((item) => item.views);
  const uniquePaths = [...new Set(views.map((item) => item.assetPath))];
  return {
    scenarios: validation.scenarios.length,
    readyScenarios: ready.length,
    missingScenarios: validation.scenarios
      .filter((item) => item.effectiveStatus === "missing_asset").length,
    invalidScenarios: validation.scenarios
      .filter((item) => item.effectiveStatus === "invalid_asset").length,
    originalAssets: views.filter((item) => item.sourceType === "original").length,
    derivedAssets: views.filter((item) => item.sourceType === "derived").length,
    views: views.length,
    multiPhotoViews: ready.filter((item) => MULTI_PHOTO_IDS.has(item.id))
      .reduce((sum, item) => sum + item.views.length, 0),
    totalBytes: uniquePaths.reduce((sum, item) => {
      const absolute = path.resolve(rootDirectory, item);
      return sum + (fs.existsSync(absolute) ? fs.statSync(absolute).size : 0);
    }, 0),
  };
}

function sha256File(filePath) {
  return crypto.createHash("sha256").update(fs.readFileSync(filePath))
    .digest("hex");
}
function mimeFromExtension(value) {
  const extension = path.extname(value).toLowerCase();
  if (extension === ".jpg" || extension === ".jpeg") return "image/jpeg";
  if (extension === ".png") return "image/png";
  return null;
}
function sniffMime(filePath) {
  const bytes = fs.readFileSync(filePath).subarray(0, 8);
  if (bytes[0] === 0xff && bytes[1] === 0xd8) return "image/jpeg";
  if (bytes.equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) {
    return "image/png";
  }
  return null;
}
function integer(value) {
  if (!Number.isInteger(value) || value < 0) {
    throw new Error("derivation_integer_invalid");
  }
  return value;
}
function isObject(value) {
  return value != null && typeof value === "object" && !Array.isArray(value);
}
function text(value) {
  return typeof value === "string" && value.trim().length > 0;
}

module.exports = {
  ASSET_DATASET,
  bindingFromRelationship,
  buildDerivedAsset,
  datasetSummary,
  sha256File,
  synchronizeCaptureManifest,
  validateAssetDataset,
};
