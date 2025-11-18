// lib/screens/public_wardrobe_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:outfitofTheDay/constants/app_constants.dart';
import 'package:outfitofTheDay/screens/clothing_detail_screen.dart';
import 'package:outfitofTheDay/screens/user_wardrobe_detail_screen.dart'; // TENTO IMPORT MUSÍ BYŤ PRÍTOMNÝ

class PublicWardrobeScreen extends StatefulWidget {
  const PublicWardrobeScreen({Key? key}) : super(key: key);

  @override
  _PublicWardrobeScreenState createState() => _PublicWardrobeScreenState();
}

class _PublicWardrobeScreenState extends State<PublicWardrobeScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _user = FirebaseAuth.instance.currentUser;

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Verejné šatníky'),
        ),
        body: const Center(
          child: Text('Pre zobrazenie verejných šatníkov sa musíte prihlásiť.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verejné šatníky'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('public_wardrobe').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Chyba pri načítavaní: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text('Zatiaľ nikto nezdieľal svoje oblečenie.'),
            );
          }

          Map<String, List<Map<String, dynamic>>> groupedItems = {};
          for (var doc in snapshot.data!.docs) {
            final itemData = doc.data() as Map<String, dynamic>;
            final userId = itemData['userId'] as String? ?? 'Neznámy';
            if (!groupedItems.containsKey(userId)) {
              groupedItems[userId] = [];
            }
            groupedItems[userId]!.add(itemData);
          }

          final List<String> userIds = groupedItems.keys.toList();

          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: userIds.length,
            itemBuilder: (context, index) {
              final userId = userIds[index];
              final items = groupedItems[userId]!;
              final int sharedCount = items.length;
              final String? imageUrl = items.firstWhere((item) => item['imageUrl'] != null, orElse: () => {})['imageUrl'];
              final String? userName = items.firstWhere((item) => item['userName'] != null, orElse: () => {})['userName'];

              return Card(
                elevation: 4.0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
                    child: imageUrl == null ? const Icon(Icons.person) : null,
                  ),
                  title: Text(userName != null ? 'Šatník od: $userName' : 'Šatník: $userId', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Zdieľa $sharedCount kúskov'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UserWardrobeDetailScreen(
                          userId: userId,
                          userName: userName,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
