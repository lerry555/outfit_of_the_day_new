import 'wardrobe_item_v2.dart';

enum OutfitTemplateV2 { separates, onePiece }

enum CompositionRoleV2 { core, conditional, functional, finishing, accent }

class OutfitCompositionItemV2 {
  const OutfitCompositionItemV2({
    required this.itemId,
    required this.item,
    required this.role,
    required this.compositionGroup,
    required this.required,
    required this.selectionReason,
  });
  final String itemId, compositionGroup, selectionReason;
  final WardrobeItemV2 item;
  final CompositionRoleV2 role;
  final bool required;
}

class OutfitCompletenessV2 {
  const OutfitCompletenessV2({
    required this.coreComplete,
    required this.weatherComplete,
    required this.dressCodeComplete,
    required this.functionalComplete,
    required this.enhanced,
    required this.gaps,
  });
  final bool coreComplete,
      weatherComplete,
      dressCodeComplete,
      functionalComplete,
      enhanced;
  final List<String> gaps;
}

class OutfitCompositionV2 {
  const OutfitCompositionV2({required this.template, required this.items});
  final OutfitTemplateV2 template;
  final List<OutfitCompositionItemV2> items;
  OutfitCompletenessV2 completeness({
    required bool weatherProtectionRequired,
    required int minimumFormality,
    Set<String> requiredFunctions = const {},
  }) {
    bool hasSlot(String s) => items.any(
      (x) => x.role == CompositionRoleV2.core && x.item.bodySlots.contains(s),
    );
    final footwear = hasSlot('feet');
    final silhouette = template == OutfitTemplateV2.onePiece
        ? hasSlot('full_body')
        : hasSlot('upper_body') && hasSlot('lower_body');
    final weather =
        !weatherProtectionRequired ||
        items.any(
          (x) =>
              x.item.layerPosition == 'outer' ||
              x.item.layerPosition == 'shell',
        );
    final dress = items
        .where((x) => x.required)
        .every((x) => x.item.formality >= minimumFormality);
    final providedFunctions = items
        .expand((x) => x.item.outfitFunctions)
        .toSet();
    final functional = providedFunctions.containsAll(requiredFunctions);
    final gaps = <String>[
      if (!silhouette) 'core_silhouette',
      if (!footwear) 'footwear',
      if (!weather) 'weather_protection',
      if (!dress) 'dress_code',
      if (!functional) 'functional',
    ];
    return OutfitCompletenessV2(
      coreComplete: silhouette && footwear,
      weatherComplete: weather,
      dressCodeComplete: dress,
      functionalComplete: functional,
      enhanced: items.any((x) => !x.required),
      gaps: gaps,
    );
  }

  List<String> compatibilityErrors() {
    final errors = <String>[];
    final groups = <String, List<OutfitCompositionItemV2>>{};
    for (final x in items) {
      final g = x.item.canonicalFamily == 'bag'
          ? 'primary_bag'
          : x.item.canonicalType == 'watch'
          ? 'watch'
          : x.item.canonicalType.contains('necklace')
          ? 'necklace'
          : x.item.canonicalType == 'belt'
          ? 'belt'
          : null;
      if (g != null) (groups[g] ??= []).add(x);
    }
    for (final g in ['watch', 'necklace', 'belt', 'primary_bag']) {
      if ((groups[g]?.length ?? 0) > 1) errors.add('max_per_group:$g');
    }
    final tie = items.any((x) => x.item.canonicalType == 'tie'),
        bow = items.any((x) => x.item.canonicalType == 'bow_tie');
    if (tie && bow) errors.add('mutually_exclusive:neckwear');
    return errors;
  }
}
