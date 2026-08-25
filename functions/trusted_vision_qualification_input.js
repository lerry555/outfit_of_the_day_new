"use strict";

const crypto = require("node:crypto");
const {decodeServerAnalysisIdentity, canonicalStringify,
  sourceGenerationFingerprint} = require("./server_analysis_identity");
const {decodeTrustedSourceObjectSnapshot} = require("./trusted_source_object_snapshot");
const {decodeRevisionContext} = require("./wardrobe_qualification_revision_contract");

const CONTRACT_ID = "TrustedVisionQualificationInput/v1";
const WIRE_ID = "trusted-vision-qualification-input/v1";
const CONTRACT_VERSION = 1;
const VIEW_ORDERING_ID = "TrustedVisionViewOrdering/v1";
const ALLOWED_CONTENT_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
const CLAIMS = new Set(["same_physical_item", "different_physical_items", "undeclared"]);
const ROOT_FIELDS = Object.freeze(["contractVersion", "analysisIdentity",
  "parserResult", "parserAttestation", "sourceAttestation", "viewOrdering",
  "multiViewSubjectBinding", "revisionContext", "artifactIntegrity"]);

function buildTrustedVisionQualificationInput(input) {
  object(input, "handoff_builder_input_not_object");
  rejectForbidden(input);
  rejectNamed(input, ["analysisKind", "clientAnalysisKind"],
    "handoff_builder_analysis_kind_duplicate");
  exact(input, ["serverAnalysisIdentity", "trustedParserResult",
    "trustedParserAttestation", "trustedSourceSnapshots", "trustedRevisionContext",
    "trustedViewOrdering", "artifactIntegrity", "expectedRuntime"],
  "handoff_builder_unknown_field");
  const parser = object(input.trustedParserResult, "parser_result_not_object");
  rejectNamed(parser, ["scenarioId", "fixtureId", "fixtureRoot", "oracleId",
    "clientAnalysisId", "providerOutputs", "mapperOutput"],
  "parser_result_forbidden_runtime_field");
  const views = array(parser.views, "parser_result_views_empty");
  if (views.length === 0) fail("parser_result_views_empty");
  const projectedViews = views.map((view, index) => {
    object(view, `parser_view_not_object:${index}`);
    const viewId = text(view.viewId, `parser_view_id_required:${index}`);
    object(view.response, `parser_view_response_required:${index}`);
    return {viewId, response: structuredClone(view.response)};
  });
  const binding = parser.multiViewSubjectBinding ?? null;
  const snapshots = array(input.trustedSourceSnapshots,
    "source_attestation_views_missing").map(decodeTrustedSourceObjectSnapshot);
  const sourceSetFingerprint = sha256(canonicalStringify(snapshots.map((item) => ({
    generation: item.generation, sourceStoragePath: item.sourceStoragePath}))));
  const sourceGenerationSetFingerprint = sha256(canonicalStringify(
    snapshots.map((item) => sourceGenerationFingerprint(
      item.sourceStoragePath, item.generation))));
  const raw = {contractVersion: CONTRACT_VERSION,
    analysisIdentity: input.serverAnalysisIdentity,
    parserResult: {contractVersion: 1, views: projectedViews},
    parserAttestation: input.trustedParserAttestation,
    sourceAttestation: {contractVersion: 1, sourceSetFingerprint,
      sourceGenerationSetFingerprint,
      views: snapshots},
    viewOrdering: input.trustedViewOrdering,
    multiViewSubjectBinding: binding,
    revisionContext: input.trustedRevisionContext,
    artifactIntegrity: input.artifactIntegrity};
  return decodeTrustedVisionQualificationInput(raw, input.expectedRuntime);
}

function decodeTrustedVisionQualificationInput(raw, expectedRuntime) {
  object(raw, "trusted_vision_qualification_input_not_object");
  exact(raw, ROOT_FIELDS, "trusted_vision_qualification_input_unknown_field");
  if (raw.contractVersion !== CONTRACT_VERSION) fail("handoff_contract_unsupported");
  const expected = decodeExpectedRuntime(expectedRuntime);
  const analysisIdentity = decodeServerAnalysisIdentity(raw.analysisIdentity);
  const parserAttestation = decodeParserAttestation(raw.parserAttestation, expected);
  const sourceAttestation = decodeSourceAttestation(raw.sourceAttestation);
  const ordering = decodeViewOrdering(raw.viewOrdering);
  const revisionContext = decodeRevisionContext(raw.revisionContext);
  const artifacts = decodeArtifactIntegrity(raw.artifactIntegrity, expected);
  const parserResult = decodeParserResult(raw.parserResult, parserAttestation);
  bindCounts(parserResult, analysisIdentity, sourceAttestation, ordering);
  const binding = decodeMultiViewBinding(raw.multiViewSubjectBinding,
    parserResult.views.length);
  for (let index = 0; index < parserResult.views.length; index += 1) {
    const parserView = parserResult.views[index];
    const identityView = analysisIdentity.perViewAnalysisIds[index];
    const source = sourceAttestation.views[index];
    const ordered = ordering.orderedViews[index];
    if (parserView.viewId !== identityView.viewId ||
        parserView.viewId !== ordered.viewId || ordered.index !== index) {
      fail("handoff_view_ordering_mismatch");
    }
    if (parserView.response.analysisId !== identityView.analysisId) {
      fail("handoff_parser_analysis_id_mismatch");
    }
    const fingerprint = sourceGenerationFingerprint(
      source.sourceStoragePath, source.generation);
    if (fingerprint !== identityView.sourceGenerationFingerprint ||
        fingerprint !== ordered.sourceGenerationFingerprint) {
      fail("handoff_source_generation_fingerprint_mismatch");
    }
    if (parserView.response.sourceReference !== ordered.sourceReference) {
      fail("handoff_source_reference_mismatch");
    }
    const orientation = parserView.response.subjectAssessment &&
      parserView.response.subjectAssessment.framingAttestations &&
      parserView.response.subjectAssessment.framingAttestations.subjectOrientation;
    if (ordered.orientation != null && orientation !== ordered.orientation) {
      fail("handoff_view_orientation_mismatch");
    }
  }
  const primary = analysisIdentity.primaryViewIndex;
  if (ordering.primaryViewIndex !== primary ||
      parserResult.views[primary].response.analysisId !==
        analysisIdentity.rootAnalysisId) {
    fail("handoff_primary_analysis_identity_mismatch");
  }
  const primarySource = sourceAttestation.views[primary];
  if (revisionContext.sourceStoragePath !== primarySource.sourceStoragePath ||
      revisionContext.sourceObjectGeneration !== primarySource.generation ||
      revisionContext.uploadGeneration !== primarySource.generation) {
    fail("handoff_revision_source_mismatch");
  }
  if (revisionContext.generationId !== expected.generationId ||
      revisionContext.itemId !== expected.itemId) {
    fail("handoff_revision_identity_mismatch");
  }
  if (analysisIdentity.sourceGenerationSetFingerprint !==
      sourceAttestation.sourceGenerationSetFingerprint) {
    fail("handoff_source_set_identity_mismatch");
  }
  return deepFreeze({contractVersion: CONTRACT_VERSION,
    analysisIdentity: structuredClone(analysisIdentity), parserResult,
    parserAttestation, sourceAttestation, viewOrdering: ordering,
    multiViewSubjectBinding: binding, revisionContext,
    artifactIntegrity: artifacts});
}

function extractTrustedMapperAnalysisKind(raw, expectedRuntime) {
  return decodeTrustedVisionQualificationInput(raw, expectedRuntime)
    .analysisIdentity.analysisKind;
}

function decodeExpectedRuntime(raw) {
  object(raw, "expected_runtime_not_object");
  const keys = ["parserContractVersion", "parserVersion", "visionSchemaVersion",
    "promptVersion", "modelIdentifier", "pipelineVersion", "qualificationVersion",
    "provenanceSource", "itemId", "generationId", "artifactIntegrity"];
  exact(raw, keys, "expected_runtime_unknown_field");
  const artifactIntegrity = object(raw.artifactIntegrity,
    "expected_artifact_integrity_missing");
  return deepFreeze({parserContractVersion: positiveInt(raw.parserContractVersion,
    "expected_parser_contract_invalid"), parserVersion: text(raw.parserVersion,
    "expected_parser_version_required"), visionSchemaVersion: positiveInt(
    raw.visionSchemaVersion, "expected_schema_invalid"), promptVersion: text(
    raw.promptVersion, "expected_prompt_required"), modelIdentifier: text(
    raw.modelIdentifier, "expected_model_required"), pipelineVersion: text(
    raw.pipelineVersion, "expected_pipeline_required"), qualificationVersion: text(
    raw.qualificationVersion, "expected_qualification_required"), provenanceSource: text(
    raw.provenanceSource, "expected_provenance_source_required"), itemId: text(
    raw.itemId, "expected_item_id_required"), generationId: text(raw.generationId,
    "expected_generation_id_required"), artifactIntegrity: structuredClone(artifactIntegrity)});
}

function decodeParserAttestation(raw, expected) {
  object(raw, "parser_attestation_not_object");
  exact(raw, ["contractVersion", "parserContractVersion", "parserVersion",
    "visionSchemaVersion", "promptVersion", "modelIdentifier", "pipelineVersion",
    "qualificationVersion", "strictParserValidationPassed", "provenance"],
  "parser_attestation_unknown_field");
  if (raw.contractVersion !== 1) fail("parser_attestation_contract_unsupported");
  if (raw.strictParserValidationPassed !== true) fail("strict_parser_validation_required");
  const fields = ["parserContractVersion", "parserVersion", "visionSchemaVersion",
    "promptVersion", "modelIdentifier", "pipelineVersion", "qualificationVersion"];
  for (const field of fields) {
    if (raw[field] !== expected[field]) fail(`parser_attestation_${field}_mismatch`);
  }
  object(raw.provenance, "parser_provenance_missing");
  exact(raw.provenance, ["source", "liveModel", "serverOwnedSourceReference"],
    "parser_provenance_unknown_field");
  if (raw.provenance.source !== expected.provenanceSource) {
    fail("parser_provenance_source_mismatch");
  }
  if (raw.provenance.liveModel !== true) fail("parser_provenance_live_model_required");
  if (raw.provenance.serverOwnedSourceReference !== true) {
    fail("parser_source_reference_not_server_owned");
  }
  return deepFreeze(structuredClone(raw));
}

function decodeParserResult(raw, attestation) {
  object(raw, "parser_result_not_object");
  exact(raw, ["contractVersion", "views"], "parser_result_unknown_field");
  if (raw.contractVersion !== attestation.parserContractVersion) {
    fail("parser_result_contract_mismatch");
  }
  const views = array(raw.views, "parser_result_views_missing");
  if (!views.length) fail("parser_result_views_empty");
  const seen = new Set();
  const decoded = views.map((view, index) => {
    object(view, `parser_view_not_object:${index}`);
    exact(view, ["viewId", "response"], "parser_view_unknown_field");
    const viewId = text(view.viewId, `parser_view_id_required:${index}`);
    if (seen.has(viewId)) fail("parser_view_id_duplicate"); seen.add(viewId);
    const response = object(view.response, `parser_response_missing:${index}`);
    rejectNamed(response, ["analysisKind", "clientAnalysisKind"],
      "parser_response_analysis_kind_forbidden");
    for (const field of ["analysisId", "modelVersion", "sourceReference",
      "observedAt", "inputAssessment"]) text(response[field],
      `parser_response_${field}_required:${index}`);
    if (response.schemaVersion !== attestation.visionSchemaVersion) {
      fail("parser_response_schema_mismatch");
    }
    if (response.modelVersion !== attestation.modelIdentifier) {
      fail("parser_response_model_mismatch");
    }
    for (const field of ["quality", "subjectAssessment", "observations"] ) {
      object(response[field], `parser_response_${field}_invalid:${index}`);
    }
    if (!Array.isArray(response.identityCandidates) ||
        !Array.isArray(response.validationErrors)) {
      fail(`parser_response_collections_invalid:${index}`);
    }
    return {viewId, response: structuredClone(response)};
  });
  return deepFreeze({contractVersion: raw.contractVersion, views: decoded});
}

function decodeSourceAttestation(raw) {
  object(raw, "source_attestation_not_object");
  exact(raw, ["contractVersion", "sourceSetFingerprint",
    "sourceGenerationSetFingerprint", "views"],
    "source_attestation_unknown_field");
  if (raw.contractVersion !== 1) fail("source_attestation_contract_unsupported");
  const views = array(raw.views, "source_attestation_views_missing")
    .map((snapshot) => {
      const decoded = decodeTrustedSourceObjectSnapshot(snapshot);
      if (!decoded.exists || !decoded.generation) fail("source_snapshot_missing");
      if (!Number.isInteger(decoded.sizeBytes) || decoded.sizeBytes <= 0) {
        fail("source_snapshot_size_invalid");
      }
      if (!ALLOWED_CONTENT_TYPES.has(decoded.contentType)) {
        fail("source_snapshot_content_type_invalid");
      }
      return decoded;
    });
  if (!views.length) fail("source_attestation_views_missing");
  const fingerprint = sha(raw.sourceSetFingerprint, "source_set_fingerprint_invalid");
  const expected = sha256(canonicalStringify(views.map((item) => ({
    generation: item.generation, sourceStoragePath: item.sourceStoragePath}))));
  if (fingerprint !== expected) fail("source_set_fingerprint_mismatch");
  const generationSet = sha(raw.sourceGenerationSetFingerprint,
    "source_generation_set_fingerprint_invalid");
  const expectedGenerationSet = sha256(canonicalStringify(views.map((item) =>
    sourceGenerationFingerprint(item.sourceStoragePath, item.generation))));
  if (generationSet !== expectedGenerationSet) {
    fail("source_generation_set_fingerprint_mismatch");
  }
  return deepFreeze({contractVersion: 1, sourceSetFingerprint: fingerprint,
    sourceGenerationSetFingerprint: generationSet,
    views: structuredClone(views)});
}

function decodeViewOrdering(raw) {
  object(raw, "view_ordering_not_object");
  exact(raw, ["contractVersion", "primaryViewIndex", "orderedViews"],
    "view_ordering_unknown_field");
  if (raw.contractVersion !== 1) fail("view_ordering_contract_unsupported");
  const primaryViewIndex = nonNegativeInt(raw.primaryViewIndex,
    "view_ordering_primary_invalid");
  const views = array(raw.orderedViews, "view_ordering_views_missing");
  if (!views.length || primaryViewIndex >= views.length) fail("view_ordering_primary_missing");
  const ids = new Set();
  const decoded = views.map((view, position) => {
    object(view, `view_ordering_descriptor_invalid:${position}`);
    exact(view, ["index", "viewId", "sourceGenerationFingerprint",
      "sourceReference", "orientation"], "view_ordering_descriptor_unknown_field");
    const index = nonNegativeInt(view.index, "view_ordering_index_invalid");
    if (index !== position) fail("view_ordering_index_mismatch");
    const viewId = text(view.viewId, "view_ordering_view_id_required");
    if (ids.has(viewId)) fail("view_ordering_duplicate_view_id"); ids.add(viewId);
    return {index, viewId, sourceGenerationFingerprint: sha(
      view.sourceGenerationFingerprint, "view_ordering_source_fingerprint_invalid"),
    sourceReference: text(view.sourceReference, "view_ordering_source_reference_required"),
    orientation: view.orientation == null ? null : text(view.orientation,
      "view_ordering_orientation_invalid")};
  });
  return deepFreeze({contractVersion: 1, primaryViewIndex,
    orderedViews: decoded});
}

function decodeMultiViewBinding(raw, count) {
  const value = raw == null ? {contractVersion: 1,
    physicalIdentityClaim: "undeclared", source: "undeclared", reasonCodes: []} : raw;
  object(value, "multi_view_binding_not_object");
  exact(value, ["contractVersion", "physicalIdentityClaim", "source", "reasonCodes"],
    "multi_view_binding_unknown_field");
  if (value.contractVersion !== 1 || !CLAIMS.has(value.physicalIdentityClaim)) {
    fail("multi_view_binding_invalid");
  }
  const source = text(value.source, "multi_view_binding_source_required");
  if (!Array.isArray(value.reasonCodes) || value.reasonCodes.some((item) =>
    typeof item !== "string" || !item.trim())) fail("multi_view_binding_reasons_invalid");
  if (count === 1 && value.physicalIdentityClaim !== "undeclared") {
    fail("single_view_binding_must_be_undeclared");
  }
  if (count > 1 && raw == null) fail("multi_view_binding_required");
  return deepFreeze({contractVersion: 1,
    physicalIdentityClaim: value.physicalIdentityClaim, source,
    reasonCodes: [...value.reasonCodes]});
}

function decodeArtifactIntegrity(raw, expected) {
  object(raw, "artifact_integrity_not_object");
  const keys = ["contractVersion", "canonicalFamilyArtifactSha256",
    "structuredTaxonomyArtifactSha256", "knowledgeBaseArtifactSha256",
    "canonicalFamilyArtifactVersion", "structuredTaxonomyArtifactVersion",
    "knowledgeBaseArtifactVersion"];
  exact(raw, keys, "artifact_integrity_unknown_field");
  if (raw.contractVersion !== 1) fail("artifact_integrity_contract_unsupported");
  exact(expected.artifactIntegrity, keys, "expected_artifact_integrity_unknown_field");
  for (const key of keys) {
    if (raw[key] !== expected.artifactIntegrity[key]) fail(`artifact_integrity_mismatch:${key}`);
  }
  for (const key of keys.filter((key) => key.endsWith("Sha256"))) sha(raw[key],
    `artifact_integrity_sha_invalid:${key}`);
  return deepFreeze(structuredClone(raw));
}

function bindCounts(parser, identity, source, ordering) {
  const count = parser.views.length;
  if (identity.perViewAnalysisIds.length !== count || source.views.length !== count ||
      ordering.orderedViews.length !== count) fail("handoff_view_count_mismatch");
}
function rejectForbidden(value) { rejectNamed(value, ["scenarioId", "fixtureId",
  "fixtureRoot", "oracleId", "clientAnalysisId", "providerOutputs", "mapperOutput"],
"handoff_forbidden_runtime_field"); }
function rejectNamed(value, keys, prefix) { for (const key of keys) if (
  Object.prototype.hasOwnProperty.call(value, key)) fail(`${prefix}:${key}`); }
function stableCanonicalSerialize(value) { return canonicalStringify(value); }
function sha256(value) { return crypto.createHash("sha256").update(value).digest("hex"); }
function sha(value, code) { const v = text(value, code).toLowerCase();
  if (!/^[a-f0-9]{64}$/.test(v)) fail(code); return v; }
function object(value, code) { if (!value || typeof value !== "object" ||
  Array.isArray(value)) fail(code); return value; }
function array(value, code) { if (!Array.isArray(value)) fail(code); return value; }
function text(value, code) { if (typeof value !== "string" || !value.trim()) fail(code);
  return value.trim(); }
function positiveInt(value, code) { if (!Number.isInteger(value) || value <= 0) fail(code);
  return value; }
function nonNegativeInt(value, code) { if (!Number.isInteger(value) || value < 0) fail(code);
  return value; }
function exact(value, allowed, prefix) { for (const key of Object.keys(value)) {
  if (!allowed.includes(key)) fail(`${prefix}:${key}`); } }
function deepFreeze(value) { if (value && typeof value === "object" && !Object.isFrozen(value)) {
  Object.values(value).forEach(deepFreeze); Object.freeze(value); } return value; }
function fail(code) { const error = new Error(code); error.code = code; throw error; }

module.exports = {ALLOWED_CONTENT_TYPES, CONTRACT_ID, CONTRACT_VERSION,
  VIEW_ORDERING_ID, WIRE_ID, buildTrustedVisionQualificationInput,
  decodeTrustedVisionQualificationInput, extractTrustedMapperAnalysisKind,
  stableCanonicalSerialize};
