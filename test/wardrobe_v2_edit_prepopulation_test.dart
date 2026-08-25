import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/wardrobe_v2_edit_prepopulation.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_v1_retirement.dart';

void main() {
  Map<String, dynamic> cardigan() {
    final snapshot =
        jsonDecode(
              File(
                '.local_audit/wardrobe_ontology_v2/'
                'owner_wardrobe_snapshot_20260811T154520Z.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final document = (snapshot['documents'] as List).cast<Map>().singleWhere(
      (item) => item['documentId'] == 'YFRdEcwbBgN8tPX5EOjd',
    );
    return Map<String, dynamic>.from(document['fields'] as Map);
  }

  test('strict V2 document prepopulates all edit presentation axes', () {
    final state = WardrobeV2EditPrepopulation.fromDocument(cardigan());
    expect(state.canonicalType, 'cardigan');
    expect(state.mainCategory, 'oblecenie');
    expect(state.category, 'svetre');
    expect(state.subcategory, 'sveter_kardigan');
    expect(state.displayColors, contains('biela'));
    expect(state.patterns, ['jednofarebné']);
    expect(state.styles, ['casual', 'smart casual']);
    expect(state.seasons, ['jeseň', 'zima']);
    expect(state.fit, 'loose');
    expect(state.formality, 4);
    expect(state.warmth, 7);
  });

  test('no-change edit round-trip preserves semantic V2 without overrides', () {
    final document = cardigan();
    final before = WardrobeV2EditPersistence.authoritativePayloadFromDocument(
      document,
    );
    final after = WardrobeV2EditPersistence.applyBrandEdit(
      payload: before,
      originalBrand: document['brand'].toString(),
      editedBrand: document['brand'].toString(),
    );
    expect(after, equals(before));
    expect(
      WardrobeV1Retirement.retiredWardrobeFieldPaths.where(after.containsKey),
      isEmpty,
    );
  });

  test('one-field edit changes only brand authority metadata', () {
    final document = cardigan();
    final before = WardrobeV2EditPersistence.authoritativePayloadFromDocument(
      document,
    );
    final after = WardrobeV2EditPersistence.applyBrandEdit(
      payload: before,
      originalBrand: document['brand'].toString(),
      editedBrand: 'OwnerEditStable2',
    );
    for (final key in before.keys.where(
      (key) => !{
        'userOverrideFields',
        'fieldSources',
        'fieldConfidence',
      }.contains(key),
    )) {
      expect(after[key], equals(before[key]), reason: key);
    }
    expect(after['userOverrideFields'], contains('brand'));
    expect((after['fieldSources'] as Map)['brand'], 'user_correction');
    expect((after['fieldConfidence'] as Map)['brand'], 1.0);
    expect(
      WardrobeV1Retirement.retiredWardrobeFieldPaths.where(after.containsKey),
      isEmpty,
    );
  });

  test('colorProfile projects primary, secondary, then accents', () {
    expect(
      WardrobeV2EditPrepopulation.colorFamiliesFromProfile({
        'primary': {'family': 'blue'},
        'secondary': {'family': 'white'},
        'accents': [
          {'family': 'red'},
        ],
      }),
      ['blue', 'white', 'red'],
    );
    expect(
      WardrobeV2EditPrepopulation.displayColorsFromProfile({
        'primary': {'family': 'blue'},
        'secondary': {'family': 'white'},
        'accents': [
          {'family': 'red'},
        ],
      }),
      ['modrá', 'biela', 'červená'],
    );
  });
}
