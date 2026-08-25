import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String home;
  late String profile;
  late String stylePrefs;
  late String userPrefs;

  setUpAll(() {
    home = File('lib/screens/home_screen.dart').readAsStringSync();
    profile = File('lib/screens/profile_screen.dart').readAsStringSync();
    stylePrefs =
        File('lib/screens/style_preferences_screen.dart').readAsStringSync();
    userPrefs =
        File('lib/screens/user_preferences_screen.dart').readAsStringSync();
  });

  test('Profile Style Preferences still opens StylePreferencesScreen', () {
    expect(profile.contains("title: 'Štýlové preferencie'"), isTrue);
    expect(
      profile.contains('builder: (_) => const StylePreferencesScreen()'),
      isTrue,
    );
  });

  test('Home drawer settings entry opens the same StylePreferencesScreen', () {
    expect(
      home.contains('builder: (_) => const StylePreferencesScreen()'),
      isTrue,
    );
    expect(home.contains('import \'style_preferences_screen.dart\''), isTrue);
  });

  test('production navigation no longer opens UserPreferencesScreen', () {
    expect(home.contains('UserPreferencesScreen'), isFalse);
    expect(profile.contains('UserPreferencesScreen'), isFalse);
    expect(home.contains('user_preferences_screen.dart'), isFalse);
    expect(profile.contains('user_preferences_screen.dart'), isFalse);
  });

  test('StylePreferencesScreen still persists to stylePreferences/main', () {
    expect(stylePrefs.contains(".collection('stylePreferences')"), isTrue);
    expect(stylePrefs.contains(".doc('main')"), isTrue);
    expect(stylePrefs.contains("'favoriteColors'"), isTrue);
    expect(stylePrefs.contains("'avoidedColors'"), isTrue);
    expect(stylePrefs.contains("'preferredStyles'"), isTrue);
    expect(stylePrefs.contains("'favoriteBrands'"), isTrue);
    expect(stylePrefs.contains("'topSize'"), isTrue);
    expect(stylePrefs.contains("'outerwearSize'"), isTrue);
    expect(stylePrefs.contains("'pantsSize'"), isTrue);
    expect(stylePrefs.contains("'shortsSize'"), isTrue);
    expect(stylePrefs.contains("'shoeSize'"), isTrue);
    expect(stylePrefs.contains("data['bottomSize']"), isTrue);
  });

  test('no new writes to legacy user-root style fields were introduced', () {
    expect(stylePrefs.contains("'dislikedColorCombinations'"), isFalse);
    expect(home.contains("'favoriteColors'"), isFalse);
    expect(home.contains("'preferredStyles'"), isFalse);
    expect(home.contains("'dislikedColorCombinations'"), isFalse);
    expect(
      stylePrefs.contains(".collection('stylePreferences')"),
      isTrue,
    );
    expect(
      RegExp(
        r"collection\('users'\)\s*\.doc\([^)]+\)\s*\.set\(",
      ).hasMatch(stylePrefs),
      isFalse,
      reason: 'live editor must not set() the user root document',
    );
  });

  test('misleading AI Stylist consumption copy is gone', () {
    expect(stylePrefs.contains('Pomôž AI stylistovi'), isFalse);
    expect(stylePrefs.contains('Nastav si svoje štýlové preferencie.'), isTrue);
    expect(stylePrefs.toLowerCase().contains('ai stylistovi'), isFalse);
  });

  test('intentional Profile Settings placeholder sheet remains intact', () {
    expect(profile.contains("title: 'Nastavenia'"), isTrue);
    expect(profile.contains('onTap: _openSettingsSheet'), isTrue);
    expect(profile.contains("label: 'Notifikácie'"), isTrue);
    expect(profile.contains("label: 'Súkromie a dáta'"), isTrue);
    expect(profile.contains("label: 'Jazyk aplikácie'"), isTrue);
    expect(profile.contains("label: 'Vzhľad aplikácie'"), isTrue);
    expect(profile.contains("label: 'Účet'"), isTrue);
    expect(profile.contains('pripravujeme'), isTrue);
  });

  test('UserPreferencesScreen file is retained as legacy', () {
    expect(userPrefs.contains('class UserPreferencesScreen'), isTrue);
    expect(File('lib/screens/user_preferences_screen.dart').existsSync(), isTrue);
  });
}
