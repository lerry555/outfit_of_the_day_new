"use strict";

const crypto = require("node:crypto");

const CONTRACT_ID = "ServerAnalysisIdentity/v1";
const WIRE_ID = "server-analysis-identity/v1";
const CONTRACT_VERSION = 1;
const ROOT_PREFIX = "wqvis:v1:";
const VIEW_PREFIX = "wqview:v1:";
const ANALYSIS_KINDS = new Set(["initial_analysis", "reanalysis"]);

function allocateServerAnalysisIdentity(input) {
  assertObject(input, "analysis_identity_factory_input_not_object");
  rejectKeys(input, ["analysisId", "rootAnalysisId", "scenarioId", "fixtureId",
    "oracleId", "clientAnalysisId", "clientAnalysisKind"],
  "server_analysis_identity_forbidden_input");
  const itemId = text(input.itemId, "analysis_identity_item_id_required");
  const generationId = text(input.generationId,
    "analysis_identity_generation_id_required");
  const analysisKind = enumValue(input.analysisKind, ANALYSIS_KINDS,
    "analysis_identity_kind_invalid");
  const attemptId = text(input.serverAttemptId,
    "analysis_identity_server_attempt_id_required");
  const primaryViewIndex = nonNegativeInt(input.primaryViewIndex,
    "analysis_identity_primary_index_invalid");
  const views = decodeFactoryViews(input.views);
  if (primaryViewIndex >= views.length) fail("analysis_identity_primary_missing");

  const rootAnalysisId = ROOT_PREFIX + hash(canonicalStringify({analysisKind,
    attemptId, generationId, itemId, primaryViewIndex,
    views: views.map(({index, viewId, sourceGenerationFingerprint}) =>
      ({index, sourceGenerationFingerprint, viewId}))})).slice(0, 32);
  const perViewAnalysisIds = views.map((view) => Object.freeze({
    index: view.index,
    viewId: view.viewId,
    sourceGenerationFingerprint: view.sourceGenerationFingerprint,
    analysisId: view.index === primaryViewIndex ? rootAnalysisId :
      VIEW_PREFIX + hash(canonicalStringify({rootAnalysisId, index: view.index,
        sourceGenerationFingerprint: view.sourceGenerationFingerprint,
        viewId: view.viewId})).slice(0, 32),
  }));
  return decodeServerAnalysisIdentity({contractVersion: CONTRACT_VERSION,
    analysisKind, rootAnalysisId, primaryViewIndex,
    sourceGenerationSetFingerprint: hash(canonicalStringify(
      views.map((view) => view.sourceGenerationFingerprint))),
    perViewAnalysisIds});
}

function decodeServerAnalysisIdentity(raw) {
  assertObject(raw, "analysis_identity_not_object");
  exactKeys(raw, ["contractVersion", "analysisKind", "rootAnalysisId", "primaryViewIndex",
    "sourceGenerationSetFingerprint", "perViewAnalysisIds"],
  "analysis_identity_unknown_field");
  if (raw.contractVersion !== CONTRACT_VERSION) {
    fail("analysis_identity_contract_unsupported");
  }
  const analysisKind = enumValue(raw.analysisKind, ANALYSIS_KINDS,
    "analysis_identity_kind_invalid");
  const rootAnalysisId = text(raw.rootAnalysisId,
    "analysis_identity_root_required");
  if (!new RegExp(`^${escapeRegex(ROOT_PREFIX)}[a-f0-9]{32}$`).test(rootAnalysisId)) {
    fail("analysis_identity_root_malformed");
  }
  const primaryViewIndex = nonNegativeInt(raw.primaryViewIndex,
    "analysis_identity_primary_index_invalid");
  const setFingerprint = sha(raw.sourceGenerationSetFingerprint,
    "analysis_identity_source_set_fingerprint_invalid");
  if (!Array.isArray(raw.perViewAnalysisIds) ||
      raw.perViewAnalysisIds.length === 0) {
    fail("analysis_identity_views_empty");
  }
  const seenIndexes = new Set();
  const seenViews = new Set();
  const seenIds = new Set();
  const views = raw.perViewAnalysisIds.map((value, position) => {
    assertObject(value, `analysis_identity_view_invalid:${position}`);
    exactKeys(value, ["index", "viewId", "sourceGenerationFingerprint",
      "analysisId"], "analysis_identity_view_unknown_field");
    const index = nonNegativeInt(value.index,
      "analysis_identity_view_index_invalid");
    if (index !== position) fail("analysis_identity_view_order_invalid");
    if (seenIndexes.has(index)) fail("analysis_identity_duplicate_view_index");
    const viewId = text(value.viewId, "analysis_identity_view_id_required");
    if (seenViews.has(viewId)) fail("analysis_identity_duplicate_view_id");
    const sourceGenerationFingerprint = sha(value.sourceGenerationFingerprint,
      "analysis_identity_source_fingerprint_invalid");
    const analysisId = text(value.analysisId,
      "analysis_identity_view_analysis_id_required");
    if (seenIds.has(analysisId)) fail("analysis_identity_duplicate_view_analysis_id");
    const expected = index === primaryViewIndex ? rootAnalysisId :
      VIEW_PREFIX + hash(canonicalStringify({rootAnalysisId, index,
        sourceGenerationFingerprint, viewId})).slice(0, 32);
    if (analysisId !== expected) fail("analysis_identity_subordinate_mismatch");
    seenIndexes.add(index); seenViews.add(viewId); seenIds.add(analysisId);
    return {index, viewId, sourceGenerationFingerprint, analysisId};
  });
  if (!seenIndexes.has(primaryViewIndex)) fail("analysis_identity_primary_missing");
  if (views[primaryViewIndex].analysisId !== rootAnalysisId) {
    fail("analysis_identity_primary_not_root");
  }
  const expectedSet = hash(canonicalStringify(
    views.map((view) => view.sourceGenerationFingerprint)));
  if (setFingerprint !== expectedSet) fail("analysis_identity_source_set_mismatch");
  return deepFreeze({contractVersion: CONTRACT_VERSION, analysisKind, rootAnalysisId,
    primaryViewIndex, sourceGenerationSetFingerprint: setFingerprint,
    perViewAnalysisIds: structuredClone(views)});
}

function sourceGenerationFingerprint(sourceStoragePath, generation) {
  return hash(canonicalStringify({generation: digits(generation,
    "source_generation_invalid"), sourceStoragePath: text(sourceStoragePath,
    "source_storage_path_required")}));
}
function decodeFactoryViews(raw) {
  if (!Array.isArray(raw) || raw.length === 0) fail("analysis_identity_views_empty");
  return raw.map((value, position) => {
    assertObject(value, `analysis_identity_factory_view_invalid:${position}`);
    exactKeys(value, ["index", "viewId", "sourceStoragePath", "generation"],
      "analysis_identity_factory_view_unknown_field");
    const index = nonNegativeInt(value.index, "analysis_identity_view_index_invalid");
    if (index !== position) fail("analysis_identity_view_order_invalid");
    return {index, viewId: text(value.viewId, "analysis_identity_view_id_required"),
      sourceGenerationFingerprint: sourceGenerationFingerprint(
        value.sourceStoragePath, value.generation)};
  });
}
function canonicalStringify(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalStringify).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.keys(value).sort()
    .map((key) => `${JSON.stringify(key)}:${canonicalStringify(value[key])}`).join(",")}}`;
  return JSON.stringify(value);
}
function hash(value) { return crypto.createHash("sha256").update(value).digest("hex"); }
function sha(value, code) { const v = text(value, code).toLowerCase();
  if (!/^[a-f0-9]{64}$/.test(v)) fail(code); return v; }
function digits(value, code) { const v = text(String(value ?? ""), code);
  if (!/^\d+$/.test(v)) fail(code); return v; }
function text(value, code) { if (typeof value !== "string" || !value.trim()) fail(code);
  return value.trim(); }
function enumValue(value, allowed, code) { const result = text(value, code);
  if (!allowed.has(result)) fail(code); return result; }
function nonNegativeInt(value, code) { if (!Number.isInteger(value) || value < 0) fail(code);
  return value; }
function assertObject(value, code) { if (!value || typeof value !== "object" ||
  Array.isArray(value)) fail(code); }
function exactKeys(value, allowed, prefix) { for (const key of Object.keys(value)) {
  if (!allowed.includes(key)) fail(`${prefix}:${key}`); } }
function rejectKeys(value, keys, prefix) { for (const key of keys) {
  if (Object.prototype.hasOwnProperty.call(value, key)) fail(`${prefix}:${key}`); } }
function escapeRegex(value) { return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }
function deepFreeze(value) { if (value && typeof value === "object" && !Object.isFrozen(value)) {
  Object.values(value).forEach(deepFreeze); Object.freeze(value); } return value; }
function fail(code) { const error = new Error(code); error.code = code; throw error; }

module.exports = {ANALYSIS_KINDS, CONTRACT_ID, CONTRACT_VERSION, ROOT_PREFIX,
  VIEW_PREFIX, WIRE_ID,
  allocateServerAnalysisIdentity, canonicalStringify, decodeServerAnalysisIdentity,
  sourceGenerationFingerprint};
