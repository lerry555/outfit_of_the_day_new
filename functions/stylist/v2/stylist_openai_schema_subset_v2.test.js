"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {PLAN_SCHEMA, FINAL_SCHEMA} = require("./openai_stylist_model_port_v2");

const FORBIDDEN_STRICT_SCHEMA_KEYWORDS = new Set([
  "maxLength",
  "minLength",
  "uniqueItems",
  "allOf",
  "not",
  "dependentRequired",
  "dependentSchemas",
  "if",
  "then",
  "else",
]);

function findForbidden(value, path = "$") {
  const hits = [];
  if (Array.isArray(value)) {
    value.forEach((item, index) => hits.push(...findForbidden(item, `${path}[${index}]`)));
    return hits;
  }
  if (!value || typeof value !== "object") return hits;
  for (const [key, child] of Object.entries(value)) {
    if (FORBIDDEN_STRICT_SCHEMA_KEYWORDS.has(key)) hits.push(`${path}.${key}`);
    hits.push(...findForbidden(child, `${path}.${key}`));
  }
  return hits;
}

test("V2 strict response schemas stay inside the OpenAI Structured Outputs subset", () => {
  assert.deepEqual(findForbidden(PLAN_SCHEMA), []);
  assert.deepEqual(findForbidden(FINAL_SCHEMA), []);
});
