"use strict";

const {clone} = require("./stylist_session_state_v2");
const {categoryMatches} = require("./firestore_wardrobe_tool_v2");

const NUMBER_WORDS = new Map(Object.entries({
  jeden: 1, jedna: 1, jedno: 1, dva: 2, dve: 2, tri: 3, styri: 4,
  pat: 5, sest: 6, sedem: 7, osem: 8, devat: 9, desat: 10,
  jedenast: 11, dvanast: 12, trinast: 13, strnast: 14,
}));

const WEEKDAYS = new Map(Object.entries({
  pondelok: 1, pondelka: 1, pondeloky: 1,
  utorok: 2, utorka: 2,
  streda: 3, stredu: 3, stredy: 3,
  stvrtok: 4, stvrtka: 4,
  piatok: 5, piatka: 5,
  sobota: 6, sobotu: 6, soboty: 6,
  nedela: 0, nedelu: 0, nedele: 0,
}));

function normalizeShellTextV2(value) {
  return String(value || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9.\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function parseDateKeyV2(value) {
  const match = String(value || "").match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return null;
  return date;
}

function buildUtcDateV2(year, month, day) {
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return null;
  return date;
}

function nextMonthDayV2(today, month, day) {
  const startYear = today.getUTCFullYear();
  // Four years are enough to cross a leap cycle for 29 February while keeping
  // an implicit date conservative and deterministic.
  for (let offset = 0; offset <= 4; offset += 1) {
    const candidate = buildUtcDateV2(startYear + offset, month, day);
    if (candidate && candidate.getTime() >= today.getTime()) return candidate;
  }
  return null;
}

function formatDateKeyV2(date) {
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, "0")}-${String(date.getUTCDate()).padStart(2, "0")}`;
}

function addDaysV2(date, days) {
  const out = new Date(date.getTime());
  out.setUTCDate(out.getUTCDate() + days);
  return out;
}

function numberTokenV2(token) {
  if (/^\d+$/.test(token || "")) return Number(token);
  return NUMBER_WORDS.get(token) || null;
}

function nextWeekdayV2(base, targetDay, minimumDays = 1) {
  let delta = (targetDay - base.getUTCDay() + 7) % 7;
  if (delta < minimumDays) delta += 7;
  return addDaysV2(base, delta);
}

function normalizedDateMatchRangeV2(match) {
  const raw = String(match?.[0] || "");
  const leadingWhitespace = raw.match(/^\s*/)?.[0]?.length || 0;
  const trailingWhitespace = raw.match(/\s*$/)?.[0]?.length || 0;
  return {
    start: Number(match?.index || 0) + leadingWhitespace,
    end: Number(match?.index || 0) + raw.length - trailingWhitespace,
  };
}

function hasCompetingDateExpressionsV2(normalized) {
  const number = "(?:\\d+|jeden|jedna|jedno|dva|dve|tri|styri|pat|sest|sedem|osem|devat|desat|jedenast|dvanast|trinast|strnast)";
  const weekday = "(?:pondelok|pondelka|utorok|utorka|stredu|streda|stvrtok|stvrtka|piatok|piatka|sobotu|sobota|nedelu|nedela)";
  const patterns = [
    /(?:^|\s)\d{1,2}\.\d{1,2}(?:\.\d{4})?\.?(?=\s|$)/g,
    /\b(?:pozajtra|zajtra|dnes)\b/g,
    new RegExp(`\\b(?:o|za)\\s+${number}\\s+(?:den|dni|dnov)\\b`, "g"),
    new RegExp(`\\b(?:o|za)\\s+(?:${number}\\s+)?tyzd(?:en|ne|nov)\\s+(?:v|vo)\\s+${weekday}\\b`, "g"),
    new RegExp(`\\b(?:o|za)\\s+(?:${number}\\s+)?tyzd(?:en|ne|nov)\\b`, "g"),
    new RegExp(`\\b(?:(?:buduci|buducu|najblizsi|najblizsiu|tento|tuto)\\s+)?${weekday}\\b`, "g"),
  ];

  const ranges = [];
  for (const pattern of patterns) {
    for (const match of normalized.matchAll(pattern)) {
      const range = normalizedDateMatchRangeV2(match);
      if (range.end > range.start) ranges.push(range);
    }
  }
  if (ranges.length <= 1) return false;

  // Nested recognizers are one semantic expression, not a conflict. Example:
  // "o tyzden v stredu" is seen as the full compound, "o tyzden", and
  // "stredu". Their ranges overlap, so collapse that connected component.
  ranges.sort((a, b) => a.start - b.start || b.end - a.end);
  const merged = [];
  for (const range of ranges) {
    const previous = merged[merged.length - 1];
    if (previous && range.start < previous.end && range.end > previous.start) {
      previous.end = Math.max(previous.end, range.end);
    } else {
      merged.push({...range});
    }
  }
  return merged.length > 1;
}

function parseDeterministicDateV2(text, todayDateKey) {
  const today = parseDateKeyV2(todayDateKey);
  if (!today) return null;
  const normalized = normalizeShellTextV2(text);
  if (!normalized) return null;
  if (hasCompetingDateExpressionsV2(normalized)) return null;

  const absoluteRe = /(?:^|\s)(\d{1,2})\.(\d{1,2})(?:\.(\d{4}))?(?:\.|\s|$)/g;
  const absoluteMatches = [...normalized.matchAll(absoluteRe)];
  if (absoluteMatches.length > 1) return null;

  const simpleRelativeSignals = ["pozajtra", "zajtra", "dnes"].filter((token) =>
    new RegExp(`\\b${token}\\b`).test(normalized));
  if (simpleRelativeSignals.length > 1) return null;
  if (absoluteMatches.length === 1 && simpleRelativeSignals.length === 1) return null;

  const absolute = absoluteMatches[0] || null;
  if (absolute) {
    const month = Number(absolute[2]);
    const day = Number(absolute[1]);
    const parsed = absolute[3] ? buildUtcDateV2(Number(absolute[3]), month, day) : nextMonthDayV2(today, month, day);
    if (parsed) {
      return {dateKey: formatDateKeyV2(parsed), label: absolute[0].trim(), source: "deterministic_user_text"};
    }
  }

  if (simpleRelativeSignals[0] === "pozajtra") {
    return {dateKey: formatDateKeyV2(addDaysV2(today, 2)), label: "pozajtra", source: "deterministic_user_text"};
  }
  if (simpleRelativeSignals[0] === "zajtra") {
    return {dateKey: formatDateKeyV2(addDaysV2(today, 1)), label: "zajtra", source: "deterministic_user_text"};
  }
  if (simpleRelativeSignals[0] === "dnes") {
    return {dateKey: formatDateKeyV2(today), label: "dnes", source: "deterministic_user_text"};
  }

  const relativeDays = normalized.match(/\b(?:o|za)\s+(\d+|jeden|jedna|jedno|dva|dve|tri|styri|pat|sest|sedem|osem|devat|desat|jedenast|dvanast|trinast|strnast)\s+(?:den|dni|dnov)\b/);
  if (relativeDays) {
    const amount = numberTokenV2(relativeDays[1]);
    if (Number.isInteger(amount) && amount >= 0 && amount <= 60) {
      return {dateKey: formatDateKeyV2(addDaysV2(today, amount)), label: relativeDays[0], source: "deterministic_user_text"};
    }
  }

  const weekWithDay = normalized.match(/\b(?:o|za)\s+(?:(\d+|jeden|jedenast|dva|dve|tri|styri)\s+)?tyzd(?:en|ne|nov)\s+(?:v|vo)\s+(pondelok|pondelka|utorok|utorka|stredu|streda|stvrtok|stvrtka|piatok|piatka|sobotu|sobota|nedelu|nedela)\b/);
  if (weekWithDay) {
    const weeks = weekWithDay[1] ? numberTokenV2(weekWithDay[1]) : 1;
    const target = WEEKDAYS.get(weekWithDay[2]);
    if (weeks && target != null) {
      const anchor = addDaysV2(today, weeks * 7);
      return {dateKey: formatDateKeyV2(nextWeekdayV2(anchor, target, 0)), label: weekWithDay[0], source: "deterministic_user_text"};
    }
  }

  const relativeWeeks = normalized.match(/\b(?:o|za)\s+(?:(\d+|jeden|dva|dve|tri|styri)\s+)?tyzd(?:en|ne|nov)\b/);
  if (relativeWeeks) {
    const weeks = relativeWeeks[1] ? numberTokenV2(relativeWeeks[1]) : 1;
    if (Number.isInteger(weeks) && weeks >= 1 && weeks <= 8) {
      return {dateKey: formatDateKeyV2(addDaysV2(today, weeks * 7)), label: relativeWeeks[0], source: "deterministic_user_text"};
    }
  }

  const weekday = normalized.match(/\b(?:(buduci|buducu|najblizsi|najblizsiu|tento|tuto)\s+)?(pondelok|pondelka|utorok|utorka|stredu|streda|stvrtok|stvrtka|piatok|piatka|sobotu|sobota|nedelu|nedela)\b/);
  if (weekday) {
    const target = WEEKDAYS.get(weekday[2]);
    if (target != null) {
      const inclusiveCurrentDay = ["tento", "tuto"].includes(weekday[1]);
      return {
        dateKey: formatDateKeyV2(nextWeekdayV2(today, target, inclusiveCurrentDay ? 0 : 1)),
        label: weekday[0].trim(),
        source: "deterministic_user_text",
      };
    }
  }
  return null;
}

function applyDeterministicDateFromTextV2(state, text, todayDateKey) {
  const parsed = parseDeterministicDateV2(text, todayDateKey);
  if (!parsed) return clone(state);
  const next = clone(state);
  const weatherDateKey = next.context?.weather?.dateKey || null;
  next.context.date = parsed;
  if (weatherDateKey && weatherDateKey !== parsed.dateKey) next.context.weather = null;
  return next;
}

const EDIT_TERMS = Object.freeze([
  {category: "layer", kind: "hoodie", re: /\b(mikinu|mikina|mikiny|hoodie)\b/},
  {category: "layer", kind: "sweater", re: /\b(sveter|svetra|svetre|pulover|pulovera)\b/},
  {category: "layer", kind: "jacket", re: /\b(bundu|bunda|bundy)\b/},
  {category: "layer", kind: "coat", re: /\b(kabat|kabata|kabaty)\b/},
  {category: "layer", kind: null, re: /\b(vrchnu vrstvu|vrstva|vrstvu)\b/},
  {category: "upper_body", kind: "tshirt", re: /\b(tricko|tricka|tee)\b/},
  {category: "upper_body", kind: "shirt", re: /\b(koselu|kosela|kosele)\b/},
  {category: "upper_body", kind: "blouse", re: /\b(bluzku|bluzka|bluzky)\b/},
  {category: "lower_body", kind: "jeans", re: /\b(rifle|dzinsy|jeans)\b/},
  {category: "lower_body", kind: "sweatpants", re: /\b(teplaky|joggers)\b/},
  {category: "lower_body", kind: "shorts", re: /\b(kratasy|sortky)\b/},
  {category: "lower_body", kind: "skirt", re: /\b(suknu|sukna|sukne)\b/},
  {category: "lower_body", kind: null, re: /\b(gate|nohavice|nohavic)\b/},
  {category: "footwear", kind: "sneakers", re: /\b(tenisky|tenisku|sneakers)\b/},
  {category: "footwear", kind: "boots", re: /\b(cizmy|cizmu|boots)\b/},
  {category: "footwear", kind: null, re: /\b(topanky|topanku|obuv)\b/},
  {category: "full_body", kind: "dress", re: /\b(saty|saty)\b/},
  {category: "full_body", kind: "jumpsuit", re: /\b(overal|overalu)\b/},
]);
const STRONG_EDIT_VERB_RE = /\b(zmen|zmenit|vymen|vymenit|nahrad|nahradit)\b/;
const REQUEST_ALTERNATIVE_RE = /\b(?:skus|daj|chcem)\s+(?:mi\s+)?(?:ine|iny|inu|inych|nieco ine)\b/;

function itemDescriptorV2(item) {
  return normalizeShellTextV2([
    item?.canonicalType,
    item?.canonicalFamily,
    item?.subCategory,
    item?.mainGroup,
    item?.name,
  ].filter(Boolean).join(" "));
}

function itemMatchesEditKindV2(item, kind) {
  if (!kind) return true;
  const text = itemDescriptorV2(item);
  if (!text) return false;
  if (kind === "hoodie") return /\b(hoodie|sweatshirt|mikina)\b/.test(text);
  if (kind === "sweater") return /\b(sweater|jumper|pullover|pulover|knitwear|cardigan|sveter)\b/.test(text);
  if (kind === "jacket") return /\b(jacket|parka|puffer|windbreaker|anorak|bunda)\b/.test(text);
  if (kind === "coat") return /\b(coat|overcoat|trench|kabat)\b/.test(text);
  if (kind === "tshirt") return /\b(t shirt|tshirt|tee|tricko)\b/.test(text);
  if (kind === "shirt") return !/\b(t shirt|tshirt|tee)\b/.test(text) && /\b(shirt|kosela)\b/.test(text);
  if (kind === "blouse") return /\b(blouse|bluzka)\b/.test(text);
  if (kind === "jeans") return /\b(jeans|denim|rifle|dzinsy)\b/.test(text);
  if (kind === "sweatpants") return /\b(sweatpants|joggers|teplaky)\b/.test(text);
  if (kind === "shorts") return /\b(shorts|kratasy|sortky)\b/.test(text);
  if (kind === "skirt") return /\b(skirt|sukna)\b/.test(text);
  if (kind === "sneakers") return /\b(sneakers|trainers|tenisky)\b/.test(text);
  if (kind === "boots") return /\b(boots|boot|cizmy)\b/.test(text);
  if (kind === "dress") return /\b(dress|saty)\b/.test(text);
  if (kind === "jumpsuit") return /\b(jumpsuit|overal)\b/.test(text);
  return false;
}

function detectDeterministicEditScopeV2(message, state, wardrobeItems) {
  const normalized = normalizeShellTextV2(message);
  if (!STRONG_EDIT_VERB_RE.test(normalized) && !REQUEST_ALTERNATIVE_RE.test(normalized)) return null;
  const currentIds = Array.isArray(state?.currentOutfit?.itemIds) ? state.currentOutfit.itemIds : [];
  if (!currentIds.length || !Array.isArray(wardrobeItems) || !wardrobeItems.length) return null;
  const currentItems = wardrobeItems.filter((item) => currentIds.includes(item.id));
  const term = EDIT_TERMS.find((entry) => entry.re.test(normalized)) || null;
  let targets = term ? currentItems.filter((item) =>
    categoryMatches(item, term.category) && itemMatchesEditKindV2(item, term.kind)) : [];
  if (!targets.length && !term) {
    targets = currentItems.filter((item) => {
      const name = normalizeShellTextV2(item.name || item.canonicalType || "");
      return name && name.split(" ").some((part) => part.length >= 4 && normalized.includes(part));
    });
  }
  if (targets.length !== 1) return null;
  const target = targets[0];
  const semanticCategory = term?.category || target.category || target.canonicalFamily || target.canonicalType || null;
  if (!semanticCategory) return null;

  // The target noun identifies exactly which current item is being replaced.
  // Replacement breadth is a separate concern: trousers may legitimately replace
  // sweatpants and other footwear may replace sneakers. Layered upper-body pieces
  // are the dangerous exception because hoodie/jacket/coat share upper_body; for
  // those named layer kinds we keep retrieval on the exact canonical type so an
  // unrelated outer layer can never enter the authorized candidate set.
  let candidatePool = wardrobeItems.filter((item) =>
    !currentIds.includes(item.id) && categoryMatches(item, semanticCategory));
  if (!candidatePool.length) return null;

  let retrievalCategory = semanticCategory;
  const strictLayerKinds = new Set(["hoodie", "sweater", "jacket", "coat"]);
  if (strictLayerKinds.has(term?.kind)) {
    const canonicalType = String(target.canonicalType || "").trim().toLowerCase();
    if (!canonicalType) return null;
    candidatePool = candidatePool.filter((item) =>
      String(item.canonicalType || "").trim().toLowerCase() === canonicalType);
    if (!candidatePool.length) return null;
    retrievalCategory = canonicalType;
  }

  const allowedSlots = [...new Set(target.bodySlots || [])];
  const allowedCategories = [...new Set(candidatePool.map((item) => item.category).filter(Boolean))];
  return {
    category: retrievalCategory,
    targetItemId: target.id,
    editScope: {
      replaceItemIds: [target.id],
      retainItemIds: [],
      allowedSlots,
      allowedCategories,
      allowRemovalOnly: false,
    },
  };
}

module.exports = {
  addDaysV2,
  applyDeterministicDateFromTextV2,
  buildUtcDateV2,
  detectDeterministicEditScopeV2,
  formatDateKeyV2,
  normalizeShellTextV2,
  parseDateKeyV2,
  parseDeterministicDateV2,
};
