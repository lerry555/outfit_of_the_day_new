import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;

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

  /// ✅ Bottom sheet picker (galéria / kamera) -> potom otvorí Preflight (otáčanie)
  static Future<void> openFromPicker(BuildContext context) async {
    final picker = ImagePicker();

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.black.withOpacity(0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Tipy pre najlepšiu fotku',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 8),
                      _TipRow(
                        icon: Icons.stay_current_portrait,
                        text: 'Foť oblečenie ideálne na výšku.',
                      ),
                      _TipRow(
                        icon: Icons.crop_free,
                        text: 'Nech je celý kúsok v zábere.',
                      ),
                      _TipRow(
                        icon: Icons.wallpaper,
                        text: 'Jednofarebné pozadie = lepší výsledok.',
                      ),
                      _TipRow(
                        icon: Icons.wb_sunny_outlined,
                        text: 'Radšej denné svetlo, minimum tieňov.',
                      ),
                      SizedBox(height: 6),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Z galérie'),
                  onTap: () => Navigator.pop(sheetCtx, 'gallery'),
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('Odfotiť'),
                  onTap: () => Navigator.pop(sheetCtx, 'camera'),
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
        builder: (_) => _PhotoPreflightScreen(localFile: File(x.path)),
      ),
    );
  }

  @override
  State<AddClothingScreen> createState() => _AddClothingScreenState();
}

class _TipRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _TipRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.black54),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoPreflightScreen extends StatefulWidget {
  final File localFile;
  const _PhotoPreflightScreen({required this.localFile});

  @override
  State<_PhotoPreflightScreen> createState() => _PhotoPreflightScreenState();
}

class _PhotoPreflightScreenState extends State<_PhotoPreflightScreen> {
  int _quarterTurns = 0;
  bool _saving = false;

  Future<File> _applyRotationIfNeeded(File input) async {
    final turns = _quarterTurns % 4;
    if (turns == 0) return input;

    final bytes = await input.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return input;

    // clockwise by 90deg * turns
    final rotated = img.copyRotate(decoded, angle: 90 * turns);

    final dir = await getTemporaryDirectory();
    final ext = p.extension(input.path).toLowerCase();
    final outExt = (ext == '.png') ? '.png' : '.jpg';

    final outPath = p.join(
      dir.path,
      'ootd_rotated_${DateTime.now().millisecondsSinceEpoch}$outExt',
    );

    final outFile = File(outPath);

    if (outExt == '.png') {
      await outFile.writeAsBytes(img.encodePng(rotated));
    } else {
      await outFile.writeAsBytes(img.encodeJpg(rotated, quality: 95));
    }

    return outFile;
  }

  Future<void> _continue() async {
    setState(() => _saving = true);
    try {
      final fileToUse = await _applyRotationIfNeeded(widget.localFile);
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => _AddClothingEntryPoint(localFile: fileToUse),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nepodarilo sa pripraviť fotku. Skús to prosím znova. ($e)'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Úprava fotky'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(Icons.info_outline, size: 18, color: Colors.black54),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Fotku môžeš pred spracovaním otočiť.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.black.withOpacity(0.08)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Center(
                      child: RotatedBox(
                        quarterTurns: _quarterTurns,
                        child: Image.file(
                          widget.localFile,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => setState(() => _quarterTurns = (_quarterTurns + 3) % 4),
                    icon: const Icon(Icons.rotate_left),
                    label: const Text('Vľavo'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => setState(() => _quarterTurns = (_quarterTurns + 1) % 4),
                    icon: const Icon(Icons.rotate_right),
                    label: const Text('Vpravo'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _continue,
                      icon: _saving
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Icon(Icons.check),
                      label: Text(_saving ? 'Pripravujem…' : 'Potvrdiť'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
      initialData: {'_localFilePath': widget.localFile.path},
      imageUrl: null,
      isEditing: false,
    );
  }
}

class _AddClothingScreenState extends State<AddClothingScreen> {
  // ---------------------------------------------------------
  // ✅ SEASONS RULES (celoročne vs. 4 sezóny)
  // ---------------------------------------------------------
  List<String> _sanitizeSeasons(List<String> input) {
    final set = input.toSet();
    const four = {'jar', 'leto', 'jeseň', 'zima'};

    if (set.contains('celoročne')) {
      return ['celoročne'];
    }

    if (set.containsAll(four)) {
      return ['celoročne'];
    }

    return allowedSeasons.where((s) => set.contains(s)).toList();
  }

  // ---------------------------------------------------------
  // SEARCH NORMALIZE (bez mäkčeňov)
  // ---------------------------------------------------------
  String _normalizeForSearch(String input) {
    var s = input.toLowerCase().trim();

    const map = {
      'á': 'a',
      'ä': 'a',
      'č': 'c',
      'ď': 'd',
      'é': 'e',
      'ě': 'e',
      'í': 'i',
      'ĺ': 'l',
      'ľ': 'l',
      'ň': 'n',
      'ó': 'o',
      'ô': 'o',
      'ŕ': 'r',
      'ř': 'r',
      'š': 's',
      'ť': 't',
      'ú': 'u',
      'ů': 'u',
      'ü': 'u',
      'ý': 'y',
      'ž': 'z',
    };

    final buffer = StringBuffer();
    for (final ch in s.split('')) {
      buffer.write(map[ch] ?? ch);
    }
    return buffer.toString();
  }

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _brandController = TextEditingController();

  bool _isSystemNameSelected = false;
  String? _selectedSystemNameLabel;
  String? _selectedSystemSubCategoryKey;

  File? _localImageFile;
  String? _uploadedImageUrl;
  String? _uploadedStoragePath;

  String? _selectedMainGroupKey;
  String? _selectedCategoryKey;
  String? _selectedSubCategoryKey;

  List<String> _selectedColors = [];
  List<String> _selectedStyles = [];
  List<String> _selectedPatterns = [];
  List<String> _selectedSeasons = [];

  bool _isAiLoading = false;
  bool _aiCompleted = false;
  bool _aiFailed = false;
  String? _aiError;

  final List<String> _progressSteps = const [
    'Analyzujem obrázok',
    'Rozpoznávam typ kúsku',
    'Zaraďujem do kategórie',
    'Kontrolujem farby, vzor, sezónu',
    'Pripravujem formulár',
  ];

  final List<bool> _done = [false, false, false, false, false];
  int _activeStepIndex = 0;

  Timer? _uxTimer;
  final int _uxIntervalMs = 2000;
  final int _maxFakeDoneIndex = 3;

  String? _lastTypeLabel;

  List<String> _brandOptions = [];
  bool _brandsLoaded = false;

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

      _selectedColors = (d['colors'] as List?)?.map((e) => e.toString()).toList() ?? [];
      _selectedStyles = (d['styles'] as List?)?.map((e) => e.toString()).toList() ?? [];
      _selectedPatterns = (d['patterns'] as List?)?.map((e) => e.toString()).toList() ?? [];
      if (_selectedPatterns.length > 1) _selectedPatterns = [_selectedPatterns.first];

      final loadedSeasons = (d['seasons'] as List?)?.map((e) => e.toString()).toList() ?? [];
      _selectedSeasons = _sanitizeSeasons(loadedSeasons);

      _uploadedImageUrl = widget.imageUrl;
      _uploadedStoragePath = (d['storagePath'] ?? '').toString().isEmpty ? null : (d['storagePath'] ?? '').toString();
      _aiCompleted = true;

      _lastTypeLabel = _nameController.text.trim().isEmpty ? null : _nameController.text.trim();
    }

    _loadBrandSuggestions();
    _syncSystemNameValidity();

    _nameController.addListener(() {
      final current = _nameController.text.trim();
      if (_selectedSystemNameLabel != null && current != _selectedSystemNameLabel) {
        if (_isSystemNameSelected) {
          setState(() {
            _isSystemNameSelected = false;
            _selectedSystemNameLabel = null;
            _selectedSystemSubCategoryKey = null;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _uxTimer?.cancel();
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
  // BRAND SUGGESTIONS
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
    } catch (_) {}
  }

  // ---------------------------------------------------------
  // ✅ PROGRESS (spinner + zelené fajky)
  // ---------------------------------------------------------
  void _resetProgress() {
    for (int i = 0; i < _done.length; i++) {
      _done[i] = false;
    }
    _activeStepIndex = 0;

    _uxTimer?.cancel();
    _uxTimer = Timer.periodic(Duration(milliseconds: _uxIntervalMs), (_) {
      if (!mounted) return;
      if (!_isAiLoading) return;

      setState(() {
        if (_activeStepIndex <= _maxFakeDoneIndex) {
          _done[_activeStepIndex] = true;
          _activeStepIndex = (_activeStepIndex + 1).clamp(0, _progressSteps.length - 1);
        }
      });
    });
  }

  void _stopProgressTimers() {
    _uxTimer?.cancel();
    _uxTimer = null;
  }

  void _reachMilestone(int index) {
    if (!mounted) return;
    setState(() {
      _done[index] = true;
      if (_activeStepIndex <= index && index < _progressSteps.length - 1) {
        _activeStepIndex = index + 1;
      }
    });
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

    try {
      final task = await ref.putFile(_localImageFile!).timeout(const Duration(seconds: 25));
      final url = await task.ref.getDownloadURL().timeout(const Duration(seconds: 15));

      setState(() {
        _uploadedImageUrl = url;
        _uploadedStoragePath = storagePath;
      });

      return url;
    } on TimeoutException {
      throw Exception('Upload trvá príliš dlho (timeout). Skontroluj internet a skús znova.');
    } on FirebaseException catch (e) {
      throw Exception('Upload do Storage zlyhal: ${e.code} – ${e.message ?? ''}');
    } catch (e) {
      throw Exception('Upload do Storage zlyhal: $e');
    }
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

    if (_localImageFile == null && (_uploadedImageUrl == null || _uploadedImageUrl!.isEmpty)) {
      return;
    }

    setState(() {
      _isAiLoading = true;
      _aiCompleted = false;
      _aiFailed = false;
      _aiError = null;
    });

    _resetProgress();

    try {
      // 0) upload
      final imageUrl = await _ensureImageUrl();
      if (imageUrl == null || imageUrl.isEmpty) {
        throw Exception('Nepodarilo sa získať URL obrázka.');
      }
      _reachMilestone(0);

      // 1) AI call
      const endpoint =
          'https://us-east1-outfitoftheday-4d401.cloudfunctions.net/analyzeClothingImage';

      final resp = await http
          .post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'imageUrl': imageUrl}),
      )
          .timeout(const Duration(seconds: 30));

      if (resp.statusCode != 200) {
        throw Exception('AI zlyhalo: ${resp.statusCode} ${resp.body}');
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('AI odpoveď nie je JSON objekt.');
      }

      _reachMilestone(1);

      final m = decoded;

      final String prettyType = (m['type_pretty'] ?? m['type'] ?? '').toString().trim();
      final String rawType = (m['type'] ?? '').toString().trim();
      final String canonical = (m['canonical_type'] ?? '').toString().trim();
      final String brandFromAi = (m['brand'] ?? '').toString().trim();

      final colorsFromAi = _toStringList(m['colors'] ?? m['color']);
      final stylesFromAi = _toStringList(m['style'] ?? m['styles']);
      final patternsFromAi = _toStringList(m['patterns'] ?? m['pattern']);
      final seasonsFromAi = _toStringList(m['season'] ?? m['seasons']);

      if (_nameController.text.trim().isEmpty && prettyType.isNotEmpty) {
        _nameController.text = prettyType;
        _lastTypeLabel = prettyType;
        _syncSystemNameValidity();
      }

      if (_brandController.text.trim().isEmpty && brandFromAi.isNotEmpty) {
        _brandController.text = brandFromAi;
        await _saveBrandSuggestion(brandFromAi);
      }

      // kategória
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

      _reachMilestone(2);

      // farby/štýly/vzory/sezóny
      if (colorsFromAi.isNotEmpty) {
        _selectedColors = colorsFromAi.where((c) => allowedColors.contains(c)).toList();
      }
      if (stylesFromAi.isNotEmpty) {
        _selectedStyles = stylesFromAi.where((s) => allowedStyles.contains(s)).toList();
      }

      if (patternsFromAi.isNotEmpty) {
        final filteredPatterns = patternsFromAi.where((p) => allowedPatterns.contains(p)).toList();
        _selectedPatterns = filteredPatterns.isEmpty ? [] : [filteredPatterns.first];
      }

      if (seasonsFromAi.isNotEmpty) {
        final raw = seasonsFromAi.where((s) => allowedSeasons.contains(s)).toList();
        _selectedSeasons = _sanitizeSeasons(raw);
      }

      _reachMilestone(3);

      _reachMilestone(4);
      await Future.delayed(const Duration(milliseconds: 450));

      if (!mounted) return;
      _stopProgressTimers();
      setState(() {
        _aiCompleted = true;
        _aiFailed = false;
        _isAiLoading = false;
      });
    } on TimeoutException {
      _stopProgressTimers();
      if (!mounted) return;
      setState(() {
        _aiFailed = true;
        _aiCompleted = false;
        _isAiLoading = false;
        _aiError = 'Sieťový timeout. Skontroluj internet a skús znova.';
      });
    } catch (e) {
      _stopProgressTimers();
      if (!mounted) return;
      setState(() {
        _aiFailed = true;
        _aiCompleted = false;
        _isAiLoading = false;
        _aiError = e.toString();
      });
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

      _syncSystemNameValidity();
      if (!_isSystemNameSelected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vyber názov zo zoznamu.')),
        );
        return;
      }

      if (_selectedMainGroupKey == null || _selectedCategoryKey == null || _selectedSubCategoryKey == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vyber hlavnú skupinu, kategóriu a typ.')),
        );
        return;
      }

      final brand = _brandController.text.trim();
      await _saveBrandSuggestion(brand);

      final safeSeasons = _sanitizeSeasons(_selectedSeasons);

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
        'seasons': safeSeasons.isEmpty ? ['celoročne'] : safeSeasons,
        'imageUrl': imageUrl,

        // --- AI image processing (product photo pipeline) ---
        'originalImageUrl': imageUrl,
        'cutoutImageUrl': null,
        'productImageUrl': null,

        'imageVersion': 1,
        if (_uploadedStoragePath != null) 'storagePath': _uploadedStoragePath,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!widget.isEditing) 'createdAt': FieldValue.serverTimestamp(),
      };

      // ✅ processing nastavíme len pri NOVOM kuse
      if (!widget.isEditing) {
        data['processing'] = {
          'cutout': 'queued', // queued | running | done | error
          'product': 'queued',
        };
      }

      final ref = _firestore.collection('users').doc(user.uid).collection('wardrobe');

      if (widget.isEditing && widget.itemId != null) {
        await ref.doc(widget.itemId).set(data, SetOptions(merge: true));
      } else {
        final newDoc = ref.doc();
        await newDoc.set(data, SetOptions(merge: true));
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
  // UI HELPERS
  // ---------------------------------------------------------
  Widget _buildProcessingImagePreview() {
    final Widget imgWidget;

    if (_localImageFile != null) {
      imgWidget = Image.file(_localImageFile!, fit: BoxFit.contain);
    } else if (_uploadedImageUrl != null && _uploadedImageUrl!.isNotEmpty) {
      imgWidget = Image.network(_uploadedImageUrl!, fit: BoxFit.contain);
    } else {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 260,
        width: double.infinity,
        color: Colors.grey.shade100, // jemné pozadie, aby nebolo "prázdno"
        padding: const EdgeInsets.all(12),
        alignment: Alignment.center,
        child: imgWidget,
      ),
    );
  }

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
          final done = _done[i];
          final isActive = !done && i == _activeStepIndex;

          Widget leading;
          if (done) {
            leading = const Icon(Icons.check_circle, color: Colors.green, size: 20);
          } else if (isActive) {
            leading = const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          } else {
            leading = const Icon(Icons.radio_button_unchecked, color: Colors.grey, size: 20);
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                leading,
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

  // ---------------------------------------------------------
  // SYSTEM NAME PICKER
  // ---------------------------------------------------------
  List<String> get _systemNameOptions {
    final set = <String>{};
    for (final v in subCategoryLabels.values) {
      final s = v.toString().trim();
      if (s.isNotEmpty) set.add(s);
    }
    final list = set.toList()..sort();
    return list;
  }

  String? _findSubCategoryKeyForLabel(String label) {
    final target = label.trim();
    for (final entry in subCategoryLabels.entries) {
      if (entry.value == target) return entry.key;
    }
    return null;
  }

  void _syncSystemNameValidity() {
    final current = _nameController.text.trim();
    if (current.isEmpty) {
      _isSystemNameSelected = false;
      _selectedSystemNameLabel = null;
      _selectedSystemSubCategoryKey = null;
      return;
    }

    final subKey = _findSubCategoryKeyForLabel(current);
    if (subKey != null) {
      _isSystemNameSelected = true;
      _selectedSystemNameLabel = current;
      _selectedSystemSubCategoryKey = subKey;
    } else {
      _isSystemNameSelected = false;
      _selectedSystemNameLabel = null;
      _selectedSystemSubCategoryKey = null;
    }
  }

  void _applyRulesFromSystemName(String label) {
    final chosen = label.trim();
    final subKey = _findSubCategoryKeyForLabel(chosen);

    setState(() {
      _nameController.text = chosen;
      _lastTypeLabel = chosen;

      _isSystemNameSelected = true;
      _selectedSystemNameLabel = chosen;
      _selectedSystemSubCategoryKey = subKey;

      if (subKey != null) {
        final mapped = AiClothingParser.fromCanonicalType(subKey);
        if (mapped != null) {
          _selectedMainGroupKey = mapped.mainGroupKey;
          _selectedCategoryKey = mapped.categoryKey;
          _selectedSubCategoryKey = mapped.subCategoryKey;
        }
      }

      if (_selectedMainGroupKey == null || _selectedCategoryKey == null || _selectedSubCategoryKey == null) {
        final mapped = AiClothingParser.mapType(
          AiParserInput(
            rawType: '',
            aiName: '',
            userName: chosen,
            seasons: _selectedSeasons,
            brand: _brandController.text.trim(),
          ),
        );
        if (mapped != null) {
          _selectedMainGroupKey = mapped.mainGroupKey;
          _selectedCategoryKey = mapped.categoryKey;
          _selectedSubCategoryKey = mapped.subCategoryKey;
        }
      }

      final n = chosen.toLowerCase();
      List<String>? forcedSeasons;
      if (subKey != null) {
        final k = subKey.toLowerCase();
        if (k.contains('zim')) forcedSeasons = ['zima'];
        if (k.contains('prechod')) forcedSeasons = ['jar', 'jeseň'];
        if (k.contains('let')) forcedSeasons = ['leto'];
        if (k.contains('jarn')) forcedSeasons = ['jar'];
        if (k.contains('jesen') || k.contains('jese')) forcedSeasons = ['jeseň'];
        if (k.contains('celoroc') || k.contains('celoro')) forcedSeasons = ['jar', 'leto', 'jeseň', 'zima'];
      }

      forcedSeasons ??= () {
        if (n.contains('zimn')) return ['zima'];
        if (n.contains('prechod')) return ['jar', 'jeseň'];
        if (n.contains('letn')) return ['leto'];
        if (n.contains('jarn')) return ['jar'];
        if (n.contains('jesen') || n.contains('jese')) return ['jeseň'];
        if (n.contains('celoroč') || n.contains('celoroc') || n.contains('celoro')) return ['jar', 'leto', 'jeseň', 'zima'];
        return null;
      }();

      if (forcedSeasons != null) {
        final raw = forcedSeasons.where((s) => allowedSeasons.contains(s)).toList();
        _selectedSeasons = _sanitizeSeasons(raw);
      }
    });
  }

  Future<void> _openSystemNamePicker() async {
    final options = _systemNameOptions;
    final controller = TextEditingController(text: _nameController.text.trim());

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final query = controller.text.trim();

            List<String> filtered = options;
            if (query.isNotEmpty) {
              final q = _normalizeForSearch(query);
              filtered = options.where((o) => _normalizeForSearch(o).contains(q)).toList();
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Začni písať (napr. zi...)',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (_) => setSheetState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) {
                          final label = filtered[i];
                          final selected = (_selectedSystemNameLabel == label);
                          return ListTile(
                            title: Text(label),
                            trailing: selected ? const Icon(Icons.check_circle) : null,
                            onTap: () => Navigator.of(ctx).pop(label),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null) return;
    _applyRulesFromSystemName(result);
  }

  Widget _buildSystemNameField() {
    final text = _nameController.text.trim();
    final display = text.isEmpty ? 'Vyber názov zo zoznamu' : text;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _openSystemNamePicker,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Názov',
          border: const OutlineInputBorder(),
          helperText: text.isEmpty ? 'Vyber názov zo zoznamu' : null,
          errorText: (text.isNotEmpty && !_isSystemNameSelected) ? 'Vyber názov zo zoznamu' : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                display,
                style: TextStyle(
                  color: text.isEmpty ? Theme.of(context).hintColor : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  Widget _brandAutoComplete() {
    final options = _brandOptions;

    return Autocomplete<String>(
      initialValue: TextEditingValue(text: _brandController.text),
      optionsBuilder: (TextEditingValue textEditingValue) {
        final q = textEditingValue.text.trim().toLowerCase();
        if (q.isEmpty) return options.take(25);
        return options.where((b) => b.toLowerCase().contains(q)).take(50);
      },
      onSelected: (String selection) {
        _brandController.text = selection;
        _saveBrandSuggestion(selection);
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        controller.text = _brandController.text;
        controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));

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
          onChanged: (v) => _brandController.text = v,
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

  // =========================
  // ✅ Rolovateľné multi-select okná (Farby / Štýly / Sezóny)
  // =========================
  Widget _buildMultiSelectField({
    required String label,
    required List<String> options,
    required List<String> selected,
    required ValueChanged<List<String>> onChanged,
  }) {
    final text = selected.isEmpty
        ? 'Vyber...'
        : () {
      const maxVisible = 3;
      if (selected.length <= maxVisible) {
        return selected.join(', ');
      }
      final visible = selected.take(maxVisible).join(', ');
      final rest = selected.length - maxVisible;
      return '$visible +$rest';
    }();

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final result = await _openMultiSelectBottomSheet(
          title: label,
          options: options,
          initialSelected: selected,
          enforceSeasonRules: (label == 'Sezóny'),
        );
        if (result != null) {
          onChanged(result);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.keyboard_arrow_down_rounded),
          ],
        ),
      ),
    );
  }

  Future<List<String>?> _openMultiSelectBottomSheet({
    required String title,
    required List<String> options,
    required List<String> initialSelected,
    bool enforceSeasonRules = false,
  }) async {
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final tempSelected = <String>{...initialSelected};
        String query = '';

        List<String> filtered() {
          final q = query.trim().toLowerCase();
          if (q.isEmpty) return options;
          return options.where((o) => o.toLowerCase().contains(q)).toList();
        }

        final height = MediaQuery.of(ctx).size.height * 0.75;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            void toggle(String value, bool v) {
              setSheetState(() {
                if (!enforceSeasonRules) {
                  if (v) {
                    tempSelected.add(value);
                  } else {
                    tempSelected.remove(value);
                  }
                  return;
                }

                const four = {'jar', 'leto', 'jeseň', 'zima'};

                if (value == 'celoročne') {
                  if (v) {
                    tempSelected
                      ..clear()
                      ..add('celoročne');
                  } else {
                    tempSelected.remove('celoročne');
                  }
                  return;
                }

                if (tempSelected.contains('celoročne')) {
                  tempSelected.remove('celoročne');
                }

                if (v) {
                  tempSelected.add(value);
                } else {
                  tempSelected.remove(value);
                }

                if (tempSelected.containsAll(four)) {
                  tempSelected
                    ..clear()
                    ..add('celoročne');
                }
              });
            }

            return SafeArea(
              child: SizedBox(
                height: height,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 12 + MediaQuery.of(ctx).viewInsets.bottom,
                    top: 4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(ctx).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Hľadať...',
                          border: UnderlineInputBorder(),
                        ),
                        onChanged: (v) => setSheetState(() => query = v),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Builder(builder: (ctx) {
                          final items = filtered();
                          return ListView.builder(
                            itemCount: items.length,
                            itemBuilder: (ctx, i) {
                              final o = items[i];
                              final checked = tempSelected.contains(o);
                              final primary = Theme.of(ctx).colorScheme.primary;

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(o, style: Theme.of(ctx).textTheme.bodyLarge),
                                trailing: checked
                                    ? Icon(Icons.check_circle_rounded, color: primary)
                                    : const SizedBox(width: 24, height: 24),
                                onTap: () => toggle(o, !checked),
                              );
                            },
                          );
                        }),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(null),
                            child: const Text('Zrušiť'),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => setSheetState(() => tempSelected.clear()),
                            child: const Text('Vymazať'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => Navigator.of(ctx).pop(tempSelected.toList()),
                            child: const Text('Hotovo'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null) return null;
    final ordered = options.where((o) => result.contains(o)).toList();
    if (enforceSeasonRules) return _sanitizeSeasons(ordered);
    return ordered;
  }

  // =========================
  // ✅ Single-select okno (Vzor)
  // =========================
  Widget _buildSingleSelectField({
    required String label,
    required List<String> options,
    required String? selected,
    required ValueChanged<String?> onChanged,
  }) {
    final text = (selected == null || selected.isEmpty) ? 'Vyber...' : selected;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final result = await _openSingleSelectBottomSheet(
          title: label,
          options: options,
          selected: selected,
        );
        if (result != null) {
          onChanged(result);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.keyboard_arrow_down_rounded),
          ],
        ),
      ),
    );
  }

  Future<String?> _openSingleSelectBottomSheet({
    required String title,
    required List<String> options,
    required String? selected,
  }) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        String query = '';

        List<String> filtered() {
          final q = query.trim().toLowerCase();
          if (q.isEmpty) return options;
          return options.where((o) => o.toLowerCase().contains(q)).toList();
        }

        final height = MediaQuery.of(ctx).size.height * 0.75;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final items = filtered();
            final primary = Theme.of(ctx).colorScheme.primary;

            return SafeArea(
              child: SizedBox(
                height: height,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 12 + MediaQuery.of(ctx).viewInsets.bottom,
                    top: 4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(ctx).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Hľadať...',
                          border: UnderlineInputBorder(),
                        ),
                        onChanged: (v) => setSheetState(() => query = v),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (ctx, i) {
                            final o = items[i];
                            final checked = (selected == o);

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(o, style: Theme.of(ctx).textTheme.bodyLarge),
                              trailing: checked
                                  ? Icon(Icons.check_circle_rounded, color: primary)
                                  : const SizedBox(width: 24, height: 24),
                              onTap: () => Navigator.of(ctx).pop(o),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(null),
                            child: const Text('Zrušiť'),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(''),
                            child: const Text('Vymazať'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => Navigator.of(ctx).pop(selected ?? ''),
                            child: const Text('Hotovo'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((value) {
      if (value == null) return null;
      if (value.isEmpty) return '';
      return value;
    });
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
        _buildSystemNameField(),
        const SizedBox(height: 12),
        _brandAutoComplete(),
        const SizedBox(height: 12),
        CategoryPicker(
          hideSubCategory: true,
          initialMainGroup: _selectedMainGroupKey,
          initialCategory: _selectedCategoryKey,
          initialSubCategory: _selectedSubCategoryKey,
          onChanged: (data) {
            final main = data['mainGroup'];
            final cat = data['category'];
            final sub = data['subCategory'];

            final subLabel = (sub != null && sub.isNotEmpty) ? (subCategoryLabels[sub] ?? sub) : '';

            setState(() {
              _selectedMainGroupKey = main;
              _selectedCategoryKey = cat;
              _selectedSubCategoryKey = sub;

              final currentName = _nameController.text.trim();
              if (currentName.isEmpty || currentName == (_lastTypeLabel ?? '')) {
                if (subLabel.isNotEmpty) {
                  _nameController.text = subLabel;
                  _lastTypeLabel = subLabel;
                  _syncSystemNameValidity();
                }
              }
            });
          },
        ),
        const SizedBox(height: 12),
        _buildMultiSelectField(
          label: 'Farby',
          options: allowedColors,
          selected: _selectedColors,
          onChanged: (v) => setState(() => _selectedColors = v),
        ),
        const SizedBox(height: 12),
        _buildMultiSelectField(
          label: 'Štýly',
          options: allowedStyles,
          selected: _selectedStyles,
          onChanged: (v) => setState(() => _selectedStyles = v),
        ),
        const SizedBox(height: 12),
        _buildSingleSelectField(
          label: 'Vzor',
          options: allowedPatterns,
          selected: _selectedPatterns.isEmpty ? null : _selectedPatterns.first,
          onChanged: (v) {
            setState(() {
              if (v == null) return;
              if (v.isEmpty) {
                _selectedPatterns = [];
              } else {
                _selectedPatterns = [v];
              }
            });
          },
        ),
        const SizedBox(height: 12),
        _buildMultiSelectField(
          label: 'Sezóny',
          options: allowedSeasons,
          selected: _selectedSeasons,
          onChanged: (v) => setState(() => _selectedSeasons = _sanitizeSeasons(v)),
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
                _buildProcessingImagePreview(),
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
