"use strict";

/** Shared production allowlists (mirror analyzeClothingImage contract). */

const ALLOWED_SEASONS = Object.freeze([
  "jar", "leto", "jeseň", "zima", "celoročne",
]);

const ALLOWED_PATTERNS = Object.freeze([
  "jednofarebné",
  "pruhované",
  "kockované",
  "bodkované",
  "kvetované",
  "maskáčové",
  "animal print",
  "grafické",
  "iný vzor",
]);

const ALLOWED_STYLES = Object.freeze([
  "elegantný",
  "casual",
  "streetwear",
  "športový",
  "business",
  "outdoor",
  "basic",
  "party",
]);

const ALLOWED_COLORS = Object.freeze([
  "čierna", "biela", "sivá", "tmavomodrá", "modrá", "svetlomodrá",
  "zelená", "olivová", "khaki", "hnedá", "béžová", "červená", "bordová",
  "žltá", "oranžová", "ružová", "fialová",
]);

const ALLOWED_FIT = Object.freeze([
  "slim", "regular", "relaxed", "oversized", "unknown",
]);

const ALLOWED_VIBE = Object.freeze([
  "basic", "minimalist", "casual", "streetwear", "sport", "business",
  "elegant", "outdoor", "party", "beach", "urban", "unknown",
]);

const ALLOWED_LOGO_PROMINENCE = Object.freeze([
  "none", "small", "medium", "large", "unknown",
]);

const ALLOWED_OCCASION_FIT = Object.freeze([
  "daily", "work", "date", "party", "sport", "travel", "beach",
  "home", "outdoor", "formal_event",
]);

/** Full production layer roles including KB body-placement values. */
const ALLOWED_LAYER_ROLE = Object.freeze([
  "base_layer", "mid_layer", "outer_layer", "bottom", "footwear", "accessory",
]);

const ALLOWED_IDENTITY_SLOT = Object.freeze([
  "tops", "outerwear", "bottoms", "one_piece", "footwear", "accessories",
]);

const COLOR_MAP = Object.freeze({
  navy: "tmavomodrá",
  "dark blue": "tmavomodrá",
  blue: "modrá",
  "light blue": "svetlomodrá",
  black: "čierna",
  white: "biela",
  grey: "sivá",
  gray: "sivá",
  beige: "béžová",
  brown: "hnedá",
  olive: "olivová",
  khaki: "khaki",
  green: "zelená",
  red: "červená",
  burgundy: "bordová",
  yellow: "žltá",
  orange: "oranžová",
  pink: "ružová",
  purple: "fialová",
});

const PATTERN_MAP = Object.freeze({
  solid: "jednofarebné",
  plain: "jednofarebné",
  striped: "pruhované",
  checked: "kockované",
  plaid: "kockované",
  dotted: "bodkované",
  floral: "kvetované",
  camo: "maskáčové",
  camouflage: "maskáčové",
  animal: "animal print",
  graphic: "grafické",
  logo_print: "grafické",
  graphic_print: "grafické",
  other: "iný vzor",
  unclear: "jednofarebné",
});

const SEASON_MAP = Object.freeze({
  spring: "jar",
  summer: "leto",
  autumn: "jeseň",
  fall: "jeseň",
  winter: "zima",
  allyear: "celoročne",
  "all year": "celoročne",
  year_round: "celoročne",
});

const LAYER_ROLE_MAP = Object.freeze({
  base: "base_layer",
  mid: "mid_layer",
  outer: "outer_layer",
  base_layer: "base_layer",
  mid_layer: "mid_layer",
  outer_layer: "outer_layer",
  bottom: "bottom",
  footwear: "footwear",
  accessory: "accessory",
  unknown: "",
});

module.exports = {
  ALLOWED_SEASONS,
  ALLOWED_PATTERNS,
  ALLOWED_STYLES,
  ALLOWED_COLORS,
  ALLOWED_FIT,
  ALLOWED_VIBE,
  ALLOWED_LOGO_PROMINENCE,
  ALLOWED_OCCASION_FIT,
  ALLOWED_LAYER_ROLE,
  ALLOWED_IDENTITY_SLOT,
  COLOR_MAP,
  PATTERN_MAP,
  SEASON_MAP,
  LAYER_ROLE_MAP,
};
