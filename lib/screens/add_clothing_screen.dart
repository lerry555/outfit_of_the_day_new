import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../constants/app_constants.dart';
import '../utils/ai_clothing_parser.dart';
import '../widgets/category_picker.dart';
import 'stylist_chat_screen.dart';

class AddClothingScreen extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  final String? imageUrl;
  final String? itemId;
  final bool isEditing;

  const AddClothingScreen({
    super.key,
    this.initialData,
    this.imageUrl,
    this.itemId,
    this.isEditing = false,
  });

  /// ✅ Bottom sheet picker (galéria / kamera) -> potom otvorí AddClothingScreen
  static Future<void> openFromPicker(BuildContext context) async {
    final picker = ImagePicker();

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Z galérie'),
                  onTap: () => Navigator.pop(context, 'gallery'),
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('Odfotiť'),
                  onTap: () => Navigator.pop(context, 'camera'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (choice == null) return;

    final XFile? x = await picker.pickImage(
      source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 90,
    );

    if (x == null) return;

    // ignore: use_build_context_synchronously
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AddClothingEntryPoint(localFile: File(x.path)),
      ),
    );
  }

  @override
  State<AddClothingScreen> createState() => _AddClothingScreenState();
}

/// Pomocný wrapper, aby sme vedeli odovzdať File hneď do AddClothingScreen bez hackov.
class _AddClothingEntryPoint extends StatelessWidget {
  final File localFile;
  const _AddClothingEntryPoint({required this.localFile});

  @override
  Widget build(BuildContext context) {
    return AddClothingScreenHost(localFile: localFile);
  }
}

class AddClothingScreenHost extends StatefulWidget {
  final File localFile;
  const AddClothingScreenHost({super.key, required this.localFile});

  @override
  State<AddClothingScreenHost> createState() => _AddClothingScreenHostState();
}

class _AddClothingScreenHostState extends State<AddClothingScreenHost> {
  @override
  Widget build(BuildContext context) {
    return AddClothingScreen(
      initialData: {
        '_localFilePath': widget.localFile.path,
      },
      imageUrl: null,
      isEditing: false,
    );
  }
}

class _AddClothingScreenState extends State<AddClothingScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _brandController = TextEditingController();

  File? _localImageFile;
  String? _uploadedImageUrl;

  // ✅ kvôli background triggeru
  String? _uploadedStoragePath;

  // Form selections
  String? _selectedMainGroupKey;
  String? _selectedCategoryKey;
  String? _selectedSubCategoryKey;

  List<String> _selectedColors = [];
  List<String> _selectedStyles = [];
  List<String> _selectedPatterns = [];
  List<String> _selectedSeasons = [];

  // AI state
  bool _isAiLoading = false;
  bool _aiCompleted = false;
  bool _aiFailed = false;
  String? _aiError;

  // ✅ “checklist” progress (pôsobí plynule, bez preskakovania)
  final List<String> _progressSteps = const [
    'Analyzujem obrázok',
    'Rozpoznávam typ kúsku',
    'Zaraďujem do kategórie',
    'Kontrolujem farby, vzor, sezónu',
    'Pripravujem formulár',
  ];

  // čo je už fajknuté
  final List<bool> _progressDone = [false, false, false, false, false];

  // milestone: kedy AI reálne dosiahlo danú “fázu”
  final List<bool> _milestoneReached = [false, false, false, false, false];

  // minimálne časy (aby sa kroky neodfajkli naraz)
  // (je to úmyselne “feels good” tempo)
  final List<int> _minStepMs = const [
    650,  // 1) analyzujem obrázok
    900,  // 2) rozpoznávam typ
    700,  // 3) zaraďujem do kategórie
    700,  // 4) kontrolujem farby/vzor/sezónu
    500,  // 5) pripravujem formulár
  ];

  // ktorý krok je “aktívny” (spinner)
  int _activeStepIndex = 0;

  Timer? _progressTimer;
  int _lastStepFlipMs = 0;
  Stopwatch? _progressWatch;

  // ✅ AI výsledky (pripravíme si ich, ale UI ukážeme až po animácii checklistu)
  Map<String, dynamic>? _pendingAiResult;
  bool _aiResultReady = false;

  String? _lastTypeLabel;

  // ✅ Brand autocomplete data
  List<String> _brandOptions = [];
  bool _brandsLoaded = false;

  // Default seed brands
  static const List<String> _seedBrands = [
    'Adidas',
    'Nike',
    'Puma',
    'Reebok',
    'New Balance',
    'Asics',
    'Converse',
    'Vans',
    'Fila',
    'Under Armour',
    'The North Face',
    'Columbia',
    'Salomon',
    'HI-TEC',
    'Helly Hansen',
    'Jack Wolfskin',
    'Mammut',
    'Patagonia',
    'Quechua',
    'Decathlon',
    'Carhartt',
    'Levi\'s',
    'Wrangler',
    'Diesel',
    'Tommy Hilfiger',
    'Calvin Klein',
    'Hugo Boss',
    'Ralph Lauren',
    'Lacoste',
    'Guess',
    'Armani',
    'Zara',
    'H&M',
    'Bershka',
    'Pull&Bear',
    'Stradivarius',
    'Mango',
    'Reserved',
    'Sinsay',
    'C&A',
    'Uniqlo',
    'Massimo Dutti',
    'COS',
    'GAP',
    'Abercrombie & Fitch',
    'Superdry',
    'Timberland',
    'Dr. Martens',
    'Clarks',
    'Ecco',
    'Geox',
    'Crocs',
    'Birkenstock',
  ];

  @override
  void initState() {
    super.initState();

    // Ak prichádzame z openFromPicker, dostaneme path v initialData
    final path = (widget.initialData?['_localFilePath'] ?? '').toString();
    if (!widget.isEditing && path.isNotEmpty) {
      _localImageFile = File(path);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fillWithAi();
      });
    }

    if (widget.isEditing && widget.initialData != null) {
      final d = widget.initialData!;
      _nameController.text = (d['name'] ?? '').toString();
      _brandController.text = (d['brand'] ?? '').toString();

      _selectedMainGroupKey =
      (d['mainGroupKey'] ?? d['mainGroup'] ?? '').toString().isEmpty
          ? null
          : (d['mainGroupKey'] ?? d['mainGroup']).toString();

      final cat = (d['categoryKey'] ?? d['category'] ?? '').toString();
      final sub = (d['subCategoryKey'] ?? d['subCategory'] ?? '').toString();

      _selectedCategoryKey = cat.isEmpty ? null : cat;
      _selectedSubCategoryKey = sub.isEmpty ? null : sub;

      _selectedColors =
          (d['colors'] as List?)?.map((e) => e.toString()).toList() ?? [];
      _selectedStyles =
          (d['styles'] as List?)?.map((e) => e.toString()).toList() ?? [];
      _selectedPatterns =
          (d['patterns'] as List?)?.map((e) => e.toString()).toList() ?? [];
      _selectedSeasons =
          (d['seasons'] as List?)?.map((e) => e.toString()).toList() ?? [];

      _uploadedImageUrl = widget.imageUrl;
      _uploadedStoragePath = (d['storagePath'] ?? '').toString().isEmpty
          ? null
          : (d['storagePath'] ?? '').toString();

      _aiCompleted = true;
      _lastTypeLabel =
      _nameController.text.trim().isEmpty ? null : _nameController.text.trim();
    }

    _loadBrandSuggestions();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _nameController.dispose();
    _brandController.dispose();
    super.dispose();
  }

  List<String> _toStringList(dynamic v) {
    if (v == null) return [];
    if (v is List) return v.map((e) => e.toString()).toList();
    return [];
  }

  // ---------------------------------------------------------
  // BRAND SUGGESTIONS (Firestore)
  // ---------------------------------------------------------
  Future<void> _loadBrandSuggestions() async {
    final user = _auth.currentUser;
    final base = <String>{..._seedBrands, ...premiumBrands};

    if (user == null) {
      setState(() {
        _brandOptions = base.toList()..sort();
        _brandsLoaded = true;
      });
      return;
    }

    try {
      final docRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('meta')
          .doc('brand_suggestions');

      final snap = await docRef.get();
      final data = snap.data();
      final dynamic arr = data?['brands'];

      final fromDb = <String>[];
      if (arr is List) {
        for (final x in arr) {
          final s = x.toString().trim();
          if (s.isNotEmpty) fromDb.add(s);
        }
      }

      final all = <String>{...base, ...fromDb};
      final list = all.toList()..sort();

      if (!mounted) return;
      setState(() {
        _brandOptions = list;
        _brandsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _brandOptions = base.toList()..sort();
        _brandsLoaded = true;
      });
    }
  }

  Future<void> _saveBrandSuggestion(String brandRaw) async {
    final user = _auth.currentUser;
    final brand = brandRaw.trim();
    if (brand.isEmpty) return;

    // Lokálne doplň hneď (UI)
    if (!_brandOptions.map((e) => e.toLowerCase()).contains(brand.toLowerCase())) {
      setState(() {
        _brandOptions = [..._brandOptions, brand]..sort();
      });
    }

    if (user == null) return;

    try {
      final docRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('meta')
          .doc('brand_suggestions');

      await docRef.set({
        'brands': FieldValue.arrayUnion([brand]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // nič – appka funguje aj bez toho
    }
  }

  // ---------------------------------------------------------
  // UPLOAD IMAGE
  // ---------------------------------------------------------
  Future<String?> _ensureImageUrl() async {
    if (_uploadedImageUrl != null && _uploadedImageUrl!.isNotEmpty) {
      return _uploadedImageUrl;
    }

    final user = _auth.currentUser;
    if (user == null) return null;
    if (_localImageFile == null) return null;

    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final storagePath = 'wardrobe/${user.uid}/$fileName';
    final ref = _storage.ref().child(storagePath);

    final task = await ref.putFile(_localImageFile!);
    final url = await task.ref.getDownloadURL();

    setState(() {
      _uploadedImageUrl = url;
      _uploadedStoragePath = storagePath;
    });

    return url;
  }

  // ---------------------------------------------------------
  // ✅ PROGRESS ENGINE (plynulé odfajkávanie)
  // - milestony nastavuje AI časť
  // - odfajkávanie riadi timer, krok po kroku, s min časom
  // - formulár sa ukáže až keď: AI výsledok je ready + posledná fajka hotová
  // ---------------------------------------------------------
  void _resetProgressEngine() {
    for (var i = 0; i < _progressDone.length; i++) {
      _progressDone[i] = false;
      _milestoneReached[i] = false;
    }
    _activeStepIndex = 0;
    _aiResultReady = false;
    _pendingAiResult = null;

    _progressTimer?.cancel();
    _progressWatch?.stop();

    _progressWatch = Stopwatch()..start();
    _lastStepFlipMs = 0;

    _progressTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!mounted) return;
      final sw = _progressWatch;
      if (sw == null) return;

      final nowMs = sw.elapsedMilliseconds;

      // nájdi prvý nehotový krok
      final next = _progressDone.indexWhere((x) => x == false);

      // všetko hotové
      if (next == -1) {
        // ak už máme AI výsledok -> zobraz form (hneď)
        if (_aiResultReady) {
          _progressTimer?.cancel();
          _progressTimer = null;
          setState(() {
            _isAiLoading = false;
            _aiCompleted = true;
            _aiFailed = false;
          });
        }
        return;
      }

      // aktívny krok je prvý nehotový
      if (_activeStepIndex != next) {
        _activeStepIndex = next;
      }

      // “next” krok sa môže odfajknúť iba ak:
      // 1) milestoneReached[next] = true
      // 2) uplynul min čas od posledného odfajknutia
      final canFlipByTime = (nowMs - _lastStepFlipMs) >= _minStepMs[next];
      if (_milestoneReached[next] && canFlipByTime) {
        _progressDone[next] = true;
        _lastStepFlipMs = nowMs;
      }

      setState(() {});
    });
  }

  void _reachMilestone(int i) {
    if (i < 0 || i >= _milestoneReached.length) return;
    _milestoneReached[i] = true;
  }

  // ---------------------------------------------------------
  // AI
  // ---------------------------------------------------------
  Future<void> _fillWithAi() async {
    if (_isAiLoading) return;

    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Musíš byť prihlásený.')),
      );
      return;
    }

    if (_localImageFile == null &&
        (_uploadedImageUrl == null || _uploadedImageUrl!.isEmpty)) {
      return;
    }

    setState(() {
      _isAiLoading = true;
      _aiCompleted = false;
      _aiFailed = false;
      _aiError = null;
    });

    _resetProgressEngine();

    try {
      // 1) upload + url
      final imageUrl = await _ensureImageUrl();
      if (imageUrl == null || imageUrl.isEmpty) {
        throw Exception('Nepodarilo sa získať URL obrázka.');
      }
      _reachMilestone(0); // ✅ “Analyzujem obrázok” môže časom odfajknúť

      const endpoint =
          'https://us-east1-outfitoftheday-4d401.cloudfunctions.net/analyzeClothingImage';

      final resp = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'imageUrl': imageUrl}),
      );

      if (resp.statusCode != 200) {
        throw Exception('AI zlyhalo: ${resp.statusCode} ${resp.body}');
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('AI odpoveď nie je JSON objekt.');
      }

      _reachMilestone(1); // ✅ rozpoznávanie typu máme (AI odpoveď prišla)

      _pendingAiResult = decoded;

      // teraz pripravíme dáta do formu (ale UI ukážeme až po checklist animácii)
      await _applyAiResult(decoded);

      // po vyplnení kategórie:
      _reachMilestone(2);

      // po vyplnení farieb/štýlov/vzorov/sezóny:
      _reachMilestone(3);

      // “pripravujem formulár” – pustíme až keď máme všetko pripravené
      _reachMilestone(4);
      _aiResultReady = true;

      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      _progressTimer?.cancel();
      _progressTimer = null;

      setState(() {
        _aiFailed = true;
        _aiCompleted = false;
        _isAiLoading = false;
        _aiError = e.toString();
      });
    }
  }

  Future<void> _applyAiResult(Map<String, dynamic> m) async {
    final String prettyType =
    (m['type_pretty'] ?? m['type'] ?? '').toString().trim();
    final String rawType = (m['type'] ?? '').toString().trim();
    final String canonical = (m['canonical_type'] ?? '').toString().trim();
    final String brandFromAi = (m['brand'] ?? '').toString().trim();

    final colorsFromAi = _toStringList(m['colors'] ?? m['color']);
    final stylesFromAi = _toStringList(m['style'] ?? m['styles']);
    final patternsFromAi = _toStringList(m['patterns'] ?? m['pattern']);
    final seasonsFromAi = _toStringList(m['season'] ?? m['seasons']);

    // názov
    if (_nameController.text.trim().isEmpty && prettyType.isNotEmpty) {
      _nameController.text = prettyType;
      _lastTypeLabel = prettyType;
    }

    // značka
    if (_brandController.text.trim().isEmpty && brandFromAi.isNotEmpty) {
      _brandController.text = brandFromAi;
      await _saveBrandSuggestion(brandFromAi);
    }

    // kategória podľa canonical / fallback parser
    if (canonical.isNotEmpty) {
      final mapped = AiClothingParser.fromCanonicalType(canonical);
      if (mapped != null) {
        _selectedMainGroupKey = mapped.mainGroupKey;
        _selectedCategoryKey = mapped.categoryKey;
        _selectedSubCategoryKey = mapped.subCategoryKey;
      }
    }

    if (_selectedMainGroupKey == null || _selectedCategoryKey == null) {
      final mapped = AiClothingParser.mapType(
        AiParserInput(
          rawType: rawType,
          aiName: prettyType,
          userName: _nameController.text.trim(),
          seasons: seasonsFromAi,
          brand: brandFromAi,
        ),
      );
      if (mapped != null) {
        _selectedMainGroupKey = mapped.mainGroupKey;
        _selectedCategoryKey = mapped.categoryKey;
        _selectedSubCategoryKey = mapped.subCategoryKey;
      }
    }

    // farby/štýly/vzory/sezóny
    if (colorsFromAi.isNotEmpty) {
      _selectedColors = colorsFromAi.where((c) => allowedColors.contains(c)).toList();
    }
    if (stylesFromAi.isNotEmpty) {
      _selectedStyles = stylesFromAi.where((s) => allowedStyles.contains(s)).toList();
    }
    if (patternsFromAi.isNotEmpty) {
      _selectedPatterns =
          patternsFromAi.where((p) => allowedPatterns.contains(p)).toList();
    }
    if (seasonsFromAi.isNotEmpty) {
      _selectedSeasons =
          seasonsFromAi.where((s) => allowedSeasons.contains(s)).toList();
    }
  }

  // ---------------------------------------------------------
  // SAVE
  // ---------------------------------------------------------
  Future<void> _save() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final imageUrl = await _ensureImageUrl();
      if (imageUrl == null || imageUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chýba obrázok.')),
        );
        return;
      }

      if (_selectedMainGroupKey == null ||
          _selectedCategoryKey == null ||
          _selectedSubCategoryKey == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vyber hlavnú skupinu, kategóriu a typ.')),
        );
        return;
      }

      final brand = _brandController.text.trim();
      await _saveBrandSuggestion(brand);

      final data = <String, dynamic>{
        'name': _nameController.text.trim(),
        'brand': brand,
        'mainGroup': _selectedMainGroupKey,
        'category': _selectedCategoryKey,
        'subCategory': _selectedSubCategoryKey,
        'mainGroupKey': _selectedMainGroupKey,
        'categoryKey': _selectedCategoryKey,
        'subCategoryKey': _selectedSubCategoryKey,
        'colors': _selectedColors,
        'styles': _selectedStyles,
        'patterns': _selectedPatterns,
        'seasons': _selectedSeasons.isEmpty ? ['celoročne'] : _selectedSeasons,
        'imageUrl': imageUrl,
        if (_uploadedStoragePath != null) 'storagePath': _uploadedStoragePath,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!widget.isEditing) 'createdAt': FieldValue.serverTimestamp(),
      };

      final ref = _firestore.collection('users').doc(user.uid).collection('wardrobe');

      if (widget.isEditing && widget.itemId != null) {
        await ref.doc(widget.itemId).set(data, SetOptions(merge: true));
      } else {
        await ref.add(data);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Uloženie zlyhalo: $e')),
      );
    }
  }

  // ---------------------------------------------------------
  // UI helpers
  // ---------------------------------------------------------
  Widget _buildProgressChecklist() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        const Text(
          'AI spracovanie',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ...List.generate(_progressSteps.length, (i) {
          final done = _progressDone[i];
          final isActive = !done && i == _activeStepIndex;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                if (done)
                  const Icon(Icons.check_circle, color: Colors.green, size: 20)
                else if (isActive)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(Icons.radio_button_unchecked, color: Colors.grey, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _progressSteps[i],
                    style: TextStyle(
                      fontSize: 14,
                      color: done ? Colors.black87 : Colors.black54,
                      fontWeight: done ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildAiError() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'AI sa nepodarilo: ${_aiError ?? ''}',
          style: const TextStyle(color: Colors.red),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _fillWithAi,
              icon: const Icon(Icons.refresh),
              label: const Text('Skúsiť znova'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _brandAutoComplete() {
    final options = _brandOptions;

    return Autocomplete<String>(
      initialValue: TextEditingValue(text: _brandController.text),
      optionsBuilder: (TextEditingValue textEditingValue) {
        final q = textEditingValue.text.trim().toLowerCase();
        if (q.isEmpty) {
          return options.take(25);
        }
        return options.where((b) => b.toLowerCase().contains(q)).take(50);
      },
      onSelected: (String selection) {
        _brandController.text = selection;
        _saveBrandSuggestion(selection);
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        controller.text = _brandController.text;
        controller.selection = TextSelection.fromPosition(
          TextPosition(offset: controller.text.length),
        );

        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: 'Značka',
            border: const OutlineInputBorder(),
            suffixIcon: _brandsLoaded
                ? const Icon(Icons.arrow_drop_down)
                : const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          onChanged: (v) {
            _brandController.text = v;
          },
          onEditingComplete: () {
            final txt = controller.text.trim();
            _brandController.text = txt;
            _saveBrandSuggestion(txt);
            onFieldSubmitted();
          },
        );
      },
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),

        if (_localImageFile != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(
              _localImageFile!,
              height: 220,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          )
        else if (_uploadedImageUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              _uploadedImageUrl!,
              height: 220,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),

        const SizedBox(height: 16),

        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Názov',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),

        _brandAutoComplete(),
        const SizedBox(height: 12),

        CategoryPicker(
          initialMainGroup: _selectedMainGroupKey,
          initialCategory: _selectedCategoryKey,
          initialSubCategory: _selectedSubCategoryKey,
          onChanged: (data) {
            final main = data['mainGroup'];
            final cat = data['category'];
            final sub = data['subCategory'];

            final subLabel =
            (sub != null && sub.isNotEmpty) ? (subCategoryLabels[sub] ?? sub) : '';

            setState(() {
              _selectedMainGroupKey = main;
              _selectedCategoryKey = cat;
              _selectedSubCategoryKey = sub;

              final currentName = _nameController.text.trim();
              if (currentName.isEmpty || currentName == (_lastTypeLabel ?? '')) {
                if (subLabel.isNotEmpty) {
                  _nameController.text = subLabel;
                  _lastTypeLabel = subLabel;
                }
              }
            });
          },
        ),

        const SizedBox(height: 12),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: allowedColors.map((c) {
            final selected = _selectedColors.contains(c);
            return FilterChip(
              label: Text(c),
              selected: selected,
              onSelected: (v) {
                setState(() {
                  final next = List<String>.from(_selectedColors);
                  if (v) {
                    if (!next.contains(c)) next.add(c);
                  } else {
                    next.remove(c);
                  }
                  _selectedColors = next;
                });
              },
            );
          }).toList(),
        ),

        const SizedBox(height: 12),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: allowedStyles.map((s) {
            final selected = _selectedStyles.contains(s);
            return FilterChip(
              label: Text(s),
              selected: selected,
              onSelected: (v) {
                setState(() {
                  final next = List<String>.from(_selectedStyles);
                  if (v) {
                    if (!next.contains(s)) next.add(s);
                  } else {
                    next.remove(s);
                  }
                  _selectedStyles = next;
                });
              },
            );
          }).toList(),
        ),

        const SizedBox(height: 12),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: allowedPatterns.map((p) {
            final selected = _selectedPatterns.contains(p);
            return FilterChip(
              label: Text(p),
              selected: selected,
              onSelected: (v) {
                setState(() {
                  final next = List<String>.from(_selectedPatterns);
                  if (v) {
                    if (!next.contains(p)) next.add(p);
                  } else {
                    next.remove(p);
                  }
                  _selectedPatterns = next;
                });
              },
            );
          }).toList(),
        ),

        const SizedBox(height: 12),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: allowedSeasons.map((s) {
            final selected = _selectedSeasons.contains(s);
            return FilterChip(
              label: Text(s),
              selected: selected,
              onSelected: (v) {
                setState(() {
                  final next = List<String>.from(_selectedSeasons);
                  if (v) {
                    if (!next.contains(s)) next.add(s);
                  } else {
                    next.remove(s);
                  }
                  _selectedSeasons = next;
                });
              },
            );
          }).toList(),
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _save,
                child: const Text('Uložiť'),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        if (_uploadedImageUrl != null && _uploadedImageUrl!.isNotEmpty)
          TextButton.icon(
            onPressed: () {
              final payload = <String, dynamic>{
                'name': _nameController.text.trim(),
                'brand': _brandController.text.trim(),
                'mainGroupKey': _selectedMainGroupKey,
                'categoryKey': _selectedCategoryKey,
                'subCategoryKey': _selectedSubCategoryKey,
                'color': _selectedColors,
                'style': _selectedStyles,
                'pattern': _selectedPatterns,
                'season': _selectedSeasons,
                'imageUrl': _uploadedImageUrl,
              };

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StylistChatScreen(
                    initialClothingData: payload,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Poradiť sa o tomto kúsku'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final showPick = !_isAiLoading &&
        _localImageFile == null &&
        (_uploadedImageUrl == null || _uploadedImageUrl!.isEmpty) &&
        !widget.isEditing;

    final showLoader = _isAiLoading;
    final showForm = _aiCompleted || widget.isEditing || _aiFailed;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Upraviť oblečenie' : 'Pridať oblečenie'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showPick)
                Column(
                  children: [
                    const SizedBox(height: 16),
                    Container(
                      height: 260,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.photo, size: 64, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => AddClothingScreen.openFromPicker(context),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Vybrať fotku'),
                    ),
                  ],
                ),

              if (showLoader) ...[
                if (_localImageFile != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(
                      _localImageFile!,
                      height: 260,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  )
                else if (_uploadedImageUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      _uploadedImageUrl!,
                      height: 260,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                _buildProgressChecklist(),
              ],

              if (_aiFailed) _buildAiError(),
              if (showForm) _buildForm(),
            ],
          ),
        ),
      ),
    );
  }
}
