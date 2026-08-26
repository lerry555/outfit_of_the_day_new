import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/stylist_chat_service.dart';
import 'package:outfitofTheDay/Services/user_style_preferences_reader.dart';
import 'package:outfitofTheDay/domain/style_preferences/style_preferences_runtime.dart';
import 'package:outfitofTheDay/domain/style_preferences/styling_presentation.dart';
import 'package:outfitofTheDay/domain/style_preferences/user_style_preferences.dart';

void main() {
  tearDown(() => StylePreferencesRuntime.debugOverrideEnabled(null));
  group('UserStylePreferences model', () {
    test('missing document and empty arrays omit Stylist payload', () {
      expect(UserStylePreferences.fromMap(null).toStylistPayload(), isNull);
      expect(UserStylePreferences.fromMap({}).toStylistPayload(), isNull);
      expect(
        UserStylePreferences.fromMap({
          'favoriteColors': <String>[],
          'avoidedColors': <String>[],
          'preferredStyles': <String>[],
          'favoriteBrands': <String>[],
          'topSize': 'M',
          'shoeSize': '42',
        }).toStylistPayload(),
        isNull,
      );
    });

    test('preferredStyles Casual is canonicalized for Stylist', () {
      final payload = UserStylePreferences.fromMap({
        'preferredStyles': ['Casual'],
      }).toStylistPayload();
      expect(payload, isNotNull);
      expect(payload!['preferredStyles'], ['casual']);
    });

    test('styling presentation is explicit authority and not inferred', () {
      final prefs = UserStylePreferences.fromMap({
        'stylingPresentation': 'menswear',
      });
      expect(prefs.stylingPresentation, StylingPresentation.menswear);
      expect(prefs.toStylistPayload(), {'stylingPresentation': 'menswear'});
      expect(
        UserStylePreferences.fromMap({
          'preferredStyles': ['Romantický'],
        }).stylingPresentation,
        StylingPresentation.noPreference,
      );
    });

    test('avoidedColors Červená is a taste avoid, not a size/safety field', () {
      final payload = UserStylePreferences.fromMap({
        'avoidedColors': ['Červená'],
      }).toStylistPayload();
      expect(payload, isNotNull);
      expect(payload!['avoidedColors'], ['red']);
      expect(payload.containsKey('topSize'), isFalse);
      expect(payload.containsKey('shoeSize'), isFalse);
    });

    test('favoriteColors Modrá is a soft preference in the payload', () {
      final payload = UserStylePreferences.fromMap({
        'favoriteColors': ['Modrá'],
      }).toStylistPayload();
      expect(payload, isNotNull);
      expect(payload!['favoriteColors'], ['blue']);
    });

    test('favoriteBrands are included without sizes or unrelated fields', () {
      final payload = UserStylePreferences.fromMap({
        'favoriteBrands': ['Zara'],
        'pantsSize': '32',
        'bottomSize': 'legacy-bottom',
        'email': 'hidden@example.com',
        'dislikedColorCombinations': ['red+green'],
      }).toStylistPayload();
      expect(payload, isNotNull);
      expect(payload!.keys.toList()..sort(), ['favoriteBrands']);
      expect(payload['favoriteBrands'], ['Zara']);
    });

    test(
      'legacy bottomSize is read for pantsSize only, never sent to Stylist',
      () {
        final prefs = UserStylePreferences.fromMap({
          'bottomSize': 'L',
          'preferredStyles': ['Elegantný'],
        });
        expect(prefs.pantsSize, 'L');
        final payload = prefs.toStylistPayload();
        expect(payload!['preferredStyles'], ['elegant']);
        expect(payload.containsKey('pantsSize'), isFalse);
        expect(payload.containsKey('bottomSize'), isFalse);
      },
    );

    test(
      'legacy root-shaped fields are not merged into the Stylist payload',
      () {
        final payload = UserStylePreferences.fromMap({
          'favoriteColors': ['Biela'],
          'dislikedColorCombinations': ['black+navy'],
          'preferredStyles': ['Streetwear'],
        }).toStylistPayload();
        expect(payload!['favoriteColors'], ['white']);
        expect(payload['preferredStyles'], ['streetwear']);
        expect(payload.containsKey('dislikedColorCombinations'), isFalse);
      },
    );
  });

  group('Stylist preference payload resolution', () {
    test(
      'missing prefs keep the Stylist request valid without the field',
      () async {
        final payload = <String, dynamic>{'message': 'Čo si mám obliecť?'};
        final prefs = await StylistChatService.resolveStylePreferencesPayload(
          _FakeStylePreferencesReader(UserStylePreferences.empty),
          'uid-1',
        );
        if (prefs != null) {
          payload['userStylePreferences'] = prefs;
        }
        expect(payload.containsKey('userStylePreferences'), isFalse);
        expect(payload['message'], 'Čo si mám obliecť?');
      },
    );

    test('read failure does not block Stylist send', () async {
      final prefs = await StylistChatService.resolveStylePreferencesPayload(
        _ThrowingStylePreferencesReader(),
        'uid-1',
      );
      expect(prefs, isNull);
    });

    test(
      'saved taste is omitted when runtime consumption is disabled',
      () async {
        StylePreferencesRuntime.debugOverrideEnabled(false);
        final saved = UserStylePreferences.fromMap({
          'preferredStyles': ['Casual'],
          'avoidedColors': ['Červená'],
          'favoriteColors': ['Modrá'],
          'favoriteBrands': ['Nike'],
        });
        final prefs = await StylistChatService.resolveStylePreferencesPayload(
          _FakeStylePreferencesReader(saved),
          'uid-1',
        );
        expect(prefs, isNull);
      },
    );

    test(
      'explicit presentation is retained when soft taste is disabled',
      () async {
        StylePreferencesRuntime.debugOverrideEnabled(false);
        final prefs = await StylistChatService.resolveStylePreferencesPayload(
          _FakeStylePreferencesReader(
            const UserStylePreferences(
              favoriteColors: <String>['Červená'],
              stylingPresentation: StylingPresentation.menswear,
            ),
          ),
          'uid-1',
        );
        expect(prefs, <String, dynamic>{'stylingPresentation': 'menswear'});
      },
    );

    test(
      'saved taste is attached as userStylePreferences when runtime is on',
      () async {
        StylePreferencesRuntime.debugOverrideEnabled(true);
        final prefs = await StylistChatService.resolveStylePreferencesPayload(
          _FakeStylePreferencesReader(
            UserStylePreferences.fromMap({
              'preferredStyles': ['Casual'],
              'avoidedColors': ['Červená'],
              'favoriteColors': ['Modrá'],
              'favoriteBrands': ['Nike'],
              'shoeSize': '42',
            }),
          ),
          'uid-1',
        );
        expect(prefs, {
          'preferredStyles': ['casual'],
          'avoidedColors': ['red'],
          'favoriteColors': ['blue'],
          'favoriteBrands': ['Nike'],
        });
      },
    );
  });

  group('wiring and isolation', () {
    test('reader only addresses users/{uid}/stylePreferences/main', () {
      final src = File(
        'lib/Services/user_style_preferences_reader.dart',
      ).readAsStringSync();
      expect(src.contains("collectionId = 'stylePreferences'"), isTrue);
      expect(src.contains("documentId = 'main'"), isTrue);
      expect(src.contains(".collection('users')"), isTrue);
      expect(src.contains('.collection(collectionId)'), isTrue);
      expect(src.contains('.doc(documentId)'), isTrue);
      expect(src.contains('dislikedColorCombinations'), isFalse);
      expect(src.contains('userPreferences'), isFalse);
      expect(src.contains("collection('userPreferences')"), isFalse);
    });

    test(
      'StylistChatService attaches userStylePreferences and never sends sizes',
      () {
        final src = File(
          'lib/Services/stylist_chat_service.dart',
        ).readAsStringSync();
        expect(src.contains("payload['userStylePreferences']"), isTrue);
        expect(src.contains('resolveStylePreferencesPayload'), isTrue);
        expect(src.contains("'topSize'"), isFalse);
        expect(src.contains("'shoeSize'"), isFalse);
        expect(src.contains("'pantsSize'"), isFalse);
      },
    );

    test('presentation authority is read at orchestration boundaries only', () {
      for (final path in const [
        'lib/Services/calendar_outfit_service.dart',
        'lib/Services/stylist_chat_outfit_service.dart',
        'lib/Services/trip_packing_service.dart',
      ]) {
        expect(
          File(path).readAsStringSync().contains('UserStylePreferencesReader'),
          isTrue,
          reason: '$path must load the explicit presentation preference',
        );
      }
      const untouched = [
        'lib/utils/home_wardrobe_read_path.dart',
        'lib/screens/trip_planner_screen.dart',
        'lib/domain/wardrobe_v2/native_outfit_engine_v2.dart',
      ];
      for (final path in untouched) {
        final src = File(path).readAsStringSync();
        expect(
          src.contains('UserStylePreferencesReader'),
          isFalse,
          reason:
              '$path must receive preference data rather than read Firestore',
        );
        expect(
          src.contains('userStylePreferences'),
          isFalse,
          reason: '$path must not send style preferences in Phase 2',
        );
      }
    });

    test(
      'flag off still sends the current-turn message, not saved taste',
      () async {
        StylePreferencesRuntime.debugOverrideEnabled(false);
        final payload = <String, dynamic>{'message': 'Chcem modrý outfit'};
        final prefs = await StylistChatService.resolveStylePreferencesPayload(
          _FakeStylePreferencesReader(
            UserStylePreferences.fromMap({
              'favoriteColors': ['Červená'],
            }),
          ),
          'uid-1',
        );
        if (prefs != null) {
          payload['userStylePreferences'] = prefs;
        }
        expect(payload['message'], 'Chcem modrý outfit');
        expect(payload.containsKey('userStylePreferences'), isFalse);
      },
    );

    test(
      'prompt contract ranks current request and suitability above saved taste',
      () {
        final src = File(
          'functions/stylist/style_preferences_context.js',
        ).readAsStringSync();
        expect(src.contains('aktuálna správa používateľa'), isTrue);
        expect(src.contains('prebiť'), isTrue);
        expect(src.contains('nie tvrdé bezpečnostné pravidlo'), isTrue);
        expect(src.contains('suitability vyhrá'), isTrue);
        expect(src.contains('soft preference'), isTrue);
        expect(
          src.contains('weak preference only when a wardrobe item'),
          isTrue,
        );
        expect(src.contains('favoriteColors contains'), isTrue);
      },
    );
  });
}

class _FakeStylePreferencesReader extends UserStylePreferencesReader {
  _FakeStylePreferencesReader(this.prefs);

  final UserStylePreferences prefs;

  @override
  Future<UserStylePreferences> loadForUid(String? uid) async => prefs;
}

class _ThrowingStylePreferencesReader extends UserStylePreferencesReader {
  @override
  Future<UserStylePreferences> loadForUid(String? uid) async {
    throw StateError('stylePreferences unavailable');
  }
}
