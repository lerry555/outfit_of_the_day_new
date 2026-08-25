"use strict";

/**
 * Shopping Phase 8 — Real Partner Onboarding Foundation
 * Public module surface. No production deploy / polling / live retailers.
 */

const partnerCapabilities = require("./partner_capabilities");
const partnerAdapterContract = require("./partner_adapter_contract");
const partnerConfig = require("./partner_config");
const partnerSecrets = require("./partner_secrets");
const partnerErrors = require("./partner_errors");
const partnerRetry = require("./partner_retry");
const partnerRateLimit = require("./partner_rate_limit");
const partnerImages = require("./partner_images");
const partnerRawRetention = require("./partner_raw_retention");
const partnerSyncOrchestrator = require("./partner_sync_orchestrator");
const partnerNormalize = require("./partner_normalize");
const registry = require("./registry");
const genericHttp = require("./generic_http_adapter_skeleton");
const mockHttp = require("./http/mock_partner_http");
const partnerA = require("./synthetic/partner_a");
const partnerB = require("./synthetic/partner_b");
const partnerC = require("./synthetic/partner_c");
const cjSchema = require("./cj/cj_product_feed_schema");
const cjParser = require("./cj/cj_product_feed_parser");
const cjAuth = require("./cj/cj_auth_contract");
const reserved = require("./reserved");

const PARTNER_ONBOARDING_CHECKLIST = Object.freeze([
  {id: "retailer_legal_entity", ownerDecision: true},
  {id: "market", ownerDecision: true},
  {id: "official_data_api_feed_source", ownerDecision: true},
  {id: "api_feed_documentation", ownerDecision: false},
  {id: "authentication_method", ownerDecision: false},
  {id: "credentials_secrets", ownerDecision: true},
  {id: "rate_limits", ownerDecision: false},
  {id: "data_license_usage_rights", ownerDecision: true, legal: true},
  {id: "product_image_usage_rights", ownerDecision: true, legal: true},
  {id: "affiliate_relationship", ownerDecision: true, rankingNeutral: true},
  {id: "stable_product_ids", ownerDecision: false},
  {id: "stable_variant_ids", ownerDecision: false},
  {id: "gtin_sku_availability", ownerDecision: false},
  {id: "price_semantics", ownerDecision: false},
  {id: "promotion_semantics", ownerDecision: false},
  {id: "size_data", ownerDecision: false},
  {id: "stock_quantity_reliability", ownerDecision: false},
  {id: "image_fields_roles", ownerDecision: false},
  {id: "update_frequency", ownerDecision: false},
  {id: "webhook_polling_incremental", ownerDecision: false},
  {id: "deletion_discontinued_semantics", ownerDecision: false},
  {id: "test_sandbox_availability", ownerDecision: false},
]);

module.exports = {
  PARTNER_ONBOARDING_CHECKLIST,
  ...partnerCapabilities,
  ...partnerAdapterContract,
  ...partnerConfig,
  ...partnerSecrets,
  ...partnerErrors,
  ...partnerRetry,
  ...partnerRateLimit,
  ...partnerImages,
  ...partnerRawRetention,
  ...partnerSyncOrchestrator,
  ...partnerNormalize,
  ...registry,
  ...genericHttp,
  ...mockHttp,
  partnerA,
  partnerB,
  partnerC,
  cjSchema,
  cjParser,
  cjAuth,
  reserved,
};
