"use strict";

const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {
  discoverFirestoreRulesBaseline,
  FRAGMENT_REL,
  ROOT_RULES_REL,
  PROJECT_ID,
} = require("./wardrobe_firestore_rules_baseline_discovery");

const {
  evaluateWardrobeAuthorityExportReadiness,
  assertWardrobeAuthorityExportReady,
  phase9cRExportReadinessState,
} = require("./wardrobe_authority_export_gate");

const {
  BACKEND_CONTRACT_GRAPH,
} = require("./backend_provider_dependency_graph");

describe("Phase 5.3B-9C-R Firestore Rules baseline merge discovery", () => {
  it("1 baseline verdict is deployable_rules_baseline_found", () => {
    const d = discoverFirestoreRulesBaseline();
    assert.equal(d.baselineVerdict, "deployable_rules_baseline_found");
    assert.equal(d.stopCondition, null);
    assert.equal(d.securityRulesBaselineMissing, false);
  });

  it("2 merge verdict is backend_boundary_merge_implementable", () => {
    assert.equal(
      discoverFirestoreRulesBaseline().mergeVerdict,
      "backend_boundary_merge_implementable");
  });

  it("3 emulator verdict is rules_emulator_validation_available", () => {
    assert.equal(
      discoverFirestoreRulesBaseline().emulatorVerdict,
      "rules_emulator_validation_available");
  });

  it("4 export discovery reports security_gate_ready_for_future_export", () => {
    assert.equal(
      discoverFirestoreRulesBaseline().exportVerdict,
      "security_gate_ready_for_future_export");
  });

  it("5 firebase.json binds firestore.rules", () => {
    const d = discoverFirestoreRulesBaseline();
    assert.equal(d.firebaseJson.hasFirestoreBlock, true);
    assert.equal(d.firebaseJson.configuredRules, ROOT_RULES_REL);
    assert.equal(d.firebaseJson.boundToBaseline, true);
  });

  it("6 root firestore.rules exists with boundary merge", () => {
    const d = discoverFirestoreRulesBaseline();
    assert.equal(d.rootRules.exists, true);
    assert.equal(d.rootRules.boundaryMerged, true);
    assert.ok(d.rootRules.sha256);
    const text = fs.readFileSync(
      path.resolve(__dirname, "..", ROOT_RULES_REL), "utf8");
    assert.match(text, /wardrobeBackendOwnedKeys/);
    assert.doesNotMatch(text, /security_rules_baseline_missing/);
  });

  it("7 fragment remains reference-only", () => {
    const d = discoverFirestoreRulesBaseline();
    assert.equal(d.fragment.exists, true);
    assert.equal(d.fragment.path, FRAGMENT_REL);
    assert.equal(d.fragment.deployableAlone, false);
    assert.equal(d.fragment.referenceOnly, true);
  });

  it("8 project alias unchanged", () => {
    const d = discoverFirestoreRulesBaseline();
    assert.equal(d.projectId, PROJECT_ID);
    assert.equal(d.projectAliases.default, PROJECT_ID);
  });

  it("9 merge performed; export still not fully ready", () => {
    const d = discoverFirestoreRulesBaseline();
    assert.equal(d.mergePerformed, true);
    assert.equal(d.firebaseJsonUpdated, true);
    assert.equal(d.exportGateCleared, false);
  });

  it("10 export gate drops security_rules_baseline_missing only", () => {
    const readiness = evaluateWardrobeAuthorityExportReadiness(
      phase9cRExportReadinessState());
    assert.equal(readiness.ready, false);
    assert.ok(!readiness.blockers.includes("security_rules_baseline_missing"));
    assert.ok(readiness.blockers.includes("client_write_path_cutover_pending"));
    assert.ok(readiness.blockers.includes("migration_required"));
    assert.ok(readiness.blockers.includes("deployment_pending"));
    assert.throws(
      () => assertWardrobeAuthorityExportReady(phase9cRExportReadinessState()),
      /export_blocked/);
  });

  it("10b phase10a also drops client_write_path_cutover_pending", () => {
    const {
      phase10aExportReadinessState,
    } = require("./wardrobe_authority_export_gate");
    const readiness = evaluateWardrobeAuthorityExportReadiness(
      phase10aExportReadinessState());
    assert.equal(readiness.ready, false);
    assert.ok(!readiness.blockers.includes("security_rules_baseline_missing"));
    assert.ok(!readiness.blockers.includes("client_write_path_cutover_pending"));
    assert.ok(readiness.blockers.includes("migration_required"));
    assert.ok(readiness.blockers.includes("deployment_pending"));
  });

  it("11 SecurityRulesBoundary is rules_ready_emulator", () => {
    const node = BACKEND_CONTRACT_GRAPH.find(
      (n) => n.id === "SecurityRulesBoundary");
    assert.ok(node);
    assert.equal(node.status, "rules_ready_emulator");
    assert.ok(!node.blockers.includes("security_rules_baseline_missing"));
    assert.ok(node.blockers.includes("deployment_pending"));
    assert.equal(node.deployableBaselinePath, "firestore.rules");
  });

  it("12 production deps no longer list security_rules_baseline_missing", () => {
    const node = BACKEND_CONTRACT_GRAPH.find(
      (n) => n.id === "WardrobeAuthorityProductionDependencies");
    assert.ok(!node.blockers.includes("security_rules_baseline_missing"));
    assert.ok(!node.blockers.includes("client_write_path_cutover_pending"));
    assert.ok(node.blockers.includes("migration_required"));
    assert.ok(node.blockers.includes("deployment_pending"));
  });

  it("12b ClientWritePathCutover is ready", () => {
    const node = BACKEND_CONTRACT_GRAPH.find(
      (n) => n.id === "ClientWritePathCutover");
    assert.ok(node);
    assert.equal(node.status, "client_write_path_cutover_ready");
  });

  it("13 @firebase/rules-unit-testing is installed", () => {
    assert.equal(
      discoverFirestoreRulesBaseline().rulesUnitTestingInstalled,
      true);
  });
});
