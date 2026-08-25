import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_ontology_v2.dart';
import 'package:outfitofTheDay/utils/home_wardrobe_read_path.dart';
import 'package:outfitofTheDay/utils/stylist_chat_wardrobe_read_path.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'post-retirement owner snapshot has zero Home and Stylist fallback',
    () async {
      await WardrobeOntologyV2.load();
      final snapshot =
          jsonDecode(
                File(
                  '.local_audit/wardrobe_ontology_v2/'
                  'owner_wardrobe_snapshot_20260811T154520Z.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final raw = (snapshot['documents'] as List)
          .cast<Map<String, dynamic>>()
          .map(
            (document) => <String, dynamic>{
              ...Map<String, dynamic>.from(document['fields'] as Map),
              'id': document['documentId'],
            },
          )
          .toList(growable: false);

      final home = const HomeWardrobeReadPath(
        useResolvedProfiles: true,
      ).build(raw);
      final stylist = const StylistChatWardrobeReadPath(
        useResolvedProfiles: true,
      ).build(raw);
      final homeFallbackIds = raw
          .where(
            (item) =>
                const HomeWardrobeReadPath(useResolvedProfiles: true).build(
                  <Map<String, dynamic>>[item],
                ).compatibilityFallbackItems >
                0,
          )
          .map((item) => item['id'])
          .toList();

      expect(raw, hasLength(49));
      expect(home.usedResolvedProfiles, isTrue);
      expect(home.resolvedWithoutFallback, 49, reason: '$homeFallbackIds');
      expect(home.compatibilityFallbackItems, 0);
      expect(stylist.usedResolvedProfiles, isTrue);
      expect(stylist.resolvedWithoutFallback, 49);
      expect(stylist.compatibilityFallbackItems, 0);
    },
  );
}
