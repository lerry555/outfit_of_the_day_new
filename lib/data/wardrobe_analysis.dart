/// Medzera v šatníku — chýbajúca kategória pre ideálny outfit.
class WardrobeGap {
  const WardrobeGap({
    required this.category,
    required this.reason,
    required this.blocksIdealOutfit,
    required this.explanationSk,
  });

  /// Napr. `shirt`, `formal_shoes`, `hiking_pants`, `rain_jacket`.
  final String category;

  /// Napr. `wedding`, `interview`, `hike`, `rain`.
  final String reason;

  final bool blocksIdealOutfit;

  final String explanationSk;

  String get wireKey => '$category:$reason';

  Map<String, dynamic> toPayload() => {
        'category': category,
        'reason': reason,
        'blocksIdealOutfit': blocksIdealOutfit,
        'explanationSk': explanationSk,
      };

  factory WardrobeGap.fromPayload(Map<String, dynamic> raw) {
    return WardrobeGap(
      category: (raw['category'] ?? '').toString(),
      reason: (raw['reason'] ?? '').toString(),
      blocksIdealOutfit: raw['blocksIdealOutfit'] == true,
      explanationSk: (raw['explanationSk'] ?? '').toString(),
    );
  }
}

/// Výsledok gap analýzy po výbere outfitu — pre explain a budúci affiliate.
class WardrobeAnalysis {
  const WardrobeAnalysis({
    this.usedCompromise = false,
    this.missingItems = const [],
    this.compromiseItems = const [],
  });

  final bool usedCompromise;
  final List<WardrobeGap> missingItems;
  final List<String> compromiseItems;

  Map<String, dynamic> toPayload() => {
        'usedCompromise': usedCompromise,
        'missingItems': missingItems.map((g) => g.toPayload()).toList(),
        'compromiseItems': compromiseItems,
      };

  factory WardrobeAnalysis.fromPayload(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return const WardrobeAnalysis();
    final gapsRaw = raw['missingItems'];
    final gaps = <WardrobeGap>[];
    if (gapsRaw is List) {
      for (final entry in gapsRaw) {
        if (entry is Map) {
          gaps.add(WardrobeGap.fromPayload(Map<String, dynamic>.from(entry)));
        }
      }
    }
    final compromiseRaw = raw['compromiseItems'];
    final compromiseItems = <String>[];
    if (compromiseRaw is List) {
      compromiseItems.addAll(
        compromiseRaw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty),
      );
    }
    return WardrobeAnalysis(
      usedCompromise: raw['usedCompromise'] == true,
      missingItems: gaps,
      compromiseItems: compromiseItems,
    );
  }
}
