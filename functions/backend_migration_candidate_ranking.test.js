"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  COMPLETED_IDS,
  MIGRATION_CANDIDATES,
  rankCandidates,
  scoreCandidate,
} = require("./backend_migration_candidate_ranking");

const root = path.resolve(__dirname, "..");

test("candidate ranking is complete deterministic and source-backed", () => {
  assert.equal(MIGRATION_CANDIDATES.length, 12);
  assert.equal(new Set(MIGRATION_CANDIDATES.map((item) => item.id)).size, 12);
  assert.deepEqual(rankCandidates(), rankCandidates());
  for (const item of MIGRATION_CANDIDATES) {
    if (item.id === "WardrobeProfilePersistenceRepositoryAdapter") {
      assert.equal(fs.existsSync(path.join(root, item.dartSource)), true,
        item.id);
      continue;
    }
    assert.equal(fs.existsSync(path.join(root, item.dartSource)), true, item.id);
    assert.equal(Number.isInteger(scoreCandidate(item)), true, item.id);
  }
});

test("repository adapter ranks next after trusted revision contract foundation", () => {
  const ranking = rankCandidates();
  assert.equal(ranking.some((item) =>
    item.id === "QualifiedVisionPersistenceMapper"), false);
  assert.equal(ranking.some((item) =>
    item.id === "WardrobeProfilePersistenceRepositoryAdapter"), false);
  assert.equal(ranking.length, 0);
  assert.ok(COMPLETED_IDS.includes("QualifiedVisionPersistenceMapper"));
  assert.ok(COMPLETED_IDS.includes(
    "WardrobeProfilePersistenceRepositoryAdapter"));
});

test("ranking does not mistake boundary types for providers", () => {
  const byId = new Map(MIGRATION_CANDIDATES.map((item) => [item.id, item]));
  assert.equal(byId.get("VisionIdentityQualification").kind,
    "private_orchestration_stage");
  assert.equal(byId.get("WardrobeProfileResolver").kind, "final_resolver");
  assert.equal(byId.get("QualifiedVisionPersistenceMapper").kind, "mapper");
  assert.equal(byId.get("WardrobeProfilePersistenceRepositoryAdapter").kind,
    "repository_adapter");
  assert.equal(byId.get("CanonicalObservationConsistencyValidator").kind,
    "validator");
});

test("audit ranking is absent from production entry points", () => {
  const production = [
    fs.readFileSync(path.join(__dirname, "index.js"), "utf8"),
    fs.readFileSync(path.join(__dirname, "vision_v2_shadow.js"), "utf8"),
  ].join("\n");
  assert.doesNotMatch(production, /backend_migration_candidate_ranking/);
});
