// lib/screens/add_clothing_screen.dart

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

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
  bool _isAiLoading = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    super.dispose();
  }

  void _loadInitialData() {
    final data = widget.initialData;

    // názov
    final String? storedName = data['name'] as String?;
    if (storedName != null && storedName.isNotEmpty) {
      _nameController.text = storedName;
    }

    // značka
    final String? storedBrand = data['brand'] as String?;
    if (storedBrand != null && storedBrand.isNotEmpty) {
      _brandController.text = storedBrand;
    }

    // hlavná kategória
    final String? storedMainCategory = data['mainCategory'] as String?;
    if (storedMainCategory != null &&
        storedMainCategory.isNotEmpty &&
        categories.contains(storedMainCategory)) {
      _selectedMainCategory = storedMainCategory;
    }

    // podkategória
    final String? storedCategory = data['category'] as String?;
    if (storedCategory != null &&
        storedCategory.isNotEmpty &&
        _selectedMainCategory != null) {
      final subs =
          subcategoriesByCategory[_selectedMainCategory!.toLowerCase()] ?? [];
      if (subs.contains(storedCategory)) {
        _selectedSubcategory = storedCategory;
      }
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

    _isClean = (data['isClean'] as bool?) ?? true;

    // obrázok
    if (widget.imageUrl.isNotEmpty) {
      _uploadedImageUrl = widget.imageUrl;
    } else {
      final String? storedImage = data['imageUrl'] as String?;
      if (storedImage != null && storedImage.isNotEmpty) {
        _uploadedImageUrl = storedImage;
      }
    }
  }

  /// Pomocná funkcia – konverzia dynamic -> List<String>
  List<String> _toStringList(dynamic val) {
    if (val == null) return [];
    if (val is List) return val.map((e) => e.toString()).toList();
    if (val is String && val.isNotEmpty) return [val];
    return [];
  }

  /// Normalizácia názvov farieb z AI na naše appkové farby
  String _normalizeColorName(String raw) {
    if (raw.isEmpty) return "";

    final l = raw.toLowerCase().trim();

    // špeciálne odtiene → konkrétne slovenské farby
    if (l.contains("burgundy") ||
        l.contains("wine") ||
        l.contains("maroon") ||
        l.contains("dark red")) {
      return "bordová";
    }

    if (l.contains("navy") ||
        l.contains("midnight") ||
        l.contains("indigo") ||
        l.contains("dark blue")) {
      return "tmavomodrá";
    }

    if (l.contains("sky blue") ||
        l.contains("baby blue") ||
        l.contains("light blue")) {
      return "svetlomodrá";
    }

    if (l.contains("denim")) {
      return "modrá";
    }

    if (l.contains("olive") ||
        l.contains("army") ||
        l.contains("military")) {
      return "khaki";
    }

    if (l.contains("cream") ||
        l.contains("ivory") ||
        l.contains("off white") ||
        l.contains("off-white")) {
      return "béžová";
    }

    if (l.contains("tan") ||
        l.contains("camel") ||
        l.contains("sand") ||
        l.contains("nude")) {
      return "béžová";
    }

    if (l.contains("charcoal") || l.contains("anthracite")) {
      return "sivá";
    }

    if (l.contains("silver") ||
        l.contains("metallic") ||
        l.contains("metal")) {
      return "strieborná";
    }

    // základné anglické farby → slovenské
    if (l.contains("white")) return "biela";
    if (l.contains("black")) return "čierna";
    if (l.contains("grey") || l.contains("gray")) return "sivá";
    if (l.contains("beige")) return "béžová";
    if (l.contains("brown")) return "hnedá";
    if (l.contains("red")) return "červená";
    if (l.contains("blue")) return "modrá";
    if (l.contains("green")) return "zelená";
    if (l.contains("yellow")) return "žltá";
    if (l.contains("orange")) return "oranžová";
    if (l.contains("pink")) return "ružová";
    if (l.contains("purple") || l.contains("violet")) return "fialová";
    if (l.contains("gold")) return "zlatá";

    // ak nič z vyššieho nesedí, vrátime pôvodný text (možno už je v slovenčine)
    return raw;
  }

  
  /// Prenesenie údajov z AI do formulára (kategória, farby, štýl, sezóna, značka...)
  void _applyAiMetadata(Map<String, dynamic> ai) {
    final String? type = (ai['type'] as String?)?.trim();
    final String? brandFromAi = (ai['brand'] as String?)?.trim();

    // farby z AI → normalizované názvy
    final List<String> aiColorsRaw = _toStringList(ai['colors']);
    final List<String> aiColors = aiColorsRaw
        .map(_normalizeColorName)
        .where((c) => c.isNotEmpty)
        .toList();

    final List<String> aiStyles =
    _toStringList(ai['style'] ?? ai['styles']);
    final List<String> aiPatterns = _toStringList(ai['patterns']);
    final List<String> aiSeasons =
    _toStringList(ai['season'] ?? ai['seasons']);

    String? detectedMainCategory;
    String? detectedSubcategory;

    // pokus o nájdenie mainCategory + subcategory podľa type (napr. "tričko")
    if (type != null && type.isNotEmpty) {
      final lowerType = type.toLowerCase();
      subcategoriesByCategory.forEach((main, subs) {
        for (final s in subs) {
          final ls = s.toLowerCase();
          if (ls.contains(lowerType) || lowerType.contains(ls)) {
            detectedMainCategory = main; // napr. "vrch"
            detectedSubcategory = s;     // napr. "Tričko"
            break;
          }
        }
        if (detectedMainCategory != null) {
          return;
        }
      });
    }

    // farby – mapujeme na zoznam colors (z AppConstants)
    final List<String> matchedColors = [];
    for (final c in aiColors) {
      final lc = c.toLowerCase();
      for (final available in colors) {
        final la = available.toLowerCase();
        if (la == lc || la.contains(lc) || lc.contains(la)) {
          matchedColors.add(available);
        }
      }
    }

    // štýly – mapujeme na zoznam styles
    final List<String> matchedStyles = [];
    for (final s in aiStyles) {
      final ls = s.toLowerCase();
      for (final available in styles) {
        final la = available.toLowerCase();
        if (la == ls || la.contains(ls) || ls.contains(la)) {
          matchedStyles.add(available);
        }
      }
    }

    // vzory – mapujeme na patterns
    final List<String> matchedPatterns = [];
    for (final p in aiPatterns) {
      final lp = p.toLowerCase();
      for (final available in patterns) {
        final la = available.toLowerCase();
        if (la == lp || la.contains(lp) || lp.contains(la)) {
          matchedPatterns.add(available);
        } else if (lp.contains('logo') && la.contains('potlač')) {
          matchedPatterns.add(available);
        }
      }
    }

    // sezóny – mapujeme na seasons
    final List<String> matchedSeasons = [];
    for (final s in aiSeasons) {
      final ls = s.toLowerCase();
      for (final available in seasons) {
        final la = available.toLowerCase();
        if (la == ls || la.contains(ls) || ls.contains(la)) {
          matchedSeasons.add(available);
        }
      }
    }

    setState(() {
      // 🔹 1) Hlavná kategória – z 'vrch' spravíme 'Vrch', aby sedela s Dropdownom
      String? mainCat = detectedMainCategory;
      if (mainCat != null) {
        final lc = mainCat.toLowerCase();
        final fromList = categories.firstWhere(
              (c) => c.toLowerCase() == lc,
          orElse: () => mainCat!,
        );
        mainCat = fromList; // napr. z 'vrch' → 'Vrch'
      }

      if (mainCat != null && detectedSubcategory != null) {
        _selectedMainCategory ??= mainCat;
        _selectedSubcategory ??= detectedSubcategory;
      }

      // 🔹 2) Farby
      if (matchedColors.isNotEmpty && _selectedColors.isEmpty) {
        _selectedColors = matchedColors.toSet().toList();
      }

      // 🔹 3) Štýly
      if (matchedStyles.isNotEmpty && _selectedStyles.isEmpty) {
        _selectedStyles = matchedStyles.toSet().toList();
      }

      // 🔹 4) Vzory
      if (matchedPatterns.isNotEmpty && _selectedPatterns.isEmpty) {
        _selectedPatterns = matchedPatterns.toSet().toList();
      }

      // 🔹 5) Sezóny – prepíš aj vtedy, keď tam máme len default "Celoročne"
      if (matchedSeasons.isNotEmpty &&
          (_selectedSeasons.isEmpty ||
              (_selectedSeasons.length == 1 &&
                  _selectedSeasons.first.toLowerCase() == 'celoročne'))) {
        _selectedSeasons = matchedSeasons.toSet().toList();
      }

      // Názov doplníme len ak je úplne prázdny
      if (_nameController.text.trim().isEmpty &&
          type != null &&
          type.isNotEmpty) {
        final String niceType =
            type.substring(0, 1).toUpperCase() + type.substring(1);
        _nameController.text = niceType;
      }

      // Značka – doplníme len ak si ju ešte nezadal ručne
      if (brandFromAi != null &&
          brandFromAi.isNotEmpty &&
          _brandController.text.trim().isEmpty) {
        _brandController.text = brandFromAi;
      }
    });
  }


  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked =
      await _picker.pickImage(source: source, imageQuality: 80);
      if (picked == null) return;

      setState(() {
        _localImageFile = File(picked.path);
        // vymažeme starý URL, aby sme vedeli, že treba znova uploadnúť
        _uploadedImageUrl = null;
      });
    } catch (e) {
      debugPrint('Chyba pri výbere obrázka: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nepodarilo sa načítať obrázok.')),
      );
    }
  }

  /// Nahrá lokálny obrázok do Firebase Storage a vráti URL
  Future<String?> _uploadImageToFirebase() async {
    if (_localImageFile == null) return _uploadedImageUrl;

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

  /// Istota, že máme URL obrázka (buď existujúci, alebo novonahratý)
  Future<String?> _ensureImageUrl() async {
    if (_uploadedImageUrl != null && _uploadedImageUrl!.isNotEmpty) {
      return _uploadedImageUrl;
    }
    final url = await _uploadImageToFirebase();
    if (url != null && url.isNotEmpty) {
      setState(() {
        _uploadedImageUrl = url;
      });
    }
    return url;
  }

  Future<void> _save() async {
    final user = _auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Musíš byť prihlásený.')),
      );
      return;
    }

    if (_selectedMainCategory == null || _selectedSubcategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Prosím, vyber hlavnú kategóriu aj podkategóriu.')),
      );
      return;
    }

    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      String? imageUrl = _uploadedImageUrl;

      if (_localImageFile != null) {
        final uploaded = await _uploadImageToFirebase();
        if (uploaded != null) {
          imageUrl = uploaded;
        }
      }

      final docRef = widget.isEditing && widget.itemId != null
          ? _firestore
          .collection('users')
          .doc(user.uid)
          .collection('wardrobe')
          .doc(widget.itemId)
          : _firestore
          .collection('users')
          .doc(user.uid)
          .collection('wardrobe')
          .doc();

      final dataToSave = {
        'name': _nameController.text.trim(),
        'brand': _brandController.text.trim(),
        'mainCategory': _selectedMainCategory,
        'category': _selectedSubcategory,
        'color': _selectedColors,
        'style': _selectedStyles,
        'pattern': _selectedPatterns,
        'season': _selectedSeasons,
        'isClean': _isClean,
        'imageUrl': imageUrl ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (!widget.isEditing || widget.itemId == null) {
        dataToSave['uploadedAt'] = FieldValue.serverTimestamp();
      }

      await docRef.set(
        dataToSave,
        SetOptions(merge: true),
      );

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      debugPrint('Chyba pri ukladaní: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nepodarilo sa uložiť kúsok.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  /// Vyplniť pomocou AI – zavolá Cloud Function analyzeClothingImage
  Future<void> _fillWithAi() async {
    if (_isAiLoading) return;

    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Musíš byť prihlásený.')),
      );
      return;
    }

    if (_localImageFile == null && (_uploadedImageUrl == null || _uploadedImageUrl!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Najprv pridaj fotku kúsku.')),
      );
      return;
    }

    setState(() {
      _isAiLoading = true;
    });

    try {
      final imageUrl = await _ensureImageUrl();
      if (imageUrl == null || imageUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nepodarilo sa získať URL obrázka.')),
        );
        return;
      }

      const functionUrl =
          'https://us-east1-outfitoftheday-4d401.cloudfunctions.net/analyzeClothingImage';

      final response = await http.post(
        Uri.parse(functionUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'imageUrl': imageUrl}),
      );

      debugPrint(
          'analyzeClothingImage status: ${response.statusCode}, body: ${response.body}');

      if (response.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'AI analýza zlyhala (kód ${response.statusCode}). Skús neskôr.')),
        );
        return;
      }

      final Map<String, dynamic> body =
      jsonDecode(response.body) as Map<String, dynamic>;

      try {
        Map<String, dynamic> aiJson;

        if (body.containsKey('rawText')) {
          // AI vrátila JSON obalený v ```json ... ```
          String raw = (body['rawText'] as String? ?? '').trim();

          // odstrániť úvodné ``` alebo ```json
          if (raw.startsWith('```')) {
            final firstNewline = raw.indexOf('\n');
            if (firstNewline != -1) {
              raw = raw.substring(firstNewline + 1);
            }
          }

          // odstrániť koncové ```
          if (raw.endsWith('```')) {
            raw = raw.substring(0, raw.lastIndexOf('```')).trim();
          }

          aiJson = jsonDecode(raw) as Map<String, dynamic>;
        } else {
          // už je to čistý JSON
          aiJson = body;
        }

        _applyAiMetadata(aiJson);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AI doplnila údaje. Skontroluj a uprav podľa seba.'),
          ),
        );
      } catch (e) {
        debugPrint('Chyba pri parsovaní AI JSONu: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nepodarilo sa spracovať odpoveď AI.')),
        );
      }

    } catch (e) {
      debugPrint('Chyba pri volaní analyzeClothingImage: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nepodarilo sa zavolať AI analyzátor.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAiLoading = false;
        });
      }
    }
  }

  void _showStyleInfo() {
    showDialog(
      context: context,
      builder: (ctx) => const AlertDialog(
        title: Text('Štýly oblečenia'),
        content: SingleChildScrollView(
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
      ),
    );
  }

  void _showPatternInfo() {
    showDialog(
      context: context,
      builder: (ctx) => const AlertDialog(
        title: Text('Vzory'),
        content: SingleChildScrollView(
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
      ),
    );
  }

  void _showSeasonInfo() {
    showDialog(
      context: context,
      builder: (ctx) => const AlertDialog(
        title: Text('Sezóny nosenia'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('• Jar – prechodné kúsky, ľahšie bundy, dlhé tričká.'),
              SizedBox(height: 4),
              Text('• Leto – krátke rukávy, šortky, šaty, ľahké materiály.'),
              SizedBox(height: 4),
              Text('• Jeseň – vrstvenie, mikiny, prechodné bundy.'),
              SizedBox(height: 4),
              Text('• Zima – hrubé mikiny, zimné bundy, svetre.'),
              SizedBox(height: 4),
              Text('• Celoročne – kúsky, ktoré vieš nosiť celý rok.'),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentImageWidget = _localImageFile != null
        ? Image.file(
      _localImageFile!,
      fit: BoxFit.cover,
      height: 260,
    )
        : (_uploadedImageUrl != null && _uploadedImageUrl!.isNotEmpty)
        ? Image.network(
      _uploadedImageUrl!,
      fit: BoxFit.cover,
      height: 260,
    )
        : Container(
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.grey.shade200,
      ),
      child: const Center(
        child: Icon(Icons.image_outlined, size: 48),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Upraviť kúsok' : 'Pridať kúsok'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Obrázok
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: currentImageWidget,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Odfotiť'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Z galérie'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Text(
              'Názov kúsku',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Napr. Bordové tričko Primark',
              ),
            ),
            const SizedBox(height: 16),

            Text(
              'Hlavná kategória',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
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
            const SizedBox(height: 16),

            Text(
              'Podkategória',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              value: _selectedSubcategory,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
              items: (_selectedMainCategory == null
                  ? <String>[]
                  : (subcategoriesByCategory[
              _selectedMainCategory!.toLowerCase()] ??
                  []))
                  .map((value) {
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
            const SizedBox(height: 16),

            // Farby
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Farby:',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: colors.map((c) {
                final isSelected = _selectedColors.contains(c);
                return FilterChip(
                  label: Text(c),
                  selected: isSelected,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedColors.add(c);
                      } else {
                        _selectedColors.remove(c);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Štýly
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
              runSpacing: 4,
              children: styles.map((s) {
                final isSelected = _selectedStyles.contains(s);
                return FilterChip(
                  label: Text(s),
                  selected: isSelected,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedStyles.add(s);
                      } else {
                        _selectedStyles.remove(s);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Vzory
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
              runSpacing: 4,
              children: patterns.map((p) {
                final isSelected = _selectedPatterns.contains(p);
                return FilterChip(
                  label: Text(p),
                  selected: isSelected,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedPatterns.add(p);
                      } else {
                        _selectedPatterns.remove(p);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Sezóny
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Sezóny:',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline, size: 20),
                  tooltip: 'Vysvetlenie sezón',
                  onPressed: _showSeasonInfo,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: seasons.map((s) {
                final isSelected = _selectedSeasons.contains(s);
                return FilterChip(
                  label: Text(s),
                  selected: isSelected,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedSeasons.add(s);
                      } else {
                        _selectedSeasons.remove(s);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            Text(
              'Značka',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _brandController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Napr. Primark, Nike, Zara…',
              ),
            ),
            const SizedBox(height: 16),

            // Uložiť
            ElevatedButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Text('Uložiť'),
            ),
            const SizedBox(height: 8),

            // Vyplniť pomocou AI
            OutlinedButton.icon(
              onPressed: _isAiLoading ? null : _fillWithAi,
              icon: _isAiLoading
                  ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.auto_awesome),
              label: const Text('Vyplniť pomocou AI'),
            ),
            const SizedBox(height: 8),

            // Poradiť sa o tomto kúsku
            OutlinedButton.icon(
              onPressed: () {
                final user = _auth.currentUser;
                if (user == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Na poradenstvo potrebuješ byť prihlásený.')),
                  );
                  return;
                }

                final Map<String, dynamic> itemData = {
                  'name': _nameController.text.trim(),
                  'brand': _brandController.text.trim(),
                  'mainCategory': _selectedMainCategory,
                  'category': _selectedSubcategory,
                  'color': _selectedColors,
                  'style': _selectedStyles,
                  'pattern': _selectedPatterns,
                  'season': _selectedSeasons,
                  'imageUrl': _uploadedImageUrl ?? '',
                };

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => StylistChatScreen(
                      initialItemData: itemData,
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
