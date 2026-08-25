/// Úroveň osobného názoru stylistu na hotový outfit.
enum StylistOpinionLevel {
  excellent,
  good,
  acceptable,
  weak;

  String get wireName => name;
}

/// Jeden faktor deterministického skóre — transparentnosť výpočtu.
class StylistOpinionFactor {
  const StylistOpinionFactor({
    required this.id,
    required this.score,
    required this.weight,
    required this.noteSk,
  });

  /// Napr. `dress_code_fit`, `weather_fit`, `completeness`.
  final String id;
  final double score;
  final double weight;
  final String noteSk;

  double get weightedPoints => score * weight;

  Map<String, dynamic> toPayload() => {
        'id': id,
        'score': score,
        'weight': weight,
        'noteSk': noteSk,
        'weightedPoints': weightedPoints,
      };
}

/// Osobný názor stylistu na výsledný outfit — read-only hodnotenie.
///
/// Opinion nie je Explain: nepopisuje výber, ale hodnotí kvalitu výsledku.
class StylistOpinion {
  const StylistOpinion({
    required this.overallConfidence,
    required this.opinionLevel,
    required this.strengths,
    required this.compromises,
    this.biggestMissingPiece,
    required this.shortOpinionSk,
    required this.factors,
  });

  final int overallConfidence;
  final StylistOpinionLevel opinionLevel;
  final List<String> strengths;
  final List<String> compromises;
  final String? biggestMissingPiece;
  final String shortOpinionSk;
  final List<StylistOpinionFactor> factors;

  bool get isCompromiseHonest =>
      opinionLevel != StylistOpinionLevel.excellent ||
      compromises.isNotEmpty;

  Map<String, dynamic> toPayload() => {
        'overallConfidence': overallConfidence,
        'opinionLevel': opinionLevel.wireName,
        'strengths': strengths,
        'compromises': compromises,
        if (biggestMissingPiece != null)
          'biggestMissingPiece': biggestMissingPiece,
        'shortOpinionSk': shortOpinionSk,
        'factors': factors.map((f) => f.toPayload()).toList(),
      };
}
