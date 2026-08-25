"use strict";

/**
 * TrustedVisionAnalysisClient/v1 — offline fake fixture client.
 *
 * Returns captured parser fixtures. Never calls OpenAI / live Vision.
 */

const fs = require("node:fs");
const path = require("node:path");

const CLIENT_ID = "TrustedVisionAnalysisClient";
const CLIENT_VERSION = "trusted-vision-analysis-client-v1";
const CLIENT_CONTRACT = "TrustedVisionAnalysisClient/v1";

const DEFAULT_FIXTURE_ROOT = path.resolve(__dirname, "../test/fixtures/" +
  "backend_qualification");

/**
 * @param {{fixtureRoot?: string, scenarios?: Record<string, object>}} [options]
 */
function createFakeTrustedVisionAnalysisClient(options = {}) {
  const fixtureRoot = options.fixtureRoot || DEFAULT_FIXTURE_ROOT;
  const scenarios = options.scenarios || null;

  return Object.freeze({
    clientId: CLIENT_ID,
    clientVersion: CLIENT_VERSION,
    clientContract: CLIENT_CONTRACT,
    liveModelCalls: 0,

    /**
     * @param {{
     *   scenarioId?: string,
     *   itemId: string,
     *   sourceStoragePath?: string,
     * }} request
     */
    async analyzeCurrentSource(request) {
      if (request == null || typeof request !== "object") {
        fail("vision_client_request_not_object");
      }
      if (request.imageBytes != null || request.signedUrl != null ||
          request.downloadURL != null) {
        fail("vision_client_rejects_bytes_or_signed_url");
      }
      const scenarioId = requireNonEmpty(
        request.scenarioId || request.fixtureId, "scenarioId");
      let parser;
      if (scenarios && Object.prototype.hasOwnProperty.call(scenarios, scenarioId)) {
        parser = structuredClone(scenarios[scenarioId]);
      } else {
        const parserPath = path.join(
          fixtureRoot, "parser", `${scenarioId}.parser.json`);
        if (!fs.existsSync(parserPath)) {
          fail(`vision_parser_fixture_missing:${scenarioId}`);
        }
        parser = JSON.parse(fs.readFileSync(parserPath, "utf8"));
      }
      validateParserFixture(parser, scenarioId);
      return deepFreeze({
        contractVersion: 1,
        clientContract: CLIENT_CONTRACT,
        scenarioId,
        itemId: requireNonEmpty(request.itemId, "itemId"),
        parser,
        provenance: Object.freeze({
          source: "offline_parser_fixture",
          liveModel: false,
          fixtureId: parser.fixtureId,
          captureDataset: parser.captureDataset ?? null,
        }),
      });
    },
  });
}

function validateParserFixture(parser, scenarioId) {
  if (parser == null || typeof parser !== "object" || Array.isArray(parser)) {
    fail("parser_fixture_not_object");
  }
  if (parser.fixtureContractVersion !== 1) {
    fail("parser_fixture_contract_unsupported");
  }
  if (parser.fixtureId !== scenarioId) {
    fail("parser_fixture_id_mismatch");
  }
  if (!Array.isArray(parser.views) || parser.views.length === 0) {
    fail("parser_fixture_views_missing");
  }
  for (const view of parser.views) {
    if (view.response == null || typeof view.response !== "object") {
      fail("parser_fixture_response_missing");
    }
    if (typeof view.response.analysisId !== "string" ||
        !view.response.analysisId.trim()) {
      fail("parser_fixture_analysis_id_missing");
    }
    if (!Number.isInteger(view.response.schemaVersion) ||
        view.response.schemaVersion < 1) {
      fail("parser_fixture_schema_invalid");
    }
  }
}

function requireNonEmpty(value, label) {
  if (typeof value !== "string" || !value.trim()) fail(`${label}_empty`);
  return value.trim();
}

function deepFreeze(value) {
  if (value == null || typeof value !== "object") return value;
  if (Object.isFrozen(value)) return value;
  for (const child of Object.values(value)) deepFreeze(child);
  return Object.freeze(value);
}

function fail(code) {
  throw new Error(code);
}

module.exports = {
  CLIENT_CONTRACT,
  CLIENT_ID,
  CLIENT_VERSION,
  createFakeTrustedVisionAnalysisClient,
  validateParserFixture,
};
