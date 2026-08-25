"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const sharp = require("sharp");
sharp.cache(false);
const {
  buildCandidatePlan,
  downloadCandidatePlan,
  normalizeApprovedCandidate,
  publicPlan,
  sniffMime,
} = require("./wardrobe_asset_materialization");

function documents(count = 2) {
  return Array.from({length: count}, (_, index) => ({
    documentId: `doc-${index}`,
    fields: {
      storagePath: `wardrobe/private-user/${index}.jpg`,
      categoryKey: index % 2 ? "bottoms" : "tops",
      subCategoryKey: `type_${index}`,
    },
  }));
}

function metadata(count = 2, sizeBytes = 100) {
  return Array.from({length: count}, (_, index) => ({
    storagePath: `wardrobe/{user}/${index}.jpg`,
    exists: true,
    contentType: "image/jpeg",
    sizeBytes,
  }));
}

async function temporaryDirectory(run) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "wardrobe-assets-"));
  try {
    return await run(root);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
}

test("candidate plan prefers normalized user upload and redacts public plan",
  () => {
    const plan = buildCandidatePlan(documents(), metadata());
    assert.equal(plan.selected.length, 2);
    assert(plan.selected.every((item) =>
      item.sourceRole === "normalized_user_upload"));
    const serialized = JSON.stringify(publicPlan(plan));
    assert.doesNotMatch(serialized, /private-user|doc-/);
    assert.match(serialized, /\{user\}/);
  });

test("candidate count and total byte limits are fail closed", () => {
  assert.equal(buildCandidatePlan(documents(5), metadata(5), {
    maxAssets: 2,
    maxTotalBytes: 1000,
  }).selected.length, 2);
  assert.equal(buildCandidatePlan(documents(5), metadata(5, 80), {
    maxAssets: 5,
    maxTotalBytes: 160,
  }).selected.length, 2);
  assert.throws(() => buildCandidatePlan(documents(), metadata(), {
    maxAssets: 21,
  }), /max_assets/);
  assert.throws(() => buildCandidatePlan(documents(), metadata(), {
    maxTotalBytes: 104857601,
  }), /max_total_bytes/);
});

test("download performs only Storage media GET and records SHA MIME dimensions",
  async () => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), "wardrobe-q-"));
    try {
      const bytes = await sharp({
        create: {
          width: 20, height: 12, channels: 3, background: "#335577",
        },
      }).jpeg({quality: 88}).toBuffer();
      const plan = buildCandidatePlan(documents(1),
        metadata(1, bytes.length));
      const calls = [];
      const result = await downloadCandidatePlan({
        plan,
        bucket: "bucket",
        accessToken: "memory-token",
        outputDirectory: directory,
        fetchImpl: async (url, options) => {
          calls.push({url, options});
          return {
            ok: true,
            arrayBuffer: async () =>
              bytes.buffer.slice(bytes.byteOffset,
                bytes.byteOffset + bytes.byteLength),
          };
        },
      });
      assert.equal(calls.length, 1);
      assert.equal(calls[0].options.method, "GET");
      assert.match(calls[0].url, /alt=media$/);
      assert.equal(result.index[0].mimeType, "image/jpeg");
      assert.equal(result.index[0].width, 20);
      assert.match(result.index[0].sha256, /^[a-f0-9]{64}$/);
      assert.equal(result.index[0].privacyReviewState,
        "manual_privacy_review_required");
      assert.equal(result.index[0].provenanceState,
        "approved_user_owned_test_source");
    } finally {
      fs.rmSync(directory, {recursive: true, force: true});
    }
  });

test("magic byte validation rejects declared JPEG with PNG bytes", async () => {
  const bytes = await sharp({
    create: {width: 2, height: 2, channels: 3, background: "#ffffff"},
  }).png().toBuffer();
  assert.equal(sniffMime(bytes), "image/png");
});

test("existing quarantine file is never overwritten", async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "wardrobe-q-"));
  try {
    const bytes = await sharp({
      create: {width: 2, height: 2, channels: 3, background: "#ffffff"},
    }).jpeg().toBuffer();
    fs.writeFileSync(path.join(directory, "wardrobe_asset_001.jpg"), bytes);
    const plan = buildCandidatePlan(documents(1),
      metadata(1, bytes.length));
    await assert.rejects(downloadCandidatePlan({
      plan,
      bucket: "bucket",
      accessToken: "token",
      outputDirectory: directory,
      fetchImpl: async () => ({
        ok: true,
        arrayBuffer: async () =>
          bytes.buffer.slice(bytes.byteOffset,
            bytes.byteOffset + bytes.byteLength),
      }),
    }), /EEXIST/);
  } finally {
    fs.rmSync(directory, {recursive: true, force: true});
  }
});

test("normalization strips metadata, preserves source, and is deterministic",
  async () => {
    await temporaryDirectory(async (root) => {
      const source = path.join(root, "source.jpg");
      await sharp({
        create: {width: 2400, height: 1800, channels: 3, background: "#557799"},
      }).withMetadata({
        exif: {IFD0: {Copyright: "private"}},
      }).jpeg().toFile(source);
      const sourceHash = sha256File(source);
      const review = {
        privacyReviewed: true,
        provenanceApproved: true,
        redistributionAllowed: true,
        sourceRole: "normalized_user_upload",
      };
      const first = path.join(root, "first.jpg");
      const second = path.join(root, "second.jpg");
      const a = await normalizeApprovedCandidate({
        sourcePath: source, outputPath: first, review,
      });
      const b = await normalizeApprovedCandidate({
        sourcePath: source, outputPath: second, review,
      });
      assert.equal(a.sha256, b.sha256);
      assert.equal(sha256File(source), sourceHash);
      assert.equal(a.metadataClean, true);
      assert(a.width <= 2048 && a.height <= 2048);
      const metadata = await sharp(first).metadata();
      assert.equal(metadata.exif, undefined);
      assert.equal(metadata.iptc, undefined);
      assert.equal(metadata.xmp, undefined);
    });
  });

test("uncertain privacy provenance and product sources block staging",
  async () => {
    await temporaryDirectory(async (root) => {
      const source = path.join(root, "source.jpg");
      await sharp({
        create: {width: 32, height: 32, channels: 3, background: "#ffffff"},
      }).jpeg().toFile(source);
      for (const review of [
        {privacyReviewed: false, provenanceApproved: true,
          redistributionAllowed: true, sourceRole: "normalized_user_upload"},
        {privacyReviewed: true, provenanceApproved: false,
          redistributionAllowed: true, sourceRole: "normalized_user_upload"},
        {privacyReviewed: true, provenanceApproved: true,
          redistributionAllowed: true, sourceRole: "product_derivative"},
      ]) {
        await assert.rejects(normalizeApprovedCandidate({
          sourcePath: source,
          outputPath: path.join(root, `${Math.random()}.jpg`),
          review,
        }));
      }
    });
  });

test("CLI requires explicit mode and contains no Firebase write or Vision path",
  () => {
    const cli = fs.readFileSync(path.join(__dirname, "..", "tool",
      "materialize_wardrobe_fixture_candidates.cjs"), "utf8");
    const source = fs.readFileSync(__filename.replace(".test.js", ".js"),
      "utf8");
    assert.match(cli, /exactly_one_of_dry_run_or_execute_download_required/);
    assert.doesNotMatch(`${cli}\n${source}`,
      /firebase-admin|firestore\(\)|\b(?:upload|putFile|putData)\s*\(|OpenAI|Vision/);
    assert.match(source, /method: "GET"/);
    const gitignore = fs.readFileSync(path.join(__dirname, "..", ".gitignore"),
      "utf8");
    assert.match(gitignore, /^\.local_audit\/$/m);
    assert.doesNotMatch(`${cli}\n${source}`,
      /parser_fixture|qualification_golden|execute-live/);
});

function sha256File(filePath) {
  return require("crypto").createHash("sha256")
    .update(fs.readFileSync(filePath)).digest("hex");
}
