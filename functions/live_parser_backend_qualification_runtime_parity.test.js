"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {diff} = require("./backend_provider_oracle_parity");
const {allocateServerAnalysisIdentity, sourceGenerationFingerprint} =
  require("./server_analysis_identity");
const {buildTrustedVisionQualificationInput} =
  require("./trusted_vision_qualification_input");
const {buildRevisionContext} = require("./wardrobe_qualification_revision_contract");
const {runLiveParserBackendQualification} =
  require("./live_parser_backend_qualification_orchestrator");

const FIXTURES = path.resolve(__dirname, "../test/fixtures");
const QUALIFICATION = path.join(FIXTURES, "backend_qualification");
const CLOCK = "2000-01-01T00:00:00.000Z";
const READY = ["blurred_item", "complementary_multi_view",
  "conflicting_multi_view", "cropped_lower", "cropped_upper",
  "dark_low_contrast", "front_only_garment", "shoe_without_outsole"];
const ARTIFACTS = {contractVersion: 1,
  canonicalFamilyArtifactSha256: "965d8dc38c4b73d70703c48f643754608667b52d243d33080e151ffbc2830c20",
  structuredTaxonomyArtifactSha256: "34cac678be2a8507be12903ad53dfc77e7c81fd448a5f7712bbeba00f771e6dc",
  knowledgeBaseArtifactSha256: "e9b07d0e9867bb63b7962bcf8a4f8acc7cca24c77d9911079e71988b659705c7",
  canonicalFamilyArtifactVersion: "vision-canonical-family-registry-artifact-v1",
  structuredTaxonomyArtifactVersion: "canonical-resolver-structured-taxonomy-artifact-v1",
  knowledgeBaseArtifactVersion: "clothing-kb-prior-artifact-v1"};
const VERSIONS = {parserContractVersion: 1,
  parserVersion: "vision_v2_parser_v1", visionSchemaVersion: 9,
  promptVersion: "vision-v2-schema-9", modelIdentifier: "gpt-4o-mini",
  pipelineVersion: "vision-v2-phase-4.9", qualificationVersion: "qualification-v1",
  provenanceSource: "trusted_server_media"};
const MANIFESTS = Object.freeze({framing: "backend_framing_attestor_oracle_manifest.json",
  applicability: "backend_applicability_qualifier_oracle_manifest.json",
  visibility: "backend_visibility_trust_oracle_manifest.json",
  negativeClaim: "backend_negative_claim_corroborator_oracle_manifest.json",
  absence: "backend_observation_absence_qualifier_oracle_manifest.json",
  observation: "backend_provider_oracle_manifest.json",
  canonical: "backend_canonical_consistency_oracle_manifest.json",
  identity: "backend_identity_qualification_oracle_manifest.json",
  family: "backend_family_identity_oracle_manifest.json",
  kb: "backend_wardrobe_kb_prior_oracle_manifest.json",
  resolver: "backend_wardrobe_profile_resolver_oracle_manifest.json",
  mapper: "backend_qualified_vision_persistence_mapper_oracle_manifest.json"});

function read(file) { return JSON.parse(fs.readFileSync(file, "utf8")); }
function fixture(id) { return read(path.join(QUALIFICATION, "parser",
  `${id}.parser.json`)); }
function oracle(kind, id) { const manifest = read(path.join(QUALIFICATION,
  MANIFESTS[kind])); const entry = manifest.fixtures.find((item) =>
    item.status === "ready" && item.scenarioId === id); if (!entry) return null;
  return read(path.resolve(FIXTURES, entry.oraclePath)); }

function buildCase(id) {
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
    generationId: revision.generationId, analysisKind: "initial_analysis",
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
      serverOwnedSourceReference: true}}; delete attestation.provenanceSource;
  const expectedRuntime = {...VERSIONS, itemId: "item-1",
    generationId: revision.generationId, artifactIntegrity: ARTIFACTS};
  const input = buildTrustedVisionQualificationInput({serverAnalysisIdentity: identity,
    trustedParserResult: {views, multiViewSubjectBinding:
      views.length === 1 ? null : captured.multiViewSubjectBinding},
    trustedParserAttestation: attestation, trustedSourceSnapshots: snapshots,
    trustedRevisionContext: revision, trustedViewOrdering: ordering,
    artifactIntegrity: ARTIFACTS, expectedRuntime});
  const output = runLiveParserBackendQualification(input, {expectedRuntime});
  assert.equal(output.status, "qualified", `${id}:${JSON.stringify(output.diagnostics)}`);
  return {captured, identity, input, output};
}

function replacements(value) {
  const map = new Map();
  value.captured.views.forEach((view, index) => { const old = view.response.analysisId;
    const current = value.identity.perViewAnalysisIds[index].analysisId;
    map.set(old, current); map.set(encodeURIComponent(old), encodeURIComponent(current)); });
  return map;
}

function normalize(value, map) {
  if (typeof value === "string") { let result = value;
    for (const [oldValue, newValue] of map) result = result.split(oldValue).join(newValue);
    return result; }
  if (Array.isArray(value)) return value.map((item) => normalize(item, map));
  if (value && typeof value === "object") return Object.fromEntries(
    Object.entries(value).map(([key, child]) => [normalize(key, map),
      normalize(child, map)]));
  return value;
}

function compare(expected, actual, map, label, differences) {
  const found = diff(normalize(expected, map), structuredClone(actual));
  if (found.length) differences.push(...found.map((item) =>
    `${label}:${JSON.stringify(item)}`));
}

function compareEvidenceOrdered(expected, actual, map, label, differences) {
  const normalized = normalize(expected, map);
  const normalizedActual = structuredClone(actual);
  sortEvidenceArrays(normalized);
  sortEvidenceArrays(normalizedActual);
  const found = diff(normalized, normalizedActual);
  if (found.length) differences.push(...found.map((item) =>
    `${label}:${JSON.stringify(item)}`));
}

function sortEvidenceArrays(value) {
  if (Array.isArray(value)) {
    value.forEach(sortEvidenceArrays);
    if (value.length > 0 && value.every((item) => item &&
        typeof item === "object" && typeof item.id === "string")) {
      value.sort((left, right) => left.id < right.id ? -1 :
        left.id > right.id ? 1 : 0);
    }
  } else if (value && typeof value === "object") {
    Object.values(value).forEach(sortEvidenceArrays);
  }
}

function capabilityExpected(id) {
  const manifest = read(path.join(FIXTURES,
    "backend_qualification_golden_manifest.json"));
  const entry = manifest.fixtures.find((item) => item.id === id &&
    item.goldenStatus === "ready");
  return entry ? read(path.resolve(FIXTURES, entry.dartReference))
    .capabilityEvidence : null;
}

function projectCapability(items) { return items.map((item) => {
  const result = {}; for (const key of ["id", "property", "value", "valueState",
    "source", "nature", "confidence", "method", "supportingEvidenceIds"]) {
    result[key] = structuredClone(item[key]);
  } return result; }); }

function scenarioParity(id) {
  const value = buildCase(id); const output = value.output;
  const map = replacements({...value, id}); const differences = [];
  const coverage = {};
  const perView = (kind, actual, inputKey = "providerInput",
      outputKey = "providerOutput") => { const expected = oracle(kind, id);
    coverage[kind] = expected ? expected.invocations.length : 0;
    if (!expected) return; expected.invocations.forEach((invocation, index) => {
      compare(invocation[inputKey], actual[index].input, map,
        `${kind}.input.${index}`, differences);
      compare(invocation[outputKey], actual[index].output, map,
        `${kind}.output.${index}`, differences); }); };
  perView("framing", output.perViewQualificationReports.map((item, index) => ({
    input: {inputAssessment: value.input.parserResult.views[index].response.inputAssessment,
      subject: (() => { const subject = structuredClone(value.input.parserResult
        .views[index].response.subjectAssessment); delete subject.framingAttestations;
      return subject; })(),
      quality: value.input.parserResult.views[index].response.quality,
      attestations: value.input.parserResult.views[index].response.subjectAssessment
        .framingAttestations}, output: item.framing})));
  const simple = [["applicability", "applicability"], ["visibility", "visibility"],
    ["negativeClaim", "negativeClaims"]];
  for (const [kind, field] of simple) { const expected = oracle(kind, id);
    coverage[kind] = expected ? expected.invocations.length : 0;
    if (!expected) continue; expected.invocations.forEach((invocation, index) => {
      compare(invocation.providerOutput,
        output.perViewQualificationReports[index][field], map,
        `${kind}.output.${index}`, differences); }); }
  const absence = oracle("absence", id); coverage.absence = absence ? 1 : 0;
  if (absence) { compare(absence.invocations[0].providerOutput,
    output.absenceQualificationReport, map, "absence.output", differences); }
  const observation = oracle("observation", id); coverage.observation = observation ? 1 : 0;
  if (observation) { compare(observation.providerOutput,
    output.observationProviderOutput,
    map, "observation.output", differences); }
  const expectedCapability = capabilityExpected(id);
  coverage.capability = expectedCapability ? 1 : 0;
  if (expectedCapability) compare(expectedCapability,
    projectCapability(output.capabilityProviderOutput), map,
    "capability.output", differences);
  const canonical = oracle("canonical", id); coverage.canonical = canonical ? 1 : 0;
  if (canonical) compare(canonical.providerOutput, output.canonicalConsistency,
    map, "canonical.output", differences);
  for (const [kind, inputField, outputField, actualInput, actualOutput] of [
    ["identity", "providerInput", "providerOutput", output.identityInput,
      {qualifiedIdentityEvidence: output.qualifiedIdentityEvidence,
        report: output.identityQualificationReport}],
    ["family", "providerInput", "providerOutput", output.familyInput,
      output.familyIdentityReport],
    ["kb", "providerInput", "providerOutput", output.knowledgeBaseInput,
      output.knowledgeBaseEvidence]]) {
    const expected = oracle(kind, id); coverage[kind] = expected ? 1 : 0;
    if (expected) { const compareStage = kind === "family" ? compare :
      compareEvidenceOrdered; compareStage(expected.invocations[0][inputField],
      actualInput, map, `${kind}.input`, differences); compareStage(
      expected.invocations[0][outputField], actualOutput, map,
      `${kind}.output`, differences); }
  }
  const resolver = oracle("resolver", id); coverage.resolver = resolver ? 1 : 0;
  if (resolver) { const expectedInput = structuredClone(
    resolver.invocations[0].resolverInput); expectedInput.itemId = "item-1";
    const expectedOutput = structuredClone(resolver.invocations[0].resolverOutput);
    expectedOutput.itemId = "item-1"; compareEvidenceOrdered(expectedInput,
    output.resolverInput, map, "resolver.input", differences); compareEvidenceOrdered(
    expectedOutput, output.resolvedWardrobeProfile,
    map, "resolver.output", differences); }
  const mapper = oracle("mapper", id); coverage.mapper = mapper ? 1 : 0;
  if (mapper) { const invocation = structuredClone(mapper.invocations[0]);
    const expectedContext = invocation.mapperInput.mappingContext;
    const actualContext = output.mapperInput.mappingContext;
    for (const key of Object.keys(expectedContext)) {
      if (typeof expectedContext[key] === "string" &&
          typeof actualContext[key] === "string") {
        map.set(expectedContext[key], actualContext[key]);
      }
    }
    invocation.mapperInput.mappingContext = structuredClone(actualContext);
    compareEvidenceOrdered(invocation.mapperInput, output.mapperInput, map,
      "mapper.input", differences);
    compareEvidenceOrdered(invocation.mapperOutput, output.mapperResult, map,
      "mapper.output", differences); }
  return {id, passed: differences.length === 0, differences, coverage};
}

test("provider-boundary runtime parity for eight ready scenarios", () => {
  const results = READY.map(scenarioParity); const failed = results.filter(
    (item) => !item.passed); const summary = failed.map((item) => ({id: item.id,
    differenceCount: item.differences.length,
    differences: item.differences.slice(0, 20), coverage: item.coverage}));
  assert.deepEqual(failed.map((item) => item.id), [], JSON.stringify(summary,
    null, 2)); assert.equal(results.length, 8);
});
