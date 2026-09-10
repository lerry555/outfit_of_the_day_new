from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path, old, new):
    p = ROOT / path
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected exactly one match, got {count}: {old[:120]!r}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


def append_once(path, marker, addition):
    p = ROOT / path
    text = p.read_text(encoding="utf-8")
    if marker in text:
        raise RuntimeError(f"{path}: marker already present: {marker}")
    p.write_text(text.rstrip() + "\n\n" + addition.rstrip() + "\n", encoding="utf-8")


# ---------------------------------------------------------------------------
# Flutter: generic greeting/advice intro must be instant but must never swallow
# an actual outfit request.
# ---------------------------------------------------------------------------
replace_once(
    "lib/Services/stylist_simple_agent_service_v1.dart",
    """  static bool _isFriendlyLocalGreeting(String normalized) {\n    if (_localGreetingTexts.contains(normalized)) return true;\n    return RegExp(\n      r'^(ahoj|čau|cau|čauko|cauko|nazdar|servus|hello|hi|hey)\\s+(divočák|divocak|kamo|kamarát|kamarat|stylista)$',\n    ).hasMatch(normalized);\n  }\n\n  @visibleForTesting\n  static Map<String, dynamic>? localFastReplyForMessage(String message) {\n    final normalized = _normalizeLocalFastText(message);\n    String? reply;\n    if (_isFriendlyLocalGreeting(normalized) ||\n        (normalized.isEmpty && message.contains('👋'))) {\n      reply = 'Ahoj! Ako ti môžem pomôcť?';\n    } else if (_localThanksTexts.contains(normalized)) {\n""",
    """  static bool _isFriendlyLocalGreeting(String normalized) {\n    if (_localGreetingTexts.contains(normalized)) return true;\n    return RegExp(\n      r'^(ahoj|čau|cau|čauko|cauko|nazdar|servus|hello|hi|hey)\\s+(divočák|divocak|kamo|kamarát|kamarat|stylista)$',\n    ).hasMatch(normalized);\n  }\n\n  static bool _isGenericAdviceIntro(String normalized) => RegExp(\n        r'^(ahoj|čau|cau|čauko|cauko|nazdar|servus|hello|hi|hey)'\n        r'(?:\\s+(divočák|divocak|kamo|kamarát|kamarat|stylista))?'\n        r'\\s+(potrebujem|chcem|mohol by si|môžeš mi|mozes mi)'\n        r'\\s+(poradiť|poradit|poradíš|poradis)$',\n      ).hasMatch(normalized);\n\n  @visibleForTesting\n  static Map<String, dynamic>? localFastReplyForMessage(String message) {\n    final normalized = _normalizeLocalFastText(message);\n    String? reply;\n    if (_isGenericAdviceIntro(normalized)) {\n      reply = 'Ahoj! Jasné 🙂 S čím ti môžem pomôcť?';\n    } else if (_isFriendlyLocalGreeting(normalized) ||\n        (normalized.isEmpty && message.contains('👋'))) {\n      reply = 'Ahoj! Ako ti môžem pomôcť?';\n    } else if (_localThanksTexts.contains(normalized)) {\n""",
)

replace_once(
    "test/stylist_simple_agent_fast_path_test.dart",
    """  test('real stylist requests never get swallowed by local fast path', () {\n    expect(StylistSimpleAgentServiceV1.localFastReplyForMessage('ahoj, zajtra idem na koncert a potrebujem outfit'), isNull);\n""",
    """  test('generic advice intro is instant but real styling stays on the stylist path', () {\n    final result = StylistSimpleAgentServiceV1.localFastReplyForMessage('ahoj divočák potrebujem poradiť');\n    expect(result, isNotNull);\n    expect(result!['modelPath'], 'local_fast');\n    expect(result['reply'], 'Ahoj! Jasné 🙂 S čím ti môžem pomôcť?');\n\n    expect(StylistSimpleAgentServiceV1.localFastReplyForMessage('ahoj divočák potrebujem poradiť s outfitom'), isNull);\n  });\n\n  test('real stylist requests never get swallowed by local fast path', () {\n    expect(StylistSimpleAgentServiceV1.localFastReplyForMessage('ahoj, zajtra idem na koncert a potrebujem outfit'), isNull);\n""",
)

# ---------------------------------------------------------------------------
# Coordinator: conservative grammar fast lane for obvious remote outfit turns.
# It is activity- and place-agnostic: it recognizes common semantic activities,
# resolves the location directly, and skips the planner model entirely.
# ---------------------------------------------------------------------------
replace_once(
    "functions/stylist/v2/stylist_turn_coordinator_v2.js",
    """function broadLocationClarificationDecision(field, latestUserInput) {\n  const candidate = cleanLocationAnswerFragmentV2(latestUserInput).slice(0, 120) || \"toto miesto\";\n  const event = field === \"eventLocation\";\n  const question = event ?\n    `„${candidate}“ je na spoľahlivé miestne počasie príliš široké. V ktorom meste, štáte alebo regióne sa podujatie koná?` :\n    `„${candidate}“ je na spoľahlivé miestne počasie príliš široké. Do ktorého mesta, štátu alebo regiónu ideš?`;\n  const actionId = event ? \"clarify_event_location\" : \"clarify_destination\";\n  return {action: \"clarify\", assistantText: question, clarification: {field, question, actionId}, display: {kind: \"none\", itemIds: []}};\n}\n""",
    """function broadLocationClarificationDecision(field, latestUserInput) {\n  const event = field === \"eventLocation\";\n  const question = event ?\n    \"Kde približne sa podujatie koná? Stačí mesto alebo oblasť.\" :\n    \"Kam približne ideš? Stačí oblasť alebo najbližšie mesto.\";\n  const actionId = event ? \"clarify_event_location\" : \"clarify_destination\";\n  return {action: \"clarify\", assistantText: question, clarification: {field, question, actionId}, display: {kind: \"none\", itemIds: []}};\n}\n""",
)

replace_once(
    "functions/stylist/v2/stylist_turn_coordinator_v2.js",
    """function disableOptionalWeatherGroundingV2(state) {\n""",
    """function inferObviousActivityV2(value) {\n  const text = normalizeConversationTextV2(value);\n  const definitions = [\n    {id: \"hiking\", label: \"túra\", environment: \"outdoor\", event: false, pattern: /\\b(tura|turu|turistika|hiking|hike|trek|treking)\\b/},\n    {id: \"concert\", label: \"koncert\", environment: \"mixed\", event: true, pattern: /\\b(koncert|concert|festival)\\b/},\n    {id: \"wedding\", label: \"svadba\", environment: \"mixed\", event: true, pattern: /\\b(svadba|svadbu|wedding)\\b/},\n    {id: \"interview\", label: \"pohovor\", environment: \"indoor\", event: true, pattern: /\\b(pohovor|interview)\\b/},\n    {id: \"dinner\", label: \"večera\", environment: \"indoor\", event: true, pattern: /\\b(vecera|dinner|restauracia|restaurant)\\b/},\n    {id: \"cinema\", label: \"kino\", environment: \"indoor\", event: true, pattern: /\\b(kino|cinema)\\b/},\n    {id: \"date\", label: \"rande\", environment: \"mixed\", event: true, pattern: /\\b(rande|date)\\b/},\n    {id: \"party\", label: \"oslava\", environment: \"mixed\", event: true, pattern: /\\b(oslava|party|ples)\\b/},\n  ];\n  return definitions.find((entry) => entry.pattern.test(text)) || null;\n}\n\nfunction explicitTravelDestinationCandidateV2(value) {\n  const raw = String(value || \"\").trim().replace(/\\s+/g, \" \");\n  if (!raw) return \"\";\n  const match = raw.match(/\\b(?:idem|ideme|pojdem|pojdeme|chystám\\s+sa|chystam\\s+sa|chystáme\\s+sa|chystame\\s+sa|cestujem|cestujeme|letím|letim|letíme|letime|vyrážam|vyrazam|vyrážame|vyrazame|chcem\\s+(?:ísť|ist)|chcel\\s+by\\s+som\\s+(?:ísť|ist))\\s+(?:do|v|vo)\\s+(.+?)(?=\\s+(?:na|kvôli|kvoli)\\s+|[,;.!?]|$)/iu);\n  if (!match) return \"\";\n  const candidate = match[1].trim().slice(0, 180);\n  const normalized = normalizeConversationTextV2(candidate);\n  if (/^(prace|skoly|fitka|posilnovne|kina|domu)$/.test(normalized)) return \"\";\n  return candidate;\n}\n\nfunction deterministicRemoteOutfitFastLaneV2(request, state) {\n  if (state.conversationMemory.pendingQuestion || state.conversationMemory.pendingAction) return null;\n  const text = normalizeConversationTextV2(request.latestUserInput);\n  const asksOutfit = /\\b(outfit|oblecenie|obliect|co si mam dat|co mam na seba|vyber mi|navrhni mi|zostav mi)\\b/.test(text);\n  if (!asksOutfit) return null;\n  const activity = inferObviousActivityV2(request.latestUserInput);\n  const locationQuery = explicitTravelDestinationCandidateV2(request.latestUserInput);\n  if (!activity || !locationQuery) return null;\n\n  let dateKey = null;\n  if (/\\b(zajtra|tomorrow)\\b/.test(text)) dateKey = request.clientCapabilities?.tomorrowDateKey || null;\n  else if (/\\b(dnes|today)\\b/.test(text)) dateKey = request.clientCapabilities?.todayDateKey || null;\n  if (!dateKey) return null;\n\n  const targetField = activity.event ? \"eventLocation\" : \"destination\";\n  const next = clone(state);\n  next.context.activity = {id: activity.id, label: activity.label, source: \"user\"};\n  next.context.environment = activity.environment;\n  next.context.date = {dateKey, source: \"user\"};\n  next.context.timeWindow = next.context.timeWindow || {key: \"day\", label: \"cez deň\", source: \"help_first_default\"};\n  next.context.weather = null;\n  next.context[targetField] = null;\n  if (targetField === \"destination\") next.context.eventLocation = null;\n  else next.context.destination = null;\n  next.context.groundingRequirements = {\n    weatherRequired: true,\n    weatherLocationField: targetField,\n    terrainRequiredFields: [],\n  };\n  return {state: next, targetField, locationQuery};\n}\n\nfunction semanticLocationFallbackV2(value, field) {\n  const label = cleanLocationAnswerFragmentV2(value).slice(0, 220) || \"neupresnené miesto\";\n  const slug = normalizeConversationTextV2(label).replace(/\\s+/g, \"-\").slice(0, 80) || \"unknown\";\n  return {\n    providerId: `user-text:${field}:${slug}`,\n    label,\n    source: \"user_text\",\n    granularity: \"region\",\n  };\n}\n\nfunction disableOptionalWeatherGroundingV2(state) {\n""",
)

replace_once(
    "functions/stylist/v2/stylist_turn_coordinator_v2.js",
    """      if (!decision && preflight.kind === \"continue\") {\n        const fastClarification = deterministicRemoteOutfitClarificationV2(request, workingState);\n        if (fastClarification) {\n          workingState = fastClarification.state;\n          decision = fastClarification.decision;\n        }\n      }\n\n      const pendingQuestion = workingState.conversationMemory.pendingQuestion;\n""",
    """      if (!decision && preflight.kind === \"continue\") {\n        const fastLane = deterministicRemoteOutfitFastLaneV2(request, workingState);\n        if (fastLane) {\n          workingState = fastLane.state;\n          const resolved = await locationResolver.resolve(fastLane.locationQuery);\n          if (!resolved) {\n            const semantic = semanticLocationFallbackV2(fastLane.locationQuery, fastLane.targetField);\n            workingState.context[fastLane.targetField] = semantic;\n            workingState.conversationMemory.answeredClarificationFields[fastLane.targetField] = clone(semantic);\n            workingState = disableOptionalWeatherGroundingV2(workingState);\n            pendingLocationContinuation = true;\n          } else if (locationIsTooBroadForWeatherV2(resolved)) {\n            workingState.context[fastLane.targetField] = resolved;\n            workingState.conversationMemory.answeredClarificationFields[fastLane.targetField] = clone(resolved);\n            const broad = broadLocationClarificationDecision(fastLane.targetField, fastLane.locationQuery);\n            workingState.conversationMemory.pendingQuestion = {\n              type: \"question\",\n              actionId: broad.clarification.actionId,\n              field: fastLane.targetField,\n              question: broad.clarification.question,\n              acceptsYesNo: false,\n              attemptedAnswers: [fastLane.locationQuery],\n            };\n            decision = broad;\n          } else {\n            workingState.context[fastLane.targetField] = resolved;\n            workingState.conversationMemory.answeredClarificationFields[fastLane.targetField] = clone(resolved);\n            toolResults.resolvedLocations.push({targetField: fastLane.targetField, location: clone(resolved)});\n            pendingLocationContinuation = true;\n          }\n        }\n      }\n\n      if (!decision && preflight.kind === \"continue\") {\n        const fastClarification = deterministicRemoteOutfitClarificationV2(request, workingState);\n        if (fastClarification) {\n          workingState = fastClarification.state;\n          decision = fastClarification.decision;\n        }\n      }\n\n      const pendingQuestion = workingState.conversationMemory.pendingQuestion;\n""",
)

replace_once(
    "functions/stylist/v2/stylist_turn_coordinator_v2.js",
    """          if (!resolution.resolved) {\n            // Exact weather is optional after the user has already answered the\n            // one useful location question. A geocoder miss is a tool failure,\n            // not a reason to trap the conversation in another questionnaire.\n            rememberPendingLocationAttemptV2(workingState, pendingField, request.latestUserInput);\n            workingState = skipPendingClarificationV2(workingState, pendingField);\n            pendingLocationContinuation = true;\n""",
    """          if (!resolution.resolved) {\n            // Exact weather is optional after the user has already answered the\n            // one useful location question. Preserve the user's semantic place\n            // (for natural final wording) but never turn a geocoder miss into a\n            // second questionnaire turn.\n            rememberPendingLocationAttemptV2(workingState, pendingField, request.latestUserInput);\n            const semanticQuery = resolution.queries?.[0] || request.latestUserInput;\n            const semantic = semanticLocationFallbackV2(semanticQuery, pendingField);\n            workingState.context[pendingField] = semantic;\n            workingState.conversationMemory.answeredClarificationFields[pendingField] = clone(semantic);\n            workingState = disableOptionalWeatherGroundingV2(workingState);\n            pendingLocationContinuation = true;\n""",
)

replace_once(
    "functions/stylist/v2/stylist_turn_coordinator_v2.js",
    """  deterministicRemoteOutfitClarificationV2,\n  disableOptionalWeatherGroundingV2,\n""",
    """  deterministicRemoteOutfitClarificationV2,\n  deterministicRemoteOutfitFastLaneV2,\n  disableOptionalWeatherGroundingV2,\n  explicitTravelDestinationCandidateV2,\n  inferObviousActivityV2,\n  semanticLocationFallbackV2,\n""",
)

# ---------------------------------------------------------------------------
# Engine: production bridge already read the canonical state. Reuse it; and
# after a successful CAS commit trust the state just validated/committed instead
# of reading the same Firestore document again.
# ---------------------------------------------------------------------------
replace_once(
    "functions/stylist/v2/stylist_turn_engine_v2.js",
    """      const persisted = await durableRepository.get({uid, chatId: request.chatId});\n      if (!persisted?.state) {\n        throw new StylistSessionRepositoryV2Error(\"SESSION_NOT_FOUND\", \"session disappeared after commit\");\n      }\n      workingState = clone(persisted.state);\n      return clone(workingState);\n""",
    """      if (!commitOutcome?.replayed) {\n        workingState = clone(validated);\n        return clone(workingState);\n      }\n      const persisted = await durableRepository.get({uid, chatId: request.chatId});\n      if (!persisted?.state) {\n        throw new StylistSessionRepositoryV2Error(\"SESSION_NOT_FOUND\", \"session disappeared after replay commit\");\n      }\n      workingState = clone(persisted.state);\n      return clone(workingState);\n""",
)
replace_once(
    "functions/stylist/v2/stylist_turn_engine_v2.js",
    """    async resolveTurn({uid, request: untrustedRequest, bootstrapInput = null}) {\n      const request = validateTurnRequestV2(untrustedRequest);\n      let initialState = await ensureCanonicalSession({\n        durableRepository,\n        uid,\n        request,\n        bootstrapInput,\n      });\n""",
    """    async resolveTurn({uid, request: untrustedRequest, bootstrapInput = null, knownCanonicalState = null}) {\n      const request = validateTurnRequestV2(untrustedRequest);\n      let initialState = knownCanonicalState ? validateStylistSessionStateV2(knownCanonicalState) :\n        await ensureCanonicalSession({\n          durableRepository,\n          uid,\n          request,\n          bootstrapInput,\n        });\n""",
)

# ---------------------------------------------------------------------------
# Production bridge: tiny conversation-only greeting/advice acknowledgement is
# server-local too; pass the already-read state into the engine; shrink prose
# history supplied as an optional model hint.
# ---------------------------------------------------------------------------
replace_once(
    "functions/stylist/v2/stylist_production_bridge_v2.js",
    """function reasonsMap(raw) {\n""",
    """function normalizeLocalConversationTextV2(value) {\n  return clean(value, 500)\n    .normalize(\"NFD\")\n    .replace(/[\\u0300-\\u036f]/g, \"\")\n    .toLowerCase()\n    .replace(/[^a-z0-9\\s]/g, \" \")\n    .replace(/\\s+/g, \" \")\n    .trim();\n}\n\nfunction localConversationReplyV2(message) {\n  const text = normalizeLocalConversationTextV2(message);\n  if (/^(ahoj|cau|cauko|nazdar|servus|hello|hi|hey)(?:\\s+(divocak|kamo|kamarat|stylista))?$/.test(text)) {\n    return \"Ahoj! Ako ti môžem pomôcť?\";\n  }\n  if (/^(ahoj|cau|cauko|nazdar|servus|hello|hi|hey)(?:\\s+(divocak|kamo|kamarat|stylista))?\\s+(potrebujem|chcem|mohol by si|mozes mi)\\s+(poradit|poradis)$/.test(text)) {\n    return \"Ahoj! Jasné 🙂 S čím ti môžem pomôcť?\";\n  }\n  return null;\n}\n\nfunction reasonsMap(raw) {\n""",
)
replace_once(
    "functions/stylist/v2/stylist_production_bridge_v2.js",
    """  const recentHistory = (Array.isArray(data?.history) ? data.history : [])\n    .slice(-8)\n    .map((entry) => ({\n      role: entry?.role === \"assistant\" ? \"assistant\" : \"user\",\n      content: clean(entry?.content, 1200),\n""",
    """  const recentHistory = (Array.isArray(data?.history) ? data.history : [])\n    .slice(-6)\n    .map((entry) => ({\n      role: entry?.role === \"assistant\" ? \"assistant\" : \"user\",\n      content: clean(entry?.content, 700),\n""",
)
replace_once(
    "functions/stylist/v2/stylist_production_bridge_v2.js",
    """      const executeStructured = modelFactory ? null : createOpenAiSimpleAgentExecutorV1({\n""",
    """      const localReply = !shoppingActive ? localConversationReplyV2(message) : null;\n      if (localReply) {\n        const response = {\n          ok: true, simpleAgent: true, v2: true, failClosed: false, contractVersion: 2,\n          modelPath: \"stylist_v2_local_chat\", sessionId, sessionRevision: existing?.state?.revision ?? 0,\n          reply: localReply, stylistComment: localReply,\n          resultingOutfitItemIds: [], displayItemIds: [], resultingOutfitItems: [], displayItems: [],\n          outfitChanged: false, quickReplyMode: \"none\", quickReplyPrompt: null, action: \"chat\",\n        };\n        logger?.info?.(\"STYLIST_V2_TURN_LATENCY\", {path: \"local_chat\", totalMs: Date.now() - turnStartedAt});\n        await writeJobResult({db, admin, uid, notifyJobId, result: response});\n        return response;\n      }\n\n      const executeStructured = modelFactory ? null : createOpenAiSimpleAgentExecutorV1({\n""",
)
replace_once(
    "functions/stylist/v2/stylist_production_bridge_v2.js",
    """      const result = await engine.resolveTurn({\n        uid,\n        request,\n        bootstrapInput: existing ? null : {\n""",
    """      const result = await engine.resolveTurn({\n        uid,\n        request,\n        knownCanonicalState: existing?.state || null,\n        bootstrapInput: existing ? null : {\n""",
)
replace_once(
    "functions/stylist/v2/stylist_production_bridge_v2.js",
    """  legacyCompatibleResponse,\n  migrateProvisionalSession,\n};\n""",
    """  legacyCompatibleResponse,\n  localConversationReplyV2,\n  migrateProvisionalSession,\n};\n""",
)

# ---------------------------------------------------------------------------
# Model adapter: constrain clarification field vocabulary, send only the active
# semantic state, compact weather + wardrobe, and make compromise language
# conversational rather than an internal-state report.
# ---------------------------------------------------------------------------
replace_once(
    "functions/stylist/v2/openai_stylist_model_port_v2.js",
    """const ACTIONS = [\"chat\", \"clarify\", \"generate_outfit\", \"edit_outfit\", \"explain_outfit\", \"show_items\", \"stop\"];\n""",
    """const ACTIONS = [\"chat\", \"clarify\", \"generate_outfit\", \"edit_outfit\", \"explain_outfit\", \"show_items\", \"stop\"];\nconst CLARIFICATION_FIELDS = [null, \"currentLocationObservation\", \"destination\", \"eventLocation\", \"date\", \"timeWindow\", \"terrain.surface\", \"terrain.difficulty\", \"terrain.condition\"];\n""",
)
replace_once(
    "functions/stylist/v2/openai_stylist_model_port_v2.js",
    """    clarificationField: {type: [\"string\", \"null\"]},\n""",
    """    clarificationField: {type: [\"string\", \"null\"], enum: CLARIFICATION_FIELDS},\n""",
)
# second occurrence in FINAL_SCHEMA
replace_once(
    "functions/stylist/v2/openai_stylist_model_port_v2.js",
    """    clarificationField: {type: [\"string\", \"null\"]},\n""",
    """    clarificationField: {type: [\"string\", \"null\"], enum: CLARIFICATION_FIELDS},\n""",
)
replace_once(
    "functions/stylist/v2/openai_stylist_model_port_v2.js",
    """function compactWardrobeItemForModelV2(raw) {\n  const item = raw && typeof raw === \"object\" && !Array.isArray(raw) ? raw : {};\n  const {\n    productImageUrl, cutoutImageUrl, cleanImageUrl, imageUrl, originalImageUrl,\n    storagePath, cleanStoragePath, productStoragePath, processing,\n    ...semantic\n  } = item;\n  return semantic;\n}\n\nfunction compactWardrobeForModelV2(items) {\n  return (Array.isArray(items) ? items : []).map(compactWardrobeItemForModelV2);\n}\n\nfunction shoppingQuickReplyPromptV2(needLabel, canonicalNeed) {\n  const normalized = normalizeIntentTextV2(`${needLabel || \"\"} ${canonicalNeed || \"\"}`);\n  if (/\\b(hiking|trekking|turist)/.test(normalized)) {\n    return \"Chceš, aby som ti pozrel vhodné topánky v obchodoch?\";\n  }\n  if (/\\b(shoe|shoes|boot|boots|sneaker|footwear|topank|obuv)/.test(normalized)) {\n    return \"Chceš, aby som ti pozrel vhodné topánky v obchodoch?\";\n  }\n  return \"Chceš, aby som ti pozrel možnosti v obchodoch?\";\n}\n""",
    """function compactWardrobeItemForModelV2(raw) {\n  const item = raw && typeof raw === \"object\" && !Array.isArray(raw) ? raw : {};\n  const profile = item.colorProfile && typeof item.colorProfile === \"object\" ? item.colorProfile : {};\n  const primaryColor = clean(item.primaryColor || profile?.primary?.family || profile?.primary?.name, 80) || null;\n  const secondaryColor = clean(item.secondaryColor || profile?.secondary?.family || profile?.secondary?.name, 80) || null;\n  const accentColors = list(item.accentColors || (Array.isArray(profile?.accents) ? profile.accents.map((entry) => entry?.family || entry?.name) : []), 4);\n  const out = {\n    id: clean(item.id, 180),\n    name: clean(item.name, 160) || null,\n    category: clean(item.category, 80) || null,\n    subCategory: clean(item.subCategory, 80) || null,\n    mainGroup: clean(item.mainGroup, 80) || null,\n    canonicalType: clean(item.canonicalType, 100) || null,\n    canonicalFamily: clean(item.canonicalFamily, 100) || null,\n    bodySlots: list(item.bodySlots, 8),\n    layerPosition: clean(item.layerPosition, 80) || null,\n    colors: list(item.colors, 6),\n    primaryColor,\n    secondaryColor,\n    accentColors,\n    warmth: Number.isFinite(Number(item.warmth)) ? Number(item.warmth) : null,\n    formality: Number.isFinite(Number(item.formality)) ? Number(item.formality) : null,\n    outfitFunctions: list(item.outfitFunctions, 8),\n    occasionFit: list(item.occasionFit, 8),\n    seasons: list(item.seasons, 6),\n    accessoryGroup: clean(item.accessoryGroup, 80) || null,\n    safety: item.safety && typeof item.safety === \"object\" ? item.safety : null,\n  };\n  return Object.fromEntries(Object.entries(out).filter(([, value]) => value != null && !(Array.isArray(value) && value.length === 0)));\n}\n\nfunction compactWardrobeForModelV2(items) {\n  return (Array.isArray(items) ? items : []).map(compactWardrobeItemForModelV2).filter((item) => item.id);\n}\n\nfunction compactLocationForModelV2(value) {\n  if (!value || typeof value !== \"object\") return value ?? null;\n  return Object.fromEntries(Object.entries({\n    providerId: clean(value.providerId, 180) || null,\n    label: clean(value.label, 240) || null,\n    source: clean(value.source, 80) || null,\n    granularity: clean(value.granularity, 40) || null,\n    countryCode: clean(value.countryCode, 12) || null,\n  }).filter(([, item]) => item != null));\n}\n\nfunction compactWeatherForModelV2(value) {\n  if (!value || typeof value !== \"object\") return value ?? null;\n  const snapshot = value.snapshot && typeof value.snapshot === \"object\" ? value.snapshot : {};\n  return {\n    locationProviderId: clean(value.locationProviderId, 180) || null,\n    dateKey: clean(value.dateKey, 20) || null,\n    timeWindowKey: clean(value.timeWindowKey, 40) || null,\n    source: clean(value.source, 60) || null,\n    snapshot: Object.fromEntries(Object.entries({\n      representativeTempC: snapshot.representativeTempC ?? null,\n      minTempC: snapshot.minTempC ?? null,\n      maxTempC: snapshot.maxTempC ?? null,\n      willRain: snapshot.willRain ?? null,\n      willSnow: snapshot.willSnow ?? null,\n      isWindy: snapshot.isWindy ?? null,\n      maxWindKph: snapshot.maxWindKph ?? null,\n      precipitationProbabilityMax: snapshot.precipitationProbabilityMax ?? null,\n    }).filter(([, item]) => item != null)),\n  };\n}\n\nfunction compactContextForModelV2(context) {\n  const source = context && typeof context === \"object\" ? context : {};\n  return {\n    currentLocationObservation: compactLocationForModelV2(source.currentLocationObservation),\n    destination: compactLocationForModelV2(source.destination),\n    eventLocation: compactLocationForModelV2(source.eventLocation),\n    date: source.date || null,\n    timeWindow: source.timeWindow || null,\n    activity: source.activity || null,\n    environment: source.environment ?? null,\n    terrain: source.terrain || {surface: null, difficulty: null, condition: null},\n    weather: compactWeatherForModelV2(source.weather),\n    groundingRequirements: source.groundingRequirements || {weatherRequired: false, weatherLocationField: null, terrainRequiredFields: []},\n  };\n}\n\nfunction compactSessionForModelV2(session, phase) {\n  const source = session && typeof session === \"object\" ? session : {};\n  const memory = source.conversationMemory && typeof source.conversationMemory === \"object\" ? source.conversationMemory : {};\n  const compact = {\n    schemaVersion: source.schemaVersion || 2,\n    revision: source.revision || 0,\n    context: compactContextForModelV2(source.context),\n    currentOutfit: {\n      itemIds: list(source.currentOutfit?.itemIds, 12),\n      selectionReasonsByItemId: source.currentOutfit?.selectionReasonsByItemId || {},\n      compromises: list(source.currentOutfit?.compromises, 12),\n      missingWardrobeNeeds: list(source.currentOutfit?.missingWardrobeNeeds, 12),\n    },\n    conversationMemory: {\n      pendingQuestion: memory.pendingQuestion || null,\n      pendingAction: memory.pendingAction || null,\n      answeredClarificationFields: memory.answeredClarificationFields || {},\n      communicatedWarnings: list(memory.communicatedWarnings, 12),\n      userCorrections: list(memory.userCorrections, 12),\n      acceptedCompromises: list(memory.acceptedCompromises, 12),\n    },\n    shopping: source.shopping || null,\n  };\n  if (phase === \"plan\") {\n    compact.scenarioMemory = {\n      activeScenarioId: source.scenarioMemory?.activeScenarioId || null,\n      snapshots: (source.scenarioMemory?.snapshots || []).slice(-8).map((snapshot) => ({\n        id: snapshot.id,\n        label: clean(snapshot.label, 180) || null,\n        referenceSignals: list(snapshot.referenceSignals, 12),\n        context: compactContextForModelV2(snapshot.context),\n        outfit: {\n          itemIds: list(snapshot.outfit?.itemIds, 12),\n          selectionReasonsByItemId: snapshot.outfit?.selectionReasonsByItemId || {},\n        },\n      })),\n    };\n  }\n  return compact;\n}\n\nfunction shoppingQuickReplyPromptV2(needLabel, canonicalNeed) {\n  const normalized = normalizeIntentTextV2(`${needLabel || \"\"} ${canonicalNeed || \"\"}`);\n  const footwear = /\\b(shoe|shoes|boot|boots|sneaker|footwear|topank|obuv)\\w*/.test(normalized);\n  const bottoms = /\\b(pant|pants|trouser|trousers|nohav|rifl|bottom|spodn)\\w*/.test(normalized);\n  if (footwear && bottoms) {\n    return \"Chceš, aby som ti pozrel vhodné turistické nohavice a topánky v obchodoch?\";\n  }\n  if (/\\b(hiking|trekking|turist)/.test(normalized) || footwear) {\n    return \"Chceš, aby som ti pozrel vhodné topánky v obchodoch?\";\n  }\n  return \"Chceš, aby som ti pozrel možnosti v obchodoch?\";\n}\n""",
)
replace_once(
    "functions/stylist/v2/openai_stylist_model_port_v2.js",
    """    \"Ak vhodný ideálny kus chýba, vyber najlepší prijateľný kus zo šatníka, vysvetli limit a offerShopping=true, ak by doplnenie šatníka bolo užitočné. Pri offerShopping vždy vyplň shoppingNeedLabel a shoppingNeedCanonicalType, ak ho poznáš.\",\n    \"Text píš ako 2 až 4 krátke, úplné a gramaticky prirodzené vety s normálnou interpunkciou. Nepíš surový inline zoznam oddelený pomlčkami; karty pod správou už zobrazia jednotlivé kúsky.\",\n    \"Najprv jednou vetou zhrň podmienky, potom jednou až dvoma vetami vysvetli kombináciu a prípadný kompromis. Neopakuj názov každého kúsku, ak to nepridáva užitočné vysvetlenie.\",\n""",
    """    \"Ak vhodný ideálny kus chýba, stále dokonči najlepší outfit z dostupného šatníka. Slabší kus otvorene označ ako kompromis, stručne povedz prečo a offerShopping=true, ak by doplnenie šatníka pomohlo.\",\n    \"Pri bežnej túre bez explicitného safety red flagu: ak chýbajú turistické nohavice, vyber najpraktickejšie dostupné rifle/nohavice; ak chýba turistická obuv, vyber najpraktickejšie dostupné tenisky. Obe voľby vysvetli ako kompromis, nie ako ideál. Ak chýbajú obe kategórie, shoppingNeedLabel nastav na 'turistické nohavice a turistická obuv'.\",\n    \"Text píš ako 2 až 4 krátke, úplné a prirodzené vety. Začni konkrétnym odporúčaním, nie interným reportom o tom, čo nepoznáš. Nezačínaj formuláciami typu 'Keďže miesto/terén/počasie nie sú známe' ani nevypisuj metadata; chýbajúci kontext spomeň iba ak mení praktickú radu.\",\n    \"Karty pod správou ukážu jednotlivé kúsky, preto ich nevypisuj mechanicky. Pomenuj však konkrétny kompromis (napr. rifle alebo tenisky), keď je to pre používateľa užitočné.\",\n""",
)
replace_once(
    "functions/stylist/v2/openai_stylist_model_port_v2.js",
    """        session: input.session,\n""",
    """        session: compactSessionForModelV2(input.session, phase),\n""",
)
replace_once(
    "functions/stylist/v2/openai_stylist_model_port_v2.js",
    """          maxOutputTokens: phase === \"plan\" ? 1200 : 1400,\n""",
    """          maxOutputTokens: phase === \"plan\" ? 850 : 1150,\n""",
)
replace_once(
    "functions/stylist/v2/openai_stylist_model_port_v2.js",
    """  compactWardrobeForModelV2,\n""",
    """  compactSessionForModelV2,\n  compactWardrobeForModelV2,\n""",
)

# ---------------------------------------------------------------------------
# Tests: reproduce live conversation with ZERO planner calls, enforce lean model
# payload, local acknowledgement, engine read reduction, and combined CTA.
# ---------------------------------------------------------------------------
replace_once(
    "functions/stylist/v2/stylist_help_first_torture_v2.test.js",
    """    modelResults: [\n      toolEnvelope([\n        {tool: \"location\", query: \"Rakúska\", targetField: \"destination\"},\n      ], {\n        context: {\n          activity: {id: \"hiking\", label: \"túra\", source: \"user\"},\n          date: {dateKey: \"2026-09-11\", source: \"user\"},\n          timeWindow: {key: \"day\", label: \"cez deň\", source: \"help_first_default\"},\n          // Simulate the exact over-eager planner behavior that caused the bug.\n          groundingRequirements: {\n            weatherRequired: true,\n            weatherLocationField: \"destination\",\n            terrainRequiredFields: [\"surface\"],\n          },\n        },\n      }),\n      hikingOutfitEnvelope(),\n    ],\n""",
    """    // The common remote-outfit grammar is deterministic: no planning model\n    // call is allowed before the one final stylist decision.\n    modelResults: [hikingOutfitEnvelope()],\n""",
)
replace_once(
    "functions/stylist/v2/stylist_help_first_torture_v2.test.js",
    """  assert.equal(h.ledger.calls(\"model\", \"plan\").length, 1);\n  assert.equal(h.ledger.calls(\"model\", \"final\").length, 1);\n""",
    """  assert.equal(h.ledger.calls(\"model\", \"plan\").length, 0);\n  assert.equal(h.ledger.calls(\"model\", \"final\").length, 1);\n""",
)
append_once(
    "functions/stylist/v2/stylist_model_payload_efficiency_v2.test.js",
    "model payload excludes durable replay history",
    r'''test("model payload excludes durable replay history and full weather arrays", async () => {
  let call;
  const input = baseInput();
  input.session.replay = {turns: Array.from({length: 30}, (_, i) => ({turnId: `old-${i}`, result: {assistantText: "old"}}))};
  input.session.wardrobePreferences = {retrievalCache: {huge: "x".repeat(5000)}};
  input.session.context.weather = {
    locationProviderId: "place:1", dateKey: "2026-09-11", timeWindowKey: "day", source: "open-meteo",
    snapshot: {temperatureC: Array(24).fill(12), weatherCode: Array(24).fill(1), representativeTempC: 12, minTempC: 8, maxTempC: 15, willRain: false},
  };
  const port = createOpenAiStylistModelPortV2({executeStructured: async (request) => { call = request; return validChatRaw(); }});
  await port.turn(input);
  const payload = JSON.parse(call.messages[1].content);
  assert.equal(Object.hasOwn(payload.session, "replay"), false);
  assert.equal(Object.hasOwn(payload.session, "wardrobePreferences"), false);
  assert.equal(Object.hasOwn(payload.session, "scenarioMemory"), false);
  assert.equal(Object.hasOwn(payload.session.context.weather.snapshot, "temperatureC"), false);
  assert.equal(payload.session.context.weather.snapshot.representativeTempC, 12);
});

test("wardrobe projection sent to model is semantic and intentionally lean", async () => {
  let call;
  const input = baseInput();
  input.toolResults.wardrobeItems[0].debugBlob = "x".repeat(2000);
  input.toolResults.wardrobeItems[0].colorProfile = {primary: {family: "blue", lab: [1, 2, 3]}, accents: [{family: "white", huge: "x".repeat(1000)}]};
  const port = createOpenAiStylistModelPortV2({executeStructured: async (request) => { call = request; return validChatRaw(); }});
  await port.turn(input);
  const item = JSON.parse(call.messages[1].content).toolResults.wardrobeItems[0];
  assert.equal(item.id, "shirt");
  assert.equal(item.primaryColor, "blue");
  assert.deepEqual(item.accentColors, ["white"]);
  assert.equal(Object.hasOwn(item, "colorProfile"), false);
  assert.equal(Object.hasOwn(item, "debugBlob"), false);
});

test("shopping CTA can offer both missing hiking pants and footwear", () => {
  assert.equal(
    shoppingQuickReplyPromptV2("turistické nohavice a turistická obuv", "hiking_pants_and_shoes"),
    "Chceš, aby som ti pozrel vhodné turistické nohavice a topánky v obchodoch?",
  );
});''',
)
append_once(
    "functions/stylist/v2/stylist_production_bridge_v2.test.js",
    "server local advice intro bypasses every AI/tool path",
    r'''test("server local advice intro bypasses every AI/tool path", async () => {
  const repository = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  const calls = {model: 0, fast: 0, wardrobe: 0, location: 0, weather: 0};
  const handler = createStylistChatV2Handler({
    db: {}, admin: {}, logger: {warn() {}, info() {}}, resolveOpenAISecret: async () => "unused", clock: () => NOW,
    sessionRepository: repository,
    fastChatFactory: () => { calls.fast += 1; throw new Error("fast_chat_must_not_be_created"); },
    modelFactory: () => { calls.model += 1; throw new Error("model_must_not_run"); },
    wardrobeToolFactory: () => { calls.wardrobe += 1; throw new Error("wardrobe_must_not_run"); },
    shoppingToolFactory: () => ({async search() { throw new Error("shopping_must_not_run"); }}),
    locationResolver: {async resolve() { calls.location += 1; throw new Error("location_must_not_run"); }},
    weatherTool: {async getForecast() { calls.weather += 1; throw new Error("weather_must_not_run"); }},
  });

  const response = await handler({
    v2SessionId: "local_intro", turnId: "intro_1", message: "ahoj divočák potrebujem poradiť",
    history: [], currentOutfitItemIds: [], currentSelectionReasons: [], shoppingEnabled: false, clientContext: {},
  }, {auth: {uid: "user-local"}});

  assert.equal(response.ok, true);
  assert.equal(response.modelPath, "stylist_v2_local_chat");
  assert.equal(response.reply, "Ahoj! Jasné 🙂 S čím ti môžem pomôcť?");
  assert.deepEqual(calls, {model: 0, fast: 0, wardrobe: 0, location: 0, weather: 0});
});''',
)
append_once(
    "functions/stylist/v2/stylist_turn_engine_v2.test.js",
    "known canonical state removes redundant normal-turn repository reads",
    r'''test("known canonical state removes redundant normal-turn repository reads", async () => {
  const base = createMemoryStylistSessionRepositoryV2({now: () => NOW});
  await base.ensure({uid: "user-a", chatId: "chat-known"});
  const existing = await base.get({uid: "user-a", chatId: "chat-known"});
  const calls = {ensure: 0, ensureFromLegacy: 0, get: 0, commitTurn: 0};
  const repository = {
    async ensure(args) { calls.ensure += 1; return base.ensure(args); },
    async ensureFromLegacy(args) { calls.ensureFromLegacy += 1; return base.ensureFromLegacy(args); },
    async get(args) { calls.get += 1; return base.get(args); },
    async commitTurn(args) { calls.commitTurn += 1; return base.commitTurn(args); },
  };
  const h = harness({repository, modelResults: [finalChat("Rifle sú v poriadku.")]});
  const result = await h.engine.resolveTurn({
    uid: "user-a",
    request: request("chat-known", "known-1", 0, "A rifle sú v poriadku?"),
    knownCanonicalState: existing.state,
  });
  assert.equal(result.action, "chat");
  assert.equal(calls.ensure, 0);
  assert.equal(calls.ensureFromLegacy, 0);
  assert.equal(calls.get, 0);
  assert.equal(calls.commitTurn, 1);
});''',
)

print("Stylist V2 conversation fastlane patch applied")
