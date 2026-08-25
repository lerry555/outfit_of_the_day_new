import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adversarial fixture metadata has explicit safety expectations', () {
    final decoded =
        jsonDecode(
              File(
                'test/fixtures/vision_v2_adversarial_scenarios.json',
              ).readAsStringSync(),
            )
            as List;
    expect(decoded, hasLength(greaterThanOrEqualTo(14)));
    final ids = <String>{};
    for (final raw in decoded) {
      final scenario = Map<String, Object?>.from(raw as Map);
      expect(ids.add(scenario['id']! as String), isTrue);
      expect(
        scenario['inputAssessment'],
        isIn([
          'valid_single_item',
          'multiple_items',
          'insufficient_visual_information',
          'non_wardrobe_object',
          'ambiguous_subject',
        ]),
      );
      expect(scenario['forbiddenAbsenceClaims'], isA<List>());
      expect(scenario['maximumVisibilityTrust'], isA<String>());
      expect(scenario['expectedFamilyState'], isA<String>());
      expect(scenario['canonicalSubtypeAllowed'], isA<bool>());
    }
    expect(
      ids,
      containsAll([
        'fabric_detail_only',
        'front_only_garment',
        'shoe_without_outsole',
        'outsole_only',
        'multiple_garments',
        'non_wardrobe_object',
        'cross_family_ambiguity',
        'complementary_multi_view',
        'conflicting_multi_view',
      ]),
    );
  });
}
