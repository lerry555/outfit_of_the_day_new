"use strict";

const {
  parseFirebaseStoragePath,
  redactStoragePath,
} = require("./wardrobe_image_inventory");

const EXPORTED_FIELDS = Object.freeze([
  "storagePath",
  "cleanStoragePath",
  "productStoragePath",
  "imageUrl",
  "originalImageUrl",
  "cleanImageUrl",
  "cutoutImageUrl",
  "productImageUrl",
  "productLinkSeedImageUrl",
  "thumbnailUrl",
]);

async function extractRuntimeInventory({
  projectId,
  bucket,
  accessToken,
  fetchImpl = fetch,
}) {
  requireText(projectId, "project_id_required");
  requireText(bucket, "storage_bucket_required");
  requireText(accessToken, "access_token_required");

  const documents = await queryWardrobeDocuments({
    projectId, accessToken, fetchImpl,
  });
  const storagePaths = collectStoragePaths(documents);
  const storageMetadata = [];
  for (const storagePath of storagePaths) {
    storageMetadata.push(await readStorageMetadata({
      bucket, storagePath, accessToken, fetchImpl,
    }));
  }
  return {
    documents: documents.map(redactDocument),
    storageMetadata,
  };
}

async function queryWardrobeDocuments({
  projectId,
  accessToken,
  fetchImpl,
  fieldPaths = EXPORTED_FIELDS,
}) {
  const endpoint =
    `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(projectId)}` +
    "/databases/(default)/documents:runQuery";
  const response = await fetchImpl(endpoint, {
    method: "POST",
    headers: authorizationHeaders(accessToken),
    body: JSON.stringify({
      structuredQuery: {
        from: [{collectionId: "wardrobe", allDescendants: true}],
        select: {
          fields: fieldPaths.map((fieldPath) => ({fieldPath})),
        },
      },
    }),
  });
  if (!response.ok) {
    throw new Error(`firestore_read_failed:${response.status}`);
  }
  const rows = await response.json();
  return rows
    .filter((row) => row.document)
    .map((row) => ({
      documentId: row.document.name.split("/").pop(),
      fields: decodeFirestoreFields(row.document.fields || {}),
    }))
    .sort((a, b) => a.documentId.localeCompare(b.documentId));
}

async function readStorageMetadata({
  bucket,
  storagePath,
  accessToken,
  fetchImpl,
}) {
  const endpoint =
    `https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(bucket)}` +
    `/o/${encodeURIComponent(storagePath)}` +
    "?fields=name,contentType,size,generation,updated";
  const response = await fetchImpl(endpoint, {
    method: "GET",
    headers: authorizationHeaders(accessToken),
  });
  if (response.status === 404) {
    return {
      storagePath: redactStoragePath(storagePath),
      exists: false,
      contentType: null,
      sizeBytes: null,
      generation: null,
      updated: null,
    };
  }
  if (!response.ok) {
    throw new Error(`storage_metadata_read_failed:${response.status}`);
  }
  const metadata = await response.json();
  return {
    storagePath: redactStoragePath(storagePath),
    exists: true,
    contentType: text(metadata.contentType),
    sizeBytes: safeInteger(metadata.size),
    generation: text(metadata.generation),
    updated: text(metadata.updated),
  };
}

function collectStoragePaths(documents) {
  const paths = new Set();
  for (const document of documents) {
    const fields = document.fields;
    for (const field of ["storagePath", "cleanStoragePath",
      "productStoragePath"]) {
      const value = text(fields[field]);
      if (isStoragePath(value)) paths.add(value);
    }
    for (const field of EXPORTED_FIELDS.filter((item) =>
      item.toLowerCase().includes("url"))) {
      const parsed = parseFirebaseStoragePath(fields[field]);
      if (parsed) paths.add(parsed);
    }
  }
  return [...paths].sort();
}

function redactDocument(document) {
  const fields = {};
  for (const field of EXPORTED_FIELDS) {
    const value = text(document.fields[field]);
    if (!value) {
      fields[field] = null;
    } else if (field.toLowerCase().includes("url")) {
      fields[field] = redactImageReference(value);
    } else {
      fields[field] = isStoragePath(value) ?
        redactStoragePath(value) : null;
    }
  }
  return {documentId: document.documentId, ...fields};
}

function redactImageReference(value) {
  const storagePath = parseFirebaseStoragePath(value);
  if (storagePath) return `storage://${redactStoragePath(storagePath)}`;
  return "{external_url}";
}

function decodeFirestoreFields(fields) {
  return Object.fromEntries(Object.entries(fields).map(([key, value]) =>
    [key, decodeFirestoreValue(value)]));
}

function decodeFirestoreValue(value) {
  if (value && typeof value.stringValue === "string") {
    return value.stringValue;
  }
  return null;
}

function authorizationHeaders(accessToken) {
  return {
    "Authorization": `Bearer ${accessToken}`,
    "Content-Type": "application/json",
  };
}

function isStoragePath(value) {
  return typeof value === "string" &&
    /^(wardrobe|wardrobe_clean|wardrobe_product)\//.test(value) &&
    !value.includes("..") && !value.includes("://");
}
function requireText(value, reason) {
  if (!text(value)) throw new Error(reason);
}
function text(value) {
  if (typeof value !== "string") return null;
  return value.trim() || null;
}
function safeInteger(value) {
  const number = Number(value);
  return Number.isSafeInteger(number) && number >= 0 ? number : null;
}

module.exports = {
  EXPORTED_FIELDS,
  collectStoragePaths,
  extractRuntimeInventory,
  queryWardrobeDocuments,
  redactDocument,
  redactImageReference,
  readStorageMetadata,
};
