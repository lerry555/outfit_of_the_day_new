// lib/screens/user_wardrobe_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:outfitofTheDay/screens/clothing_detail_screen.dart';
import 'package:outfitofTheDay/screens/public_clothing_detail_screen.dart';
import 'package:outfitofTheDay/constants/app_constants.dart';

class UserWardrobeDetailScreen extends StatelessWidget {
  final String userId;
  final String? userName;

  const UserWardrobeDetailScreen({
    Key? key,
    required this.userId,
    this.userName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    final bool isMyPublicWardrobe = currentUser?.uid == userId;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isMyPublicWardrobe
              ? 'Môj verejný šatník'
              : 'Šatník: ${userName ?? userId}',
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('public_wardrobe')
            .where('userId', isEqualTo: userId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Chyba pri načítavaní: ${snapshot.error}'),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text('Používateľ zatiaľ nič nezdieľal.'),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16.0),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16.0,
              mainAxisSpacing: 16.0,
              childAspectRatio: 0.75,
            ),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final DocumentSnapshot doc = snapshot.data!.docs[index];
              final Map<String, dynamic> itemData =
              doc.data() as Map<String, dynamic>;

              // 👇 TU JE DÔLEŽITÁ ZMENA
              // Ak existuje cleanImageUrl (obrázok bez pozadia), použijeme ten.
              // Inak fallback na pôvodné imageUrl.
              final String imageUrl =
              (itemData['cleanImageUrl'] as String?)?.isNotEmpty == true
                  ? itemData['cleanImageUrl'] as String
                  : itemData['imageUrl'] as String? ?? '';

              final String itemCategory =
                  itemData['category'] as String? ?? 'Neznáma kategória';

              return Card(
                elevation: 4.0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PublicClothingDetailScreen(
                          clothingItemData: itemData,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(10.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(10.0),
                          ),
                          child: imageUrl.isNotEmpty
                              ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                          )
                              : const Center(child: Text('Bez obrázka')),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          itemCategory,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
