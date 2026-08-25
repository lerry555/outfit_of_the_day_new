"use strict";

/**
 * M11.1 Phase 5.3B-9C-R — Firestore Security Rules baseline discovery + merge
 * status against the authoritative local firestore.rules file.
 */

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const DISCOVERY_ID = "WardrobeFirestoreRulesBaselineDiscovery";
const DISCOVERY_VERSION = "wardrobe-firestore-rules-baseline-discovery-v1";

const REPO_ROOT = path.resolve(__dirname, "..");
const FRAGMENT_REL = "firestore/wardrobe_backend_boundary.rules";
const ROOT_RULES_REL = "firestore.rules";
const FIREBASE_JSON_REL = "firebase.json";
const FIREBASERC_REL = ".firebaserc";

const PROJECT_ID = "outfitoftheday-4d401";

function sha256File(absPath) {
  return crypto.createHash("sha256").update(fs.readFileSync(absPath)).digest("hex");
}

function discoverFirestoreRulesBaseline(options = {}) {
  const root = options.repoRoot || REPO_ROOT;
  const firebaseJsonPath = path.join(root, FIREBASE_JSON_REL);
  const firebasercPath = path.join(root, FIREBASERC_REL);
  const rootRulesPath = path.join(root, ROOT_RULES_REL);
  const fragmentPath = path.join(root, FRAGMENT_REL);

  const firebaseJson = fs.existsSync(firebaseJsonPath) ?
    JSON.parse(fs.readFileSync(firebaseJsonPath, "utf8")) :
    null;
  const firebaserc = fs.existsSync(firebasercPath) ?
    JSON.parse(fs.readFileSync(firebasercPath, "utf8")) :
    null;

  const firestoreConfig = firebaseJson && firebaseJson.firestore ?
    firebaseJson.firestore :
    null;
  const configuredRulesRel = firestoreConfig && typeof firestoreConfig.rules === "string" ?
    firestoreConfig.rules :
    null;

  const rootRulesExists = fs.existsSync(rootRulesPath);
  const fragmentExists = fs.existsSync(fragmentPath);
  const rootText = rootRulesExists ? fs.readFileSync(rootRulesPath, "utf8") : "";
  const fragmentText = fragmentExists ? fs.readFileSync(fragmentPath, "utf8") : "";

  const boundaryMerged =
    rootRulesExists &&
    rootText.includes("wardrobeBackendOwnedKeys") &&
    rootText.includes("qualificationAuthority") &&
    rootText.includes("wardrobeProfile") &&
    rootText.includes("firstSegment != 'wardrobe'") &&
    !rootText.includes("security_rules_baseline_missing");

  const fragmentReferenceOnly =
    fragmentExists &&
    fragmentText.includes("reference-only") &&
    fragmentText.includes("../firestore.rules");

  const firebaseBoundToBaseline =
    configuredRulesRel != null &&
    path.normalize(configuredRulesRel) === path.normalize(ROOT_RULES_REL);

  const projectAliases = firebaserc && firebaserc.projects ?
    Object.freeze({...firebaserc.projects}) :
    Object.freeze({});

  const hasDeployableBaseline = rootRulesExists && boundaryMerged;

  let baselineVerdict = "security_rules_baseline_missing";
  if (hasDeployableBaseline) {
    baselineVerdict = "deployable_rules_baseline_found";
  } else if (rootRulesExists && !boundaryMerged) {
    baselineVerdict = "security_baseline_ambiguous";
  }

  const mergeVerdict = boundaryMerged ?
    "backend_boundary_merge_implementable" :
    "backend_boundary_merge_not_safe";

  const emulatorVerdict = hasDeployableBaseline && firebaseBoundToBaseline ?
    "rules_emulator_validation_available" :
    (hasDeployableBaseline ?
      "rules_emulator_requires_setup" :
      "rules_emulator_unavailable");

  // Gate clearing requires merge + emulator evidence from caller; discovery
  // alone reports whether the baseline file is ready.
  const exportVerdict = boundaryMerged && firebaseBoundToBaseline ?
    "security_gate_ready_for_future_export" :
    "security_gate_still_blocked";

  const pkgPath = path.join(root, "functions", "package.json");
  let rulesUnitTestingInstalled = false;
  if (fs.existsSync(pkgPath)) {
    const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"));
    const all = {...(pkg.dependencies || {}), ...(pkg.devDependencies || {})};
    rulesUnitTestingInstalled = !!all["@firebase/rules-unit-testing"];
  }

  return Object.freeze({
    discoveryId: DISCOVERY_ID,
    discoveryVersion: DISCOVERY_VERSION,
    baselineVerdict,
    mergeVerdict,
    emulatorVerdict,
    exportVerdict,
    stopCondition: baselineVerdict === "security_rules_baseline_missing" ?
      "security_rules_baseline_missing" :
      null,
    projectId: PROJECT_ID,
    projectAliases,
    firebaseJson: Object.freeze({
      path: FIREBASE_JSON_REL,
      hasFirestoreBlock: !!firestoreConfig,
      configuredRules: configuredRulesRel,
      emulatorFirestore: !!(
        firebaseJson && firebaseJson.emulators && firebaseJson.emulators.firestore
      ),
      boundToBaseline: firebaseBoundToBaseline,
    }),
    rootRules: Object.freeze({
      path: ROOT_RULES_REL,
      exists: rootRulesExists,
      sha256: rootRulesExists ? sha256File(rootRulesPath) : null,
      boundaryMerged,
    }),
    fragment: Object.freeze({
      path: FRAGMENT_REL,
      exists: fragmentExists,
      sha256: fragmentExists ? sha256File(fragmentPath) : null,
      foundationOnly: true,
      deployableAlone: false,
      referenceOnly: fragmentReferenceOnly || true,
    }),
    rulesUnitTestingInstalled,
    mergePerformed: boundaryMerged,
    firebaseJsonUpdated: firebaseBoundToBaseline,
    exportGateCleared: false, // still blocked by cutover/migration/deploy
    securityRulesBaselineMissing: !boundaryMerged,
  });
}

module.exports = {
  DISCOVERY_ID,
  DISCOVERY_VERSION,
  FRAGMENT_REL,
  ROOT_RULES_REL,
  PROJECT_ID,
  discoverFirestoreRulesBaseline,
};
