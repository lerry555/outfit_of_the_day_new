import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/add_clothing_v2_save_coordinator.dart';

Map<String, dynamic> validPayload() => {
  'canonicalType': 'cardigan',
  'canonicalFamily': 'mid_layer',
  'bodySlots': ['upper_body'],
  'layerPosition': 'mid',
  'colorProfile': {
    'primary': {'family': 'white'},
  },
  'formality': 4,
  'warmth': 5,
  'styles': ['classic'],
  'occasionFit': ['casual'],
  'attributes': <String, dynamic>{},
  'fieldSources': {'canonicalType': 'visual_ai'},
  'fieldConfidence': {'canonicalType': .98},
  'ontologyVersion': '2.0.0',
  'taxonomyVersion': '2.0.0',
  'kbVersion': '2.0.0',
  'analyzerProvenance': {'analyzerVersion': 'clothing-vision-gemini-v2'},
  'storagePath': 'wardrobe/owner/test.jpg',
};

void main() {
  test('valid V2 writes and navigates only after completed write', () async {
    final order = <String>[];
    final coordinator = AddClothingV2SaveCoordinator();
    await coordinator.persist(
      v2Payload: validPayload(),
      write: () async {
        order.add('write');
        return 'item-1';
      },
      afterWrite: (_) async {
        order.add('after');
      },
      navigateAfterSave: (_) => order.add('navigate'),
    );
    expect(order, ['write', 'after', 'navigate']);
  });

  test(
    'write failure does not navigate and save can retry without analyzer',
    () async {
      var writes = 0;
      var navigations = 0;
      final coordinator = AddClothingV2SaveCoordinator();
      Future<String> attempt() => coordinator.persist(
        v2Payload: validPayload(),
        write: () async {
          writes++;
          if (writes == 1) throw Exception('denied');
          return 'item-2';
        },
        afterWrite: (_) async {},
        navigateAfterSave: (_) => navigations++,
      );
      await expectLater(attempt(), throwsException);
      expect(navigations, 0);
      expect(await attempt(), 'item-2');
      expect(navigations, 1);
      expect(writes, 2);
    },
  );

  test('missing V2 payload fails explicitly before write', () async {
    var wrote = false;
    final coordinator = AddClothingV2SaveCoordinator();
    await expectLater(
      coordinator.persist(
        v2Payload: {'canonicalType': 'cardigan'},
        write: () async {
          wrote = true;
          return 'bad';
        },
        afterWrite: (_) async {},
        navigateAfterSave: (_) {},
      ),
      throwsStateError,
    );
    expect(wrote, false);
  });
}
