"use strict";

/**
 * Centralized redaction for wardrobe authority runtime logs/responses.
 */

const REDACTION_ID = "WardrobeAuthorityRedaction";
const REDACTION_VERSION = "wardrobe-authority-redaction-v1";
const REDACTED = "[REDACTED]";

const SENSITIVE_KEY_PATTERN = /token|password|secret|authorization|bearer|api[_-]?key|signed|download|email|service.?account|private.?key|credential/i;

function redactValue(value, key = "") {
  if (value == null) return value;
  if (typeof key === "string" && SENSITIVE_KEY_PATTERN.test(key)) {
    return REDACTED;
  }
  if (typeof value === "string") {
    if (/^Bearer\s+/i.test(value)) return REDACTED;
    if (/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\./.test(value)) return REDACTED;
    if (/X-Goog-Signature=|GoogleAccessId=|Signature=/.test(value)) {
      return REDACTED;
    }
    if (/^https?:\/\//i.test(value) &&
        /firebasestorage|googleapis|storage\.google/i.test(value)) {
      return REDACTED;
    }
    if (/^[A-Za-z]:\\/.test(value) || value.startsWith("/Users/") ||
        value.startsWith("/home/")) {
      return REDACTED;
    }
    if (key === "uid" || key === "userId" || key === "ownerUid" ||
        key === "itemId" || key === "wardrobeItemId" ||
        key === "storagePath" || key === "sourceStoragePath") {
      return fingerprint(value);
    }
    return value;
  }
  if (Array.isArray(value)) {
    return value.map((item) => redactValue(item, key));
  }
  if (typeof value === "object") {
    const out = {};
    for (const [childKey, childValue] of Object.entries(value)) {
      out[childKey] = redactValue(childValue, childKey);
    }
    return out;
  }
  return value;
}

function fingerprint(value) {
  if (typeof value !== "string" || !value) return REDACTED;
  let hash = 0;
  for (let i = 0; i < value.length; i += 1) {
    hash = ((hash << 5) - hash + value.charCodeAt(i)) | 0;
  }
  return `fp:${(hash >>> 0).toString(16).padStart(8, "0")}`;
}

function safeLogFields(fields) {
  const allowed = [
    "operationKind", "status", "reasonCode", "itemFingerprint",
    "generationFingerprint", "durationMs", "retryCount", "action",
  ];
  const out = {};
  for (const key of allowed) {
    if (Object.prototype.hasOwnProperty.call(fields, key)) {
      out[key] = redactValue(fields[key], key);
    }
  }
  return Object.freeze(out);
}

module.exports = {
  REDACTED,
  REDACTION_ID,
  REDACTION_VERSION,
  fingerprint,
  redactValue,
  safeLogFields,
};
