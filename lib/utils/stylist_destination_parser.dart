import '../data/parsed_destination.dart';
import 'dress_code_resolver.dart';
import 'slovak_city_locative.dart';
import 'stylist_destination_intelligence.dart';

/// Cieľové mesto/ miesto z konverzácie v stylist chate (nie GPS usera).
class StylistDestinationParser {
  const StylistDestinationParser._();

  static const String destinationClarificationMessage =
      'Kam presne idete? Zostanete tam, kde ste, alebo idete niekam inde?';

  /// Krajiny / kontinenty / príliš všeobecné regióny. Pri nich sa NESMIE
  /// generovať outfit ani volať weather (počasie závisí od konkrétneho mesta).
  /// Kľúč = tvar v texte (vrátane skloňovania a ASCII), hodnota = zobrazovaný
  /// názov krajiny/regiónu.
  static const Map<String, String> _broadRegions = {
    'usa': 'USA',
    'u.s.a': 'USA',
    'u.s.a.': 'USA',
    'united states': 'USA',
    'amerika': 'Amerika',
    'ameriky': 'Amerika',
    'amerike': 'Amerika',
    'ameriku': 'Amerika',
    'america': 'Amerika',
    'slovensko': 'Slovensko',
    'slovenska': 'Slovensko',
    'slovensku': 'Slovensko',
    'cesko': 'Česko',
    'česko': 'Česko',
    'ceska': 'Česko',
    'česka': 'Česko',
    'cesku': 'Česko',
    'česku': 'Česko',
    'cechy': 'Česko',
    'čechy': 'Česko',
    'taliansko': 'Taliansko',
    'talianska': 'Taliansko',
    'taliansku': 'Taliansko',
    'chorvatsko': 'Chorvátsko',
    'chorvátsko': 'Chorvátsko',
    'chorvatska': 'Chorvátsko',
    'chorvátska': 'Chorvátsko',
    'chorvatsku': 'Chorvátsko',
    'chorvátsku': 'Chorvátsko',
    'rakusko': 'Rakúsko',
    'rakúsko': 'Rakúsko',
    'rakuska': 'Rakúsko',
    'rakúska': 'Rakúsko',
    'rakusku': 'Rakúsko',
    'rakúsku': 'Rakúsko',
    'europa': 'Európa',
    'európa': 'Európa',
    'europy': 'Európa',
    'európy': 'Európa',
    'europe': 'Európa',
    'európe': 'Európa',
    'nemecko': 'Nemecko',
    'nemecka': 'Nemecko',
    'nemecku': 'Nemecko',
    'francuzsko': 'Francúzsko',
    'francúzsko': 'Francúzsko',
    'francuzska': 'Francúzsko',
    'francúzska': 'Francúzsko',
    'francuzsku': 'Francúzsko',
    'francúzsku': 'Francúzsko',
    'spanielsko': 'Španielsko',
    'španielsko': 'Španielsko',
    'spanielska': 'Španielsko',
    'španielska': 'Španielsko',
    'spanielsku': 'Španielsko',
    'španielsku': 'Španielsko',
    'madarsko': 'Maďarsko',
    'maďarsko': 'Maďarsko',
    'madarska': 'Maďarsko',
    'maďarska': 'Maďarsko',
    'polsko': 'Poľsko',
    'poľsko': 'Poľsko',
    'polska': 'Poľsko',
    'poľska': 'Poľsko',
    'grecko': 'Grécko',
    'grécko': 'Grécko',
    'grecka': 'Grécko',
    'grécka': 'Grécko',
    'anglicko': 'Anglicko',
    'anglicka': 'Anglicko',
    'anglicku': 'Anglicko',
    'irsko': 'Írsko',
    'írsko': 'Írsko',
    'irska': 'Írsko',
    'írska': 'Írsko',
    'azia': 'Ázia',
    'ázia': 'Ázia',
    'azie': 'Ázia',
    'ázie': 'Ázia',
    'afrika': 'Afrika',
    'afriky': 'Afrika',
    'afrike': 'Afrika',
    'australia': 'Austrália',
    'austrália': 'Austrália',
    'austrálie': 'Austrália',
    'austrálii': 'Austrália',
    // Európa / sever
    'nórsko': 'Nórsko',
    'norsko': 'Nórsko',
    'nórska': 'Nórsko',
    'norska': 'Nórsko',
    'nórsku': 'Nórsko',
    'norsku': 'Nórsko',
    'švédsko': 'Švédsko',
    'svedsko': 'Švédsko',
    'švédska': 'Švédsko',
    'svedska': 'Švédsko',
    'švédsku': 'Švédsko',
    'svedsku': 'Švédsko',
    'fínsko': 'Fínsko',
    'finsko': 'Fínsko',
    'fínska': 'Fínsko',
    'finska': 'Fínsko',
    'fínsku': 'Fínsko',
    'finsku': 'Fínsko',
    'dánsko': 'Dánsko',
    'dansko': 'Dánsko',
    'dánska': 'Dánsko',
    'danska': 'Dánsko',
    'dánsku': 'Dánsko',
    'dansku': 'Dánsko',
    'island': 'Island',
    'islandu': 'Island',
    'islande': 'Island',
    'turecko': 'Turecko',
    'turecka': 'Turecko',
    'turecku': 'Turecko',
    'portugalsko': 'Portugalsko',
    'portugalska': 'Portugalsko',
    'portugalsku': 'Portugalsko',
    'holandsko': 'Holandsko',
    'holandska': 'Holandsko',
    'holandsku': 'Holandsko',
    'belgicko': 'Belgicko',
    'belgicka': 'Belgicko',
    'belgicku': 'Belgicko',
    'švajčiarsko': 'Švajčiarsko',
    'svajciarsko': 'Švajčiarsko',
    'švajčiarska': 'Švajčiarsko',
    'svajciarska': 'Švajčiarsko',
    'švajčiarsku': 'Švajčiarsko',
    'svajciarsku': 'Švajčiarsko',
    'veľká británia': 'Veľká Británia',
    'velka britania': 'Veľká Británia',
    'veľkej británie': 'Veľká Británia',
    'velkej britanie': 'Veľká Británia',
    'británia': 'Veľká Británia',
    'britania': 'Veľká Británia',
    'británie': 'Veľká Británia',
    'britanie': 'Veľká Británia',
    'rusko': 'Rusko',
    'ruska': 'Rusko',
    'rusku': 'Rusko',
    'ukrajina': 'Ukrajina',
    'ukrajiny': 'Ukrajina',
    'ukrajine': 'Ukrajina',
    // Afrika / Blízky východ
    'egypt': 'Egypt',
    'egypta': 'Egypt',
    'egypte': 'Egypt',
    'maroko': 'Maroko',
    'maroka': 'Maroko',
    'maroku': 'Maroko',
    'keňa': 'Keňa',
    'kena': 'Keňa',
    'kene': 'Keňa',
    'južná afrika': 'Južná Afrika',
    'juzna afrika': 'Južná Afrika',
    'južnej afriky': 'Južná Afrika',
    'juznej afriky': 'Južná Afrika',
    'izrael': 'Izrael',
    'izraela': 'Izrael',
    'izraeli': 'Izrael',
    'sae': 'SAE',
    'spojené arabské emiráty': 'SAE',
    'spojene arabske emiraty': 'SAE',
    'spojených arabských emirátov': 'SAE',
    'spojenych arabskych emiratov': 'SAE',
    'emirátov': 'SAE',
    'emiratov': 'SAE',
    'emiráty': 'SAE',
    'emiraty': 'SAE',
    'maldivy': 'Maldivy',
    'filipíny': 'Filipíny',
    'filipiny': 'Filipíny',
    // Amerika
    'kanada': 'Kanada',
    'kanady': 'Kanada',
    'kanade': 'Kanada',
    'mexiko': 'Mexiko',
    'mexika': 'Mexiko',
    'mexiku': 'Mexiko',
    'brazília': 'Brazília',
    'brazilia': 'Brazília',
    'brazílie': 'Brazília',
    'brazilie': 'Brazília',
    'argentína': 'Argentína',
    'argentina': 'Argentína',
    'argentíny': 'Argentína',
    'argentiny': 'Argentína',
    'čile': 'Čile',
    'chile': 'Čile',
    'peru': 'Peru',
    'kolumbia': 'Kolumbia',
    'kolumbie': 'Kolumbia',
    // Ázia / Oceánia
    'japonsko': 'Japonsko',
    'japonska': 'Japonsko',
    'japonsku': 'Japonsko',
    'čína': 'Čína',
    'cina': 'Čína',
    'číny': 'Čína',
    'ciny': 'Čína',
    'číne': 'Čína',
    'cine': 'Čína',
    'india': 'India',
    'indie': 'India',
    'thajsko': 'Thajsko',
    'thajska': 'Thajsko',
    'thajsku': 'Thajsko',
    'vietnam': 'Vietnam',
    'vietnamu': 'Vietnam',
    'indonézia': 'Indonézia',
    'indonezia': 'Indonézia',
    'indonézie': 'Indonézia',
    'indonezie': 'Indonézia',
    'nový zéland': 'Nový Zéland',
    'novy zeland': 'Nový Zéland',
    'nového zélandu': 'Nový Zéland',
    'noveho zelandu': 'Nový Zéland',
    'zéland': 'Nový Zéland',
    'zeland': 'Nový Zéland',
    'južná kórea': 'Južná Kórea',
    'juzna korea': 'Južná Kórea',
    'južnej kórey': 'Južná Kórea',
    'juznej korey': 'Južná Kórea',
  };

  /// Zobrazovaný názov v lokáli pre otázku „Do ktorého mesta {…} idete?“.
  static const Map<String, String> _broadRegionLocativePhrase = {
    'USA': 'v USA',
    'Amerika': 'v Amerike',
    'Slovensko': 'na Slovensku',
    'Česko': 'v Česku',
    'Taliansko': 'v Taliansku',
    'Chorvátsko': 'v Chorvátsku',
    'Rakúsko': 'v Rakúsku',
    'Európa': 'v Európe',
    'Nemecko': 'v Nemecku',
    'Francúzsko': 'vo Francúzsku',
    'Španielsko': 'v Španielsku',
    'Maďarsko': 'v Maďarsku',
    'Poľsko': 'v Poľsku',
    'Grécko': 'v Grécku',
    'Anglicko': 'v Anglicku',
    'Írsko': 'v Írsku',
    'Ázia': 'v Ázii',
    'Afrika': 'v Afrike',
    'Austrália': 'v Austrálii',
    'Nórsko': 'v Nórsku',
    'Švédsko': 'vo Švédsku',
    'Fínsko': 'vo Fínsku',
    'Dánsko': 'v Dánsku',
    'Island': 'na Islande',
    'Turecko': 'v Turecku',
    'Portugalsko': 'v Portugalsku',
    'Holandsko': 'v Holandsku',
    'Belgicko': 'v Belgicku',
    'Švajčiarsko': 'vo Švajčiarsku',
    'Veľká Británia': 'vo Veľkej Británii',
    'Rusko': 'v Rusku',
    'Ukrajina': 'na Ukrajine',
    'Egypt': 'v Egypte',
    'Maroko': 'v Maroku',
    'Keňa': 'v Keni',
    'Južná Afrika': 'v Južnej Afrike',
    'Kanada': 'v Kanade',
    'Mexiko': 'v Mexiku',
    'Brazília': 'v Brazílii',
    'Argentína': 'v Argentíne',
    'Čile': 'v Čile',
    'Peru': 'v Peru',
    'Kolumbia': 'v Kolumbii',
    'Japonsko': 'v Japonsku',
    'Čína': 'v Číne',
    'India': 'v Indii',
    'Thajsko': 'v Thajsku',
    'Vietnam': 'vo Vietname',
    'Indonézia': 'v Indonézii',
    'Nový Zéland': 'na Novom Zélande',
    'SAE': 'v SAE',
    'Izrael': 'v Izraeli',
    'Južná Kórea': 'v Južnej Kórei',
    'Maldivy': 'na Maldivách',
    'Filipíny': 'na Filipínach',
  };

  /// True, ak je hodnota krajina/kontinent/príliš všeobecný región (nie mesto).
  static bool isBroadRegion(String? value) {
    if (value == null) return false;
    return _broadRegions.containsKey(value.toLowerCase().trim());
  }

  /// Ak konverzácia spomína cestu do krajiny/regiónu (a nie konkrétne mesto),
  /// vráti zobrazovaný názov krajiny/regiónu (napr. „USA“), inak null.
  static String? broadRegionInConversation(String text) {
    final blob = text.toLowerCase();
    if (blob.trim().isEmpty) return null;
    // Dlhšie výrazy majú prednosť („južná afrika" pred „afrika").
    final entries = _broadRegions.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final entry in entries) {
      // Hranica slova bez závislosti na \b (kvôli diakritike): pred/za výrazom
      // nesmie byť písmeno.
      final pattern = RegExp(
        r'(?:^|[^0-9a-záäčďéíĺľňóôřšťúýž])' +
            RegExp.escape(entry.key) +
            r'(?![0-9a-záäčďéíĺľňóôřšťúýž])',
        caseSensitive: false,
      );
      if (pattern.hasMatch(blob)) return entry.value;
    }
    return null;
  }

  /// Doplňujúca otázka, keď máme len krajinu/región (nie mesto).
  static String broadRegionCityQuestion(String region) {
    final loc = _broadRegionLocativePhrase[region] ?? 'v $region';
    return 'Do ktorého mesta $loc idete? Počasie sa môže veľmi líšiť podľa mesta.';
  }

  /// True ak text spomína destináciu bez jednoznačného mesta — flow musí
  /// zastaviť ešte pred weather/AI/outfit.
  static bool shouldBlockForBroadRegion(
    String text, {
    Set<String> exclude = const <String>{},
  }) {
    final parsed = parseDestination(text, exclude: exclude);
    return parsed.needsClarification && parsed.hasTravelDestination;
  }

  /// Typovo vedomé parsovanie destinácie (M9).
  static ParsedDestination parseDestination(
    String text, {
    Set<String> exclude = const <String>{},
  }) =>
      StylistDestinationIntelligence.parse(text, exclude: exclude);

  /// True ak [city] je skutočné mesto (nie krajina ani skloňovací omyl).
  static bool _isExplicitCity(String? city) {
    if (city == null) return false;
    if (!isPlausibleDestination(city)) return false;
    if (isBroadRegion(city)) return false;
    if (_isCountryDeclensionArtifact(city)) return false;
    return true;
  }

  /// Zachytí falošné „mesto" vzniknuté zo skloňovania krajiny
  /// (napr. „Brazílie" → „Brazíli", „Spojených arabských emirátov" → „Spojených").
  static bool _isCountryDeclensionArtifact(String place) {
    final lower = place.toLowerCase().trim();
    if (lower.isEmpty) return false;
    if (_broadRegions.containsKey(lower)) return true;
    for (final key in _broadRegions.keys) {
      if (key == lower) return true;
      if (key.startsWith('$lower ') || lower.startsWith('$key ')) return true;
      if (key.startsWith(lower) || lower.startsWith(key)) {
        if ((key.length - lower.length).abs() <= 3) return true;
      }
    }
    return false;
  }

  /// Verejné API pre QA runner — true ak je hodnota skutočné mesto.
  static bool isResolvableCity(String? city) => _isExplicitCity(city);

  /// True ak je mesto dostatočne isté na počasie (nie krátky neznámy token).
  static bool isConfidentResolvableCity(String? city) {
    if (!isResolvableCity(city)) return false;
    final name = city!.trim();
    final lower = name.toLowerCase();
    if (isKnownCityShortcut(lower)) return true;
    final normalized = normalizePlacePhrase(name).toLowerCase();
    for (final value in _knownCityShortcuts.values) {
      final core = value.split(',').first.trim().toLowerCase();
      if (normalized == core) return true;
    }
    final words = name.split(RegExp(r'\s+'));
    if (words.length >= 2) {
      if (words.any((w) => isKnownCityShortcut(w.toLowerCase()))) return true;
      if (_looksLikeMultiWordCityName(name)) return true;
    }
    return false;
  }

  /// Dvojslovné (a viac) geografické mená — nie atrakcie („Santa Barbara“ áno,
  /// „Universal Studios“ nie).
  static bool _looksLikeMultiWordCityName(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.length < 2) return false;
    const blockedLast = {
      'studios',
      'world',
      'park',
      'palace',
      'valley',
      'festival',
      'hotel',
      'land',
      'kingdom',
      'arena',
      'resort',
      'lagoon',
      'dome',
      'bay',
      'flags',
      'wonders',
      'landia',
      'parku',
      'centra',
      'centrum',
      'mall',
      'place',
      'gate',
      'waves',
    };
    const blockedFirst = {
      'universal',
      'mystery',
      'ocean',
      'golden',
      'green',
      'crystal',
      'sunset',
      'horizon',
      'star',
      'vin',
      'grand',
      'blue',
      'hoteli',
      'parku',
      'hotelu',
    };
    if (blockedFirst.contains(words.first.toLowerCase())) return false;
    if (blockedLast.contains(words.last.toLowerCase())) return false;
    return words.every((w) => w.length >= 3 && _startsWithUpper(w));
  }

  /// Optimalizačný zoznam známych miest — nie hlavná klasifikačná logika.
  static bool isKnownCityShortcut(String lower) {
    final blob = lower.trim();
    if (blob.isEmpty) return false;
    if (_knownCityShortcuts.containsKey(blob)) return true;
    for (final key in _knownCityShortcuts.keys) {
      if (blob == key) return true;
      if (key.length >= 3 &&
          (blob.startsWith(key) || key.startsWith(blob)) &&
          (blob.length - key.length).abs() <= 4) {
        return true;
      }
    }
    for (final value in _knownCityShortcuts.values) {
      final core = value.split(',').first.trim().toLowerCase();
      if (blob == core) return true;
      if (core.length >= 3 &&
          (blob.startsWith(core) || core.startsWith(blob)) &&
          (blob.length - core.length).abs() <= 4) {
        return true;
      }
    }
    return false;
  }

  /// Normalizuje extrahovanú frázu na nominatív (pre intelligence vrstvu).
  static String normalizePlacePhrase(String phrase) {
    var place = _keepCityWords(phrase.trim());
    place = _stripTrailingStopWords(place);
    place = _toNominativeCity(place);
    return _titleCase(place);
  }

  /// Mesto pre počasie z konverzácie — deleguje na [parseDestination].
  static String? inferFromConversation(
    String text, {
    Set<String> exclude = const <String>{},
  }) =>
      parseDestination(text, exclude: exclude).weatherCity;

  /// Surová extrakcia kandidáta na mesto (bez typovej klasifikácie).
  static String? inferCityCandidate(
    String text, {
    Set<String> exclude = const <String>{},
  }) =>
      _inferCityCandidateBody(text, exclude: exclude);

  static const Map<String, String> _knownCityShortcuts = {
      'galway': 'Galway, Ireland',
      'london': 'London, United Kingdom',
      'žilina': 'Žilina',
      'zilina': 'Žilina',
      'žiliny': 'Žilina',
      'ziliny': 'Žilina',
      'žiline': 'Žilina',
      'ziline': 'Žilina',
      'dublin': 'Dublin, Ireland',
      'bratislava': 'Bratislava',
      'košice': 'Košice',
      'kosice': 'Košice',
      'košiciach': 'Košice',
      'kosiciach': 'Košice',
      'košic': 'Košice',
      'kosic': 'Košice',
      'martin': 'Martin',
      'bratislav': 'Bratislava',
      'tatry': 'Tatry',
      'vysoké tatry': 'Vysoké Tatry',
      'vysoke tatry': 'Vysoké Tatry',
      'ružbach': 'Vyšné Ružbachy',
      'ruzbach': 'Vyšné Ružbachy',
      'rajeckej lesn': 'Rajecká Lesná',
      'rajecka lesn': 'Rajecká Lesná',
      'piešťan': 'Piešťany',
      'piestan': 'Piešťany',
      'poprad': 'Poprad',
      'nitr': 'Nitra',
      'trnav': 'Trnava',
      'trenčín': 'Trenčín',
      'trencin': 'Trenčín',
      'prešov': 'Prešov',
      'presov': 'Prešov',
      'banská bystrica': 'Banská Bystrica',
      'banska bystrica': 'Banská Bystrica',
      'mníchov': 'Mníchov',
      'mnichov': 'Mníchov',
      'munich': 'Mníchov',
      'münchen': 'Mníchov',
      'munchen': 'Mníchov',
      'viedeň': 'Viedeň',
      'vieden': 'Viedeň',
      'vienna': 'Viedeň',
      'wien': 'Viedeň',
      'praha': 'Praha',
      'prahe': 'Praha',
      'praze': 'Praha',
      'prague': 'Praha',
      'brno': 'Brno',
      'brne': 'Brno',
      'brna': 'Brno',
      'ostrava': 'Ostrava',
      'berlín': 'Berlín',
      'berlin': 'Berlín',
      'norimberg': 'Norimberg',
      'nürnberg': 'Norimberg',
      'nurnberg': 'Norimberg',
      'nuremberg': 'Norimberg',
      'budapešť': 'Budapešť',
      'budapest': 'Budapešť',
      'krakov': 'Krakov',
      'krakow': 'Krakov',
      'varšava': 'Varšava',
      'varsava': 'Varšava',
      'warszawa': 'Varšava',
      'londýn': 'London',
      'londyn': 'London',
      'londýna': 'London',
      'londyna': 'London',
      'washington': 'Washington',
      'washingtonu': 'Washington',
      'new york': 'New York',
      'new yorku': 'New York',
      'los angeles': 'Los Angeles',
      'miami': 'Miami',
      'toronto': 'Toronto',
      'toronta': 'Toronto',
      'vancouver': 'Vancouver',
      'vancouveru': 'Vancouver',
      'mexico city': 'Mexico City',
      'rio de janeiro': 'Rio de Janeiro',
      'são paulo': 'São Paulo',
      'sao paulo': 'São Paulo',
      'são paule': 'São Paulo',
      'buenos aires': 'Buenos Aires',
      'santiago': 'Santiago',
      'santiaga': 'Santiago',
      'lima': 'Lima',
      'limy': 'Lima',
      'limu': 'Lima',
      'mumbai': 'Mumbai',
      'mumbaia': 'Mumbai',
      'mumbaji': 'Mumbai',
      'chamonix': 'Chamonix',
      'chamonixu': 'Chamonix',
      'jamajka': 'Kingston, Jamaica',
      'jamajke': 'Kingston, Jamaica',
      'jamajku': 'Kingston, Jamaica',
      'bali': 'Bali',
      'balí': 'Bali',
      'split': 'Split',
      'splite': 'Split',
      'splitu': 'Split',
      'bogotá': 'Bogotá',
      'bogota': 'Bogotá',
      'bogoty': 'Bogotá',
      'lisabon': 'Lisabon',
      'lisabonu': 'Lisabon',
      'lisbon': 'Lisabon',
      'brusel': 'Brusel',
      'bruselu': 'Brusel',
      'brussels': 'Brusel',
      'zürich': 'Zürich',
      'zurich': 'Zürich',
      'zürichu': 'Zürich',
      'zurichu': 'Zürich',
      'oslo': 'Oslo',
      'osla': 'Oslo',
      'stockholm': 'Stockholm',
      'stockholmu': 'Stockholm',
      'kodaň': 'Kodaň',
      'kodan': 'Kodaň',
      'kodane': 'Kodaň',
      'copenhagen': 'Kodaň',
      'helsinki': 'Helsinki',
      'helsínk': 'Helsinki',
      'helsink': 'Helsinki',
      'reykjavik': 'Reykjavik',
      'reykjavíku': 'Reykjavik',
      'atény': 'Atény',
      'ateny': 'Atény',
      'atén': 'Atény',
      'athens': 'Atény',
      'istanbul': 'Istanbul',
      'istanbulu': 'Istanbul',
      'dubaj': 'Dubaj',
      'dubaja': 'Dubaj',
      'dubai': 'Dubaj',
      'tel aviv': 'Tel Aviv',
      'tel avivu': 'Tel Aviv',
      'káhira': 'Káhira',
      'kahira': 'Káhira',
      'káhiry': 'Káhira',
      'kahiry': 'Káhira',
      'cairo': 'Káhira',
      'marrakesh': 'Marrakesh',
      'marrakeshu': 'Marrakesh',
      'cape town': 'Cape Town',
      'cape townu': 'Cape Town',
      'nairobi': 'Nairobi',
      'tokio': 'Tokio',
      'tokia': 'Tokio',
      'tokyo': 'Tokio',
      'soul': 'Soul',
      'soulu': 'Soul',
      'seoul': 'Soul',
      'peking': 'Peking',
      'pekingu': 'Peking',
      'beijing': 'Peking',
      'šanghaj': 'Šanghaj',
      'sanghaj': 'Šanghaj',
      'šanghaja': 'Šanghaj',
      'sanghaja': 'Šanghaj',
      'shanghai': 'Šanghaj',
      'bangkok': 'Bangkok',
      'bangkoku': 'Bangkok',
      'hanoi': 'Hanoi',
      'hanoja': 'Hanoi',
      'singapur': 'Singapur',
      'singapuru': 'Singapur',
      'singapore': 'Singapur',
      'sydney': 'Sydney',
      'melbourne': 'Melbourne',
      'auckland': 'Auckland',
      'aucklandu': 'Auckland',
      'paríž': 'Paríž',
      'pariz': 'Paríž',
      'paris': 'Paríž',
      'rím': 'Rím',
      'ríma': 'Rím',
      'miláno': 'Miláno',
      'milano': 'Miláno',
      'milána': 'Miláno',
      'milana': 'Miláno',
      'benátky': 'Benátky',
      'benatky': 'Benátky',
      'barcelona': 'Barcelona',
      'barcelony': 'Barcelona',
      'madrid': 'Madrid',
      'madridu': 'Madrid',
      'amsterdam': 'Amsterdam',
      'viedne': 'Viedeň',
      'prahy': 'Praha',
      'košíc': 'Košice',
      'budapešti': 'Budapešť',
      'liptovsk': 'Liptovský Mikuláš',
      'liptovsky': 'Liptovský Mikuláš',
      'liptovský mikuláš': 'Liptovský Mikuláš',
      'liptovsky mikulas': 'Liptovský Mikuláš',
    };

  static String? _inferCityCandidateBody(
    String text, {
    Set<String> exclude = const <String>{},
  }) {
    final blob = text.toLowerCase();
    if (blob.trim().isEmpty) return null;

    final excludeLower = exclude.map((e) => e.toLowerCase().trim()).toSet();
    bool isExcluded(String value) =>
        excludeLower.contains(value.toLowerCase().trim());

    for (final entry in _knownCityShortcuts.entries) {
      if (blob.contains(entry.key) && !isExcluded(entry.value)) {
        return entry.value;
      }
    }

    // Holá odpoveď používateľa: keď je celá správa len názov mesta (bez „do/v“),
    // napr. ako reakcia na otázku „v ktorom meste to je?“. Berieme 1–2 slová.
    final bare = blob.trim();
    final bareWords = bare.split(RegExp(r'\s+'));
    if (bareWords.length <= 2 &&
        bare.length >= 3 &&
        isPlausibleDestination(bare) &&
        !isBroadRegion(bare) &&
        !_isNoisePlace(bare)) {
      // Holá odpoveď býva v nominatíve („Washington“), skloňovanie neriešime.
      final result = _titleCase(bare);
      if (!isExcluded(result)) return result;
    }

    // Pozn.: zámerne NEhľadáme mesto po „na“ — v slovenčine „na“ uvádza skoro
    // vždy akciu, nie mesto („na vystúpenie“, „na koncert“, „na rande“). Mestá
    // chodia cez „do“ / „v“ / „vo“. Tým sa vyhneme falošným „miestam“.
    // Regex púšťame na PÔVODNOM texte (so zachovaným veľkým písmenom), aby sme
    // vedeli odlíšiť pokračovanie názvu mesta („Vysoké Tatry“) od náhodných
    // ďalších slov („Washingtonu potrebujem“).
    final matches = RegExp(
      r'(?:\bv|\bvo|\bdo|\bpri)\s+'
      r'([a-záäčďéíĺľňóôřšťúýž][a-záäčďéíĺľňóôřšťúýž-]{1,}'
      // Druhé slovo nesmie byť predložka/častica („do USA do New Yorku" → nie
      // „USA do", ale samostatne „USA" a potom „New Yorku").
      r'(?:\s+(?!do\b|na\b|v\b|vo\b|pri\b|od\b|a\b|so\b|s\b|'
      r'zajtra\b|dnes\b|budeme\b|idem\b|ideme\b|potrebujem\b)'
      r'[a-záäčďéíĺľňóôřšťúýž][a-záäčďéíĺľňóôřšťúýž-]{1,})?)',
      caseSensitive: false,
    ).allMatches(text);
    for (final m in matches) {
      final raw = (m.group(1) ?? '').trim();
      var place = _keepCityWords(raw);
      place = _stripTrailingStopWords(place);
      place = _toNominativeCity(place);
      if (place.length >= 3 &&
          isPlausibleDestination(place) &&
          !isBroadRegion(place) &&
          !_isCountryDeclensionArtifact(place) &&
          !_isNoisePlace(place)) {
        final result = _titleCase(place);
        if (!isExcluded(result)) {
          if (isConfidentResolvableCity(result)) return result;
        }
      }
    }
    for (final m in matches) {
      final raw = (m.group(1) ?? '').trim();
      var place = _keepCityWords(raw);
      place = _stripTrailingStopWords(place);
      place = _toNominativeCity(place);
      if (place.length >= 3 &&
          isPlausibleDestination(place) &&
          !isBroadRegion(place) &&
          !_isCountryDeclensionArtifact(place) &&
          !_isNoisePlace(place)) {
        final result = _titleCase(place);
        if (!isExcluded(result)) return result;
      }
    }
    return null;
  }

  /// Z viacslovného zachytenia necháme len skutočný názov mesta. Prvé slovo je
  /// vždy súčasťou názvu; ďalšie slová pripojíme len ak vyzerajú ako vlastné
  /// meno (začínajú veľkým písmenom, napr. „Vysoké Tatry“, „New York“). Tým
  /// odrežeme náhodné slovesá/podstatné mená za mestom („Washingtonu potrebujem“
  /// → „Washingtonu“).
  static String _keepCityWords(String raw) {
    final words = raw.split(RegExp(r'\s+'));
    if (words.isEmpty) return raw;
    final kept = <String>[words.first];
    for (final word in words.skip(1)) {
      if (word.isNotEmpty && _startsWithUpper(word)) {
        kept.add(word);
      } else {
        break;
      }
    }
    return kept.join(' ');
  }

  static bool _startsWithUpper(String word) {
    if (word.isEmpty) return false;
    final first = word[0];
    return first.toUpperCase() == first && first.toLowerCase() != first;
  }

  /// Prevedie bežný skloňovaný tvar mesta na čistý názov, aby geokóder dostal
  /// nominatív (napr. „Washingtonu“ → „Washington“, „Washingtone“ →
  /// „Washington“). Zámerne konzervatívne: iba dlhšie slová a jednoznačné
  /// koncovky, aby sme nepokazili krátke názvy ako „Nice“, „Baku“, „Oslo“.
  static String _toNominativeCity(String city) {
    final words = city.trim().split(RegExp(r'\s+'));
    final out = words.map(_wordToNominative).toList();
    return out.join(' ');
  }

  static String _wordToNominative(String word) {
    // Skloňovanie riešime len pri vlastných menách (veľké začiatočné písmeno),
    // aby sme nepokazili bežné podstatné mená ako „práce“/„školy“ (tie sú malým
    // písmenom a padnú do noise filtra). Krátke názvy („Nice“, „Baku“, „Oslo“)
    // chránime dĺžkovou poistkou.
    if (word.length <= 4 || !_startsWithUpper(word)) return word;
    final lower = word.toLowerCase();
    // Genitív po „do“ (do Washingtonu, do New Yorku) a lokál po „v/vo“
    // (vo Washingtone).
    if (lower.endsWith('u') || lower.endsWith('e')) {
      return word.substring(0, word.length - 1);
    }
    return word;
  }

  static String _stripTrailingStopWords(String place) {
    const stop = {
      'od',
      'do',
      'o',
      'a',
      'ale',
      'so',
      's',
      'bude',
      'hra',
      'hrá',
      'zajtra',
      'dnes',
      'kde',
      'ideme',
      'idem',
      'je',
      'to',
      'na',
      'v',
      'vo',
      'okolo',
      'po',
      'pri',
      'cez',
      'meste',
      'mestom',
      'mesta',
      'centre',
      'centra',
      'centrom',
      'ulici',
      'ulicou',
      'rano',
      'ráno',
      'vecer',
      'večer',
      'poobede',
      'predpoludnim',
      'predpoludním',
      'sa',
    };
    var words = place.split(RegExp(r'\s+'));
    while (words.length > 1 && stop.contains(words.last.toLowerCase())) {
      words = words.sublist(0, words.length - 1);
    }
    return words.join(' ');
  }

  /// Skutočné mesto/oblasť — nie „divadla so ženou“, „výlet“ atď.
  static bool isPlausibleDestination(String? value) {
    if (value == null || value.trim().isEmpty) return false;
    final lower = value.toLowerCase().trim();
    if (_isNoisePlace(lower)) return false;
    if (RegExp(r'\b(so|s)\s+(zen|manzel|manžel|priateľ|priatel|muz|muž)\b')
        .hasMatch(lower)) {
      return false;
    }
    const activityHints = [
      'divadl',
      'kino',
      'reštaur',
      'restaur',
      'zmrzlin',
      'koncert',
      'klub',
      'bar ',
      'amfik',
      'amfite',
      'festival',
      'stadion',
      'štadión',
      'hala',
      'hale',
      'sála',
      'sále',
      'sala',
      'sale',
      'zenop',
      'ženou',
      'manzelk',
      'manželk',
      'vystúp',
      'vystup',
      'spevák',
      'spevak',
      'speváč',
      'spevac',
      'kapel',
      'predstaven',
      'akci',
      'jedneho',
      'jedného',
      'jednej',
    ];
    if (activityHints.any((h) => _tokenInText(lower, h))) return false;
    final wordCount = lower.split(RegExp(r'\s+')).length;
    if (wordCount > 3) return false;
    return true;
  }

  /// User chce konkrétny outfit zo šatníka (nie len všeobecné rady).
  static bool userWantsOutfitFromWardrobe(String text) {
    final blob = text.toLowerCase();
    if (blob.contains('outfit')) {
      if (RegExp(
        r'(?:ďakuj|dakuj|vďak|vdak|páči|paci|super|skvel)',
        caseSensitive: false,
      ).hasMatch(blob) &&
          !RegExp(r'potrebujem|chcem|neviem', caseSensitive: false)
              .hasMatch(blob)) {
        return false;
      }
      return true;
    }
    if (blob.contains('čo si oblie') || blob.contains('co si oblie')) {
      return true;
    }
    if (RegExp(r'co\s+si\s+.*\bseba\b', caseSensitive: false).hasMatch(blob)) {
      return true;
    }
    if (blob.contains('čo na seba') ||
        blob.contains('co na seba') ||
        blob.contains('dat na seba') ||
        blob.contains('dať na seba') ||
        blob.contains('cosi obliect') ||
        blob.contains('cos obliect')) {
      return true;
    }
    if (blob.contains('obliec') || blob.contains('obliect')) return true;
    if (blob.contains('neviem') &&
        (blob.contains('oblie') ||
            blob.contains('čo si') ||
            blob.contains('co si') ||
            blob.contains('na seba') ||
            blob.contains('obl'))) {
      return true;
    }
    if (blob.contains('ukáž') &&
        (blob.contains('kombin') || blob.contains('šatník') || blob.contains('satnik'))) {
      return true;
    }
    if (blob.contains('prech') &&
        (blob.contains('oblie') ||
            blob.contains('neviem') ||
            blob.contains('na seba') ||
            blob.contains('co si') ||
            blob.contains('čo si'))) {
      return true;
    }
    if ((blob.contains('hor') || blob.contains('hory')) &&
        (blob.contains('neviem') ||
            blob.contains('oblie') ||
            blob.contains('porad') ||
            blob.contains('na seba') ||
            blob.contains('co si') ||
            blob.contains('čo si'))) {
      return true;
    }
    if (blob.contains('elan') || blob.contains('elán')) return true;
    if ((blob.contains('idem') || blob.contains('ideme')) &&
        (blob.contains('koncert') ||
            blob.contains('festival') ||
            blob.contains('divadl'))) {
      return true;
    }
    if ((blob.contains('divadl') || blob.contains('kino') || blob.contains('koncert')) &&
        (blob.contains('idem') ||
            blob.contains('ideme') ||
            blob.contains('chcem') ||
            blob.contains('chceme') ||
            blob.contains('pôjd') ||
            blob.contains('pojd') ||
            blob.contains('neviem'))) {
      return true;
    }
    return false;
  }

  static String? occasionStyleHint(String conversationText) {
    return DressCodeResolver.styleHintFor(conversationText);
  }

  static String clarificationPrompt({
    required String gpsCityShort,
    String? styleHint,
  }) {
    final prefix = (styleHint ?? '').trim();
    final intro = prefix.isNotEmpty ? '$prefix ' : '';
    final place = SlovakCityLocative.inCity(gpsCityShort);
    return '${intro}O koľkej vyrazíš? Počasie beriem pre $place — ak ideš '
        'inde, napíš mi mesto.';
  }

  /// Máme čas + miesto na vygenerovanie outfitu. Miesto = explicitné z textu
  /// ALEBO GPS mesto (default, ak user nepovedal iné).
  static bool hasOutfitGenerationContext({
    required String conversationText,
    required int? hourLocal,
    String? inferredDestination,
    String? gpsCityLabel,
  }) {
    if (hourLocal == null) return false;
    final inferred = (inferredDestination ??
            inferFromConversation(conversationText) ??
            '')
        .trim();
    if (inferred.isNotEmpty && isPlausibleDestination(inferred)) return true;
    final gps = (gpsCityLabel ?? '').split(',').first.trim();
    return gps.isNotEmpty;
  }

  static bool userConfirmedGpsCity(String conversationText, String gpsCityLabel) {
    final gps = gpsCityLabel.trim();
    if (gps.isEmpty) return false;
    final cityCore = gps.split(',').first.trim().toLowerCase();
    if (cityCore.isEmpty) return false;
    final blob = conversationText.toLowerCase();
    return blob.contains('v $cityCore') ||
        blob.contains('vo $cityCore') ||
        blob.contains('ano v $cityCore') ||
        blob.contains('áno v $cityCore') ||
        (blob.contains('ostan') && blob.contains(cityCore));
  }

  /// True len keď nemáme ANI GPS mesto ANI explicitné mesto z konverzácie.
  static bool needsDestinationForOutfit({
    required String conversationText,
    String? inferredDestination,
    String? gpsCityLabel,
  }) {
    if ((inferredDestination ?? '').trim().isNotEmpty &&
        isPlausibleDestination(inferredDestination)) {
      return false;
    }
    final gps = (gpsCityLabel ?? '').split(',').first.trim();
    if (gps.isNotEmpty) return false;

    final blob = conversationText.toLowerCase();
    const outingWords = [
      'rande',
      'večer',
      'vecer',
      'reštaur',
      'restaur',
      'von ',
      'prechádz',
      'prechadz',
      'outfit',
      'divadl',
      'kino',
      'koncert',
    ];
    return outingWords.any(blob.contains);
  }

  static bool _isNoisePlace(String place) {
    final lower = place.toLowerCase().trim();
    const noise = [
      'irsku',
      'irsko',
      'slovensku',
      'slovensko',
      'seba',
      'sebe',
      'amfik',
      'amfiku',
      'amfite',
      'festival',
      'hoteli',
      'hotelu',
      'parku',
      'parkom',
      'komplexe',
      'komplexu',
      'resorte',
      'resortu',
      'rytmus',
      'rytmusa',
      'rytmicu',
      'rytmusovi',
      'elan',
      'elán',
      'kabat',
      'kabát',
      'desmod',
      'zajtra',
      'dnes',
      'vylet',
      'výlet',
      'prechadzku',
      'prechádzku',
      'prechadzke',
      'prechádzke',
      'prechadzku zajtra',
      // Aktivity / krajina — nie mestá („do hory“, „v horách“…)
      'hora',
      'hory',
      'horu',
      'horou',
      'horach',
      'hore',
      'hor',
      'horami',
      'prirode',
      'prírode',
      'prirody',
      'prírody',
      'priroda',
      'príroda',
      'les',
      'lese',
      'lesa',
      'lesom',
      'vonku',
      'rande',
      'veceru',
      'večeru',
      'vecer',
      'večer',
      'restauracii',
      'reštaurácii',
      'vychadzku',
      'výchadzku',
      'potulku',
      'divadl',
      'divadle',
      'kino',
      'koncert',
      'meste',
      'mesta',
      'centre',
      'centra',
      'centrom',
      'centrum',
      'center',
      'stred',
      'zenop',
      'ženou',
      'manzelk',
      'manželk',
      // App/wardrobe nouns — „do šatníka“ is not a travel destination.
      'satnik',
      'satnika',
      'satniku',
      'satnikom',
      'šatník',
      'šatníka',
      'šatníku',
      'šatníkom',
      'koselie',
      'kosela',
      'košele',
      'košeli',
      'košeľa',
      'setu',
      // Názvy dní v týždni (vrátane skloňovaných tvarov) – nie sú to mestá,
      // chytal ich regex „v stredu“, „v piatok“…
      'pondelok',
      'pondelka',
      'utorok',
      'utorka',
      'streda',
      'stredu',
      'stredou',
      'stvrtok',
      'štvrtok',
      'stvrtka',
      'štvrtka',
      'piatok',
      'piatka',
      'sobota',
      'sobotu',
      'sobotou',
      'nedela',
      'nedeľa',
      'nedelu',
      'nedeľu',
      'nedelou',
      'nedeľou',
      'vikend',
      'víkend',
      'vikende',
      'víkende',
      // Aktivita / miesto výkonu práce — nie geografické mesto
      'práca',
      'prace',
      'práce',
      'roboty',
      'robote',
      'zamestnanie',
      'zamestnania',
      'kancelária',
      'kancelaria',
      'kancelárii',
      'kancelarii',
      'škola',
      'skola',
      'školy',
      'skoly',
    ];
    if (noise.contains(lower)) return true;
    return noise.any((token) => _tokenInText(lower, token));
  }

  /// Krátke tokeny (napr. „elan“) nesmú padať na substring v inom slove
  /// („Ireland“ obsahuje „elan“, ale nie je to kapela Elán).
  static bool _tokenInText(String text, String token) {
    final t = token.trim();
    if (t.isEmpty) return false;
    if (t.endsWith(' ')) return text.contains(t);
    if (t.length <= 4) {
      return RegExp(r'\b' + RegExp.escape(t) + r'\b').hasMatch(text);
    }
    return text.contains(t);
  }

  static String _titleCase(String input) {
    if (input.isEmpty) return input;
    return input[0].toUpperCase() + input.substring(1);
  }
}
