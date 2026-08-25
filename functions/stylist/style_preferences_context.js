"use strict";

const MAX_LIST = 16;
const MAX_ITEM_LENGTH = 40;

function asStringList(raw) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  const seen = new Set();
  for (const item of raw) {
    const value = String(item || "").trim().slice(0, MAX_ITEM_LENGTH);
    if (!value) continue;
    const key = value.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(value);
    if (out.length >= MAX_LIST) break;
  }
  return out;
}

function sanitizeUserStylePreferences(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const favoriteColors = asStringList(raw.favoriteColors);
  const avoidedColors = asStringList(raw.avoidedColors);
  const preferredStyles = asStringList(raw.preferredStyles);
  const favoriteBrands = asStringList(raw.favoriteBrands);
  if (!favoriteColors.length && !avoidedColors.length &&
      !preferredStyles.length && !favoriteBrands.length) {
    return null;
  }
  return {favoriteColors, avoidedColors, preferredStyles, favoriteBrands};
}

const STYLE_PREFERENCE_RULES =
  `\nULOŽENÉ ŠTÝLOVÉ PREFERENCIE (userStylePreferences — chuť, NIE povinnosť):\n` +
  `- Poradie: 1) aktuálna správa používateľa 2) dress code / príležitosť / aktivita ` +
  `3) počasie a praktická bezpečnosť 4) dostupnosť šatníka 5) tieto uložené preferencie.\n` +
  `- avoidedColors: silné vyhnutie sa farbe, ALE nie tvrdé bezpečnostné pravidlo. ` +
  `Ak je rovnako vhodná alternatíva, vyhni sa jej. Ak je to jediný vhodný kúsok ` +
  `(dážď, svadba, pohreb, pohovor, turistika), suitability vyhrá.\n` +
  `- preferredStyles: pozitívna štylistická preferencia, keď dress code dovolí.\n` +
  `- favoriteColors: mäkká preferencia — môžeš k nej prikloniť, nenútiť.\n` +
  `- favoriteBrands: slabá preferencia LEN ak kúsok v šatníku má tú značku.\n` +
  `- Aktuálna správa môže uložené preferencie pre TENTO turn prebiť ` +
  `(napr. „chcem čierny outfit" aj keď avoidedColors obsahuje black). ` +
  `Uložené preferencie NEPREPISUJ.\n` +
  `- Nevymýšľaj kúsky, ktoré user nevlastní.\n` +
  `- V reply nespomínaj preferencie, kým reálne neovplyvnili výber. ` +
  `Nikdy nepíš interné názvy polí ani vety typu „favoriteColors contains…".\n`;

function formatStylePreferencesBlock(prefs) {
  const clean = sanitizeUserStylePreferences(prefs);
  if (!clean) return "";
  const lines = [
    "USER STYLE PREFERENCES (saved taste; subordinate):",
    "Precedence: current message > occasion/dress-code/activity > weather/safety > wardrobe availability > these preferences.",
  ];
  if (clean.preferredStyles.length) {
    lines.push(`preferredStyles: ${clean.preferredStyles.join(", ")} (positive style preference).`);
  }
  if (clean.avoidedColors.length) {
    lines.push(
      `avoidedColors: ${clean.avoidedColors.join(", ")} ` +
      `(strong avoid, not an absolute safety constraint; equally suitable alternatives should win).`,
    );
  }
  if (clean.favoriteColors.length) {
    lines.push(`favoriteColors: ${clean.favoriteColors.join(", ")} (soft preference, not required).`);
  }
  if (clean.favoriteBrands.length) {
    lines.push(
      `favoriteBrands: ${clean.favoriteBrands.join(", ")} ` +
      `(weak preference only when a wardrobe item actually has that brand).`,
    );
  }
  lines.push("Do not invent owned items. Do not mention preferences unless they materially influenced the outfit.");
  return lines.join("\n");
}

function appendStylePreferencesSection(base, prefs) {
  const block = formatStylePreferencesBlock(prefs);
  if (!block) return base;
  return `${base}\n\n${block}`;
}

module.exports = {
  STYLE_PREFERENCE_RULES,
  appendStylePreferencesSection,
  formatStylePreferencesBlock,
  sanitizeUserStylePreferences,
};
