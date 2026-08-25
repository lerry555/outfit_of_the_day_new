"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {allocateServerAnalysisIdentity, sourceGenerationFingerprint} =
  require("./server_analysis_identity");
const {buildTrustedVisionQualificationInput, stableCanonicalSerialize} =
  require("./trusted_vision_qualification_input");
const {buildRevisionContext} = require("./wardrobe_qualification_revision_contract");
const {runLiveParserBackendQualification} =
  require("./live_parser_backend_qualification_orchestrator");

const ROOT = path.resolve(__dirname, "..");
const CLOCK = "2000-01-01T00:00:00.000Z";
const READY = ["blurred_item", "complementary_multi_view",
  "conflicting_multi_view", "cropped_lower", "cropped_upper",
  "dark_low_contrast", "front_only_garment", "shoe_without_outsole"];
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

function fixture(id) { return JSON.parse(fs.readFileSync(path.join(ROOT,
  "test/fixtures/backend_qualification/parser", `${id}.parser.json`), "utf8")); }

function runtimeCase(id = "front_only_garment", analysisKind = "initial_analysis") {
  const captured = fixture(id);
  const sources = captured.views.map((_, index) => ({index,
    viewId: `view_${index + 1}`,
    sourceStoragePath: `wardrobe/user-1/item-${index + 1}.jpg`,
    generation: String(100 + index)}));
  const revision = buildRevisionContext({itemId: "item-1", imageRevision: 1,
    wardrobeItemRevision: 1, sourceStoragePath: sources[0].sourceStoragePath,
    sourceObjectGeneration: sources[0].generation, sourceObjectMetageneration: "1",
    sourceImageSha256: "a".repeat(64), sourceUpdatedAt: CLOCK,
    expectedProfileRevision: 1});
  const identity = allocateServerAnalysisIdentity({itemId: "item-1",
    generationId: revision.generationId, analysisKind,
    serverAttemptId: "attempt-1", primaryViewIndex: 0, views: sources});
  const views = captured.views.map((view, index) => { const response =
    structuredClone(view.response); response.analysisId =
    identity.perViewAnalysisIds[index].analysisId;
  return {viewId: sources[index].viewId, response}; });
  const snapshots = sources.map((source) => ({contractVersion: 1,
    sourceStoragePath: source.sourceStoragePath, generation: source.generation,
    metageneration: "1", sha256: "a".repeat(64), md5Hash: null, crc32c: null,
    sizeBytes: 5, contentType: "image/jpeg", updatedAt: CLOCK,
    exists: true, backendVerified: true}));
  const ordering = {contractVersion: 1, primaryViewIndex: 0,
    orderedViews: sources.map((source, index) => ({index, viewId: source.viewId,
      sourceGenerationFingerprint: sourceGenerationFingerprint(
        source.sourceStoragePath, source.generation),
      sourceReference: views[index].response.sourceReference,
      orientation: views[index].response.subjectAssessment
        .framingAttestations.subjectOrientation}))};
  const attestation = {contractVersion: 1, ...VERSIONS,
    strictParserValidationPassed: true, provenance: {
      source: VERSIONS.provenanceSource, liveModel: true,
      serverOwnedSourceReference: true}};
  delete attestation.provenanceSource;
  const expectedRuntime = {...VERSIONS, itemId: "item-1",
    generationId: revision.generationId, artifactIntegrity: ARTIFACTS};
  const input = buildTrustedVisionQualificationInput({serverAnalysisIdentity: identity,
    trustedParserResult: {views, multiViewSubjectBinding:
      views.length === 1 ? null : captured.multiViewSubjectBinding},
    trustedParserAttestation: attestation, trustedSourceSnapshots: snapshots,
    trustedRevisionContext: revision, trustedViewOrdering: ordering,
    artifactIntegrity: ARTIFACTS, expectedRuntime});
  return {captured, expectedRuntime, identity, input};
}

function execute(id, kind, dependencies = {}) { const value = runtimeCase(id, kind);
  return {...value, output: runLiveParserBackendQualification(value.input,
    {expectedRuntime: value.expectedRuntime, ...dependencies})}; }
function tampered(mutator) { const value = runtimeCase(); const raw =
  structuredClone(value.input); mutator(raw); return runLiveParserBackendQualification(
  raw, {expectedRuntime: value.expectedRuntime}); }

test("1 valid single-view initial_analysis", () => { const x = execute();
  assert.equal(x.output.status, "qualified", JSON.stringify(x.output.diagnostics));
  assert.equal(x.output.analysisKind, "initial_analysis"); });
test("2 valid single-view reanalysis", () => { const x = execute(
  "front_only_garment", "reanalysis"); assert.equal(x.output.status, "qualified",
  JSON.stringify(x.output.diagnostics)); assert.equal(x.output.mapperInput
    .mappingContext.analysisKind, "reanalysis"); });
test("3 valid multi-view", () => { const x = execute("complementary_multi_view");
  assert.equal(x.output.status, "qualified", JSON.stringify(x.output.diagnostics));
  assert.equal(x.output.perViewQualificationReports.length, 2); });
test("4 invalid trusted input", () => assert.equal(
  runLiveParserBackendQualification(null).status,
  "invalid_trusted_input"));
test("5 analysis ID mismatch", () => assert.equal(tampered((raw) => {
  raw.parserResult.views[0].response.analysisId = "foreign"; }).status,
"analysis_identity_mismatch"));
test("6 parallel analysisKind rejected", () => { const x = runtimeCase();
  assert.equal(runLiveParserBackendQualification({...x.input,
    analysisKind: "reanalysis"}, {expectedRuntime: x.expectedRuntime}).status,
  "analysis_kind_mismatch"); });
test("7 view ordering mismatch", () => assert.equal(tampered((raw) => {
  raw.viewOrdering.orderedViews[0].viewId = "other"; }).status,
"view_ordering_mismatch"));
test("8 missing parser field", () => assert.equal(tampered((raw) => {
  delete raw.parserResult.views[0].response.modelVersion; }).status,
"parser_attestation_mismatch"));
test("9 provider failure propagation", () => { const x = execute(
  "front_only_garment", "initial_analysis", {provideKnowledgeBasePriors() {
    throw new Error("forced_provider_failure"); }}); assert.equal(x.output.status,
  "provider_output_invalid"); assert.equal(x.output.diagnostics.stage, "kb_provider"); });
test("10 artifact SHA mismatch", () => assert.equal(tampered((raw) => {
  raw.artifactIntegrity.knowledgeBaseArtifactSha256 = "0".repeat(64); }).status,
"artifact_integrity_mismatch"));
test("11 immutable input", () => { const x = runtimeCase(); const before =
  stableCanonicalSerialize(x.input); execute(); assert.equal(
    stableCanonicalSerialize(x.input), before); });
test("12 deterministic rerun", () => { const x = runtimeCase(); const a =
  runLiveParserBackendQualification(x.input, {expectedRuntime: x.expectedRuntime});
  const b = runLiveParserBackendQualification(x.input,
    {expectedRuntime: x.expectedRuntime}); assert.equal(a.canonicalJson, b.canonicalJson); });
test("13 scenarioId rejected", () => { const x = runtimeCase(); assert.equal(
  runLiveParserBackendQualification({...x.input, scenarioId: "x"},
    {expectedRuntime: x.expectedRuntime}).status, "invalid_trusted_input"); });
test("14 fixtureId rejected", () => { const x = runtimeCase(); assert.equal(
  runLiveParserBackendQualification({...x.input, fixtureId: "x"},
    {expectedRuntime: x.expectedRuntime}).status, "invalid_trusted_input"); });
test("15 oracle output injection rejected", () => { const x = runtimeCase();
  assert.equal(runLiveParserBackendQualification({...x.input, providerOutputs: []},
    {expectedRuntime: x.expectedRuntime}).status, "invalid_trusted_input"); });
test("16 production source has no fixture/oracle imports", () => { const source =
  fs.readFileSync(path.join(__dirname,
    "live_parser_backend_qualification_orchestrator.js"), "utf8");
  assert.doesNotMatch(source, /test[\\/]fixtures|oracle_manifest|backend_.*parity/);
  assert.doesNotMatch(source, /scenarioId|fixtureId|fixtureRoot|oraclePath/); });
test("17 single-view evidence IDs stable", () => assert.deepEqual(
  execute().output.observationEvidence.map((item) => item.id),
  execute().output.observationEvidence.map((item) => item.id)));
test("18 multi-view evidence IDs stable", () => assert.deepEqual(
  execute("complementary_multi_view").output.observationEvidence.map((item) => item.id),
  execute("complementary_multi_view").output.observationEvidence.map((item) => item.id)));
test("19 same-item binding", () => assert.equal(execute("complementary_multi_view")
  .output.mapperInput.analysisProjection.multiPhotoAssessment.sameItemViews, true));
test("20 different-items binding", () => assert.equal(execute("conflicting_multi_view")
  .output.mapperInput.analysisProjection.multiPhotoAssessment.sameItemViews, false));
test("21 invalid parser result", () => assert.equal(tampered((raw) => {
  raw.parserResult.views[0].response.inputAssessment = "invalid"; }).status,
"invalid_trusted_input"));
test("22 mapper analysisId exact match", () => { const x = execute(); assert.equal(
  x.output.mapperInput.mappingContext.analysisId, x.output.rootAnalysisId); });
test("23 mapper analysisKind exact match", () => { const x = execute(
  "front_only_garment", "reanalysis"); assert.equal(
  x.output.mapperInput.mappingContext.analysisKind, x.output.analysisKind); });
test("24 eight fixture inputs lose no parser fields", () => { for (const id of READY) {
  const x = runtimeCase(id); x.captured.views.forEach((view, index) => { const expected =
    structuredClone(view.response); const actual = structuredClone(x.input.parserResult
      .views[index].response); delete expected.analysisId; delete actual.analysisId;
  assert.deepEqual(actual, expected, id); }); } });
test("25 zero hidden mutation", () => { const x = runtimeCase(); const parser =
  stableCanonicalSerialize(x.input.parserResult); runLiveParserBackendQualification(x.input,
    {expectedRuntime: x.expectedRuntime}); assert.equal(
    stableCanonicalSerialize(x.input.parserResult), parser); });
test("26 canonical JSON stable", () => { const x = execute(); const value =
  structuredClone(x.output); delete value.canonicalJson; assert.equal(
    x.output.canonicalJson, stableCanonicalSerialize(value)); });
test("27 all eight fixtures execute without oracle injection", () => {
  for (const id of READY) { const x = execute(id); assert.equal(x.output.status,
    "qualified", `${id}:${JSON.stringify(x.output.diagnostics)}`); }
});
test("28 output deeply frozen", () => { const output = execute().output;
  assert.equal(Object.isFrozen(output), true);
  assert.equal(Object.isFrozen(output.mapperResult), true); });
test("29 isolated runtime import", () => { assert.doesNotThrow(() =>
  require("./live_parser_backend_qualification_orchestrator")); });
