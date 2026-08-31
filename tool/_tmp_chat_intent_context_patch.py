from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one match, got {count}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


# 1) Client-side intent safety: a statement of plans is context, not an outfit request.
signals_path = Path("lib/utils/stylist_conversation_signals.dart")
signals = signals_path.read_text(encoding="utf-8")
anchor = """  static bool userExplicitlyWantsOutfitShown(String text) {\n"""
if anchor not in signals:
    raise SystemExit("stylist_conversation_signals.dart anchor missing")
if "isContextOnlyPlanStatement" in signals:
    raise SystemExit("context-only plan helper already exists")
insert = r'''  /// A plan/activity statement gives the conversation context but does not, by
  /// itself, authorize generating an outfit. Keep this broad and semantic:
  /// it applies to city plans, events, trips and other activities alike.
  static bool isContextOnlyPlanStatement(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) return false;

    final explicitlyRequestsStyling = RegExp(
      r'(outfit|co\s+si\s+mam\s+(?:dat|obliect)|čo\s+si\s+mám\s+(?:dať|obliecť)|co\s+na\s+seba|čo\s+na\s+seba|oblec|obleč|obliec|porad|odporuc|odporúč|navrh|vyber|pomoz|pomôž|daj\s+mi|chcem|ukaz|ukáž|zobraz|kombinac|kombinác)',
      caseSensitive: false,
    ).hasMatch(lower);
    if (explicitlyRequestsStyling) return false;

    return RegExp(
      r'\b(idem|ideme|pojdem|pôjdem|pojdeme|pôjdeme|chystam\s+sa|chystám\s+sa|chystame\s+sa|chystáme\s+sa|cestujem|cestujeme|letim|letím|letime|letíme|vyrazam|vyrážam|vyrazame|vyrážame|caka\s+ma|čaká\s+ma|caka\s+nas|čaká\s+nás)\b',
      caseSensitive: false,
    ).hasMatch(lower);
  }

'''
signals = signals.replace(anchor, insert + anchor, 1)
signals_path.write_text(signals, encoding="utf-8")


# 2) The screen enforces the intent invariant and sends the currently displayed
# outfit to Brain as presentation-safe app context for follow-up questions.
screen = "lib/screens/stylist_chat_screen.dart"
replace_once(
    screen,
    """    var effectiveAction = action;\n    var requestedImpactFields = response['impactFields'] is List\n""",
    """    var effectiveAction = action;\n    if (effectiveAction == 'generate_outfit' &&\n        !_conversationAlreadyHasOutfitCards() &&\n        StylistConversationSignals.isContextOnlyPlanStatement(userText)) {\n      // A declared plan is context only. Grounding becoming sufficient does\n      // not mean the user asked us to style them. This client invariant is a\n      // safety net even if a conversational model over-eagerly requests D/R.\n      effectiveAction = 'chat';\n      response['reply'] = 'Jasné 🙂';\n      debugPrint(\n        'STYLIST CHAT generation_suppressed reason=context_only_plan',\n      );\n    }\n    var requestedImpactFields = response['impactFields'] is List\n""",
)

replace_once(
    screen,
    """  Map<String, dynamic> _buildClientContext({String? cityName}) {\n""",
    r'''  List<Map<String, String>> _currentDisplayedOutfitContext() {
    String valueFor(Map<String, dynamic> item, List<String> keys) {
      for (final key in keys) {
        final raw = item[key];
        if (raw == null) continue;
        if (raw is List) {
          final value = raw
              .map((part) => part.toString().trim())
              .where((part) => part.isNotEmpty)
              .take(3)
              .join(', ');
          if (value.isNotEmpty) return value;
          continue;
        }
        if (raw is Map) {
          for (final nestedKey in const ['family', 'name', 'label']) {
            final nested = raw[nestedKey]?.toString().trim() ?? '';
            if (nested.isNotEmpty) return nested;
          }
          continue;
        }
        final value = raw.toString().trim();
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    for (final message in _messages.reversed) {
      if (message.isUser || message.suggestedItems.isEmpty) continue;
      return message.suggestedItems
          .take(6)
          .map((item) {
            final name = valueFor(
              item,
              const ['name', 'displayName', 'title', 'canonicalType', 'type'],
            );
            final type = valueFor(
              item,
              const ['canonicalType', 'type', 'subType', 'category'],
            );
            final color = valueFor(
              item,
              const ['primaryColor', 'color', 'colorName', 'colors'],
            );
            return <String, String>{
              if (name.isNotEmpty) 'name': name,
              if (type.isNotEmpty) 'type': type,
              if (color.isNotEmpty) 'color': color,
            };
          })
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const <Map<String, String>>[];
  }

  Map<String, dynamic> _buildClientContext({String? cityName}) {
''',
)
replace_once(
    screen,
    """    final lat = UserLocationService.instance.latitude;\n    final lon = UserLocationService.instance.longitude;\n    return <String, dynamic>{\n""",
    """    final lat = UserLocationService.instance.latitude;\n    final lon = UserLocationService.instance.longitude;\n    final currentOutfit = _currentDisplayedOutfitContext();\n    return <String, dynamic>{\n""",
)
replace_once(
    screen,
    """      if (eventDestination != null && eventDestination.isNotEmpty)\n        'eventDestination': eventDestination,\n      if (lat != null) 'latitude': lat,\n""",
    """      if (eventDestination != null && eventDestination.isNotEmpty)\n        'eventDestination': eventDestination,\n      if (currentOutfit.isNotEmpty) 'currentOutfit': currentOutfit,\n      if (lat != null) 'latitude': lat,\n""",
)


# 3) Brain prompt: explicit user intent owns generation; current outfit and app
# weather are authoritative conversational context.
prompt = "functions/stylist/chat_prompts.js"
replace_once(
    prompt,
    """  `- Keď používateľ iba reaguje, poďakuje alebo sa rozpráva, odpovedz normálne. Nemeň každú správu na formulár na generovanie outfitu.\\n` +\n  `- Pri konkrétnej rade môžeš prirodzene ponúknuť ďalší užitočný krok (pozrieť šatník, nájsť alternatívu), ale nikdy ho nenúť.\\n` +\n""",
    """  `- Keď používateľ iba reaguje, poďakuje alebo sa rozpráva, odpovedz normálne. Nemeň každú správu na formulár na generovanie outfitu.\\n` +\n  `- KRITICKÉ — samotné oznámenie plánu alebo aktivity (napr. že večer niekam ide, zajtra cestuje, má koncert, svadbu či prechádzku) je IBA kontext. Nie je to implicitná požiadavka na styling. Ak používateľ nežiada outfit, oblečenie, radu k tomu čo si dať, ani neprijíma tvoju predchádzajúcu ponuku outfitu, action MUSÍ zostať chat. Samotné sufficient grounding NIKDY neoprávňuje generate_outfit.\\n` +\n  `- generate_outfit použi iba keď používateľ významovo žiada zostaviť/odporučiť outfit alebo oblečenie, prijme ponuku na jeho zostavenie, prípadne explicitne mení už zobrazený outfit.\\n` +\n  `- Ak Client context obsahuje currentOutfit, je to autoritatívny outfit PRÁVE ZOBRAZENÝ používateľovi. Pri follow-upe typu „prečo?“, „je to vhodné?“, „čo na tom nie je ideálne?“ NIKDY netvrď, že outfit alebo konkrétne kúsky nevidíš; odpovedaj o currentOutfit.\\n` +\n  `- Keď vysvetľuješ alebo odporúčaš konkrétny outfit a Weather context je dostupný, prirodzene spomeň iba relevantné počasie (najmä kanonickú teplotu a dážď/vietor, ak menia voľbu). Nevymýšľaj inú teplotu.\\n` +\n  `- Pri konkrétnej rade môžeš prirodzene ponúknuť ďalší užitočný krok (pozrieť šatník, nájsť alternatívu), ale nikdy ho nenúť.\\n` +\n""",
)


# 4) Server explicitly sanitizes and exposes the current displayed outfit to
# Brain instead of relying on assistant prose as evidence.
index = "functions/index.js"
replace_once(
    index,
    """    const eventDestination = String(clientContext.eventDestination || \"\").trim();\n    const lat = clientContext.latitude;\n    const lon = clientContext.longitude;\n    const parts = [];\n""",
    """    const eventDestination = String(clientContext.eventDestination || \"\").trim();\n    const currentOutfit = Array.isArray(clientContext.currentOutfit) ?\n      clientContext.currentOutfit.slice(0, 6).map((raw) => {\n        if (!raw || typeof raw !== \"object\" || Array.isArray(raw)) return null;\n        const item = {};\n        for (const key of [\"name\", \"type\", \"color\"]) {\n          const value = String(raw[key] || \"\").trim().slice(0, 120);\n          if (value) item[key] = value;\n        }\n        return Object.keys(item).length ? item : null;\n      }).filter(Boolean) : [];\n    const lat = clientContext.latitude;\n    const lon = clientContext.longitude;\n    const parts = [];\n""",
)
replace_once(
    index,
    """    if (eventDestination) parts.push(`eventDestination=${eventDestination}`);\n    if (lat != null && lon != null) parts.push(`coords=${lat},${lon}`);\n""",
    """    if (eventDestination) parts.push(`eventDestination=${eventDestination}`);\n    if (currentOutfit.length) {\n      parts.push(`currentOutfit=${JSON.stringify(currentOutfit)}`);\n    }\n    if (lat != null && lon != null) parts.push(`coords=${lat},${lon}`);\n""",
)


# 5) Frozen explanation fallback must describe the real selected pieces and
# real resolved weather, and only call something a compromise when it is one.
authority = "functions/stylist/frozen_stylist_authority_v1.js"
replace_once(
    authority,
    """function deterministicExplanation(decision) {\n  return decision.action === \"reject_all\" ?\n    \"Z toho, čo máš, teraz neviem poskladať outfit, ktorý by som ti s čistým svedomím odporučil. Radšej ti poviem, čo v ňom chýba, než aby som predstieral, že je všetko v poriadku.\" :\n    \"Toto je z tvojho šatníka najsilnejšia dostupná kombinácia. Ak je niektorý kúsok kompromis, ber ho ako najlepšiu aktuálnu možnosť, nie ako ideálne riešenie.\";\n}\n""",
    r'''function listUserFacingItems(items) {
  const names = (Array.isArray(items) ? items : [])
    .map((item) => cleanText(item && item.name, 120))
    .filter(Boolean);
  if (!names.length) return "";
  if (names.length === 1) return names[0];
  if (names.length === 2) return `${names[0]} a ${names[1]}`;
  return `${names.slice(0, -1).join(", ")} a ${names[names.length - 1]}`;
}

function userFacingWeatherSummary(value) {
  const raw = cleanText(value, 240);
  if (!raw) return "";
  const parts = [];
  const temp = raw.match(/(-?\d+(?:\.\d+)?)\s*C\b/i);
  if (temp) parts.push(`približne ${temp[1].replace(".", ",")} °C`);
  if (/\brain=true\b/i.test(raw)) parts.push("s dažďom");
  else if (/\brain=false\b/i.test(raw)) parts.push("bez dažďa");
  if (/\bwind=true\b/i.test(raw)) parts.push("s vetrom");
  return parts.join(", ");
}

function deterministicExplanation(decision, normalized = null) {
  if (decision.action === "reject_all") {
    return "Z toho, čo máš, teraz neviem poskladať outfit, ktorý by som ti s čistým svedomím odporučil. Radšej ti poviem, čo v ňom chýba, než aby som predstieral, že je všetko v poriadku.";
  }
  const selected = normalized && Array.isArray(normalized.frozenCandidates) ?
    normalized.frozenCandidates.find((candidate) =>
      candidate.candidateId === decision.selectedCandidateId) : null;
  if (!selected) {
    return "Z tvojho šatníka som vybral najsilnejšiu dostupnú kombináciu pre túto situáciu.";
  }

  const sentences = [];
  const itemList = listUserFacingItems(selected.presentationItems);
  if (itemList) sentences.push(`Vybral som ${itemList}.`);
  const weather = userFacingWeatherSummary(
    normalized.resolvedContext && normalized.resolvedContext.weather,
  );
  if (weather) sentences.push(`Počítam pritom s ${weather}.`);

  const firstCompromise = selected.compromiseDetails && selected.compromiseDetails[0];
  if (firstCompromise) {
    const itemName = cleanText(firstCompromise.itemName, 120) || "jeden kúsok";
    const ideal = cleanText(firstCompromise.idealReplacementDescription, 180);
    sentences.push(
      ideal ?
        `${itemName} je tu kompromis; ideálnejšia náhrada by bola ${ideal}.` :
        `${itemName} je tu najlepší dostupný kompromis.`,
    );
  } else if (selected.compromiseClassification &&
      selected.compromiseClassification.level !== "none") {
    sentences.push("Je to najlepšia dostupná možnosť, hoci nie úplne bez kompromisu.");
  } else {
    sentences.push("Z toho, čo máš v šatníku, je to pre túto situáciu najsilnejšia dostupná kombinácia.");
  }
  return sentences.join(" ");
}
''',
)
replace_once(
    authority,
    """      const explanation = explanationValid ? explanationResult.value.explanation : deterministicExplanation(decision);\n""",
    """      const explanation = explanationValid ? explanationResult.value.explanation :\n        deterministicExplanation(decision, normalized);\n""",
)


# 6) Explanation model gets an explicit weather/pieces requirement too.
brain = "functions/stylist/conversation_brain_v1.js"
replace_once(
    brain,
    """    \"- Pri select_candidate pomenuj iba kúsky z userFacingSelectedOutfit. Vysvetli konkrétne, prečo kombinácia funguje pre situáciu, počasie alebo dress code.\",\n""",
    """    \"- Pri select_candidate pomenuj iba kúsky z userFacingSelectedOutfit. Vysvetli konkrétne, prečo kombinácia funguje pre situáciu, počasie alebo dress code.\",\n    \"- Ak userFacingContext.weather obsahuje teplotu/dážď/vietor, spomeň relevantné počasie prirodzene v používateľskom vysvetlení; nepoužívaj inú teplotu.\",\n    \"- Nikdy nepíš, že konkrétne kúsky alebo hotový outfit nevidíš: userFacingSelectedOutfit je presne uzavretý outfit, ktorý sa zobrazuje používateľovi.\",\n""",
)


# 7) Regression coverage for intent, current-outfit authority and fallback truthfulness.
test_path = Path("functions/stylist/frozen_stylist_explanation_user_facing_v1.test.js")
test_text = test_path.read_text(encoding="utf-8")
old_test = r'''test("deterministic explanation fallback remains user-facing", () => {
  const selected = deterministicExplanation({action: "select_candidate"});
  assert.equal(selected.includes("kontrolou"), false);
  assert.equal(selected.includes("najsilnejšia dostupná kombinácia"), true);
  assert.equal(selected.includes("candidate"), false);
  assert.equal(
    deterministicExplanation({action: "reject_all"}).includes("reason code"),
    false,
  );
});
'''
new_test = r'''test("deterministic explanation fallback remains grounded in selected pieces and weather", () => {
  const normalized = normalizeRequest(request(), owned);
  const selected = deterministicExplanation({
    action: "select_candidate",
    selectedCandidateId: "candidate-internal-only",
  }, normalized);
  assert.equal(selected.includes("biela košeľa"), true);
  assert.equal(selected.includes("sivé nohavice"), true);
  assert.equal(selected.includes("18 °C"), true);
  assert.equal(selected.includes("pružné turistické nohavice"), true);
  assert.equal(selected.includes("candidate"), false);
  assert.equal(
    deterministicExplanation({action: "reject_all"}).includes("reason code"),
    false,
  );
});

test("deterministic explanation never invents a compromise for a clean selected outfit", () => {
  const clean = request();
  clean.frozenCandidates[0].compromiseClassification = {level: "none", reasonCodes: []};
  clean.frozenCandidates[0].compromiseDetails = [];
  const normalized = normalizeRequest(clean, owned);
  const selected = deterministicExplanation({
    action: "select_candidate",
    selectedCandidateId: "candidate-internal-only",
  }, normalized);
  assert.equal(selected.includes("kompromis"), false);
  assert.equal(selected.includes("18 °C"), true);
  assert.equal(selected.includes("najsilnejšia dostupná kombinácia"), true);
});
'''
if old_test not in test_text:
    raise SystemExit("deterministic explanation test anchor missing")
test_path.write_text(test_text.replace(old_test, new_test, 1), encoding="utf-8")

bundle = Path("test/brain_v1_v2_offline_bundle_test.dart")
bundle_text = bundle.read_text(encoding="utf-8")
anchor_test = """  test('manual chat regressions keep local weather and quality guardrails', () {\n"""
if anchor_test not in bundle_text:
    raise SystemExit("offline bundle manual regression anchor missing")
new_bundle_test = r'''  test('conversation plan statements cannot silently authorize outfit generation', () {
    final signals = _read('lib/utils/stylist_conversation_signals.dart');
    final screen = _read('lib/screens/stylist_chat_screen.dart');
    final prompts = _read('functions/stylist/chat_prompts.js');
    final server = _read('functions/index.js');

    expect(signals, contains('isContextOnlyPlanStatement'));
    expect(signals, contains('ideme'));
    expect(signals, contains('porad'));
    expect(screen, contains('generation_suppressed reason=context_only_plan'));
    expect(screen, contains("'currentOutfit': currentOutfit"));
    expect(server, contains('clientContext.currentOutfit'));
    expect(server, contains('currentOutfit=${JSON.stringify(currentOutfit)}'));
    expect(prompts, contains('samotné oznámenie plánu alebo aktivity'));
    expect(prompts, contains('Samotné sufficient grounding NIKDY neoprávňuje generate_outfit'));
  });

'''
bundle_text = bundle_text.replace(anchor_test, new_bundle_test + anchor_test, 1)
bundle.write_text(bundle_text, encoding="utf-8")

print("chat intent/context patch applied")
