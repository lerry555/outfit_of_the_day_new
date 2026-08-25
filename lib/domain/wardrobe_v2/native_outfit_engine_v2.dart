import 'outfit_composition_v2.dart';
import 'outfit_suitability_policy_v2.dart';
import 'wardrobe_v2_resolver.dart';

class NativeOutfitRequestV2 {
  const NativeOutfitRequestV2({
    this.weatherProtectionRequired = false,
    this.minimumFormality = 1,
    this.requiredFunctions = const {},
    this.preferOnePiece = false,
    this.tempC,
    this.feelsLikeC,
    this.eveningTempC,
    this.activityType = '',
    this.requestedItemIds = const {},
    this.formalityFloor,
    this.forbiddenCanonicalTypes = const {},
  });
  final bool weatherProtectionRequired, preferOnePiece;
  final int minimumFormality;
  final int? tempC, feelsLikeC, eveningTempC, formalityFloor;
  final String activityType;
  final Set<String> requiredFunctions, requestedItemIds, forbiddenCanonicalTypes;

  int get resolvedFormalityFloor => formalityFloor ?? minimumFormality;

  int? get effectiveTempC =>
      OutfitSuitabilityPolicyV2.effectiveTempC(tempC: tempC, feelsLikeC: feelsLikeC);
}

/// Provider/UI-independent native V2 composition engine.
abstract final class NativeOutfitEngineV2 {
  static OutfitCompositionV2? compose(
    Iterable<ResolvedWardrobeItemV2> wardrobe,
    NativeOutfitRequestV2 request,
  ) {
    final available = wardrobe
        .where((x) => x.item.formality >= request.minimumFormality)
        .toList(growable: false);
    bool isSelected(List<OutfitCompositionItemV2> selected, String id) =>
        selected.any((chosen) => chosen.itemId == id);

    bool physicallyUnsuitable(ResolvedWardrobeItemV2 value) {
      if (request.forbiddenCanonicalTypes.contains(value.item.canonicalType)) {
        return true;
      }
      return OutfitSuitabilityPolicyV2.isPhysicallyUnsuitable(
        value.item,
        tempC: request.effectiveTempC,
        isRainy: request.weatherProtectionRequired,
        activityType: request.activityType,
      );
    }

    ResolvedWardrobeItemV2? pick(
      bool Function(ResolvedWardrobeItemV2) test, {
      int Function(ResolvedWardrobeItemV2)? rank,
      bool allowUnsafeFallback = true,
    }) {
      ResolvedWardrobeItemV2? best;
      var bestRank = 1 << 20;
      for (final value in available) {
        if (!test(value)) continue;
        if (physicallyUnsuitable(value)) continue;
        var r = rank?.call(value) ?? 0;
        if (request.requestedItemIds.contains(value.itemId)) r -= 50;
        if (r < bestRank) {
          bestRank = r;
          best = value;
        }
      }
      if (best != null || !allowUnsafeFallback) return best;
      for (final value in available) {
        if (!test(value)) continue;
        if (request.forbiddenCanonicalTypes.contains(value.item.canonicalType)) {
          continue;
        }
        return value;
      }
      return null;
    }

    bool isUpperLayer(ResolvedWardrobeItemV2 x) {
      if (x.item.bodySlots.contains('full_body')) return false;
      if (x.item.bodySlots.contains('feet')) return false;
      if (x.item.bodySlots.contains('lower_body') &&
          !x.item.bodySlots.contains('upper_body')) {
        return false;
      }
      return x.item.bodySlots.contains('upper_body');
    }

    bool wantsLayer(String layer, ResolvedWardrobeItemV2 candidate) {
      if (request.requiredFunctions.any(
        candidate.item.outfitFunctions.contains,
      )) {
        return true;
      }
      final temp = request.effectiveTempC;
      if (layer == 'skin_base') {
        return temp != null && temp <= 6;
      }
      if (layer == 'mid') {
        if (temp == null) return true;
        if (request.eveningTempC != null &&
            request.eveningTempC! <= 12 &&
            temp <= 24 &&
            candidate.item.warmth <= 6) {
          return true;
        }
        return temp <= 16;
      }
      if (layer == 'outer' || layer == 'shell') {
        if (request.weatherProtectionRequired) return true;
        if (temp != null && temp <= 12) return true;
        final formalOuter =
            candidate.item.formality >= 7 && candidate.item.warmth <= 5;
        if (formalOuter && request.resolvedFormalityFloor >= 6 &&
            (temp == null || temp <= 24)) {
          return true;
        }
        if (formalOuter &&
            request.resolvedFormalityFloor >= 5 &&
            temp != null &&
            temp <= 18) {
          return true;
        }
        return false;
      }
      return false;
    }

    int layerWarmthRank(ResolvedWardrobeItemV2 value) {
      final temp = request.effectiveTempC;
      final type = value.item.canonicalType.toLowerCase();
      var rank = 0;
      if (temp != null) {
        final target = temp >= 24
            ? 3
            : temp >= 18
            ? 4
            : temp >= 10
            ? 6
            : 8;
        rank += (value.item.warmth - target).abs();
      }
      if (request.weatherProtectionRequired) {
        final rainCapable =
            type.contains('rain') ||
            value.item.outfitFunctions.contains('weather_protection');
        if (rainCapable && !type.contains('winter')) rank -= 12;
        if (type.contains('track')) rank += 8;
      }
      if (request.resolvedFormalityFloor >= 5) {
        if (type.contains('suit_jacket') || type.contains('blazer')) {
          rank -= 8;
        }
        if (type.contains('track')) rank += 10;
      }
      return rank;
    }

    final onePiece = pick(
      (x) => x.item.bodySlots.contains('full_body'),
      rank: (x) => request.resolvedFormalityFloor >= 5
          ? -x.item.formality
          : 0,
    );
    final upper = pick(
      (x) =>
          x.item.bodySlots.contains('upper_body') &&
          !const {'mid', 'outer', 'shell'}.contains(x.item.layerPosition),
      rank: (x) => request.resolvedFormalityFloor >= 5
          ? -x.item.formality
          : 0,
    );
    final lower = pick(
      (x) =>
          x.item.bodySlots.contains('lower_body') &&
          x.item.layerPosition != 'skin_base',
      rank: (x) => request.resolvedFormalityFloor >= 5
          ? -x.item.formality
          : 0,
    );
    final footwear = pick(
      (x) => x.item.bodySlots.contains('feet'),
      rank: (x) => OutfitSuitabilityPolicyV2.footwearPreferenceRank(
        x.item,
        activityType: request.activityType,
        formalityFloorValue: request.resolvedFormalityFloor,
        isRainy: request.weatherProtectionRequired,
      ),
    );
    final useOnePiece =
        onePiece != null &&
        (request.preferOnePiece || upper == null || lower == null);
    if (footwear == null ||
        (!useOnePiece && (upper == null || lower == null))) {
      return null;
    }
    final selected = <OutfitCompositionItemV2>[];
    void add(
      ResolvedWardrobeItemV2 value,
      CompositionRoleV2 role,
      String group,
      bool required,
      String reason,
    ) => selected.add(
      OutfitCompositionItemV2(
        itemId: value.itemId,
        item: value.item,
        role: role,
        compositionGroup: group,
        required: required,
        selectionReason: reason,
      ),
    );
    if (useOnePiece) {
      add(
        onePiece,
        CompositionRoleV2.core,
        'full_body_core',
        true,
        'one_piece_template',
      );
    } else {
      add(
        upper!,
        CompositionRoleV2.core,
        'upper_body_core',
        true,
        'separates_template',
      );
      add(
        lower!,
        CompositionRoleV2.core,
        'lower_body_core',
        true,
        'separates_template',
      );
    }
    add(
      footwear,
      CompositionRoleV2.core,
      'footwear',
      true,
      'core_foot_support',
    );

    for (final layer in ['skin_base', 'mid', 'outer', 'shell']) {
      final candidate = pick(
        (x) =>
            x.item.layerPosition == layer &&
            !isSelected(selected, x.itemId) &&
            (layer == 'skin_base' || isUpperLayer(x)),
        rank: layerWarmthRank,
      );
      if (candidate != null && wantsLayer(layer, candidate)) {
        add(
          candidate,
          CompositionRoleV2.conditional,
          'layer_$layer',
          false,
          'weather_or_function',
        );
      }
    }

    final accessoryGroups = <String>{};
    for (final candidate in available) {
      final group = candidate.item.accessoryGroup;
      if (group == null || group.isEmpty || accessoryGroups.contains(group)) {
        continue;
      }
      if (selected.any((x) => x.itemId == candidate.itemId)) continue;
      add(
        candidate,
        CompositionRoleV2.finishing,
        group,
        false,
        'optional_enhancement',
      );
      accessoryGroups.add(group);
      if (selected.length >= (useOnePiece ? 6 : 7)) {
        break;
      }
    }
    final result = OutfitCompositionV2(
      template: useOnePiece
          ? OutfitTemplateV2.onePiece
          : OutfitTemplateV2.separates,
      items: selected,
    );
    return result.compatibilityErrors().isEmpty ? result : null;
  }
}
