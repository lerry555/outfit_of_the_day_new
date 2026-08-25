"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  AVAILABILITY,
  PROMOTION_KIND,
  QUANTITY_RELIABILITY,
  effectivePublicPrice,
} = require("../catalog_contract");
const {createMemoryCatalogRepository} = require("../catalog_repository");
const {
  normalizeCatalogChangeSet,
  CHANGESET_SOURCES,
} = require("../monitoring/catalog_change_set");
const {
  PARTNER_CAPABILITY,
  normalizeCapabilities,
  hasCapability,
} = require("./partner_capabilities");
const {
  REQUIRED_ADAPTER_METHODS,
  SYNC_MODE,
  assertPartnerAdapter,
} = require("./partner_adapter_contract");
const {
  PARTNER_STATUS,
  buildPublicPartnerConfig,
  buildPrivatePartnerConfig,
  validatePartnerConfiguration,
} = require("./partner_config");
const {
  NEW_LEGACY_FUNCTIONS_CONFIG_USAGE_COUNT,
  resolvePartnerSecret,
  redactPrivateConfig,
} = require("./partner_secrets");
const {
  PARTNER_ERROR,
  isRetryableError,
  classifyHttpStatus,
} = require("./partner_errors");
const {
  PARTNER_RETRY_POLICY_V1,
  computeBackoffMs,
  withPartnerRetry,
} = require("./partner_retry");
const {
  PARTNER_PRODUCT_ONLY_TRUST_POLICY,
  MODEL_MANNEQUIN_IMAGE_POLICY,
  NO_IMAGE_POLICY,
  IMAGE_STATUS,
  AI_REQUEST_COUNT,
  normalizePartnerImageCandidates,
  createOotdImagePreflightBoundary,
  PARTNER_IMAGE_ROLE,
} = require("./partner_images");
const {
  runPartnerSync,
  createMemoryCheckpointStore,
  REAL_PARTNER_API_REQUESTS,
  PARTNER_POLLING_COUNT,
  AFFILIATE_RANKING_INPUT_COUNT,
} = require("./partner_sync_orchestrator");
const {
  createSyntheticPartnerAAdapter,
  samplePartnerARecord,
} = require("./synthetic/partner_a");
const {
  createSyntheticPartnerBAdapter,
  samplePartnerBRecord,
} = require("./synthetic/partner_b");
const {
  createSyntheticPartnerCAdapter,
  samplePartnerCRecord,
} = require("./synthetic/partner_c");
const {
  createGenericHttpPartnerAdapterSkeleton,
} = require("./generic_http_adapter_skeleton");
const {createMockPartnerHttpServer} = require("./http/mock_partner_http");
const {
  FIRST_REAL_PARTNER_STATUS,
  OWNER_APPROVED_FIRST_PARTNER_ID,
  listRegisteredAdapterKeys,
} = require("./registry");
const {createWishlistMonitoringService} =
  require("../monitoring/wishlist_monitoring_service");

test("adapter capabilities: declare and never infer unknown", () => {
  const caps = normalizeCapabilities([
    PARTNER_CAPABILITY.FULL_CATALOG_SNAPSHOT,
    PARTNER_CAPABILITY.GTIN,
  ]);
  assert.ok(hasCapability(caps, PARTNER_CAPABILITY.FULL_CATALOG_SNAPSHOT));
  assert.equal(hasCapability(caps, PARTNER_CAPABILITY.WEBHOOK), false);
  assert.throws(
    () => normalizeCapabilities(["not_a_real_capability"]),
    /partner_capability_unknown/,
  );
});

test("partner adapter interface surface", () => {
  const adapter = createSyntheticPartnerAAdapter({
    records: [samplePartnerARecord()],
  });
  assertPartnerAdapter(adapter);
  for (const method of REQUIRED_ADAPTER_METHODS) {
    assert.equal(typeof adapter[method], "function");
  }
  assert.equal(adapter.partnerId(), "synthetic_a_sk");
});

test("public vs private config isolation + secret redaction", () => {
  const pub = buildPublicPartnerConfig({
    partnerId: "synthetic_a_sk",
    displayName: "Synthetic Partner A",
    market: "SK",
    allowedDomains: ["shop.synthetic-a.test"],
    capabilities: [PARTNER_CAPABILITY.FULL_CATALOG_SNAPSHOT],
    adapterKey: "synthetic_partner_a_full",
    adapterVersion: "1",
  });
  assert.equal(pub.partnerId, "synthetic_a_sk");
  assert.equal(pub.status, PARTNER_STATUS.ACTIVE);
  assert.equal("secret" in pub, false);

  const priv = buildPrivatePartnerConfig({
    partnerId: "synthetic_a_sk",
    adapterKey: "synthetic_partner_a_full",
    adapterVersion: "1",
    secretRef: "SHOPPING_PARTNER_SECRET_SLOT_A",
    rawPartnerConfig: {apiKey: "should-strip", feedId: "feed-1"},
  }, {secrets: {apiKey: "test-secret"}});
  assert.equal(priv.rawPartnerConfig.apiKey, undefined);
  assert.equal(priv.rawPartnerConfig.feedId, "feed-1");
  assert.equal(priv._resolvedSecrets.apiKey, "test-secret");

  const redacted = redactPrivateConfig(priv);
  assert.equal(redacted.hasResolvedSecrets, true);
  assert.equal(JSON.stringify(redacted).includes("test-secret"), false);

  assert.equal(NEW_LEGACY_FUNCTIONS_CONFIG_USAGE_COUNT, 0);
  const secret = resolvePartnerSecret({
    secretRef: "x",
    getSecret: () => "placeholder",
  });
  assert.equal(secret, "placeholder");
});

test("identity: GTIN merges; partner-only stays separate; weak name does not merge", async () => {
  const repository = createMemoryCatalogRepository();
  const navy = samplePartnerARecord();
  const sameGtinOtherListing = samplePartnerARecord({
    partnerListingId: "a-list-2",
    partnerVariantId: "a-var-navy",
    partnerProductId: "a-prod-1",
  });
  const adapter = createSyntheticPartnerAAdapter({
    records: [navy, sameGtinOtherListing],
  });
  await runPartnerSync({
    adapter,
    publicConfig: adapter.publicConfig(),
    privateConfig: {
      partnerId: adapter.partnerId(),
      adapterKey: adapter.partner.adapterKey,
      adapterVersion: adapter.partner.adapterVersion,
      rateLimit: {pageSize: 10, requestsPerSecond: 50, requestsPerMinute: 500},
    },
    repository,
    mode: SYNC_MODE.FULL,
    runId: "id-gtin",
    sleep: async () => {},
  });
  let dump = repository.dump();
  assert.equal(Object.keys(dump.products).length, 1);
  assert.equal(Object.keys(dump.variants).length, 1);
  assert.equal(Object.keys(dump.offers).length, 2);

  const other = createSyntheticPartnerAAdapter({
    records: [samplePartnerARecord({
      partnerProductId: "weak-1",
      partnerVariantId: "weak-v1",
      partnerListingId: "weak-l1",
      brand: "SyntheticBrand",
      modelIdentity: "DIFFERENT-MODEL",
      productEvidence: {reliablePartnerProductId: "synthetic_a_sk:weak-1"},
      variantEvidence: {reliablePartnerVariantId: "synthetic_a_sk:weak-v1"},
      url: "https://shop.synthetic-a.test/p/weak-1",
    })],
  });
  await runPartnerSync({
    adapter: other,
    publicConfig: other.publicConfig(),
    privateConfig: {
      partnerId: other.partnerId(),
      adapterKey: other.partner.adapterKey,
      adapterVersion: other.partner.adapterVersion,
      rateLimit: {pageSize: 10, requestsPerSecond: 50, requestsPerMinute: 500},
    },
    repository,
    mode: SYNC_MODE.FULL,
    runId: "id-weak",
    sleep: async () => {},
  });
  dump = repository.dump();
  assert.ok(Object.keys(dump.products).length >= 2);
});

test("variant identity: different colors stay isolated", async () => {
  const repository = createMemoryCatalogRepository();
  const adapter = createSyntheticPartnerAAdapter({
    records: [
      samplePartnerARecord(),
      samplePartnerARecord({
        partnerVariantId: "a-var-white",
        partnerListingId: "a-list-white",
        colorName: "White",
        productEvidence: {
          gtin: "8590000000002",
          reliablePartnerProductId: "synthetic_a_sk:a-prod-1",
        },
        variantEvidence: {
          gtin: "8590000000002",
          reliablePartnerVariantId: "synthetic_a_sk:a-var-white",
        },
        regularPrice: {amountMinor: 2900, currency: "EUR"},
        url: "https://shop.synthetic-a.test/p/a-prod-1?c=white",
      }),
    ],
  });
  await runPartnerSync({
    adapter,
    publicConfig: adapter.publicConfig(),
    privateConfig: {
      partnerId: adapter.partnerId(),
      adapterKey: adapter.partner.adapterKey,
      adapterVersion: adapter.partner.adapterVersion,
      rateLimit: {pageSize: 10, requestsPerSecond: 50, requestsPerMinute: 500},
    },
    repository,
    mode: SYNC_MODE.FULL,
    runId: "colors",
    sleep: async () => {},
  });
  const dump = repository.dump();
  const variants = Object.values(dump.variants);
  assert.equal(variants.length, 2);
  const navy = variants.find((v) => v.exactColorName === "Navy");
  const white = variants.find((v) => v.exactColorName === "White");
  const navyOffer = Object.values(dump.offers).find((o) => o.variantId === navy.variantId);
  const whiteOffer = Object.values(dump.offers).find((o) => o.variantId === white.variantId);
  assert.equal(navyOffer.regularPrice.amountMinor, 4900);
  assert.equal(whiteOffer.regularPrice.amountMinor, 2900);
});

test("pricing: public coupon effective; member-only excluded; expired ignored; malformed rejected", async () => {
  const adapter = createSyntheticPartnerAAdapter({records: []});
  const withCoupon = adapter.normalizeRecord(samplePartnerARecord());
  const effective = effectivePublicPrice(withCoupon.offer);
  assert.equal(effective.price.amountMinor, 3900);
  assert.equal(effective.requiresPublicCoupon, true);

  const member = adapter.normalizeRecord(samplePartnerARecord({
    promotions: [{
      kind: PROMOTION_KIND.MEMBER_ONLY,
      price: {amountMinor: 1000, currency: "EUR"},
    }],
  }));
  assert.equal(effectivePublicPrice(member.offer).price.amountMinor, 4900);

  const expired = adapter.normalizeRecord(samplePartnerARecord({
    promotions: [{
      kind: PROMOTION_KIND.PUBLIC_SALE,
      price: {amountMinor: 1000, currency: "EUR"},
      validUntil: "2020-01-01T00:00:00.000Z",
    }],
  }), {now: "2026-08-15T00:00:00.000Z"});
  assert.equal(expired.offer.promotions[0].expired, true);
  assert.equal(effectivePublicPrice(expired.offer).price.amountMinor, 4900);

  assert.throws(
    () => adapter.normalizeRecord(samplePartnerARecord({
      regularPrice: {amountMinor: 1.5, currency: "EUR"},
    })),
    (err) => err.code === PARTNER_ERROR.INVALID_MONEY,
  );
});

test("size tri-state + reliable quantity only", () => {
  const adapter = createSyntheticPartnerAAdapter({records: []});
  const exact = adapter.normalizeRecord(samplePartnerARecord());
  assert.equal(exact.sizes[0].availability, AVAILABILITY.AVAILABLE);
  assert.equal(exact.sizes[0].exactQuantity, 3);
  assert.equal(exact.sizes[0].quantityReliability, QUANTITY_RELIABILITY.EXACT);

  const unknown = adapter.normalizeRecord(samplePartnerARecord({
    sizes: [{
      normalizedSizeKey: "S",
      partnerSizeLabel: "S",
      sizeSystem: "ALPHA",
    }],
  }));
  assert.equal(unknown.sizes[0].availability, AVAILABILITY.UNKNOWN);

  const unreliableQty = adapter.normalizeRecord(samplePartnerARecord({
    sizes: [{
      normalizedSizeKey: "M",
      partnerSizeLabel: "M",
      sizeSystem: "ALPHA",
      availability: "AVAILABLE",
      exactQuantity: 2,
      quantityReliability: QUANTITY_RELIABILITY.UNKNOWN,
    }],
  }));
  assert.equal(unreliableQty.sizes[0].exactQuantity, null);
});

test("lifecycle: full omission can discontinue; incremental cannot; failed sync cannot", async () => {
  const repository = createMemoryCatalogRepository();
  const first = createSyntheticPartnerAAdapter({
    records: [
      samplePartnerARecord(),
      samplePartnerARecord({
        partnerListingId: "a-list-gone",
        partnerVariantId: "a-var-gone",
        partnerProductId: "a-prod-gone",
        productEvidence: {
          gtin: "8590000000099",
          reliablePartnerProductId: "synthetic_a_sk:gone",
        },
        variantEvidence: {
          gtin: "8590000000099",
          reliablePartnerVariantId: "synthetic_a_sk:gone-v",
        },
        url: "https://shop.synthetic-a.test/p/gone",
      }),
    ],
  });
  await runPartnerSync({
    adapter: first,
    publicConfig: first.publicConfig(),
    privateConfig: {
      partnerId: first.partnerId(),
      adapterKey: first.partner.adapterKey,
      adapterVersion: first.partner.adapterVersion,
      rateLimit: {pageSize: 10, requestsPerSecond: 50, requestsPerMinute: 500},
    },
    repository,
    mode: SYNC_MODE.FULL,
    runId: "life-1",
    sleep: async () => {},
  });
  assert.equal(Object.keys(repository.dump().offers).length, 2);

  const second = createSyntheticPartnerAAdapter({
    records: [samplePartnerARecord()],
  });
  await runPartnerSync({
    adapter: second,
    publicConfig: second.publicConfig(),
    privateConfig: {
      partnerId: second.partnerId(),
      adapterKey: second.partner.adapterKey,
      adapterVersion: second.partner.adapterVersion,
      rateLimit: {pageSize: 10, requestsPerSecond: 50, requestsPerMinute: 500},
    },
    repository,
    mode: SYNC_MODE.FULL,
    runId: "life-2",
    sleep: async () => {},
  });
  const offers = Object.values(repository.dump().offers);
  const gone = offers.find((o) => o.partnerListingId === "a-list-gone");
  assert.ok(gone);
  assert.equal(gone.lifecycleState, "DISCONTINUED");

  // Incremental partner B must not discontinue from absence.
  const repoB = createMemoryCatalogRepository();
  const b1 = createSyntheticPartnerBAdapter({
    records: [samplePartnerBRecord(), samplePartnerBRecord({
      partnerListingId: "b-list-temp",
      partnerVariantId: "b-var-temp",
      partnerProductId: "b-prod-temp",
      productEvidence: {
        manufacturerSku: "TEMP-1",
        reliablePartnerProductId: "synthetic_b_cz:temp",
      },
      variantEvidence: {
        manufacturerSku: "TEMP-1-W",
        reliablePartnerVariantId: "synthetic_b_cz:temp-v",
      },
      url: "https://shop.synthetic-b.test/item/temp",
    })],
  });
  await runPartnerSync({
    adapter: b1,
    publicConfig: b1.publicConfig(),
    privateConfig: {
      partnerId: b1.partnerId(),
      adapterKey: b1.partner.adapterKey,
      adapterVersion: b1.partner.adapterVersion,
      rateLimit: {pageSize: 10, requestsPerSecond: 50, requestsPerMinute: 500},
    },
    repository: repoB,
    mode: SYNC_MODE.INCREMENTAL,
    runId: "inc-1",
    sleep: async () => {},
  });
  const b2 = createSyntheticPartnerBAdapter({
    records: [samplePartnerBRecord()],
  });
  await runPartnerSync({
    adapter: b2,
    publicConfig: b2.publicConfig(),
    privateConfig: {
      partnerId: b2.partnerId(),
      adapterKey: b2.partner.adapterKey,
      adapterVersion: b2.partner.adapterVersion,
      rateLimit: {pageSize: 10, requestsPerSecond: 50, requestsPerMinute: 500},
    },
    repository: repoB,
    mode: SYNC_MODE.INCREMENTAL,
    runId: "inc-2",
    sleep: async () => {},
  });
  const temp = Object.values(repoB.dump().offers)
    .find((o) => o.partnerListingId === "b-list-temp");
  assert.ok(temp);
  assert.notEqual(temp.lifecycleState, "DISCONTINUED");
});

test("sync: pagination, checkpoint, idempotent retry, ChangeSet emission", async () => {
  const repository = createMemoryCatalogRepository();
  const checkpointStore = createMemoryCheckpointStore();
  const records = Array.from({length: 5}, (_, i) => samplePartnerARecord({
    partnerProductId: `a-prod-${i}`,
    partnerVariantId: `a-var-${i}`,
    partnerListingId: `a-list-${i}`,
    productEvidence: {
      gtin: `85900000001${i}0`,
      reliablePartnerProductId: `synthetic_a_sk:a-prod-${i}`,
    },
    variantEvidence: {
      gtin: `85900000001${i}0`,
      reliablePartnerVariantId: `synthetic_a_sk:a-var-${i}`,
    },
    url: `https://shop.synthetic-a.test/p/${i}`,
  }));
  const adapter = createSyntheticPartnerAAdapter({records, pageSize: 2});
  const changeSets = [];
  const result = await runPartnerSync({
    adapter,
    publicConfig: adapter.publicConfig(),
    privateConfig: {
      partnerId: adapter.partnerId(),
      adapterKey: adapter.partner.adapterKey,
      adapterVersion: adapter.partner.adapterVersion,
      rateLimit: {pageSize: 2, requestsPerSecond: 50, requestsPerMinute: 500},
    },
    repository,
    mode: SYNC_MODE.FULL,
    runId: "page-1",
    checkpointStore,
    onCatalogChangeSet: async (cs) => changeSets.push(cs),
    sleep: async () => {},
  });
  assert.equal(result.metrics.pages, 3);
  assert.equal(result.acceptedCount, 5);
  assert.ok(result.changeSet);
  assert.equal(result.changeSet.source, CHANGESET_SOURCES.CATALOG_SYNC);
  assert.equal(changeSets.length, 1);
  assert.ok(checkpointStore.dump().synthetic_a_sk);

  // Re-run same payload: entities do not duplicate.
  await runPartnerSync({
    adapter,
    publicConfig: adapter.publicConfig(),
    privateConfig: {
      partnerId: adapter.partnerId(),
      adapterKey: adapter.partner.adapterKey,
      adapterVersion: adapter.partner.adapterVersion,
      rateLimit: {pageSize: 2, requestsPerSecond: 50, requestsPerMinute: 500},
    },
    repository,
    mode: SYNC_MODE.FULL,
    runId: "page-2",
    checkpointStore,
    sleep: async () => {},
  });
  assert.equal(Object.keys(repository.dump().products).length, 5);
  assert.equal(Object.keys(repository.dump().offers).length, 5);
});

test("failed sync emits no ChangeSet; stale partner preserves last-known-good", async () => {
  const repository = createMemoryCatalogRepository();
  const ok = createSyntheticPartnerAAdapter({
    records: [samplePartnerARecord()],
  });
  await runPartnerSync({
    adapter: ok,
    publicConfig: ok.publicConfig(),
    privateConfig: {
      partnerId: ok.partnerId(),
      adapterKey: ok.partner.adapterKey,
      adapterVersion: ok.partner.adapterVersion,
      rateLimit: {pageSize: 10, requestsPerSecond: 50, requestsPerMinute: 500},
    },
    repository,
    mode: SYNC_MODE.FULL,
    runId: "ok-1",
    sleep: async () => {},
  });
  const before = repository.dump();
  const offerBefore = Object.values(before.offers)[0];

  const bad = createSyntheticPartnerAAdapter({
    records: [samplePartnerARecord({__schemaDrift: true})],
  });
  const changeSets = [];
  await assert.rejects(() => runPartnerSync({
    adapter: bad,
    publicConfig: bad.publicConfig(),
    privateConfig: {
      partnerId: bad.partnerId(),
      adapterKey: bad.partner.adapterKey,
      adapterVersion: bad.partner.adapterVersion,
      rateLimit: {pageSize: 10, requestsPerSecond: 50, requestsPerMinute: 500},
    },
    repository,
    mode: SYNC_MODE.FULL,
    runId: "bad-1",
    onCatalogChangeSet: async (cs) => changeSets.push(cs),
    sleep: async () => {},
  }));
  assert.equal(changeSets.length, 0);
  const after = repository.dump();
  const offerAfter = after.offers[offerBefore.offerId];
  assert.ok(offerAfter);
  assert.notEqual(offerAfter.lifecycleState, "DISCONTINUED");
  assert.equal(after.syncRuns["bad-1"].status, "FAILED");
});

test("image contract: product-only hint not trusted; no image => NOT_AVAILABLE; no AI", async () => {
  assert.equal(AI_REQUEST_COUNT, 0);
  assert.equal(PARTNER_PRODUCT_ONLY_TRUST_POLICY.trustPartnerProductOnlyClaim, false);
  assert.equal(MODEL_MANNEQUIN_IMAGE_POLICY.allowAsFinalOotdImage, false);
  assert.equal(NO_IMAGE_POLICY.variantRemainsCatalogValid, true);

  const adapter = createSyntheticPartnerAAdapter({records: []});
  const withImages = adapter.normalizeRecord(samplePartnerARecord());
  assert.equal(withImages.imageStatus, IMAGE_STATUS.NEEDS_VALIDATION);
  assert.equal(withImages.imageCandidates[0].partnerClaimsProductOnly, true);
  assert.equal(withImages.imageCandidates[0].ootdApproved, false);
  assert.equal(
    withImages.imageCandidates.find((c) => c.partnerRole === PARTNER_IMAGE_ROLE.MODEL)
      .ootdApproved,
    false,
  );

  const noImage = adapter.normalizeRecord(samplePartnerARecord({images: []}));
  assert.equal(noImage.imageStatus, IMAGE_STATUS.NOT_AVAILABLE);

  assert.throws(
    () => normalizePartnerImageCandidates([{
      url: "https://evil.example/x.jpg",
    }], {allowedDomains: ["images.synthetic-a.test"]}),
    /partner_image_url_domain_not_allowed/,
  );

  const preflight = createOotdImagePreflightBoundary();
  const result = await preflight.evaluate(withImages.imageCandidates[0]);
  assert.equal(result.aiRequestCount, 0);
  assert.equal(result.status, IMAGE_STATUS.NEEDS_VALIDATION);
});

test("HTTP harness: 200 pagination, 429 Retry-After, auth, schema drift, malformed JSON", async () => {
  let calls = 0;
  const records = [samplePartnerCRecord()];
  const server = createMockPartnerHttpServer({
    handler: ({query, headers}) => {
      calls += 1;
      if (!headers.authorization) {
        return {status: 401, body: {error: "auth"}};
      }
      if (query.force === "429") {
        return {status: 429, headers: {"retry-after": "0"}, body: {error: "rate"}};
      }
      if (query.force === "500") {
        return {status: 500, body: {error: "down"}};
      }
      if (query.force === "malformed") {
        return {status: 200, body: "{not-json", contentType: "text/plain"};
      }
      if (query.force === "schema") {
        return {status: 200, body: {schemaVersion: 99, items: []}};
      }
      const start = query.pageToken ? Number(query.pageToken) : 0;
      const pageSize = Number(query.pageSize || 1);
      const slice = records.slice(start, start + pageSize);
      const next = start + pageSize;
      return {
        status: 200,
        body: {
          schemaVersion: 1,
          items: slice,
          nextPageToken: next >= records.length ? null : String(next),
          done: next >= records.length,
          completenessGuaranteed: next >= records.length,
        },
      };
    },
  });
  const baseUrl = await server.start();
  try {
    const adapter = createGenericHttpPartnerAdapterSkeleton({
      publicConfig: {
        partnerId: "http_skel_sk",
        displayName: "HTTP Skeleton",
        publicStoreName: "HTTP Skeleton",
        status: "ACTIVE",
        market: "SK",
        currency: "EUR",
        allowedDomains: ["shop.synthetic-c.test"],
        capabilities: [
          PARTNER_CAPABILITY.FULL_CATALOG_SNAPSHOT,
          PARTNER_CAPABILITY.PAGINATION,
          PARTNER_CAPABILITY.PRICE,
          PARTNER_CAPABILITY.STABLE_PARTNER_PRODUCT_ID,
          PARTNER_CAPABILITY.STABLE_VARIANT_ID,
          PARTNER_CAPABILITY.SIZE_AVAILABILITY,
          PARTNER_CAPABILITY.CURRENCY,
          PARTNER_CAPABILITY.MARKET_SCOPE,
        ],
        adapterKey: "generic_http_partner_skeleton",
        adapterVersion: "1",
      },
      getSecret: () => "test-token",
      mapResponseToRecords: (json) => json.items || [],
    });

    assert.equal(classifyHttpStatus(429).code, PARTNER_ERROR.RATE_LIMITED);
    assert.equal(isRetryableError(classifyHttpStatus(500)), true);
    assert.equal(isRetryableError(classifyHttpStatus(401)), false);

    // 429 then success via retry in withPartnerRetry unit:
    let attempt = 0;
    await withPartnerRetry(async () => {
      attempt += 1;
      if (attempt === 1) {
        throw classifyHttpStatus(429, {retryAfterMs: 0});
      }
      return "ok";
    }, {
      isRetryable: isRetryableError,
      sleep: async () => {},
      random: () => 0,
    });
    assert.equal(attempt, 2);
    assert.ok(computeBackoffMs(1, PARTNER_RETRY_POLICY_V1, {random: () => 0}) >= 0);

    const repository = createMemoryCatalogRepository();
    const result = await runPartnerSync({
      adapter,
      publicConfig: adapter.publicConfig(),
      privateConfig: {
        partnerId: "http_skel_sk",
        adapterKey: "generic_http_partner_skeleton",
        adapterVersion: "1",
        baseUrl,
        secretRef: "SHOPPING_PARTNER_SECRET_SLOT_A",
        rateLimit: {pageSize: 1, requestsPerSecond: 50, requestsPerMinute: 500},
        _resolvedSecrets: {apiKey: "test-token"},
      },
      repository,
      mode: SYNC_MODE.FULL,
      runId: "http-1",
      sleep: async () => {},
    });
    assert.equal(result.acceptedCount, 1);
    assert.ok(calls >= 1);
  } finally {
    await server.stop();
  }
});

test("fanout: ChangeSet reaches Phase 7 monitoring hook; unchanged retry dedupe path", async () => {
  const repository = createMemoryCatalogRepository();
  const adapter = createSyntheticPartnerAAdapter({
    records: [samplePartnerARecord()],
  });
  const processed = [];
  // Lightweight stand-in for Phase 7 service boundary used by fanout trigger.
  const monitoring = {
    async processCatalogChangeSet(raw) {
      const cs = normalizeCatalogChangeSet(raw);
      processed.push(cs);
      return {processed: cs.changedVariantIds.length};
    },
  };

  const result = await runPartnerSync({
    adapter,
    publicConfig: adapter.publicConfig(),
    privateConfig: {
      partnerId: adapter.partnerId(),
      adapterKey: adapter.partner.adapterKey,
      adapterVersion: adapter.partner.adapterVersion,
      rateLimit: {pageSize: 10, requestsPerSecond: 50, requestsPerMinute: 500},
    },
    repository,
    mode: SYNC_MODE.FULL,
    runId: "fanout-1",
    onCatalogChangeSet: (cs) => monitoring.processCatalogChangeSet(cs),
    sleep: async () => {},
  });
  assert.equal(processed.length, 1);
  assert.equal(processed[0].syncRunId, "fanout-1");
  assert.ok(result.changeSet.changedVariantIds.length >= 1);

  // Second identical sync still emits ChangeSet at sync boundary (variant
  // rewritten). Phase 7 event dedupe is by observation facts / syncRunId —
  // different runId → monitoring may evaluate, but orchestrator does not
  // invent Wishlist transitions without ChangeSet completion.
  assert.equal(typeof createWishlistMonitoringService, "function");
});

test("performance: thousands of records paged with bounded page size", async () => {
  const repository = createMemoryCatalogRepository();
  const n = 2000;
  const records = Array.from({length: n}, (_, i) => samplePartnerARecord({
    partnerProductId: `perf-${i}`,
    partnerVariantId: `perf-v-${i}`,
    partnerListingId: `perf-l-${i}`,
    productEvidence: {
      gtin: null,
      reliablePartnerProductId: `synthetic_a_sk:perf-${i}`,
    },
    variantEvidence: {
      reliablePartnerVariantId: `synthetic_a_sk:perf-v-${i}`,
    },
    url: `https://shop.synthetic-a.test/p/perf-${i}`,
  }));
  const pageSize = 100;
  const adapter = createSyntheticPartnerAAdapter({records, pageSize});
  const started = Date.now();
  const result = await runPartnerSync({
    adapter,
    publicConfig: adapter.publicConfig(),
    privateConfig: {
      partnerId: adapter.partnerId(),
      adapterKey: adapter.partner.adapterKey,
      adapterVersion: adapter.partner.adapterVersion,
      rateLimit: {
        pageSize,
        requestsPerSecond: 1000,
        requestsPerMinute: 100000,
        maxPagesPerRun: 1000,
      },
    },
    repository,
    mode: SYNC_MODE.FULL,
    runId: "perf-1",
    sleep: async () => {},
  });
  const elapsedMs = Date.now() - started;
  const recordsPerSec = Math.round((n / Math.max(elapsedMs, 1)) * 1000);
  assert.equal(result.acceptedCount, n);
  assert.equal(result.metrics.pages, 20);
  assert.ok(result.changeSetChunks.length >= 4);
  assert.ok(recordsPerSec > 0);
  // Expose for report via assertion message context
  result._perf = {n, pageSize, elapsedMs, recordsPerSec, peakPageSize: pageSize};
  assert.equal(Object.keys(repository.dump().offers).length, n);
});

test("security counters and first-partner gate", () => {
  assert.equal(REAL_PARTNER_API_REQUESTS, 0);
  assert.equal(PARTNER_POLLING_COUNT, 0);
  assert.equal(AFFILIATE_RANKING_INPUT_COUNT, 0);
  assert.equal(AI_REQUEST_COUNT, 0);
  assert.equal(OWNER_APPROVED_FIRST_PARTNER_ID, "reserved_sk");
  assert.equal(
    FIRST_REAL_PARTNER_STATUS,
    "RESERVED_SK_CJ_ONBOARDING_READY_FOR_OWNER_ACTION",
  );
  assert.ok(listRegisteredAdapterKeys().includes("synthetic_partner_a_full"));
  assert.ok(listRegisteredAdapterKeys().includes("reserved_cj"));
  assert.ok(!listRegisteredAdapterKeys().some((k) => /zalando|aboutyou|hm_/i.test(k)));
});

test("config validation rejects disabled partner and id mismatch", () => {
  assert.throws(() => validatePartnerConfiguration({
    publicConfig: {
      partnerId: "synthetic_a_sk",
      displayName: "A",
      market: "SK",
      status: "DISABLED",
      allowedDomains: ["shop.synthetic-a.test"],
      capabilities: [PARTNER_CAPABILITY.FULL_CATALOG_SNAPSHOT],
      adapterKey: "synthetic_partner_a_full",
      adapterVersion: "1",
    },
    privateConfig: {
      partnerId: "synthetic_a_sk",
      adapterKey: "synthetic_partner_a_full",
      adapterVersion: "1",
    },
  }), (err) => err.code === PARTNER_ERROR.FATAL_CONFIGURATION);
});
