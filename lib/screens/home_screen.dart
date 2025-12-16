// lib/screens/home_screen.dart

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'add_clothing_screen.dart';
import 'wardrobe_screen.dart';
import 'select_outfit_screen.dart';
import 'recommended_screen.dart';
import 'friends_screen.dart';
import 'messages_screen.dart';
import 'user_preferences_screen.dart';
import 'stylist_chat_screen.dart'; // 👈 AI chat screen

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  File? _selectedOutfitImage;
  bool _isAddingSampleWardrobe = false;

  Future<void> _pickOutfitImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _selectedOutfitImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _saveOutfitImage() async {
    // TODO: Implement saving the outfit image to Firebase Storage or Firestore
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ukladanie outfitu zatiaľ nie je implementované.'),
      ),
    );
  }

  Future<void> _addSampleWardrobe() async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() {
      _isAddingSampleWardrobe = true;
    });

    try {
      final wardrobeCollection = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('wardrobe');

      // Example sample data
      final sampleItems = [
        {
          'name': 'Čierne tričko',
          'category': 'top',
          'color': 'čierna',
          'season': 'leto',
        },
        {
          'name': 'Modré rifle',
          'category': 'bottom',
          'color': 'modrá',
          'season': 'celoročne',
        },
      ];

      for (final item in sampleItems) {
        await wardrobeCollection.add(item);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vzorový šatník bol pridaný.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nepodarilo sa pridať vzorový šatník.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAddingSampleWardrobe = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final greetingName = _getGreetingName(user);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Outfit Of The Day'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _auth.signOut();
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const DrawerHeader(
                child: Text(
                  'Menu',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: const Text('Priatelia'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const FriendsScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.diversity_2),
                title: const Text('Správy a zladenie outfitov'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MessagesScreen(),
                    ),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Nastavenia'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const UserPreferencesScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$greetingName 👋',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Poďme vybrať tvoj dnešný outfit.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),

            /// DNEŠNÝ OUTFIT
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const SelectOutfitScreen(),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.checkroom, size: 40),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Vybrať dnešný outfit',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            /// RECOMMENDED
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _openRecommended,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.star_border, size: 40),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Odporúčané kúsky a outfity',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            /// 🧠 AI STYLISTA – NOVÁ HLAVNÁ KARTA
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const StylistChatScreen(),
                  ),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.smart_toy_outlined,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "AI Stylista",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            "Opýtaj sa ma čokoľvek o móde, kombináciách a outfitoch.",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.white70,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            /// ✅ Pridať nové oblečenie (BOTTOM SHEET)
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => AddClothingScreen.openFromPicker(context),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.add_photo_alternate_outlined, size: 40),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Pridať nové oblečenie',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            /// VZOROVÝ ŠATNÍK – len pomoc pre testovanie
            if (_isAddingSampleWardrobe)
              const Center(child: CircularProgressIndicator())
            else
              TextButton.icon(
                onPressed: _addSampleWardrobe,
                icon: const Icon(Icons.download),
                label: const Text('Pridať vzorový šatník (na testovanie)'),
              ),
          ],
        ),
      ),
    );
  }

  void _openRecommended() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const RecommendedScreen(initialTab: 0),
      ),
    );
  }

  String _getGreetingName(User? user) {
    if (user == null) return 'Ahoj';
    final displayName = user.displayName;
    if (displayName == null || displayName.trim().isEmpty) {
      return 'Ahoj';
    }
    final firstName = displayName.split(' ').first;
    return 'Ahoj, $firstName';
  }
}
