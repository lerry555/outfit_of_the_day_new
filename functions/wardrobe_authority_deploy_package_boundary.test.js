"use strict";

/**
 * Isolated Functions deploy-package import test.
 *
 * Copies only the contents of functions/ (minus node_modules rebuild via
 * package.json install of production deps) into a temp directory with NO
 * access to repo lib/, test/, or tool/, then requires index.js.
 */

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {spawnSync} = require("node:child_process");
const test = require("node:test");

const FUNCTIONS_ROOT = path.resolve(__dirname);
const REPO_ROOT = path.resolve(__dirname, "..");

const SKIP_DIR_NAMES = new Set([
  "node_modules",
  ".git",
]);

function copyFunctionsTree(srcDir, destDir) {
  fs.mkdirSync(destDir, {recursive: true});
  for (const entry of fs.readdirSync(srcDir, {withFileTypes: true})) {
    if (SKIP_DIR_NAMES.has(entry.name)) continue;
    if (entry.name.startsWith("_audit_")) continue;
    const from = path.join(srcDir, entry.name);
    const to = path.join(destDir, entry.name);
    if (entry.isDirectory()) {
      copyFunctionsTree(from, to);
    } else if (entry.isFile()) {
      fs.copyFileSync(from, to);
    }
  }
}

function assertNoRepoLeak(packageRoot) {
  assert.equal(fs.existsSync(path.join(packageRoot, "lib")), false);
  assert.equal(fs.existsSync(path.join(packageRoot, "test")), false);
  assert.equal(fs.existsSync(path.join(packageRoot, "tool")), false);
  assert.equal(
    fs.existsSync(path.join(packageRoot,
      "domain", "wardrobe_profile", "vision_family_identity.dart")),
    false);
}

test("isolated deploy package can require index.js and export callables", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "ootd-fn-pkg-"));
  const packageRoot = path.join(tmp, "functions");
  try {
    copyFunctionsTree(FUNCTIONS_ROOT, packageRoot);
    assertNoRepoLeak(packageRoot);
    // Ensure artifacts are present inside the package.
    assert.equal(fs.existsSync(path.join(packageRoot,
      "artifacts", "vision_canonical_family_registry_v1.json")), true);
    assert.equal(fs.existsSync(path.join(packageRoot,
      "artifacts", "canonical_resolver_structured_taxonomy_v1.json")), true);
    assert.equal(fs.existsSync(path.join(packageRoot,
      "artifacts", "clothing_knowledge_base_prior_v1.json")), true);

    // Reuse the workspace production node_modules (Firebase also resolves deps
    // from package.json). Do not expose repo lib/test/tool.
    const nmSrc = path.join(FUNCTIONS_ROOT, "node_modules");
    assert.equal(fs.existsSync(nmSrc), true, "functions/node_modules required");
    fs.cpSync(nmSrc, path.join(packageRoot, "node_modules"), {recursive: true});

    const probe = `
      const exportsMap = require('./index.js');
      const life = exportsMap.wardrobeRevisionLifecycle;
      const auth = exportsMap.wardrobeQualificationAuthority;
      if (typeof life !== 'function' || typeof auth !== 'function') {
        throw new Error('callable_exports_missing');
      }
      if (!life.__trigger || !auth.__trigger) {
        throw new Error('callable_trigger_metadata_missing');
      }
      const {DEFAULT_MODE} = require('./wardrobe_authority_runtime_mode');
      if (DEFAULT_MODE !== 'disabled') {
        throw new Error('default_mode_not_disabled:' + DEFAULT_MODE);
      }
      console.log(JSON.stringify({
        ok: true,
        lifecycleRegions: life.__trigger.regions,
        authorityRegions: auth.__trigger.regions,
        defaultMode: DEFAULT_MODE,
      }));
    `;
    const run = spawnSync(
      process.execPath,
      ["-e", probe],
      {
        cwd: packageRoot,
        encoding: "utf8",
        timeout: 60000,
        env: {...process.env, NODE_ENV: "test"},
      },
    );
    if (run.status !== 0) {
      assert.fail(
        `isolated_require_failed status=${run.status}\n` +
        `stdout=${run.stdout}\nstderr=${run.stderr}`);
    }
    const line = run.stdout.trim().split(/\r?\n/).filter(Boolean).pop();
    const payload = JSON.parse(line);
    assert.equal(payload.ok, true);
    assert.deepEqual(payload.lifecycleRegions, ["us-east1"]);
    assert.deepEqual(payload.authorityRegions, ["us-east1"]);
    assert.equal(payload.defaultMode, "disabled");

    // Guard: package must not contain Dart sources.
    const dartHits = [];
    function walk(dir) {
      for (const entry of fs.readdirSync(dir, {withFileTypes: true})) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) {
          if (entry.name === "node_modules") continue;
          walk(full);
        } else if (entry.name.endsWith(".dart")) {
          dartHits.push(path.relative(packageRoot, full));
        }
      }
    }
    walk(packageRoot);
    assert.deepEqual(dartHits, []);
  } finally {
    fs.rmSync(tmp, {recursive: true, force: true});
  }
});

test("production import graph has no ../lib runtime path hints", () => {
  const audit = spawnSync(
    process.execPath,
    [path.join(FUNCTIONS_ROOT, "_audit_prod_import_graph.js")],
    {cwd: REPO_ROOT, encoding: "utf8"},
  );
  assert.equal(audit.status, 0, audit.stderr);
  const report = JSON.parse(audit.stdout);
  const libHints = report.pathHints.filter((h) => h.hint.includes("../lib/"));
  assert.deepEqual(libHints, []);
});
