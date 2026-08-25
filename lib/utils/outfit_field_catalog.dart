/// Katalóg polí kontextu outfitu — iba význam pre AI, nie pravidlá.
///
/// AI sama rozhodne, ktoré polia sú pre konkrétnu situáciu relevantné.
class OutfitFieldCatalog {
  const OutfitFieldCatalog._();

  static const List<Map<String, String>> fields = [
    {
      'field': 'hourLocal',
      'meaningSk':
          'Hodina začiatku aktivity (0–23). Bez nej nevieme zložiť správny outfit.',
    },
    {
      'field': 'activityLocation',
      'meaningSk':
          'Miesto, kde sa aktivita koná (mesto/oblasť). Pri výlete, turistike, '
          'horách, lese, dovolenke alebo služobnej ceste GPS mesto usera NIE JE '
          'automaticky miesto aktivity.',
    },
    {
      'field': 'activityType',
      'meaningSk':
          'Typ aktivity (turistika, prechádzka, hubovanie, svadba, koncert…). '
          'Ovplyvňuje dress code a obuv.',
    },
    {
      'field': 'activityIntensity',
      'meaningSk':
          'Intenzita (krátka prechádzka vs celodenná túra). Ovplyvňuje vrstvy a obuv.',
    },
    {
      'field': 'duration',
      'meaningSk':
          'Ako dlho bude user vonku. Dôležité pri výlete alebo koncerte.',
    },
    {
      'field': 'dressCode',
      'meaningSk':
          'Formálnosť a typ podujatia (svadba, gala, reštaurácia, koncert v sále…).',
    },
    {
      'field': 'venueType',
      'meaningSk':
          'Vonku vs vnútri (amfiteáter vs filharmónia). Dôležité pri koncerte.',
    },
    {
      'field': 'terrainSurface',
      'meaningSk':
          'Povrch (asfalt, lesná cesta, tráva). Appka už vie wetGround z počasia — '
          'nepýtaj sa usera na dážď.',
    },
  ];

  static List<Map<String, String>> forApi() => fields;
}
