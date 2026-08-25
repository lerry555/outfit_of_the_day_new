"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const {
  assertCommitSafeInventory,
  buildWardrobeImageInventory,
  classifyImageRole,
  parseFirebaseStoragePath,
} = require("./wardrobe_image_inventory");

const originalUrl =
  "https://firebasestorage.googleapis.com/v0/b/project/o/" +
  "wardrobe%2Fprivate-user-id%2Fitem.jpg?alt=media&token=secret";
const cleanUrl =
  "https://firebasestorage.googleapis.com/v0/b/project/o/" +
  "wardrobe_clean%2Fprivate-user-id%2Fitem.png?alt=media&token=secret";

function document(overrides = {}) {
  return {
    documentId: "doc-a",
    data: {
      categoryKey: "tops",
      subCategoryKey: "t_shirt",
      storagePath: "wardrobe/private-user-id/item.jpg",
      imageUrl: originalUrl,
      originalImageUrl: originalUrl,
      cleanImageUrl: cleanUrl,
      cleanStoragePath: "wardrobe_clean/private-user-id/item.png",
      ...overrides,
    },
  };
}

test("recognizes normalized user original and derived image fields", () => {
  const data = document().data;
  assert.equal(classifyImageRole("originalImageUrl", data),
    "normalized_user_photo");
  assert.equal(classifyImageRole("imageUrl", data), "normalized_user_photo");
  assert.equal(classifyImageRole("cleanImageUrl", data),
    "background_removed");
  assert.equal(classifyImageRole("cutoutImageUrl", data),
    "background_removed");
});

test("recognizes product source and normalized product fields", () => {
  assert.equal(classifyImageRole("productImageUrl", {
    productImageUrl: "https://shop.example/image.jpg",
    sourceUrl: "https://shop.example/item",
  }), "product_source_image");
  assert.equal(classifyImageRole("productImageUrl", {
    productStoragePath: "wardrobe_product/u/item.png",
  }), "normalized_product_image");
});

test("prefers normalized user photo before derived image", () => {
  const item = buildWardrobeImageInventory([document()]).items[0];
  assert.equal(item.preferredImageField, "imageUrl");
  assert.equal(item.preferredImageRole, "normalized_user_photo");
});

test("falls back when preferred original Storage object is missing", () => {
  const inventory = buildWardrobeImageInventory([document()], {
    storageMetadataByPath: new Map([
      ["wardrobe/private-user-id/item.jpg", {exists: false}],
      ["wardrobe_clean/private-user-id/item.png", {
        exists: true, mimeType: "image/png", sizeBytes: 12,
      }],
    ]),
  });
  assert.equal(inventory.items[0].preferredImageField, "cleanImageUrl");
  assert.equal(inventory.items[0].preferredImageRole, "background_removed");
});

test("deduplicates by wardrobe document ID deterministically", () => {
  const inventory = buildWardrobeImageInventory([
    document(), document({categoryKey: "different"}),
  ]);
  assert.equal(inventory.items.length, 1);
  assert.equal(inventory.items[0].categoryKey, "tops");
});

test("redacts signed URL token and user segment from output", () => {
  const serialized = JSON.stringify(
    buildWardrobeImageInventory([document()]));
  assert.doesNotMatch(serialized, /token=|secret|private-user-id/);
  assert.match(serialized, /wardrobe\/\{user\}\/item\.jpg/);
});

test("commit-safe assertion rejects UID email token and local path", () => {
  for (const unsafe of [
    {uid: "private"},
    {categoryKey: "person@example.com"},
    {value: "https://x.test/a?token=secret"},
    {value: "C:\\Users\\private\\image.jpg"},
  ]) {
    assert.throws(() => assertCommitSafeInventory(unsafe),
      /sensitive_data/);
  }
});

test("missing Storage object is represented without inventing metadata", () => {
  const inventory = buildWardrobeImageInventory([document({
    cleanImageUrl: null,
    cleanStoragePath: null,
  })], {
    storageMetadataByPath: new Map([
      ["wardrobe/private-user-id/item.jpg", {exists: false}],
    ]),
  });
  const image = inventory.items[0].availableImages[0];
  assert.equal(image.exists, false);
  assert.equal(image.sha256, null);
  assert.equal(inventory.items[0].datasetStatus, "missing_image");
});

test("legacy image fields remain conservative", () => {
  const inventory = buildWardrobeImageInventory([{
    documentId: "legacy",
    data: {photoUrl: "https://legacy.example/photo.jpg"},
  }]);
  assert.equal(inventory.items[0].preferredImageRole, "legacy_unknown");
  assert.equal(parseFirebaseStoragePath(
    "wardrobe/private-user-id/legacy.jpg"),
  "wardrobe/private-user-id/legacy.jpg");
});

test("audit implementation is offline read-only and has no AI outputs", () => {
  const moduleSource = fs.readFileSync(__filename.replace(".test.js", ".js"),
    "utf8");
  const toolSource = fs.readFileSync(path.join(__dirname, "..", "tool",
    "audit_current_wardrobe_images.cjs"), "utf8");
  const combined = `${moduleSource}\n${toolSource}`;
  assert.doesNotMatch(combined,
    /firebase-admin|firebase\/storage|firebase\/firestore|fetch\(|https\.request/);
  assert.doesNotMatch(combined,
    /\.delete\(|\b(?:putFile|putData|upload)\s*\(|OpenAI/);
  assert.doesNotMatch(combined,
    /analyzeClothingImage|vision_v2_shadow|image_url.*fetch/);
  assert.doesNotMatch(combined,
    /parserFixture|qualificationGolden|machineEvidence/);
});

test("same input produces byte-equivalent inventory ordering", () => {
  const input = [
    document({imageUrl: originalUrl}),
    {...document(), documentId: "doc-b"},
  ].reverse();
  assert.deepEqual(
    buildWardrobeImageInventory(input),
    buildWardrobeImageInventory([...input].reverse()),
  );
});
