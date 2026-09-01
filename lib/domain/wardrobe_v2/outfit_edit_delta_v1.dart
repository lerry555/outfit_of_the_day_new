import 'flexible_outfit_result_v2.dart';
import 'outfit_edit_plan_v1.dart';

/// Immutable, deterministic account of what actually changed between the
/// exact restored outfit and the accepted frozen candidate.
class OutfitEditDeltaV1 {
  const OutfitEditDeltaV1._({
    required this.addedItemIds,
    required this.removedItemIds,
    required this.preservedItemIds,
    required this.changedAfterItemIds,
    required this.actualFocusSlot,
    required this.followUpTextSk,
  });

  final Set<String> addedItemIds;
  final Set<String> removedItemIds;
  final Set<String> preservedItemIds;
  final Set<String> changedAfterItemIds;
  final String? actualFocusSlot;
  final String followUpTextSk;

  static OutfitEditDeltaV1 between({
    required V2FlexibleOutfitResult before,
    required V2FlexibleOutfitResult after,
    required OutfitEditPlanV1 plan,
  }) {
    final beforeById = <String, V2FlexibleOutfitItem>{
      for (final item in before.items) item.itemId: item,
    };
    final afterById = <String, V2FlexibleOutfitItem>{
      for (final item in after.items) item.itemId: item,
    };
    final beforeIds = beforeById.keys.toSet();
    final afterIds = afterById.keys.toSet();
    final addedIds = afterIds.difference(beforeIds);
    final removedIds = beforeIds.difference(afterIds);
    final preservedIds = beforeIds.intersection(afterIds);
    final clauses = <String>[];
    final handled = <String>{};

    for (final operation in plan.operations.where((value) => value.mutates)) {
      final key = '${operation.slot.name}:${operation.action.name}';
      if (!handled.add(key)) continue;
      final added = addedIds
          .map((id) => afterById[id]!)
          .where((item) => _matchesSlot(item, operation.slot))
          .toList(growable: false);
      final removed = removedIds
          .map((id) => beforeById[id]!)
          .where((item) => _matchesSlot(item, operation.slot))
          .toList(growable: false);
      switch (operation.action) {
        case OutfitEditActionV1.replace:
          if (removed.isNotEmpty && added.isNotEmpty) {
            clauses.add('vymenil som ${_labels(removed)} za ${_labels(added)}');
          }
        case OutfitEditActionV1.add:
          if (added.isNotEmpty) clauses.add('pridal som ${_labels(added)}');
        case OutfitEditActionV1.remove:
          if (removed.isNotEmpty) {
            clauses.add('odstránil som ${_labels(removed)}');
          }
        case OutfitEditActionV1.preserve:
          break;
      }
    }

    final mutations = plan.operations
        .where((operation) => operation.mutates)
        .toList(growable: false);
    String? focusSlot;
    if (plan.presentation == 'focused_item' &&
        mutations.length == 1 &&
        mutations.single.action == OutfitEditActionV1.replace) {
      final slot = mutations.single.slot;
      final hasActualRemoved = removedIds
          .map((id) => beforeById[id]!)
          .any((item) => _matchesSlot(item, slot));
      final hasActualAdded = addedIds
          .map((id) => afterById[id]!)
          .any((item) => _matchesSlot(item, slot));
      if (hasActualRemoved && hasActualAdded) {
        focusSlot = _slotWireName(slot);
      }
    }

    final isFocusedSingle = focusSlot != null;
    final preserved = preservedIds
        .map((id) => afterById[id]!)
        .toList(growable: false);
    var text = clauses.isEmpty
        ? 'Požadovanú zmenu som nevykonal.'
        : '${_capitalize(clauses.join('; '))}.';
    if (!isFocusedSingle && preserved.isNotEmpty) {
      text = '$text Zachoval som ${_labels(preserved)}.';
    }

    return OutfitEditDeltaV1._(
      addedItemIds: Set<String>.unmodifiable(addedIds),
      removedItemIds: Set<String>.unmodifiable(removedIds),
      preservedItemIds: Set<String>.unmodifiable(preservedIds),
      changedAfterItemIds: Set<String>.unmodifiable(addedIds),
      actualFocusSlot: focusSlot,
      followUpTextSk: text,
    );
  }

  static bool _matchesSlot(V2FlexibleOutfitItem item, OutfitEditSlotV1 slot) =>
      switch (slot) {
        OutfitEditSlotV1.shoes => item.item.bodySlots.contains('feet'),
        OutfitEditSlotV1.outerwear =>
          item.item.bodySlots.contains('upper_body') &&
              const <String>{
                'outer',
                'shell',
              }.contains(item.item.layerPosition),
        OutfitEditSlotV1.layers =>
          item.item.bodySlots.contains('upper_body') &&
              item.item.layerPosition == 'mid',
        OutfitEditSlotV1.fullBody => item.item.bodySlots.contains('full_body'),
        OutfitEditSlotV1.bottom =>
          item.item.bodySlots.contains('lower_body') &&
              !item.item.bodySlots.contains('full_body'),
        OutfitEditSlotV1.top =>
          item.item.bodySlots.contains('upper_body') &&
              !item.item.bodySlots.contains('full_body') &&
              !const <String>{
                'skin_base',
                'mid',
                'outer',
                'shell',
              }.contains(item.item.layerPosition),
        OutfitEditSlotV1.accessories =>
          item.item.accessoryGroup != null ||
              item.compositionRole.name == 'finishing' ||
              item.compositionRole.name == 'accent',
      };

  static String _labels(List<V2FlexibleOutfitItem> items) =>
      _joinSk(items.map(_label).toList(growable: false));

  static String _label(V2FlexibleOutfitItem item) {
    for (final key in const <String>['name', 'displayName', 'title']) {
      final value = item.display[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return item.item.canonicalType.replaceAll('_', ' ');
  }

  static String _joinSk(List<String> values) {
    if (values.isEmpty) return '';
    if (values.length == 1) return values.single;
    if (values.length == 2) return '${values.first} a ${values.last}';
    return '${values.take(values.length - 1).join(', ')} a ${values.last}';
  }

  static String _capitalize(String value) => value.isEmpty
      ? value
      : '${value.substring(0, 1).toUpperCase()}${value.substring(1)}';
}

String _slotWireName(OutfitEditSlotV1 slot) => switch (slot) {
  OutfitEditSlotV1.top => 'top',
  OutfitEditSlotV1.bottom => 'bottom',
  OutfitEditSlotV1.shoes => 'shoes',
  OutfitEditSlotV1.layers => 'layers',
  OutfitEditSlotV1.outerwear => 'outerwear',
  OutfitEditSlotV1.fullBody => 'full_body',
  OutfitEditSlotV1.accessories => 'accessories',
};
