/**
 * Katalóg možných polí kontextu outfitu — slovník významov pre AI.
 * NIE JE to checklist povinných otázok.
 */
const OUTFIT_FIELD_CATALOG = [
  {
    field: "hourLocal",
    meaningSk:
      "Hodina začiatku aktivity (0–23). Bez nej nevieme zložiť správny outfit.",
  },
  {
    field: "activityLocation",
    meaningSk:
      "Miesto aktivity (mesto/oblasť). Pri výlete, turistike, horách, lese, " +
      "dovolenke alebo služobnej ceste GPS mesto usera NIE JE automaticky " +
      "miesto aktivity.",
  },
  {
    field: "activityType",
    meaningSk:
      "Typ aktivity (turistika, prechádzka, hubovanie, svadba, koncert…).",
  },
  {
    field: "activityIntensity",
    meaningSk:
      "Intenzita (krátka prechádzka vs celodenná túra). Ovplyvňuje vrstvy a obuv.",
  },
  {
    field: "duration",
    meaningSk: "Ako dlho bude user vonku.",
  },
  {
    field: "dressCode",
    meaningSk:
      "Formálnosť a typ podujatia (svadba, gala, reštaurácia, koncert v sále…).",
  },
  {
    field: "venueType",
    meaningSk: "Vonku vs vnútri (amfiteáter vs filharmónia).",
  },
  {
    field: "terrainSurface",
    meaningSk:
      "Povrch (asfalt, lesná cesta, tráva). Appka už vie wetGround z počasia — " +
      "nepýtaj sa usera na dážď.",
  },
];

module.exports = {OUTFIT_FIELD_CATALOG};
