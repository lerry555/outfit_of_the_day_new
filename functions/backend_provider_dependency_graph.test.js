"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const {
  BACKEND_ARTIFACT_GRAPH,
  BACKEND_ARTIFACT_LOADER_STATUSES,
  BACKEND_ARTIFACT_STATUSES,
  BACKEND_CONTRACT_GRAPH,
  BACKEND_CONTRACT_STATUSES,
  BACKEND_ORCHESTRATION_GRAPH,
  BACKEND_ORCHESTRATION_STATUSES,
  BACKEND_PROVIDER_GRAPH,
  BACKEND_PROVIDER_STATUSES,
} = require("./backend_provider_dependency_graph");

const projectRoot = path.resolve(__dirname, "..");
const fixtureRoot = path.join(projectRoot, "test", "fixtures");
const byId = new Map(BACKEND_PROVIDER_GRAPH.map((item) => [item.id, item]));

function visit(id, visiting, visited) {
  if (visited.has(id)) return;
  assert.equal(visiting.has(id), false, `cycle detected at ${id}`);
  visiting.add(id);
  for (const next of byId.get(id).downstream) {
    visit(next, visiting, visited);
  }
  visiting.delete(id);
  visited.add(id);
}

test("provider DAG has unique IDs, valid edges, and no cycles", () => {
  assert.equal(byId.size, BACKEND_PROVIDER_GRAPH.length, "duplicate provider ID");
  for (const item of BACKEND_PROVIDER_GRAPH) {
    for (const upstream of item.upstream) {
      assert.ok(byId.has(upstream), `${item.id}: unknown upstream ${upstream}`);
      assert.ok(byId.get(upstream).downstream.includes(item.id),
        `${upstream} does not declare downstream ${item.id}`);
    }
    for (const downstream of item.downstream) {
      assert.ok(byId.has(downstream),
        `${item.id}: unknown downstream ${downstream}`);
      assert.ok(byId.get(downstream).upstream.includes(item.id),
        `${downstream} does not declare upstream ${item.id}`);
    }
  }
  const visited = new Set();
  for (const item of BACKEND_PROVIDER_GRAPH) {
    visit(item.id, new Set(), visited);
  }
  assert.equal(visited.size, BACKEND_PROVIDER_GRAPH.length);
});

test("provider ordering is a valid deterministic topological order", () => {
  const positions = new Map(
    BACKEND_PROVIDER_GRAPH.map((item, index) => [item.id, index]),
  );
  for (const item of BACKEND_PROVIDER_GRAPH) {
    for (const upstream of item.upstream) {
      assert.ok(positions.get(upstream) < positions.get(item.id),
        `${upstream} must precede ${item.id}`);
    }
  }
});

test("only declared terminal providers have no downstream", () => {
  for (const item of BACKEND_PROVIDER_GRAPH) {
    assert.equal(item.downstream.length === 0, item.terminal === true, item.id);
  }
});

test("exactly thirteen providers have Node parity", () => {
  const ready = BACKEND_PROVIDER_GRAPH.filter(
    (item) => item.status === "parity_ready",
  );
  const nodeProviders = BACKEND_PROVIDER_GRAPH.filter(
    (item) => item.nodeSource !== null,
  );
  assert.deepEqual(ready.map((item) => item.id),
    [
      "VisionFramingAttestor",
      "VisionPropertyApplicabilityQualifier",
      "VisionVisibilityTrustQualifier",
      "VisionNegativeClaimCorroborator",
      "ObservationAbsenceQualifier",
      "VisionObservationEvidenceProvider",
      "CanonicalObservationConsistencyValidator",
      "VisionIdentityQualification",
      "VisionFamilyIdentityResolver",
      "WardrobeCapabilityInferenceProvider",
      "WardrobeKnowledgeBasePriorProvider",
      "WardrobeProfileResolver",
      "QualifiedVisionPersistenceMapper",
    ]);
  assert.deepEqual(nodeProviders.map((item) => item.id),
    [
      "VisionFramingAttestor",
      "VisionPropertyApplicabilityQualifier",
      "VisionVisibilityTrustQualifier",
      "VisionNegativeClaimCorroborator",
      "ObservationAbsenceQualifier",
      "VisionObservationEvidenceProvider",
      "CanonicalObservationConsistencyValidator",
      "VisionIdentityQualification",
      "VisionFamilyIdentityResolver",
      "WardrobeCapabilityInferenceProvider",
      "WardrobeKnowledgeBasePriorProvider",
      "WardrobeProfileResolver",
      "QualifiedVisionPersistenceMapper",
    ]);
});

test("provider status and portability metadata are consistent", () => {
  for (const item of BACKEND_PROVIDER_GRAPH) {
    assert.ok(BACKEND_PROVIDER_STATUSES.includes(item.status), item.id);
    assert.equal(fs.existsSync(path.join(projectRoot, item.dartSource)), true,
      `${item.id}: missing Dart source`);
    if (item.nodeSource !== null) {
      assert.equal(fs.existsSync(path.join(projectRoot, item.nodeSource)), true,
        `${item.id}: missing Node source`);
    }
    if (item.portableNow) {
      assert.deepEqual(item.blockers, [], `${item.id}: portable with blockers`);
    } else {
      assert.ok(item.blockers.length > 0, `${item.id}: blocker missing`);
    }
  }
});

test("parity and oracle manifests agree with the audited provider status", () => {
  const oracleManifest = JSON.parse(fs.readFileSync(path.join(
    fixtureRoot,
    "backend_qualification/backend_provider_oracle_manifest.json",
  ), "utf8"));
  const parityManifest = JSON.parse(fs.readFileSync(path.join(
    fixtureRoot,
    "backend_qualification/backend_provider_parity_manifest.json",
  ), "utf8"));
  assert.deepEqual(
    [...new Set(oracleManifest.fixtures.map((item) => item.providerId))],
    ["VisionObservationEvidenceProvider"],
  );
  assert.equal(parityManifest.providers.length, 13);
  for (const persisted of parityManifest.providers) {
    const audited = byId.get(persisted.providerId);
    assert.ok(audited);
    assert.equal(persisted.parityStatus, audited.status);
    assert.equal(persisted.nodeProviderSource, audited.nodeSource);
    assert.equal(persisted.dartProviderSource, audited.dartSource);
    assert.equal(persisted.passedScenarios, 8);
    assert.equal(persisted.failedScenarios, 0);
  }
});

test("oracle dataset is complete and bound to eight distinct ready scenarios", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(
    fixtureRoot,
    "backend_qualification/backend_provider_oracle_manifest.json",
  ), "utf8"));
  const ready = manifest.fixtures.filter((item) => item.status === "ready");
  assert.equal(ready.length, 8);
  assert.equal(new Set(ready.map((item) => item.scenarioId)).size, 8);
  for (const item of ready) {
    const oraclePath = path.join(fixtureRoot, item.oraclePath);
    assert.equal(fs.existsSync(oraclePath), true, item.scenarioId);
    const oracle = JSON.parse(fs.readFileSync(oraclePath, "utf8"));
    assert.equal(oracle.providerId, item.providerId);
    assert.equal(oracle.oracleContractVersion, item.contractVersion);
    assert.equal(oracle.providerInputSha256, item.providerInputSha256);
    assert.equal(oracle.providerOutputSha256, item.providerOutputSha256);
  }
});

test("next provider input and reference output already exist for all ready scenarios", () => {
  const oracleManifest = JSON.parse(fs.readFileSync(path.join(
    fixtureRoot,
    "backend_qualification/backend_provider_oracle_manifest.json",
  ), "utf8"));
  const goldenManifest = JSON.parse(fs.readFileSync(path.join(
    fixtureRoot,
    "backend_qualification_golden_manifest.json",
  ), "utf8"));
  const readyGoldens = new Map(goldenManifest.fixtures
    .filter((item) => item.goldenStatus === "ready")
    .map((item) => [item.id, item]));
  const readyOracles = oracleManifest.fixtures
    .filter((item) => item.status === "ready");
  assert.equal(readyOracles.length, 8);
  assert.equal(readyGoldens.size, 8);

  for (const oracleEntry of readyOracles) {
    const goldenEntry = readyGoldens.get(oracleEntry.scenarioId);
    assert.ok(goldenEntry, oracleEntry.scenarioId);
    const oracle = JSON.parse(fs.readFileSync(
      path.join(fixtureRoot, oracleEntry.oraclePath), "utf8"));
    const input = JSON.parse(fs.readFileSync(
      path.join(fixtureRoot, goldenEntry.qualificationInput), "utf8"));
    const reference = JSON.parse(fs.readFileSync(
      path.join(fixtureRoot, goldenEntry.dartReference), "utf8"));

    // WardrobeCapabilityInferenceProvider consumes exactly these values.
    assert.ok(Array.isArray(oracle.providerOutput));
    assert.equal(typeof input.analysisId, "string");
    assert.equal(typeof input.observedAt, "string");
    assert.ok(Array.isArray(reference.capabilityEvidence));
  }
});

test("identity qualification is portable and parity_ready", () => {
  const identity = byId.get("VisionIdentityQualification");
  assert.equal(identity.status, "parity_ready");
  assert.equal(identity.nodeSource, "functions/vision_identity_qualifier.js");
  assert.equal(identity.portableNow, true);
  assert.deepEqual(identity.blockers, []);
});

test("family identity resolver is parity_ready with Node source", () => {
  const family = byId.get("VisionFamilyIdentityResolver");
  assert.equal(family.status, "parity_ready");
  assert.equal(family.nodeSource, "functions/vision_family_identity_resolver.js");
  assert.equal(family.portableNow, true);
  assert.deepEqual(family.blockers, []);
});

test("KB prior is parity_ready with Node source", () => {
  const kb = byId.get("WardrobeKnowledgeBasePriorProvider");
  assert.equal(kb.status, "parity_ready");
  assert.equal(kb.nodeSource, "functions/wardrobe_knowledge_base_prior_provider.js");
  assert.equal(kb.portableNow, true);
  assert.equal(kb.oracleReady, true);
  assert.deepEqual(kb.blockers, []);
  assert.equal(
    fs.existsSync(path.join(projectRoot, kb.oracleManifest)),
    true,
  );
  assert.equal(
    fs.existsSync(path.join(projectRoot, kb.nodeSource)),
    true,
  );
});

test("profile resolver is parity_ready with Node source", () => {
  const resolver = byId.get("WardrobeProfileResolver");
  assert.equal(resolver.status, "parity_ready");
  assert.equal(resolver.nodeSource, "functions/wardrobe_profile_resolver.js");
  assert.equal(resolver.portableNow, true);
  assert.equal(resolver.oracleReady, true);
  assert.deepEqual(resolver.blockers, []);
  assert.equal(
    fs.existsSync(path.join(projectRoot, resolver.oracleManifest)),
    true,
  );
  assert.equal(
    fs.existsSync(path.join(projectRoot, resolver.nodeSource)),
    true,
  );
  const mapper = byId.get("QualifiedVisionPersistenceMapper");
  assert.equal(mapper.status, "parity_ready");
  assert.equal(
    mapper.nodeSource,
    "functions/qualified_vision_persistence_mapper.js",
  );
  assert.equal(mapper.portableNow, true);
  assert.equal(mapper.oracleReady, true);
  assert.deepEqual(mapper.blockers, []);
  assert.deepEqual(mapper.productionBlockers, [
    "production_write_boundary",
    "migration_required",
    "production_export_pending",
  ]);
  assert.ok(!mapper.productionBlockers.includes("missing_trusted_revision_contract"));
  assert.ok(!mapper.productionBlockers.includes("revision_lifecycle_assignment_required"));
  assert.ok(!mapper.productionBlockers.includes("authority_endpoint_missing"));
  assert.ok(!mapper.productionBlockers.includes("storage_adapter_not_wired"));
  assert.ok(!mapper.blockers.includes("missing_oracle"));
  assert.ok(!mapper.blockers.includes("mapper_dependency"));
  assert.ok(!mapper.blockers.includes("missing_upstream_resolver"));
  assert.ok(!mapper.blockers.includes("missing_prepare_stage"));
  assert.equal(
    fs.existsSync(path.join(projectRoot, mapper.oracleManifest)),
    true,
  );
  assert.equal(
    fs.existsSync(path.join(projectRoot,
      "functions/prepare_qualified_vision_persistence_mapper_input.js")),
    true,
  );
  assert.equal(
    fs.existsSync(path.join(projectRoot, mapper.nodeSource)),
    true,
  );
  assert.equal(
    fs.existsSync(path.join(projectRoot,
      "functions/backend_qualified_vision_persistence_mapper_parity.js")),
    true,
  );
});

test("clothing KB prior artifact is artifact_ready with Node loader", () => {
  assert.equal(BACKEND_ARTIFACT_GRAPH.length, 1);
  const artifact = BACKEND_ARTIFACT_GRAPH[0];
  assert.equal(artifact.id, "ClothingKnowledgeBasePriorArtifact");
  assert.equal(artifact.status, "artifact_ready");
  assert.equal(artifact.loaderStatus, "artifact_loader_ready");
  assert.ok(BACKEND_ARTIFACT_STATUSES.includes(artifact.status));
  assert.ok(BACKEND_ARTIFACT_LOADER_STATUSES.includes(artifact.loaderStatus));
  assert.equal(
    artifact.nodeLoader,
    "functions/clothing_knowledge_base_prior_loader.js",
  );
  assert.deepEqual(artifact.consumers, ["WardrobeKnowledgeBasePriorProvider"]);
  assert.equal(
    fs.existsSync(path.join(projectRoot, artifact.artifactPath)),
    true,
  );
  assert.equal(
    fs.existsSync(path.join(projectRoot, artifact.artifactManifest)),
    true,
  );
  assert.equal(
    fs.existsSync(path.join(projectRoot, artifact.nodeLoader)),
    true,
  );
  const readyProviders = BACKEND_PROVIDER_GRAPH.filter(
    (item) => item.status === "parity_ready",
  );
  assert.equal(readyProviders.length, 13);
  assert.equal(BACKEND_ORCHESTRATION_GRAPH.length, 5);
});

test("trusted revision contract is contract_ready without changing parity count", () => {
  assert.equal(BACKEND_CONTRACT_GRAPH.length, 29);
  const handoff = BACKEND_CONTRACT_GRAPH.find((item) =>
    item.id === "TrustedVisionQualificationInput");
  const analysisIdentity = BACKEND_CONTRACT_GRAPH.find((item) =>
    item.id === "ServerAnalysisIdentityAuthority");
  const liveOrchestrator = BACKEND_CONTRACT_GRAPH.find((item) =>
    item.id === "LiveParserRuntimeOrchestrator");
  const analysisKind = BACKEND_CONTRACT_GRAPH.find((item) =>
    item.id === "TrustedAnalysisKindAuthority");
  const liveShadow = BACKEND_CONTRACT_GRAPH.find((item) =>
    item.id === "LiveShadowWiring");
  assert.equal(handoff.status, "contract_ready");
  assert.deepEqual([...handoff.blockers], []);
  assert.equal(analysisIdentity.status, "contract_ready");
  assert.deepEqual([...analysisIdentity.blockers], []);
  assert.equal(analysisKind.status, "contract_ready");
  assert.deepEqual([...analysisKind.blockers], []);
  assert.equal(liveOrchestrator.status, "runtime_ready");
  assert.equal(liveOrchestrator.portableNow, true);
  assert.equal(liveOrchestrator.nodeSource,
    "functions/live_parser_backend_qualification_orchestrator.js");
  assert.deepEqual([...liveOrchestrator.blockers], []);
  assert.deepEqual([...liveOrchestrator.productionBlockers],
    ["controlled_live_shadow_smoke_pending"]);
  assert.equal(liveShadow.status, "runtime_ready");
  assert.equal(liveShadow.nodeSource,
    "functions/wardrobe_authority_shadow_runner.js");
  assert.deepEqual([...liveShadow.blockers], []);
  assert.deepEqual([...liveShadow.productionBlockers],
    ["manual_policy_configuration_pending",
      "manual_lease_creation_pending", "disabled_redeploy_pending",
      "controlled_live_shadow_smoke_pending"]);
  assert.equal(BACKEND_CONTRACT_GRAPH.find((item) =>
    item.id === "ControlledShadowActivationPolicy").status, "contract_ready");
  assert.equal(BACKEND_CONTRACT_GRAPH.find((item) =>
    item.id === "SingleUseShadowLease").status, "runtime_ready");
  const revision = BACKEND_CONTRACT_GRAPH.find((item) =>
    item.id === "TrustedRevisionContract");
  const storage = BACKEND_CONTRACT_GRAPH.find((item) =>
    item.id === "TrustedStorageMetadataAdapter");
  const lifecycle = BACKEND_CONTRACT_GRAPH.find((item) =>
    item.id === "WardrobeRevisionLifecycleMutationService");
  const orchestrator = BACKEND_CONTRACT_GRAPH.find((item) =>
    item.id === "WardrobeBackendQualificationOrchestrator");
  const lifecycleEndpoint = BACKEND_CONTRACT_GRAPH.find((item) =>
    item.id === "WardrobeRevisionLifecycleEndpoint");
  const authorityEndpoint = BACKEND_CONTRACT_GRAPH.find((item) =>
    item.id === "WardrobeQualificationAuthorityEndpoint");
  const repository = BACKEND_CONTRACT_GRAPH.find((item) =>
    item.id === "WardrobeProfilePersistenceRepositoryAdapter");
  const rules = BACKEND_CONTRACT_GRAPH.find((item) =>
    item.id === "SecurityRulesBoundary");
  const prodDeps = BACKEND_CONTRACT_GRAPH.find((item) =>
    item.id === "WardrobeAuthorityProductionDependencies");
  const authorityHandler = BACKEND_CONTRACT_GRAPH.find((item) =>
    item.id === "WardrobeQualificationAuthorityHandler");
  const lifecycleHandler = BACKEND_CONTRACT_GRAPH.find((item) =>
    item.id === "WardrobeRevisionLifecycleHandler");
  assert.ok(revision);
  assert.equal(revision.status, "contract_ready");
  assert.equal(revision.productionReady, false);
  assert.equal(
    revision.nodeSource,
    "functions/wardrobe_qualification_revision_contract.js",
  );
  assert.ok(BACKEND_CONTRACT_STATUSES.includes(revision.status));
  assert.equal(
    fs.existsSync(path.join(projectRoot, revision.nodeSource)),
    true,
  );
  assert.ok(revision.blockers.includes("migration_required"));
  assert.ok(!revision.blockers.includes("revision_lifecycle_assignment_required"));
  assert.ok(!revision.blockers.includes("authority_endpoint_missing"));
  assert.equal(storage.status, "production_adapter_ready_unwired_export");
  assert.equal(
    storage.nodeSource,
    "functions/trusted_storage_metadata_adapter.js",
  );
  assert.ok(storage.blockers.includes("production_export_pending"));
  assert.equal(lifecycle.status, "lifecycle_ready_offline");
  assert.equal(
    lifecycle.nodeSource,
    "functions/wardrobe_revision_lifecycle_mutation_service.js",
  );
  assert.ok(lifecycle.blockers.includes("production_export_pending"));
  assert.ok(!lifecycle.blockers.includes("security_rules_baseline_missing"));
  assert.equal(
    fs.existsSync(path.join(projectRoot, lifecycle.nodeSource)),
    true,
  );
  assert.equal(orchestrator.status, "orchestration_ready_offline");
  assert.equal(
    orchestrator.nodeSource,
    "functions/wardrobe_backend_qualification_orchestrator.js",
  );
  assert.ok(orchestrator.blockers.includes("production_endpoint_not_exported"));
  assert.equal(lifecycleEndpoint.status, "endpoint_ready_offline");
  assert.equal(authorityEndpoint.status, "endpoint_ready_offline");
  assert.ok(authorityEndpoint.blockers.includes("production_export_pending"));
  assert.ok(authorityEndpoint.blockers.includes("migration_required"));
  assert.equal(repository.status, "wired_offline");
  assert.equal(
    repository.nodeSource,
    "functions/wardrobe_profile_firestore_repository.js",
  );
  assert.ok(repository.blockers.includes("production_export_pending"));
  assert.ok(!repository.blockers.includes("revision_lifecycle_assignment_required"));
  assert.ok(!repository.blockers.includes("storage_adapter_not_wired"));
  assert.ok(!repository.blockers.includes("authority_endpoint_missing"));
  assert.equal(rules.status, "rules_ready_emulator");
  assert.equal(rules.rulesSource, "firestore.rules");
  assert.ok(!rules.blockers.includes("security_rules_baseline_missing"));
  assert.ok(rules.blockers.includes("deployment_pending"));
  assert.equal(rules.discoveryCompleted, true);
  assert.equal(rules.baselineAbsentInRepo, false);
  assert.equal(rules.deployableBaselinePath, "firestore.rules");
  assert.equal(rules.fragmentReferenceOnly, true);
  assert.equal(
    rules.nodeSource,
    "functions/wardrobe_firestore_rules_baseline_discovery.js",
  );
  assert.equal(
    fs.existsSync(path.join(projectRoot, rules.rulesSource)),
    true,
  );
  assert.equal(prodDeps.status, "production_wiring_ready_unexported");
  assert.ok(!prodDeps.blockers.includes("security_rules_baseline_missing"));
  assert.ok(!prodDeps.blockers.includes("client_write_path_cutover_pending"));
  assert.ok(prodDeps.blockers.includes("migration_required"));
  assert.ok(prodDeps.blockers.includes("deployment_pending"));
  const cutover = BACKEND_CONTRACT_GRAPH.find(
    (item) => item.id === "ClientWritePathCutover");
  assert.ok(cutover);
  assert.equal(cutover.status, "client_write_path_cutover_ready");
  assert.equal(
    cutover.dartSource,
    "lib/Services/wardrobe_write_path_cutover.dart",
  );
  assert.equal(authorityHandler.status, "handler_export_ready");
  assert.equal(authorityHandler.productionExport, true);
  assert.equal(authorityHandler.defaultMode, "disabled");
  assert.ok(!authorityHandler.blockers.includes(
    "flutter_app_check_initialization_pending"));
  assert.equal(lifecycleHandler.status, "handler_export_ready");
  assert.equal(lifecycleHandler.productionExport, true);
  assert.ok(!lifecycleHandler.blockers.includes(
    "flutter_app_check_initialization_pending"));
  const appCheck = BACKEND_CONTRACT_GRAPH.find(
    (item) => item.id === "FlutterFirebaseAppCheck");
  assert.ok(appCheck);
  assert.equal(appCheck.status, "client_app_check_ready");
  assert.equal(
    appCheck.dartSource,
    "lib/Services/firebase_app_check_bootstrap.dart",
  );
  assert.deepEqual([...appCheck.blockers], []);
  assert.ok(!appCheck.blockers.includes(
    "firebase_app_check_console_registration_pending"));
  const switchNode = BACKEND_CONTRACT_GRAPH.find(
    (item) => item.id === "ProductionAuthoritySwitch");
  assert.ok(switchNode);
  assert.equal(switchNode.status, "not_started");
  assert.ok(!switchNode.blockers.includes(
    "flutter_app_check_initialization_pending"));
  assert.ok(!switchNode.blockers.includes(
    "firebase_app_check_console_registration_pending"));
  assert.deepEqual([...switchNode.blockers], [
    "controlled_write_canary_retry_pending",
    "controlled_write_production_activation_approval_pending",
  ]);
  const readyProviders = BACKEND_PROVIDER_GRAPH.filter(
    (item) => item.status === "parity_ready",
  );
  assert.equal(readyProviders.length, 13);
});

test("identity, family, KB, resolver, and mapper input preparation orchestration stages are ready", () => {
  assert.equal(BACKEND_ORCHESTRATION_GRAPH.length, 5);
  const identityStage = BACKEND_ORCHESTRATION_GRAPH.find((item) =>
    item.id === "PrepareVisionIdentityQualificationInput");
  const familyStage = BACKEND_ORCHESTRATION_GRAPH.find((item) =>
    item.id === "PrepareVisionFamilyIdentityInput");
  const kbStage = BACKEND_ORCHESTRATION_GRAPH.find((item) =>
    item.id === "PrepareVisionKnowledgeBasePriorInput");
  const resolverStage = BACKEND_ORCHESTRATION_GRAPH.find((item) =>
    item.id === "PrepareWardrobeProfileResolverInput");
  const mapperStage = BACKEND_ORCHESTRATION_GRAPH.find((item) =>
    item.id === "PrepareQualifiedVisionPersistenceMapperInput");
  assert.equal(identityStage.status, "orchestration_ready");
  assert.equal(identityStage.portableNow, true);
  assert.deepEqual(identityStage.blockers, []);
  assert.equal(familyStage.status, "orchestration_ready");
  assert.equal(familyStage.portableNow, true);
  assert.deepEqual(familyStage.blockers, []);
  assert.equal(familyStage.nodeSource,
    "functions/prepare_vision_family_identity_input.js");
  assert.equal(kbStage.status, "orchestration_ready");
  assert.equal(kbStage.portableNow, true);
  assert.deepEqual(kbStage.blockers, []);
  assert.equal(kbStage.nodeSource,
    "functions/prepare_vision_knowledge_base_prior_input.js");
  assert.equal(resolverStage.status, "orchestration_ready");
  assert.equal(resolverStage.portableNow, true);
  assert.deepEqual(resolverStage.blockers, []);
  assert.equal(resolverStage.nodeSource,
    "functions/prepare_wardrobe_profile_resolver_input.js");
  assert.ok(mapperStage);
  assert.equal(mapperStage.status, "orchestration_ready");
  assert.equal(mapperStage.portableNow, true);
  assert.deepEqual(mapperStage.blockers, []);
  assert.deepEqual(mapperStage.productionBlockers, [
    "migration_required",
    "production_export_pending",
  ]);
  assert.equal(mapperStage.nodeSource,
    "functions/prepare_qualified_vision_persistence_mapper_input.js");
  assert.ok(BACKEND_ORCHESTRATION_STATUSES.includes(familyStage.status));
  assert.equal(fs.existsSync(path.join(projectRoot, familyStage.nodeSource)),
    true);
  assert.equal(fs.existsSync(path.join(projectRoot, kbStage.nodeSource)),
    true);
  assert.equal(fs.existsSync(path.join(projectRoot, resolverStage.nodeSource)),
    true);
  assert.equal(fs.existsSync(path.join(projectRoot, mapperStage.nodeSource)),
    true);
  assert.equal(fs.existsSync(path.join(projectRoot, familyStage.dartSource)),
    true);
});

test("ported provider remains outside production endpoint and persistence code", () => {
  const productionSources = [
    "functions/index.js",
    "functions/vision_v2_shadow.js",
  ].map((item) => fs.readFileSync(path.join(projectRoot, item), "utf8"))
    .join("\n");
  assert.doesNotMatch(productionSources,
    /vision_observation_evidence_provider|VisionObservationEvidenceProvider/);
  assert.doesNotMatch(productionSources,
    /prepare_vision_identity_qualification_input|PrepareVisionIdentityQualificationInput/);
  assert.doesNotMatch(productionSources,
    /prepare_vision_family_identity_input|PrepareVisionFamilyIdentityInput/);
  assert.doesNotMatch(productionSources,
    /prepare_vision_knowledge_base_prior_input|PrepareVisionKnowledgeBasePriorInput/);
  assert.doesNotMatch(productionSources,
    /prepare_wardrobe_profile_resolver_input|PrepareWardrobeProfileResolverInput/);
  assert.doesNotMatch(productionSources,
    /wardrobe_profile_resolver|resolveWardrobeProfile|WardrobeProfileResolver/);
  assert.doesNotMatch(productionSources,
    /wardrobe_knowledge_base_prior_provider|provideWardrobeKnowledgeBasePriors/);
  assert.doesNotMatch(productionSources,
    /vision_identity_qualifier|qualifyVisionIdentity/);
  assert.doesNotMatch(productionSources,
    /VisionFamilyIdentityResolver|vision_family_identity_resolver|resolveVisionFamilyIdentity/);
  assert.doesNotMatch(productionSources,
    /qualified_vision_persistence_mapper|mapQualifiedVisionPersistence|QualifiedVisionPersistenceMapper/);
  assert.doesNotMatch(productionSources,
    /prepare_qualified_vision_persistence_mapper_input|PrepareQualifiedVisionPersistenceMapperInput/);
  assert.doesNotMatch(productionSources,
    /wardrobe_qualification_revision_contract|TrustedRevisionContract|evaluateWriteDecision/);

  const nodeProvider = fs.readFileSync(path.join(
    projectRoot,
    "functions/vision_observation_evidence_provider.js",
  ), "utf8");
  assert.doesNotMatch(nodeProvider,
    /firebase|firestore|persistence|QualifiedVisionPersistenceMapper/);
  const nodeMapper = fs.readFileSync(path.join(
    projectRoot,
    "functions/qualified_vision_persistence_mapper.js",
  ), "utf8");
  assert.doesNotMatch(nodeMapper,
    /require\(["']firebase|firebase-admin|Date\.now\(|Math\.random\(/);
  assert.match(nodeMapper, /casExpectedRevision|firestoreTimestamp/);
  const revisionContract = fs.readFileSync(path.join(
    projectRoot,
    "functions/wardrobe_qualification_revision_contract.js",
  ), "utf8");
  assert.doesNotMatch(revisionContract,
    /require\(["']firebase|firebase-admin|Date\.now\(|Math\.random\(/);
});

test("exactly the approved Node *_provider.js implementations exist", () => {
  const providerFiles = fs.readdirSync(__dirname)
    .filter((name) => name.endsWith("_provider.js"))
    .sort();
  assert.deepEqual(providerFiles, [
    "vision_observation_evidence_provider.js",
    "wardrobe_capability_inference_provider.js",
    "wardrobe_knowledge_base_prior_provider.js",
  ]);
});
