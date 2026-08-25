import '../data/stylist_opinion.dart';
import 'stylist_voice_library.dart';

/// Kompozičná vrstva osobnosti stylistu.
///
/// Nerozhoduje o outfite, opinion skóre ani wardrobe analýze. Iba skladá vety
/// do explain textu — všetky formulácie žijú v [StylistVoiceLibrary], tu je len
/// logika, ktorý „slot" sa použije a ako sa vety pospájajú.
abstract final class StylistPersonality {
  /// Úvodná veta explainu — nahrádza doslovné `shortOpinionSk` v texte
  /// (opinion engine ostáva nezmenený, mení sa iba formulácia pre používateľa).
  static String opening({
    required StylistOpinionLevel level,
    required String occasion,
    required bool usedCompromise,
    String? biggestMissingPiece,
    required List<String> missingCategories,
    String? activityType,
    bool suppressOccasionSuffix = false,
    String weatherBucket = '',
  }) {
    final base = StylistVoiceLibrary.pick(
      slot: 'opening',
      level: level,
      activityType: activityType,
      usedCompromise: usedCompromise,
      missingCategories: missingCategories,
      weatherBucket: weatherBucket,
      pool: StylistVoiceLibrary.openings(level),
    );

    if (level == StylistOpinionLevel.weak &&
        biggestMissingPiece != null &&
        biggestMissingPiece.trim().isNotEmpty) {
      return '$base Najviac by pomohlo $biggestMissingPiece.';
    }

    // M8.1: ak bude nasledovať activity flavour (ktorý sám odkazuje na aktivitu),
    // vynecháme suffix „Na X …", aby nevznikla duplicita.
    if (!suppressOccasionSuffix &&
        occasion.trim().isNotEmpty &&
        (level == StylistOpinionLevel.good ||
            level == StylistOpinionLevel.acceptable)) {
      final lower = base.toLowerCase();
      final occLower = occasion.toLowerCase();
      if (!lower.contains(occLower) && !lower.contains('príležitosť')) {
        return switch (level) {
          StylistOpinionLevel.excellent =>
            '$base Na $occasion to podľa mňa sedí.',
          StylistOpinionLevel.good => '$base Na $occasion to funguje.',
          StylistOpinionLevel.acceptable =>
            '$base Na $occasion sa s tým dá ísť.',
          StylistOpinionLevel.weak => base,
        };
      }
    }

    return base;
  }

  /// Predstavenie vybraného outfitu.
  static String outfitIntro({
    required String pieces,
    required StylistOpinionLevel level,
    String? activityType,
    required bool usedCompromise,
    required List<String> missingCategories,
    String weatherBucket = '',
  }) {
    final template = StylistVoiceLibrary.pick(
      slot: 'outfitIntro',
      level: level,
      activityType: activityType,
      usedCompromise: usedCompromise,
      missingCategories: missingCategories,
      weatherBucket: weatherBucket,
      pool: StylistVoiceLibrary.outfitIntros,
    );
    return template.replaceAll('{pieces}', pieces);
  }

  /// Doplnková kompromisná veta (acceptable / weak s compromise).
  static String? compromisePhrase({
    required StylistOpinionLevel level,
    required bool usedCompromise,
    String? activityType,
    required List<String> missingCategories,
    String weatherBucket = '',
  }) {
    if (!usedCompromise) return null;
    if (level == StylistOpinionLevel.excellent) return null;
    return StylistVoiceLibrary.pick(
      slot: 'compromise',
      level: level,
      activityType: activityType,
      usedCompromise: usedCompromise,
      missingCategories: missingCategories,
      weatherBucket: weatherBucket,
      pool: StylistVoiceLibrary.compromises,
    );
  }

  /// Kontextová veta podľa aktivity.
  static String? activityFlavour({
    required String? activityType,
    required StylistOpinionLevel level,
    required bool usedCompromise,
    required List<String> missingCategories,
    String weatherBucket = '',
  }) {
    final pool = StylistVoiceLibrary.activityFlavour(activityType);
    if (pool == null || pool.isEmpty) return null;
    return StylistVoiceLibrary.pick(
      slot: 'activityFlavour',
      level: level,
      activityType: activityType,
      usedCompromise: usedCompromise,
      missingCategories: missingCategories,
      weatherBucket: weatherBucket,
      pool: pool,
    );
  }

  /// Pozitívne zakončenie pre excellent — preferuje activity-špecifickú vetu,
  /// inak siahne po neutrálnom zakončení (bez „Na túto príležitosť to sedí").
  static String excellentClosing({
    required String occasion,
    required StylistOpinionLevel level,
    String? activityType,
    required bool usedCompromise,
    required List<String> missingCategories,
    String weatherBucket = '',
  }) {
    return StylistVoiceLibrary.pick(
      slot: 'excellentClosing',
      level: level,
      activityType: activityType,
      usedCompromise: usedCompromise,
      missingCategories: missingCategories,
      weatherBucket: weatherBucket,
      pool: StylistVoiceLibrary.excellentClosings(activityType),
    );
  }

  /// Odporúčanie doplniť šatník — zakončenie.
  static String? wardrobeClosing({
    required String? gapCategory,
    String? activityType,
    required StylistOpinionLevel level,
    required bool usedCompromise,
    required List<String> missingCategories,
    String weatherBucket = '',
  }) {
    if (gapCategory == null) return null;

    final social = activityType == 'date' ||
        activityType == 'cinema' ||
        activityType == 'dinner';

    return StylistVoiceLibrary.pick(
      slot: 'closing|$gapCategory',
      level: level,
      activityType: activityType,
      usedCompromise: usedCompromise,
      missingCategories: missingCategories,
      weatherBucket: weatherBucket,
      pool: StylistVoiceLibrary.wardrobeClosings(
        gapCategory: gapCategory,
        social: social,
        meeting: activityType == 'meeting',
      ),
    );
  }

  /// Úprimná poznámka o chýbajúcom kúsku (weak).
  static String? weakMissingNote({
    required String piece,
    required StylistOpinionLevel level,
    String? activityType,
    required bool usedCompromise,
    required List<String> missingCategories,
    required bool alreadyMentioned,
    String weatherBucket = '',
  }) {
    if (alreadyMentioned || piece.trim().isEmpty) return null;
    final template = StylistVoiceLibrary.pick(
      slot: 'weakMissing',
      level: level,
      activityType: activityType,
      usedCompromise: usedCompromise,
      missingCategories: missingCategories,
      weatherBucket: weatherBucket,
      pool: StylistVoiceLibrary.weakMissingNotes,
    );
    return template.replaceAll('{piece}', piece);
  }
}
