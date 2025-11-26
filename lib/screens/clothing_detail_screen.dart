// lib/screens/clothing_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:outfitofTheDay/constants/app_constants.dart';

class ClothingDetailScreen extends StatefulWidget {
  final String clothingItemId;
  final Map<String, dynamic> clothingItemData;

  const ClothingDetailScreen({
    Key? key,
    required this.clothingItemId,
    required this.clothingItemData,
  }) : super(key: key);

  @override
  State<ClothingDetailScreen> createState() => _ClothingDetailScreenState();
}

class _ClothingDetailScreenState extends State<ClothingDetailScreen> {
  final User? _user = FirebaseAuth.instance.currentUser;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 👉 textové pole na značku
  final TextEditingController _brandController = TextEditingController();

  String? _selectedMainCategory;
  String? _selectedSubcategory;

  List<String> _selectedColors = [];
  List<String> _selectedStyles = [];
  List<String> _selectedPatterns = [];
  List<String> _selectedSeasons = [];

  bool _isClean = true;
  int _wearCount = 0;

  String? _imageUrl;
  bool _isSaving = false;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _prefillFromItem();
  }

  void _prefillFromItem() {
    final data = widget.clothingItemData;

    _imageUrl = data['imageUrl'] as String?;
    _brandController.text = (data['brand'] ?? '') as String;

    // pôvodná kategória - v novej verzii je to podkategória (Tričko, Tepláky, ...)
    final String? storedCategory = data['category'] as String?;
    final String? storedMainCategory = data['mainCategory'] as String?;

    // najprv skúsime použiť mainCategory ak existuje
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

    // podkategória – ak je platná, použijeme ju
    if (_selectedMainCategory != null &&
        storedCategory != null &&
        subcategoriesByCategory[_selectedMainCategory!]!
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
    _wearCount = (data['wearCount'] as int?) ?? 0;
  }

  @override
  void dispose() {
    _brandController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (_user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Na úpravu musíš byť prihlásený.')),
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

    setState(() {
      _isSaving = true;
    });

    try {
      final docRef = _firestore
          .collection('users')
          .doc(_user!.uid)
          .collection('wardrobe')
          .doc(widget.clothingItemId);

      await docRef.update({
        'category': _selectedSubcategory,
        'mainCategory': _selectedMainCategory,
        'color': _selectedColors,
        'style': _selectedStyles,
        'pattern': _selectedPatterns,
        'season': _selectedSeasons,
        'brand': _brandController.text,
        'isClean': _isClean,
        'wearCount': _wearCount,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zmeny boli uložené.')),
      );

      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Chyba pri ukladaní zmien: $e');
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

  Future<void> _deleteItem() async {
    if (_user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Na vymazanie musíš byť prihlásený.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vymazať kúsok?'),
        content: const Text('Naozaj chceš vymazať tento kúsok zo šatníka?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Zrušiť'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Vymazať'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      final docRef = _firestore
          .collection('users')
          .doc(_user!.uid)
          .collection('wardrobe')
          .doc(widget.clothingItemId);

      await docRef.delete();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kúsok bol vymazaný.')),
      );

      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Chyba pri mazání kúsku: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba pri mazaní: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String title =
        (widget.clothingItemData['name'] as String?) ?? 'Detail oblečenia';

    final List<String> currentSubcategories = _selectedMainCategory != null
        ? (subcategoriesByCategory[_selectedMainCategory!] ?? [])
        : [];

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _isDeleting ? null : _deleteItem,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // obrázok
            if (_imageUrl != null && _imageUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  _imageUrl!,
                  height: 240,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 240,
                    color: Colors.grey.shade200,
                    child: const Center(
                      child: Icon(Icons.broken_image_outlined, size: 48),
                    ),
                  ),
                ),
              )
            else
              Container(
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.grey.shade200,
                ),
                child: const Center(
                  child: Icon(Icons.image_not_supported_outlined, size: 48),
                ),
              ),
            const SizedBox(height: 16),

            // kategória
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

            // značka – textové pole
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

            // stav čistoty + počet nosení
            SwitchListTile(
              title: const Text('Je čisté (pripravené na nosenie)'),
              value: _isClean,
              onChanged: (value) {
                setState(() {
                  _isClean = value;
                });
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Počet nosení: $_wearCount',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),

            // uložiť
            ElevatedButton(
              onPressed: _isSaving ? null : _saveChanges,
              child: _isSaving
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Text('Uložiť zmeny'),
            ),
          ],
        ),
      ),
    );
  }
}
