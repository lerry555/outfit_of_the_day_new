import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/utils/stylist_card_image_priority.dart';

void main() {
  test('Stylist card keeps only product-like candidates and excludes raw original', () {
    final item = <String, dynamic>{
      'productImageUrl': 'https://example.test/product.png',
      'cutoutImageUrl': 'https://example.test/cutout.png',
      'cleanImageUrl': 'https://example.test/clean.png',
      'imageUrl': 'https://example.test/person.jpg',
      'originalImageUrl': 'https://example.test/person.jpg',
      'processing': <String, dynamic>{'product': 'done'},
    };
    final candidates = stylistCardImageCandidates(item);
    expect(candidates.map((e) => e.kind), ['product', 'cutout', 'clean']);
    expect(candidates.map((e) => e.url), isNot(contains(item['imageUrl'])));
    expect(candidates.map((e) => e.url), isNot(contains(item['originalImageUrl'])));
  });

  test('Stylist card has no raw-person fallback when derivatives are absent', () {
    final candidates = stylistCardImageCandidates(<String, dynamic>{
      'imageUrl': 'https://example.test/person.jpg',
      'originalImageUrl': 'https://example.test/person.jpg',
    });
    expect(candidates, isEmpty);
  });
}
