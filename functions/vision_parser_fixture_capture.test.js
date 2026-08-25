"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const {
  CAPTURE_DATASET,
  buildParserFixture,
  captureFixture,
  preflightCaptureManifest,
  serializeParserFixture,
  sha256File,
  stableAnalysisId,
  validateParserFixture,
} = require("./vision_parser_fixture_capture");

function response({
  inputAssessment = "valid_single_item",
} = {}) {
  return {
    schemaVersion: 9,
    analysisId: "fixture:analysis",
    modelVersion: "gpt-4o-mini",
    sourceReference: "fixture://asset",
    observedAt: "2026-07-29T10:00:00.000Z",
    quality: {itemFullyVisible: true, clarity: "high"},
    inputAssessment,
    subjectAssessment: {subjectCountEstimate: 1},
    observations: {coverage: {state: "observed", value: "full"}},
    identityCandidates: [],
    validationErrors: [],
  };
}

function withAsset(run) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "capture-fixture-"));
  const asset = path.join(root, "asset.jpg");
  fs.writeFileSync(asset, Buffer.from("stable-fixture-image"));
  const fixture = {
    id: "fixture_a",
    captureStatus: "pending_capture",
    views: [{
      viewId: "view_1",
      assetPath: "asset.jpg",
      assetSha256: sha256File(asset),
      mimeType: "image/jpeg",
    }],
  };
  return Promise.resolve(run({root, asset, fixture})).finally(() =>
    fs.rmSync(root, {recursive: true, force: true}));
}

test("preflight and blocked capture never invoke transport", async () => {
  await withAsset(async ({root, fixture}) => {
    let calls = 0;
    const manifest = {
      manifestVersion: 1,
      captureDataset: CAPTURE_DATASET,
      fixtures: [fixture],
    };
    assert.equal(preflightCaptureManifest(manifest, {
      rootDirectory: root,
    }).fixtures[0].effectiveStatus, "pending_capture");
    const result = await captureFixture({
      fixture,
      rootDirectory: root,
      executeLive: false,
      transport: async () => { calls++; },
    });
    assert.equal(result.reasonCode, "execute_live_required");
    assert.equal(calls, 0);
  });
});

test("live capture uses exact asset hash and stable analysis id", async () => {
  await withAsset(async ({root, fixture}) => {
    let received;
    const result = await captureFixture({
      fixture,
      rootDirectory: root,
      executeLive: true,
      capturedAt: "2026-07-29T10:00:00.000Z",
      transport: async (request) => {
        received = request;
        return response();
      },
    });
    assert.equal(result.status, "captured");
    assert.equal(received.analysisId,
      stableAnalysisId("fixture_a", "view_1"));
    assert.equal(result.fixture.views[0].assetSha256,
      fixture.views[0].assetSha256);
  });
});

test("hash mismatch blocks request", async () => {
  await withAsset(async ({root, fixture}) => {
    fixture.views[0].assetSha256 = "0".repeat(64);
    let calls = 0;
    const result = await captureFixture({
      fixture,
      rootDirectory: root,
      executeLive: true,
      transport: async () => { calls++; },
    });
    assert.equal(result.reasonCode, "asset_hash_mismatch:view_1");
    assert.equal(calls, 0);
  });
});

test("missing asset is explicit", async () => {
  const result = await captureFixture({
    fixture: {id: "missing", captureStatus: "missing_asset", views: []},
    rootDirectory: process.cwd(),
    executeLive: true,
  });
  assert.equal(result.status, "missing_asset");
  assert.equal(result.reasonCode, "asset_not_committed");
});

test("parser fixture rejects forbidden and sensitive fields", () => {
  const fixture = validFixture();
  fixture.views[0].response.resolvedProfile = {};
  fixture.views[0].response.machineEvidence = [];
  fixture.views[0].response.authorization = "secret";
  const errors = validateParserFixture(fixture);
  assert(errors.some((item) => item.includes("resolvedProfile")));
  assert(errors.some((item) => item.includes("machineEvidence")));
  assert(errors.some((item) => item.includes("authorization")));
});

test("valid fixture including non-wardrobe result serializes deterministically", () => {
  const fixture = validFixture({inputAssessment: "non_wardrobe_object"});
  assert.deepEqual(validateParserFixture(fixture), []);
  const first = serializeParserFixture(fixture);
  const second = serializeParserFixture(JSON.parse(first));
  assert.equal(first, second);
  assert(first.endsWith("\n"));
});

test("provenance is mandatory and structural failure is rejected", () => {
  const fixture = validFixture();
  delete fixture.captureProvenance.promptVersion;
  assert(validateParserFixture(fixture)
    .includes("parser_fixture.provenance.invalid"));
  assert.throws(() => serializeParserFixture(fixture),
    /parser_fixture_invalid/);
});

test("captured fixture requires explicit refresh", async () => {
  await withAsset(async ({root, fixture}) => {
    fixture.captureStatus = "captured";
    let calls = 0;
    const result = await captureFixture({
      fixture,
      rootDirectory: root,
      executeLive: true,
      transport: async () => { calls++; },
    });
    assert.equal(result.reasonCode, "refresh_captured_required");
    assert.equal(calls, 0);
  });
});

test("multi-photo capture preserves view order and requires every view", async () => {
  await withAsset(async ({root, fixture}) => {
    fixture.views.push({
      ...fixture.views[0],
      viewId: "view_2",
    });
    const calls = [];
    const result = await captureFixture({
      fixture,
      rootDirectory: root,
      executeLive: true,
      capturedAt: "2026-07-29T10:00:00.000Z",
      transport: async ({viewId}) => {
        calls.push(viewId);
        return response();
      },
    });
    assert.equal(result.status, "captured");
    assert.deepEqual(calls, ["view_1", "view_2"]);
    assert.deepEqual(result.fixture.views.map((item) => item.viewId),
      ["view_1", "view_2"]);
    assert.throws(() => buildParserFixture({
      fixture,
      parsedResponses: [response()],
      capturedAt: "2026-07-29T10:00:00.000Z",
    }), /view_count_mismatch/);
  });
});

test("partial multi-view failure creates no fixture", async () => {
  await withAsset(async ({root, fixture}) => {
    fixture.views.push({...fixture.views[0], viewId: "view_2"});
    const calls = [];
    await assert.rejects(captureFixture({
      fixture,
      rootDirectory: root,
      executeLive: true,
      capturedAt: "2026-07-29T10:00:00.000Z",
      transport: async ({viewId}) => {
        calls.push(viewId);
        if (viewId === "view_2") throw new Error("transport_failed");
        return response();
      },
    }), /transport_failed/);
    assert.deepEqual(calls, ["view_1", "view_2"]);
  });
});

test("parser fixture binding maps asset relationship and defaults undeclared",
  async () => {
    await withAsset(async ({root, fixture}) => {
      const undeclared = buildParserFixture({
        fixture,
        parsedResponses: [response()],
        capturedAt: "2026-07-29T10:00:00.000Z",
      });
      assert.equal(
        undeclared.multiViewSubjectBinding.physicalIdentityClaim,
        "undeclared",
      );
      fixture.multiPhoto = {relationship: "same_source_garment"};
      const same = buildParserFixture({
        fixture,
        parsedResponses: [response()],
        capturedAt: "2026-07-29T10:00:00.000Z",
      });
      assert.equal(
        same.multiViewSubjectBinding.physicalIdentityClaim,
        "same_physical_item",
      );
      assert.equal(
        same.multiViewSubjectBinding.source,
        "asset_manifest_relationship",
      );
      fixture.multiViewSubjectBinding = {
        contractVersion: 1,
        physicalIdentityClaim: "different_physical_items",
        source: "capture_declaration",
        reasonCodes: ["explicit"],
      };
      const explicit = buildParserFixture({
        fixture,
        parsedResponses: [response()],
        capturedAt: "2026-07-29T10:00:00.000Z",
      });
      assert.equal(
        explicit.multiViewSubjectBinding.physicalIdentityClaim,
        "different_physical_items",
      );
      assert.deepEqual(
        validateParserFixture({
          ...same,
          multiViewSubjectBinding: {
            contractVersion: 2,
            physicalIdentityClaim: "same_physical_item",
            source: "unknown",
          },
        }),
        ["parser_fixture.multi_view_subject_binding.version_invalid"],
      );
    });
  });

function validFixture({
  inputAssessment = "valid_single_item",
} = {}) {
  return buildParserFixture({
    fixture: {
      id: "fixture_a",
      views: [{
        viewId: "view_1",
        assetPath: "test/fixtures/asset.jpg",
        assetSha256: "a".repeat(64),
        mimeType: "image/jpeg",
      }],
    },
    parsedResponses: [response({inputAssessment})],
    capturedAt: "2026-07-29T10:00:00.000Z",
  });
}
