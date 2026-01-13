import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PendingExternalItem {
  final String target; // "outfit_builder" | "stylist_chat" | "wishlist"
  final String bodyPart; // "torso" | "legs" | "feet" | "head" ...
  final String layerGroup; // "underwear" | "base" | "mid" | "outer" | "accessory"
  final String expectedType; // "tshirt" | "jacket" | "jeans" | "shoes" ...
  final int createdAtMs; // epoch ms

  const PendingExternalItem({
    required this.target,
    required this.bodyPart,
    required this.layerGroup,
    required this.expectedType,
    required this.createdAtMs,
  });

  Map<String, dynamic> toJson() => {
    'target': target,
    'bodyPart': bodyPart,
    'layerGroup': layerGroup,
    'expectedType': expectedType,
    'createdAtMs': createdAtMs,
  };

  static PendingExternalItem fromJson(Map<String, dynamic> json) {
    return PendingExternalItem(
      target: (json['target'] ?? '').toString(),
      bodyPart: (json['bodyPart'] ?? '').toString(),
      layerGroup: (json['layerGroup'] ?? '').toString(),
      expectedType: (json['expectedType'] ?? '').toString(),
      createdAtMs: (json['createdAtMs'] ?? 0) as int,
    );
  }
}

class PendingExternalItemService {
  static const _key = 'pending_external_item_v1';
  static const int _ttlMinutes = 10;

  static Future<void> set(PendingExternalItem item) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode(item.toJson()));
  }

  static Future<PendingExternalItem?> peek() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return null;

    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final item = PendingExternalItem.fromJson(data);

      final now = DateTime.now().millisecondsSinceEpoch;
      final ageMs = now - item.createdAtMs;
      final ttlMs = _ttlMinutes * 60 * 1000;

      if (ageMs > ttlMs) {
        await clear();
        return null;
      }
      return item;
    } catch (_) {
      await clear();
      return null;
    }
  }

  static Future<PendingExternalItem?> consume() async {
    final item = await peek();
    if (item != null) {
      await clear();
    }
    return item;
  }

  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key);
  }
}
