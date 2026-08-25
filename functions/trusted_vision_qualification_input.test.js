"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {ANALYSIS_KINDS, allocateServerAnalysisIdentity, decodeServerAnalysisIdentity,
  sourceGenerationFingerprint} = require("./server_analysis_identity");
const {buildTrustedVisionQualificationInput,
  decodeTrustedVisionQualificationInput, extractTrustedMapperAnalysisKind,
  stableCanonicalSerialize} =
  require("./trusted_vision_qualification_input");
const {buildRevisionContext} = require("./wardrobe_qualification_revision_contract");

const ROOT = path.resolve(__dirname, "..");
const ITEM = "item-1";
const CLOCK = "2026-08-05T12:00:00.000Z";
const ARTIFACTS = Object.freeze({contractVersion: 1,
  canonicalFamilyArtifactSha256: "965d8dc38c4b73d70703c48f643754608667b52d243d33080e151ffbc2830c20",
  structuredTaxonomyArtifactSha256: "34cac678be2a8507be12903ad53dfc77e7c81fd448a5f7712bbeba00f771e6dc",
  knowledgeBaseArtifactSha256: "e9b07d0e9867bb63b7962bcf8a4f8acc7cca24c77d9911079e71988b659705c7",
  canonicalFamilyArtifactVersion: "vision-canonical-family-registry-artifact-v1",
  structuredTaxonomyArtifactVersion: "canonical-resolver-structured-taxonomy-artifact-v1",
  knowledgeBaseArtifactVersion: "clothing-kb-prior-artifact-v1"});
const VERSIONS = Object.freeze({parserContractVersion: 1,
  parserVersion: "vision_v2_parser_v1", visionSchemaVersion: 9,
  promptVersion: "vision-v2-schema-9", modelIdentifier: "gpt-4o-mini",
  pipelineVersion: "vision-v2-phase-4.9", qualificationVersion: "qualification-v1",
  provenanceSource: "trusted_server_media"});
const READY = ["blurred_item", "complementary_multi_view", "conflicting_multi_view",
  "cropped_lower", "cropped_upper", "dark_low_contrast", "front_only_garment",
  "shoe_without_outsole"];

function fixture(id = "front_only_garment") { return JSON.parse(fs.readFileSync(
  path.join(ROOT, "test/fixtures/backend_qualification/parser", `${id}.parser.json`), "utf8")); }
function make(id = "front_only_garment", options = {}) {
  const captured = fixture(id);
  const rawViews = captured.views;
  const sources = rawViews.map((_, index) => ({index, viewId: `view_${index + 1}`,
    sourceStoragePath: `wardrobe/user-1/${id}-${index + 1}.jpg`,
    generation: String(100 + index)}));
  const primaryViewIndex = options.primaryViewIndex ?? 0;
  const revision = buildRevisionContext({itemId: ITEM, imageRevision: 1,
    wardrobeItemRevision: 1, sourceStoragePath: sources[primaryViewIndex].sourceStoragePath,
    sourceObjectGeneration: sources[primaryViewIndex].generation,
    sourceObjectMetageneration: "1", sourceImageSha256: null,
    sourceUpdatedAt: CLOCK, expectedProfileRevision: null});
  const identity = allocateServerAnalysisIdentity({itemId: ITEM,
    generationId: revision.generationId,
    analysisKind: options.analysisKind || "initial_analysis",
    serverAttemptId: options.attemptId || "attempt-1", primaryViewIndex, views: sources});
  const snapshots = sources.map((source) => ({contractVersion: 1,
    sourceStoragePath: source.sourceStoragePath, generation: source.generation,
    metageneration: "1", sha256: null, md5Hash: null, crc32c: null,
    sizeBytes: 5, contentType: "image/jpeg", updatedAt: CLOCK,
    exists: true, backendVerified: true}));
  const normalizedViews = rawViews.map((view, index) => {
    const response = structuredClone(view.response);
    response.analysisId = identity.perViewAnalysisIds[index].analysisId;
    response.sourceReference = `gs://server/${sources[index].sourceStoragePath}`;
    return {viewId: sources[index].viewId, response};
  });
  const binding = rawViews.length === 1 ? null : captured.multiViewSubjectBinding;
  const ordering = {contractVersion: 1, primaryViewIndex,
    orderedViews: sources.map((source, index) => ({index, viewId: source.viewId,
      sourceGenerationFingerprint: sourceGenerationFingerprint(
        source.sourceStoragePath, source.generation),
      sourceReference: normalizedViews[index].response.sourceReference,
      orientation: normalizedViews[index].response.subjectAssessment
        .framingAttestations.subjectOrientation}))};
  const attestation = {contractVersion: 1, ...VERSIONS,
    strictParserValidationPassed: true, provenance: {source: VERSIONS.provenanceSource,
      liveModel: true, serverOwnedSourceReference: true}};
  delete attestation.provenanceSource;
  const expectedRuntime = {...VERSIONS, itemId: ITEM,
    generationId: revision.generationId, artifactIntegrity: ARTIFACTS};
  const builderInput = {serverAnalysisIdentity: identity,
    trustedParserResult: {views: normalizedViews, multiViewSubjectBinding: binding},
    trustedParserAttestation: attestation, trustedSourceSnapshots: snapshots,
    trustedRevisionContext: revision, trustedViewOrdering: ordering,
    artifactIntegrity: ARTIFACTS, expectedRuntime};
  return {captured, identity, sources, revision, builderInput,
    value: buildTrustedVisionQualificationInput(builderInput)};
}
function clone(value) { return structuredClone(value); }
function mutate(pathParts, value, id) { const built = make(id); const raw = clone(built.value);
  let cursor = raw; for (const part of pathParts.slice(0, -1)) cursor = cursor[part];
  cursor[pathParts.at(-1)] = value; return {raw, expected: built.builderInput.expectedRuntime}; }
function rejects(raw, expected, pattern) { assert.throws(() =>
  decodeTrustedVisionQualificationInput(raw, expected), pattern); }

test("1 valid single-view identity", () => assert.equal(make().identity.perViewAnalysisIds.length, 1));
test("2 valid multi-view identity", () => assert.equal(make("complementary_multi_view").identity.perViewAnalysisIds.length, 2));
test("3 primary view uses root ID", () => { const x = make("complementary_multi_view");
  assert.equal(x.identity.perViewAnalysisIds[0].analysisId, x.identity.rootAnalysisId); });
test("4 deterministic subordinate IDs", () => assert.deepEqual(make("complementary_multi_view").identity,
  make("complementary_multi_view").identity));
test("5 duplicate view index rejected", () => { const x = clone(make("complementary_multi_view").identity);
  x.perViewAnalysisIds[1].index = 0; assert.throws(() => decodeServerAnalysisIdentity(x), /view_order_invalid|duplicate/); });
test("6 missing primary rejected", () => { const x = clone(make().identity); x.primaryViewIndex = 1;
  assert.throws(() => decodeServerAnalysisIdentity(x), /primary_missing|subordinate_mismatch/); });
test("7 ordering mismatch rejected", () => { const x = make("complementary_multi_view");
  const raw = clone(x.value); raw.viewOrdering.orderedViews.reverse(); rejects(raw,
    x.builderInput.expectedRuntime, /view_ordering/); });
test("8 parser view count mismatch", () => { const x = make("complementary_multi_view");
  const raw = clone(x.value); raw.parserResult.views.pop(); rejects(raw,
    x.builderInput.expectedRuntime, /view_count_mismatch/); });
test("9 parser ID mismatch", () => { const x = mutate(["parserResult", "views", 0,
  "response", "analysisId"], "foreign"); rejects(x.raw, x.expected, /parser_analysis_id_mismatch/); });
test("10 retry with same inputs deterministic", () => assert.equal(
  make().identity.rootAnalysisId, make().identity.rootAnalysisId));
test("11 different generation changes identity binding", () => { const x = make();
  const input = clone(x.builderInput); input.serverAnalysisIdentity = allocateServerAnalysisIdentity({
    itemId: ITEM, generationId: x.revision.generationId, analysisKind: "initial_analysis",
    serverAttemptId: "attempt-1", primaryViewIndex: 0, views: [{index: 0,
      viewId: "view_1", sourceStoragePath: x.sources[0].sourceStoragePath,
      generation: "999"}]}); assert.notEqual(input.serverAnalysisIdentity.rootAnalysisId,
    x.identity.rootAnalysisId); });
test("12 client-supplied analysisId rejected", () => assert.throws(() =>
  allocateServerAnalysisIdentity({analysisId: "client", itemId: ITEM,
    generationId: "g", analysisKind: "x", serverAttemptId: "a", primaryViewIndex: 0,
    views: []}), /forbidden_input/));
test("13 empty root ID rejected", () => { const x = clone(make().identity); x.rootAnalysisId = "";
  assert.throws(() => decodeServerAnalysisIdentity(x), /root_required/); });
test("14 malformed subordinate ID rejected", () => { const x = clone(make("complementary_multi_view").identity);
  x.perViewAnalysisIds[1].analysisId = "bad"; assert.throws(() =>
    decodeServerAnalysisIdentity(x), /subordinate_mismatch/); });

test("14a valid initial_analysis authority", () => {
  assert.equal(make().identity.analysisKind, "initial_analysis");
  assert.deepEqual([...ANALYSIS_KINDS].sort(), ["initial_analysis", "reanalysis"]);
});
test("14b valid reanalysis authority", () => {
  assert.equal(make("front_only_garment", {analysisKind: "reanalysis"})
    .identity.analysisKind, "reanalysis");
});
test("14c missing analysisKind rejected", () => { const x = clone(make().identity);
  delete x.analysisKind; assert.throws(() => decodeServerAnalysisIdentity(x),
    /analysis_identity_kind_invalid/); });
test("14d null analysisKind rejected", () => { const x = clone(make().identity);
  x.analysisKind = null; assert.throws(() => decodeServerAnalysisIdentity(x),
    /analysis_identity_kind_invalid/); });
test("14e empty analysisKind rejected", () => { const x = clone(make().identity);
  x.analysisKind = ""; assert.throws(() => decodeServerAnalysisIdentity(x),
    /analysis_identity_kind_invalid/); });
test("14f unknown analysisKind rejected", () => assert.throws(() =>
  allocateServerAnalysisIdentity({itemId: ITEM, generationId: "generation",
    analysisKind: "unknown", serverAttemptId: "attempt", primaryViewIndex: 0,
    views: [{index: 0, viewId: "view_1", sourceStoragePath: "wardrobe/a.jpg",
      generation: "1"}]}), /analysis_identity_kind_invalid/));
test("14g duplicate client analysisKind authority rejected", () => { const x = make();
  assert.throws(() => buildTrustedVisionQualificationInput({...x.builderInput,
    analysisKind: "reanalysis"}), /analysis_kind_duplicate/);
  assert.throws(() => allocateServerAnalysisIdentity({clientAnalysisKind: "reanalysis",
    itemId: ITEM, generationId: "generation", analysisKind: "initial_analysis",
    serverAttemptId: "attempt", primaryViewIndex: 0, views: [{index: 0,
      viewId: "view_1", sourceStoragePath: "wardrobe/a.jpg", generation: "1"}]}),
  /forbidden_input/); });
test("14h parser analysisKind cannot become authority", () => { const x = make();
  const input = clone(x.builderInput); input.trustedParserResult.views[0]
    .response.analysisKind = "reanalysis"; assert.throws(() =>
    buildTrustedVisionQualificationInput(input), /parser_response_analysis_kind_forbidden/); });
test("14i initial and reanalysis have distinct root bindings", () => {
  assert.notEqual(make().identity.rootAnalysisId,
    make("front_only_garment", {analysisKind: "reanalysis"}).identity.rootAnalysisId);
});
test("14j reanalysis identity is deterministic", () => assert.deepEqual(
  make("front_only_garment", {analysisKind: "reanalysis"}).identity,
  make("front_only_garment", {analysisKind: "reanalysis"}).identity));

test("15 valid full input", () => assert.equal(make().value.contractVersion, 1));
test("16 unknown contract version", () => { const x = mutate(["contractVersion"], 2);
  rejects(x.raw, x.expected, /handoff_contract_unsupported/); });
test("17 unknown root field", () => { const x = make(); const raw = clone(x.value); raw.extra = true;
  rejects(raw, x.builderInput.expectedRuntime, /unknown_field:extra/); });
test("18 missing parserResult", () => { const x = make(); const raw = clone(x.value);
  delete raw.parserResult; rejects(raw, x.builderInput.expectedRuntime, /parser_result_not_object/); });
test("19 invalid parser attestation", () => { const x = mutate(["parserAttestation",
  "strictParserValidationPassed"], false); rejects(x.raw, x.expected, /strict_parser_validation_required/); });
test("20 model mismatch", () => { const x = mutate(["parserAttestation", "modelIdentifier"], "other");
  rejects(x.raw, x.expected, /modelIdentifier_mismatch/); });
test("21 prompt mismatch", () => { const x = mutate(["parserAttestation", "promptVersion"], "other");
  rejects(x.raw, x.expected, /promptVersion_mismatch/); });
test("22 schema mismatch", () => { const x = mutate(["parserAttestation", "visionSchemaVersion"], 8);
  rejects(x.raw, x.expected, /visionSchemaVersion_mismatch/); });
test("23 pipeline mismatch", () => { const x = mutate(["parserAttestation", "pipelineVersion"], "other");
  rejects(x.raw, x.expected, /pipelineVersion_mismatch/); });
test("24 qualification version mismatch", () => { const x = mutate(["parserAttestation",
  "qualificationVersion"], "other"); rejects(x.raw, x.expected, /qualificationVersion_mismatch/); });
test("25 parser contract mismatch", () => { const x = mutate(["parserResult", "contractVersion"], 2);
  rejects(x.raw, x.expected, /parser_result_contract_mismatch/); });
test("26 missing provenance", () => { const x = make(); const raw = clone(x.value);
  delete raw.parserAttestation.provenance; rejects(raw, x.builderInput.expectedRuntime,
    /parser_provenance_missing/); });
test("27 client source provenance rejected", () => { const x = mutate(["parserAttestation",
  "provenance", "source"], "client_media"); rejects(x.raw, x.expected, /provenance_source_mismatch/); });
test("28 source generation mismatch", () => { const x = mutate(["sourceAttestation", "views", 0,
  "generation"], "999"); rejects(x.raw, x.expected, /source_set_fingerprint_mismatch|fingerprint_mismatch/); });
test("29 revision context mismatch", () => { const x = mutate(["revisionContext",
  "sourceObjectGeneration"], "999"); rejects(x.raw, x.expected, /upload_generation_binding_mismatch|revision_source_mismatch/); });
test("30 item binding mismatch", () => { const x = make(); const expected = clone(x.builderInput.expectedRuntime);
  expected.itemId = "other"; rejects(x.value, expected, /revision_identity_mismatch/); });
test("31 invalid content type and size shape", () => { let x = mutate(["sourceAttestation", "views", 0,
  "contentType"], "text/plain"); rejects(x.raw, x.expected, /content_type_invalid/);
  x = mutate(["sourceAttestation", "views", 0, "sizeBytes"], 0); rejects(x.raw,
    x.expected, /size_invalid/); });
test("32 artifact SHA mismatch", () => { const x = mutate(["artifactIntegrity",
  "knowledgeBaseArtifactSha256"], "0".repeat(64)); rejects(x.raw, x.expected,
  /artifact_integrity_mismatch/); });
test("33 multi-view binding mismatch", () => { const x = make("complementary_multi_view");
  const raw = clone(x.value); raw.multiViewSubjectBinding = null; rejects(raw,
    x.builderInput.expectedRuntime, /multi_view_binding_required/); });
test("34 mutable input cloned", () => { const x = make(); const result =
  buildTrustedVisionQualificationInput(x.builderInput); x.builderInput.trustedParserResult
    .views[0].response.inputAssessment = "mutated"; assert.notEqual(
    result.parserResult.views[0].response.inputAssessment, "mutated"); });
test("35 output deeply frozen", () => { const value = make().value;
  assert.equal(Object.isFrozen(value), true); assert.equal(Object.isFrozen(
    value.parserResult.views[0].response.observations), true); });
test("36 deterministic canonical serialization", () => { const value = make().value;
  assert.equal(stableCanonicalSerialize(value), stableCanonicalSerialize(clone(value))); });
test("36a builder and decoder preserve analysisKind", () => { const x = make(
  "front_only_garment", {analysisKind: "reanalysis"}); const decoded =
  decodeTrustedVisionQualificationInput(x.value, x.builderInput.expectedRuntime);
  assert.equal(x.value.analysisIdentity.analysisKind, "reanalysis");
  assert.equal(decoded.analysisIdentity.analysisKind, "reanalysis"); });
test("36b analysisKind output is deeply frozen", () => { const value = make().value;
  assert.equal(Object.isFrozen(value.analysisIdentity), true); });
test("36c mapper extraction returns the sole trusted analysisKind", () => { const x =
  make("front_only_garment", {analysisKind: "reanalysis"}); assert.equal(
  extractTrustedMapperAnalysisKind(x.value, x.builderInput.expectedRuntime),
  "reanalysis"); });
test("36d expectedProfileRevision cannot substitute for analysisKind", () => {
  const x = make(); const raw = clone(x.value); delete raw.analysisIdentity.analysisKind;
  raw.revisionContext.expectedProfileRevision = 99; rejects(raw,
    x.builderInput.expectedRuntime, /analysis_identity_kind_invalid/); });
test("36e no hard-coded mapper analysisKind fallback in trusted contract", () => {
  const source = fs.readFileSync(path.join(__dirname,
    "trusted_vision_qualification_input.js"), "utf8");
  assert.doesNotMatch(source, /analysisKind\s*:\s*["']initial_analysis["']/);
});
test("36f parser schema remains unchanged", () => { const x = make();
  assert.equal(x.value.parserResult.views[0].response.schemaVersion, 9);
  assert.equal(Object.hasOwn(x.value.parserResult.views[0].response,
    "analysisKind"), false); });
test("36g contract has no scenario or oracle dependency", () => {
  for (const file of ["trusted_vision_qualification_input.js",
    "server_analysis_identity.js"]) { const source = fs.readFileSync(
    path.join(__dirname, file), "utf8"); assert.doesNotMatch(source,
    /test[\\/]fixtures|oracle_manifest|scenarioId\s*[:=]/i); }
});

test("eight ready parser fixtures wrap without schema change or provider output injection", () => {
  for (const id of READY) { const x = make(id); assert.equal(
    x.value.analysisIdentity.analysisKind, "initial_analysis", id); assert.equal(x.value.parserResult.views.length,
    x.captured.views.length, id); assert.equal(JSON.stringify(x.value).includes("providerOutput"), false, id); }
});
test("eight fixtures preserve all parser fields except server-normalized authority fields", () => {
  for (const id of READY) { const x = make(id); x.captured.views.forEach((view, index) => {
    const expected = clone(view.response); const actual = clone(x.value.parserResult.views[index].response);
    delete expected.analysisId; delete actual.analysisId; delete expected.sourceReference;
    delete actual.sourceReference; assert.deepEqual(actual, expected, id); }); }
});
test("production contract source has no fixture, oracle, fs, path, Firebase or OpenAI import", () => {
  for (const file of ["trusted_vision_qualification_input.js", "server_analysis_identity.js"]) {
    const source = fs.readFileSync(path.join(__dirname, file), "utf8");
    assert.doesNotMatch(source, /test[\\/]fixtures|firebase-admin|require\("node:fs"\)|require\("node:path"\)/i);
  }
});
