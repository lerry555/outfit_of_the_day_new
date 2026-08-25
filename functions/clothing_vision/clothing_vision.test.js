"use strict";

const {test, before} = require("node:test");
const assert = require("node:assert/strict");

const {
  PROVIDERS,
  resolveClothingVisionProvider,
  getClothingVisionTaskConfig,
} = require("./model_task_registry");
const {
  getClothingAnalyzerGeminiPromptV1,
  PROMPT_VERSION,
  PROMPT_HASH,
  MODEL_ID,
} = require("./prompts/clothing_analyzer_gemini_v1");
const {
  buildProductionGeminiResponseSchema,
  REQUIRED_PROPERTIES,
} = require("./production_schema");
const {
  buildGeminiAnalyzeRequestBody,
  createGeminiClothingAnalyzerClient,
  DEFAULT_MAX_OUTPUT_TOKENS,
  TRUNCATION_RECOVERY_MAX_OUTPUT_TOKENS,
  DEFAULT_TEMPERATURE,
  DEFAULT_THINKING_BUDGET,
  isTruncatedResponse,
} = require("./gemini_clothing_analyzer_client");
const {
  validateProductionGeminiOutput,
  sanitizeMaterialFeel,
  sanitizeBrand,
  boundedEnumTelemetryValue,
} = require("./production_output_validator");
const {
  adaptToProductionClientResponse,
  derivePlacementHint,
} = require("./production_response_adapter");
const {
  resolveOwnedWardrobeStoragePath,
  parseFirebaseStoragePathFromUrl,
} = require("./storage_ownership");
const {
  createAnalyzeClothingImageHandler,
} = require("./analyze_clothing_image_handler");
const {createKbIndex} = require("./kb_index");
const {
  normalizeOpenAiLegacyParsed,
} = require("./openai_legacy_clothing_analyzer");

const TINY_JPEG_BASE64 =
  "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAn/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAGfAP/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAQUCf//EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQMBAT8Bf//EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQIBAT8Bf//Z";

function validGeminiPayload(overrides = {}) {
  return {
    canonical_type: "jeans",
    type: "Rifle",
    type_pretty: "Modré rifle",
    primary_type: "Rifle",
    secondary_type: "",
    brand: "",
    colors: ["modrá"],
    styles: ["casual"],
    patterns: ["jednofarebné"],
    seasons: ["celoročne"],
    fit: "regular",
    formality: 3,
    vibe: "casual",
    logo_prominence: "none",
    occasion_fit: ["daily"],
    material_feel: "denim-like woven",
    visual_description: "modré rifle",
    layer_role: "bottom",
    warmth_level: 4,
    confidence: 90,
    visual_identity: "",
    identity_confidence: 0,
    debug_reason: "clear jeans",
    identity_slot: "bottoms",
    ...overrides,
  };
}

let kbIndex;
before(() => {
  kbIndex = createKbIndex();
});

test("routing: GEMINI default and OPENAI_LEGACY explicit", () => {
  assert.equal(resolveClothingVisionProvider({env: {}}), PROVIDERS.GEMINI);
  assert.equal(
    resolveClothingVisionProvider({env: {CLOTHING_VISION_PROVIDER: "OPENAI_LEGACY"}}),
    PROVIDERS.OPENAI_LEGACY,
  );
  const task = getClothingVisionTaskConfig({env: {}});
  assert.equal(task.allowsAutomaticCrossProviderFallback, false);
});

test("prompt version and sha are stable", () => {
  const p = getClothingAnalyzerGeminiPromptV1();
  assert.equal(p.promptVersion, PROMPT_VERSION);
  assert.equal(p.promptHash, PROMPT_HASH);
  assert.equal(p.modelId, MODEL_ID);
  assert.equal(p.promptHash.length, 64);
  assert.match(p.prompt, /correct broader/);
  assert.match(p.prompt, /exact fiber/i);
});

test("gemini request construction uses required settings", () => {
  const body = buildGeminiAnalyzeRequestBody({
    prompt: "test prompt",
    mimeType: "image/jpeg",
    base64: TINY_JPEG_BASE64,
  });
  assert.equal(body.generationConfig.temperature, DEFAULT_TEMPERATURE);
  assert.equal(body.generationConfig.maxOutputTokens, DEFAULT_MAX_OUTPUT_TOKENS);
  assert.equal(body.generationConfig.thinkingConfig.thinkingBudget, DEFAULT_THINKING_BUDGET);
  assert.equal(body.generationConfig.responseMimeType, "application/json");
  assert.ok(body.generationConfig.responseJsonSchema);
  assert.deepEqual(
    body.generationConfig.responseJsonSchema.required.sort(),
    [...REQUIRED_PROPERTIES].sort(),
  );
  assert.equal(body.contents[0].parts[1].inlineData.mimeType, "image/jpeg");
});

test("schema includes production required fields", () => {
  const schema = buildProductionGeminiResponseSchema();
  for (const key of REQUIRED_PROPERTIES) {
    assert.ok(schema.properties[key], `missing schema prop ${key}`);
  }
  assert.equal(schema.additionalProperties, false);
});

test("truncation detection", () => {
  assert.equal(isTruncatedResponse({candidates: [{finishReason: "MAX_TOKENS"}]}, "{"), true);
  assert.equal(isTruncatedResponse({candidates: [{finishReason: "STOP"}]}, "{\"a\":1}"), false);
  assert.equal(isTruncatedResponse({}, "{\"a\":"), true);
});

test("exactly one 2000→4000 truncation recovery and no infinite loop", async () => {
  let calls = 0;
  const maxTokensSeen = [];
  const fetchImpl = async (_url, init) => {
    calls += 1;
    const body = JSON.parse(init.body);
    maxTokensSeen.push(body.generationConfig.maxOutputTokens);
    if (calls === 1) {
      return {
        ok: true,
        status: 200,
        async json() {
          return {
            candidates: [{
              finishReason: "MAX_TOKENS",
              content: {parts: [{text: "{\"canonical_type\":\"jeans\""}]},
            }],
            usageMetadata: {promptTokenCount: 10, candidatesTokenCount: 2000},
          };
        },
      };
    }
    return {
      ok: true,
      status: 200,
      async json() {
        return {
          candidates: [{
            finishReason: "STOP",
            content: {parts: [{text: JSON.stringify(validGeminiPayload())}]},
          }],
          usageMetadata: {promptTokenCount: 10, candidatesTokenCount: 100},
        };
      },
    };
  };

  const client = createGeminiClothingAnalyzerClient({
    getApiKey: () => "test-key",
    fetchImpl,
    sleepImpl: async () => {},
  });
  const result = await client.analyze({
    mimeType: "image/jpeg",
    imageBase64: TINY_JPEG_BASE64,
  });
  assert.equal(calls, 2);
  assert.deepEqual(maxTokensSeen, [
    DEFAULT_MAX_OUTPUT_TOKENS,
    TRUNCATION_RECOVERY_MAX_OUTPUT_TOKENS,
  ]);
  assert.equal(result.telemetry.truncationRecovered, true);
  assert.equal(result.telemetry.success, true);
  assert.ok(result.telemetry.retryCount >= 1);
});

test("429 bounded retry then success", async () => {
  let calls = 0;
  const fetchImpl = async () => {
    calls += 1;
    if (calls < 3) {
      return {ok: false, status: 429, async json() { return {}; }};
    }
    return {
      ok: true,
      status: 200,
      async json() {
        return {
          candidates: [{
            finishReason: "STOP",
            content: {parts: [{text: JSON.stringify(validGeminiPayload())}]},
          }],
          usageMetadata: {promptTokenCount: 1, candidatesTokenCount: 1},
        };
      },
    };
  };
  const client = createGeminiClothingAnalyzerClient({
    getApiKey: () => "test-key",
    fetchImpl,
    sleepImpl: async () => {},
  });
  const result = await client.analyze({
    mimeType: "image/jpeg",
    imageBase64: TINY_JPEG_BASE64,
  });
  assert.equal(calls, 3);
  assert.equal(result.telemetry.success, true);
});

test("5xx bounded retry exhausts", async () => {
  const fetchImpl = async () => ({ok: false, status: 503, async json() { return {}; }});
  const client = createGeminiClothingAnalyzerClient({
    getApiKey: () => "test-key",
    fetchImpl,
    sleepImpl: async () => {},
  });
  await assert.rejects(
    () => client.analyze({mimeType: "image/jpeg", imageBase64: TINY_JPEG_BASE64}),
    (err) => err.code === "gemini_upstream_503",
  );
});

test("malformed non-truncated JSON fails safely", async () => {
  const fetchImpl = async () => ({
    ok: true,
    status: 200,
    async json() {
      return {
        candidates: [{
          finishReason: "STOP",
          content: {parts: [{text: "not-json"}]},
        }],
      };
    },
  });
  const client = createGeminiClothingAnalyzerClient({
    getApiKey: () => "test-key",
    fetchImpl,
    sleepImpl: async () => {},
  });
  await assert.rejects(
    () => client.analyze({mimeType: "image/jpeg", imageBase64: TINY_JPEG_BASE64}),
    (err) => err.code === "malformed_json",
  );
});

test("canonical allowlist + alias + parent fallback + wrong sibling protection", () => {
  const ok = validateProductionGeminiOutput(validGeminiPayload({
    canonical_type: "jeans",
  }), {kbIndex});
  assert.equal(ok.ok, true);
  assert.equal(ok.value.canonical_type, "jeans");

  const alias = validateProductionGeminiOutput(validGeminiPayload({
    canonical_type: "cap",
    layer_role: "accessory",
    identity_slot: "accessories",
  }), {kbIndex});
  assert.equal(alias.value.canonical_type, "baseball_cap");

  const sibling = validateProductionGeminiOutput(validGeminiPayload({
    canonical_type: "maxi_skirt",
    visual_description: "sukňa", // no maxi evidence
    layer_role: "bottom",
    identity_slot: "bottoms",
  }), {kbIndex});
  assert.equal(sibling.value.canonical_type, "skirt");
  assert.ok(sibling.notes.some((n) => n.includes("unsupported_specificity")));

  const supportedChild = validateProductionGeminiOutput(validGeminiPayload({
    canonical_type: "maxi_skirt",
    visual_description: "dlhá maxi sukňa po členky",
    layer_role: "bottom",
    identity_slot: "bottoms",
  }), {kbIndex});
  assert.equal(supportedChild.value.canonical_type, "maxi_skirt");
});

test("approved taxonomy compatibility aliases resolve without sibling overrides", () => {
  const cases = [
    ["macintosh", "rain_jacket", "outer_layer", "outerwear"],
    ["fannypack", "fanny_pack", "accessory", "accessories"],
    ["cross-body bag", "crossbody_bag", "accessory", "accessories"],
    ["trench", "trench_coat", "outer_layer", "outerwear"],
  ];
  for (const [input, expected, layerRole, identitySlot] of cases) {
    const result = validateProductionGeminiOutput(validGeminiPayload({
      canonical_type: input,
      layer_role: layerRole,
      identity_slot: identitySlot,
    }), {kbIndex});
    assert.equal(result.value.canonical_type, expected, input);
    assert.ok(result.sanitizationActions.some((action) =>
      action.field === "canonical_type" && action.reason === "alias_normalized"), input);

    const idempotent = validateProductionGeminiOutput(validGeminiPayload({
      canonical_type: expected,
      layer_role: layerRole,
      identity_slot: identitySlot,
    }), {kbIndex});
    assert.equal(idempotent.value.canonical_type, expected, `${expected}:idempotent`);
    assert.equal(idempotent.sanitizationActions.some((a) =>
      a.field === "canonical_type"), false, `${expected}:no canonical action`);
  }

  for (const variant of ["cross body bag", "cross-body bag", "cross_body_bag"]) {
    const result = validateProductionGeminiOutput(validGeminiPayload({
      canonical_type: variant,
      layer_role: "accessory",
      identity_slot: "accessories",
    }), {kbIndex});
    assert.equal(result.value.canonical_type, "crossbody_bag", variant);
  }
});

test("approved safe parent collapses resolve all sixteen specific terms", () => {
  const cases = [
    ["maxi_dress", "dress"],
    ["midi_dress", "dress"],
    ["mini_dress", "dress"],
    ["sheath_dress", "dress"],
    ["shirt_dress", "dress"],
    ["faux_leather_jacket", "leather_jacket"],
    ["palazzo_pants", "wide_leg_pants"],
    ["mom_jeans", "jeans"],
    ["flare_jeans", "jeans"],
    ["distressed_jeans", "jeans"],
    ["pencil_skirt", "skirt"],
    ["pleated_skirt", "skirt"],
    ["cable_knit_sweater", "knit_sweater"],
    ["cropped_hoodie", "hoodie"],
    ["long_cardigan", "cardigan"],
    ["open_front_cardigan", "cardigan"],
  ];
  for (const [input, expected] of cases) {
    const exact = validateProductionGeminiOutput(validGeminiPayload({
      canonical_type: input,
    }), {kbIndex});
    assert.equal(exact.value.canonical_type, expected, input);
    assert.deepEqual(exact.sanitizationActions.find((action) =>
      action.field === "canonical_type"), {
      field: "canonical_type",
      before: input,
      after: expected,
      reason: "safe_parent_collapse",
    });

    for (const variant of [input.replaceAll("_", " "), input.replaceAll("_", "-")]) {
      const normalized = validateProductionGeminiOutput(validGeminiPayload({
        canonical_type: variant,
      }), {kbIndex});
      assert.equal(normalized.value.canonical_type, expected, variant);
    }

    const idempotent = validateProductionGeminiOutput(validGeminiPayload({
      canonical_type: expected,
    }), {kbIndex});
    assert.equal(idempotent.value.canonical_type, expected, `${expected}:idempotent`);
  }
});

test("dress length collapse preserves descriptive fields", () => {
  for (const input of ["maxi_dress", "midi_dress", "mini_dress"]) {
    const result = validateProductionGeminiOutput(validGeminiPayload({
      canonical_type: input,
      type: input.replace("_", " "),
      type_pretty: `pretty ${input}`,
      secondary_type: input,
      visual_description: `visible ${input} length detail`,
    }), {kbIndex});
    assert.equal(result.value.canonical_type, "dress");
    assert.equal(result.value.type, input.replace("_", " "));
    assert.equal(result.value.type_pretty, `pretty ${input}`);
    assert.equal(result.value.secondary_type, input);
    assert.equal(result.value.visual_description, `visible ${input} length detail`);
  }
});

test("faux leather mapping is garment identity only and creates no material claim", () => {
  const result = validateProductionGeminiOutput(validGeminiPayload({
    canonical_type: "faux_leather_jacket",
    material_feel: "unknown",
    visual_description: "black jacket with a smooth leather-like visual finish",
  }), {kbIndex});
  assert.equal(result.value.canonical_type, "leather_jacket");
  assert.equal(result.value.material_feel, "unknown");
  const serialized = JSON.stringify(result.value).toLowerCase();
  for (const forbidden of ["genuine leather", "pravá koža", "100% leather"]) {
    assert.equal(serialized.includes(forbidden), false, forbidden);
  }
});

test("generic and ambiguous compatibility terms remain fail-closed", () => {
  for (const input of [
    "jacket", "pants", "coat", "top", "jersey",
    "button_down_shirt", "moto_jacket", "puffer_coat",
    "quilted_jacket", "quilted_coat", "wool_coat", "tailored_trousers",
  ]) {
    const result = validateProductionGeminiOutput(validGeminiPayload({
      canonical_type: input,
    }), {kbIndex});
    assert.equal(result.value.canonical_type, "", input);
    assert.equal(result.sanitizationActions.find((action) =>
      action.field === "canonical_type").reason, "canonical_unresolved", input);
  }
  for (const [input, expected] of [
    ["vest", "vest"],
    ["waistcoat", "waistcoat"],
    ["varsity_jacket", "varsity_jacket"],
    ["bomber_jacket", "bomber_jacket"],
    ["overcoat", "overcoat"],
    ["trench_coat", "trench_coat"],
  ]) {
    const result = validateProductionGeminiOutput(validGeminiPayload({
      canonical_type: input,
    }), {kbIndex});
    assert.equal(result.value.canonical_type, expected, input);
  }
});

test("canonical sanitization actions are minimal, bounded, and control-safe", () => {
  const unknown = validateProductionGeminiOutput(validGeminiPayload({
    canonical_type: "maxi_dress",
  }), {kbIndex});
  assert.equal(unknown.value.canonical_type, "dress");
  assert.deepEqual(unknown.sanitizationActions, [{
    field: "canonical_type",
    before: "maxi_dress",
    after: "dress",
    reason: "safe_parent_collapse",
  }]);

  const known = validateProductionGeminiOutput(validGeminiPayload({
    canonical_type: "cardigan",
    layer_role: "mid_layer",
    identity_slot: "tops",
  }), {kbIndex});
  assert.equal(known.value.canonical_type, "cardigan");
  assert.deepEqual(known.sanitizationActions, []);

  const alias = validateProductionGeminiOutput(validGeminiPayload({
    canonical_type: "cap",
    layer_role: "accessory",
    identity_slot: "accessories",
  }), {kbIndex});
  assert.equal(alias.value.canonical_type, "baseball_cap");
  assert.deepEqual(alias.sanitizationActions, [{
    field: "canonical_type",
    before: "cap",
    after: "baseball_cap",
    reason: "alias_normalized",
  }]);

  const unsafe = `  ${"x".repeat(40)}\u0000\n${"y".repeat(40)}  `;
  const unsafeResult = validateProductionGeminiOutput(validGeminiPayload({
    canonical_type: unsafe,
  }), {kbIndex});
  const action = unsafeResult.sanitizationActions[0];
  assert.equal(action.reason, "canonical_unresolved");
  assert.equal(action.before.length, 64);
  assert.equal(/[\u0000-\u001f\u007f]/.test(action.before), false);
  assert.equal(boundedEnumTelemetryValue(unsafe), action.before);
});

test("free-text sanitization actions expose hashes, never raw brand or material", () => {
  const result = validateProductionGeminiOutput(validGeminiPayload({
    brand: "Unverified Brand",
    logo_prominence: "none",
    visual_description: "plain garment",
    material_feel: "100% cotton knit",
  }), {kbIndex});
  const brandAction = result.sanitizationActions.find((a) => a.field === "brand");
  const materialAction = result.sanitizationActions.find((a) => a.field === "material_feel");
  for (const action of [brandAction, materialAction]) {
    assert.ok(action);
    assert.equal(Object.prototype.hasOwnProperty.call(action, "before"), false);
    assert.equal(Object.prototype.hasOwnProperty.call(action, "after"), false);
    assert.match(action.beforeHash, /^[a-f0-9]{64}$/);
    assert.match(action.afterHash, /^[a-f0-9]{64}$/);
  }
  assert.equal(JSON.stringify(result.sanitizationActions).includes("Unverified Brand"), false);
  assert.equal(JSON.stringify(result.sanitizationActions).includes("100% cotton"), false);
});

test("bottoms and footwear retain production layer semantics", () => {
  const jeans = validateProductionGeminiOutput(validGeminiPayload({
    canonical_type: "jeans",
    layer_role: "outer_layer", // wrong AI outermost interpretation
    identity_slot: "outerwear",
  }), {kbIndex});
  assert.equal(jeans.value.layer_role, "bottom");
  assert.equal(jeans.value.identity_slot, "bottoms");

  const shoes = validateProductionGeminiOutput(validGeminiPayload({
    canonical_type: "sneakers",
    layer_role: "base_layer",
    identity_slot: "tops",
    type: "Tenisky",
    type_pretty: "Tenisky",
  }), {kbIndex});
  assert.equal(shoes.value.layer_role, "footwear");
  assert.equal(shoes.value.identity_slot, "footwear");
});

test("one_piece handling", () => {
  const dress = validateProductionGeminiOutput(validGeminiPayload({
    canonical_type: "summer_dress",
    visual_description: "ľahké letné šaty summer dress",
    layer_role: "base_layer",
    identity_slot: "tops",
  }), {kbIndex});
  assert.equal(dress.value.canonical_type, "summer_dress");
  assert.equal(dress.value.identity_slot, "one_piece");
  assert.equal(dress.value.layer_role, "bottom"); // KB production semantics
});

test("material observable allowed; exact fiber sanitized", () => {
  assert.equal(sanitizeMaterialFeel("knit ribbed"), "knit ribbed");
  const sanitized = sanitizeMaterialFeel("100% cotton knit");
  assert.equal(sanitized.includes("100%"), false);
  assert.equal(sanitized.includes("cotton"), false);

  const validated = validateProductionGeminiOutput(validGeminiPayload({
    material_feel: "soft polyester blend",
  }), {kbIndex});
  assert.ok(validated.notes.includes("material_exact_fiber_sanitized"));
});

test("guessed brand rejected", () => {
  assert.equal(
    sanitizeBrand("Nike", "none", "black tee", ""),
    "",
  );
  assert.equal(
    sanitizeBrand("Nike", "small", "black tee with nike logo", ""),
    "Nike",
  );
});

test("adapter preserves flutter response shape + analyzer metadata", () => {
  const validated = validateProductionGeminiOutput(validGeminiPayload(), {kbIndex});
  const adapted = adaptToProductionClientResponse(validated.value, {
    provider: "GEMINI",
    modelId: MODEL_ID,
    promptVersion: PROMPT_VERSION,
    promptHash: PROMPT_HASH,
  });
  for (const key of [
    "type", "type_pretty", "canonical_type", "brand", "colors", "styles",
    "patterns", "seasons", "fit", "formality", "vibe", "logo_prominence",
    "occasion_fit", "material_feel", "visual_description", "primary_type",
    "secondary_type", "layer_role", "warmth_level", "confidence",
    "visual_identity", "identity_confidence", "debug_reason",
  ]) {
    assert.ok(Object.prototype.hasOwnProperty.call(adapted, key), key);
  }
  assert.equal(adapted.analyzerProvider, "GEMINI");
  assert.equal(adapted.analyzerModel, MODEL_ID);
  assert.equal(adapted.analyzerPromptVersion, PROMPT_VERSION);
  assert.equal(Object.prototype.hasOwnProperty.call(adapted, "bodySlot"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(adapted, "layerPosition"), false);
  const placement = derivePlacementHint(validated.value);
  assert.equal(placement.bodySlot, "bottom");
});

test("storage ownership validation", () => {
  const path = resolveOwnedWardrobeStoragePath({
    uid: "uid1",
    storagePath: "wardrobe/uid1/123.jpg",
  });
  assert.equal(path, "wardrobe/uid1/123.jpg");

  assert.throws(
    () => resolveOwnedWardrobeStoragePath({
      uid: "uid1",
      storagePath: "wardrobe/uid2/123.jpg",
    }),
    (e) => e.code === "storage_path_uid_mismatch",
  );

  assert.throws(
    () => resolveOwnedWardrobeStoragePath({
      uid: "uid1",
      imageUrl: "https://example.com/photo.jpg",
    }),
    (e) => e.code === "external_or_unparseable_image_url_rejected",
  );

  const encoded = encodeURIComponent("wardrobe/uid1/a.jpg");
  const parsed = parseFirebaseStoragePathFromUrl(
    `https://firebasestorage.googleapis.com/v0/b/my.appspot.com/o/${encoded}?alt=media&token=x`,
  );
  assert.equal(parsed, "wardrobe/uid1/a.jpg");
});

test("handler requires auth and does not auto-fallback Gemini→OpenAI", async () => {
  const logs = [];
  let openaiCalled = false;
  const admin = {
    auth() {
      return {
        async verifyIdToken() {
          return {uid: "uid1"};
        },
      };
    },
    appCheck() {
      return {
        async verifyToken() {
          return {appId: "x"};
        },
      };
    },
  };

  const geminiClient = {
    provider: "GEMINI",
    modelId: MODEL_ID,
    analyzerVersion: "clothing-vision-gemini-v1",
    promptVersion: PROMPT_VERSION,
    promptHash: PROMPT_HASH,
    async analyze() {
      const err = new Error("gemini_upstream_500");
      err.code = "gemini_upstream_500";
      err.httpStatus = 502;
      throw err;
    },
  };

  const handler = createAnalyzeClothingImageHandler({
    admin,
    logger: {
      info: (...a) => logs.push(a),
      error: (...a) => logs.push(a),
      warn: (...a) => logs.push(a),
    },
    getOpenAiKey: () => {
      openaiCalled = true;
      return "openai-key";
    },
    getGeminiApiKey: () => "gemini-key",
    geminiClient,
    kbIndex,
    env: {
      CLOTHING_VISION_PROVIDER: "GEMINI",
      CLOTHING_VISION_ENVIRONMENT: "test",
      CLOTHING_VISION_APP_CHECK_MODE: "optional_with_warning",
    },
    readStorageBytes: async () => ({
      buffer: Buffer.from(TINY_JPEG_BASE64, "base64"),
      contentType: "image/jpeg",
    }),
    providerOverride: "GEMINI",
  });

  const res = {
    statusCode: 0,
    body: null,
    status(code) { this.statusCode = code; return this; },
    send(body) { this.body = body; return this; },
  };

  await handler({
    method: "POST",
    headers: {authorization: "Bearer token"},
    body: {storagePath: "wardrobe/uid1/x.jpg"},
  }, res);

  assert.equal(res.statusCode, 502);
  assert.equal(openaiCalled, false);

  // unauthenticated
  const res401 = {
    statusCode: 0,
    body: null,
    status(code) { this.statusCode = code; return this; },
    send(body) { this.body = body; return this; },
  };
  await handler({
    method: "POST",
    headers: {},
    body: {storagePath: "wardrobe/uid1/x.jpg"},
  }, res401);
  assert.equal(res401.statusCode, 401);
});

test("OPENAI_LEGACY kill-switch path normalizes response shape", () => {
  const normalized = normalizeOpenAiLegacyParsed({
    type: "Mikina",
    type_pretty: "Mikina",
    canonical_type: "hoodie",
    brand: "",
    colors: ["čierna"],
    styles: ["casual"],
    patterns: ["jednofarebné"],
    seasons: ["jeseň"],
    fit: "regular",
    formality: 3,
    vibe: "casual",
    logo_prominence: "none",
    occasion_fit: [],
    material_feel: "knit",
    visual_description: "čierna mikina",
    primary_type: "Mikina",
    secondary_type: "",
    layer_role: "mid_layer",
    warmth_level: 5,
    confidence: 80,
    visual_identity: "",
    identity_confidence: 0,
    debug_reason: "ok",
  });
  assert.equal(normalized.analyzerProvider, "OPENAI_LEGACY");
  assert.equal(normalized.canonical_type, "hoodie");
  assert.equal(normalized.layer_role, "mid_layer");
});

test("existing wardrobe compatibility: adapter output is plain JSON map", () => {
  const validated = validateProductionGeminiOutput(validGeminiPayload(), {kbIndex});
  const adapted = adaptToProductionClientResponse(validated.value, {
    provider: "GEMINI",
    modelId: MODEL_ID,
    promptVersion: PROMPT_VERSION,
    promptHash: PROMPT_HASH,
  });
  const roundTrip = JSON.parse(JSON.stringify(adapted));
  assert.equal(roundTrip.canonical_type, "jeans");
  assert.ok(Array.isArray(roundTrip.colors));
});

test("App Check status distinguishes valid / missing / invalid", () => {
  const {
    resolveAppCheckStatus,
    evaluateAppCheck,
    resolveAppCheckPolicy,
    APP_CHECK_MODES,
  } = require("../wardrobe_authority_app_check_policy");

  assert.equal(resolveAppCheckStatus({}), "missing");
  assert.equal(
    resolveAppCheckStatus({appCheckPresent: false, appCheckVerified: false}),
    "missing",
  );
  assert.equal(
    resolveAppCheckStatus({appCheckPresent: true, appCheckVerified: false}),
    "invalid",
  );
  assert.equal(
    resolveAppCheckStatus({appCheckPresent: true, appCheckVerified: true}),
    "valid",
  );

  const policy = resolveAppCheckPolicy({
    environmentMode: "production",
    appCheckMode: APP_CHECK_MODES.optionalWithWarning,
  });
  const missing = evaluateAppCheck(policy, {
    appCheckPresent: false,
    appCheckVerified: false,
  });
  const invalid = evaluateAppCheck(policy, {
    appCheckPresent: true,
    appCheckVerified: false,
  });
  assert.equal(missing.status, "missing");
  assert.equal(missing.reasonCode, "app_check_missing_warning");
  assert.equal(invalid.status, "invalid");
  assert.equal(invalid.reasonCode, "app_check_invalid_warning");
  assert.equal(missing.ok, true);
  assert.equal(invalid.ok, true);
});

test("handler emits private sanitization event and explicit App Check telemetry", async () => {
  async function run(appCheckHeader) {
    const logs = [];
    const admin = {
      auth: () => ({verifyIdToken: async () => ({uid: "sensitive-uid"})}),
      appCheck: () => ({
        verifyToken: async (token) => {
          if (token === "invalid-token") throw new Error("invalid");
          return {appId: "app"};
        },
      }),
    };
    const geminiClient = {
      modelId: MODEL_ID,
      analyzerVersion: "clothing-vision-gemini-v1",
      promptVersion: PROMPT_VERSION,
      promptHash: PROMPT_HASH,
      analyze: async () => ({
        parsed: validGeminiPayload({canonical_type: "maxi_dress"}),
        telemetry: {parserStatus: "ok"},
      }),
    };
    const handler = createAnalyzeClothingImageHandler({
      admin,
      logger: {
        info: (message, fields) => logs.push({level: "info", message, fields}),
        warn: (message, fields) => logs.push({level: "warn", message, fields}),
        error: (message, fields) => logs.push({level: "error", message, fields}),
      },
      geminiClient,
      kbIndex,
      env: {
        CLOTHING_VISION_ENVIRONMENT: "production",
        CLOTHING_VISION_APP_CHECK_MODE: "optional_with_warning",
      },
      readStorageBytes: async () => ({
        buffer: Buffer.from(TINY_JPEG_BASE64, "base64"),
        contentType: "image/jpeg",
      }),
      providerOverride: "GEMINI",
    });
    const res = {
      statusCode: 0,
      body: null,
      status(code) { this.statusCode = code; return this; },
      send(body) { this.body = body; return this; },
    };
    const headers = {authorization: "Bearer firebase-id-token"};
    if (appCheckHeader !== undefined) headers["x-firebase-appcheck"] = appCheckHeader;
    await handler({
      method: "POST",
      headers,
      body: {storagePath: "wardrobe/sensitive-uid/secret-object.jpg"},
    }, res);
    assert.equal(res.statusCode, 200);
    return logs;
  }

  for (const [token, expectedStatus] of [
    ["valid-token", "valid"],
    [undefined, "missing"],
    ["invalid-token", "invalid"],
  ]) {
    const logs = await run(token);
    const telemetry = logs.find((entry) =>
      entry.message === "analyzeClothingImage telemetry");
    assert.equal(telemetry.fields.appCheckStatus, expectedStatus);
    assert.equal(telemetry.fields.appCheckMode, "optional_with_warning");

    const event = logs.find((entry) =>
      entry.fields.event === "clothing_vision_validation_sanitization");
    assert.ok(event);
    assert.equal(event.fields.schemaVersion, 1);
    assert.equal(event.fields.parserStatus, "ok");
    assert.deepEqual(event.fields.actions, [{
      field: "canonical_type",
      before: "maxi_dress",
      after: "dress",
      reason: "safe_parent_collapse",
    }]);
    const serialized = JSON.stringify(event);
    for (const forbidden of [
      "sensitive-uid", "secret-object.jpg", "firebase-id-token",
      "valid-token", "invalid-token", TINY_JPEG_BASE64,
    ]) {
      assert.equal(serialized.includes(forbidden), false, forbidden);
    }
    assert.equal(Object.prototype.hasOwnProperty.call(event.fields, "appCheckStatus"), false);
    const allLogs = JSON.stringify(logs);
    for (const forbidden of [
      "sensitive-uid", "sensit", "wardrobe/", "secret-object.jpg",
      "firebase-id-token", "valid-token", "invalid-token", TINY_JPEG_BASE64,
    ]) {
      assert.equal(allLogs.includes(forbidden), false, `all logs:${forbidden}`);
    }
    assert.equal(telemetry.fields.requestFingerprint, event.fields.requestFingerprint);
    assert.match(telemetry.fields.requestFingerprint, /^[0-9a-f-]{36}$/);
    assert.equal(Object.hasOwn(telemetry.fields, "uidFingerprint"), false);
    assert.equal(Object.hasOwn(telemetry.fields, "storagePathPrefix"), false);
  }
});
