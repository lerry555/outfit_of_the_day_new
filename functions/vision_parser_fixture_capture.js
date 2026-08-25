"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const {
  MODEL_VERSION,
  SCHEMA_VERSION,
} = require("./vision_v2_shadow");

const CAPTURE_CONTRACT_VERSION = 1;
const CAPTURE_DATASET = "current_pipeline_capture_v1";
const PROMPT_VERSION = "vision_v2_prompt_schema_10_1";
const PIPELINE_VERSION = "vision_v2_phase_4_9";
const PARSER_VERSION = "vision_v2_parser_v1";
const FORBIDDEN_KEYS = new Set([
  "authorization",
  "apiKey",
  "token",
  "uid",
  "email",
  "signedUrl",
  "resolvedProfile",
  "knowledgeBaseEvidence",
  "machineEvidence",
  "userCorrections",
]);

function stableAnalysisId(fixtureId, viewId) {
  const suffix = viewId ? `:${viewId}` : "";
  return `fixture:${CAPTURE_DATASET}:${fixtureId}${suffix}`;
}

function sha256File(filePath) {
  return crypto.createHash("sha256").update(fs.readFileSync(filePath))
    .digest("hex");
}

function validateCaptureManifest(manifest, {rootDirectory}) {
  const errors = [];
  if (!isObject(manifest) || manifest.manifestVersion !== 1 ||
      manifest.captureDataset !== CAPTURE_DATASET ||
      !Array.isArray(manifest.fixtures)) {
    return ["capture_manifest.invalid"];
  }
  const ids = new Set();
  for (const item of manifest.fixtures) {
    if (!isObject(item) || !text(item.id) || ids.has(item.id)) {
      errors.push("capture_manifest.fixture_id.invalid");
      continue;
    }
    ids.add(item.id);
    if (!Array.isArray(item.views) || item.views.length === 0) {
      if (item.captureStatus !== "missing_asset") {
        errors.push(`capture_manifest.views.required:${item.id}`);
      }
      continue;
    }
    for (const view of item.views) {
      if (!isObject(view) || !text(view.viewId) ||
          !text(view.assetPath) || !hexSha256(view.assetSha256)) {
        errors.push(`capture_manifest.view.invalid:${item.id}`);
        continue;
      }
      if (path.isAbsolute(view.assetPath) ||
          view.assetPath.includes("..")) {
        errors.push(`capture_manifest.asset_path.unsafe:${item.id}`);
      }
      const absolute = path.resolve(rootDirectory, view.assetPath);
      if (fs.existsSync(absolute) &&
          sha256File(absolute) !== view.assetSha256) {
        errors.push(`capture_manifest.asset_hash.mismatch:${item.id}`);
      }
    }
  }
  return errors.sort();
}

function preflightCaptureManifest(manifest, {rootDirectory}) {
  const structuralErrors = validateCaptureManifest(manifest, {rootDirectory});
  if (structuralErrors.length) {
    return {ok: false, errors: structuralErrors, fixtures: []};
  }
  const fixtures = manifest.fixtures.map((item) => {
    if (!item.views.length) {
      return {...item, effectiveStatus: "missing_asset",
        reasonCode: "asset_not_committed"};
    }
    for (const view of item.views) {
      const absolute = path.resolve(rootDirectory, view.assetPath);
      if (!fs.existsSync(absolute)) {
        return {...item, effectiveStatus: "missing_asset",
          reasonCode: `asset_missing:${view.viewId}`};
      }
      if (sha256File(absolute) !== view.assetSha256) {
        return {...item, effectiveStatus: "invalid",
          reasonCode: `asset_hash_mismatch:${view.viewId}`};
      }
    }
    if (item.captureStatus === "captured" &&
        item.parserFixture &&
        fs.existsSync(path.resolve(rootDirectory, item.parserFixture))) {
      return {...item, effectiveStatus: "captured", reasonCode: null};
    }
    return {...item, effectiveStatus: "pending_capture",
      reasonCode: "live_capture_not_executed"};
  });
  return {ok: true, errors: [], fixtures};
}

function buildParserFixture({
  fixture,
  parsedResponses,
  capturedAt,
}) {
  if (!fixture || !Array.isArray(fixture.views) ||
      parsedResponses.length !== fixture.views.length) {
    throw new Error("parser_fixture_view_count_mismatch");
  }
  const views = parsedResponses.map((response, index) => {
    const view = fixture.views[index];
    return {
      viewId: view.viewId,
      assetPath: view.assetPath,
      assetSha256: view.assetSha256,
      mimeType: view.mimeType,
      response: {
        ...structuredClone(response),
        analysisId: stableAnalysisId(fixture.id, view.viewId),
        sourceReference: `fixture://${fixture.id}/${view.viewId}`,
        // Capture time is retained separately. Qualification receives a fixed
        // provenance time so replay cannot change evidence or snapshots.
        observedAt: "2000-01-01T00:00:00.000Z",
      },
    };
  });
  const result = {
    fixtureContractVersion: CAPTURE_CONTRACT_VERSION,
    captureDataset: CAPTURE_DATASET,
    fixtureId: fixture.id,
    multiViewSubjectBinding: resolveMultiViewSubjectBinding(fixture),
    captureProvenance: {
      capturedAt,
      modelIdentifier: MODEL_VERSION,
      promptVersion: PROMPT_VERSION,
      pipelineVersion: PIPELINE_VERSION,
      visionSchemaVersion: SCHEMA_VERSION,
      parserVersion: PARSER_VERSION,
    },
    views,
  };
  const errors = validateParserFixture(result);
  if (errors.length) throw new Error(`parser_fixture_invalid:${errors.join(",")}`);
  return result;
}

function bindingFromAssetRelationship(relationship) {
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

function resolveMultiViewSubjectBinding(fixture) {
  if (isObject(fixture.multiViewSubjectBinding)) {
    return structuredClone(fixture.multiViewSubjectBinding);
  }
  if (isObject(fixture.multiPhoto) && text(fixture.multiPhoto.relationship)) {
    return bindingFromAssetRelationship(fixture.multiPhoto.relationship);
  }
  return bindingFromAssetRelationship(null);
}

function validateMultiViewSubjectBinding(value, errors) {
  if (value == null) return;
  if (!isObject(value)) {
    errors.push("parser_fixture.multi_view_subject_binding.invalid");
    return;
  }
  if (value.contractVersion !== 1) {
    errors.push("parser_fixture.multi_view_subject_binding.version_invalid");
  }
  if (!["same_physical_item", "different_physical_items", "undeclared"]
      .includes(value.physicalIdentityClaim)) {
    errors.push("parser_fixture.multi_view_subject_binding.claim_invalid");
  }
  if (!["user_item_upload_intent", "capture_declaration",
      "asset_manifest_relationship", "unknown"].includes(value.source)) {
    errors.push("parser_fixture.multi_view_subject_binding.source_invalid");
  }
  if (value.reasonCodes != null && (!Array.isArray(value.reasonCodes) ||
      value.reasonCodes.some((item) => typeof item !== "string"))) {
    errors.push("parser_fixture.multi_view_subject_binding.reason_codes_invalid");
  }
}

function validateParserFixture(value) {
  const errors = [];
  if (!isObject(value) ||
      value.fixtureContractVersion !== CAPTURE_CONTRACT_VERSION ||
      value.captureDataset !== CAPTURE_DATASET ||
      !text(value.fixtureId)) {
    return ["parser_fixture.root.invalid"];
  }
  scanForbidden(value, "$", errors);
  validateMultiViewSubjectBinding(value.multiViewSubjectBinding, errors);
  const provenance = value.captureProvenance;
  if (!isObject(provenance) || !text(provenance.capturedAt) ||
      !text(provenance.modelIdentifier) ||
      !text(provenance.promptVersion) ||
      !text(provenance.pipelineVersion) ||
      !Number.isInteger(provenance.visionSchemaVersion) ||
      !text(provenance.parserVersion)) {
    errors.push("parser_fixture.provenance.invalid");
  }
  if (!Array.isArray(value.views) || value.views.length === 0) {
    errors.push("parser_fixture.views.invalid");
  } else {
    for (const view of value.views) {
      if (!isObject(view) || !text(view.viewId) ||
          !text(view.assetPath) || path.isAbsolute(view.assetPath) ||
          !hexSha256(view.assetSha256) || !text(view.mimeType) ||
          !isObject(view.response)) {
        errors.push("parser_fixture.view.invalid");
        continue;
      }
      if (view.response.schemaVersion !== SCHEMA_VERSION ||
          !text(view.response.analysisId) ||
          !text(view.response.modelVersion) ||
          !isObject(view.response.quality) ||
          !isObject(view.response.subjectAssessment) ||
          !isObject(view.response.observations) ||
          !Array.isArray(view.response.identityCandidates) ||
          !Array.isArray(view.response.validationErrors)) {
        errors.push(`parser_fixture.response.invalid:${view.viewId}`);
      }
    }
  }
  return [...new Set(errors)].sort();
}

function serializeParserFixture(value) {
  const errors = validateParserFixture(value);
  if (errors.length) throw new Error(`parser_fixture_invalid:${errors.join(",")}`);
  return `${JSON.stringify(canonicalize(value), null, 2)}\n`;
}

function captureFixture({
  fixture,
  rootDirectory,
  executeLive = false,
  refreshCaptured = false,
  transport,
  capturedAt,
}) {
  if (!executeLive) {
    return Promise.resolve({status: "blocked", reasonCode: "execute_live_required"});
  }
  if (fixture.captureStatus === "captured" && !refreshCaptured) {
    return Promise.resolve({status: "blocked",
      reasonCode: "refresh_captured_required"});
  }
  if (!fixture.views || !fixture.views.length) {
    return Promise.resolve({status: "missing_asset",
      reasonCode: "asset_not_committed"});
  }
  for (const view of fixture.views) {
    const absolute = path.resolve(rootDirectory, view.assetPath);
    if (!fs.existsSync(absolute)) {
      return Promise.resolve({status: "missing_asset",
        reasonCode: `asset_missing:${view.viewId}`});
    }
    if (sha256File(absolute) !== view.assetSha256) {
      return Promise.resolve({status: "invalid",
        reasonCode: `asset_hash_mismatch:${view.viewId}`});
    }
  }
  if (typeof transport !== "function") {
    return Promise.resolve({status: "blocked",
      reasonCode: "live_transport_unavailable"});
  }
  return Promise.all(fixture.views.map((view) => transport({
    fixtureId: fixture.id,
    viewId: view.viewId,
    assetPath: path.resolve(rootDirectory, view.assetPath),
    analysisId: stableAnalysisId(fixture.id, view.viewId),
  }))).then((responses) => ({
    status: "captured",
    fixture: buildParserFixture({
      fixture,
      parsedResponses: responses,
      capturedAt,
    }),
  }));
}

function scanForbidden(value, currentPath, errors) {
  if (Array.isArray(value)) {
    value.forEach((item, index) =>
      scanForbidden(item, `${currentPath}[${index}]`, errors));
    return;
  }
  if (!isObject(value)) return;
  for (const [key, item] of Object.entries(value)) {
    if (FORBIDDEN_KEYS.has(key) ||
        /authorization|signed.?url|download.?token/i.test(key)) {
      errors.push(`parser_fixture.forbidden:${currentPath}.${key}`);
    }
    scanForbidden(item, `${currentPath}.${key}`, errors);
  }
}

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (isObject(value)) {
    return Object.fromEntries(Object.keys(value).sort()
      .map((key) => [key, canonicalize(value[key])]));
  }
  return value;
}

function isObject(value) {
  return value != null && typeof value === "object" && !Array.isArray(value);
}
function text(value) {
  return typeof value === "string" && value.trim().length > 0;
}
function hexSha256(value) {
  return typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
}

module.exports = {
  CAPTURE_CONTRACT_VERSION,
  CAPTURE_DATASET,
  PARSER_VERSION,
  PIPELINE_VERSION,
  PROMPT_VERSION,
  buildParserFixture,
  captureFixture,
  preflightCaptureManifest,
  serializeParserFixture,
  sha256File,
  stableAnalysisId,
  bindingFromAssetRelationship,
  resolveMultiViewSubjectBinding,
  validateCaptureManifest,
  validateParserFixture,
};
