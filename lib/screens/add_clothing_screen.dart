// lib/screens/add_clothing_screen.dart

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/app_constants.dart';

class AddClothingScreen extends StatefulWidget {
  final Map<String, dynamic> initialData;
  final String imageUrl;
  final String? itemId;       // nové
  final bool isEditing;       // nové

  const AddClothingScreen({
    Key? key,
    this.initialData = const <String, dynamic>{},
    this.imageUrl = '',
    this.itemId,
    this.isEditing = false,
  }) : super(key: key);

  @override
  State<AddClothingScreen> createState() => _AddClothingScreenState();
}

class _AddClothingScreenState extends State<AddClothingScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _picker = ImagePicker();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _brandController = TextEditingController();

  String? _selectedMainCategory;
  String? _selectedSubcategory;

  List<String> _selectedColors = [];
  List<String> _selectedStyles = [];
  List<String> _selectedPatterns = [];

  // sezóna – iba jedna hodnota
  String _selectedSeason = 'Celoročne';

  File? _localImageFile;
  String? _uploadedImageUrl;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _prefillFromInitialData();
  }

  void _prefillFromInitialData() {
    final data = widget.initialData;

    if (widget.isEditing && data.isNotEmpty) {
      _nameController.text = (data['name'] ?? '') as String;
      _brandController.text = (data['brand'] ?? '') as String;

      // hlavná kategória
      final main = data['mainCategory'] as String?;
      if (main != null) {
        _selectedMainCategory = main;
      }

      // podkategória
      final sub = data['category'] as String?;
      if (sub != null) {
        _selectedSubcategory = sub;
      }

      // farby
      _selectedColors = _normalizeList(data['color']);

      // štýl
      _selectedStyles = _normalizeList(data['style']);

      // pattern
      _selectedPatterns = _normalizeList(data['pattern']);

      // sezóna — len jedna
      final s = _normalizeList(data['season']);
      if (s.isNotEmpty) _selectedSeason = s.first;

      // obrázok
      if (widget.imageUrl.isNotEmpty) {
        _uploadedImageUrl = widget.imageUrl;
      }
    }
  }

  List<String> _normalizeList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.map((e) => e.toString()).toList();
    if (value is String && value.isNotEmpty) return [value];
    return [];
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 80);
      if (picked == null) return;

      setState(() {
        _localImageFile = File(picked.path);
      });
    } catch (e) {
      debugPrint('Chyba pri výbere obrázka: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nepodarilo sa načítať obrázok.')),
      );
    }
  }

  Future<String?> _uploadImageIfNeeded() async {
    if (_localImageFile == null) {
      return _uploadedImageUrl;
    }

    final user = _auth.currentUser;
    if (user == null) return _uploadedImageUrl;

    try {
      final fileName =
          'wardrobe/${user.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = _storage.ref().child(fileName);
      await ref.putFile(_localImageFile!);
      final url = await ref.getDownloadURL();
      return url;
    } catch (e) {
      debugPrint('Chyba pri nahrávaní obrázka: $e');
      return _uploadedImageUrl;
    }
  }

  Future<void> _save() async {
    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Musíš byť prihlásený.')),
      );
      return;
    }

    if (_selectedMainCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prosím, vyber kategóriu.')),
      );
      return;
    }

    if (_selectedSubcategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prosím, vyber podkategóriu.')),
      );
      return;
    }

    if (_selectedColors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vyber aspoň jednu farbu.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final imageUrl = await _uploadImageIfNeeded();

      final dataToSave = {
        'name': _nameController.text.trim(),
        'mainCategory': _selectedMainCategory,
        'category': _selectedSubcategory,
        'color': _selectedColors,
        'style': _selectedStyles,
        'pattern': _selectedPatterns,
        'season': _selectedSeason,
        'brand': _brandController.text.trim(),
        'uploadedAt': FieldValue.serverTimestamp(),
      };

      // NOVÉ: ak editujeme → update
      if (widget.isEditing && widget.itemId != null) {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('wardrobe')
            .doc(widget.itemId!)
            .update(dataToSave);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Zmeny uložené')),
        );

      } else {
        // nový kúsok → add()
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('wardrobe')
            .add({
          ...dataToSave,
          'imageUrl': imageUrl ?? '',
          'wearCount': 0,
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kúsok bol pridaný')),
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();

    } catch (e) {
      debugPrint('Chyba pri ukladaní: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba pri ukladaní: $e')),
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
  Widget build(BuildContext context) {
    final List<String> currentSubcategories = _selectedMainCategory != null
        ? (subcategoriesByCategory[_selectedMainCategory!] ?? [])
        : [];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Upraviť kúsok' : 'Pridať nový kúsok'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // Obrázok
            if (_localImageFile != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(_localImageFile!, height: 220, fit: BoxFit.cover),
              )
            else if (_uploadedImageUrl != null && _uploadedImageUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  _uploadedImageUrl!,
                  height: 220,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 220,
                    color: Colors.grey.shade200,
                    child: const Center(child: Icon(Icons.broken_image, size: 48)),
                  ),
                ),
              )
            else
              Container(
                height: 180,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.grey.shade200,
                ),
                child:
                    const Center(child: Icon(Icons.image_outlined, size: 48)),
              ),

            const SizedBox(height: 8),

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

            const SizedBox(height: 16),

            // Názov
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Názov (nepovinné)',
                hintText: 'Napr. Sivé tepláky Nike',
              ),
            ),
            const SizedBox(height: 16),

            // hlavná kategória
            Text('Kategória:', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedMainCategory,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: categories.map((value) {
                return DropdownMenuItem(value: value, child: Text(value));
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedMainCategory = value;
                  _selectedSubcategory = null;
                });
              },
            ),

            const SizedBox(height: 12),

            // podkategória
            if (_selectedMainCategory != null) ...[
              Text('Typ / podkategória:',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _selectedSubcategory,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: currentSubcategories.map((value) {
                  return DropdownMenuItem(value: value, child: Text(value));
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedSubcategory = value;
                  });
                },
              ),
              const SizedBox(height: 12),
            ],

            // farby
            Text('Farby:', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: colors.map((color) {
                final selected = _selectedColors.contains(color);
                return FilterChip(
                  label: Text(color),
                  selected: selected,
                  onSelected: (v) {
                    setState(() {
                      if (v) {
                        _selectedColors.add(color);
                      } else {
                        _selectedColors.remove(color);
                      }
                    });
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 12),

            // štýl
            Text('Štýl:', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: styles.map((style) {
                final selected = _selectedStyles.contains(style);
                return FilterChip(
                  label: Text(style),
                  selected: selected,
                  onSelected: (v) {
                    setState(() {
                      if (v) {
                        _selectedStyles.add(style);
                      } else {
                        _selectedStyles.remove(style);
                      }
                    });
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 12),

            // vzor
            Text('Vzor:', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: patterns.map((pattern) {
                final selected = _selectedPatterns.contains(pattern);
                return FilterChip(
                  label: Text(pattern),
                  selected: selected,
                  onSelected: (v) {
                    setState(() {
                      if (v) {
                        _selectedPatterns.add(pattern);
                      } else {
                        _selectedPatterns.remove(pattern);
                      }
                    });
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 12),

            // sezóna (len jedna)
            Text('Sezóna:', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: ['Celoročne', 'Jar/Jeseň', 'Leto', 'Zima']
                  .map(
                    (season) => ChoiceChip(
                      label: Text(season),
                      selected: _selectedSeason == season,
                      onSelected: (_) {
                        setState(() {
                          _selectedSeason = season;
                        });
                      },
                    ),
                  )
                  .toList(),
            ),

            const SizedBox(height: 12),

            // značka
            Text('Značka:', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            TextField(
              controller: _brandController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Napr. Nike, Zara, H&M…',
              ),
            ),

            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(widget.isEditing ? 'Uložiť zmeny' : 'Uložiť do šatníka'),
            ),
          ],
        ),
      ),
    );
  }
}