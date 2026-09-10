from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path, old, new):
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"anchor not found in {path}: {old[:140]!r}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


contract = ROOT / "functions/stylist/v2/stylist_help_first_contract_v2.test.js"
old_contract = '''test("golden: country-level destination asks once for a useful narrower place", async () => {
  const state = pendingDestinationState("usa-trip");
  const h = harness({initialStates: [state], resolutions: {USA: usa}});
  const result = await h.coordinator.resolveTurn(request("usa-trip", "u-1", 0, "USA"));
  assert.equal(result.action, "clarify");
  assert.equal(result.clarification.field, "destination");
  assert.match(result.assistantText, /mesto|štát|stat|región|region/i);
  assert.equal(h.ledger.calls("location").length, 1);
  assert.equal(h.ledger.calls("weather").length, 0);
  assert.equal(h.ledger.calls("wardrobe").length, 0);
  assert.equal(h.ledger.calls("model").length, 0);
  const saved = await h.sessionRepository.read("usa-trip");
  assert.equal(saved.context.destination, null);
  assert.deepEqual(saved.conversationMemory.pendingQuestion.attemptedAnswers, ["USA"]);
});'''
new_contract = '''test("golden: one broad answer to the location question is enough and continues weatherless", async () => {
  const state = pendingDestinationState("usa-trip");
  const h = harness({
    initialStates: [state],
    resolutions: {USA: usa},
    modelResults: [finalEnvelope(outfitResult("Presnú lokálnu predpoveď nemám, preto volím konzervatívny outfit."))],
  });
  const result = await h.coordinator.resolveTurn(request("usa-trip", "u-1", 0, "USA"));
  assert.equal(result.action, "generate_outfit");
  assert.equal(result.clarification, null);
  assert.doesNotMatch(result.assistantText, /mesto|štát|stat|región|region/i);
  assert.equal(h.ledger.calls("location").length, 1);
  assert.equal(h.ledger.calls("weather").length, 0);
  assert.equal(h.ledger.calls("wardrobe").length, 1);
  assert.equal(h.ledger.calls("model", "plan").length, 0);
  assert.equal(h.ledger.calls("model", "final").length, 1);
  const saved = await h.sessionRepository.read("usa-trip");
  assert.equal(saved.context.destination.providerId, "place:usa");
  assert.equal(saved.context.groundingRequirements.weatherRequired, false);
  assert.equal(saved.context.groundingRequirements.weatherLocationField, null);
  assert.equal(saved.conversationMemory.pendingQuestion, null);
});'''
replace_once(contract, old_contract, new_contract)

release_gate = ROOT / "functions/stylist/v2/stylist_release_gate_v2.test.js"
old_release = '''test("release gate: country-only destination narrows once without spending a model call", async () => {
  const h = makeHarness();
  await invoke(h.handler, baseData("country_chat", "c1", "zajtra idem na túru potrebujem outfit"));
  const response = await invoke(h.handler, baseData("country_chat", "c2", "USA"));
  assertHealthy(response);
  assert.equal(response.action, "clarify");
  assert.match(response.reply, /mesto|štát|stat|región|region/i);
  assert.equal(h.calls.model.length, 0);
  assert.equal(h.calls.weather.length, 0);
  assert.equal(h.calls.wardrobe.length, 0);
});'''
new_release = '''test("release gate: after one location clarification a country answer proceeds without a questionnaire loop", async () => {
  const h = makeHarness();
  const first = await invoke(h.handler, baseData("country_chat", "c1", "zajtra idem na túru potrebujem outfit"));
  assertHealthy(first);
  assert.equal(first.action, "clarify");
  assert.match(first.reply, /kam približne/i);

  const response = await invoke(h.handler, baseData("country_chat", "c2", "USA"));
  assertHealthy(response);
  assert.equal(response.action, "generate_outfit");
  assert.doesNotMatch(response.reply, /mesto|štát|stat|región|region|kam približne/i);
  assert.equal(h.calls.location.length, 1);
  assert.equal(h.calls.model.length, 1);
  assert.equal(h.calls.model[0].schemaName, "stylist_v2_final");
  assert.equal(h.calls.weather.length, 0);
  assert.equal(h.calls.wardrobe.length, 1);

  const stored = await h.repository.get({uid: UID, chatId: "country_chat"});
  assert.equal(stored.state.context.destination.providerId, "place:usa");
  assert.equal(stored.state.context.groundingRequirements.weatherRequired, false);
  assert.equal(stored.state.conversationMemory.pendingQuestion, null);
});'''
replace_once(release_gate, old_release, new_release)

print("Updated obsolete country-level clarification expectations")
