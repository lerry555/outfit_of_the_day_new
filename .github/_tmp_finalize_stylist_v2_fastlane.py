from pathlib import Path


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected exactly one match, got {count}: {old[:120]!r}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


replace_once(
    "functions/stylist/v2/stylist_adversarial_conversation_v2.test.js",
    '  assert.deepEqual(h.calls.model.map((entry) => entry.schemaName), ["stylist_v2_plan", "stylist_v2_final"]);',
    '  assert.deepEqual(h.calls.model.map((entry) => entry.schemaName), ["stylist_v2_final"]);',
)

replace_once(
    "functions/stylist/v2/stylist_pending_location_v2.test.js",
    '  const saved = await h.sessionRepository.read("pending-region");\n  assert.equal(saved.context.destination, null);\n  assert.equal(saved.context.groundingRequirements.weatherRequired, false);',
    '  const saved = await h.sessionRepository.read("pending-region");\n  assert.equal(saved.context.destination.label, "Tatier");\n  assert.equal(saved.context.destination.source, "user_text");\n  assert.equal(saved.context.groundingRequirements.weatherRequired, false);',
)

replace_once(
    "functions/stylist/v2/openai_stylist_model_port_v2.js",
    "    warmth: Number.isFinite(Number(item.warmth)) ? Number(item.warmth) : null,",
    "    warmth: item.warmth != null && Number.isFinite(Number(item.warmth)) ? Number(item.warmth) : null,",
)

replace_once(
    "functions/stylist/v2/openai_stylist_model_port_v2.js",
    "    formality: Number.isFinite(Number(item.formality)) ? Number(item.formality) : null,",
    "    formality: item.formality != null && Number.isFinite(Number(item.formality)) ? Number(item.formality) : null,",
)

p = Path("functions/stylist/v2/stylist_model_payload_efficiency_v2.test.js")
text = p.read_text(encoding="utf-8")
marker = 'test("absent warmth/formality stay absent instead of becoming zero"'
if marker in text:
    raise RuntimeError("nullable metadata test already present")
text = (text.rstrip() + r'''


test("absent warmth/formality stay absent instead of becoming zero", async () => {
  let call;
  const input = baseInput();
  input.toolResults.wardrobeItems[0].warmth = null;
  input.toolResults.wardrobeItems[0].formality = null;
  const port = createOpenAiStylistModelPortV2({executeStructured: async (request) => { call = request; return validChatRaw(); }});
  await port.turn(input);
  const item = JSON.parse(call.messages[1].content).toolResults.wardrobeItems[0];
  assert.equal(Object.hasOwn(item, "warmth"), false);
  assert.equal(Object.hasOwn(item, "formality"), false);
});
''').rstrip() + "\n"
p.write_text(text, encoding="utf-8")

print("Stylist V2 fastlane contract updates applied")
