"use strict";

const fs = require("node:fs");
const crypto = require("node:crypto");

const raw = fs.readFileSync(process.argv[2], "utf8");
const start = raw.indexOf("[");
const data = JSON.parse(raw.slice(start));

function fp(s) {
  return crypto.createHash("sha256").update(String(s)).digest("hex").slice(0, 12);
}

function field(doc, name) {
  const f = (doc.fields || {})[name];
  if (!f) return null;
  if (f.stringValue != null) return f.stringValue;
  if (f.mapValue) {
    return {map: true, keys: Object.keys(f.mapValue.fields || {})};
  }
  if (f.timestampValue) return f.timestampValue;
  return f;
}

const out = [];
for (const row of data) {
  const doc = row.document;
  if (!doc) continue;
  const m = doc.name.match(/documents\/users\/([^/]+)\/wardrobe\/([^/]+)$/);
  if (!m) continue;
  const storagePath = field(doc, "storagePath");
  out.push({
    uidFp: fp(m[1]),
    itemFp: fp(m[2]),
    uid: m[1],
    itemId: m[2],
    storagePath: storagePath || null,
    hasStoragePath: !!storagePath,
    hasQA: !!field(doc, "qualificationAuthority"),
    hasWP: !!field(doc, "wardrobeProfile"),
    updatedAt: field(doc, "updatedAt"),
  });
}
out.sort((a, b) => Number(b.hasStoragePath) - Number(a.hasStoragePath));
console.log(JSON.stringify(out, null, 2));
