import '../data/stylist_opinion.dart';

/// Deterministické slovenské šablóny pre [StylistOpinion.shortOpinionSk].
abstract final class StylistOpinionPhrases {
  static String shortOpinion({
    required StylistOpinionLevel level,
    required String occasionLabel,
    String? biggestMissingPiece,
    required bool usedCompromise,
    required bool weatherConcern,
  }) {
    final occasion = occasionLabel.trim().isEmpty ? 'túto príležitosť' : occasionLabel;

    final base = switch (level) {
      StylistOpinionLevel.excellent =>
        'Tento outfit by som na $occasion pokojne odporučil.',
      StylistOpinionLevel.good =>
        'Celkovo dobrá voľba na $occasion. Pár detailov by sa dalo vylepšiť, ale sedí.',
      StylistOpinionLevel.acceptable =>
        'Z toho, čo máš v šatníku, je to rozumný kompromis na $occasion. Nie je to ideál, ale dá sa.',
      StylistOpinionLevel.weak => biggestMissingPiece != null
          ? 'Úprimne, nie som z neho úplne presvedčený na $occasion. Najviac by pomohlo $biggestMissingPiece.'
          : 'Úprimne, nie som z neho úplne presvedčený na $occasion.',
    };

    final parts = <String>[base];

    if (usedCompromise &&
        level != StylistOpinionLevel.excellent &&
        level != StylistOpinionLevel.weak) {
      parts.add(
        'Nie je to úplne ideálna voľba, ale je to najlepšie, čo sa dá z tvojho šatníka.',
      );
    }

    if (weatherConcern) {
      parts.add('Na dnešné počasie by som niečo ešte upravil.');
    }

    return parts.join(' ');
  }

  static String? strengthForFactor(String factorId) {
    return switch (factorId) {
      'dress_code_fit' => 'Vrch a spodok ladia s dress code',
      'weather_fit' => 'Praktické na dnešné počasie',
      'color_harmony' => 'Farby spolu dobre fungujú',
      'activity_identity' => 'Outfit sedí na aktivitu',
      'completeness' => 'Šatník pokrýva väčšinu požiadaviek',
      _ => null,
    };
  }

  static String compromiseForItem(String itemLabel) {
    return '$itemLabel nie je ideál, ale je najlepší dostupný.';
  }

  static String? missingPieceLabel(String category) {
    return switch (category) {
      'shirt' => 'košeľa',
      'polo' => 'polo alebo košeľa',
      'formal_shoes' => 'formálna obuv',
      'rain_jacket' => 'nepremokavá vrstva',
      'hiking_pants' => 'turistické nohavice',
      _ => null,
    };
  }
}
