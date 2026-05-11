import 'package:cloud_firestore/cloud_firestore.dart';

import '../Services/date_weather_service.dart';
import '../Services/outfit_generation_service.dart';

class CalendarOutfitItem {
  final OutfitWearType type;
  final String label;

  // Image URLs needed for preview. Some fields are optional because older
  // Firestore docs might be missing them.
  final String? productImageUrl;
  final String? cutoutImageUrl;
  final String? cleanImageUrl;
  final String? originalImageUrl;
  final String? imageUrl; // legacy

  const CalendarOutfitItem({
    required this.type,
    required this.label,
    required this.productImageUrl,
    required this.cutoutImageUrl,
    required this.cleanImageUrl,
    required this.originalImageUrl,
    required this.imageUrl,
  });

  static String typeToKey(OutfitWearType type) => switch (type) {
        OutfitWearType.top => 'top',
        OutfitWearType.bottom => 'bottom',
        OutfitWearType.shoes => 'shoes',
        OutfitWearType.outerwear => 'outerwear',
      };

  static OutfitWearType typeFromKey(String? key) {
    switch (key) {
      case 'top':
        return OutfitWearType.top;
      case 'bottom':
        return OutfitWearType.bottom;
      case 'shoes':
        return OutfitWearType.shoes;
      case 'outerwear':
        return OutfitWearType.outerwear;
      default:
        return OutfitWearType.top;
    }
  }

  factory CalendarOutfitItem.fromMap(Map<String, dynamic> map) {
    String? getStr(String key) => map[key]?.toString();

    final typeKey = map['typeKey'] as String? ?? map['type'] as String?;

    final rawLabel = getStr('label') ?? getStr('itemName') ?? '';
    final label = rawLabel.trim();

    return CalendarOutfitItem(
      type: typeFromKey(typeKey),
      label: label.isNotEmpty ? label : 'Kúsok',
      productImageUrl: getStr('productImageUrl'),
      cutoutImageUrl: getStr('cutoutImageUrl'),
      cleanImageUrl: getStr('cleanImageUrl'),
      originalImageUrl: getStr('originalImageUrl'),
      imageUrl: getStr('imageUrl'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'typeKey': typeToKey(type),
      'label': label,
      'productImageUrl': productImageUrl,
      'cutoutImageUrl': cutoutImageUrl,
      'cleanImageUrl': cleanImageUrl,
      'originalImageUrl': originalImageUrl,
      'imageUrl': imageUrl,
    };
  }
}

class CalendarOutfitDay {
  final String dateKey; // yyyy-MM-dd
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? generatedAt;

  final DateWeatherSnapshot weatherSnapshot;

  final List<CalendarOutfitItem> outfitItems;
  final String generationSource;
  final int? version;
  final String? reason;
  const CalendarOutfitDay({
    required this.dateKey,
    required this.weatherSnapshot,
    required this.outfitItems,
    required this.generationSource,
    this.createdAt,
    this.updatedAt,
    this.generatedAt,
    this.version,
    this.reason,
  });

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }

  factory CalendarOutfitDay.fromFirestore({
    required String dateKey,
    required Map<String, dynamic> data,
  }) {
    final weatherRaw = data['weatherSnapshot'];
    final weatherMap =
        weatherRaw is Map ? weatherRaw.cast<String, dynamic>() : null;

    final weatherSnapshot = weatherMap != null
        ? DateWeatherSnapshot.fromJson(weatherMap)
        : DateWeatherSnapshot(
            tempC: 0,
            isRainy: false,
            isWindy: false,
            seasonLabel: 'Zima',
            seasonKey: 'zim',
            forecastAvailable: false,
            sourceLabel: 'Odhad',
            summarySubtitle: 'Zima • 0°C • jasno',
          );

    final itemsRaw = data['outfitItems'];
    final itemsList = itemsRaw is List ? itemsRaw : const [];
    final outfitItems = itemsList
        .whereType<Map>()
        .map((e) => CalendarOutfitItem.fromMap(e.cast<String, dynamic>()))
        .toList();

    return CalendarOutfitDay(
      dateKey: dateKey,
      createdAt: _ts(data['createdAt']),
      updatedAt: _ts(data['updatedAt']),
      generatedAt: _ts(data['generatedAt']),
      weatherSnapshot: weatherSnapshot,
      outfitItems: outfitItems,
      generationSource: (data['generationSource'] ?? 'calendar').toString(),
      version: data['version'] is int ? data['version'] as int : null,

      reason: data['reason']?.toString(),
    );
  }
}

