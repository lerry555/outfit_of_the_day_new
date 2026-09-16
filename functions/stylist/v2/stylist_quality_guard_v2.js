"use strict";

const OUTDOOR_ACTIVITY_IDS = new Set([
  "hike", "hiking", "mountains", "mountain_hike", "trekking", "outdoor", "nature_walk",
]);
const PROTECTIVE_FUNCTION_TOKENS = [
  "weather_protection", "rain_protection", "wind_protection", "waterproof", "windproof", "shell",
];

function clone(value) {
  return value == null ? value : JSON.parse(JSON.stringify(value));
}

function text(value) {
  return String(value || "").trim();
}

function normalized(value) {
  return text(value)
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9\s_-]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function array(value) {
  return Array.isArray(value) ? value : [];
}

function numeric(value) {
  if (value == null || value === "") return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function naturalListV2(values) {
  const items = array(values).map(text).filter(Boolean);
  if (items.length <= 1) return items[0] || "";
  if (items.length === 2) return `${items[0]} a ${items[1]}`;
  return `${items.slice(0, -1).join(", ")} a ${items[items.length - 1]}`;
}

function normalizedSeasonV2(value) {
  const season = normalized(value).replace(/\s+/g, "_");
  if (["zim", "zima", "winter"].includes(season)) return "winter";
  if (["let", "leto", "summer"].includes(season)) return "summer";
  if (["jar", "spring"].includes(season)) return "spring";
  if (["jese", "jesen", "autumn", "fall"].includes(season)) return "autumn";
  if (["celorocne", "all_season", "all-season", "allseason"].includes(season)) return "all_season";
  return season;
}

function currentTemperatureCV2(session) {
  const snapshot = session?.context?.weather?.snapshot || {};
  const representative = numeric(snapshot.representativeTempC);
  if (representative != null) return representative;
  const min = numeric(snapshot.minTempC);
  const max = numeric(snapshot.maxTempC);
  if (min != null && max != null) return (min + max) / 2;
  return max ?? min;
}

function currentMonthV2(session) {
  const dateKey = text(session?.context?.date?.dateKey);
  const match = dateKey.match(/^\d{4}-(\d{2})-\d{2}$/);
  if (!match) return null;
  const month = Number(match[1]);
  return Number.isInteger(month) && month >= 1 && month <= 12 ? month : null;
}

function isFootwearV2(item) {
  return normalized(item?.category) === "footwear" ||
    normalized(item?.canonicalFamily) === "footwear" ||
    array(item?.bodySlots).includes("feet");
}

function isBootV2(item) {
  const type = normalized(item?.canonicalType);
  return type.includes("boot") || type.includes("cizm");
}

function userExplicitlyRequestsBootsV2(input) {
  const latest = normalized(input?.request?.latestUserInput);
  return /\b(boot\w*|cizm\w*|chelsea\w*|zimn\w*\s+(?:topank\w*|obuv\w*))\b/.test(latest);
}

function isWinterFootwearUnsuitableV2(item, input) {
  if (!isFootwearV2(item) || !isBootV2(item) || userExplicitlyRequestsBootsV2(input)) return false;
  const warmth = numeric(item?.warmth) ?? 0;
  const type = normalized(item?.canonicalType).replace(/\s+/g, "_");
  const seasons = array(item?.seasons).map(normalizedSeasonV2).filter(Boolean);
  const winterOnly = seasons.length > 0 && seasons.every((season) => season === "winter");
  const supportsWarmSeason = seasons.some((season) => ["summer", "all_season"].includes(season));
  const winterType = type.includes("winter") || type.includes("snow");
  const temp = currentTemperatureCV2(input?.session);

  if (temp != null) {
    if (temp >= 14 && winterOnly && warmth >= 7) return true;
    if (temp >= 18 && winterType && warmth >= 7) return true;
    if (temp >= 20 && warmth >= 6 && !supportsWarmSeason) return true;
    return false;
  }

  const month = currentMonthV2(input?.session);
  if (month != null && month >= 4 && month <= 10 && warmth >= 7 && (winterOnly || winterType)) {
    return true;
  }
  return false;
}

function hasProtectiveOuterFunctionV2(item) {
  const type = normalized(item?.canonicalType).replace(/\s+/g, "_");
  const functions = array(item?.outfitFunctions).map((value) => normalized(value).replace(/\s+/g, "_"));
  if (functions.some((fn) => PROTECTIVE_FUNCTION_TOKENS.some((token) => fn.includes(token)))) return true;
  return /(?:rain|shell|windbreaker|windproof|waterproof)/.test(type);
}

function isLightSportOuterV2(item) {
  if (!item || !["outer", "shell"].includes(normalized(item.layerPosition))) return false;
  if (!array(item.bodySlots).includes("upper_body")) return false;
  const haystack = normalized([item.canonicalType, item.name, item.subCategory, item.canonicalFamily].filter(Boolean).join(" "));
  return /\b(track|training|sport|sports|athletic|trening)\w*\b/.test(haystack);
}

function isOutdoorRelevantV2(session) {
  const environment = normalized(session?.context?.environment);
  const activity = normalized(session?.context?.activity?.id).replace(/\s+/g, "_");
  return environment === "outdoor" || environment === "mixed" || OUTDOOR_ACTIVITY_IDS.has(activity);
}

function preserveCurrentCandidatesV2(input) {
  return input?.runtimeConstraints?.requiredAnswerAction === "edit_outfit" ||
    Boolean(input?.toolResults?.authorizedEditScope);
}

function filterWardrobeForStylistQualityV2(items, input) {
  const wardrobe = clone(array(items));
  if (!wardrobe.length) return wardrobe;
  const currentIds = preserveCurrentCandidatesV2(input) ?
    new Set(array(input?.session?.currentOutfit?.itemIds).map(String)) : new Set();
  const mids = wardrobe.filter((item) =>
    normalized(item?.layerPosition) === "mid" && array(item?.bodySlots).includes("upper_body"));
  const maxMidWarmth = mids.reduce((best, item) => Math.max(best, numeric(item?.warmth) ?? 0), -Infinity);
  const outdoor = isOutdoorRelevantV2(input?.session);
  const temp = currentTemperatureCV2(input?.session);

  return wardrobe.filter((item) => {
    if (currentIds.has(String(item?.id || ""))) return true;
    if (isWinterFootwearUnsuitableV2(item, input)) return false;
    if (outdoor && temp != null && temp <= 16 && Number.isFinite(maxMidWarmth) &&
        isLightSportOuterV2(item) && !hasProtectiveOuterFunctionV2(item) &&
        (numeric(item?.warmth) ?? 0) < maxMidWarmth) {
      return false;
    }
    return true;
  });
}

function guardSelectedOutfitQualityV2(raw, input) {
  if (!raw || raw.action !== "generate_outfit" || !isOutdoorRelevantV2(input?.session)) return raw;
  const selectedIds = array(raw.resultingOutfitItemIds).map(String);
  if (selectedIds.length < 2) return raw;
  const itemById = new Map(array(input?.toolResults?.wardrobeItems).map((item) => [String(item?.id || ""), item]));
  const selectedItems = selectedIds.map((id) => itemById.get(id)).filter(Boolean);
  const mids = selectedItems.filter((item) =>
    normalized(item?.layerPosition) === "mid" && array(item?.bodySlots).includes("upper_body"));
  if (!mids.length) return raw;

  const removeIds = new Set();
  for (const outer of selectedItems) {
    if (!isLightSportOuterV2(outer) || hasProtectiveOuterFunctionV2(outer)) continue;
    const outerWarmth = numeric(outer?.warmth) ?? 0;
    if (mids.some((mid) => (numeric(mid?.warmth) ?? 0) > outerWarmth)) {
      removeIds.add(String(outer.id));
    }
  }
  if (!removeIds.size) return raw;

  const next = clone(raw);
  next.resultingOutfitItemIds = selectedIds.filter((id) => !removeIds.has(id));
  next.displayItemIds = array(raw.displayItemIds).map(String).filter((id) => !removeIds.has(id));
  next.selectionReasons = array(raw.selectionReasons).filter((entry) => !removeIds.has(String(entry?.itemId || "")));
  const remainingNames = next.resultingOutfitItemIds
    .map((id) => text(itemById.get(id)?.name))
    .filter(Boolean);
  if (remainingNames.length) {
    next.assistantText = `Odporúčam ti ${naturalListV2(remainingNames)}. Slabšiu tréningovú bundu cez teplejšiu mikinu vynechávam, pretože bez ochrannej funkcie by také vrstvenie nedávalo zmysel.`;
  }
  return next;
}

function normalizeStylistVoiceV2(value) {
  let output = text(value);
  if (!output) return output;
  output = output
    .replace(/\bby som išiel(?:a)?\s+radšej\s+vo vrstvách\b/giu, "odporúčam ti obliecť sa vo vrstvách")
    .replace(/\bby som išiel(?:a)?\s+čisto\s+a\s+uhladen[eé]\b/giu, "ti odporúčam čistý a uhladený outfit")
    .replace(/\bja\s+by som si\s+dal(?:a)?\b/giu, "odporúčam ti")
    .replace(/\bja\s+by som\s+zvolil(?:a)?\b/giu, "odporúčam ti zvoliť")
    .replace(/\bja\s+by som\s+išiel(?:a)?\b/giu, "odporúčam ti obliecť sa")
    .replace(/\bby som si\s+dal(?:a)?\b/giu, "odporúčam ti")
    .replace(/\bby som\s+zvolil(?:a)?\b/giu, "odporúčam ti zvoliť");
  return output.replace(/\s{2,}/g, " ").trim();
}

function hasWeatherCueV2(value) {
  const line = normalized(value);
  return /\b(pocas\w*|teplot\w*|stupn\w*|dazd\w*|prs\w*|vetr\w*|vietor\w*|sneh\w*|chlad\w*|tepl\w*)\b/.test(line) || /°\s*c?/i.test(String(value || ""));
}

function weatherSentenceV2(session) {
  const snapshot = session?.context?.weather?.snapshot;
  if (!snapshot || typeof snapshot !== "object") return null;
  const min = numeric(snapshot.minTempC);
  const max = numeric(snapshot.maxTempC);
  const representative = numeric(snapshot.representativeTempC);
  let temperature = null;
  if (min != null && max != null && Math.round(min) !== Math.round(max)) {
    temperature = `${Math.round(min)}–${Math.round(max)} °C`;
  } else {
    const value = representative ?? max ?? min;
    if (value != null) temperature = `${Math.round(value)} °C`;
  }
  const facts = [];
  if (temperature) facts.push(`teplotou ${temperature}`);
  if (snapshot.willRain === true) facts.push("možným dažďom");
  if (snapshot.willSnow === true) facts.push("snežením");
  if (snapshot.isWindy === true) {
    const wind = numeric(snapshot.maxWindKph);
    facts.push(wind != null ? `vetrom do približne ${Math.round(wind)} km/h` : "vetrom");
  }
  if (!facts.length) return null;
  const prefix = OUTDOOR_ACTIVITY_IDS.has(normalized(session?.context?.activity?.id).replace(/\s+/g, "_")) ?
    "Na túre" : "Vonku";
  return `${prefix} počítaj s ${naturalListV2(facts)}.`;
}

function applyStylistResponseQualityV2(envelope, input) {
  if (!envelope || envelope.kind !== "final" || !envelope.result) return envelope;
  const next = clone(envelope);
  next.result.assistantText = normalizeStylistVoiceV2(next.result.assistantText);
  if (["generate_outfit", "edit_outfit"].includes(next.result.action) &&
      isOutdoorRelevantV2(input?.session) && input?.session?.context?.weather &&
      !hasWeatherCueV2(next.result.assistantText)) {
    const sentence = weatherSentenceV2(input.session);
    if (sentence) next.result.assistantText = `${sentence} ${next.result.assistantText}`.trim();
  }
  return next;
}

module.exports = {
  applyStylistResponseQualityV2,
  currentMonthV2,
  currentTemperatureCV2,
  filterWardrobeForStylistQualityV2,
  guardSelectedOutfitQualityV2,
  hasProtectiveOuterFunctionV2,
  isWinterFootwearUnsuitableV2,
  normalizeStylistVoiceV2,
  weatherSentenceV2,
};
