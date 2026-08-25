import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/data/clothing_knowledge_base.dart';

void main() {
  test('approved KB aliases resolve to existing canonical items', () {
    const cases = <String, String>{
      'macintosh': 'rain_jacket',
      'fannypack': 'fanny_pack',
      'cross-body bag': 'crossbody_bag',
      'trench': 'trench_coat',
    };
    for (final entry in cases.entries) {
      expect(
        ClothingKnowledgeBase.findByAlias(entry.key)?.canonicalType,
        entry.value,
        reason: entry.key,
      );
      expect(
        ClothingKnowledgeBase.resolveClothingType(canonicalType: entry.key)
            ?.canonicalType,
        entry.value,
        reason: '${entry.key}:resolver',
      );
      expect(
        ClothingKnowledgeBase.findByCanonicalType(entry.value)?.canonicalType,
        entry.value,
        reason: '${entry.value}:idempotent',
      );
    }
  });

  test('generic and ambiguous terms do not gain an authoritative KB alias', () {
    for (final input in const [
      'jacket',
      'pants',
      'coat',
      'top',
      'jersey',
      'button-down shirt',
      'moto jacket',
      'puffer coat',
      'quilted jacket',
      'quilted coat',
      'wool coat',
      'tailored trousers',
    ]) {
      expect(ClothingKnowledgeBase.findByAlias(input), isNull, reason: input);
    }
  });

  test('approved aliases do not override adjacent sibling canonicals', () {
    for (final canonical in const [
      'rain_jacket',
      'trench_coat',
      'overcoat',
      'leather_jacket',
      'varsity_jacket',
      'bomber_jacket',
      'vest',
      'waistcoat',
    ]) {
      expect(
        ClothingKnowledgeBase.findByCanonicalType(canonical)?.canonicalType,
        canonical,
        reason: canonical,
      );
    }
  });
}
