import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:outfitofTheDay/Services/wardrobe_qualification_authority_client.dart';
import 'package:outfitofTheDay/Services/wardrobe_revision_lifecycle_client.dart';
import 'package:outfitofTheDay/Services/wardrobe_write_path_cutover.dart';

void main() {
  group('buildClassificationLifecyclePatch', () {
    test('keeps allow-listed UX fields only', () {
      final patch = buildClassificationLifecyclePatch({
        'name': 'Hoodie',
        'brand': 'X',
        'colorProfile': {
          'primary': {'family': 'blue'},
          'secondary': [],
          'accents': [],
          'metalTone': 'none',
          'hardwareTone': 'none',
        },
        'storagePath': 'wardrobe/u/a.jpg',
        'imageUrl': 'https://example.test/a.jpg',
        'qualificationAuthority': {'imageRevision': 1},
        'wardrobeProfile': {'r': 1},
        'updatedAt': 'server',
      });
      expect(patch.keys, containsAll(['name', 'brand', 'colorProfile']));
      expect(patch.containsKey('colors'), isFalse);
      expect(patch.containsKey('storagePath'), isFalse);
      expect(patch.containsKey('imageUrl'), isFalse);
      expect(patch.containsKey('qualificationAuthority'), isFalse);
      expect(patch.containsKey('wardrobeProfile'), isFalse);
    });
  });

  group('WardrobeWritePathCutover', () {
    test('create with storagePath initializes then analyzes', () async {
      final calls = <Map<String, dynamic>>[];
      Future<Map<String, dynamic>> transport(
        String name,
        Map<String, dynamic> data,
      ) async {
        calls.add({'name': name, ...data});
        return {
          'ok': true,
          'result': {'status': 'mutation_applied'},
        };
      }

      final cutover = WardrobeWritePathCutover(
        lifecycleClient: WardrobeRevisionLifecycleClient(transport: transport),
        authorityClient: WardrobeQualificationAuthorityClient(
          transport: transport,
        ),
      );

      final result = await cutover.afterUxSave(
        isEditing: false,
        itemId: 'item-1',
        savedFields: {
          'name': 'Hoodie',
          'storagePath': 'wardrobe/uid/photo.jpg',
        },
        storagePath: 'wardrobe/uid/photo.jpg',
      );

      expect(result.lifecycle?.status, WardrobeLifecycleCallStatus.applied);
      expect(result.authority?.status, WardrobeLifecycleCallStatus.applied);
      expect(calls.length, 2);
      expect(calls[0]['name'], kWardrobeRevisionLifecycleCallableName);
      expect(calls[0]['operationKind'], kLifecycleOpInitializeUserPhoto);
      expect(calls[0].containsKey('uid'), isFalse);
      expect(calls[1]['name'], kWardrobeQualificationAuthorityCallableName);
      expect(calls[1]['action'], kAuthorityActionAnalyzeCurrentSource);
    });

    test('create without storagePath skips lifecycle', () async {
      var called = false;
      final cutover = WardrobeWritePathCutover(
        lifecycleClient: WardrobeRevisionLifecycleClient(
          transport: (name, data) async {
            called = true;
            return {'ok': true};
          },
        ),
      );

      final result = await cutover.afterUxSave(
        isEditing: false,
        itemId: 'pl-1',
        savedFields: {'name': 'Product', 'productLinkSku': 'SKU'},
        fromProductLink: true,
      );

      expect(called, isFalse);
      expect(result.lifecycle, isNull);
    });

    test('edit sends classification patch without authority fields', () async {
      Map<String, dynamic>? seen;
      final cutover = WardrobeWritePathCutover(
        lifecycleClient: WardrobeRevisionLifecycleClient(
          transport: (name, data) async {
            seen = data;
            return {
              'ok': true,
              'result': {'status': 'mutation_applied'},
            };
          },
        ),
      );

      await cutover.afterUxSave(
        isEditing: true,
        itemId: 'item-2',
        savedFields: {
          'name': 'New',
          'canonicalType': 'hoodie',
          'bodySlots': ['upper_body'],
          'categoryKey': 'tops',
          'imageUrl': 'https://example.test/x.jpg',
          'qualificationAuthority': {'v': 1},
        },
      );

      expect(seen!['operationKind'], kLifecycleOpClassificationEdit);
      final patch = Map<String, dynamic>.from(seen!['patch'] as Map);
      expect(patch['name'], 'New');
      expect(patch['canonicalType'], 'hoodie');
      expect(patch['bodySlots'], ['upper_body']);
      expect(patch.containsKey('categoryKey'), isFalse);
      expect(patch.containsKey('imageUrl'), isFalse);
      expect(patch.containsKey('qualificationAuthority'), isFalse);
      expect(seen!.containsKey('uid'), isFalse);
    });

    test('not-found callable soft-defers without throwing', () async {
      final cutover = WardrobeWritePathCutover(
        lifecycleClient: WardrobeRevisionLifecycleClient(
          transport: (name, data) async {
            throw FirebaseFunctionsException(
              code: 'not-found',
              message: 'not exported',
            );
          },
        ),
      );

      final result = await cutover.afterUxSave(
        isEditing: true,
        itemId: 'item-3',
        savedFields: {'name': 'A', 'brand': 'B'},
      );

      expect(
        result.lifecycle?.status,
        WardrobeLifecycleCallStatus.deferredUntilExport,
      );
      expect(result.preservedUx, isTrue);
    });

    test('same-image reanalysis uses lifecycle op', () async {
      Map<String, dynamic>? seen;
      final cutover = WardrobeWritePathCutover(
        lifecycleClient: WardrobeRevisionLifecycleClient(
          transport: (name, data) async {
            seen = data;
            return {
              'ok': true,
              'result': {'status': 'idempotent_noop'},
            };
          },
        ),
      );

      final result = await cutover.afterSameImageReanalysis(itemId: 'item-9');
      expect(result.status, WardrobeLifecycleCallStatus.applied);
      expect(seen!['operationKind'], kLifecycleOpSameImageReanalysis);
    });
  });
}
