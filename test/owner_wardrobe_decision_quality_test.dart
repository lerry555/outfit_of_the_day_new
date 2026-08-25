import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/decision_quality_harness.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/outfit_suitability_policy_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_item_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_v2_resolver.dart';

ResolvedWardrobeItemV2? _fromOwner(Map<String, dynamic> raw) {
  final id = (raw['id'] ?? '').toString();
  final type = (raw['canonicalType'] ?? '').toString();
  final family = (raw['canonicalFamily'] ?? '').toString();
  final layer = (raw['layerPosition'] ?? '').toString();
  final slots = (raw['bodySlots'] as List? ?? const [])
      .map((e) => e.toString())
      .toList(growable: false);
  if (id.isEmpty || type.isEmpty || family.isEmpty || slots.isEmpty) {
    return null;
  }
  final warmth = (raw['warmth'] as num?)?.toInt() ?? 4;
  final formality = (raw['formality'] as num?)?.toInt() ?? 4;
  return ResolvedWardrobeItemV2(
    itemId: id,
    item: WardrobeItemV2(
      canonicalType: type,
      canonicalFamily: family,
      bodySlots: slots,
      layerPosition: layer,
      outfitFunctions: (raw['outfitFunctions'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      colorProfile: const ColorProfileV2(
        primary: SemanticColorV2(family: 'navy'),
        metalTone: 'none',
        hardwareTone: 'none',
      ),
      formality: formality,
      styles: const [],
      occasionFit: const [],
      seasons: const [],
      warmth: warmth,
      attributes: const {},
      fieldSources: const {'canonicalType': 'visual_ai'},
      fieldConfidence: const {'canonicalType': .9},
      userOverrideFields: (raw['userOverrideFields'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
    ),
    raw: raw,
  );
}

void main() {
  final file = File('.local_audit/decision_quality/owner_wardrobe.json');
  late List<ResolvedWardrobeItemV2> wardrobe;

  setUpAll(() {
    if (!file.existsSync()) return;
    final items = (jsonDecode(file.readAsStringSync()) as List)
        .whereType<Map>()
        .map((e) => _fromOwner(Map<String, dynamic>.from(e)))
        .whereType<ResolvedWardrobeItemV2>()
        .toList(growable: false);
    wardrobe = items;
  });

  test('owner wardrobe snapshot is 52 strict V2 items', () {
    if (!file.existsSync()) {
      markTestSkipped('owner wardrobe snapshot not present');
      return;
    }
    expect(wardrobe.length, 52);
    expect(wardrobe.every((e) => e.item.canonicalType.isNotEmpty), isTrue);
  });

  test('owner casual warm-weather outfit is not a winter jacket', () {
    if (!file.existsSync()) {
      markTestSkipped('owner wardrobe snapshot not present');
      return;
    }
    final report = DecisionQualityHarness.evaluate(
      wardrobe: wardrobe,
      context: const DecisionQualityContext(tempC: 26, occasionId: 'casual'),
    );
    expect(report.winner, isNotNull);
    expect(report.winnerHasType('winter_jacket'), isFalse);
    expect(report.winnerHasType('shorts') || report.winnerHasType('t_shirt'), isTrue);
  });

  test('owner work outfit does not use shorts or sandals', () {
    if (!file.existsSync()) {
      markTestSkipped('owner wardrobe snapshot not present');
      return;
    }
    final report = DecisionQualityHarness.evaluate(
      wardrobe: wardrobe,
      context: const DecisionQualityContext(
        tempC: 20,
        occasionId: 'work',
        outdoor: false,
      ),
    );
    expect(report.winnerHasType('shorts'), isFalse);
    expect(report.winnerHasType('sandals'), isFalse);
  });

  test('owner funeral outfit does not use shorts', () {
    if (!file.existsSync()) {
      markTestSkipped('owner wardrobe snapshot not present');
      return;
    }
    final report = DecisionQualityHarness.evaluate(
      wardrobe: wardrobe,
      context: const DecisionQualityContext(
        tempC: 18,
        occasionId: 'funeral',
        outdoor: false,
      ),
    );
    expect(report.winnerHasType('shorts'), isFalse);
    expect(report.winnerHasType('sweatpants'), isFalse);
  });

  test('owner hike prefers boots or sneakers over dress shoes', () {
    if (!file.existsSync()) {
      markTestSkipped('owner wardrobe snapshot not present');
      return;
    }
    final report = DecisionQualityHarness.evaluate(
      wardrobe: wardrobe,
      context: const DecisionQualityContext(tempC: 12, activityType: 'hike'),
    );
    expect(report.winnerHasType('dress_shoes'), isFalse);
    expect(
      report.winnerHasType('chelsea_boots') || report.winnerHasType('sneakers'),
      isTrue,
    );
  });

  test('owner explicit denim jacket request is honored when weather allows', () {
    if (!file.existsSync()) {
      markTestSkipped('owner wardrobe snapshot not present');
      return;
    }
    final denim = wardrobe.firstWhere(
      (e) => e.item.canonicalType == 'denim_jacket',
    );
    final report = DecisionQualityHarness.evaluate(
      wardrobe: wardrobe,
      context: DecisionQualityContext(
        tempC: 12,
        requestedItemIds: {denim.itemId},
      ),
    );
    expect(report.winnerHasType('denim_jacket'), isTrue);
  });

  test('owner funeral footwear compromise is not graded excellent', () {
    if (!file.existsSync()) {
      markTestSkipped('owner wardrobe snapshot not present');
      return;
    }
    final report = DecisionQualityHarness.evaluate(
      wardrobe: wardrobe,
      context: const DecisionQualityContext(
        tempC: 18,
        occasionId: 'funeral',
        outdoor: false,
      ),
    );
    final hasDressShoes = wardrobe.any(
      (e) => e.item.canonicalType == 'dress_shoes',
    );
    if (!hasDressShoes) {
      expect(report.grade, isNot(DecisionQualityGrade.excellent));
    }
  });
}
