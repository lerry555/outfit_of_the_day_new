from pathlib import Path

engine = Path('functions/stylist/v2/stylist_one_brain_engine_v2.js')
text = engine.read_text(encoding='utf-8')

old = '''const SKIP_DIRECTIVE_RE = /\\b(neviem|netusim|je mi to jedno|preskoc|preskocme|neries|nechaj tak|nechajme to|kasli na to|zrus to|zabudni na to|bez pocasia|daj mi proste|proste mi daj|vyber proste)\\b/;'''
new = '''const SKIP_DIRECTIVE_RE = /\\b(neviem|netusim|je mi to jedno|preskoc|preskocme|neries|nechaj tak|nechajme to|kasli na to|zrus to|zabudni na to|bez pocasia|daj mi proste|proste mi daj|vyber proste)\\b/;\nconst EXPLICIT_BEST_EFFORT_RE = /\\b(je mi to jedno|preskoc|preskocme|neries|nechaj tak|nechajme to|kasli na to|zrus to|zabudni na to|bez pocasia|daj mi proste|proste mi daj|vyber proste)\\b/;'''
if new not in text:
    if old not in text:
        raise SystemExit('best-effort regex anchor missing')
    text = text.replace(old, new, 1)

old = '''function userRequestsBestEffortV2(value) {\n  return SKIP_DIRECTIVE_RE.test(normalizeConversationTextV2(value));\n}\n'''
new = '''function userRequestsBestEffortV2(value) {\n  return SKIP_DIRECTIVE_RE.test(normalizeConversationTextV2(value));\n}\n\nfunction userExplicitlyRequestsBestEffortV2(value) {\n  return EXPLICIT_BEST_EFFORT_RE.test(normalizeConversationTextV2(value));\n}\n'''
if new not in text:
    if old not in text:
        raise SystemExit('best-effort helper anchor missing')
    text = text.replace(old, new, 1)

old = '''      const hadPendingQuestion = Boolean(workingState.conversationMemory.pendingQuestion);\n      const bestEffortDirective = userRequestsBestEffortV2(request.latestUserInput);\n      if (hadPendingQuestion && bestEffortDirective) {\n      workingState = applySkipToPendingQuestionV2(workingState);\n    }'''
new = '''      const hadPendingQuestion = Boolean(workingState.conversationMemory.pendingQuestion);\n      const pendingSkipDirective = hadPendingQuestion && userRequestsBestEffortV2(request.latestUserInput);\n      const bestEffortDirective = pendingSkipDirective ||\n        (!hadPendingQuestion && userExplicitlyRequestsBestEffortV2(request.latestUserInput));\n      if (pendingSkipDirective) {\n      workingState = applySkipToPendingQuestionV2(workingState);\n    }'''
if new not in text:
    if old not in text:
        raise SystemExit('best-effort call-site anchor missing')
    text = text.replace(old, new, 1)

anchor = '''async function executeRequestedToolsV2({envelope, state, wardrobeTool, locationResolver, weatherTool,\n  knownWardrobeItems = null}) {'''
helper = '''function broadLocationClarificationDecisionV2(locationRequest, toolResults) {\n  const resolved = (toolResults?.resolvedLocations || [])\n    .find((entry) => entry?.targetField === locationRequest?.targetField)?.location;\n  const rawLabel = String(resolved?.label || locationRequest?.query || "").trim();\n  const label = rawLabel ? `„${rawLabel}“` : "Toto miesto";\n  const targetField = locationRequest?.targetField === "eventLocation" ? "eventLocation" : "destination";\n  const question = targetField === "eventLocation" ?\n    `Jasné 😊 ${label} je ešte dosť široké. Kde približne sa tá udalosť koná?` :\n    `Jasné 😊 ${label} je na takýto plán ešte dosť široké. Kam približne tam ideš? Stačí oblasť alebo pohorie.`;\n  return {\n    action: "clarify",\n    assistantText: question,\n    clarification: {\n      field: targetField,\n      question,\n      actionId: `clarify_${targetField}_narrow`,\n      acceptsYesNo: false,\n    },\n    display: {kind: "none", itemIds: []},\n  };\n}\n\n'''
if helper not in text:
    if anchor not in text:
        raise SystemExit('engine helper anchor missing')
    text = text.replace(anchor, helper + anchor, 1)

old = '''      workingState = executed.workingState;\n      const answerConstraints = {'''
new = '''      workingState = executed.workingState;\n      const broadLocationRequest = toolEnvelope.requests.find((entry) => entry?.tool === "location");\n      if (!pendingQuestionAtBrain &&\n          runtimeConstraints.allowClarification &&\n          broadLocationRequest &&\n          executed.toolResults.locationStatus === "broad") {\n        const decision = broadLocationClarificationDecisionV2(broadLocationRequest, executed.toolResults);\n        return commitResultV2({\n          durableRepository, uid, request, originalState, workingState, decision,\n          wardrobeItems: executed.wardrobeItems,\n          authorizedEditScope: executed.toolResults.authorizedEditScope,\n        });\n      }\n      const answerConstraints = {'''
if new not in text:
    if old not in text:
        raise SystemExit('engine intercept anchor missing')
    text = text.replace(old, new, 1)
engine.write_text(text, encoding='utf-8')

model = Path('functions/stylist/v2/openai_one_brain_model_port_v2.js')
text = model.read_text(encoding='utf-8')
old = '''    "Tón: priateľský profesionál — teplý, nenútený a ľudský, ale stále kompetentný. Jemne zrkadli energiu používateľa a nepreháňaj familiárnosť, ak ju používateľ sám nenastaví.",\n    "Emoji používaj striedmo a prirodzene, zvyčajne najviac jedno v odpovedi. Nemusí byť v každej správe a pri vážnom bezpečnostnom upozornení ho radšej vynechaj.",'''
new = '''    "Tón: priateľský profesionál — teplý, nenútený a ľudský, ale stále kompetentný. Jemne zrkadli energiu používateľa a nepreháňaj familiárnosť, ak ju používateľ sám nenastaví.",\n    "Pri prvom vecnom turne s prosbou o radu nezačínaj holým rozkazom typu Na túru si daj. Najprv krátko ľudsky nadviaž, napríklad Jasné, Super alebo Poďme na to, a hneď pokračuj konkrétnou pomocou. Acknowledgement má byť krátke, nie vata.",\n    "Emoji používaj striedmo a prirodzene, zvyčajne najviac jedno v odpovedi. Nemusí byť v každej správe a pri vážnom bezpečnostnom upozornení ho radšej vynechaj.",'''
if new not in text:
    if old not in text:
        raise SystemExit('model warmth anchor missing')
    text = text.replace(old, new, 1)
model.write_text(text, encoding='utf-8')

test_file = Path('functions/stylist/v2/stylist_one_brain_runtime_v2.test.js')
text = test_file.read_text(encoding='utf-8')
marker = 'test("One Brain: neviem permanently consumes the pending field for that continuation", async () => {'
regression = r'''test("One Brain: country-level hike is narrowed deterministically before the answer stage", async () => {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  const calls = {brainInputs: []};
  const brain = {
    async brainTurn(input) {
      calls.brainInputs.push(JSON.parse(JSON.stringify(input)));
      return {
        kind: "tool_request",
        statePatch: {
          context: {
            activity: {id: "hiking", label: "turistika", source: "user"},
            date: {dateKey: "2026-09-17", source: "user"},
            timeWindow: {key: "day", label: "cez deň", source: "one_brain_default"},
            environment: "outdoor",
            groundingRequirements: {
              weatherRequired: true,
              weatherLocationField: "destination",
              terrainRequiredFields: [],
            },
          },
        },
        requests: [
          {tool: "location", query: "Rakúsko", targetField: "destination"},
          {tool: "wardrobe", scope: "full_relevant", category: null, editScope: null},
        ],
      };
    },
  };
  const ports = fakePorts({
    brain,
    calls,
    location: {
      providerId: "openmeteo:austria",
      label: "Rakúsko",
      lat: 47.5,
      lng: 14.5,
      source: "fake-location",
      granularity: "country",
    },
  });
  const engine = createStylistOneBrainEngineV2({sessionRepository: repository, ...ports, clock: () => NOW});
  const result = await engine.resolveTurn({
    uid: "u_country",
    request: request({
      chatId: "chat_country_hike",
      turnId: "t1",
      revision: 0,
      message: "budúci štvrtok ideme do Rakúska na turistiku a neviem čo si mám obliecť",
    }),
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
  assert.equal(calls.location, 1);
  assert.equal(calls.wardrobe, 1);
  assert.equal(calls.weather || 0, 0);
  assert.equal(calls.brainInputs.length, 1, "broad country must not spend the answer-stage model call");
});

'''
if regression not in text:
    if marker not in text:
        raise SystemExit('test insertion marker missing')
    text = text.replace(marker, regression + marker, 1)
old_assert = '''  assert.match(systemPrompt, /priateľský profesionál/);\n  assert.match(systemPrompt, /Emoji používaj striedmo/);'''
new_assert = '''  assert.match(systemPrompt, /priateľský profesionál/);\n  assert.match(systemPrompt, /nezačínaj holým rozkazom/);\n  assert.match(systemPrompt, /Emoji používaj striedmo/);'''
if new_assert not in text:
    if old_assert not in text:
        raise SystemExit('prompt assertion anchor missing')
    text = text.replace(old_assert, new_assert, 1)
test_file.write_text(text, encoding='utf-8')
