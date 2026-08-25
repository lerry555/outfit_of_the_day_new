import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outfitofTheDay/Services/calendar_outfit_ownership.dart';
import 'package:outfitofTheDay/Services/calendar_outfit_service.dart';
import 'package:outfitofTheDay/Services/date_weather_service.dart';
import 'package:outfitofTheDay/Services/home_daily_outfit_cache_service.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_item_v2.dart';
import 'package:outfitofTheDay/domain/wardrobe_v2/wardrobe_v2_resolver.dart';

DateWeatherSnapshot _snap({
  required int tempC,
  bool isRainy = false,
  bool isWindy = false,
  int? eveningTempC,
}) {
  return DateWeatherSnapshot(
    tempC: tempC,
    isRainy: isRainy,
    isWindy: isWindy,
    seasonLabel: 'Leto',
    seasonKey: 'let',
    forecastAvailable: true,
    sourceLabel: 'Predpoveď',
    summarySubtitle: '$tempC°C',
    fromOpenMeteo: true,
    cityLabel: 'Martin',
    dateKey: '2026-08-25',
    eveningTempC: eveningTempC,
  );
}

WardrobeItemV2 _item(
  String type,
  String family,
  List<String> slots,
  String layer, {
  int warmth = 4,
  int formality = 4,
  List<String> functions = const [],
}) {
  return WardrobeItemV2(
    canonicalType: type,
    canonicalFamily: family,
    bodySlots: slots,
    layerPosition: layer,
    outfitFunctions: functions,
    colorProfile: const ColorProfileV2(
      primary: SemanticColorV2(family: 'navy'),
    ),
    formality: formality,
    styles: const ['casual'],
    occasionFit: const ['everyday'],
    seasons: const ['summer'],
    warmth: warmth,
    attributes: const {},
    fieldSources: const {'canonicalType': 'visual_ai'},
    fieldConfidence: const {'canonicalType': 0.9},
    userOverrideFields: const [],
  );
}

ResolvedWardrobeItemV2 _resolved(String id, WardrobeItemV2 item) {
  return ResolvedWardrobeItemV2(itemId: id, item: item, raw: {'id': id});
}

List<ResolvedWardrobeItemV2> _planningWardrobe() {
  return [
    _resolved(
      'tee',
      _item('t_shirt', 'top', const ['upper_body'], 'base', warmth: 3),
    ),
    _resolved(
      'jeans',
      _item('jeans', 'bottom', const ['lower_body'], 'base', warmth: 4),
    ),
    _resolved(
      'sneakers',
      _item('sneakers', 'footwear', const ['feet'], 'not_applicable', warmth: 3),
    ),
    _resolved(
      'sandals',
      _item('sandals', 'footwear', const ['feet'], 'not_applicable', warmth: 1),
    ),
    _resolved(
      'cardigan',
      _item('cardigan', 'knitwear', const ['upper_body'], 'mid', warmth: 5),
    ),
    _resolved(
      'rain_jacket',
      _item(
        'rain_jacket',
        'outerwear',
        const ['upper_body'],
        'shell',
        warmth: 5,
        functions: const ['weather_protection'],
      ),
    ),
    _resolved(
      'winter_coat',
      _item('parka', 'outerwear', const ['upper_body'], 'outer', warmth: 8),
    ),
  ];
}

void main() {
  group('Calendar composition request semantics', () {
    test('warm dry day does not require weather protection', () {
      final request = CalendarOutfitService.compositionRequestFor(
        _snap(tempC: 26, eveningTempC: 24),
      );
      final context = CalendarOutfitService.compositionContextFor(
        _snap(tempC: 26, eveningTempC: 24),
      );

      expect(request.weatherProtectionRequired, isFalse);
      expect(request.tempC, 26);
      expect(request.eveningTempC, 24);
      expect(request.feelsLikeC, isNull);
      expect(request.activityType, isEmpty);
      expect(context.isRainy, isFalse);
      expect(context.isWindy, isFalse);
    });

    test('cold day carries low tempC into V2 request', () {
      final request = CalendarOutfitService.compositionRequestFor(
        _snap(tempC: 4, eveningTempC: 1),
      );

      expect(request.tempC, 4);
      expect(request.eveningTempC, 1);
      expect(request.effectiveTempC, 4);
    });

    test('rain sets protection and distinct isRainy on matrix context', () {
      final weather = _snap(tempC: 16, isRainy: true, eveningTempC: 14);
      final request = CalendarOutfitService.compositionRequestFor(weather);
      final context = CalendarOutfitService.compositionContextFor(weather);

      expect(request.weatherProtectionRequired, isTrue);
      expect(context.isRainy, isTrue);
      expect(context.isWindy, isFalse);
      expect(context.weatherProtectionRequired, isTrue);
    });

    test('wind sets protection and distinct isWindy on matrix context', () {
      final weather = _snap(tempC: 14, isWindy: true, eveningTempC: 12);
      final request = CalendarOutfitService.compositionRequestFor(weather);
      final context = CalendarOutfitService.compositionContextFor(weather);

      expect(request.weatherProtectionRequired, isTrue);
      expect(context.isRainy, isFalse);
      expect(context.isWindy, isTrue);
    });

    test('warm afternoon + cool evening preserves eveningTempC', () {
      final request = CalendarOutfitService.compositionRequestFor(
        _snap(tempC: 22, eveningTempC: 10),
      );

      expect(request.tempC, 22);
      expect(request.eveningTempC, 10);
      expect(request.weatherProtectionRequired, isFalse);
    });

    test('eveningTempC is omitted when the weather service did not provide it', () {
      final request = CalendarOutfitService.compositionRequestFor(
        _snap(tempC: 18),
      );
      expect(request.eveningTempC, isNull);
    });
  });

  group('Calendar deterministic engine integration', () {
    test('rain prefers closed footwear over sandals', () {
      final outfit = CalendarOutfitService.composeForCalendar(
        _planningWardrobe(),
        _snap(tempC: 18, isRainy: true, eveningTempC: 16),
      );
      expect(outfit, isNotNull);
      final feet = outfit!.items.where(
        (item) => item.item.bodySlots.contains('feet'),
      );
      expect(feet, isNotEmpty);
      expect(feet.first.itemId, isNot('sandals'));
    });

    test('cool evening can introduce a mid layer', () {
      final outfit = CalendarOutfitService.composeForCalendar(
        _planningWardrobe(),
        _snap(tempC: 22, eveningTempC: 10),
      );
      expect(outfit, isNotNull);
      expect(
        outfit!.items.any((item) => item.item.layerPosition == 'mid'),
        isTrue,
      );
    });

    test('warm dry day does not require a heavy winter coat', () {
      final outfit = CalendarOutfitService.composeForCalendar(
        _planningWardrobe(),
        _snap(tempC: 28, eveningTempC: 26),
      );
      expect(outfit, isNotNull);
      expect(
        outfit!.items.any((item) => item.itemId == 'winter_coat'),
        isFalse,
      );
    });

    test('uses resolved V2 item fields rather than legacy type mapping', () {
      final outfit = CalendarOutfitService.composeForCalendar(
        _planningWardrobe(),
        _snap(tempC: 20, eveningTempC: 18),
      );
      expect(outfit, isNotNull);
      for (final piece in outfit!.items) {
        expect(piece.item.canonicalType, isNotEmpty);
        expect(piece.item.canonicalFamily, isNotEmpty);
        expect(piece.item.bodySlots, isNotEmpty);
      }
    });
  });

  group('Phase 3 ownership still bypasses Calendar composition', () {
    test('homeDaily source does not allow Calendar write/regenerate', () {
      final now = DateTime(2026, 8, 17);
      final daily = HomeDailyOutfitCacheDocument(
        dateKey: '2026-08-17',
        itemIds: const ['home-top'],
        items: const [
          {'type': 'top', 'label': 'Home tee', 'wardrobeItemId': 'home-top'},
        ],
        reasonText: 'Home',
        weatherSignature: '20|0|0|let',
        wardrobeSignature: '1:home-top',
        source: 'ai_generated',
        userModified: false,
      );
      final resolved = CalendarOutfitOwnership.resolve(
        date: now,
        now: now,
        daily: daily,
        calendar: null,
      );
      expect(resolved.source, CalendarOutfitSource.homeDaily);
      expect(resolved.allowsCalendarWrite, isFalse);
    });
  });

  group('future Calendar persistence path', () {
    test('still writes calendar_outfits and never daily_outfits', () {
      final service = File(
        'lib/Services/calendar_outfit_service.dart',
      ).readAsStringSync();
      expect(service.contains("collection('calendar_outfits')"), isTrue);
      expect(service.contains("collection('daily_outfits')"), isTrue);
      expect(service.contains('composeForCalendar'), isTrue);
      expect(service.contains('NativeOutfitEngineV2.compose'), isTrue);
      expect(service.contains('V2FlexibleCandidateMatrix.generate'), isTrue);
      expect(service.contains('.delete('), isFalse);
      expect(service.contains("_dailyOutfitCache.save"), isFalse);
      expect(service.contains("_dailyDocRef(uid, key).set"), isFalse);
      expect(service.contains("_dayDocRef(uid: uid, dateKey: key).set"), isTrue);
    });
  });
}
