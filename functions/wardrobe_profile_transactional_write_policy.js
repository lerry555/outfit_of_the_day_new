"use strict";

/**
 * Node port of Dart WardrobeProfileTransactionalWritePolicy.
 * Source of truth remains:
 * lib/domain/wardrobe_profile/wardrobe_profile_persistence_repository.dart
 *
 * Pure / sync. No I/O. Does not invent evidence.
 */

const crypto = require("node:crypto");

const ENVELOPE_KEY = "wardrobeProfile";

const WRITE_STATUS = Object.freeze({
  created: "created",
  updated: "updated",
  alreadyApplied: "alreadyApplied",
  staleRejected: "staleRejected",
  revisionConflict: "revisionConflict",
  unsupportedExistingVersion: "unsupportedExistingVersion",
  invalidExistingProfile: "invalidExistingProfile",
  invalidWriteInput: "invalidWriteInput",
  notFound: "notFound",
  authorityFailure: "authorityFailure",
});

/**
 * @param {{exists:boolean, source:object|null, document:object}} current
 * @param {{
 *   userId:string,
 *   wardrobeItemId:string,
 *   envelope:object,
 *   expectedSource:object,
 *   expectedProfileRevision:number|null,
 * }} command
 */
function evaluateTransactionalWrite({current, command}) {
  const inputFailure = validateCommand(command);
  if (inputFailure) return resultOnly(inputFailure);
  if (!current.exists) {
    return resultOnly(writeResult(WRITE_STATUS.notFound, "wardrobe_item_not_found"));
  }
  if (current.source == null) {
    return resultOnly(writeResult(
      WRITE_STATUS.authorityFailure, "trusted_source_snapshot_missing"));
  }
  const sourceFailure = compareSource(command.expectedSource, current.source);
  if (sourceFailure) return resultOnly(sourceFailure);
  const mapped = command.envelope;
  const mappedSourceFailure = compareSource(command.expectedSource, {
    imageRevision: mapped.source.imageRevision,
    wardrobeItemRevision: mapped.source.wardrobeItemRevision,
    storagePath: mapped.source.storagePath ?? null,
    imageHash: mapped.source.imageHash ?? null,
    uploadGeneration: mapped.source.uploadGeneration ?? null,
  });
  if (mappedSourceFailure) return resultOnly(mappedSourceFailure);

  const existing = decodeExistingProfile(current.document);
  if (existing.status === "unsupportedVersion") {
    return resultOnly(writeResult(
      WRITE_STATUS.unsupportedExistingVersion,
      existing.failureCode || "unsupported_existing_profile"));
  }
  if (existing.status === "invalid") {
    return resultOnly(writeResult(
      WRITE_STATUS.invalidExistingProfile,
      existing.failureCode || "invalid_existing_profile"));
  }
  if (existing.status === "missing") {
    if (command.expectedProfileRevision != null) {
      return resultOnly(writeResult(
        WRITE_STATUS.revisionConflict,
        "profile_missing_but_revision_expected"));
    }
    if (mapped.metadata.revision !== 1) {
      return resultOnly(writeResult(
        WRITE_STATUS.invalidWriteInput,
        "first_profile_revision_must_be_1"));
    }
    const withCorrections = {
      ...mapped,
      userCorrections: {},
    };
    return writeDecision(WRITE_STATUS.created, "profile_created", withCorrections);
  }

  const old = existing.envelope;
  const sameIdentity =
    old.metadata.generationId === mapped.metadata.generationId &&
    old.analysis.analysisId === mapped.analysis.analysisId;
  if (sameIdentity) {
    const merged = {
      ...mapped,
      userCorrections: old.userCorrections || {},
    };
    if (fingerprint(old) === fingerprint(merged)) {
      return resultOnly(writeResult(
        WRITE_STATUS.alreadyApplied,
        "identical_generation_already_applied",
        old.metadata.revision,
        old.metadata.generationId));
    }
    return resultOnly(writeResult(
      WRITE_STATUS.revisionConflict,
      "generation_identity_reused_with_different_content",
      old.metadata.revision,
      old.metadata.generationId));
  }

  if (command.expectedProfileRevision !== old.metadata.revision) {
    return resultOnly(writeResult(
      WRITE_STATUS.revisionConflict,
      "expected_profile_revision_mismatch",
      old.metadata.revision,
      old.metadata.generationId));
  }
  if (mapped.metadata.revision !== old.metadata.revision + 1) {
    return resultOnly(writeResult(
      WRITE_STATUS.invalidWriteInput,
      "profile_revision_must_increment_by_one",
      old.metadata.revision,
      old.metadata.generationId));
  }

  const merged = {
    ...mapped,
    userCorrections: old.userCorrections || {},
  };
  return writeDecision(
    WRITE_STATUS.updated, "profile_generation_updated", merged);
}

function decodeExistingProfile(document) {
  if (!document || typeof document !== "object") {
    return {status: "missing"};
  }
  const raw = document[ENVELOPE_KEY];
  if (raw == null) return {status: "missing"};
  try {
    const envelope = decodeEnvelope(raw);
    return {status: "valid", envelope};
  } catch (error) {
    const message = String(error.message || error);
    if (message.startsWith("unsupported_")) {
      return {status: "unsupportedVersion", failureCode: message};
    }
    return {status: "invalid", failureCode: message};
  }
}

function decodeEnvelope(raw) {
  if (!isObject(raw)) fail("invalid_existing_profile");
  const metadata = requireObject(raw.metadata, "metadata");
  const schemaVersion = requireInt(metadata.schemaVersion, "schemaVersion");
  if (schemaVersion !== 1) fail(`unsupported_schema_version:${schemaVersion}`);
  const evidenceVersion = requireInt(
    metadata.evidenceSchemaVersion, "evidenceSchemaVersion");
  if (evidenceVersion !== 1) {
    fail(`unsupported_evidence_schema_version:${evidenceVersion}`);
  }
  const source = requireObject(raw.source, "source");
  const analysis = requireObject(raw.analysis, "analysis");
  if (!Array.isArray(raw.machineEvidence)) fail("machineEvidence.required_list");
  const userCorrections = raw.userCorrections == null ? {} :
    requireObject(raw.userCorrections, "userCorrections");
  return {
    metadata: {
      schemaVersion,
      evidenceSchemaVersion: evidenceVersion,
      resolverCompatibilityVersion: requirePositiveInt(
        metadata.resolverCompatibilityVersion,
        "resolverCompatibilityVersion"),
      generationId: requireNonEmpty(metadata.generationId, "generationId"),
      revision: requireNonNegativeInt(metadata.revision, "revision"),
      createdAt: requireNonEmpty(metadata.createdAt, "createdAt"),
      updatedAt: requireNonEmpty(metadata.updatedAt, "updatedAt"),
      status: requireNonEmpty(metadata.status, "status"),
    },
    source: {
      imageRevision: requireNonNegativeInt(source.imageRevision, "imageRevision"),
      wardrobeItemRevision: requireNonNegativeInt(
        source.wardrobeItemRevision, "wardrobeItemRevision"),
      storagePath: source.storagePath ?? null,
      imageHash: source.imageHash ?? null,
      uploadGeneration: source.uploadGeneration ?? null,
    },
    analysis: {
      analysisId: requireNonEmpty(analysis.analysisId, "analysisId"),
      kind: requireNonEmpty(analysis.kind, "kind"),
      completedAt: requireNonEmpty(analysis.completedAt, "completedAt"),
      modelIdentifier: requireNonEmpty(analysis.modelIdentifier, "modelIdentifier"),
      pipelineVersion: requireNonEmpty(analysis.pipelineVersion, "pipelineVersion"),
      promptVersion: requireNonEmpty(analysis.promptVersion, "promptVersion"),
      visionSchemaVersion: requirePositiveInt(
        analysis.visionSchemaVersion, "visionSchemaVersion"),
      qualificationVersion: requireNonEmpty(
        analysis.qualificationVersion, "qualificationVersion"),
    },
    machineEvidence: raw.machineEvidence,
    userCorrections,
  };
}

function validateCommand(command) {
  if (!command.userId || !String(command.userId).trim() ||
      !command.wardrobeItemId || !String(command.wardrobeItemId).trim()) {
    return writeResult(WRITE_STATUS.invalidWriteInput, "stable_identifiers_required");
  }
  if (!command.envelope || typeof command.envelope !== "object") {
    return writeResult(WRITE_STATUS.invalidWriteInput, "mapped_envelope_required");
  }
  try {
    decodeEnvelope(command.envelope);
  } catch (error) {
    return writeResult(
      WRITE_STATUS.invalidWriteInput,
      error.message || "envelope_codec_validation_failed");
  }
  return null;
}

function compareSource(expected, actual) {
  if (expected.imageRevision !== actual.imageRevision) {
    return stale("image_revision_mismatch");
  }
  if (expected.wardrobeItemRevision !== actual.wardrobeItemRevision) {
    return stale("wardrobe_item_revision_mismatch");
  }
  if (expected.uploadGeneration !== actual.uploadGeneration) {
    return stale("upload_generation_mismatch");
  }
  if (expected.storagePath !== actual.storagePath ||
      expected.imageHash !== actual.imageHash) {
    return stale("image_identity_mismatch");
  }
  return null;
}

function fingerprint(envelope) {
  return crypto.createHash("sha256")
    .update(JSON.stringify(canonicalize(envelope)))
    .digest("hex");
}

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value != null && typeof value === "object") {
    const keys = Object.keys(value).sort();
    const out = {};
    for (const key of keys) out[key] = canonicalize(value[key]);
    return out;
  }
  return value;
}

function writeDecision(status, reasonCode, envelope) {
  return Object.freeze({
    result: writeResult(
      status, reasonCode, envelope.metadata.revision, envelope.metadata.generationId),
    documentPatch: Object.freeze({
      [ENVELOPE_KEY]: envelope,
    }),
  });
}

function resultOnly(result) {
  return Object.freeze({result, documentPatch: null});
}

function writeResult(status, reasonCode, currentRevision = null,
  currentGenerationId = null) {
  return Object.freeze({
    status,
    reasonCode,
    currentRevision,
    currentGenerationId,
  });
}

function stale(reasonCode) {
  return writeResult(WRITE_STATUS.staleRejected, reasonCode);
}

function requireObject(value, label) {
  if (!isObject(value)) fail(`${label}_not_object`);
  return value;
}

function requireNonEmpty(value, label) {
  if (typeof value !== "string" || !value.trim()) fail(`${label}_empty`);
  return value.trim();
}

function requireInt(value, label) {
  if (!Number.isInteger(value)) fail(`${label}_invalid`);
  return value;
}

function requirePositiveInt(value, label) {
  const n = requireInt(value, label);
  if (n <= 0) fail(`${label}_invalid`);
  return n;
}

function requireNonNegativeInt(value, label) {
  const n = requireInt(value, label);
  if (n < 0) fail(`${label}_invalid`);
  return n;
}

function isObject(value) {
  return value != null && typeof value === "object" && !Array.isArray(value);
}

function fail(code) {
  throw new Error(code);
}

module.exports = {
  ENVELOPE_KEY,
  WRITE_STATUS,
  decodeExistingProfile,
  decodeEnvelope,
  evaluateTransactionalWrite,
  fingerprint,
};
