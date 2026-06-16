part of 'home_screen.dart';

class _HeroOutfitItem {
  final _HeroWearType type;
  final IconData icon;
  final String label;
  final String? brandLine;
  final String? imageUrl;
  final String? categoryKey;
  final String? subCategoryKey;

  /// Firestore dokument šatníka — na výklik „Nový outfit“ / porovnanie kombinácie.
  final String? wardrobeItemId;
  final bool imageProcessing;

  const _HeroOutfitItem({
    required this.type,
    required this.icon,
    required this.label,
    this.brandLine,
    this.imageUrl,
    this.categoryKey,
    this.subCategoryKey,
    this.wardrobeItemId,
    this.imageProcessing = false,
  });
}

class _HeroBannerVM {
  final String description;

  const _HeroBannerVM({
    required this.description,
  });
}

class _HeroTodayState {
  final _HeroBannerVM vm;
  final List<_HeroOutfitItem> outfitItems;
  final String source;
  final String? loadingReason;

  const _HeroTodayState({
    required this.vm,
    required this.outfitItems,
    required this.source,
    this.loadingReason,
  });
}

enum _HeroWearType { top, bottom, shoes, outerwear }

class _TypedWardrobePick {
  final _HeroWearType type;
  final Map<String, dynamic> item;

  const _TypedWardrobePick({required this.type, required this.item});
}

class _HeroOutfitRecommendation {
  final List<_HeroOutfitItem> items;
  final String reason;

  const _HeroOutfitRecommendation({
    required this.items,
    required this.reason,
  });
}

class _StylistFinalReviewSelection {
  final int finalSelectedIndex;
  final OutfitPreview finalSelectedCandidate;
  final String finalSelectedSignature;
  final List<String> finalSelectedItemIds;
  final List<_HeroOutfitItem> heroItems;
  final String reason;

  const _StylistFinalReviewSelection({
    required this.finalSelectedIndex,
    required this.finalSelectedCandidate,
    required this.finalSelectedSignature,
    required this.finalSelectedItemIds,
    required this.heroItems,
    required this.reason,
  });
}

enum _VibeStyle { sporty, clean, street }

class _VibeImageAnalysis {
  final double avgLuminance;
  final double avgSaturation;
  final double contrast;
  final List<int> dominantHueBins;
  final int layeringCount;
  final bool layeredOutfit;
  final bool redAccentImportant;
  final bool denimLightImportant;
  final bool darkBottomImportant;
  final _VibeStyle style;

  const _VibeImageAnalysis({
    required this.avgLuminance,
    required this.avgSaturation,
    required this.contrast,
    required this.dominantHueBins,
    required this.layeringCount,
    required this.layeredOutfit,
    required this.redAccentImportant,
    required this.denimLightImportant,
    required this.darkBottomImportant,
    required this.style,
  });
}

class _VibeRecreationResult {
  final List<_HeroOutfitItem> items;
  final String summary;
  final Map<_HeroWearType, List<_HeroOutfitItem>> candidatePools;
  final String? honestyMessage;
  final List<String> missingPieces;
  final List<String> suggestedFillers;

  const _VibeRecreationResult({
    required this.items,
    required this.summary,
    required this.candidatePools,
    this.honestyMessage,
    this.missingPieces = const [],
    this.suggestedFillers = const [],
  });
}

class _ScoredRaw {
  final Map<String, dynamic> raw;
  final double score;
  const _ScoredRaw({required this.raw, required this.score});
}

class _VibeComposition {
  final List<_TypedWardrobePick> picks;
  final List<String> missingPieces;
  final List<String> suggestedFillers;
  final String? honestyMessage;

  const _VibeComposition({
    required this.picks,
    required this.missingPieces,
    required this.suggestedFillers,
    required this.honestyMessage,
  });
}

class _HomeAiCacheEntry {
  final String signature;
  final _HeroOutfitRecommendation? recommendation;

  const _HomeAiCacheEntry({
    required this.signature,
    required this.recommendation,
  });
}

class _HomeAiRequestContext {
  final DateTime date;
  final _LocalWeather weather;
  final Set<String> excludedItemIds;
  final Set<String> rejectedCombinationSignatures;
  final Set<String> previousOutfitItemIds;
  final bool forceDifferentOutfit;
  final bool isPremiumUser;

  const _HomeAiRequestContext({
    required this.date,
    required this.weather,
    required this.excludedItemIds,
    required this.rejectedCombinationSignatures,
    required this.previousOutfitItemIds,
    required this.forceDifferentOutfit,
    required this.isPremiumUser,
  });
}

class _HomeDayHeroCacheEntry {
  final _HeroTodayState state;
  final String weatherSignature;
  final String wardrobeSignature;
  final bool userModified;
  final String? persistSource;
  final DateTime? updatedAt;

  const _HomeDayHeroCacheEntry({
    required this.state,
    required this.weatherSignature,
    required this.wardrobeSignature,
    this.userModified = false,
    this.persistSource,
    this.updatedAt,
  });
}

class _HomeDayCacheSnapshot {
  final String chosenSource;
  final List<String> itemIds;
  final List<Map<String, dynamic>>? slotMaps;
  final List<_HeroOutfitItem>? heroItems;
  final String reasonText;
  final bool userModified;
  final String persistSource;
  final DateTime updatedAt;
  final String weatherSignature;
  final String wardrobeSignature;
  final String? likedOutfitKey;

  const _HomeDayCacheSnapshot({
    required this.chosenSource,
    required this.itemIds,
    this.slotMaps,
    this.heroItems,
    this.reasonText = '',
    this.userModified = false,
    this.persistSource = 'unknown',
    required this.updatedAt,
    this.weatherSignature = '',
    this.wardrobeSignature = '',
    this.likedOutfitKey,
  });
}

class _LocalWeather {
  final int tempC;
  final bool isRainy;
  final bool isWindy;
  final String seasonLabel; // Jar/Leto/Jeseň/Zima

  /// Kalendárny deň počasia (deň pre výber outfitu / kontext).
  final DateTime calendarDate;
  final bool morningRainSegment;
  final bool afternoonRainSegment;
  final bool eveningRainSegment;

  /// Hodinové teploty segmentov; null → [HomeDailyBriefingRow] odvodí z [tempC].
  final int? briefingMorningC;
  final int? briefingAfternoonC;
  final int? briefingEveningC;

  /// Krátke štítky počasia pre „Prehľad dňa“.
  final String briefingMorningCondition;
  final String briefingAfternoonCondition;
  final String briefingEveningCondition;
  final String outfitWhyWeatherNote;

  /// Ľudsky napísané okná dažďa (napr. „ráno 08:00“) — pre stylistický text, nie hero počasie.
  final String? rainTimeText;

  const _LocalWeather({
    required this.tempC,
    required this.isRainy,
    required this.isWindy,
    required this.seasonLabel,
    required this.calendarDate,
    this.morningRainSegment = false,
    this.afternoonRainSegment = false,
    this.eveningRainSegment = false,
    this.briefingMorningC,
    this.briefingAfternoonC,
    this.briefingEveningC,
    required this.briefingMorningCondition,
    required this.briefingAfternoonCondition,
    required this.briefingEveningCondition,
    this.outfitWhyWeatherNote = '',
    this.rainTimeText,
  });

  static _LocalWeather fromSnapshot(OutfitWeatherDaySnapshot snap) {
    final month = snap.date.month;
    final seasonLabel = (month >= 3 && month <= 5)
        ? 'Jar'
        : (month >= 6 && month <= 8)
        ? 'Leto'
        : (month >= 9 && month <= 11)
        ? 'Jeseň'
        : 'Zima';
    return _LocalWeather(
      tempC: snap.mainChipTempC,
      isRainy: snap.willRain,
      isWindy: snap.isWindy,
      seasonLabel: seasonLabel,
      calendarDate: DateTime(snap.date.year, snap.date.month, snap.date.day),
      morningRainSegment: snap.morningRainSegment,
      afternoonRainSegment: snap.afternoonRainSegment,
      eveningRainSegment: snap.eveningRainSegment,
      briefingMorningC: snap.morningTempC,
      briefingAfternoonC: snap.noonTempC,
      briefingEveningC: snap.eveningTempC,
      briefingMorningCondition: snap.briefingMorningCondition,
      briefingAfternoonCondition: snap.briefingAfternoonCondition,
      briefingEveningCondition: snap.briefingEveningCondition,
      outfitWhyWeatherNote: snap.outfitWhyWeatherNote,
      rainTimeText: snap.rainTimeText,
    );
  }

  static _LocalWeather fallbackFor(DateTime date) {
    // Jednoduché, deterministické hodnoty aby UI fungovalo aj offline.
    final month = date.month;
    final seasonLabel = (month >= 3 && month <= 5)
        ? 'Jar'
        : (month >= 6 && month <= 8)
        ? 'Leto'
        : (month >= 9 && month <= 11)
        ? 'Jeseň'
        : 'Zima';

    int baseTemp;
    if (seasonLabel == 'Zima') {
      baseTemp = 2;
    } else if (seasonLabel == 'Jar') {
      baseTemp = 10;
    } else if (seasonLabel == 'Leto') {
      baseTemp = 24;
    } else {
      baseTemp = 12; // Jeseň
    }

    // jemné kolísanie podľa dňa v mesiaci (-2..+2)
    final delta = (date.day % 5) - 2;
    final tempC = baseTemp + delta;

    // šanca na dážď častejšie na jar/jeseň (deterministicky)
    final rainyMonths = <int>{3, 4, 5, 9, 10, 11};
    final isRainy = rainyMonths.contains(month) && (date.day % 3 == 0);
    final isWindy = date.day % 4 == 0;

    final mt = tempC - 1;
    final at = tempC;
    final et = tempC - 2;
    const morningRainSeg = false;
    final afternoonRainSeg = isRainy;
    const eveningRainSeg = false;
    final d = DateTime(date.year, date.month, date.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isTomorrow = d == today.add(const Duration(days: 1));
    final minT = tempC - 3;
    final maxT = tempC + 1;
    final ux = buildDayWeatherUx(
      date: d,
      isTomorrow: isTomorrow,
      morningTempC: mt,
      afternoonTempC: at,
      eveningTempC: et,
      mainChipTempC: tempC,
      minTempC: minT,
      maxTempC: maxT,
      willRain: isRainy,
      morningRain: morningRainSeg,
      afternoonRain: afternoonRainSeg,
      eveningRain: eveningRainSeg,
      isWindy: isWindy,
      windMorning: isWindy,
      windAfternoon: isWindy,
      windEvening: isWindy,
    );

    return _LocalWeather(
      tempC: tempC,
      isRainy: isRainy,
      isWindy: isWindy,
      seasonLabel: seasonLabel,
      calendarDate: d,
      morningRainSegment: morningRainSeg,
      afternoonRainSegment: afternoonRainSeg,
      eveningRainSegment: eveningRainSeg,
      briefingMorningC: mt,
      briefingAfternoonC: at,
      briefingEveningC: et,
      briefingMorningCondition: BriefingWeatherCondition.briefingUiSk(
        BriefingWeatherCondition.fallback(
          segmentRain: morningRainSeg,
          segmentWindy: isWindy,
          segment: BriefingDaySegment.morning,
        ),
      ),
      briefingAfternoonCondition: BriefingWeatherCondition.briefingUiSk(
        BriefingWeatherCondition.fallback(
          segmentRain: afternoonRainSeg,
          segmentWindy: isWindy,
          segment: BriefingDaySegment.afternoon,
        ),
      ),
      briefingEveningCondition: BriefingWeatherCondition.briefingUiSk(
        BriefingWeatherCondition.fallback(
          segmentRain: eveningRainSeg,
          segmentWindy: isWindy,
          segment: BriefingDaySegment.evening,
        ),
      ),
      outfitWhyWeatherNote: ux.outfitWhyWeatherNote,
      rainTimeText: isRainy ? 'poobedie okolo 17:00' : null,
    );
  }

  String get seasonKey {
    final s = seasonLabel.toLowerCase();
    if (s.contains('jar')) return 'jar';
    if (s.contains('let')) return 'let';
    if (s.contains('jese')) return 'jese';
    return 'zim';
  }

  String get summarySubtitle {
    final parts = <String>[seasonLabel, '$tempC°C'];
    if (isWindy) parts.add('vietor');
    if (isRainy) parts.add('dážď');
    if (!isWindy && !isRainy) parts.add('jasno');
    return parts.join(' • ');
  }
}
