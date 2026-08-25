"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildVisionV2Prompt,
  buildVisionV2ResponseFormat,
  createVisionV2ShadowHandler,
  PROPERTY_CONFIDENCE_RUBRIC,
  parseVisionV2Response,
  runVisionV2ShadowBatch,
} = require("./vision_v2_shadow");

test("per-property rubric permits direct facts and rejects comfort confidence", () => {
  assert.match(PROPERTY_CONFIDENCE_RUBRIC.hasHood, /Very high only/);
  assert.match(PROPERTY_CONFIDENCE_RUBRIC.visibleTread, /not_visible/);
  assert.match(PROPERTY_CONFIDENCE_RUBRIC.visibleStretchCue, /unknown/);
  assert.match(PROPERTY_CONFIDENCE_RUBRIC.coverage, /wearer's body/);
  const prompt = buildVisionV2Prompt(taxonomy);
  assert.match(prompt, /epistemic|direct visibility/i);
  assert.match(prompt, /Do not list them as defining/i);
  assert.match(prompt, /per-property confidence rubric/i);
  assert.match(prompt, /Do not confuse garment coverage/i);
  assert.match(PROPERTY_CONFIDENCE_RUBRIC.visiblePocketStructure,
    /single front view usually requires unknown or not_visible/);
});

const taxonomy = ["hoodie", "sweater", "t_shirt"];
const observations = {
  coverage: {state: "observed", value: "full", confidence: 0.9},
  hasHood: {state: "not_visible", confidence: 0.2},
  frontClosure: {state: "observed", value: "none", confidence: 0.8},
  visibleBulk: {state: "observed", value: "low", confidence: 0.8},
  surfaceAppearance: {state: "observed", value: "knit", confidence: 0.9},
  necklineShape: {state: "observed", value: "crew", confidence: 0.9},
  visiblePocketStructure: {state: "not_applicable", confidence: 1},
  visibleStretchCue: {state: "unknown", confidence: 0},
  sportyCues: {state: "observed", value: "low", confidence: 0.7},
  formalCues: {state: "observed", value: "low", confidence: 0.7},
  footwearConstruction: {state: "not_applicable", confidence: 1},
  footwearFastening: {state: "not_applicable", confidence: 1},
  soleProfile: {state: "not_applicable", confidence: 1},
  visibleTread: {state: "not_applicable", confidence: 1},
  footwearUpperHeight: {state: "not_applicable", confidence: 1},
};

const defaultRegions = {
  coverage: ["full_silhouette"],
  hasHood: ["collar", "back"],
  frontClosure: ["front"],
  visibleBulk: ["full_silhouette"],
  surfaceAppearance: ["surface_detail"],
  necklineShape: ["neckline"],
  visiblePocketStructure: ["front", "side", "pocket_area"],
  visibleStretchCue: ["surface_detail"],
  sportyCues: ["full_silhouette"],
  formalCues: ["full_silhouette"],
  footwearConstruction: ["footwear_upper"],
  footwearFastening: ["fastening_area"],
  soleProfile: ["sole_profile", "side"],
  visibleTread: ["outsole"],
  footwearUpperHeight: ["footwear_upper", "side"],
};

function valid(overrides = {}) {
  const payload = {
    quality: {
      itemFullyVisible: true,
      occlusion: "none",
      backgroundInterference: "low",
      clarity: "high",
    },
    inputAssessment: "valid_single_item",
    subjectAssessment: {
      subjectCountEstimate: 1,
      cardinalityState: "single_item_supported",
      primarySubjectPresent: true,
      sameItemConsistency: "same_item_supported",
      subjectDomain: "garment_upper",
      framingClass: "full_item",
      framingAttestations: {
        visibleBoundaries: ["top", "bottom", "left", "right"],
        primarySilhouetteContinuous: true,
        visibleItemExtent: "whole",
        localDetailOnly: false,
        cropIndicators: [],
        subjectOrientation: "front",
      },
      reasonCodes: ["single_complete_subject"],
    },
    observations,
    identityCandidates: [{
      canonicalType: "sweater",
      confidence: 0.8,
      definingObservations: ["surfaceAppearance"],
      supportingObservations: ["necklineShape", "surfaceAppearance"],
    }],
    directInferences: {},
    ...overrides,
  };
  payload.observations = Object.fromEntries(
    Object.entries(payload.observations).map(([key, value]) => [
      key,
      {
        ...value,
        visibilityScope: value.visibilityScope ??
          (value.state === "not_visible" ? "not_visible" : "complete"),
        visibleRegions: value.visibleRegions ?? defaultRegions[key] ?? [],
      },
    ]),
  );
  return JSON.stringify(payload);
}

function parse(text) {
  return parseVisionV2Response(text, {
    allowedCanonicalTypes: taxonomy,
    analysisId: "a1",
    sourceReference: "fixture://sweater",
    observedAt: "2026-01-01T00:00:00.000Z",
  });
}

test("parses valid response and preserves not_visible", () => {
  const result = parse(valid());
  assert.equal(result.ok, true);
  assert.equal(result.value.observations.hasHood.state, "not_visible");
  assert.equal(result.value.observations.hasHood.visibilityScope, "not_visible");
  assert.equal(result.value.identityCandidates[0].canonicalType, "sweater");
  assert.equal(result.value.subjectAssessment.framingAttestations
    .visibleItemExtent, "whole");
  assert.deepEqual(result.value.identityCandidates[0].supportingObservations,
    ["necklineShape", "surfaceAppearance"]);
  assert.deepEqual(result.value.identityCandidates[0].definingObservations,
    ["surfaceAppearance"]);
});

test("invalid JSON is a hard parser failure", () => {
  assert.deepEqual(parse("{no").errors, ["invalid_json"]);
});

test("unknown enum and invalid confidence are dropped without defaults", () => {
  const bad = structuredClone(observations);
  bad.visibleBulk = {state: "observed", value: "neutral", confidence: 0.9};
  bad.formalCues = {state: "observed", value: "high", confidence: 4};
  const result = parse(valid({observations: bad}));
  assert.equal(result.value.observations.visibleBulk, undefined);
  assert.equal(result.value.observations.formalCues, undefined);
  assert(result.errors.includes("observations.visibleBulk.value.invalid"));
  assert(result.errors.includes("observations.formalCues.confidence.invalid"));
});

test("missing property is reported and not fabricated", () => {
  const incomplete = structuredClone(observations);
  delete incomplete.visibleTread;
  const result = parse(valid({observations: incomplete}));
  assert.equal(result.value.observations.visibleTread, undefined);
  assert(result.errors.includes("observations.visibleTread.missing"));
});

test("observed false remains distinct from not_visible", () => {
  const visible = structuredClone(observations);
  visible.hasHood = {state: "observed", value: false, confidence: 0.95};
  assert.equal(parse(valid({observations: visible})).value.observations.hasHood.value, false);
  assert.equal(parse(valid()).value.observations.hasHood.value, undefined);
});

test("multiple candidates are retained and outside taxonomy is rejected", () => {
  const result = parse(valid({identityCandidates: [
    {canonicalType: "hoodie", confidence: 0.5},
    {canonicalType: "sweater", confidence: 0.3,
      definingObservations: [], supportingObservations: []},
    {canonicalType: "invented_type", confidence: 0.2,
      definingObservations: [], supportingObservations: []},
  ]}));
  assert.deepEqual(result.value.identityCandidates.map((item) => item.canonicalType),
    ["hoodie", "sweater"]);
  assert(result.errors.some((item) => item.includes("invented_type")));
});

test("prompt prohibits capability output and uses supplied taxonomy", () => {
  const prompt = buildVisionV2Prompt(taxonomy);
  assert.match(prompt, /Do not infer capabilities/);
  assert.match(prompt, /ABSENCE OF VISIBLE EVIDENCE IS NOT A NEGATIVE OBSERVATION/);
  assert.match(prompt, /visibleTread=not_visible/);
  assert.match(prompt, /Do not repeat 0\.95 as a generic confidence/);
  assert.match(prompt, /"t_shirt"/);
  assert.match(prompt, /high-top fashion sneaker is not automatically basketball_shoes/);
  assert.match(prompt, /outdoor-looking jacket is not automatically hiking_jacket/);
  assert.match(prompt, /full_silhouette never substitutes for a required/);
  assert.match(prompt, /ABSENCE REGION-SET RULES/);
  assert.match(prompt, /listing one loosely related region is usually not enough/);
  assert.match(prompt, /hasHood=false: downstream absence trust needs collar AND back/);
  assert.match(prompt, /visiblePocketStructure=none: downstream absence trust needs front AND side AND/);
  assert.match(prompt, /A back-only view MUST NOT claim frontClosure=none/);
  assert.match(prompt, /frontClosure=not_visible or unknown instead/);
  assert.match(prompt, /Never invent a region that is not truly shown/);
  assert.match(prompt, /Never add a region only to pass qualification/);
  assert.match(prompt, /B\) Hood absence on front-only\/collar-only view/);
  assert.match(prompt, /F\) Back view where the front closure path is unseen/);
  assert.match(prompt, /G\) Positive full_zip/);
  assert.match(prompt, /visibleStretchCue=false remains almost never valid/);
  assert.doesNotMatch(prompt,
    /Do not add a region merely to justify a negative value/);
  assert.doesNotMatch(prompt, /and\/or back/);
  assert.doesNotMatch(prompt, /dress_trousers/);
});

test("prompt negative region-set contract matches visibility teaching", () => {
  const prompt = buildVisionV2Prompt(taxonomy);
  assert.match(prompt, /negatives require complete visible evidence sets|Declare every property-specific region that is actually visible/i);
  assert.match(prompt, /full_silhouette never substitutes/);
  assert.match(prompt, /Do not invent side or pocket_area from a pure back view/);
  assert.match(prompt, /A front\/collar-only view must NOT invent back coverage/);
  assert.match(prompt, /frontClosure=none: only when this view can inspect the front closure path/);
  assert.match(prompt, /Positive examples: hasHood=true must include collar or back/);
  assert.match(prompt, /cargo or standard pockets must include pocket_area/);
});

test("strict response schema region enum and shape are unchanged", () => {
  const format = buildVisionV2ResponseFormat(taxonomy);
  const observed = format.json_schema.schema.properties.observations
    .properties.hasHood.anyOf[0];
  const regions = observed.properties.visibleRegions;
  assert.equal(regions.type, "array");
  assert.deepEqual(regions.items.enum, [
    "full_silhouette", "front", "side", "back", "collar", "neckline",
    "pocket_area", "footwear_upper", "fastening_area", "sole_profile",
    "outsole", "surface_detail",
  ]);
  assert.deepEqual(observed.required.sort(), [
    "confidence", "state", "value", "visibilityScope", "visibleRegions",
  ].sort());
  assert.equal(Object.prototype.hasOwnProperty.call(regions, "minItems"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(regions, "maxItems"), false);
});

test("strict response schema requires every observation and supplied taxonomy", () => {
  const format = buildVisionV2ResponseFormat(taxonomy);
  assert.equal(format.type, "json_schema");
  assert.equal(format.json_schema.strict, true);
  const schema = format.json_schema.schema;
  assert.deepEqual(schema.properties.identityCandidates.items.properties
    .canonicalType.enum, taxonomy);
  assert(schema.properties.identityCandidates.items.required
    .includes("supportingObservations"));
  assert(schema.properties.identityCandidates.items.required
    .includes("definingObservations"));
  assert(schema.properties.observations.properties.coverage.anyOf[0].required
    .includes("visibilityScope"));
  assert(schema.properties.observations.properties.coverage.anyOf[0].required
    .includes("visibleRegions"));
  assert(schema.required.includes("inputAssessment"));
  assert(schema.required.includes("subjectAssessment"));
  assert(schema.properties.subjectAssessment.required
    .includes("framingAttestations"));
  assert.match(buildVisionV2Prompt(taxonomy), /local construction detail/);
  assert.deepEqual(
    schema.properties.identityCandidates.items.properties
      .supportingObservations.items.enum,
    Object.keys(schema.properties.observations.properties),
  );
  assert.deepEqual(schema.properties.observations.required.sort(),
    Object.keys(schema.properties.observations.properties).sort());
  assert.equal(schema.properties.directInferences.additionalProperties, false);
});

test("handler performs one model call and has no persistence dependency", async () => {
  let calls = 0;
  const handler = createVisionV2ShadowHandler({
    fetchImpl: async () => {
      calls += 1;
      return {ok: true, json: async () => ({
        choices: [{message: {content: valid()}}],
      })};
    },
    getApiKey: () => "test",
    logger: {error() {}},
    authorize: async () => ({uid: "qa-user"}),
  });
  let status;
  let body;
  const res = {
    status(value) { status = value; return this; },
    json(value) { body = value; return this; },
    send(value) { body = value; return this; },
  };
  await handler({
    method: "POST",
    body: {imageUrl: "fixture://image", canonicalTypes: taxonomy},
  }, res);
  assert.equal(status, 200);
  assert.equal(calls, 1);
  assert.equal(body.diagnostics.modelCallCount, 1);
});

test("handler rejects missing or invalid authorization before model call", async () => {
  let calls = 0;
  const handler = createVisionV2ShadowHandler({
    fetchImpl: async () => { calls += 1; },
    getApiKey: () => "test",
    logger: {error() {}},
    authorize: async () => null,
  });
  let status;
  const res = {
    status(value) { status = value; return this; },
    json() { return this; },
    send() { return this; },
  };
  await handler({method: "POST", body: {}}, res);
  assert.equal(status, 401);
  assert.equal(calls, 0);
});

test("handler preserves retryable status and makes upstream 400 non-retryable", async () => {
  for (const [upstreamStatus, expectedStatus] of [[503, 503], [400, 422]]) {
    let status;
    let body;
    const handler = createVisionV2ShadowHandler({
      fetchImpl: async () => ({
        ok: false,
        status: upstreamStatus,
        text: async () => "upstream failure",
      }),
      getApiKey: () => "test",
      logger: {error() {}},
      authorize: async () => ({uid: "qa-user"}),
    });
    const res = {
      status(value) { status = value; return this; },
      json(value) { body = value; return this; },
      send(value) { body = value; return this; },
    };
    await handler({
      method: "POST",
      body: {imageUrl: "fixture://image", canonicalTypes: taxonomy},
    }, res);
    assert.equal(status, expectedStatus);
    assert.equal(body.retryable, upstreamStatus === 503);
    assert.equal(body.upstreamStatus, upstreamStatus);
  }
});

test("batch retries 502 with bounded backoff", async () => {
  const sleeps = [];
  const result = await runVisionV2ShadowBatch(["a"], async (_, attempt) => {
    if (attempt < 3) throw Object.assign(new Error("upstream"), {status: 502});
    return "ok";
  }, {sleep: async (ms) => sleeps.push(ms), pacingMs: 0, jitterRatio: 0});
  assert.equal(result[0].ok, true);
  assert.equal(result[0].attempts, 3);
  assert.deepEqual(sleeps, [1000, 2000]);
});

test("batch respects retry-after and reports rate-limit reason", async () => {
  const sleeps = [];
  const result = await runVisionV2ShadowBatch(["a"], async (_, attempt) => {
    if (attempt === 1) {
      throw Object.assign(new Error("rate limit"), {
        status: 429,
        retryAfterMs: 2400,
      });
    }
    return "ok";
  }, {
    sleep: async (ms) => sleeps.push(ms),
    pacingMs: 0,
    jitterRatio: 0,
  });
  assert.deepEqual(sleeps, [2400]);
  assert.equal(result[0].retries[0].reason, "rate_limited");
  assert.equal(result[0].retries[0].delayMs, 2400);
});

test("batch does not retry non-retryable failure and continues", async () => {
  const result = await runVisionV2ShadowBatch(["bad", "good"], async (item) => {
    if (item === "bad") throw Object.assign(new Error("invalid"), {status: 400});
    return "ok";
  }, {pacingMs: 0});
  assert.equal(result[0].ok, false);
  assert.equal(result[0].attempts, 1);
  assert.equal(result[1].ok, true);
});

test("batch respects concurrency limit", async () => {
  let active = 0;
  let peak = 0;
  await runVisionV2ShadowBatch([1, 2, 3, 4], async () => {
    active += 1;
    peak = Math.max(peak, active);
    await new Promise((resolve) => setTimeout(resolve, 5));
    active -= 1;
    return "ok";
  }, {concurrency: 2, pacingMs: 0});
  assert.equal(peak, 2);
});
