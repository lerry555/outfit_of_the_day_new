from pathlib import Path


def read(path):
    return Path(path).read_text(encoding="utf-8")


def write(path, text):
    Path(path).write_text(text, encoding="utf-8")


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly 1 match, found {count}")
    return text.replace(old, new, 1)


# Client: safety may force clarify, but a valid Brain clarification owns wording.
path = "lib/screens/stylist_chat_screen.dart"
s = read(path)
s = replace_once(
    s,
    "import '../utils/stylist_occasion_guidance.dart';\n",
    "import '../utils/stylist_occasion_guidance.dart';\nimport '../utils/stylist_semantic_activity.dart';\n",
    "client semantic import",
)
old = "      response['reply'] = _groundingClarificationText(\n        _outfitContextState.unresolvedMaterialFields,\n        correction: _outfitContextState.userCorrectionDetected,\n      );\n"
new = "      final brainReply = (response['reply'] ?? '').toString().trim();\n      final brainAlreadyClarified = action == 'clarify' && brainReply.isNotEmpty;\n      if (!brainAlreadyClarified) {\n        response['reply'] = _groundingClarificationText(\n          _outfitContextState.unresolvedMaterialFields,\n          correction: _outfitContextState.userCorrectionDetected,\n        );\n      }\n"
s = replace_once(s, old, new, "client reply ownership")

replacements = {
    "Kam sa chystáte a čo tam budete približne robiť?": "Kam sa chystáš a čo tam budeš približne robiť?",
    "Čo budete po príchode približne robiť a na ktorý deň cez víkend outfit riešime? Počasie sa môže medzi dňami zmeniť.": "Čo budeš po príchode približne robiť a na ktorý deň cez víkend outfit riešime? Počasie sa môže medzi dňami zmeniť.",
    "Čo budete počas pobytu približne robiť a kedy cestujete?": "Čo budeš počas pobytu približne robiť a kedy cestuješ?",
    "Ešte kam sa chystáte? Podľa miesta vyberiem správne počasie.": "Ešte kam sa chystáš? Podľa miesta vyberiem správne počasie.",
    "Kam sa chystáte? Podľa miesta vyberiem vhodné počasie aj outfit.": "Kam sa chystáš? Podľa miesta vyberiem vhodné počasie aj outfit.",
    "Čo budete po príchode približne robiť? To rozhodne, či má byť outfit hlavne pohodlný, alebo aj upravenejší.": "Čo budeš po príchode približne robiť? To rozhodne, či má byť outfit hlavne pohodlný, alebo aj upravenejší.",
    "Čo máte počas pobytu v pláne? Na celodenné chodenie po meste a na lepšiu večeru sa balí trochu inak.": "Čo máš počas pobytu v pláne? Na celodenné chodenie po meste a na lepšiu večeru sa balí trochu inak.",
    "Čo tam budete približne robiť?": "Čo tam budeš približne robiť?",
    "Kedy cestujete? Podľa termínu overím správne počasie.": "Kedy cestuješ? Podľa termínu overím správne počasie.",
}
for old_text, new_text in replacements.items():
    if old_text not in s:
        raise SystemExit(f"client fallback copy missing: {old_text}")
    s = s.replace(old_text, new_text)

old_log = "        'location=${_outfitContextState.activityLocationLabel ?? '-'} '\n        'correction=${_outfitContextState.userCorrectionDetected}',\n"
new_log = "        'location=${_outfitContextState.activityLocationLabel ?? '-'} '\n        'activity=${_outfitContextState.activityHint ?? '-'} '\n        'unresolved=${_outfitContextState.unresolvedMaterialFields} '\n        'semantic=${StylistSemanticActivity.runtimeVersion} '\n        'directActivity=${StylistSemanticActivity.resolveExplicit(text) ?? '-'} '\n        'correction=${_outfitContextState.userCorrectionDetected}',\n"
s = replace_once(s, old_log, new_log, "client grounding diagnostic")
write(path, s)

# Shared deterministic resolver gets a runtime marker visible in debug logs.
path = "lib/utils/stylist_semantic_activity.dart"
s = read(path)
s = replace_once(
    s,
    "class StylistSemanticActivity {\n  const StylistSemanticActivity._();\n",
    "class StylistSemanticActivity {\n  const StylistSemanticActivity._();\n\n  static const String runtimeVersion = 'brain_v1_semantic_activity_v3';\n",
    "semantic runtime marker",
)
write(path, s)

# Server: verified semantic grounding always gets a transport object back to Flutter.
path = "functions/stylist/outfit_decision.js"
s = read(path)
old = "  return {\n    confidence,\n    decisionRisk,\n    assumptions,\n    clarifyReason,\n    impactFields,\n    semanticGrounding: parseSemanticGrounding(parsed),\n    eventContext:\n      parsed?.eventContext && typeof parsed.eventContext === \"object\" ?\n        parsed.eventContext : null,\n  };\n"
new = "  const semanticGrounding = parseSemanticGrounding(parsed);\n  let eventContext =\n    parsed?.eventContext && typeof parsed.eventContext === \"object\" &&\n      !Array.isArray(parsed.eventContext) ? parsed.eventContext : null;\n  if (semanticGrounding && parsed && typeof parsed === \"object\" &&\n      !Array.isArray(parsed) && !eventContext) {\n    eventContext = {};\n    parsed.eventContext = eventContext;\n  }\n\n  return {\n    confidence,\n    decisionRisk,\n    assumptions,\n    clarifyReason,\n    impactFields,\n    semanticGrounding,\n    eventContext,\n  };\n"
s = replace_once(s, old, new, "server semantic transport")
write(path, s)

# Brain contract: mandatory meaning-first semantic pre-pass for unresolved activity.
path = "functions/stylist/chat_prompts.js"
s = read(path)
old = '  `- Ak je unresolved "activity", NAJPRV skontroluj výhradne správy s rolou user. Ak user aktivitu významovo jasne pomenoval aj iným slovným tvarom/parafrázou, môžeš ju uzemniť cez semanticGrounding.activity.\\n` +\n'
new = '  `- Ak je unresolved "activity", MUSÍŠ pred voľbou action spraviť semantický pre-pass výhradne nad správami s rolou user: rozhodni, či user už významovo jasne opísal, čo bude robiť, aj keď nepoužil názov aktivity ani očakávané kľúčové slovo.\\n` +\n  `- Ak je aktivita z user textu významovo jednoznačná, semanticGrounding.activity je POVINNÉ a NESMIEŠ sa na tú istú aktivitu znovu pýtať. Parserovo unresolved vtedy znamená iba „fast-path to nerozpoznal“, nie „user to nepovedal“.\\n` +\n'
s = replace_once(s, old, new, "brain semantic prepass")
write(path, s)

# Lower variance for the structured Brain decision while keeping its natural persona.
path = "functions/stylist/ai_model_registry.js"
s = read(path)
s = replace_once(
    s,
    'provider: "openai", id: "gpt-4o", maxTokens: 700, temperature: 0.65,',
    'provider: "openai", id: "gpt-4o", maxTokens: 700, temperature: 0.3,',
    "brain temperature",
)
write(path, s)

# Emergency deterministic server copy stays only as a safety fallback and uses tykanie.
path = "functions/stylist/grounding_reply.js"
s = read(path)
server_copy = {
    "Kam sa chystáte a čo tam budete približne robiť?": "Kam sa chystáš a čo tam budeš približne robiť?",
    "Kam sa chystáte? Podľa miesta vyberiem vhodné počasie aj outfit.": "Kam sa chystáš? Podľa miesta vyberiem vhodné počasie aj outfit.",
    "Čo budete na výlete približne robiť a pôjde o jeden deň alebo viac dní?": "Čo budeš na výlete približne robiť a pôjde o jeden deň alebo viac dní?",
}
for old_text, new_text in server_copy.items():
    if old_text not in s:
        raise SystemExit(f"server fallback copy missing: {old_text}")
    s = s.replace(old_text, new_text)
write(path, s)

# Regression for semantic transport when the model omits eventContext.
path = "functions/stylist/outfit_decision.test.js"
s = read(path)
marker = 'test("semantic grounding cannot borrow assistant-only or invented evidence", () => {'
test_block = '''test("verified semantic activity creates transport context when model omits eventContext", () => {
  const parsed = {
    semanticGrounding: {
      activity: {
        value: "hike",
        evidence: "motať po vysokohorskom chodníku",
        source: "user_explicit",
      },
    },
  };
  const decision = parseOutfitDecisionFields(parsed);
  const state = {
    groundingStatus: "needs_grounding",
    unresolvedMaterialFields: ["activity"],
    semanticEvidenceTexts: [
      "budeme sa asi 6 hodín motať po vysokohorskom chodníku",
    ],
  };

  assert.equal(resolveOutfitAction("clarify", decision, state), "chat");
  assert.equal(state.activityHint, "hike");
  assert.equal(parsed.eventContext.occasion, "hike");
  assert.equal(decision.eventContext.occasion, "hike");
  assert.deepEqual(state.unresolvedMaterialFields, []);
});

'''
if test_block not in s:
    if marker not in s:
        raise SystemExit("server test insertion marker missing")
    s = s.replace(marker, test_block + marker, 1)
write(path, s)
