"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const sharp = require("sharp");
const {
  buildDerivedAsset,
  sha256File,
  synchronizeCaptureManifest,
  validateAssetDataset,
} = require("./vision_adversarial_asset_dataset");

async function workspace(run) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "vision-assets-"));
  const image = path.join(root, "source.png");
  await sharp({
    create: {width: 64, height: 64, channels: 3, background: "#557799"},
  }).png({compressionLevel: 9}).toFile(image);
  try {
    return await run({root, image});
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
}

function scenario(view, overrides = {}) {
  return {
    id: "fixture_a",
    scenarioVersion: 1,
    status: "ready_asset",
    requiredViewCount: 1,
    contract: {visible: "item", hidden: "none", tests: "test"},
    views: [view],
    license: {
      type: "generated_for_project",
      redistributionAllowed: true,
    },
    privacyReviewed: true,
    provenance: "generated_for_project",
    ...overrides,
  };
}

function view(image, root, overrides = {}) {
  return {
    viewId: "view_1",
    assetPath: path.relative(root, image).replaceAll("\\", "/"),
    assetSha256: sha256File(image),
    mimeType: "image/png",
    sourceType: "original",
    width: 64,
    height: 64,
    ...overrides,
  };
}

async function validate(root, scenarios, ids = ["fixture_a"]) {
  return validateAssetDataset({
    manifestVersion: 1,
    assetDataset: "current_pipeline_assets_v1",
    scenarios,
  }, {rootDirectory: root, scenarioIds: ids});
}

test("unknown and duplicate scenario IDs fail", async () => {
  await workspace(async ({root, image}) => {
    const item = scenario(view(image, root));
    assert((await validate(root, [item], ["known"])).errors
      .includes("asset_manifest.unknown_scenario:fixture_a"));
    assert((await validate(root, [item, item])).errors
      .includes("asset_manifest.scenario_id.invalid"));
  });
});

test("unsafe absolute traversal URL and missing paths fail", async () => {
  await workspace(async ({root, image}) => {
    for (const assetPath of [
      image,
      "../outside.png",
      "https://example.invalid/image.png",
      "missing.png",
    ]) {
      const result = await validate(root, [
        scenario(view(image, root, {assetPath})),
      ]);
      assert.equal(result.ok, false);
    }
  });
});

test("hash MIME extension and view identity are validated", async () => {
  await workspace(async ({root, image}) => {
    const bad = view(image, root, {
      assetSha256: "0".repeat(64),
      mimeType: "image/jpeg",
    });
    const item = scenario(bad, {views: [bad, {...bad}]});
    const errors = (await validate(root, [item])).errors.join(",");
    assert.match(errors, /sha256/);
    assert.match(errors, /mime/);
    const invalidIdentity = view(image, root, {viewId: ""});
    const identityErrors = (await validate(root, [
      scenario(invalidIdentity),
    ])).errors.join(",");
    assert.match(identityErrors, /view_id/);
    const good = view(image, root);
    const duplicateErrors = (await validate(root, [
      scenario(good, {views: [good, {...good}]}),
    ])).errors.join(",");
    assert.match(duplicateErrors, /view_id/);
  });
});

test("embedded private image metadata is rejected", async () => {
  await workspace(async ({root}) => {
    const image = path.join(root, "private.jpg");
    await sharp({
      create: {width: 32, height: 32, channels: 3, background: "#ffffff"},
    }).withMetadata({
      exif: {IFD0: {Copyright: "fixture-private-metadata"}},
    }).jpeg().toFile(image);
    const result = await validate(root, [scenario(view(image, root, {
      mimeType: "image/jpeg",
    }))]);
    assert.match(result.errors.join(","), /private_metadata/);
  });
});

test("license redistribution and privacy policy are fail closed", async () => {
  await workspace(async ({root, image}) => {
    for (const overrides of [
      {license: {type: "unknown", redistributionAllowed: true}},
      {license: {type: "generated_for_project", redistributionAllowed: false}},
      {privacyReviewed: false},
    ]) {
      assert.equal((await validate(root, [
        scenario(view(image, root), overrides),
      ])).ok, false);
    }
  });
});

test("derived asset requires source and derivation metadata", async () => {
  await workspace(async ({root, image}) => {
    const derived = view(image, root, {sourceType: "derived"});
    assert.match((await validate(root, [
      scenario(derived),
    ])).errors.join(","), /derived_provenance/);
  });
});

for (const [operation, parameters] of [
  ["crop", {left: 4, top: 4, width: 48, height: 48}],
  ["blur", {sigma: 3}],
  ["dark", {brightness: 0.35, saturation: 0.4, contrast: 0.5, offset: 40}],
]) {
  test(`${operation} derivation is byte deterministic and preserves source`,
    async () => {
      await workspace(async ({root, image}) => {
        const sourceHash = sha256File(image);
        const first = path.join(root, `first-${operation}.png`);
        const second = path.join(root, `second-${operation}.png`);
        await buildDerivedAsset({
          sourcePath: image, outputPath: first, operation, parameters,
        });
        await buildDerivedAsset({
          sourcePath: image, outputPath: second, operation, parameters,
        });
        assert.equal(sha256File(first), sha256File(second));
        assert.equal(sha256File(image), sourceHash);
      });
    });
}

test("multi-photo and special scenario contracts are required", async () => {
  await workspace(async ({root, image}) => {
    const baseView = view(image, root);
    const complementary = scenario(baseView, {
      id: "complementary_multi_view",
      requiredViewCount: 2,
      views: [baseView],
      multiPhoto: {relationship: "wrong", ordering: ["view_1"]},
    });
    const conflict = scenario(baseView, {
      id: "conflicting_multi_view",
      requiredViewCount: 2,
      views: [baseView, {...baseView, viewId: "view_2"}],
      multiPhoto: {
        relationship: "different_garments_intentional_conflict",
        ordering: ["view_2", "view_1"],
      },
    });
    const ambiguity = scenario(baseView, {
      id: "cross_family_ambiguity",
      ambiguity: {plausibleFamilies: ["top"]},
    });
    const result = await validate(root, [complementary, conflict, ambiguity],
      ["complementary_multi_view", "conflicting_multi_view",
        "cross_family_ambiguity"]);
    assert.match(result.errors.join(","), /multi_photo_requires_two_views/);
    assert.match(result.errors.join(","), /conflict_contract_required/);
    assert.match(result.errors.join(","), /multi_photo_ordering_invalid/);
    assert.match(result.errors.join(","), /ambiguity_contract_required/);
  });
});

test("capture sync only promotes valid assets to pending, never captured",
  async () => {
    await workspace(async ({root, image}) => {
      const validation = await validate(root, [
        scenario(view(image, root)),
        {
          id: "missing",
          status: "missing_asset",
          requiredViewCount: 1,
          views: [],
        },
      ], ["fixture_a", "missing"]);
      const synchronized = synchronizeCaptureManifest({
        captureManifest: {
          manifestVersion: 1,
          captureDataset: "current_pipeline_capture_v1",
          fixtures: [
            {id: "fixture_a", captureStatus: "missing_asset", views: []},
            {id: "missing", captureStatus: "missing_asset", views: []},
          ],
        },
        validation,
      });
      assert.equal(synchronized.fixtures[0].captureStatus, "pending_capture");
      assert.equal(synchronized.fixtures[1].captureStatus, "missing_asset");
      assert(!synchronized.fixtures.some((item) =>
        item.captureStatus === "captured"));
    });
  });

test("validation is offline and module has no HTTP or Vision transport", () => {
  const source = fs.readFileSync(__filename.replace(".test.js", ".js"), "utf8");
  assert.doesNotMatch(source, /fetch\(|https?:\/\//);
});
