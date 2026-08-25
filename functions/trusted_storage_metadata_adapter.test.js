"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {canonicalBytes} = require("./backend_provider_oracle_parity");
const {
  ADAPTER_ID,
  ADAPTER_VERSION,
  SNAPSHOT_CONTRACT,
  createFakeStorageMetadataClient,
  fetchTrustedSourceObjectSnapshot,
} = require("./trusted_storage_metadata_adapter");

const root = path.resolve(__dirname, "..");

function validMetadata(overrides = {}) {
  return {
    generation: "1700000000000000",
    metageneration: "3",
    size: "2048",
    contentType: "image/jpeg",
    updated: "2026-07-29T10:00:00.000Z",
    md5Hash: "abc=",
    crc32c: "xyz=",
    ...overrides,
  };
}

function baseInput(overrides = {}) {
  return {
    uid: "user-1",
    itemId: "item-1",
    sourceStoragePath: "wardrobe/user-1/item.jpg",
    storageMetadataClient: createFakeStorageMetadataClient({
      "wardrobe/user-1/item.jpg": validMetadata(),
    }),
    ...overrides,
  };
}

test("adapter constants", () => {
  assert.equal(ADAPTER_ID, "TrustedStorageMetadataAdapter");
  assert.equal(ADAPTER_VERSION, "trusted-storage-metadata-adapter-v1");
  assert.equal(SNAPSHOT_CONTRACT, "trusted_source_object_snapshot/v1");
});

test("valid object produces TrustedSourceObjectSnapshot/v1", async () => {
  const snapshot = await fetchTrustedSourceObjectSnapshot(baseInput());
  assert.equal(snapshot.exists, true);
  assert.equal(snapshot.backendVerified, true);
  assert.equal(snapshot.sourceStoragePath, "wardrobe/user-1/item.jpg");
  assert.equal(snapshot.generation, "1700000000000000");
  assert.equal(snapshot.metageneration, "3");
  assert.equal(snapshot.sizeBytes, 2048);
  assert.equal(snapshot.contentType, "image/jpeg");
  assert.equal(snapshot.updatedAt, "2026-07-29T10:00:00.000Z");
  assert.equal(snapshot.md5Hash, "abc=");
  assert.equal(snapshot.crc32c, "xyz=");
  assert.equal(snapshot.sha256, null);
  assert.ok(Object.isFrozen(snapshot));
});

test("missing object fails closed", async () => {
  await assert.rejects(() => fetchTrustedSourceObjectSnapshot(baseInput({
    storageMetadataClient: createFakeStorageMetadataClient({}),
  })), /source_object_missing/);
});

test("invalid generation fails closed", async () => {
  await assert.rejects(() => fetchTrustedSourceObjectSnapshot(baseInput({
    storageMetadataClient: createFakeStorageMetadataClient({
      "wardrobe/user-1/item.jpg": validMetadata({generation: null}),
    }),
  })), /storage_generation_invalid/);
  await assert.rejects(() => fetchTrustedSourceObjectSnapshot(baseInput({
    storageMetadataClient: createFakeStorageMetadataClient({
      "wardrobe/user-1/item.jpg": validMetadata({generation: "not-a-number"}),
    }),
  })), /storage_generation_invalid/);
});

test("invalid path fails closed", async () => {
  await assert.rejects(() => fetchTrustedSourceObjectSnapshot(baseInput({
    sourceStoragePath: "wardrobe_clean/user-1/item.png",
  })), /source_storage_path_invalid/);
  await assert.rejects(() => fetchTrustedSourceObjectSnapshot(baseInput({
    sourceStoragePath: "wardrobe/other-user/item.jpg",
  })), /source_storage_path_uid_mismatch/);
  await assert.rejects(() => fetchTrustedSourceObjectSnapshot(baseInput({
    sourceStoragePath: "https://example.com/x",
  })), /source_storage_path_invalid/);
});

test("malformed metadata fails closed", async () => {
  await assert.rejects(() => fetchTrustedSourceObjectSnapshot(baseInput({
    storageMetadataClient: createFakeStorageMetadataClient({
      "wardrobe/user-1/item.jpg": "nope",
    }),
  })), /storage_metadata_malformed/);
  await assert.rejects(() => fetchTrustedSourceObjectSnapshot(baseInput({
    storageMetadataClient: createFakeStorageMetadataClient({
      "wardrobe/user-1/item.jpg": validMetadata({
        signedUrl: "https://example.com/x?X-Goog-Signature=1",
      }),
    }),
  })), /storage_download_or_signed_url_rejected/);
  await assert.rejects(() => fetchTrustedSourceObjectSnapshot(baseInput({
    storageMetadataClient: createFakeStorageMetadataClient({
      "wardrobe/user-1/item.jpg": validMetadata({size: -1}),
    }),
  })), /storage_size_invalid/);
});

test("deterministic snapshot", async () => {
  const first = await fetchTrustedSourceObjectSnapshot(baseInput());
  const second = await fetchTrustedSourceObjectSnapshot(baseInput());
  assert.equal(
    crypto.createHash("sha256").update(canonicalBytes(first)).digest("hex"),
    crypto.createHash("sha256").update(canonicalBytes(second)).digest("hex"),
  );
});

test("client metadata rejected", async () => {
  await assert.rejects(() => fetchTrustedSourceObjectSnapshot({
    ...baseInput(),
    clientMetadata: {generation: "1"},
  }), /client_storage_metadata_rejected/);
});

test("production isolation", () => {
  const production = [
    "functions/index.js",
    "functions/vision_v2_shadow.js",
    "functions/wardrobe_profile_firestore_repository.js",
  ].map((item) => fs.readFileSync(path.join(root, item), "utf8")).join("\n");
  assert.equal(production.includes("trusted_storage_metadata_adapter"), false);
  assert.equal(production.includes("fetchTrustedSourceObjectSnapshot"), false);
});
