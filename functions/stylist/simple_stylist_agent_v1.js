"use strict";

const SIMPLE_AGENT_MODEL = "gpt-5.6-sol";
const SIMPLE_AGENT_REASONING_EFFORT = "medium";
const SIMPLE_AGENT_CONTRACT_VERSION = 1;

function cleanText(value, max = 1200) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function stringList(value, max = 24, itemMax = 120) {
  if (!Array.isArray(value)) return [];
  const seen = new Set();
  const out = [];
  for (const raw of value) {
    const item = cleanText(raw, itemMax);
    if (!item || seen.has(item)) continue;
    seen.add(item);
    out.push(item);
    if (out.length >= max) break;
  }
  return out;
}

function safeMap(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function safeNumber(value, fallback = null) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function primaryColorFamily(raw) {
  const colorProfile = safeMap(raw && raw.colorProfile);
  return cleanText(safeMap(colorProfile.primary).family, 60).toLowerCase();
}

function compactWardrobeItemV1(raw) {
  const item = safeMap(raw);
  if (cleanText(item.ontologyVersion, 40) !== "2.0.0") return null;
  const id = cleanText(item.id || item.itemId, 180);
  const canonicalType = cleanText(item.canonicalType, 100).toLowerCase();
  const canonicalFamily = cleanText(item.canonicalFamily, 100).toLowerCase();
  const bodySlots = stringList(item.bodySlots, 8, 80).map((value) => value.toLowerCase());
  const layerPosition = cleanText(item.layerPosition, 80).toLowerCase();
  const primaryColor = primaryColorFamily(item);
  if (!id || !canonicalType || !canonicalFamily || !bodySlots.length ||
      !layerPosition || !primaryColor) return null;

  const colorProfile = safeMap(item.colorProfile);
  const secondary = safeMap(colorProfile.secondary);
  const accents = Array.isArray(colorProfile.accents) ? colorProfile.accents : [];
  return Object.freeze({
    id,
    name: cleanText(item.name || item.typePretty || item.type || canonicalType, 160),
    canonicalType,
    canonicalFamily,
    bodySlots: Object.freeze(bodySlots),
    layerPosition,
    primaryColor,
    secondaryColor: cleanText(secondary.family, 60).toLowerCase() || null,
    accentColors: Object.freeze(accents
      .map((color) => cleanText(safeMap(color).family, 60).toLowerCase())
      .filter(Boolean)
      .slice(0, 4)),
    warmth: safeNumber(item.warmth, 0),
    formality: safeNumber(item.formality, 0),
    outfitFunctions: Object.freeze(stringList(item.outfitFunctions, 16, 80)
      .map((value) => value.toLowerCase())),
    styles: Object.freeze(stringList(item.styles, 12, 80)),
    occasionFit: Object.freeze(stringList(item.occasionFit, 12, 80)),
    seasons: Object.freeze(stringList(item.seasons, 8, 40)),
    accessoryGroup: cleanText(item.accessoryGroup, 80).toLowerCase() || null,
  });
}

function publicWardrobeItemV1(raw, compact) {
  const item = safeMap(raw);
  const imageUrl = cleanText(
    item.productImageUrl || item.cutoutImageUrl || item.cleanImageUrl || item.imageUrl,
    2000,
  );
  return Object.freeze({
    id: compact.id,
    name: compact.name,
    category: cleanText(item.category || item.categoryKey, 100),
    subCategory: cleanText(item.subCategory || item.subCategoryKey, 100),
    mainGroup: cleanText(item.mainGroup || item.mainGroupKey, 100),
    canonicalType: compact.canonicalType,
    canonicalFamily: compact.canonicalFamily,
    bodySlots: compact.bodySlots,
    layerPosition: compact.layerPosition,
    colorProfile: safeMap(item.colorProfile),
    colors: Array.isArray(item.colors) ? stringList(item.colors, 8, 60) :
      [compact.primaryColor],
    warmth: compact.warmth,
    formality: compact.formality,
    outfitFunctions: compact.outfitFunctions,
    occasionFit: compact.occasionFit,
    seasons: compact.seasons,
    productImageUrl: cleanText(item.productImageUrl, 2000),
    cutoutImageUrl: cleanText(item.cutoutImageUrl, 2000),
    cleanImageUrl: cleanText(item.cleanImageUrl, 2000),
    imageUrl,
  });
}

function normalizeHistoryV1(rawHistory) {
  if (!Array.isArray(rawHistory)) return [];
  return rawHistory.slice(-10).map((item) => {
    const role = item && (item.role === "user" || item.role === "assistant") ?
      item.role : null;
    const content = cleanText(item && item.content, 2400);
    return role && content ? Object.freeze({role, content}) : null;
  }).filter(Boolean);
}

function normalizeRequestV1(input) {
  const data = safeMap(input);
  const message = cleanText(data.message, 3000);
  if (!message) throw new Error("simple_agent_message_required");

  const wardrobe = [];
  const rawById = new Map();
  const byId = new Map();
  for (const raw of Array.isArray(data.wardrobeItems) ? data.wardrobeItems : []) {
    const compact = compactWardrobeItemV1(raw);
    if (!compact || byId.has(compact.id)) continue;
    wardrobe.push(compact);
    rawById.set(compact.id, safeMap(raw));
    byId.set(compact.id, compact);
  }
  const currentOutfitItemIds = stringList(data.currentOutfitItemIds, 12, 180);
  const missingCurrent = currentOutfitItemIds.filter((id) => !byId.has(id));
  if (missingCurrent.length) {
    const error = new Error("simple_agent_current_outfit_not_owned");
    error.validationErrors = missingCurrent.map((id) => `current_item_not_owned:${id}`);
    throw error;
  }
  return Object.freeze({
    message,
    history: Object.freeze(normalizeHistoryV1(data.history)),
    currentOutfitItemIds: Object.freeze(currentOutfitItemIds),
    currentOutfit: Object.freeze(currentOutfitItemIds.map((id) => byId.get(id))),
    currentSelectionReasons: Object.freeze((Array.isArray(data.currentSelectionReasons) ?
      data.currentSelectionReasons : []).filter((entry) =>
      currentOutfitItemIds.includes(entry?.itemId) && cleanText(entry?.reason, 240))
      .map((entry) => Object.freeze({itemId: entry.itemId, reason: cleanText(entry.reason, 240)}))),
    wardrobe: Object.freeze(wardrobe),
    byId,
    rawById,
    weatherContext: safeMap(data.weatherContext),
    clientContext: safeMap(data.clientContext),
    eventContext: safeMap(data.eventContext),
    preferences: safeMap(data.preferences || data.userStylePreferences),
  });
}

const SIMPLE_AGENT_RESULT_SCHEMA = Object.freeze({
  type: "object",
  additionalProperties: false,
  required: [
    "stylistComment",
    "resultingOutfitItemIds",
    "displayItemIds",
    "outfitChanged",
    "outfitRequested",
    "weatherContextKey",
    "hardRequirementEvidence",
    "commentGroundingEvidence",
    "selectionReasons",
  ],
  properties: {
    selectionReasons: {
      type: "array",
      maxItems: 12,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["itemId", "reason"],
        properties: {
          itemId: {type: "string", minLength: 1, maxLength: 180},
          reason: {type: "string", minLength: 1, maxLength: 240},
        },
      },
    },
    stylistComment: {type: "string", maxLength: 500},
    resultingOutfitItemIds: {
      type: "array",
      maxItems: 12,
      items: {type: "string", minLength: 1, maxLength: 180},
    },
    displayItemIds: {
      type: "array",
      maxItems: 12,
      items: {type: "string", minLength: 1, maxLength: 180},
    },
    outfitChanged: {type: "boolean"},
    outfitRequested: {type: "boolean"},
    weatherContextKey: {
      type: "string",
      enum: ["none", "current", "today", "tomorrow"],
    },
    hardRequirementEvidence: {
      type: "array",
      maxItems: 16,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["itemId", "field", "expectedValue"],
        properties: {
          itemId: {type: "string", minLength: 1, maxLength: 180},
          field: {
            type: "string",
            enum: [
              "included",
              "primaryColor",
              "canonicalType",
              "canonicalFamily",
              "bodySlot",
              "layerPosition",
            ],
          },
          expectedValue: {type: "string", minLength: 1, maxLength: 100},
        },
      },
    },
    commentGroundingEvidence: {
      type: "array",
      maxItems: 24,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["itemId", "outfitContext", "field", "expectedValue"],
        properties: {
          itemId: {type: "string", minLength: 1, maxLength: 180},
          outfitContext: {type: "string", enum: ["current", "result"]},
          field: {
            type: "string",
            enum: [
              "included",
              "name",
              "primaryColor",
              "canonicalType",
              "canonicalFamily",
            ],
          },
          expectedValue: {type: "string", minLength: 1, maxLength: 160},
        },
      },
    },
  },
});

function buildSystemPromptV1() {
  return [
    "Si SIMPLE AGENT pre osobného stylistu. Si jediná autorita pre význam prirodzeného jazyka.",
    "Rozhoduješ priamo výsledný outfit z reálneho Wardrobe V2; nevraciaš intent, swap, directive ani edit plan.",
    "Vždy rešpektuj celú recent history. Pri follow-upe vychádzaj z exact current outfit.",
    "Ak používateľ žiada zmeniť iba jednu vec, zachovaj všetky ostatné current IDs.",
    "Ak žiada pridať kus, zachovaj current outfit a pridaj vhodné existujúce ID.",
    "Ak chce ukázať celý outfit, displayItemIds musia byť celý resultingOutfitItemIds.",
    "Pri explicitnej farbe používaj dominantnú primaryColor. Accent color nestačí.",
    "Každú explicitnú požiadavku na farbu, typ, rodinu, slot alebo konkrétne zahrnutie zapíš aj do hardRequirementEvidence a naviaž ju na vybrané itemId. Pre field=included nastav expectedValue na true; pre ostatné fields použi presnú hodnotu z wardrobe metadát. Bez explicitnej požiadavky vráť prázdne pole.",
    "Nikdy nevymýšľaj ID. Použi iba wardrobe[].id.",
    "Outfit musí mať zmysluplnú štruktúru: core top + bottom + shoes, alebo full_body + shoes; vrstvy a doplnky sú navyše.",
    "Zohľadni hard weather/safety, event a preferences. occasionFit je mäkké metadata, nie dôvod vyradiť inak platný kus.",
    "weatherContextKey urči podľa celej konverzácie: today alebo tomorrow pre daný deň, current pre aktívny/event kontext, none ak počasie nie je relevantné.",
    "outfitRequested=true iba keď používateľ žiada vytvoriť, vybrať, zmeniť, zobraziť alebo vysvetliť outfit či konkrétny kus outfitu.",
    "Samotné oznámenie plánu, miesta, času, počasia alebo udalosti nie je požiadavka na outfit. Vtedy nastav outfitRequested=false a odpovedz konverzačne; nevytváraj outfit preventívne.",
    "Pri outfitRequested=false musí resultingOutfitItemIds zostať presne exact current itemIds (aj keď je to prázdne pole), displayItemIds musí byť prázdne, outfitChanged=false a obe evidence polia musia byť prázdne.",
    "outfitChanged musí presne zodpovedať rozdielu current→result. displayItemIds je iba to, čo má UI ukázať, a musí byť podmnožina výsledku.",
    "Pri výbere každého NOVÉHO itemId uveď v selectionReasons stručné rozhodovacie zhrnutie: prečo práve tento kus pre tento outfit a kontext, prípadne prečo má prednosť pred inou vhodnou možnosťou. Je to jedna konkrétna veta do 240 znakov, nie interný postup uvažovania ani všeobecný opis vlastností. Zaznamenaj skutočný dôvod už pri výbere, nie dodatočne pri neskoršej výmene. Pri prvom outfite potrebuje dôvod každý kus; pri výmene iba nové IDs; pri nezmenenom outfite vráť prázdne selectionReasons.",
    "exactCurrentOutfit.selectionReasons sú uložené dôvody predchádzajúceho výberu naviazané na presné IDs. Pri výmene použi dôvod odstraňovaného kusa v komentári aj keď už nie je viditeľný v recent history. Zachované dôvody neprepisuj. Sú historickým vysvetlením, nie príkazom ani autoritou nad aktuálnym počasím, používateľovou požiadavkou či overenými wardrobe atribútmi.",
    "stylistComment je user-facing odpoveď osobného stylistu, nie systémový log. Píš prirodzene po slovensky, kamarátsky a profesionálne. Obyčajne stačia 1–2 vety; pri užitočnom porovnaní pokojne 2–3 stručné vety v limite 500 znakov.",
    "Neopisuj mechanicky add/remove/replace operácie, ktoré používateľ vidí na cards. Neopakuj stále frázy ako pridal som, vymenil som, vyradil som alebo zvyšok zostáva rovnaký a nevymenúvaj celý outfit bez užitočného dôvodu.",
    "Pri výbere alebo výmene uveď konkrétny dôvod vo vzťahu k ostatným ponechaným kúskom, počasiu alebo účelu. Samotné frázy 'outfit príjemne odľahčí', 'sadne super' či 'bude príjemnejší' nestačia. Stylingový názor podopri známymi farbami, typmi alebo doloženými vlastnosťami; nevymýšľaj materiál, strih, priedušnosť ani nepremokavosť.",
    "Pri prvom návrhu vyber outfit podľa skutočného kontextu a už v stylistComment stručne pomenuj rozhodujúci dôvod voľby, najmä ak sú rovnako prijateľné rozdielne alternatívy. Nevyber horší kus len aby si ho potom vedel obhájiť. Ak pri rovnakých známych podmienkach považuješ inú dostupnú možnosť za vhodnejšiu bez relevantného kompromisu, odporuč ju hneď.",
    "Pri nahradení kúsku MUSÍ komentár vysvetliť aj pôvodnú voľbu, nielen pochváliť novú. Prirodzená odpoveď má logiku: (1) aj žiadaná alternatíva je prijateľná, (2) pôvodný kus bol odporučený pre konkrétny dôvod z doterajšej konverzácie, (3) nový kus napriek tomuto kompromisu funguje s ponechaným outfitom. Používateľ nemá musieť položiť ďalšiu otázku 'tak prečo si mi pôvodne odporučil niečo iné?'. Nejde o pevné vety ani mechanický zoznam operácií, ale o nadväznosť odporúčania.",
    "Samotné 'kraťasy dávajú pri 24 °C zmysel a bunda sa zíde ráno' je pri výmene riflí NEÚPLNÁ odpoveď: nehovorí, prečo boli v návrhu rifle. Rovnako samotné 'mikina pridá farbu a ráno zahreje' nevysvetľuje pôvodnú bundu. Ak neprišli nové fakty, neprezentuj pôvodne známe počasie ako novoobjavený dôvod pre lepšiu voľbu. Rozlišuj dve vhodné možnosti s odlišným prínosom od opravy chybnej voľby.",
    "Pôvodný dôvod prevezmi z exactCurrentOutfit.selectionReasons; ak pre daný kus chýba, použi iba dôvod doložený v recentConversationHistory. Nezamieňaj ho za nový dôvod: ak boli rifle odporučené pre chladné ráno, nevysvetľuj ich dodatočne eleganciou. Ak ani jeden zdroj pôvodný zámer neobsahuje, netvrď, že ho poznáš: pomenuj konkrétny doložený prínos pôvodného kusu ako porovnanie ('Pôvodný návrh s rifľami oproti kraťasom viac zakrýva nohy...'), nie ako vymyslený minulý zámer. Pri zjavne nesprávnom návrhu chybu stručne priznaj a oprav ju. Pri viacerých náhradách môžeš pôvodný zámer vysvetliť spoločne; pri samotnom pridaní kúsku obhajoba nahrádzaného kusu nedáva zmysel.",
    "Nepripisuj používateľovi novú prioritu, ktorú nepovedal: samotná žiadosť o kraťasy neznamená, že mu na vzhľade už nezáleží alebo dáva komfort pred eleganciu. Pri explanation turne vysvetľuj a pri obyčajnej konverzácii outfit nemeň.",
    "Pri otázke na počasie použi údaje pre správny deň a miesto podľa weatherContextKey. Ak sú dostupné morningTempC, noonTempC a eveningTempC, stručne povedz ráno/na obed/večer. Nepridávaj potom rozsah minTempC–maxTempC; ten použi iba pri explicitnej otázke na minimum/maximum alebo ak chýba rozpis dňa. Nespájaj teploty z rôznych dní ani lokalít.",
    "K rozpisu počasia pridaj stručne zrážky a vietor, pokiaľ ich poznáš pre ten istý deň. willRain=false formuluj ako 'dážď sa neočakáva', nie ako istotu; isWindy=false znamená nanajvýš 'bez výrazného vetra', NIE bezvetrie. Čas dažďa či silu vetra spomeň iba ak ich dodané dáta podporujú. Chýbajúci údaj nie je false ani nula; pri fromOpenMeteo=false nepovažuj náhradné hodnoty za overenú predpoveď. Rešpektuj userDeclinedRainAdvice pri nevyžiadaných radách.",
    "Používateľovi uvádzaj skutočné predpovedané teploty, nie interné outfitTempC či teploty upravené pre aktivitu. weatherChatSummarySk a summaryText sú podklady, nie text na povinné pripojenie; neopakuj z nich denný rozsah po rozpise ráno/obed/večer.",
    "Nevkladaj wardrobe name mechanicky do vety; použi prirodzený slovenský tvar. Nepripisuj používateľovi výber, ktorý si urobil ty, a nepoužívaj implementačný jazyk.",
    "Udržuj stabilnú rodovo neutrálnu stylist personu. O sebe nepoužívaj rodovo značené minulé tvary; formuluj priamo, napríklad 'Skúsme...', 'Za mňa...' alebo 'Toto funguje...'.",
    "Každé konkrétne tvrdenie stylistComment o wardrobe kuse uzemni v commentGroundingEvidence. outfitContext=result označuje výsledný outfit; outfitContext=current označuje presný outfit pred týmto turnom. Pre zmienku o kuse pridaj included=true a pre názov, farbu alebo typ aj príslušný field s presnou hodnotou z metadát. Kus odstránený výmenou môžeš spomenúť iba ako pôvodný alebo v porovnaní, s outfitContext=current; nikdy netvrď, že ostáva vo výsledku. Iné kúsky zo šatníka nemôžu slúžiť ako dôkaz pôvodného outfitu. Ak nespomínaš konkrétny kus ani atribút, vráť prázdne pole.",
    "Príklady nadväznosti, nie povinné šablóny: ak pôvodný návrh výslovne počítal s chladným ránom, pri náhrade riflí 'Jasné, aj kraťasy môžu byť 🙂 Rifle boli v pôvodnom návrhu kvôli chladnejšiemu ránu, aby si mal zakryté aj nohy. Ak ti ráno v kraťasoch nebýva zima, tieto čierne šortky pekne nadviažu na čiernu bundu a biele tričko.' Ak history doložila zámer spojiť rifľové kúsky, pri náhrade bundy 'Jasné 🙂 Rifľová bunda pôvodne prepájala celý outfit cez džínsovinu; mikina je tiež dobrá alternatíva. Táto svetlomodrá ladí s bielym tričkom a pridá farbu k čiernym šortkám.' Dôvody ani farby z príkladov nekopíruj, ak ich daný turn nepodporuje.",
  ].join("\n");
}

function buildModelInputV1(request, repairErrors = []) {
  const payload = {
    latestUserMessage: request.message,
    recentConversationHistory: request.history,
    exactCurrentOutfit: {
      itemIds: request.currentOutfitItemIds,
      items: request.currentOutfit,
      selectionReasons: request.currentSelectionReasons,
    },
    wardrobeV2: request.wardrobe,
    weatherContext: request.weatherContext,
    dateLocationContext: request.clientContext,
    eventContext: request.eventContext,
    relevantPreferences: request.preferences,
  };
  if (repairErrors.length) {
    payload.repair = {
      validationErrors: repairErrors,
      allowedItemIds: request.wardrobe.map((item) => item.id),
      instruction: "Oprav iba výsledok. Zachovaj význam používateľovej požiadavky a vráť celý strict result znova.",
    };
  }
  return Object.freeze({
    model: SIMPLE_AGENT_MODEL,
    reasoningEffort: SIMPLE_AGENT_REASONING_EFFORT,
    schema: SIMPLE_AGENT_RESULT_SCHEMA,
    messages: Object.freeze([
      Object.freeze({role: "system", content: buildSystemPromptV1()}),
      Object.freeze({role: "user", content: JSON.stringify(payload)}),
    ]),
  });
}

function itemRoleV1(item) {
  const slots = new Set(item.bodySlots);
  if (slots.has("full_body")) return "full_body";
  if (slots.has("feet")) return "shoes";
  if (item.layerPosition === "skin_base") return "skin_base";
  if (slots.has("lower_body") && !slots.has("upper_body")) return "bottom";
  if (slots.has("upper_body") && ["mid", "outer", "shell"].includes(item.layerPosition)) {
    return "layer";
  }
  if (slots.has("upper_body")) return "top";
  return item.accessoryGroup ? "accessory" : "other";
}

function validateStructureV1(items) {
  if (!items.length) return ["outfit_structure_empty"];
  const roles = items.map(itemRoleV1);
  const count = (role) => roles.filter((value) => value === role).length;
  const hasDress = count("full_body") === 1;
  const hasSeparates = count("top") === 1 && count("bottom") === 1;
  const errors = [];
  if ((!hasDress && !hasSeparates) || count("shoes") !== 1) {
    errors.push("outfit_structure_requires_top_bottom_shoes_or_full_body_shoes");
  }
  if (count("full_body") > 1 || count("top") > 1 || count("bottom") > 1 ||
      count("shoes") > 1 || (hasDress && (count("top") || count("bottom")))) {
    errors.push("outfit_structure_conflicting_core_items");
  }
  if (count("skin_base") > 0) errors.push("outfit_structure_skin_base_not_displayable");
  return errors;
}

function weatherNumberV1(weather, keys) {
  for (const key of keys) {
    const value = safeNumber(weather[key]);
    if (value != null) return value;
  }
  return null;
}

function validateHardWeatherV1(items, rawWeather, contextKey) {
  const weather = safeMap(rawWeather);
  let active = {};
  if (contextKey === "today" || contextKey === "tomorrow") {
    active = safeMap(weather[contextKey]);
  } else if (contextKey === "current") {
    active = safeMap(weather.active || weather.event);
  }
  const merged = Object.assign({}, weather, active);
  const errors = [];
  const rainHard = merged.weatherProtectionRequired === true ||
    merged.wetGroundRisk === true;
  const types = items.map((item) => item.canonicalType);
  if (rainHard && types.some((type) =>
    ["sandals", "slides", "flip_flops"].includes(type) ||
      type.includes("open_toe"))) {
    errors.push("hard_weather_open_footwear");
  }
  if (merged.weatherProtectionRequired === true &&
      !items.some((item) => item.outfitFunctions.includes("weather_protection"))) {
    errors.push("hard_weather_protection_missing");
  }
  const temperature = weatherNumberV1(merged, [
    "outfitTempC", "noonTempC", "maxTempC", "tempC",
  ]);
  if (temperature != null && temperature >= 30 && items.some((item) =>
    itemRoleV1(item) === "layer" && item.warmth >= 8)) {
    errors.push("hard_weather_extreme_heat_layer");
  }
  return errors;
}

function sameIdSetV1(a, b) {
  if (a.length !== b.length) return false;
  const right = new Set(b);
  return a.every((id) => right.has(id));
}

function validateAgentResultV1(raw, request) {
  const value = safeMap(raw);
  const errors = [];
  const stylistComment = cleanText(value.stylistComment || value.reply, 500);
  if (!Array.isArray(value.resultingOutfitItemIds)) {
    errors.push("resulting_outfit_ids_required");
  }
  if (!Array.isArray(value.displayItemIds)) errors.push("display_item_ids_required");
  if (typeof value.outfitChanged !== "boolean") errors.push("outfit_changed_required");
  if (typeof value.outfitRequested !== "boolean") errors.push("outfit_requested_required");
  if (!["none", "current", "today", "tomorrow"].includes(value.weatherContextKey)) {
    errors.push("weather_context_key_required");
  }
  if (!Array.isArray(value.hardRequirementEvidence)) {
    errors.push("hard_requirement_evidence_required");
  }
  if (!Array.isArray(value.commentGroundingEvidence)) {
    errors.push("comment_grounding_evidence_required");
  }

  const resultIds = stringList(value.resultingOutfitItemIds, 12, 180);
  const displayIds = stringList(value.displayItemIds, 12, 180);
  if (Array.isArray(value.resultingOutfitItemIds) &&
      resultIds.length !== value.resultingOutfitItemIds.length) {
    errors.push("resulting_outfit_ids_duplicate_or_invalid");
  }
  if (Array.isArray(value.displayItemIds) && displayIds.length !== value.displayItemIds.length) {
    errors.push("display_item_ids_duplicate_or_invalid");
  }
  for (const id of resultIds) {
    if (!request.byId.has(id)) errors.push(`result_item_not_owned:${id}`);
  }
  for (const id of displayIds) {
    if (!request.byId.has(id)) errors.push(`display_item_not_owned:${id}`);
    if (!resultIds.includes(id)) errors.push(`display_item_not_in_result:${id}`);
  }
  const actualChanged = !sameIdSetV1(request.currentOutfitItemIds, resultIds);
  if (typeof value.outfitChanged === "boolean" && value.outfitChanged !== actualChanged) {
    errors.push("outfit_changed_mismatch");
  }
  if (value.outfitRequested === true && resultIds.length === 0) {
    errors.push("requested_outfit_missing");
  }
  if (value.outfitRequested !== true &&
      !sameIdSetV1(request.currentOutfitItemIds, resultIds)) {
    errors.push("chat_turn_mutated_current_outfit");
  }
  if (value.outfitRequested !== true && displayIds.length) {
    errors.push("chat_turn_display_not_empty");
  }
  if (resultIds.length) {
    const items = resultIds.map((id) => request.byId.get(id)).filter(Boolean);
    errors.push(...validateStructureV1(items));
    errors.push(...validateHardWeatherV1(
      items,
      request.weatherContext,
      value.weatherContextKey,
    ));
  }
  for (const rawEvidence of Array.isArray(value.hardRequirementEvidence) ?
    value.hardRequirementEvidence.slice(0, 16) : []) {
    const evidence = safeMap(rawEvidence);
    const itemId = cleanText(evidence.itemId, 180);
    const field = cleanText(evidence.field, 80);
    const expected = cleanText(evidence.expectedValue, 100).toLowerCase();
    const item = request.byId.get(itemId);
    if (!itemId || !field || !expected || !item) {
      errors.push("hard_requirement_evidence_invalid");
      continue;
    }
    if (!resultIds.includes(itemId)) {
      errors.push(`hard_requirement_item_not_in_result:${itemId}`);
      continue;
    }
    let actualMatches = false;
    // The selected itemId already proves inclusion because the validator above
    // requires every evidence item to be present in resultingOutfitItemIds.
    // Treat expectedValue as descriptive for this field. In live Slovak turns
    // models may repeat the requested garment label (for example "mikina")
    // instead of the literal string "true"; rejecting that valid evidence
    // caused both the original result and its single repair to fail closed.
    if (field === "included") actualMatches = true;
    if (field === "primaryColor") actualMatches = item.primaryColor === expected;
    if (field === "canonicalType") actualMatches = item.canonicalType === expected;
    if (field === "canonicalFamily") actualMatches = item.canonicalFamily === expected;
    if (field === "bodySlot") actualMatches = item.bodySlots.includes(expected);
    if (field === "layerPosition") actualMatches = item.layerPosition === expected;
    if (!actualMatches) {
      errors.push(`hard_requirement_not_satisfied:${itemId}:${field}:${expected}`);
    }
  }
  for (const rawEvidence of Array.isArray(value.commentGroundingEvidence) ?
    value.commentGroundingEvidence.slice(0, 24) : []) {
    const evidence = safeMap(rawEvidence);
    // Older internal callers omit the scope; keep their result-only semantics.
    // The strict model schema always supplies it for new responses.
    const outfitContext = evidence.outfitContext === undefined ?
      "result" : evidence.outfitContext;
    const itemId = cleanText(evidence.itemId, 180);
    const field = cleanText(evidence.field, 80);
    const expected = cleanText(evidence.expectedValue, 160).toLowerCase();
    const item = request.byId.get(itemId);
    if (!itemId || !field || !expected || !item) {
      errors.push("comment_grounding_evidence_invalid");
      continue;
    }
    if (!["current", "result"].includes(outfitContext)) {
      errors.push("comment_grounding_outfit_context_invalid");
      continue;
    }
    const contextIds = outfitContext === "current" ?
      request.currentOutfitItemIds : resultIds;
    if (!contextIds.includes(itemId)) {
      errors.push(`comment_grounding_item_not_in_${outfitContext}:${itemId}`);
      continue;
    }
    let actualMatches = false;
    if (field === "included") actualMatches = expected === "true";
    if (field === "name") actualMatches = item.name.toLowerCase() === expected;
    if (field === "primaryColor") actualMatches = item.primaryColor === expected;
    if (field === "canonicalType") actualMatches = item.canonicalType === expected;
    if (field === "canonicalFamily") actualMatches = item.canonicalFamily === expected;
    if (!actualMatches) {
      errors.push(`comment_grounding_not_satisfied:${itemId}:${field}:${expected}`);
    }
  }
  if (actualChanged && displayIds.length === 0) errors.push("changed_outfit_display_empty");

  // Preserve reasons for retained items exactly; only the selection of a new
  // item may introduce a new reason. Old internal fixtures can omit this field,
  // while every live model result must include it through the strict schema.
  const reasons = new Map(request.currentSelectionReasons
    .filter((entry) => resultIds.includes(entry.itemId))
    .map((entry) => [entry.itemId, entry.reason]));
  if (value.selectionReasons !== undefined && !Array.isArray(value.selectionReasons)) {
    errors.push("selection_reasons_invalid");
  }
  if (Array.isArray(value.selectionReasons)) {
    const seen = new Set();
    for (const entry of value.selectionReasons) {
      const itemId = cleanText(entry?.itemId, 180);
      const reason = cleanText(entry?.reason, 240);
      if (!resultIds.includes(itemId) || !reason || seen.has(itemId)) {
        errors.push("selection_reason_invalid_or_detached");
        continue;
      }
      seen.add(itemId);
      if (!request.currentOutfitItemIds.includes(itemId)) reasons.set(itemId, reason);
    }
    for (const id of resultIds) {
      if (!request.currentOutfitItemIds.includes(id) && !reasons.has(id)) {
        errors.push(`new_item_selection_reason_missing:${id}`);
      }
    }
  }

  return Object.freeze({
    valid: errors.length === 0,
    errors: Object.freeze([...new Set(errors)]),
    value: Object.freeze({
      stylistComment,
      resultingOutfitItemIds: Object.freeze(resultIds),
      displayItemIds: Object.freeze(displayIds),
      outfitChanged: actualChanged,
      outfitRequested: value.outfitRequested === true,
      selectionReasons: Object.freeze([...reasons].map(([itemId, reason]) =>
        Object.freeze({itemId, reason}))),
    }),
  });
}

function fallbackStylistCommentV1(result) {
  if (result.outfitChanged) {
    return "Čo povieš na túto verziu? Podľa mňa spolu funguje veľmi dobre.";
  }
  if (result.outfitRequested) {
    return "Za mňa tento outfit funguje veľmi dobre.";
  }
  return "Jasné — čo by si chcel doladiť?";
}

function materializeResultV1(validated, request) {
  const value = validated.value;
  const publicById = new Map();
  const reasonsById = new Map(value.selectionReasons.map((entry) => [entry.itemId, entry.reason]));
  for (const id of value.resultingOutfitItemIds) {
    publicById.set(id, Object.freeze({
      ...publicWardrobeItemV1(request.rawById.get(id), request.byId.get(id)),
      ...(reasonsById.has(id) ? {stylistSelectionReason: reasonsById.get(id)} : {}),
    }));
  }
  // The same Sol response decides the validated outfit and writes its natural
  // user-facing comment. IDs/cards remain authoritative; deterministic prose is
  // reserved for the unlikely case that the optional comment is empty.
  const stylistComment = value.stylistComment || fallbackStylistCommentV1(value);
  return Object.freeze({
    contractVersion: SIMPLE_AGENT_CONTRACT_VERSION,
    simpleAgent: true,
    reply: stylistComment,
    stylistComment,
    resultingOutfitItemIds: value.resultingOutfitItemIds,
    displayItemIds: value.displayItemIds,
    outfitChanged: value.outfitChanged,
    outfitRequested: value.outfitRequested,
    selectionReasons: value.selectionReasons,
    resultingOutfitItems: Object.freeze(value.resultingOutfitItemIds.map((id) => publicById.get(id))),
    displayItems: Object.freeze(value.displayItemIds.map((id) => publicById.get(id))),
    action: value.outfitRequested ? "simple_agent_outfit" : "simple_agent_chat",
  });
}

function safeLog(logger, level, marker, details) {
  const fn = logger && typeof logger[level] === "function" ? logger[level] : null;
  if (fn) fn.call(logger, marker, details);
}

function createSimpleStylistAgentV1({executeModel, logger = console} = {}) {
  if (typeof executeModel !== "function") throw new Error("simple_agent_execute_model_required");
  return Object.freeze({
    async resolve(input) {
      let request;
      try {
        request = normalizeRequestV1(input);
      } catch (error) {
        safeLog(logger, "warn", "SIMPLE_AGENT_FAIL_CLOSED", {
          stage: "request_validation",
          errors: error.validationErrors || [String(error.message || "invalid_request")],
        });
        throw error;
      }
      safeLog(logger, "info", "SIMPLE_AGENT_REQUEST", {
        model: SIMPLE_AGENT_MODEL,
        reasoningEffort: SIMPLE_AGENT_REASONING_EFFORT,
        historyCount: request.history.length,
        wardrobeCount: request.wardrobe.length,
        currentOutfitItemIds: request.currentOutfitItemIds,
      });

      let validation;
      for (let attempt = 0; attempt < 2; attempt += 1) {
        if (attempt === 1) {
          safeLog(logger, "warn", "SIMPLE_AGENT_REPAIR", {
            validationErrors: validation.errors,
            allowedItemIds: request.wardrobe.map((item) => item.id),
          });
        }
        const modelInput = buildModelInputV1(request, attempt === 1 ? validation.errors : []);
        const raw = await executeModel(modelInput);
        safeLog(logger, "info", "SIMPLE_AGENT_RESULT", {
          attempt: attempt + 1,
          resultingOutfitItemIds: Array.isArray(raw?.resultingOutfitItemIds) ?
            raw.resultingOutfitItemIds : [],
          displayItemIds: Array.isArray(raw?.displayItemIds) ? raw.displayItemIds : [],
          outfitChanged: raw?.outfitChanged === true,
          outfitRequested: raw?.outfitRequested === true,
          weatherContextKey: cleanText(raw?.weatherContextKey, 20),
          stylistCommentPresent: Boolean(cleanText(raw?.stylistComment, 500)),
          stylistCommentLength: cleanText(raw?.stylistComment, 500).length,
          hardRequirementEvidence: Array.isArray(raw?.hardRequirementEvidence) ?
            raw.hardRequirementEvidence.slice(0, 16).map((entry) => ({
              itemId: cleanText(entry?.itemId, 180),
              field: cleanText(entry?.field, 80),
              expectedValue: cleanText(entry?.expectedValue, 100),
            })) : [],
          commentGroundingEvidence: Array.isArray(raw?.commentGroundingEvidence) ?
            raw.commentGroundingEvidence.slice(0, 24).map((entry) => ({
              itemId: cleanText(entry?.itemId, 180),
              outfitContext: cleanText(entry?.outfitContext, 20) || "result",
              field: cleanText(entry?.field, 80),
              expectedValue: cleanText(entry?.expectedValue, 160),
            })) : [],
        });
        validation = validateAgentResultV1(raw, request);
        safeLog(logger, validation.valid ? "info" : "warn", "SIMPLE_AGENT_VALIDATION", {
          attempt: attempt + 1,
          valid: validation.valid,
          validationErrors: validation.errors,
        });
        if (validation.valid) {
          const result = materializeResultV1(validation, request);
          safeLog(logger, "info", "SIMPLE_AGENT_VALIDATED", {
            attempt: attempt + 1,
            resultingOutfitItemIds: result.resultingOutfitItemIds,
            displayItemIds: result.displayItemIds,
            outfitChanged: result.outfitChanged,
          });
          return result;
        }
      }
      safeLog(logger, "warn", "SIMPLE_AGENT_FAIL_CLOSED", {
        stage: "result_validation",
        validationErrors: validation.errors,
      });
      const error = new Error("simple_agent_validation_failed");
      error.validationErrors = validation.errors;
      throw error;
    },
  });
}

function extractResponsesTextV1(json) {
  const direct = cleanText(json && json.output_text, 16000);
  if (direct) return direct;
  const parts = [];
  for (const item of Array.isArray(json && json.output) ? json.output : []) {
    if (!item || item.type !== "message") continue;
    for (const content of Array.isArray(item.content) ? item.content : []) {
      if (content && content.type === "output_text") {
        const text = cleanText(content.text, 16000);
        if (text) parts.push(text);
      }
    }
  }
  return parts.join("").trim();
}

function providerErrorDetailsV1(response, body) {
  const errorBody = safeMap(safeMap(body).error);
  const headers = response && response.headers;
  const requestId = headers && typeof headers.get === "function" ?
    cleanText(headers.get("x-request-id") || headers.get("request-id"), 160) : "";
  return Object.freeze({
    providerStatus: Number.isInteger(response?.status) ? response.status : null,
    providerErrorType: cleanText(errorBody.type, 100),
    providerErrorCode: cleanText(errorBody.code, 100),
    providerRequestId: requestId,
  });
}

function createOpenAiSimpleAgentExecutorV1({
  fetchImpl,
  resolveOpenAISecret,
  logger = console,
  sleepImpl = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds)),
} = {}) {
  if (typeof fetchImpl !== "function" || typeof resolveOpenAISecret !== "function") {
    throw new Error("simple_agent_transport_dependencies_missing");
  }
  return async function executeModel(input) {
    const requestBody = JSON.stringify({
      model: input.model,
      input: input.messages,
      reasoning: {effort: input.reasoningEffort},
      // Leave room for the structured per-item choice summaries as well as
      // evidence and the short user-facing reply.
      max_output_tokens: 2400,
      text: {
        format: {
          type: "json_schema",
          name: "simple_stylist_agent_result_v1",
          strict: true,
          schema: input.schema,
        },
      },
      store: false,
    });
    for (let providerAttempt = 1; providerAttempt <= 2; providerAttempt += 1) {
      const response = await fetchImpl("https://api.openai.com/v1/responses", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${resolveOpenAISecret()}`,
        },
        body: requestBody,
      });
      let json = {};
      try {
        json = await response.json();
      } catch (_) {
        json = {};
      }
      if (!response.ok) {
        const details = providerErrorDetailsV1(response, json);
        const permanentQuotaFailure = details.providerErrorType === "insufficient_quota" ||
          details.providerErrorCode === "credit_balance_exhausted";
        const retryable = details.providerStatus === 408 ||
          details.providerStatus === 409 ||
          (details.providerStatus === 429 && !permanentQuotaFailure) ||
          (details.providerStatus != null && details.providerStatus >= 500);
        if (providerAttempt === 1 && retryable) {
          safeLog(logger, "warn", "SIMPLE_AGENT_PROVIDER_RETRY", {
            providerAttempt,
            ...details,
          });
          await sleepImpl(750);
          continue;
        }
        const error = new Error(`simple_agent_openai_http_${details.providerStatus || "unknown"}`);
        error.code = "simple_agent_provider_failed";
        Object.assign(error, details);
        throw error;
      }
      const text = extractResponsesTextV1(json);
      if (!text) {
        const error = new Error("simple_agent_openai_empty_result");
        error.code = "simple_agent_provider_empty_result";
        error.providerResponseStatus = cleanText(json?.status, 60);
        error.providerIncompleteReason = cleanText(json?.incomplete_details?.reason, 100);
        Object.assign(error, providerErrorDetailsV1(response, json));
        throw error;
      }
      try {
        return JSON.parse(text);
      } catch (_) {
        return {stylistComment: "", resultingOutfitItemIds: null, displayItemIds: null};
      }
    }
    throw new Error("simple_agent_provider_retry_exhausted");
  };
}

module.exports = {
  SIMPLE_AGENT_MODEL,
  SIMPLE_AGENT_REASONING_EFFORT,
  SIMPLE_AGENT_CONTRACT_VERSION,
  SIMPLE_AGENT_RESULT_SCHEMA,
  compactWardrobeItemV1,
  normalizeRequestV1,
  buildModelInputV1,
  validateAgentResultV1,
  createSimpleStylistAgentV1,
  createOpenAiSimpleAgentExecutorV1,
};
