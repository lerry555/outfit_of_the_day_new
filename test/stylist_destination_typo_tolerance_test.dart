import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/utils/stylist_destination_parser.dart';
import 'package:outfitofTheDay/utils/stylist_swap_request.dart';

void main() {
  test('high-confidence city typos ground Washington', () {
    for (final typo in ['Wasntom', 'Washinton', 'Wasinton']) {
      expect(
        StylistDestinationParser.inferFromConversation(
          'Cestujeme do USA, $typo a prechádzka po meste.',
        ),
        'Washington',
        reason: typo,
      );
    }
  });

  test('a broad country alone is never treated as a fuzzy city', () {
    expect(
      StylistDestinationParser.inferFromConversation(
        'Cestujeme do USA a popozeráme sa po meste.',
      ),
      isNull,
    );
  });

  test('city matching uses whole words and the latest explicit place', () {
    expect(
      StylistDestinationParser.inferFromConversation(
        'Ideme do Prahy a chcem poradit co zbalit na cely pobyt.',
      ),
      'Praha',
    );
    expect(
      StylistDestinationParser.inferFromConversation(
        'Najprv sme chceli ist do Ziliny, ale ostavame pri Martine.',
      ),
      'Martin',
    );
  });

  test('outfit explanation questions never become explicit swaps', () {
    for (final text in [
      'preco si vybral tieto tenisky',
      'ako sa k tomu hodia topanky',
      'z akeho dovodu je tam bunda',
      'preco nie su lepsie kratasy',
    ]) {
      expect(StylistSwapRequest.parse(text), isNull, reason: text);
    }
    expect(StylistSwapRequest.parse('daj mi ine tenisky'), isNotNull);
  });
}
