import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/utils/home_debug_logging.dart';

void main() {
  test('Wardrobe V2 is the safe source-code default', () {
    expect(kUseResolvedWardrobeProfilesInHome, isTrue);
    expect(kUseResolvedWardrobeProfilesInChat, isTrue);
  });
}
