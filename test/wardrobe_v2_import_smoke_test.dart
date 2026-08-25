import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_ontology_v2.dart';

void main() {
  test('imports V2 ontology without app or Firebase startup', () {
    expect(WardrobeOntologyV2Values.ontologyVersion, '2.0.0');
  });
}
