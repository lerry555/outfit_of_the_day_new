// lib/screens/public_clothing_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:outfitofTheDay/constants/app_constants.dart';

class PublicClothingDetailScreen extends StatelessWidget {
  final Map<String, dynamic> clothingItemData;

  const PublicClothingDetailScreen({
    Key? key,
    required this.clothingItemData,
  }) : super(key: key);

  Future<void> _addClothingToMyWardrobe(BuildContext context) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chyba: Pre pridanie oblečenia sa musíte prihlásiť.')),
      );
      return;
    }

    try {
      final Map<String, dynamic> newClothingData = {
        'category': clothingItemData['category'],
        'color': clothingItemData['color'],
        'style': clothingItemData['style'],
        'pattern': clothingItemData['pattern'],
        'brand': clothingItemData['brand'],
        'season': clothingItemData['season'],
        'imageUrl': clothingItemData['imageUrl'],
        'uploadedAt': FieldValue.serverTimestamp(),
        'isClean': true, // Nová položka je predvolene čistá
        'wearCount': 0, // Počet nosení začína na 0
        'isSharable': false, // Nová položka nie je predvolene zdieľaná
        'id': FirebaseFirestore.instance.collection('users').doc(user.uid).collection('wardrobe').doc().id,
        'userName': user.displayName,
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('wardrobe')
          .doc(newClothingData['id'])
          .set(newClothingData);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Oblečenie bolo úspešne pridané do vášho šatníka!')),
      );

      Navigator.of(context).pop();
    } catch (e) {
      print('Chyba pri pridávaní oblečenia: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba pri pridávaní oblečenia: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final String imageUrl = clothingItemData['imageUrl'] as String? ?? '';
    final String itemCategory = clothingItemData['category'] as String? ?? 'Neznáma kategória';
    final List<dynamic> colorsData = clothingItemData['color'] is List ? clothingItemData['color'] : (clothingItemData['color'] != null ? [clothingItemData['color']] : []);
    final String color = colorsData.isNotEmpty ? (colorsData.first.toString()) : 'Neznáma farba';
    final List<dynamic> stylesData = clothingItemData['style'] is List ? clothingItemData['style'] : (clothingItemData['style'] != null ? [clothingItemData['style']] : []);
    final String style = stylesData.isNotEmpty ? (stylesData.first.toString()) : 'Neznámy štýl';
    final List<dynamic> patternsData = clothingItemData['pattern'] is List ? clothingItemData['pattern'] : (clothingItemData['pattern'] != null ? [clothingItemData['pattern']] : []);
    final String pattern = patternsData.isNotEmpty ? (patternsData.first.toString()) : 'Neznámy vzor';
    final String brand = clothingItemData['brand'] as String? ?? 'Neznáma značka';
    final List<dynamic> seasonsData = clothingItemData['season'] is List ? clothingItemData['season'] : (clothingItemData['season'] != null ? [clothingItemData['season']] : []);
    final String season = seasonsData.isNotEmpty ? (seasonsData.first.toString()) : 'Neznáma sezóna';

    final String? userName = clothingItemData['userName'] as String? ?? 'Neznámy používateľ';
    final String? userId = clothingItemData['userId'] as String? ?? 'Neznámy používateľ';

    return Scaffold(
      appBar: AppBar(
        title: Text(itemCategory),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl.isNotEmpty)
              Center(
                child: Image.network(
                  imageUrl,
                  height: 300,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(Icons.broken_image, size: 100.0);
                  },
                ),
              ),
            if (imageUrl.isEmpty)
              const Center(
                child: Text('Bez obrázka', style: TextStyle(fontSize: 18.0)),
              ),
            const SizedBox(height: 20),
            _buildInfoRow('Kategória:', itemCategory),
            _buildInfoRow('Farba:', color),
            _buildInfoRow('Štýl:', style),
            _buildInfoRow('Vzor:', pattern),
            _buildInfoRow('Značka:', brand),
            _buildInfoRow('Sezóna:', season),
            const SizedBox(height: 20),
            _buildInfoRow('Zdieľal:', userName ?? userId),
            _buildInfoRow('Nahrané:', (clothingItemData['uploadedAt'] as Timestamp?)?.toDate().toString().split(' ')[0] ?? 'N/A'),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          onPressed: () => _addClothingToMyWardrobe(context),
          child: const Text('Pridať do šatníka'),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value ?? 'N/A'),
          ),
        ],
      ),
    );
  }
}