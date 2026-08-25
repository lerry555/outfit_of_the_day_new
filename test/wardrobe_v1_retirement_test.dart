import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/wardrobe_revision_lifecycle_client.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_v1_retirement.dart';

void main() {
  final allowlist =
      jsonDecode(
            File(
              'assets/wardrobe_ontology_v2_retirement_allowlist.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final cleanupFields = Set<String>.from(
    allowlist['deleteReadyFieldPaths'] as List,
  );

  test('runtime retired fields cover the cleanup allowlist', () {
    expect(
      WardrobeV1Retirement.retiredWardrobeFieldPaths,
      containsAll(cleanupFields),
    );
    expect(allowlist['artifactVersion'], WardrobeV1Retirement.artifactVersion);
  });

  test('new V2 save strips retired aliases and preserves authority', () {
    final payload = WardrobeV1Retirement.stripRetiredFields({
      'canonicalType': 'cardigan',
      'canonicalFamily': 'mid_layer',
      'bodySlots': ['upper_body'],
      'layerPosition': 'mid',
      'colorProfile': {
        'primary': {'family': 'white'},
        'secondary': null,
        'accents': <Object>[],
        'metalTone': 'none',
        'hardwareTone': 'none',
      },
      'brand': 'OwnerEdit',
      'userOverrideFields': ['brand'],
      'fieldSources': {'brand': 'user_correction'},
      'fieldConfidence': {'brand': 1.0},
      for (final field in WardrobeV1Retirement.retiredWardrobeFieldPaths)
        field: 'legacy',
    });

    expect(payload['canonicalType'], 'cardigan');
    expect(payload['bodySlots'], ['upper_body']);
    expect(payload['layerPosition'], 'mid');
    expect(payload['brand'], 'OwnerEdit');
    expect(payload['userOverrideFields'], ['brand']);
    for (final field in WardrobeV1Retirement.retiredWardrobeFieldPaths) {
      expect(payload.containsKey(field), isFalse, reason: field);
    }
  });

  test('edit lifecycle cannot recreate retired classification aliases', () {
    for (final field in cleanupFields) {
      expect(
        kClassificationLifecycleAllowList.contains(field),
        isFalse,
        reason: field,
      );
    }
    expect(kClassificationLifecycleAllowList, contains('canonicalType'));
    expect(kClassificationLifecycleAllowList, contains('bodySlots'));
    expect(kClassificationLifecycleAllowList, contains('layerPosition'));
    expect(kClassificationLifecycleAllowList, contains('analyzerProvenance'));
  });

  test('stripping is idempotent', () {
    final once = WardrobeV1Retirement.stripRetiredFields({
      'canonicalType': 'trousers',
      'canonical_type': 'trousers',
      'categoryKey': 'nohavice',
    });
    final twice = WardrobeV1Retirement.stripRetiredFields(once);
    expect(twice, once);
  });
}
