import 'flexible_candidate_matrix_v2.dart';
import 'flexible_outfit_result_v2.dart';
import 'functional_suitability_v1.dart';
import 'outfit_composition_v2.dart';
import 'outfit_edit_plan_v1.dart';
import 'outfit_suitability_policy_v2.dart';
import 'wardrobe_v2_resolver.dart';

/// Applies a Brain-authored edit as one transaction over an exact ID-restored
/// outfit. No intermediate outfit escapes this executor: callers receive a
/// complete frozen candidate set or an empty list.
abstract final class OutfitEditExecutorV1 {
  static V2FlexibleOutfitResult? restoreCurrent({
    required Iterable<ResolvedWardrobeItemV2> wardrobe,
    required Set<String> currentItemIds,
    required V2CandidateMatrixContext context,
  }) {
    if (currentItemIds.isEmpty) return null;
    final resolved = wardrobe
        .where((item) => currentItemIds.contains(item.itemId))
        .toList(growable: false);
    if (resolved.length != currentItemIds.length ||
        resolved.map((item) => item.itemId).toSet().length != resolved.length) {
      return null;
    }
    final hasOnePiece = resolved.any(
      (item) => item.item.bodySlots.contains('full_body'),
    );
    final composition = OutfitCompositionV2(
      template: hasOnePiece
          ? OutfitTemplateV2.onePiece
          : OutfitTemplateV2.separates,
      items: resolved.map(_restoredCompositionItem).toList(growable: false),
    );
    if (composition.compatibilityErrors().isNotEmpty) return null;
    final result = V2FlexibleOutfitResult.fromComposition(
      composition,
      weatherProtectionRequired: context.weatherProtectionRequired,
      minimumFormality: context.minimumFormality,
      requiredFunctions: context.requiredFunctions,
      displayByItemId: <String, Map<String, dynamic>>{
        for (final item in resolved) item.itemId: item.raw,
      },
    );
    return result.validate().isEmpty ? result : null;
  }

  static List<V2FlexibleCandidate> generateCandidates({
    required OutfitEditPlanV1 plan,
    required V2FlexibleOutfitResult current,
    required Iterable<ResolvedWardrobeItemV2> wardrobe,
    required V2CandidateMatrixContext context,
  }) {
    if (plan.intent != OutfitEditIntentV1.editCurrentOutfit ||
        !plan.mutatesCurrentOutfit) {
      return const <V2FlexibleCandidate>[];
    }
    final source = wardrobe.toList(growable: false);
    final ownedById = <String, ResolvedWardrobeItemV2>{
      for (final item in source) item.itemId: item,
    };
    final currentIds = current.items.map((item) => item.itemId).toSet();
    if (!ownedById.keys.toSet().containsAll(currentIds)) {
      return const <V2FlexibleCandidate>[];
    }

    final removedIds = <String>{};
    final preservedIds = <String>{};
    final mutationOperations = <OutfitEditOperationV1>[];
    final targetsBySlot = <OutfitEditSlotV1, List<V2FlexibleOutfitItem>>{};
    for (final operation in plan.operations) {
      final targets = current.items
          .where((item) => _matchesSlot(item, operation.slot))
          .toList(growable: false);
      targetsBySlot[operation.slot] = targets;
      switch (operation.action) {
        case OutfitEditActionV1.preserve:
          preservedIds.addAll(targets.map((item) => item.itemId));
        case OutfitEditActionV1.remove:
          if (targets.isEmpty) return const <V2FlexibleCandidate>[];
          removedIds.addAll(targets.map((item) => item.itemId));
        case OutfitEditActionV1.replace:
          if (targets.isEmpty) return const <V2FlexibleCandidate>[];
          removedIds.addAll(targets.map((item) => item.itemId));
          mutationOperations.add(operation);
        case OutfitEditActionV1.add:
          mutationOperations.add(operation);
      }
    }
    if (removedIds.intersection(preservedIds).isNotEmpty) {
      return const <V2FlexibleCandidate>[];
    }

    final base = current.items
        .where((item) => !removedIds.contains(item.itemId))
        .toList(growable: false);
    final pools = <List<ResolvedWardrobeItemV2>>[];
    for (final operation in mutationOperations) {
      final targets = targetsBySlot[operation.slot] ?? const [];
      final pool = source
          .where((candidate) => !currentIds.contains(candidate.itemId))
          .where((candidate) => _resolvedMatchesSlot(candidate, operation.slot))
          .where(
            (candidate) => _matchesConstraints(candidate, operation, targets),
          )
          .where(
            (candidate) => FunctionalSuitabilityEvaluatorV1.presentationAllowed(
              candidate,
              context.stylingPresentation,
            ),
          )
          .where(
            (candidate) => candidate.item.formality >= context.minimumFormality,
          )
          .where(
            (candidate) =>
                context.requiredOccasions.isEmpty ||
                candidate.item.occasionFit
                    .toSet()
                    .intersection(context.requiredOccasions)
                    .isNotEmpty,
          )
          .take(16)
          .toList(growable: false);
      if (pool.isEmpty) return const <V2FlexibleCandidate>[];
      pools.add(pool);
    }

    final choices = <List<ResolvedWardrobeItemV2>>[];
    _cartesianProduct(
      pools: pools,
      index: 0,
      current: <ResolvedWardrobeItemV2>[],
      output: choices,
      maximum: 512,
    );
    final candidates = <V2FlexibleCandidate>[];
    final seen = <String>{};
    for (final choice in choices) {
      if (choice.map((item) => item.itemId).toSet().length != choice.length) {
        continue;
      }
      final nextItems = <V2FlexibleOutfitItem>[...base];
      for (var index = 0; index < choice.length; index++) {
        final operation = mutationOperations[index];
        final selected = choice[index];
        nextItems.add(_editedOutfitItem(selected, operation));
      }
      if (!nextItems
          .map((item) => item.itemId)
          .toSet()
          .containsAll(preservedIds)) {
        continue;
      }
      final hasOnePiece = nextItems.any(
        (item) => item.item.bodySlots.contains('full_body'),
      );
      final composition = OutfitCompositionV2(
        template: hasOnePiece
            ? OutfitTemplateV2.onePiece
            : OutfitTemplateV2.separates,
        items: nextItems
            .map(
              (item) => OutfitCompositionItemV2(
                itemId: item.itemId,
                item: item.item,
                role: item.compositionRole,
                compositionGroup: item.compositionGroup,
                required: item.requiredness == 'required',
                selectionReason: item.selectionReason,
              ),
            )
            .toList(growable: false),
      );
      if (composition.compatibilityErrors().isNotEmpty) continue;
      final outfit = V2FlexibleOutfitResult.fromComposition(
        composition,
        weatherProtectionRequired: context.weatherProtectionRequired,
        minimumFormality: context.minimumFormality,
        requiredFunctions: context.requiredFunctions,
        displayByItemId: <String, Map<String, dynamic>>{
          for (final item in nextItems) item.itemId: item.display,
        },
      );
      if (outfit.validate().isNotEmpty ||
          !outfit.completeness.weatherComplete ||
          !outfit.completeness.dressCodeComplete ||
          !outfit.completeness.functionalComplete) {
        continue;
      }
      if (outfit.items.any(
        (item) => OutfitSuitabilityPolicyV2.isPhysicallyUnsuitable(
          item.item,
          tempC: OutfitSuitabilityPolicyV2.effectiveTempC(
            tempC: context.tempC,
            feelsLikeC: context.feelsLikeC,
          ),
          seasonKey: context.seasonKey,
          isRainy: context.isRainy || context.weatherProtectionRequired,
          activityType: context.activityType,
        ),
      )) {
        continue;
      }
      final functional = FunctionalSuitabilityEvaluatorV1.assessCandidate(
        outfit: outfit,
        source: source,
        requirements: ActivityFunctionalRequirementsV1(
          activityType: context.activityType,
          outdoor: context.outdoor,
          isRainy: context.isRainy || context.weatherProtectionRequired,
          wetGroundRisk: context.wetGroundRisk,
          minimumFormality: context.decisionFormalityFloor,
          durationMinutes: context.activityDurationMinutes,
          terrain: context.terrain,
          tempC: OutfitSuitabilityPolicyV2.effectiveTempC(
            tempC: context.tempC,
            feelsLikeC: context.feelsLikeC,
          ),
        ),
      );
      if (!functional.selectable) continue;
      final signature = outfit.items.map((item) => item.itemId).toList()
        ..sort();
      if (!seen.add(signature.join('|'))) continue;
      final scoreBreakdown = V2FlexibleOutfitScorer.score(outfit, context);
      scoreBreakdown['functionalCapability'] = functional.scoreAdjustment;
      candidates.add(
        V2FlexibleCandidate(
          candidateId: 'edit_v1_${candidates.length + 1}',
          outfit: outfit,
          score: scoreBreakdown.values.fold(0.0, (sum, value) => sum + value),
          scoreBreakdown: scoreBreakdown,
          functionalAssessment: functional,
        ),
      );
    }
    candidates.sort((left, right) => right.score.compareTo(left.score));
    return List<V2FlexibleCandidate>.unmodifiable(
      candidates.take(context.maxCandidates),
    );
  }

  static OutfitCompositionItemV2 _restoredCompositionItem(
    ResolvedWardrobeItemV2 value,
  ) {
    final item = value.item;
    if (item.bodySlots.contains('feet')) {
      return _compositionItem(value, CompositionRoleV2.core, 'footwear', true);
    }
    if (item.bodySlots.contains('full_body')) {
      return _compositionItem(
        value,
        CompositionRoleV2.core,
        'full_body_core',
        true,
      );
    }
    if (item.bodySlots.contains('lower_body') &&
        !item.bodySlots.contains('upper_body')) {
      return _compositionItem(
        value,
        CompositionRoleV2.core,
        'lower_body_core',
        true,
      );
    }
    if (_isUpperLayerPosition(item.layerPosition)) {
      return _compositionItem(
        value,
        CompositionRoleV2.conditional,
        'layer_${item.layerPosition}',
        false,
      );
    }
    if (item.bodySlots.contains('upper_body')) {
      return _compositionItem(
        value,
        CompositionRoleV2.core,
        'upper_body_core',
        true,
      );
    }
    return _compositionItem(
      value,
      CompositionRoleV2.finishing,
      item.accessoryGroup ?? 'finishing',
      false,
    );
  }

  static OutfitCompositionItemV2 _compositionItem(
    ResolvedWardrobeItemV2 value,
    CompositionRoleV2 role,
    String group,
    bool required,
  ) => OutfitCompositionItemV2(
    itemId: value.itemId,
    item: value.item,
    role: role,
    compositionGroup: group,
    required: required,
    selectionReason: 'restore_exact_current_id',
  );

  static V2FlexibleOutfitItem _editedOutfitItem(
    ResolvedWardrobeItemV2 value,
    OutfitEditOperationV1 operation,
  ) {
    final restored = _restoredCompositionItem(value);
    return V2FlexibleOutfitItem(
      itemId: value.itemId,
      item: value.item,
      compositionRole: restored.role,
      compositionGroup: restored.compositionGroup,
      requiredness: restored.required ? 'required' : 'optional',
      selectionReason:
          'brain_plan_${operation.action.name}_${_slotName(operation.slot)}',
      display: value.raw,
    );
  }

  static bool _matchesSlot(V2FlexibleOutfitItem item, OutfitEditSlotV1 slot) =>
      _itemMatchesSlot(
        bodySlots: item.item.bodySlots,
        layerPosition: item.item.layerPosition,
        accessoryGroup: item.item.accessoryGroup,
        role: item.compositionRole,
        slot: slot,
      );

  static bool _resolvedMatchesSlot(
    ResolvedWardrobeItemV2 item,
    OutfitEditSlotV1 slot,
  ) => _itemMatchesSlot(
    bodySlots: item.item.bodySlots,
    layerPosition: item.item.layerPosition,
    accessoryGroup: item.item.accessoryGroup,
    role: null,
    slot: slot,
  );

  static bool _itemMatchesSlot({
    required List<String> bodySlots,
    required String layerPosition,
    required String? accessoryGroup,
    required CompositionRoleV2? role,
    required OutfitEditSlotV1 slot,
  }) => switch (slot) {
    OutfitEditSlotV1.top =>
      bodySlots.contains('upper_body') &&
          !bodySlots.contains('full_body') &&
          !_isUpperLayerPosition(layerPosition),
    OutfitEditSlotV1.bottom =>
      bodySlots.contains('lower_body') && !bodySlots.contains('full_body'),
    OutfitEditSlotV1.shoes => bodySlots.contains('feet'),
    OutfitEditSlotV1.layers =>
      bodySlots.contains('upper_body') &&
          const <String>{'skin_base', 'mid'}.contains(layerPosition),
    OutfitEditSlotV1.outerwear =>
      bodySlots.contains('upper_body') &&
          const <String>{'outer', 'shell'}.contains(layerPosition),
    OutfitEditSlotV1.fullBody => bodySlots.contains('full_body'),
    OutfitEditSlotV1.accessories =>
      accessoryGroup != null ||
          role == CompositionRoleV2.finishing ||
          role == CompositionRoleV2.accent,
  };

  static bool _matchesConstraints(
    ResolvedWardrobeItemV2 candidate,
    OutfitEditOperationV1 operation,
    List<V2FlexibleOutfitItem> targets,
  ) {
    final constraints = operation.constraints;
    final item = candidate.item;
    if (constraints.type != null &&
        item.canonicalType.toLowerCase() != constraints.type) {
      return false;
    }
    if (constraints.family != null &&
        !_matchesFamily(
          item.canonicalFamily,
          item.canonicalType,
          constraints.family!,
        )) {
      return false;
    }
    final colors = <String>{
      item.colorProfile.primary.family.toLowerCase(),
      if (item.colorProfile.secondary != null)
        item.colorProfile.secondary!.family.toLowerCase(),
      ...item.colorProfile.accents.map((color) => color.family.toLowerCase()),
    };
    if (constraints.color != null && !colors.contains(constraints.color)) {
      return false;
    }
    if (constraints.excludedColor != null &&
        colors.contains(constraints.excludedColor)) {
      return false;
    }
    if (constraints.thermal != null && targets.isNotEmpty) {
      final reference =
          targets
              .map((target) => target.item.warmth)
              .fold<int>(0, (sum, warmth) => sum + warmth) /
          targets.length;
      if (constraints.thermal == OutfitEditThermalV1.warmer &&
          candidate.item.warmth <= reference) {
        return false;
      }
      if (constraints.thermal == OutfitEditThermalV1.cooler &&
          candidate.item.warmth >= reference) {
        return false;
      }
    }
    return true;
  }

  static bool _matchesFamily(
    String canonicalFamily,
    String canonicalType,
    String requestedFamily,
  ) {
    final family = requestedFamily.toLowerCase();
    final type = canonicalType.toLowerCase();
    if (canonicalFamily.toLowerCase() == family || type == family) return true;
    const members = <String, Set<String>>{
      'pants': <String>{'trousers', 'suit_trousers', 'chinos', 'slacks'},
      'joggers': <String>{'joggers', 'sweatpants'},
      'sneakers': <String>{
        'sneakers',
        'running_shoes',
        'training_shoes',
        'basketball_shoes',
        'canvas_shoes',
      },
      'boots': <String>{
        'boots',
        'ankle_boots',
        'chelsea_boots',
        'winter_boots',
      },
      'formal_shoes': <String>{'dress_shoes', 'oxford_shoes', 'derby_shoes'},
      'hoodie': <String>{'hoodie', 'zip_hoodie', 'sweatshirt'},
    };
    return members[family]?.contains(type) ?? false;
  }

  static bool _isUpperLayerPosition(String value) =>
      const <String>{'skin_base', 'mid', 'outer', 'shell'}.contains(value);

  static String _slotName(OutfitEditSlotV1 slot) => switch (slot) {
    OutfitEditSlotV1.top => 'top',
    OutfitEditSlotV1.bottom => 'bottom',
    OutfitEditSlotV1.shoes => 'shoes',
    OutfitEditSlotV1.layers => 'layers',
    OutfitEditSlotV1.outerwear => 'outerwear',
    OutfitEditSlotV1.fullBody => 'full_body',
    OutfitEditSlotV1.accessories => 'accessories',
  };

  static void _cartesianProduct({
    required List<List<ResolvedWardrobeItemV2>> pools,
    required int index,
    required List<ResolvedWardrobeItemV2> current,
    required List<List<ResolvedWardrobeItemV2>> output,
    required int maximum,
  }) {
    if (output.length >= maximum) return;
    if (index >= pools.length) {
      output.add(List<ResolvedWardrobeItemV2>.unmodifiable(current));
      return;
    }
    for (final item in pools[index]) {
      if (current.any((selected) => selected.itemId == item.itemId)) continue;
      current.add(item);
      _cartesianProduct(
        pools: pools,
        index: index + 1,
        current: current,
        output: output,
        maximum: maximum,
      );
      current.removeLast();
      if (output.length >= maximum) return;
    }
  }
}
