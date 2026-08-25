"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  buildWardrobeProfileResolverInputParityEntry,
  runWardrobeProfileResolverInputParity,
} = require("./backend_wardrobe_profile_resolver_input_parity");
const {
  FORBIDDEN_AUTHORITY_FIELDS,
  STAGE_ID,
  STAGE_VERSION,
  prepareWardrobeProfileResolverInput,
} = require("./prepare_wardrobe_profile_resolver_input");
const {canonicalBytes} = require("./backend_provider_oracle_parity");

const root = path.resolve(__dirname, "..");
const manifestOut = path.join(root, "test/fixtures/backend_qualification/" +
  "backend_wardrobe_profile_resolver_input_orchestration_manifest.json");

function baseObservation(overrides = {}) {
  return {
    id: "observation:test:visual.coverage",
    property: "visual.coverage",
    value: "partial",
    source: "visual_observation",
    nature: "observed",
    confidence: 0.8,
    method: "vision_observation",
    createdAt: "2000-01-01T00:00:00.000Z",
    modelVersion: "gpt-4o-mini",
    sourceReference: "fixture://test/view_1",
    active: true,
    verified: false,
    ...overrides,
  };
}

function baseIdentity(overrides = {}) {
  return {
    id: "vision-identity:test:boots:qualified",
    property: "identity.canonicalType",
    value: "boots",
    source: "ai_inference",
    nature: "inferred",
    confidence: 0.65,
    method: "vision_v2_identity_candidate:qualified",
    createdAt: "2000-01-01T00:00:00.000Z",
    modelVersion: "gpt-4o-mini",
    sourceReference: "vision-identity:test:boots",
    active: true,
    verified: false,
    ...overrides,
  };
}

function baseCapability(overrides = {}) {
  return {
    id: "capability:test:walkingComfort",
    property: "capabilities.walkingComfort",
    value: "high",
    source: "ai_inference",
    nature: "inferred",
    confidence: 0.55,
    method: "capability_inference",
    createdAt: "2000-01-01T00:00:00.000Z",
    modelVersion: "capability-inference-v1",
    active: true,
    verified: false,
    ...overrides,
  };
}

function baseKb(overrides = {}) {
  return {
    id: "kb-prior:boots:capabilities.warmth",
    property: "capabilities.warmth",
    value: 6,
    source: "knowledge_base_prior",
    nature: "defaulted",
    confidence: 0.35,
    method: "clothing_knowledge_base_prior",
    createdAt: "1970-01-01T00:00:00.000Z",
    modelVersion: "wardrobe-kb-prior-provider-v1",
    sourceReference: "kb:boots",
    dependsOnCanonicalType: "boots",
    active: true,
    verified: false,
    ...overrides,
  };
}

function prepareArgs(overrides = {}) {
  return {
    itemId: "shoe_without_outsole",
    resolverCompatibilityVersion: 1,
    observationEvidence: [baseObservation()],
    qualifiedIdentityEvidence: [baseIdentity()],
    capabilityEvidence: [baseCapability()],
    knowledgeBaseEvidence: [baseKb()],
    ...overrides,
  };
}

test("prepare stage constants", () => {
  assert.equal(STAGE_ID, "PrepareWardrobeProfileResolverInput");
  assert.equal(STAGE_VERSION, "wardrobe-profile-resolver-input-v1");
  assert.ok(FORBIDDEN_AUTHORITY_FIELDS.includes("evidence"));
  assert.ok(FORBIDDEN_AUTHORITY_FIELDS.includes("resolvedProfile"));
});

test("empty evidence groups", () => {
  const result = prepareWardrobeProfileResolverInput(prepareArgs({
    observationEvidence: [],
    qualifiedIdentityEvidence: [],
    capabilityEvidence: [],
    knowledgeBaseEvidence: [],
  }));
  assert.equal(result.itemId, "shoe_without_outsole");
  assert.deepEqual(result.evidence, []);
});

test("observation evidence only", () => {
  const result = prepareWardrobeProfileResolverInput(prepareArgs({
    qualifiedIdentityEvidence: [],
    capabilityEvidence: [],
    knowledgeBaseEvidence: [],
  }));
  assert.equal(result.evidence.length, 1);
  assert.equal(result.evidence[0].source, "visual_observation");
});

test("capability evidence only", () => {
  const result = prepareWardrobeProfileResolverInput(prepareArgs({
    observationEvidence: [],
    qualifiedIdentityEvidence: [],
    knowledgeBaseEvidence: [],
  }));
  assert.equal(result.evidence.length, 1);
  assert.equal(result.evidence[0].property, "capabilities.walkingComfort");
});

test("identity evidence only", () => {
  const result = prepareWardrobeProfileResolverInput(prepareArgs({
    observationEvidence: [],
    capabilityEvidence: [],
    knowledgeBaseEvidence: [],
  }));
  assert.equal(result.evidence.length, 1);
  assert.equal(result.evidence[0].property, "identity.canonicalType");
});

test("KB evidence only", () => {
  const result = prepareWardrobeProfileResolverInput(prepareArgs({
    observationEvidence: [],
    qualifiedIdentityEvidence: [],
    capabilityEvidence: [],
  }));
  assert.equal(result.evidence.length, 1);
  assert.equal(result.evidence[0].source, "knowledge_base_prior");
});

test("combined evidence groups preserve call-site order", () => {
  const result = prepareWardrobeProfileResolverInput(prepareArgs());
  assert.deepEqual(result.evidence.map((item) => item.source), [
    "visual_observation",
    "ai_inference",
    "ai_inference",
    "knowledge_base_prior",
  ]);
  assert.deepEqual(result.evidence.map((item) => item.property), [
    "visual.coverage",
    "identity.canonicalType",
    "capabilities.walkingComfort",
    "capabilities.warmth",
  ]);
});

test("family report present but intentionally excluded", () => {
  const without = prepareWardrobeProfileResolverInput(prepareArgs());
  const withFamily = prepareWardrobeProfileResolverInput(prepareArgs({
    familyIdentityReport: {
      state: "supported",
      resolvedFamily: "footwear",
    },
  }));
  assert.deepEqual(without, withFamily);
  assert.equal(
    withFamily.evidence.some((item) => item.property === "identity.family"),
    false,
  );
});

test("familyEvidence authority field is rejected", () => {
  assert.throws(() => prepareWardrobeProfileResolverInput(prepareArgs({
    familyEvidence: [baseIdentity({property: "identity.family"})],
  })), /forged_authority_field:familyEvidence|family_evidence_not_part/);
});

test("inactive evidence preserved", () => {
  const result = prepareWardrobeProfileResolverInput(prepareArgs({
    observationEvidence: [baseObservation({active: false})],
    qualifiedIdentityEvidence: [],
    capabilityEvidence: [],
    knowledgeBaseEvidence: [],
  }));
  assert.equal(result.evidence[0].active, false);
});

test("unknown evidence preserved", () => {
  const result = prepareWardrobeProfileResolverInput(prepareArgs({
    observationEvidence: [baseObservation({
      value: null,
      valueState: "unknown",
      confidence: 0,
    })],
    qualifiedIdentityEvidence: [],
    capabilityEvidence: [],
    knowledgeBaseEvidence: [],
  }));
  assert.equal(result.evidence[0].valueState, "unknown");
  assert.equal(result.evidence[0].value, null);
});

test("not_visible preserved", () => {
  const result = prepareWardrobeProfileResolverInput(prepareArgs({
    observationEvidence: [baseObservation({
      value: null,
      valueState: "not_visible",
      confidence: 0.2,
    })],
    qualifiedIdentityEvidence: [],
    capabilityEvidence: [],
    knowledgeBaseEvidence: [],
  }));
  assert.equal(result.evidence[0].valueState, "not_visible");
});

test("not_applicable preserved", () => {
  const result = prepareWardrobeProfileResolverInput(prepareArgs({
    observationEvidence: [baseObservation({
      value: null,
      valueState: "not_applicable",
      confidence: 0.9,
    })],
    qualifiedIdentityEvidence: [],
    capabilityEvidence: [],
    knowledgeBaseEvidence: [],
  }));
  assert.equal(result.evidence[0].valueState, "not_applicable");
});

test("duplicate identical evidence ID fails closed", () => {
  assert.throws(() => prepareWardrobeProfileResolverInput(prepareArgs({
    observationEvidence: [
      baseObservation(),
      baseObservation({property: "visual.fit", value: "regular"}),
    ],
    qualifiedIdentityEvidence: [],
    capabilityEvidence: [],
    knowledgeBaseEvidence: [],
  })), /duplicate_evidence_id/);
});

test("duplicate conflicting evidence ID fails closed", () => {
  assert.throws(() => prepareWardrobeProfileResolverInput(prepareArgs({
    observationEvidence: [
      baseObservation(),
      baseObservation({value: "full"}),
    ],
    qualifiedIdentityEvidence: [],
    capabilityEvidence: [],
    knowledgeBaseEvidence: [],
  })), /duplicate_evidence_id/);
});

test("multiple evidence for same property allowed with distinct IDs", () => {
  const result = prepareWardrobeProfileResolverInput(prepareArgs({
    observationEvidence: [
      baseObservation({id: "observation:a"}),
      baseObservation({id: "observation:b", value: "full"}),
    ],
    qualifiedIdentityEvidence: [],
    capabilityEvidence: [],
    knowledgeBaseEvidence: [],
  }));
  assert.equal(result.evidence.length, 2);
  assert.equal(result.evidence[0].property, result.evidence[1].property);
});

test("observation evidence is sorted by id", () => {
  const result = prepareWardrobeProfileResolverInput(prepareArgs({
    observationEvidence: [
      baseObservation({id: "observation:z", property: "visual.fit", value: "regular"}),
      baseObservation({id: "observation:a"}),
    ],
    qualifiedIdentityEvidence: [],
    capabilityEvidence: [],
    knowledgeBaseEvidence: [],
  }));
  assert.deepEqual(result.evidence.map((item) => item.id), [
    "observation:a",
    "observation:z",
  ]);
});

test("null versus omitted valueState", () => {
  const known = prepareWardrobeProfileResolverInput(prepareArgs({
    qualifiedIdentityEvidence: [],
    capabilityEvidence: [],
    knowledgeBaseEvidence: [],
  }));
  assert.equal(Object.hasOwn(known.evidence[0], "valueState"), false);
  const unknown = prepareWardrobeProfileResolverInput(prepareArgs({
    observationEvidence: [baseObservation({
      value: null,
      valueState: "unknown",
      confidence: 0,
    })],
    qualifiedIdentityEvidence: [],
    capabilityEvidence: [],
    knowledgeBaseEvidence: [],
  }));
  assert.equal(unknown.evidence[0].valueState, "unknown");
});

test("invalid confidence fails", () => {
  assert.throws(() => prepareWardrobeProfileResolverInput(prepareArgs({
    observationEvidence: [baseObservation({confidence: 1.5})],
  })), /evidence_confidence_invalid/);
});

test("invalid property path for identity fails", () => {
  assert.throws(() => prepareWardrobeProfileResolverInput(prepareArgs({
    qualifiedIdentityEvidence: [
      baseIdentity({property: "identity.brand"}),
    ],
  })), /identity_property_invalid/);
});

test("invalid source fails", () => {
  assert.throws(() => prepareWardrobeProfileResolverInput(prepareArgs({
    observationEvidence: [baseObservation({source: "not_a_source"})],
  })), /evidence_source_invalid/);
});

test("forged KB evidence in observation fails", () => {
  assert.throws(() => prepareWardrobeProfileResolverInput(prepareArgs({
    observationEvidence: [baseObservation({
      source: "knowledge_base_prior",
    })],
  })), /observation_source_invalid|forged_kb_prior_evidence/);
});

test("forged client resolved evidence fails", () => {
  assert.throws(() => prepareWardrobeProfileResolverInput(prepareArgs({
    resolvedProfile: {itemId: "x"},
  })), /forged_authority_field:resolvedProfile/);
  assert.throws(() => prepareWardrobeProfileResolverInput(prepareArgs({
    evidence: [],
  })), /forged_authority_field:evidence/);
});

test("invalid resolver compatibility version fails", () => {
  assert.throws(() => prepareWardrobeProfileResolverInput(prepareArgs({
    resolverCompatibilityVersion: 99,
  })), /resolver_compatibility_version_unsupported/);
});

test("empty itemId fails", () => {
  assert.throws(() => prepareWardrobeProfileResolverInput(prepareArgs({
    itemId: "",
  })), /item_id_required/);
});

test("deterministic serialization", () => {
  const first = prepareWardrobeProfileResolverInput(prepareArgs());
  const second = prepareWardrobeProfileResolverInput(prepareArgs());
  assert.deepEqual(
    Array.from(canonicalBytes(first)),
    Array.from(canonicalBytes(second)),
  );
});

test("immutable input and output", () => {
  const args = prepareArgs();
  const result = prepareWardrobeProfileResolverInput(args);
  assert.throws(() => {
    result.evidence.push(baseObservation({id: "x"}));
  }, TypeError);
  assert.throws(() => {
    result.itemId = "mutated";
  }, TypeError);
  args.observationEvidence[0].value = "mutated-input";
  assert.equal(result.evidence[0].value, "partial");
});

test("compatibility fallback group appends after KB", () => {
  const result = prepareWardrobeProfileResolverInput(prepareArgs({
    compatibilityFallbackEvidence: [{
      id: "compat:brand",
      property: "identity.brand",
      value: "Compat",
      source: "label_metadata",
      nature: "observed",
      confidence: 0.4,
      method: "compatibility_projection",
      createdAt: "2000-01-01T00:00:00.000Z",
      active: true,
      verified: false,
    }],
  }));
  assert.equal(result.evidence.at(-1).id, "compat:brand");
  assert.equal(result.evidence.at(-1).source, "label_metadata");
});

test("legacy fallback group appends after KB", () => {
  const result = prepareWardrobeProfileResolverInput(prepareArgs({
    legacyFallbackEvidence: [{
      id: "legacy:brand",
      property: "identity.brand",
      value: "Legacy",
      source: "legacy_fallback",
      nature: "unknown",
      confidence: 0.1,
      method: "legacy_adapter",
      createdAt: "1970-01-01T00:00:00.000Z",
      active: true,
      verified: false,
    }],
  }));
  assert.equal(result.evidence.at(-1).source, "legacy_fallback");
});

test("user-correction group appends last", () => {
  const result = prepareWardrobeProfileResolverInput(prepareArgs({
    legacyFallbackEvidence: [{
      id: "legacy:brand",
      property: "identity.brand",
      value: "Legacy",
      source: "legacy_fallback",
      nature: "unknown",
      confidence: 0.1,
      method: "legacy_adapter",
      createdAt: "1970-01-01T00:00:00.000Z",
      active: true,
      verified: false,
    }],
    userCorrectionEvidence: [{
      id: "user:brand",
      property: "identity.brand",
      value: "User",
      source: "user_correction",
      nature: "observed",
      confidence: 1,
      method: "user_edit",
      createdAt: "2000-01-01T00:00:00.000Z",
      active: true,
      verified: true,
    }],
  }));
  assert.equal(result.evidence.at(-1).source, "user_correction");
  assert.equal(result.evidence.at(-2).source, "legacy_fallback");
});

test("untrusted KB evidence without kb-prior id fails", () => {
  assert.throws(() => prepareWardrobeProfileResolverInput(prepareArgs({
    knowledgeBaseEvidence: [baseKb({id: "forged-kb"})],
  })), /untrusted_kb_prior_evidence_id/);
});

test("8/8 resolver providerInput parity with family exclusion", () => {
  const report = runWardrobeProfileResolverInputParity();
  assert.equal(report.passedScenarios, 8);
  assert.equal(report.failedScenarios, 0);
  assert.equal(report.parityStatus, "orchestration_ready");
  assert.equal(report.deterministic, true);
  assert.equal(
    report.productionAuthorityVerdict,
    "resolver_input_builder_sufficient_for_node_port",
  );
  for (const scenario of report.scenarios) {
    assert.equal(scenario.passed, true, scenario.scenarioId);
    assert.equal(scenario.fieldParity.itemId, true);
    assert.equal(scenario.fieldParity.evidenceOrdering, true);
    assert.equal(scenario.membership.family, 0);
    assert.equal(scenario.membership.fallback, 0);
    assert.equal(scenario.membership.userCorrection, 0);
  }
});

test("orchestration manifest is stable and updates on write", () => {
  const report = runWardrobeProfileResolverInputParity();
  const entry = buildWardrobeProfileResolverInputParityEntry(report);
  const first = canonicalBytes(entry);
  const second = canonicalBytes(
    buildWardrobeProfileResolverInputParityEntry(
      runWardrobeProfileResolverInputParity()));
  assert.deepEqual(Array.from(first), Array.from(second));
  fs.mkdirSync(path.dirname(manifestOut), {recursive: true});
  fs.writeFileSync(manifestOut, first);
  assert.deepEqual(fs.readFileSync(manifestOut), Buffer.from(first));
  assert.equal(
    crypto.createHash("sha256").update(fs.readFileSync(
      path.join(root, "functions/prepare_wardrobe_profile_resolver_input.js")))
      .digest("hex"),
    entry.nodeImplementationSha256,
  );
});

test("prepare stage remains production isolated", () => {
  const production = [
    fs.readFileSync(path.join(root, "functions/index.js"), "utf8"),
    fs.readFileSync(path.join(root, "functions/vision_v2_shadow.js"), "utf8"),
  ].join("\n");
  assert.doesNotMatch(production,
    /prepare_wardrobe_profile_resolver_input|PrepareWardrobeProfileResolverInput/);
  assert.equal(
    fs.existsSync(path.join(root, "functions/wardrobe_profile_resolver.js")),
    true,
  );
  assert.doesNotMatch(production,
    /wardrobe_profile_resolver|resolveWardrobeProfile/);
});
