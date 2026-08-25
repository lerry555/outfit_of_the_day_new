"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  OPENAI_API_KEY_SECRET,
  resolveOpenAISecret,
} = require("./ai_stylist_role_secret_binding_v1");

const indexSource = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");

test("Stylist OpenAI resolver fails closed when its bound secret is unavailable", () => {
  assert.throws(
    () => resolveOpenAISecret({value: () => ""}),
    (error) => error.code === "openai_secret_unavailable",
  );
});

test("Stylist OpenAI resolver accepts an explicitly bound secret value", () => {
  assert.equal(resolveOpenAISecret({value: () => "test-secret"}), "test-secret");
  assert.equal(OPENAI_API_KEY_SECRET.name, "OPENAI_API_KEY");
});

test("stylistChat has no OpenAI environment or runtime-config fallback", () => {
  const resolver = indexSource.match(
    /function getBoundStylistOpenAiKey\(\)\s*\{([\s\S]*?)\n\}/,
  );
  assert.ok(resolver);
  assert.match(resolver[1], /return resolveOpenAISecret\(\);/);
  assert.doesNotMatch(resolver[1], /getOpenAiKey|process\.env|functions\.config|getConfigValue/);
});

test("frozen Stylist authority remains explicitly bound to OpenAI and Anthropic", () => {
  const callable = indexSource.match(
    /exports\.resolveStylistFrozenCandidatesV1\s*=([\s\S]*?)\.https\.onCall/,
  );
  assert.ok(callable);
  assert.match(
    callable[1],
    /secrets:\s*\[OPENAI_API_KEY_SECRET, ANTHROPIC_API_KEY_SECRET\]/,
  );
});
