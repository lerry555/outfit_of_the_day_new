import '../wardrobe_v2/wardrobe_item_v2.dart';
import 'trip_intent_policy.dart';

/// Garment role used by the Phase 3 packing coverage optimizer.
///
/// Repeat policy (coverage first, compactness second, variety third):
/// - [footwear]: unlimited reuse across compatible days
/// - [weatherLayer]: unlimited reuse across compatible days
/// - [accessory]: unlimited reuse
/// - [bottom] / [fullBody]: moderate; several days per piece when alternatives exist
/// - [coreUpper]: lower reuse than bottoms; rotate when alternatives exist
/// - [skinBase]: hygiene-limited; do not aggressively reuse
enum TripCoverageRole {
  footwear,
  weatherLayer,
  bottom,
  fullBody,
  coreUpper,
  skinBase,
  accessory,
}

class TripCoverageDayNeed {
  const TripCoverageDayNeed({
    required this.dayIndex,
    required this.validIds,
  });

  final int dayIndex;

  /// Required slots for this day → ranked-suitable wardrobe IDs.
  final Map<TripIntentSlot, List<String>> validIds;
}

class TripCoverageResult {
  const TripCoverageResult({
    required this.assignment,
    required this.packedIds,
    required this.uncovered,
  });

  /// dayIndex → slot → wardrobe id
  final Map<int, Map<TripIntentSlot, String>> assignment;
  final Set<String> packedIds;
  final List<(int dayIndex, TripIntentSlot slot)> uncovered;
}

/// Deterministic greedy coverage for destination-day slots.
///
/// Complexity is O(days × slots × candidates) per greedy pass.
abstract final class TripPackingCoverage {
  TripPackingCoverage._();

  static TripIntentSlot? primarySlot(WardrobeItemV2 item) {
    if (item.bodySlots.contains('feet')) return TripIntentSlot.footwear;
    if (item.accessoryGroup == 'bag' ||
        item.outfitFunctions.contains('carrying') ||
        item.canonicalFamily == 'headwear' ||
        item.canonicalFamily == 'eyewear' ||
        item.bodySlots.contains('face_eyes')) {
      return TripIntentSlot.accessory;
    }
    if (item.bodySlots.contains('full_body')) return TripIntentSlot.full;
    if (item.bodySlots.contains('lower_body')) return TripIntentSlot.lower;
    final layer = item.layerPosition;
    if (layer == 'skin_base') return TripIntentSlot.layer;
    if (layer == 'outer' || layer == 'shell' || layer == 'mid') {
      return TripIntentSlot.layer;
    }
    if (item.bodySlots.contains('upper_body')) return TripIntentSlot.upper;
    return null;
  }

  static TripCoverageRole roleFor(WardrobeItemV2 item) {
    final slot = primarySlot(item);
    if (item.layerPosition == 'skin_base' ||
        item.canonicalFamily == 'undergarment') {
      return TripCoverageRole.skinBase;
    }
    switch (slot) {
      case TripIntentSlot.footwear:
        return TripCoverageRole.footwear;
      case TripIntentSlot.layer:
        return TripCoverageRole.weatherLayer;
      case TripIntentSlot.accessory:
        return TripCoverageRole.accessory;
      case TripIntentSlot.lower:
        return TripCoverageRole.bottom;
      case TripIntentSlot.full:
        return TripCoverageRole.fullBody;
      case TripIntentSlot.upper:
        return TripCoverageRole.coreUpper;
      case null:
        return TripCoverageRole.coreUpper;
    }
  }

  /// Max days one packed item may cover. Scarce wardrobes (`alternatives <= 1`)
  /// lift the cap so the plan does not fail for lack of variety.
  static int maxUses({
    required TripCoverageRole role,
    required int tripDays,
    required int alternatives,
  }) {
    if (tripDays <= 0) return 0;
    if (alternatives <= 1) return tripDays;
    switch (role) {
      case TripCoverageRole.footwear:
      case TripCoverageRole.weatherLayer:
      case TripCoverageRole.accessory:
        return tripDays;
      case TripCoverageRole.bottom:
      case TripCoverageRole.fullBody:
        return (tripDays + 1) ~/ 2 < 3 ? 3 : (tripDays + 1) ~/ 2;
      case TripCoverageRole.coreUpper:
        final cap = (tripDays + 2) ~/ 3;
        return cap < 2 ? 2 : cap;
      case TripCoverageRole.skinBase:
        return 2;
    }
  }

  /// Modest extra distinct pieces after minimum coverage.
  static int varietyTarget({
    required TripCoverageRole role,
    required int tripDays,
    required int available,
  }) {
    if (available <= 1 || tripDays <= 0) return available.clamp(0, 1);
    switch (role) {
      case TripCoverageRole.footwear:
      case TripCoverageRole.weatherLayer:
      case TripCoverageRole.accessory:
      case TripCoverageRole.skinBase:
        return 1;
      case TripCoverageRole.coreUpper:
        final target = 1 + tripDays ~/ 2;
        return available < target
            ? available
            : (target < tripDays ? target : tripDays);
      case TripCoverageRole.bottom:
      case TripCoverageRole.fullBody:
        final target = (tripDays + 2) ~/ 3;
        final atLeast = target < 1 ? 1 : target;
        return available < atLeast
            ? available
            : (atLeast < tripDays ? atLeast : tripDays);
    }
  }

  static TripCoverageResult plan({
    required List<TripCoverageDayNeed> days,
    required Map<String, WardrobeItemV2> catalog,
  }) {
    final packed = <String>{};
    final uses = <String, int>{};
    final uncovered = <(int, TripIntentSlot)>[
      for (final day in days)
        for (final slot in day.validIds.keys)
          if (day.validIds[slot]!.isNotEmpty) (day.dayIndex, slot),
    ];
    final emptySlots = <(int, TripIntentSlot)>[
      for (final day in days)
        for (final slot in day.validIds.keys)
          if (day.validIds[slot]!.isEmpty) (day.dayIndex, slot),
    ];

    final validLookup = <int, Map<TripIntentSlot, Set<String>>>{
      for (final day in days)
        day.dayIndex: {
          for (final entry in day.validIds.entries) entry.key: entry.value.toSet(),
        },
    };

    int alternativesFor(String id) {
      final item = catalog[id];
      if (item == null) return 1;
      final slot = primarySlot(item);
      var count = 0;
      for (final otherId in catalog.keys) {
        final other = catalog[otherId]!;
        if (primarySlot(other) != slot) continue;
        final appears = days.any(
          (day) => day.validIds[slot]?.contains(otherId) ?? false,
        );
        if (appears) count++;
      }
      return count < 1 ? 1 : count;
    }

    List<(int, TripIntentSlot)> compatiblePairs(String id) {
      final remaining =
          maxUses(
            role: roleFor(catalog[id]!),
            tripDays: days.length,
            alternatives: alternativesFor(id),
          ) -
          (uses[id] ?? 0);
      if (remaining <= 0) return const [];
      final hits = <(int, TripIntentSlot)>[];
      for (final pair in uncovered) {
        final valid = validLookup[pair.$1]?[pair.$2];
        if (valid != null && valid.contains(id)) hits.add(pair);
      }
      if (hits.length <= remaining) return hits;
      return hits.sublist(0, remaining);
    }

    int setBonus(String id) {
      final setId = catalog[id]?.setMembership?.setId;
      if (setId == null || setId.isEmpty) return 0;
      if (packed.any((p) => catalog[p]?.setMembership?.setId == setId)) {
        return 2;
      }
      return 1;
    }

    final allIds = <String>[];
    final seenIds = <String>{};
    for (final day in days) {
      for (final ids in day.validIds.values) {
        for (final id in ids) {
          if (seenIds.add(id)) allIds.add(id);
        }
      }
    }
    final idRank = <String, int>{
      for (var i = 0; i < allIds.length; i++) allIds[i]: i,
    };

    while (uncovered.isNotEmpty) {
      String? bestId;
      List<(int, TripIntentSlot)> bestPairs = const [];
      var bestUtility = -1 << 30;
      var bestPacked = false;
      var bestRank = 1 << 30;
      for (final id in allIds) {
        if (catalog[id] == null) continue;
        final pairs = compatiblePairs(id);
        if (pairs.isEmpty) continue;
        final already = packed.contains(id);
        final utility = pairs.length * 100 - (already ? 0 : 10) + setBonus(id);
        final rank = idRank[id] ?? 1 << 30;
        final better = utility > bestUtility ||
            (utility == bestUtility && already && !bestPacked) ||
            (utility == bestUtility &&
                already == bestPacked &&
                rank < bestRank);
        if (better) {
          bestUtility = utility;
          bestId = id;
          bestPairs = pairs;
          bestPacked = already;
          bestRank = rank;
        }
      }
      if (bestId == null) break;
      packed.add(bestId);
      uses[bestId] = (uses[bestId] ?? 0) + bestPairs.length;
      for (final pair in bestPairs) {
        uncovered.remove(pair);
      }
    }

    _addVariety(
      days: days,
      catalog: catalog,
      packed: packed,
      alternativesFor: alternativesFor,
    );

    final assignment = _assignFromPacked(
      days: days,
      catalog: catalog,
      packed: packed,
    );

    final leftover = <(int, TripIntentSlot)>[
      ...emptySlots,
      for (final day in days)
        for (final slot in day.validIds.keys)
          if (!assignment.containsKey(day.dayIndex) ||
              assignment[day.dayIndex]?[slot] == null)
            (day.dayIndex, slot),
    ];

    return TripCoverageResult(
      assignment: assignment,
      packedIds: {
        ...packed,
        for (final day in assignment.values) ...day.values,
      },
      uncovered: leftover,
    );
  }

  static void _addVariety({
    required List<TripCoverageDayNeed> days,
    required Map<String, WardrobeItemV2> catalog,
    required Set<String> packed,
    required int Function(String id) alternativesFor,
  }) {
    const rotationRoles = {
      TripCoverageRole.coreUpper,
      TripCoverageRole.bottom,
      TripCoverageRole.fullBody,
    };
    for (final role in rotationRoles) {
      TripIntentSlot slotFor(TripCoverageRole r) {
        switch (r) {
          case TripCoverageRole.coreUpper:
            return TripIntentSlot.upper;
          case TripCoverageRole.bottom:
            return TripIntentSlot.lower;
          case TripCoverageRole.fullBody:
            return TripIntentSlot.full;
          default:
            return TripIntentSlot.upper;
        }
      }

      final slot = slotFor(role);
      final available = <String>{
        for (final day in days) ...?day.validIds[slot],
      }.toList()
        ..sort();
      if (available.isEmpty) continue;
      final target = varietyTarget(
        role: role,
        tripDays: days.length,
        available: available.length,
      );
      final packedForSlot = packed.where(available.contains).toList();
      if (packedForSlot.length >= target) continue;
      final extras = available.where((id) => !packed.contains(id)).toList()
        ..sort((a, b) {
          int cover(String id) => days
              .where((day) => day.validIds[slot]?.contains(id) ?? false)
              .length;
          final byCover = cover(b).compareTo(cover(a));
          if (byCover != 0) return byCover;
          return a.compareTo(b);
        });
      for (final id in extras) {
        if (packed.where(available.contains).length >= target) break;
        final cap = maxUses(
          role: role,
          tripDays: days.length,
          alternatives: alternativesFor(id),
        );
        if (cap <= 0) continue;
        packed.add(id);
      }
    }
  }

  static Map<int, Map<TripIntentSlot, String>> _assignFromPacked({
    required List<TripCoverageDayNeed> days,
    required Map<String, WardrobeItemV2> catalog,
    required Set<String> packed,
  }) {
    const slotOrder = [
      TripIntentSlot.full,
      TripIntentSlot.upper,
      TripIntentSlot.lower,
      TripIntentSlot.footwear,
      TripIntentSlot.layer,
      TripIntentSlot.accessory,
    ];
    final uses = <String, int>{};
    final assignment = <int, Map<TripIntentSlot, String>>{};
    for (final day in days) {
      final picked = <TripIntentSlot, String>{};
      String? anchorSetId;
      for (final slot in slotOrder) {
        final valid = day.validIds[slot];
        if (valid == null) continue;
        final options = valid.where(packed.contains).toList();
        if (options.isEmpty) continue;
        options.sort((a, b) {
          final aSet = catalog[a]?.setMembership?.setId;
          final bSet = catalog[b]?.setMembership?.setId;
          final aMatch = anchorSetId != null && aSet == anchorSetId;
          final bMatch = anchorSetId != null && bSet == anchorSetId;
          if (aMatch != bMatch) return aMatch ? -1 : 1;
          final role = roleFor(catalog[a]!);
          final rotate = role == TripCoverageRole.coreUpper ||
              role == TripCoverageRole.bottom ||
              role == TripCoverageRole.fullBody;
          if (rotate) {
            final byUses = (uses[a] ?? 0).compareTo(uses[b] ?? 0);
            if (byUses != 0) return byUses;
          }
          return valid.indexOf(a).compareTo(valid.indexOf(b));
        });
        final id = options.first;
        picked[slot] = id;
        uses[id] = (uses[id] ?? 0) + 1;
        anchorSetId ??= catalog[id]?.setMembership?.setId;
      }
      if (picked.isNotEmpty) assignment[day.dayIndex] = picked;
    }
    return assignment;
  }
}
