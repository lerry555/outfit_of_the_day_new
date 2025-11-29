// lib/screens/home_screen.dart

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'add_clothing_screen.dart';
import 'wardrobe_screen.dart';
import 'select_outfit_screen.dart';
import 'calendar_screen.dart';

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

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile =
    await picker.pickImage(source: source, imageQuality: 85);

    if (pickedFile != null) {
      setState(() {
        _selectedOutfitImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _navigateToAddClothing() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddClothingScreen(),
      ),
    );
  }

  Future<void> _navigateToWardrobe() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const WardrobeScreen(),
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

            // KARTA: Vybrať outfit
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SelectOutfitScreen(),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.wb_sunny_outlined, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Vybrať outfit',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Vyber si outfit na dnes, zajtra alebo na špeciálnu udalosť. AI všetko prispôsobí počasiu.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // KARTA: Kalendár udalostí
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 2,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CalendarScreen(),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.event_note_outlined, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Kalendár udalostí',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Naplánuj si udalosti (práca, party, rande...) a AI ti potom navrhne outfit presne na ne.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
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
                                style:
                                Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Odfoti sa a neskôr ti AI povie, ako ti to pristane. (beta)',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall,
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
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.photo_camera_outlined),
                            onPressed: () => _pickImage(ImageSource.camera),
                            label: const Text('Odfotiť'),
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

            // KARTA: Šatník
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 2,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _navigateToWardrobe,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.checkroom_outlined, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tvoj šatník',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Pozri si všetky kúsky, ktoré máš pridané. Môžeš ich upraviť alebo vymazať.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // KARTA: Pridať nové oblečenie
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 2,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _navigateToAddClothing,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.add_photo_alternate_outlined, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pridať oblečenie',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Odfotíš alebo vyberieš z galérie, AI doplní kategóriu a sezónu.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // KARTA: Vzorový šatník (testovacie tlačidlo)
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nemáš ešte šatník?',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Môžeme ti pridať pár ukážkových kúskov na testovanie AI.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ElevatedButton.icon(
                        onPressed: _isAddingSampleWardrobe
                            ? null
                            : _addSampleWardrobe,
                        icon: _isAddingSampleWardrobe
                            ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                            : const Icon(Icons.auto_awesome),
                        label: const Text('Pridať vzorový šatník'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
      final itemsRef = _firestore
          .collection('wardrobe')
          .doc(user.uid)
          .collection('items');

      final batch = _firestore.batch();

      final sampleItems = [
        {
          'name': 'Čierne tričko',
          'category': 'top',
          'subCategory': 'tshirt',
          'color': 'čierna',
          'season': 'all_seasons',
          'style': 'casual',
          'imageUrl': null,
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': 'Modré rifle',
          'category': 'bottom',
          'subCategory': 'jeans',
          'color': 'modrá',
          'season': 'all_seasons',
          'style': 'casual',
          'imageUrl': null,
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': 'Biela košeľa',
          'category': 'top',
          'subCategory': 'shirt',
          'color': 'biela',
          'season': 'all_seasons',
          'style': 'formal',
          'imageUrl': null,
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': 'Čierne elegantné nohavice',
          'category': 'bottom',
          'subCategory': 'trousers',
          'color': 'čierna',
          'season': 'all_seasons',
          'style': 'formal',
          'imageUrl': null,
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': 'Biele tenisky',
          'category': 'shoes',
          'subCategory': 'sneakers',
          'color': 'biela',
          'season': 'spring_autumn',
          'style': 'casual',
          'imageUrl': null,
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': 'Čierne poltopánky',
          'category': 'shoes',
          'subCategory': 'elegant',
          'color': 'čierna',
          'season': 'all_seasons',
          'style': 'formal',
          'imageUrl': null,
          'createdAt': FieldValue.serverTimestamp(),
        },
        {
          'name': 'Tmavomodrá bunda',
          'category': 'outerwear',
          'subCategory': 'jacket',
          'color': 'tmavomodrá',
          'season': 'winter',
          'style': 'casual',
          'imageUrl': null,
          'createdAt': FieldValue.serverTimestamp(),
        },
      ];

      for (final item in sampleItems) {
        final docRef = itemsRef.doc();
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
}
