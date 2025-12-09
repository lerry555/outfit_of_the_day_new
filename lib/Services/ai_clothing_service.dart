// lib/services/ai_clothing_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AiClothingService {
  AiClothingService._();

  /// Zavolá Cloud Function `processClothingImage`, ktorá:
  /// - odstráni pozadie z imageUrl
  /// - spraví AI analýzu kúsku
  /// - uloží cleanImageUrl + aiMetadata do Firestore
  static Future<void> processClothingImageOnServer({
    required String itemId,
    required String imageUrl,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('User nie je prihlásený, neviem spracovať obrázok.');
      return;
    }

    const String functionUrl =
        'https://us-east1-outfitoftheday-4d401.cloudfunctions.net/processClothingImage';

    try {
      final body = jsonEncode({
        'imageUrl': imageUrl,
        'itemId': itemId,
        'userId': user.uid,
      });

      final response = await http.post(
        Uri.parse(functionUrl),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      debugPrint(
          'processClothingImage status: ${response.statusCode}, body: ${response.body}');

      if (response.statusCode != 200) {
        // nič dramatické – kúsok v šatníku zostane, len nebude mať AI údaje
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final cleanImageUrl = data['cleanImageUrl'];
      final metadata = data['metadata'];

      debugPrint('✅ Clean image URL: $cleanImageUrl');
      debugPrint('✅ AI metadata: $metadata');
    } catch (e) {
      debugPrint('❌ Chyba pri volaní processClothingImage: $e');
    }
  }
}
