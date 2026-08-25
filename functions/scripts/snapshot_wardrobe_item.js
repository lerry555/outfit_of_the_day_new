"use strict";

/**
 * Read-only Firestore snapshot helper for Phase 10E smoke.
 * Uses gcloud user access token (no writes).
 */

const crypto = require("node:crypto");
const {spawnSync} = require("node:child_process");

const PROJECT = "outfitoftheday-4d401";

function fp(value) {
  return crypto.createHash("sha256").update(String(value)).digest("hex").slice(0, 12);
}

function gcloudToken() {
  const cmd = process.platform === "win32" ? "gcloud.cmd" : "gcloud";
  const r = spawnSync(cmd, ["auth", "print-access-token"], {
    encoding: "utf8",
    shell: true,
  });
  if (r.status !== 0) {
    throw new Error(`gcloud_token_unavailable:${r.stderr || r.stdout}`);
  }
  return r.stdout.trim();
}

async function fetchDocument(uid, itemId) {
  const token = gcloudToken();
  const name = `projects/${PROJECT}/databases/(default)/documents/users/${uid}/wardrobe/${itemId}`;
  const url = `https://firestore.googleapis.com/v1/${name}`;
  const res = await fetch(url, {
    headers: {Authorization: `Bearer ${token}`},
  });
  if (!res.ok) {
    throw new Error(`firestore_read_failed:${res.status}`);
  }
  return res.json();
}

function fieldKeys(doc, fieldName) {
  const f = (doc.fields || {})[fieldName];
  if (!f) return {present: false, keys: []};
  if (f.mapValue && f.mapValue.fields) {
    return {present: true, keys: Object.keys(f.mapValue.fields).sort()};
  }
  return {present: true, keys: ["<non-map>"]};
}

function snapshotSummary(doc, uid, itemId) {
  const qa = fieldKeys(doc, "qualificationAuthority");
  const wp = fieldKeys(doc, "wardrobeProfile");
  const storage = (doc.fields || {}).storagePath;
  const updatedAt = (doc.fields || {}).updatedAt;
  return {
    uidFingerprint: fp(uid),
    itemFingerprint: fp(itemId),
    updateTime: doc.updateTime || null,
    createTime: doc.createTime || null,
    storagePathPresent: !!(storage && storage.stringValue),
    storagePathFingerprint: storage && storage.stringValue ?
      fp(storage.stringValue) : null,
    qualificationAuthority: qa,
    wardrobeProfile: wp,
    updatedAt: updatedAt && updatedAt.timestampValue ?
      updatedAt.timestampValue : null,
  };
}

async function main() {
  const uid = process.argv[2];
  const itemId = process.argv[3];
  if (!uid || !itemId) {
    throw new Error("usage: node snapshot_wardrobe_item.js <uid> <itemId>");
  }
  const doc = await fetchDocument(uid, itemId);
  console.log(JSON.stringify(snapshotSummary(doc, uid, itemId), null, 2));
}

if (require.main === module) {
  main().catch((err) => {
    console.error(String(err && err.message || err));
    process.exit(1);
  });
}

module.exports = {fetchDocument, snapshotSummary, fp};
