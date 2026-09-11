from pathlib import Path

ENGINE = Path('functions/stylist/v2/stylist_one_brain_engine_v2.js')
MODEL = Path('functions/stylist/v2/openai_one_brain_model_port_v2.js')
TEST = Path('functions/stylist/v2/stylist_general_location_layering_v2.test.js')


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 anchor, found {count}')
    return text.replace(old, new, 1)

engine = ENGINE.read_text(encoding='utf-8')

anchor = '''function userExplicitlyRequestsBestEffortV2(value) {
  return EXPLICIT_BEST_EFFORT_RE.test(normalizeConversationTextV2(value));
}
'''
addition = anchor + r'''
function explicitStylingDestinationCandidateV2(value) {
  const raw = String(value || "").replace(/\s+/g, " ").trim();
  if (!raw) return null;
  const normalized = normalizeConversationTextV2(raw);
  const stylingSignal = /\b(?:outfit|oblecen\w*|obliec\w*|na seba|tura|turistik\w*|hiking|trek\w*|vylet\w*|dovolen\w*|koncert\w*|festival\w*|svadb\w*|pohovor\w*|ples\w*|lyz\w*)\b/.test(normalized);
  if (!stylingSignal) return null;

  const travel = raw.match(/\b(?:idem|ideme|pojdem|pojdeme|chystam\s+sa|chystám\s+sa|chystame\s+sa|chystáme\s+sa|cestujem|cestujeme|letim|letím|letime|letíme|vyrazam|vyrážam|vyrazame|vyrážame)\s+(?:do|na|v|vo)\s+(.+?)(?=\s+(?:na|za)\s+(?:turu|túru|turistiku|vylet|výlet|vikend|víkend|dovolenku|koncert|festival|svadbu|pohovor|ples|lyzovacku|lyžovačku)\b|\s+(?:a\s+)?(?:ja\s+)?(?:neviem|netusim|netuším|chcem|potrebujem|co|čo)\b|[,!?]|$)/iu);
  const query = String(travel?.[1] || "").trim().replace(/[.]+$/g, "");
  if (!query || query.length > 160) return null;
  const eventLike = /\b(?:koncert\w*|festival\w*|svadb\w*|pohovor\w*|ples\w*|ceremoni\w*|oslava\w*)\b/.test(normalized);
  return {query, targetField: eventLike ? "eventLocation" : "destination"};
}
'''
engine = replace_once(engine, anchor, addition, 'engine explicit destination helper')

anchor = '''      const runtimeConstraints = {
        maxModelCalls: ONE_BRAIN_MAX_MODEL_CALLS,
'''
preflight = r'''      // Resolve an explicitly named travel destination before the model. This is
      // deliberately semantic and country-agnostic: the geocoder decides whether
      // the user's phrase is a country, region, city or POI. A country is too broad
      // for weather-sensitive remote styling, so ask the single useful location
      // question before spending a Brain call or reading the wardrobe.
      if (!pendingQuestionAtBrain && !bestEffortDirective) {
        const explicitDestination = explicitStylingDestinationCandidateV2(request.latestUserInput);
        if (explicitDestination) {
          let resolvedExplicitDestination = null;
          try {
            resolvedExplicitDestination = await locationResolver.resolve(explicitDestination.query);
          } catch (_) {
            resolvedExplicitDestination = null;
          }
          if (resolvedExplicitDestination) {
            const field = explicitDestination.targetField;
            workingState.context[field] = clone(resolvedExplicitDestination);
            workingState.conversationMemory.answeredClarificationFields[field] = clone(resolvedExplicitDestination);
            if (locationIsTooBroadForWeatherV2(resolvedExplicitDestination)) {
              const decision = broadLocationClarificationDecisionV2(
                {tool: "location", query: explicitDestination.query, targetField: field},
                {resolvedLocations: [{targetField: field, location: resolvedExplicitDestination}]},
              );
              return commitResultV2({
                durableRepository, uid, request, originalState, workingState, decision,
                wardrobeItems: [], authorizedEditScope: null,
              });
            }
          }
        }
      }

      const runtimeConstraints = {
        maxModelCalls: ONE_BRAIN_MAX_MODEL_CALLS,
'''
engine = replace_once(engine, anchor, preflight, 'engine runtime preflight')

anchor = '''  executeRequestedToolsV2,
  pendingReplyDispositionV2,
'''
replacement = '''  executeRequestedToolsV2,
  explicitStylingDestinationCandidateV2,
  pendingReplyDispositionV2,
'''
engine = replace_once(engine, anchor, replacement, 'engine export')
ENGINE.write_text(engine, encoding='utf-8')

model = MODEL.read_text(encoding='utf-8')
anchor = '''    "Vyberaj iba reálne item IDs z wardrobe tool výsledkov. Nevymýšľaj vlastnosti kúskov, počasie ani miesto.",
    "Ak ideálny kus chýba a nejde o objektívny safety hard-stop, dokonči najlepší dostupný outfit, označ kompromis a môžeš ponúknuť shopping.",
'''
replacement = '''    "Vyberaj iba reálne item IDs z wardrobe tool výsledkov. Nevymýšľaj vlastnosti kúskov, počasie ani miesto.",
    "Vrstvenie horných dielov musí mať funkčný zmysel. Rešpektuj layerPosition, warmth, canonicalType a outfitFunctions; viac vrstiev automaticky neznamená lepší alebo teplejší outfit.",
    "Ak vyberieš mid vrstvu (napr. mikinu alebo sveter) aj outer vrstvu, ľahší outer s nižším warmth smie ísť cez teplejší mid iba keď dáta explicitne ukazujú shell, vetruodolnú, dažďovú alebo inú ochrannú funkciu. Ľahká športová/tréningová/track bunda bez takej funkcie cez hrubšiu mikinu NIE JE ďalšia teplá vrstva; zvoľ jednu z nich alebo skutočný funkčný shell. Nikdy netvrď, že tenšia bunda pridáva teplo bez dôkazu v dátach.",
    "Ak ideálny kus chýba a nejde o objektívny safety hard-stop, dokonči najlepší dostupný outfit, označ kompromis a môžeš ponúknuť shopping.",
'''
model = replace_once(model, anchor, replacement, 'model layering contract')

anchor = '''    "Ak toolResults.wardrobeItems už obsahuje kúsky, celý relevantný šatník je prednačítaný. Nežiadaj ho znova len preto, aby si ho znovu načítal; pri editácii však stále vyžiadaj wardrobe request so scope/editScope, aby runtime zmrazil autorizovaný rozsah zmeny.",
    "Ak má vzniknúť nový outfit a wardrobeItems už sú prednačítané, môžeš vyžiadať iba potrebný location tool. Ak prednačítané nie sú, vyžiadaj wardrobe fakty. Location tool vyžiadaj iba ak používateľ uviedol cieľ, ktorý je užitočné rozlíšiť, alebo ak jeho rozlíšenie materiálne pomôže.",
'''
replacement = '''    "Ak toolResults.wardrobeItems už obsahuje kúsky, celý relevantný šatník je prednačítaný. Nežiadaj ho znova len preto, aby si ho znovu načítal; pri editácii však stále vyžiadaj wardrobe request so scope/editScope, aby runtime zmrazil autorizovaný rozsah zmeny.",
    "Runtime môže explicitný cieľ cesty geokódovať ešte pred tebou. Ak session už obsahuje destination/eventLocation s providerId pre miesto z aktuálnej správy, location tool pre to isté miesto znovu nežiadaj.",
    "Ak má vzniknúť nový outfit a wardrobeItems už sú prednačítané, môžeš vyžiadať iba potrebný location tool. Ak prednačítané nie sú, vyžiadaj wardrobe fakty. Location tool vyžiadaj iba ak používateľ uviedol cieľ, ktorý je užitočné rozlíšiť, alebo ak jeho rozlíšenie materiálne pomôže.",
'''
model = replace_once(model, anchor, replacement, 'model pre-resolved location contract')
MODEL.write_text(model, encoding='utf-8')

TEST.write_text(r'''"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  createStylistOneBrainEngineV2,
  explicitStylingDestinationCandidateV2,
} = require("./stylist_one_brain_engine_v2");
const {createMemoryStylistSessionRepositoryV2} = require("./stylist_session_repository_v2");
const {oneBrainPromptV2} = require("./openai_one_brain_model_port_v2");

const NOW = Date.parse("2026-09-11T12:00:00.000Z");

function request(message) {
  return {
    chatId: "chat_general_location",
    turnId: "t1",
    expectedSessionRevision: 0,
    latestUserInput: message,
    explicitUiActionId: null,
    freshClientObservations: {},
    clientCapabilities: {
      shoppingEnabled: false,
      supportsProgress: true,
      todayDateKey: "2026-09-11",
      tomorrowDateKey: "2026-09-12",
      timezoneOffsetMinutes: 120,
      recentHistory: [],
    },
  };
}

function enginePorts({resolvedLocation, calls}) {
  return {
    wardrobeTool: {
      async retrieve() {
        calls.wardrobe += 1;
        return [];
      },
    },
    locationResolver: {
      async resolve(query) {
        calls.location += 1;
        calls.query = query;
        return resolvedLocation;
      },
    },
    weatherTool: {
      async getForecast() {
        calls.weather += 1;
        throw new Error("weather must not run before broad-location clarification");
      },
    },
    shoppingTool: {
      async search() {
        calls.shopping += 1;
        return {candidateIds: [], appliedHardConstraints: [], reply: ""};
      },
    },
    stylistBrain: {
      async brainTurn() {
        calls.brain += 1;
        throw new Error("Brain must not run before broad-country clarification");
      },
    },
  };
}

test("general destination extractor finds Poland without country hard-coding", () => {
  assert.deepEqual(
    explicitStylingDestinationCandidateV2("buduci stvrtok ideme do polska na turu a ja neviem co na seba"),
    {query: "polska", targetField: "destination"},
  );
});

test("general destination extractor is not Austria-specific", () => {
  assert.deepEqual(
    explicitStylingDestinationCandidateV2("v sobotu ideme do Francuzska na vylet a potrebujem outfit"),
    {query: "Francuzska", targetField: "destination"},
  );
  assert.deepEqual(
    explicitStylingDestinationCandidateV2("zajtra ideme do USA na turu, co si mam obliect"),
    {query: "USA", targetField: "destination"},
  );
});

test("event trip targets eventLocation while hiking targets destination", () => {
  assert.deepEqual(
    explicitStylingDestinationCandidateV2("ideme do Berlina na koncert a neviem co na seba"),
    {query: "Berlina", targetField: "eventLocation"},
  );
});

test("country-level explicit destination clarifies before any Brain or wardrobe call", async () => {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  const calls = {brain: 0, location: 0, wardrobe: 0, weather: 0, shopping: 0, query: null};
  const engine = createStylistOneBrainEngineV2({
    sessionRepository: repository,
    ...enginePorts({
      calls,
      resolvedLocation: {
        providerId: "geo:any-country",
        label: "Poľsko",
        lat: 52.0,
        lng: 19.0,
        source: "fake-geocoder",
        granularity: "country",
        countryCode: "PL",
      },
    }),
    clock: () => NOW,
  });

  const result = await engine.resolveTurn({
    uid: "u_general_country",
    request: request("buduci stvrtok ideme do polska na turu a ja neviem co na seba"),
    bootstrapInput: {
      currentOutfitItemIds: [],
      persistedSelectionReasonsByItemId: {},
      knownExplicitDurableChoices: {},
    },
  });

  assert.equal(result.action, "clarify");
  assert.equal(result.clarification.field, "destination");
  assert.match(result.assistantText, /dosť široké/);
  assert.match(result.assistantText, /Kam približne/);
  assert.equal(calls.query, "polska");
  assert.equal(calls.location, 1);
  assert.equal(calls.brain, 0, "broad explicit country must not depend on a model choosing the location tool");
  assert.equal(calls.wardrobe, 0, "do not read the wardrobe before the one useful location answer");
  assert.equal(calls.weather, 0);
});

test("layering contract rejects warmth-by-stacking logic for thin sports outerwear", () => {
  const prompt = oneBrainPromptV2("answer");
  assert.match(prompt, /Vrstvenie horných dielov musí mať funkčný zmysel/);
  assert.match(prompt, /ľahší outer s nižším warmth/);
  assert.match(prompt, /športová\/tréningová\/track bunda/);
  assert.match(prompt, /NIE JE ďalšia teplá vrstva/);
  assert.match(prompt, /Nikdy netvrď, že tenšia bunda pridáva teplo/);
});
''', encoding='utf-8')

print('patched engine/model and created regression test')
