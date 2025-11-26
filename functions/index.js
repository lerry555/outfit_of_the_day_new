// lib/screens/add_clothing_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:outfitofTheDay/constants/app_constants.dart';

class AddClothingScreen extends StatefulWidget {
  final Map<String, dynamic> initialData;
  final String imageUrl;

  const AddClothingScreen({
    Key? key,
    required this.initialData,
    required this.imageUrl,
  }) : super(key: key);

  @override
  State<AddClothingScreen> createState() => _AddClothingScreenState();
}

class _AddClothingScreenState extends State<AddClothingScreen> {
  final User? _user = FirebaseAuth.instance.currentUser;
  final _firestore = FirebaseFirestore.instance;

  final _brandController = TextEditingController();

  String? _selectedCategory;
  String? _selectedSubcategory; // 🔥 NOVÉ – podkategória (tepláky, rifle, tenisky…)
  List<String> _selectedColors = [];
  List<String> _selectedStyles = [];
  List<String> _selectedPatterns = [];
  List<String> _selectedSeasons = [];

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _prefillData();
  }

  void _prefillData() {
    final data = widget.initialData;
    _brandController.text = data['brand'] ?? '';

    _selectedCategory =
        categories.contains(data['category']) ? data['category'] : null;

    if (data['subcategory'] is String) {
      _selectedSubcategory = data['subcategory'];
    }

    if (data['color'] is List) {
      _selectedColors = List<String>.from(data['color']);
    }

    if (data['style'] is List) {
      _selectedStyles = List<String>.from(data['style']);
    }

    if (data['pattern'] is List) {
      _selectedPatterns = List<String>.from(data['pattern']);
    }

    if (data['season'] is List) {
      _selectedSeasons = List<String>.from(data['season']);
    }
  }

  Future<void> _saveClothingItem() async {
    if (_user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Pre uloženie musíte byť prihlásený.')),
      );
      return;
    }

    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prosím, vyberte kategóriu.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final docRef = _firestore
          .collection('users')
          .doc(_user!.uid)
          .collection('wardrobe')
          .doc();

      final clothingData = {
        'id': docRef.id,
        'category': _selectedCategory,
        'subcategory':
            _selectedSubcategory, // 🔥 NOVÉ – ukladáme podkategóriu
        'color': _selectedColors,
        'style': _selectedStyles,
        'pattern': _selectedPatterns,
        'brand': _brandController.text,
        'season': _selectedSeasons,
        'imageUrl': widget.imageUrl,
        'uploadedAt': FieldValue.serverTimestamp(),
        'isClean': true,
        'wearCount': 0,
        'isSharable': false,
        'userId': _user!.uid,
      };

      await docRef.set(clothingData);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Oblečenie bolo úspešne pridané do vášho šatníka!')),
      );

      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Chyba pri ukladaní oblečenia: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _brandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Pozor: tieto premenné (categories, colors, styles, patterns, seasons)
    // musia byť definované v app_constants.dart, ako to bolo doteraz.
    // Tu ich len používame.

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pridať oblečenie'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Image.network(
                widget.imageUrl,
                height: 250,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Icons.broken_image, size: 100);
                },
              ),
            ),
            const SizedBox(height: 20),

            // 🧷 Kategória
            Text('Kategória:',
                style: Theme.of(context).textTheme.headlineSmall),
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration:
                  const InputDecoration(border: OutlineInputBorder()),
              items: categories.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedCategory = newValue;
                  // keď zmeníme kategóriu, zresetuj podkategóriu
                  _selectedSubcategory = null;
                });
              },
            ),
            const SizedBox(height: 10),

            // 🧷 Podkategória – NOVÉ
            Builder(
              builder: (context) {
                // Mapa podkategórií podľa kategórie
                final Map<String, List<String>> subcategoriesByCategory =
                    {
                  'Vrch': [
                    'Tričko',
                    'Košeľa',
                    'Mikina',
                    'Sveter',
                    'Top',
                    'Blúzka',
                  ],
                  'Spodok': [
                    'Rifle',
                    'Džínsy',
                    'Nohavice',
                    'Tepláky',
                    'Joggers',
                    'Legíny',
                    'Šortky',
                    'Kraťasy',
                    'Sukňa',
                  ],
                  'Obuv': [
                    'Tenisky',
                    'Bežecké',
                    'Elegantné topánky',
                    'Lodičky',
                    'Mokasíny',
                    'Čižmy',
                    'Sandále',
                    'Šľapky',
                  ],
                  'Doplnky': [
                    'Čiapka',
                    'Šál',
                    'Rukavice',
                    'Opasok',
                    'Taška',
                  ],
                };

                final currentSubcategories =
                    subcategoriesByCategory[_selectedCategory] ?? [];

                if (currentSubcategories.isEmpty) {
                  return const SizedBox.shrink();
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Typ / podkategória:',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _selectedSubcategory,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      items:
                          currentSubcategories.map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedSubcategory = newValue;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                );
              },
            ),

            // 🧷 Farby
            Text('Farby:',
                style: Theme.of(context).textTheme.headlineSmall),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: colors.map((color) {
                final bool isSelected =
                    _selectedColors.contains(color);
                return FilterChip(
                  label: Text(color),
                  selected: isSelected,
                  onSelected: (bool selected) {
                    setState(() {
                      if (selected) {
                        _selectedColors.add(color);
                      } else {
                        _selectedColors.remove(color);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 10),

            // 🧷 Štýl
            Text('Štýl:',
                style: Theme.of(context).textTheme.headlineSmall),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: styles.map((style) {
                final bool isSelected =
                    _selectedStyles.contains(style);
                return FilterChip(
                  label: Text(style),
                  selected: isSelected,
                  onSelected: (bool selected) {
                    setState(() {
                      if (selected) {
                        _selectedStyles.add(style);
                      } else {
                        _selectedStyles.remove(style);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 10),

            // 🧷 Vzory
            Text('Vzory:',
                style: Theme.of(context).textTheme.headlineSmall),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: patterns.map((pattern) {
                final bool isSelected =
                    _selectedPatterns.contains(pattern);
                return FilterChip(
                  label: Text(pattern),
                  selected: isSelected,
                  onSelected: (bool selected) {
                    setState(() {
                      if (selected) {
                        _selectedPatterns.add(pattern);
                      } else {
                        _selectedPatterns.remove(pattern);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 10),

            // 🧷 Sezóny
            Text('Sezóny:',
                style: Theme.of(context).textTheme.headlineSmall),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: seasons.map((season) {
                final bool isSelected =
                    _selectedSeasons.contains(season);
                return FilterChip(
                  label: Text(season),
                  selected: isSelected,
                  onSelected: (bool selected) {
                    setState(() {
                      if (selected) {
                        _selectedSeasons.add(season);
                      } else {
                        _selectedSeasons.remove(season);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 10),

            // 🧷 Značka (brand)
            Text('Značka:',
                style: Theme.of(context).textTheme.headlineSmall),
            TextField(
              controller: _brandController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Napr. Nike, Zara, H&M...',
              ),
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: _isSaving ? null : _saveClothingItem,
              child: _isSaving
                  ? const CircularProgressIndicator(
                      color: Colors.white,
                    )
                  : const Text('Uložiť do šatníka'),
            ),
          ],
        ),
      ),
    );
  }
}
