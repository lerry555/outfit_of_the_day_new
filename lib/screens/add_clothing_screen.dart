// lib/screens/add_clothing_screen.dart

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:outfitofTheDay/constants/app_constants.dart';

class AddClothingScreen extends StatefulWidget {
  final Map<String, dynamic> initialData;
  final String imageUrl;

  const AddClothingScreen({
    Key? key,
    this.initialData = const <String, dynamic>{},
    this.imageUrl = '',
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
  List<String> _selectedSeasons = [];

  bool _isClean = true;

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

    _nameController.text = (data['name'] ?? '') as String;
    _brandController.text = (data['brand'] ?? '') as String;

    final String? storedCategory = data['category'] as String?;
    final String? storedMainCategory = data['mainCategory'] as String?;

    // najprv mainCategory, ak existuje
    if (storedMainCategory != null &&
        subcategoriesByCategory.containsKey(storedMainCategory)) {
      _selectedMainCategory = storedMainCategory;
    }

    // ak nemáme mainCategory, skúsime nájsť podľa podkategórie
    if (_selectedMainCategory == null && storedCategory != null) {
      for (final entry in subcategoriesByCategory.entries) {
        if (entry.value.contains(storedCategory)) {
          _selectedMainCategory = entry.key;
          break;
        }
      }
    }

    // podkategória – ak je platná
    if (_selectedMainCategory != null &&
        storedCategory != null &&
        (subcategoriesByCategory[_selectedMainCategory!] ?? [])
            .contains(storedCategory)) {
      _selectedSubcategory = storedCategory;
    }

    // farby
    final dynamic colorData = data['color'];
    if (colorData is List) {
      _selectedColors = List<String>.from(colorData);
    } else if (colorData is String && colorData.isNotEmpty) {
      _selectedColors = [colorData];
    }

    // štýly
    final dynamic styleData = data['style'];
    if (styleData is List) {
      _selectedStyles = List<String>.from(styleData);
    } else if (styleData is String && styleData.isNotEmpty) {
      _selectedStyles = [styleData];
    }

    // vzory
    final dynamic patternData = data['pattern'];
    if (patternData is List) {
      _selectedPatterns = List<String>.from(patternData);
    } else if (patternData is String && patternData.isNotEmpty) {
      _selectedPatterns = [patternData];
    }

    // sezóny
    final dynamic seasonData = data['season'];
    if (seasonData is List) {
      _selectedSeasons = List<String>.from(seasonData);
    } else if (seasonData is String && seasonData.isNotEmpty) {
      _selectedSeasons = [seasonData];
    }

    _isClean = (data['isClean'] as bool?) ?? true;

    // obrázok – buď z parametra imageUrl, alebo z initialData
    if (widget.imageUrl.isNotEmpty) {
      _uploadedImageUrl = widget.imageUrl;
    } else {
      final String? storedImage = data['imageUrl'] as String?;
      if (storedImage != null && storedImage.isNotEmpty) {
        _uploadedImageUrl = storedImage;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked =
      await _picker.pickImage(source: source, imageQuality: 80);
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
      return _uploadedImageUrl; // možno už máme URL
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
        const SnackBar(content: Text('Prosím, vyber typ / podkategóriu.')),
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

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('wardrobe')
          .add({
        'name': _nameController.text.trim(),
        'mainCategory': _selectedMainCategory,
        'category': _selectedSubcategory,
        'color': _selectedColors,
        'style': _selectedStyles,
        'pattern': _selectedPatterns,
        'season': _selectedSeasons,
        'brand': _brandController.text.trim(),
        'isClean': _isClean,
        'wearCount': 0,
        'imageUrl': imageUrl ?? '',
        'uploadedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kúsok bol pridaný do šatníka.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Chyba pri ukladaní nového kúsku: $e');
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
        title: const Text('Pridať nový kúsok'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // obrázok + tlačidlá
            if (_localImageFile != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  _localImageFile!,
                  height: 220,
                  fit: BoxFit.cover,
                ),
              )
            else if (_uploadedImageUrl != null &&
                _uploadedImageUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  _uploadedImageUrl!,
                  height: 220,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 220,
                    color: Colors.grey.shade200,
                    child: const Center(
                      child:
                      Icon(Icons.broken_image_outlined, size: 48),
                    ),
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
                child: const Center(
                  child: Icon(
                    Icons.image_outlined,
                    size: 48,
                  ),
                ),
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

            // názov (voliteľné)
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
            Text(
              'Kategória:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedMainCategory,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
              items: categories.map((value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedMainCategory = value;
                  _selectedSubcategory = null;
                });
              },
            ),
            const SizedBox(height: 12),

            if (_selectedMainCategory != null) ...[
              Text(
                'Typ / podkategória:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _selectedSubcategory,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
                items: currentSubcategories.map((value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
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
            Text(
              'Farby:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: colors.map((color) {
                final bool selected = _selectedColors.contains(color);
                return FilterChip(
                  label: Text(color),
                  selected: selected,
                  onSelected: (value) {
                    setState(() {
                      if (value) {
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
            Text(
              'Štýl:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: styles.map((style) {
                final bool selected = _selectedStyles.contains(style);
                return FilterChip(
                  label: Text(style),
                  selected: selected,
                  onSelected: (value) {
                    setState(() {
                      if (value) {
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

            // vzory
            Text(
              'Vzory:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: patterns.map((pattern) {
                final bool selected = _selectedPatterns.contains(pattern);
                return FilterChip(
                  label: Text(pattern),
                  selected: selected,
                  onSelected: (value) {
                    setState(() {
                      if (value) {
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

            // sezóny
            Text(
              'Sezóny:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: seasons.map((season) {
                final bool selected = _selectedSeasons.contains(season);
                return FilterChip(
                  label: Text(season),
                  selected: selected,
                  onSelected: (value) {
                    setState(() {
                      if (value) {
                        _selectedSeasons.add(season);
                      } else {
                        _selectedSeasons.remove(season);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),

            // značka
            Text(
              'Značka:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _brandController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Napr. Nike, Zara, H&M…',
              ),
            ),
            const SizedBox(height: 12),

            // stav čistoty
            SwitchListTile(
              title: const Text('Je čisté (pripravené na nosenie)'),
              value: _isClean,
              onChanged: (value) {
                setState(() {
                  _isClean = value;
                });
              },
            ),
            const SizedBox(height: 16),

            // uložiť
            ElevatedButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Text('Uložiť do šatníka'),
            ),
          ],
        ),
      ),
    );
  }
}
