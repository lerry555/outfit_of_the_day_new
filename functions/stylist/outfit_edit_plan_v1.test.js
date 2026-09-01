"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {sanitizeOutfitEditPlanV1} = require("./outfit_edit_plan_v1");

test("canonical edit plan preserves every unmentioned slot", () => {
  const plan = sanitizeOutfitEditPlanV1({
    contractVersion: "outfit_edit_plan_v1",
    intent: "edit_current_outfit",
    operations: [
      {slot: "bottom", action: "replace", constraints: {family: "shorts"}},
      {slot: "layers", action: "add", constraints: {type: "hoodie"}},
    ],
  });
  assert.ok(plan);
  assert.equal(plan.contractVersion, "outfit_edit_plan_v1");
  assert.equal(plan.presentation, "concise_full");
  assert.deepEqual(
    plan.operations.filter((operation) => operation.action === "preserve")
      .map((operation) => operation.slot),
    ["top", "shoes", "outerwear", "full_body", "accessories"],
  );
});

test("multi-slot red-shoes plan remains structured", () => {
  const plan = sanitizeOutfitEditPlanV1({
    contractVersion: "outfit_edit_plan_v1",
    intent: "edit_current_outfit",
    operations: [
      {slot: "top", action: "replace", constraints: {}},
      {slot: "bottom", action: "replace", constraints: {}},
      {slot: "shoes", action: "replace", constraints: {color: "red"}},
    ],
    presentation: "concise_full",
  });
  assert.ok(plan);
  assert.equal(plan.operations.length, 7);
  assert.equal(
    plan.operations.find((operation) => operation.slot === "shoes").constraints.color,
    "red",
  );
});

test("non-mutating or structurally invalid edits fail closed", () => {
  assert.equal(sanitizeOutfitEditPlanV1({
    intent: "edit_current_outfit",
    operations: [{slot: "top", action: "replace", constraints: {}}],
  }), null);
  assert.equal(sanitizeOutfitEditPlanV1({
    contractVersion: "outfit_edit_plan_v1",
    intent: "edit_current_outfit",
    operations: [{slot: "top", action: "preserve", constraints: {}}],
  }), null);
  assert.equal(sanitizeOutfitEditPlanV1({
    contractVersion: "outfit_edit_plan_v1",
    intent: "edit_current_outfit",
    operations: [{slot: "shoes", action: "add", constraints: {}}],
  }), null);
  assert.equal(sanitizeOutfitEditPlanV1({
    contractVersion: "outfit_edit_plan_v1",
    intent: "edit_current_outfit",
    operations: [{slot: "shoes", action: "replace", constraints: {color: "red shoes"}}],
  }), null);
});
