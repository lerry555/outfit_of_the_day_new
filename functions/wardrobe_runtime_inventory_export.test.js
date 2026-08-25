"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const {
  extractRuntimeInventory,
  redactDocument,
} = require("./wardrobe_runtime_inventory_export");

function response(status, body) {
  return {
    status,
    ok: status >= 200 && status < 300,
    json: async () => body,
  };
}

test("runtime extraction uses only Firestore query and Storage metadata reads",
  async () => {
    const calls = [];
    const fetchImpl = async (url, options) => {
      calls.push({url, options});
      if (url.includes("firestore.googleapis.com")) {
        return response(200, [{
          document: {
            name: "projects/p/databases/(default)/documents/" +
              "users/private-user/wardrobe/item-a",
            fields: {
              storagePath: {
                stringValue: "wardrobe/private-user/item.jpg",
              },
              imageUrl: {
                stringValue: "https://firebasestorage.googleapis.com/v0/b/" +
                  "bucket/o/wardrobe%2Fprivate-user%2Fitem.jpg" +
                  "?alt=media&token=secret",
              },
            },
          },
        }]);
      }
      return response(200, {
        name: "wardrobe/private-user/item.jpg",
        contentType: "image/jpeg",
        size: "123",
        generation: "7",
        updated: "2026-01-01T00:00:00Z",
      });
    };
    const result = await extractRuntimeInventory({
      projectId: "project",
      bucket: "bucket",
      accessToken: "memory-only-token",
      fetchImpl,
    });
    assert.equal(calls.length, 2);
    assert.equal(calls[0].options.method, "POST");
    assert.match(calls[0].url, /documents:runQuery$/);
    assert.equal(calls[1].options.method, "GET");
    assert.match(calls[1].url, /\?fields=name,contentType,size,generation,updated$/);
    assert.doesNotMatch(calls[1].url, /alt=media/);
    assert.equal(result.storageMetadata[0].sizeBytes, 123);
  });

test("output redacts UID tokens signed URLs and external URLs", () => {
  const output = redactDocument({
    documentId: "item-a",
    fields: {
      storagePath: "wardrobe/private-user/item.jpg",
      imageUrl: "https://firebasestorage.googleapis.com/v0/b/b/o/" +
        "wardrobe%2Fprivate-user%2Fitem.jpg?alt=media&token=secret",
      productLinkSeedImageUrl:
        "https://shop.example/person-name/item.jpg?X-Goog-Signature=secret",
    },
  });
  const serialized = JSON.stringify(output);
  assert.doesNotMatch(serialized,
    /private-user|token=|secret|shop\.example|person-name/);
  assert.match(serialized, /wardrobe\/\{user\}\/item\.jpg/);
  assert.equal(output.productLinkSeedImageUrl, "{external_url}");
});

test("404 Storage object is metadata-only missing result", async () => {
  let calls = 0;
  const result = await extractRuntimeInventory({
    projectId: "project",
    bucket: "bucket",
    accessToken: "token",
    fetchImpl: async (url) => {
      calls++;
      return url.includes("firestore.googleapis.com") ?
        response(200, [{
          document: {
            name: "x/wardrobe/item",
            fields: {
              storagePath: {stringValue: "wardrobe/u/missing.jpg"},
            },
          },
        }]) :
        response(404, {});
    },
  });
  assert.equal(calls, 2);
  assert.equal(result.storageMetadata[0].exists, false);
  assert.equal(result.storageMetadata[0].sizeBytes, null);
});

test("source and CLI contain no write upload download or Vision operation", () => {
  const source = fs.readFileSync(__filename.replace(".test.js", ".js"),
    "utf8");
  const cli = fs.readFileSync(path.join(__dirname, "..", "tool",
    "extract_wardrobe_runtime_inventory.cjs"), "utf8");
  const combined = `${source}\n${cli}`;
  assert.doesNotMatch(combined,
    /firebase-admin|\.set\(|\.update\(|\.delete\(|putFile|putData|upload\(/);
  assert.doesNotMatch(combined,
    /\.download\(|alt=media|analyzeClothingImage|OpenAI|parserFixture|golden/);
});
