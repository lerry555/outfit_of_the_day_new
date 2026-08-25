"use strict";

const {
  STYLE_PREFERENCE_RULES,
  formatStylePreferencesBlock,
  sanitizeUserStylePreferences,
} = require("./style_preferences_context");

const HOME_TASTE_RULES =
  `\nULOŽENÉ ŠTÝLOVÉ PREFERENCIE (chuť medzi už vhodnými kandidátmi):\n` +
  `- Poradie: 1) počasie a praktická bezpečnosť 2) dostupný šatník / validný outfit ` +
  `3) denná vhodnosť 4) ruleScore kandidátov 5) tieto uložené preferencie.\n` +
  `- Vyberaj LEN medzi poskytnutými kandidátmi. Nevymýšľaj kúsky.\n` +
  `- avoidedColors: silné vyhnutie, ALE nie tvrdé bezpečnostné pravidlo.\n` +
  `- preferredStyles: pozitívna štylistická preferencia.\n` +
  `- favoriteColors: mäkká preferencia — môžeš k nej prikloniť, nenútiť.\n` +
  `- favoriteBrands: slabá preferencia LEN ak kúsok v kandidátovi má tú značku.\n` +
  `- Chuť NESMIE vybrať menej vhodný outfit (dážď, zima, chýbajúca vrstva).\n` +
  `- V reason nespomínaj preferencie, kým reálne neovplyvnili výber. ` +
  `Nikdy nepíš interné názvy polí.\n`;

function attachHomeFinalReviewPreferences(raw) {
  const prefs = sanitizeUserStylePreferences(raw);
  if (!prefs) {
    return {prefs: null, systemSuffix: "", userBlock: ""};
  }
  return {
    prefs,
    systemSuffix: HOME_TASTE_RULES,
    userBlock: formatStylePreferencesBlock(prefs),
  };
}

module.exports = {
  HOME_TASTE_RULES,
  attachHomeFinalReviewPreferences,
  STYLE_PREFERENCE_RULES,
};
