// lib/screens/add_clothing_screen.dart

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:outfitofTheDay/screens/stylist_chat_screen.dart';

import 'package:outfitofTheDay/constants/app_constants.dart';

class AddClothingScreen extends StatefulWidget {
  final Map<String, dynamic> initialData;
  final String imageUrl;

  /// Ak je nastavené, ide o editáciu existujúceho kúsku
  final String? itemId;
  final bool isEditing;

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

    // mainCategory
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

    // ak nič nie je uložené, nastavíme default "Celoročne"
    if (_selectedSeasons.isEmpty) {
      _selectedSeasons = ['Celoročne'];
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

    if (_selectedSeasons.isEmpty) {
      _selectedSeasons = ['Celoročne'];
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final imageUrl = await _uploadImageIfNeeded();

      final payload = {
        'name': _nameController.text.trim(),
        'mainCategory': _selectedMainCategory,
        'category': _selectedSubcategory,
        'color': _selectedColors,
        'style': _selectedStyles,
        'pattern': _selectedPatterns,
        'season': _selectedSeasons,
        'brand': _brandController.text.trim(),
        'isClean': _isClean,
        'imageUrl': imageUrl ?? '',
      };

      if (widget.isEditing && widget.itemId != null) {
        // 🔁 EDITÁCIA EXISTUJÚCEHO KÚSKU
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('wardrobe')
            .doc(widget.itemId!)
            .update(payload);
      } else {
        // ➕ NOVÝ KÚSOK
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('wardrobe')
            .add({
          ...payload,
          'wearCount': 0,
          'uploadedAt': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isEditing
              ? 'Kúsok bol upravený.'
              : 'Kúsok bol pridaný do šatníka.'),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Chyba pri ukladaní kúsku: $e');
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

  /// Simulácia AI – len pre ukážku, ako bude AI predvyplňovať polia
  void _simulateAI() {
    setState(() {
      _selectedMainCategory ??= 'Vrch';
      _selectedSubcategory ??= 'Mikina';
      _selectedColors = ['Čierna'];
      _selectedStyles = ['Casual'];
      _selectedPatterns = ['Bez vzoru'];
      _selectedSeasons = ['Jar/Jeseň (prechodná)', 'Zima'];

      if (_nameController.text.trim().isEmpty) {
        _nameController.text = 'Čierna mikina (AI simulácia)';
      }
      if (_brandController.text.trim().isEmpty) {
        _brandController.text = 'Nike';
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('AI (simulácia) predvyplnila údaje.'),
      ),
    );
  }

  void _showStyleInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Štýly oblečenia'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('• Casual – bežné, pohodlné oblečenie na každý deň.'),
              SizedBox(height: 4),
              Text('• Elegantný – košele, saká, šaty, veci do práce / na oslavy.'),
              SizedBox(height: 4),
              Text('• Športový – legíny, tepláky, funkčné tričká, tenisky na šport.'),
              SizedBox(height: 4),
              Text('• Streetwear – voľné mikiny, oversized, trendy kúsky do mesta.'),
              SizedBox(height: 4),
              Text('• Business – obleky, kostýmy, formálnejšie kúsky do kancelárie.'),
              SizedBox(height: 4),
              SizedBox(height: 12),
              Text(
                'Ak si stále nie si istý, ktorý štýl zvoliť, použi tlačidlo '
                    '„Poradiť sa o tomto kúsku“ dole.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Rozumiem'),
          ),
        ],
      ),
    );
  }

  void _showPatternInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vzory'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('• Bez vzoru – jednofarebný kúsok, žiadne potlače ani vzory.'),
              SizedBox(height: 4),
              Text('• Pruhy – horizontálne alebo vertikálne prúžky.'),
              SizedBox(height: 4),
              Text('• Bodky – klasické „polka dot“ alebo menšie bodky.'),
              SizedBox(height: 4),
              Text('• Kocky / káro – kockované košele, kárované saká atď.'),
              SizedBox(height: 4),
              Text('• Potlač / logo – veľké nápisy, logá značiek, obrázky.'),
              SizedBox(height: 4),
              Text('• Iný vzor – niečo, čo sa nehodí do vyšších kategórií.'),
              SizedBox(height: 12),
              Text(
                'Ak si stále nie si istý, ktorý vzor zvoliť, použi tlačidlo '
                    '„Poradiť sa o tomto kúsku“ dole.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Rozumiem'),
          ),
        ],
      ),
    );
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
                      child: Icon(Icons.broken_image_outlined, size: 48),
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
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _simulateAI,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Simulovať AI'),
              ),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Štýl:',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline, size: 20),
                  tooltip: 'Vysvetlenie štýlov',
                  onPressed: _showStyleInfo,
                ),
              ],
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Vzory:',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline, size: 20),
                  tooltip: 'Vysvetlenie vzorov',
                  onPressed: _showPatternInfo,
                ),
              ],
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

            // sezóny – multi-select s logikou „Celoročne“
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
                      if (season == 'Celoročne') {
                        if (value) {
                          _selectedSeasons = ['Celoročne'];
                        } else {
                          _selectedSeasons.remove('Celoročne');
                        }
                      } else {
                        if (value) {
                          _selectedSeasons.remove('Celoročne');
                          _selectedSeasons.add(season);
                        } else {
                          _selectedSeasons.remove(season);
                        }
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
                  : Text(widget.isEditing
                  ? 'Uložiť zmeny'
                  : 'Uložiť do šatníka'),
            ),
            const SizedBox(height: 8),

            // poradiť sa o kúsku – otvorí AI chat s informáciami o tomto kúsku
            TextButton.icon(
              onPressed: () {
                // poskladáme krátky popis kúsku pre chat
                final buffer = StringBuffer();
                buffer.writeln(
                  'Rád by som sa poradil o jednom konkrétnom kúsku oblečenia.',
                );

                if (_nameController.text.trim().isNotEmpty) {
                  buffer.writeln('Názov: ${_nameController.text.trim()}.');
                }
                if (_brandController.text.trim().isNotEmpty) {
                  buffer.writeln('Značka: ${_brandController.text.trim()}.');
                }
                if (_selectedMainCategory != null) {
                  buffer.writeln('Hlavná kategória: $_selectedMainCategory.');
                }
                if (_selectedSubcategory != null) {
                  buffer.writeln('Typ / podkategória: $_selectedSubcategory.');
                }
                if (_selectedColors.isNotEmpty) {
                  buffer.writeln('Farba: ${_selectedColors.join(", ")}.');
                }
                if (_selectedStyles.isNotEmpty) {
                  buffer.writeln('Štýl: ${_selectedStyles.join(", ")}.');
                }
                if (_selectedPatterns.isNotEmpty) {
                  buffer.writeln('Vzor: ${_selectedPatterns.join(", ")}.');
                }
                if (_selectedSeasons.isNotEmpty) {
                  buffer.writeln('Sezóna: ${_selectedSeasons.join(", ")}.');
                }

                buffer.writeln(
                  'Na základe týchto informácií mi prosím poraď, '
                      'ako tento kúsok najlepšie kombinovať so zvyškom môjho šatníka '
                      'a v akých situáciách alebo počasiu sa najviac hodí.',
                );

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => StylistChatScreen(
                      initialPrompt: buffer.toString(),
                      autoSendInitialPrompt: true,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Poradiť sa o tomto kúsku'),
            ),

          ],
        ),
      ),
    );
  }
}
