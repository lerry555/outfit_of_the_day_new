/// Vlastnosti aktivity odvodené z textu — nie whitelist konkrétnych aktivít.
class ActivityTraits {
  const ActivityTraits({
    this.outdoor = false,
    this.indoor = false,
    this.travel = false,
    this.requiresTerrain = false,
    this.requiresWeather = true,
    this.routineLocal = false,
    this.venueBound = false,
    this.poiDependent = false,
    this.activityLabelSk,
    required this.confidence,
    required this.reason,
  });

  /// Vonkajšia aktivita — počasie a lokalita silno závisia od miesta.
  final bool outdoor;

  /// Typicky interiér / bežná denná rutina (práca, kino…).
  final bool indoor;

  /// Cestovanie / iná krajina alebo región.
  final bool travel;

  /// Terén ovplyvňuje outfit (hory, les, trail…).
  final bool requiresTerrain;

  /// Outfit potrebuje počasie (takmer vždy pri outfit požiadavke).
  final bool requiresWeather;

  /// GPS mesto stačí (práca, obed, kino v aktuálnom meste).
  final bool routineLocal;

  /// Aktivita viazaná na miesto v meste, ale GPS mesto je OK (kino, divadlo).
  final bool venueBound;

  /// Bod záujmu bez jednoznačného mesta (ZOO, aquapark…).
  final bool poiDependent;

  /// Krátky popis detekovanej aktivity pre otázku.
  final String? activityLabelSk;

  final double confidence;
  final String reason;

  /// True ak GPS NESTAČÍ — potrebujeme explicitnú lokalitu.
  bool get requiresSpecificLocation {
    if (routineLocal && !outdoor && !travel && !poiDependent) {
      return false;
    }
    if (venueBound && !outdoor && !travel && !poiDependent) {
      return false;
    }
    return outdoor || requiresTerrain || travel || poiDependent;
  }
}
