// lib/screens/clothing_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
  _ClothingDetailScreenState createState() => _ClothingDetailScreenState();
}

class _ClothingDetailScreenState extends State<ClothingDetailScreen> {
  String? _selectedCategory;
  List<String> _selectedColors = [];
  List<String> _selectedStyles = [];
  List<String> _selectedPatterns = [];
  String? _selectedBrand;
  List<String> _selectedSeasons = [];
  late bool _isClean;
  late int _wearCount;
  late bool _isSharable; // NOVÉ: Premenná pre zdieľanie

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final User? _user = FirebaseAuth.instance.currentUser;


  @override
  void initState() {
    super.initState();

    String currentCategory = widget.clothingItemData['category'] ?? 'Ostatné';
    dynamic currentColorsData = widget.clothingItemData['color'];
    dynamic currentStylesData = widget.clothingItemData['style'];
    dynamic currentPatternsData = widget.clothingItemData['pattern'];
    String? currentBrandData = widget.clothingItemData['brand'];
    dynamic currentSeasonsData = widget.clothingItemData['season'];


    _selectedCategory = categories.contains(currentCategory) ? currentCategory : null;
    if (_selectedCategory == null && currentCategory != 'Ostatné' && currentCategory.isNotEmpty) {
      _selectedCategory = 'Ostatné';
    }

    if (currentColorsData is String) {
      _selectedColors = [currentColorsData];
    } else if (currentColorsData is List) {
      _selectedColors = List<String>.from(currentColorsData);
    } else {
      _selectedColors = [];
    }
    _selectedColors = _selectedColors.where((color) => colors.contains(color)).toList();


    if (currentStylesData is String) {
      _selectedStyles = [currentStylesData];
    } else if (currentStylesData is List) {
      _selectedStyles = List<String>.from(currentStylesData);
    } else {
      _selectedStyles = [];
    }
    _selectedStyles = _selectedStyles.where((style) => styles.contains(style)).toList();

    if (currentPatternsData is String) {
      _selectedPatterns = [currentPatternsData];
    } else if (currentPatternsData is List) {
      _selectedPatterns = List<String>.from(currentPatternsData);
    } else {
      _selectedPatterns = [];
    }
    _selectedPatterns = _selectedPatterns.where((p) => patterns.contains(p)).toList();

    _selectedBrand = brands.contains(currentBrandData) ? currentBrandData : null;
    if (_selectedBrand == null && currentBrandData != 'Ostatné' && currentBrandData != null && currentBrandData.isNotEmpty) {
      _selectedBrand = 'Ostatné';
    }


    if (currentSeasonsData is String) {
      _selectedSeasons = [currentSeasonsData];
    } else if (currentSeasonsData is List) {
      _selectedSeasons = List<String>.from(currentSeasonsData);
    } else {
      _selectedSeasons = [];
    }
    _selectedSeasons = _selectedSeasons.where((s) => seasons.contains(s)).toList();


    _isClean = widget.clothingItemData['isClean'] ?? false;
    _wearCount = widget.clothingItemData['wearCount'] ?? 0;
    _isSharable = widget.clothingItemData['isSharable'] ?? false;
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _updateClothingInFirestore() async {
    if (_user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chyba: Používateľ nie je prihlásený.')),
      );
      return;
    }

    if (_selectedCategory == null || _selectedColors.isEmpty || _selectedStyles.isEmpty || _selectedPatterns.isEmpty || _selectedBrand == null || _selectedSeasons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prosím, vyplňte všetky povinné polia (kategória, farba, štýl, vzor, značka, sezóna).')),
      );
      return;
    }


    try {
      // Uloží zmeny do tvojho súkromného šatníka
      await _firestore
          .collection('users')
          .doc(_user!.uid)
          .collection('wardrobe')
          .doc(widget.clothingItemId)
          .update({
        'category': _selectedCategory,
        'color': _selectedColors,
        'style': _selectedStyles,
        'pattern': _selectedPatterns,
        'brand': _selectedBrand,
        'season': _selectedSeasons,
        'isClean': _isClean,
        'isSharable': _isSharable,
      });

      // NOVÉ: Logika pre verejný šatník
      final publicWardrobeRef = _firestore.collection('public_wardrobe').doc(widget.clothingItemId);

      if (_isSharable) {
        // Ak je zdieľanie zapnuté, skopíruje dáta do verejnej kolekcie
        await publicWardrobeRef.set({
          ...widget.clothingItemData, // Skopíruje pôvodné dáta
          'category': _selectedCategory,
          'color': _selectedColors,
          'style': _selectedStyles,
          'pattern': _selectedPatterns,
          'brand': _selectedBrand,
          'season': _selectedSeasons,
          'isSharable': true,
          'userId': _user!.uid, // Dôležité pre identifikáciu majiteľa
        });
        print('Položka bola pridaná do verejného šatníka.');
      } else {
        // Ak je zdieľanie vypnuté, vymaže položku z verejnej kolekcie
        await publicWardrobeRef.delete();
        print('Položka bola vymazaná z verejného šatníka.');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Oblečenie úspešne upravené!')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      print('Chyba pri úprave oblečenia: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba pri úprave oblečenia: ${e.toString()}')),
      );
    }
  }

  Future<void> _deleteClothingFromFirebase() async {
    if (_user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chyba: Používateľ nie je prihlásený.')),
      );
      return;
    }

    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Potvrdiť vymazanie'),
          content: const Text('Naozaj chcete vymazať túto položku zo šatníka?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Zrušiť'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            ElevatedButton(
              child: const Text('Vymazať', style: TextStyle(color: Colors.red)),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmDelete == true) {
      try {
        // Vymaže položku z tvojho súkromného šatníka
        await _firestore
            .collection('users')
            .doc(_user!.uid)
            .collection('wardrobe')
            .doc(widget.clothingItemId)
            .delete();

        // NOVÉ: Vymaže položku aj z verejného šatníka
        await _firestore.collection('public_wardrobe').doc(widget.clothingItemId).delete();


        print('Dokument z Firestore vymazaný.');

        final String imageUrl = widget.clothingItemData['imageUrl'] ?? '';
        if (imageUrl.isNotEmpty) {
          final Reference storageRef = _storage.refFromURL(imageUrl);
          await storageRef.delete();
          print('Obrázok z Storage vymazaný.');
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Položka úspešne vymazaná!')),
        );
        Navigator.of(context).pop();
      } catch (e) {
        print('Chyba pri vymazávaní položky: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Chyba pri vymazávaní položky: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _increaseWearCount() async {
    if (_user == null) return;
    try {
      setState(() {
        _wearCount++;
      });
      await _firestore
          .collection('users')
          .doc(_user!.uid)
          .collection('wardrobe')
          .doc(widget.clothingItemId)
          .update({'wearCount': _wearCount});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Počet nosení zvýšený!')),
      );
    } catch (e) {
      print('Chyba pri zvýšení počtu nosení: $e');
    }
  }


  @override
  Widget build(BuildContext context) {
    final String imageUrl = widget.clothingItemData['imageUrl'] ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.clothingItemData['category'] ?? 'Detail oblečenia'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_circle_outline),
            tooltip: 'Označiť ako použité',
            onPressed: _increaseWearCount,
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Upraviť',
            onPressed: _updateClothingInFirestore,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Vymazať',
            onPressed: _deleteClothingFromFirebase,
          ),
        ],
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

            Text('Kategória:', style: Theme.of(context).textTheme.headlineSmall),
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: categories.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedCategory = newValue;
                });
              },
              hint: _selectedCategory == null && widget.clothingItemData['category'] != null && widget.clothingItemData['category'].isNotEmpty
                  ? Text(widget.clothingItemData['category']!)
                  : null,
            ),
            const SizedBox(height: 10),

            Text('Farba(y):', style: Theme.of(context).textTheme.headlineSmall),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: colors.map((color) {
                final bool isSelected = _selectedColors.contains(color);
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

            Text('Štýl(y):', style: Theme.of(context).textTheme.headlineSmall),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: styles.map((style) {
                final bool isSelected = _selectedStyles.contains(style);
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

            Text('Vzor(y):', style: Theme.of(context).textTheme.headlineSmall),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: patterns.map((pattern) {
                final bool isSelected = _selectedPatterns.contains(pattern);
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

            Text('Značka:', style: Theme.of(context).textTheme.headlineSmall),
            DropdownButtonFormField<String>(
              value: _selectedBrand,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: brands.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedBrand = newValue;
                });
              },
              hint: _selectedBrand == null && widget.clothingItemData['brand'] != null && widget.clothingItemData['brand'].isNotEmpty
                  ? Text(widget.clothingItemData['brand']!)
                  : null,
            ),
            const SizedBox(height: 10),

            Text('Sezóna(y):', style: Theme.of(context).textTheme.headlineSmall),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: seasons.map((season) {
                final bool isSelected = _selectedSeasons.contains(season);
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


            Row(
              children: [
                Text('Stav čistoty:', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(width: 10),
                Switch(
                  value: _isClean,
                  onChanged: (bool value) {
                    setState(() {
                      _isClean = value;
                    });
                    _updateClothingInFirestore();
                  },
                ),
                Text(_isClean ? 'Čisté' : 'Špinavé'),
              ],
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Text('Zdieľateľné:', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(width: 10),
                Switch(
                  value: _isSharable,
                  onChanged: (bool value) {
                    setState(() {
                      _isSharable = value;
                    });
                    _updateClothingInFirestore();
                  },
                ),
                Text(_isSharable ? 'Áno' : 'Nie'),
              ],
            ),
            const SizedBox(height: 10),

            Text('Počet nosení: $_wearCount', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),

            Text('Nahrané: ${(widget.clothingItemData['uploadedAt'] as Timestamp?)?.toDate().toString().split(' ')[0] ?? 'N/A'}',
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}