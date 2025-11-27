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
  List<String> _selectedSeasons = ['Celoročne']; // default

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

    if (_selectedSeasons.isEmpty) {
      _selectedSeasons = ['Celoročne'];
    }

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

  /// Sezóna – vždy maximálne 1 možnosť, "Celoročne" je exkluzívne.
  void _toggleSeason(String season) {
    setState(() {
      if (season == 'Celoročne') {
        _selectedSeasons = ['Celoročne'];
      } else {
        _selectedSeasons = [season];
      }
    });
  }

  /// Štýl – priradíme vždy 1 hlavný štýl (dominantný).
  void _toggleStyle(String style) {
    setState(() {
      if (_selectedStyles.contains(style)) {
        _selectedStyles.clear();
      } else {
        _selectedStyles = [style];
      }
    });
  }

  /// Vzor – priradíme 1 dominantný vzor.
  void _togglePattern(String pattern) {
    setState(() {
      if (_selectedPatterns.contains(pattern)) {
        _selectedPatterns.clear();
      } else {
        _selectedPatterns = [pattern];
      }
    });
  }

  /// Testovacia funkcia – "Simulovať AI"
  /// Tu sa len napevno doplnia hodnoty, aby si videl, ako to bude fungovať.
  void _applyAiMock() {
    setState(() {
      _selectedMainCategory = 'Vrch';
      _selectedSubcategory = 'Bunda';
      _selectedColors = ['Čierna'];
      _selectedSeasons = ['Zima'];
      _selectedStyles = ['Casual'];
      _selectedPatterns = ['Jednofarebné'];
      _brandController.text = 'Nike';

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Simulácia AI doplnila informácie. Skontroluj, či sú správne.'),
        ),
      );
    });
  }

  /// Zatiaľ len placeholder – neskôr sem pôjde reálny chat so stylistom.
  void _openConsultationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Poradiť sa o tomto kúsku'),
        content: const Text(
          'Tu bude neskôr chat s AI stylistom, ktorý ti vysvetlí, '
          'prečo boli tieto informácie vyplnené takto a pomôže ti ich upraviť.',
        ),
        actions: [
          TextButton(
            child: const Text('Zavrieť'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  void _showStyleInfo() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vysvetlenie štýlov',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),

                const Text(
                  '👔 Elegantný\n'
                  'Kúsky vhodné na oslavy, do divadla, reštaurácie. '
                  'Košele, saká, elegantné kabáty, látkové nohavice, lodičky a pod.',
                ),
                const SizedBox(height: 8),

                const Text(
                  '👕 Casual\n'
                  'Bežné každodenné oblečenie. Basic tričká, rifle, '
                  'jednoduché mikiny, ľahké bundy a tenisky.',
                ),
                const SizedBox(height: 8),

                const Text(
                  '🏃 Športový\n'
                  'Oblečenie určené na tréning, beh alebo aktívny pohyb. '
                  'Funkčné tričká, teplákové súpravy, športové tenisky.',
                ),
                const SizedBox(height: 8),

                const Text(
                  '🧥 Streetwear\n'
                  'Mestský, moderný štýl. Oversized mikiny, hoodie s potlačou, '
                  'baggy nohavice, výrazné logá, šiltovky.',
                ),
                const SizedBox(height: 8),

                const Text(
                  '💼 Business / formálny\n'
                  'Pracovný a formálny štýl. Obleky, formálne nohavice, košele, '
                  'saka a elegantné topánky do kancelárie alebo na meetingy.',
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),

                Text(
                  'Stále si nie si istý, kam tvoj kúsok zaradiť?',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 4),
                Text(
                  'Použi tlačidlo „Poradiť sa o tomto kúsku“ a AI stylist ti '
                  'vysvetlí konkrétne na základe tvojej fotky, ktorý štýl je '
                  'najvhodnejší.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPatternInfo() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vysvetlenie vzorov',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),

                const Text(
                  'Jednofarebné\n'
                  'Celý kúsok má jednu hlavnú farbu bez vzorov.',
                ),
                const SizedBox(height: 8),

                const Text(
                  'Pruhy\n'
                  'Opakujúce sa línie – horizontálne, vertikálne alebo šikmé pruhy.',
                ),
                const SizedBox(height: 8),

                const Text(
                  'Kocky\n'
                  'Štvorcový alebo kockovaný vzor (napríklad flanelová košeľa).',
                ),
                const SizedBox(height: 8),

                const Text(
                  'Bodky\n'
                  'Vzor z malých alebo väčších bodiek rozložených po celom kúsku.',
                ),
                const SizedBox(height: 8),

                const Text(
                  'Kamufláž\n'
                  '„Maskáčový“ vzor – organické tvary vo viacerých odtieňoch.',
                ),
                const SizedBox(height: 8),

                const Text(
                  'Potlač / logo\n'
                  'Výrazná grafika, nápis alebo logo značky na tričku, mikine a pod.',
                ),
                const SizedBox(height: 8),

                const Text(
                  'Ornamenty\n'
                  'Ozdobné vzory, ornamenty, mandaly a komplikované dekory.',
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),

                Text(
                  'Stále si nie si istý, aký vzor zvoliť?',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 4),
                Text(
                  'Použi tlačidlo „Poradiť sa o tomto kúsku“ a AI stylist ti '
                  'pomôže vzor zaradiť podľa tvojej konkrétnej fotky.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        );
      },
    );
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

            // AI informačný box
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'AI rozpoznala tieto informácie',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _applyAiMock,
                          icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                          label: const Text('Simulovať AI'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Skontroluj, či sú údaje o kúsku vyplnené správne. '
                      'V prípade potreby ich môžeš upraviť.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),

                    // hlavná kategória
                    Text(
                      'Kategória',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
               