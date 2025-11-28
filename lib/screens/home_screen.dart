// lib/screens/home_screen.dart

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'add_clothing_screen.dart';
import 'daily_outfit_screen.dart';
import 'wardrobe_screen.dart';
import 'select_outfit_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();

  File? _selectedOutfitImage;

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final String greetingName =
    (user?.displayName != null && user!.displayName!.trim().isNotEmpty)
        ? user.displayName!.split(' ').first
        : 'Ahoj';

    return Scaffold(
      appBar: AppBar(
        title: const Text('#OOTD'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _auth.signOut();
              if (!mounted) return;
              // Main widget cez StreamBuilder presmeruje na login
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pozdrav
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

            // KARTA: Dnešný outfit
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.wb_sunny_outlined, size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Dnešný outfit',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'AI ti z tvojho šatníka vyberie outfit podľa počasia.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                  const DailyOutfitScreen(isTomorrow: false),
                                ),
                              );
                            },
                            child: const Text('Outfit na dnes'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                  const DailyOutfitScreen(isTomorrow: true),
                                ),
                              );
                            },
                            child: const Text('Outfit na zajtra'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // KARTA: Ohodnoť môj outfit
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.camera_alt_outlined, size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ohodnoť môj outfit',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Odfoti sa a neskôr ti AI povie, ako ti to pristane. (beta)',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.photo_camera_outlined),
                            onPressed: () => _pickImage(ImageSource.camera),
                            label: const Text('Odfotiť outfit'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.photo_library_outlined),
                            onPressed: () => _pickImage(ImageSource.gallery),
                            label: const Text('Z galérie'),
                          ),
                        ),
                      ],
                    ),
                    if (_selectedOutfitImage != null) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          _selectedOutfitImage!,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'AI analýza outfitu (skóre + tipy) doplníme v ďalšom kroku.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Sekcia: Šatník
            Text(
              'Spravovať šatník',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.dry_cleaning_outlined),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const WardrobeScreen(),
                        ),
                      );
                    },
                    label: const Text('Môj šatník'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AddClothingScreen(
                            initialData: <String, dynamic>{},
                            imageUrl: '',
                          ),
                        ),
                      );
                    },
                    label: const Text('Pridať nový kus'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.auto_awesome),
              onPressed: _addSampleWardrobe,
              label: const Text('Pridať vzorový šatník'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 80);
      if (picked == null) return;

      setState(() {
        _selectedOutfitImage = File(picked.path);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fotka outfitu pripravená. AI analýza bude doplnená.'),
        ),
      );
    } catch (e) {
      debugPrint('Chyba pri výbere obrázka: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nepodarilo sa načítať obrázok.')),
      );
    }
  }

  Future<void> _addSampleWardrobe() async {
    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nie si prihlásený.')),
      );
      return;
    }

    try {
      final ref =
      _firestore.collection('users').doc(user.uid).collection('wardrobe');

      final batch = _firestore.batch();

      final items = [
        {
          'name': 'Biele tričko',
          'category': 'top',
          'type': 'tshirt',
          'color': 'white',
          'style': 'casual',
          'season': 'all',
        },
        {
          'name': 'Čierne rifle',
          'category': 'bottom',
          'type': 'jeans',
          'color': 'black',
          'style': 'casual',
          'season': 'all',
        },
        {
          'name': 'Sivá mikina',
          'category': 'mid_layer',
          'type': 'hoodie',
          'color': 'grey',
          'style': 'casual',
          'season': 'autumn',
        },
        {
          'name': 'Biele tenisky',
          'category': 'shoes',
          'type': 'sneakers',
          'color': 'white',
          'style': 'casual',
          'season': 'all',
        },
      ];

      for (final item in items) {
        final docRef = ref.doc();
        batch.set(docRef, item);
      }

      await batch.commit();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vzorový šatník bol pridaný.')),
      );
    } catch (e) {
      debugPrint('Chyba pri pridávaní vzorového šatníka: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Nepodarilo sa pridať vzorový šatník.')),
      );
    }
  }
}
