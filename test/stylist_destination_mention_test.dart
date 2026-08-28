import 'package:flutter_test/flutter_test.dart';

import 'package:outfitofTheDay/utils/stylist_destination_mention.dart';

void main() {
  group('StylistDestinationMentionExtractor', () {
    test('extracts destinations from generic travel language', () {
      final cases = <String, String>{
        'Letím do Londýna.': 'Londýna',
        'Idem autom do Berlína.': 'Berlína',
        'Cestujem do Prahy.': 'Prahy',
      };
      for (final entry in cases.entries) {
        expect(
          StylistDestinationMentionExtractor.extract(entry.key)?.query,
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('provider variants are generic morphology fallbacks', () {
      final genitiveA = StylistDestinationMentionExtractor.providerQueryVariants(
        'Londýna',
      );
      final genitiveY = StylistDestinationMentionExtractor.providerQueryVariants(
        'Bratislavy',
      );
      final shortGenitive =
          StylistDestinationMentionExtractor.providerQueryVariants('Prahy');

      expect(genitiveA, contains('Londýn'));
      expect(genitiveY, contains('Bratislav'));
      expect(shortGenitive, contains('Prah'));
    });

    test('transport nouns alone never become a destination', () {
      for (final text in <String>[
        'Čo si mám obliecť do lietadla?',
        'Potrebujem outfit do auta.',
        'Čo do vlaku?',
      ]) {
        expect(
          StylistDestinationMentionExtractor.extract(text),
          isNull,
          reason: text,
        );
      }
    });
  });
}
