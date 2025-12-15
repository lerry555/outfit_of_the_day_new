// lib/screens/add_clothing_screen.dart

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

  File? _localImageFile;
  String? _uploadedImageUrl;

  // ✅ NOVÉ: uložíme si aj Storage path kvôli background triggeru
  String? _uploadedStoragePath;

  // Form selections
  String? _selectedMainGroupKey;
  String? _selectedCategoryKey;
  String? _selectedSubCategoryKey;

  List<String> _selectedColors = [];
  List<String> _selectedStyles = [];
  List<String> _selectedPatterns = [];
  List<String> _selectedSeasons = [];
  bool _isClean = false;

  // AI state
  bool _isAiLoading = false;
  bool _aiCompleted = false;
  bool _aiFailed = false;
  String? _aiError;

  // Loader stages
  Timer? _progressTimer;
  int _progressIndex = 0;
  final List<String> _progressSteps = const [
    'Analyzujem obrázok…',
    'Rozpoznávam typ kúsku…',
    'Zaraďujem do kategórie…',
    'Kontrolujem farby a štýl…',
    'Pripravujem formulár…',
  ];

  String? _lastTypeLabel;

  @override
  void initState() {
    super.initState();

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
      _selectedSeasons = (d['seasons'] as List?)?.map((e) => e.toString()).toList() ?? [];
      _isClean = (d['isClean'] == true);

      _uploadedImageUrl = widget.imageUrl;
      _uploadedStoragePath = (d['storagePath'] ?? '').toString().isEmpty ? null : (d['storagePath'] ?? '').toString();
      _aiCompleted = true;

      _lastTypeLabel = _nameController.text.trim().isEmpty ? null : _nameController.text.trim();
    }
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
  // PICK
  // ---------------------------------------------------------
  Future<void> _pickFromCamera() async {
    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (x == null) return;
    await _onImageSelected(File(x.path));
  }

  Future<void> _pickFromGallery() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (x == null) return;
    await _onImageSelected(File(x.path));
  }

  Future<void> _onImageSelected(File file) async {
    setState(() {
      _localImageFile = file;
      _uploadedImageUrl = null;
      _uploadedStoragePath = null;

      _nameController.clear();
      _brandController.clear();
      _selectedMainGroupKey = null;
      _selectedCategoryKey = null;
      _selectedSubCategoryKey = null;
      _selectedColors = [];
      _selectedStyles = [];
      _selectedPatterns = [];
      _selectedSeasons = [];
      _isClean = false;
      _lastTypeLabel = null;

      _aiCompleted = false;
      _aiFailed = false;
      _aiError = null;
    });

    await _fillWithAi();
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
      _uploadedStoragePath = storagePath; // ✅ toto je kľúčové pre trigger
    });

    return url;
  }

  // ---------------------------------------------------------
  // AI
  // ---------------------------------------------------------
  void _startProgress() {
    _progressTimer?.cancel();
    _progressIndex = 0;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!mounted) return;
      setState(() {
        _progressIndex = (_progressIndex + 1) % _progressSteps.length;
      });
    });
  }

  void _stopProgress() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

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
    _startProgress();

    try {
      final imageUrl = await _ensureImageUrl();
      if (imageUrl == null || imageUrl.isEmpty) {
        throw Exception('Nepodarilo sa získať URL obrázka.');
      }

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

      final m = decoded;

      final String prettyType = (m['type_pretty'] ?? m['type'] ?? '').toString().trim();
      final String rawType = (m['type'] ?? '').toString().trim();
      final String canonical = (m['canonical_type'] ?? '').toString().trim();
      final String brandFromAi = (m['brand'] ?? '').toString().trim();

      final colorsFromAi = _toStringList(m['colors'] ?? m['color']);
      final stylesFromAi = _toStringList(m['style'] ?? m['styles']);
      final patternsFromAi = _toStringList(m['patterns'] ?? m['pattern']);
      final seasonsFromAi = _toStringList(m['season'] ?? m['seasons']);

      setState(() {
        if (_nameController.text.trim().isEmpty && prettyType.isNotEmpty) {
          _nameController.text = prettyType;
          _lastTypeLabel = prettyType;
        }
        if (_brandController.text.trim().isEmpty && brandFromAi.isNotEmpty) {
          _brandController.text = brandFromAi;
        }

        if (colorsFromAi.isNotEmpty) {
          _selectedColors = colorsFromAi.where((c) => allowedColors.contains(c)).toList();
        }
        if (stylesFromAi.isNotEmpty) {
          _selectedStyles = stylesFromAi.where((s) => allowedStyles.contains(s)).toList();
        }
        if (patternsFromAi.isNotEmpty) {
          _selectedPatterns = patternsFromAi.where((p) => allowedPatterns.contains(p)).toList();
        }
        if (seasonsFromAi.isNotEmpty) {
          _selectedSeasons = seasonsFromAi.where((s) => allowedSeasons.contains(s)).toList();
        }
      });

      setState(() {
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

        _aiCompleted = true;
        _aiFailed = false;
        _isAiLoading = false;
      });
    } catch (e) {
      setState(() {
        _aiFailed = true;
        _aiCompleted = false;
        _isAiLoading = false;
        _aiError = e.toString();
      });
    } finally {
      _stopProgress();
      if (mounted) setState(() {});
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

      if (_selectedMainGroupKey == null || _selectedCategoryKey == null || _selectedSubCategoryKey == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vyber hlavnú skupinu, kategóriu a typ.')),
        );
        return;
      }

      final data = <String, dynamic>{
        'name': _nameController.text.trim(),
        'brand': _brandController.text.trim(),

        // ✅ ukladaj oboje (kvôli rôznym častiam appky)
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
        'isClean': _isClean,
        'imageUrl': imageUrl,

        // ✅ kľúčové pre Storage trigger match
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
  // UI
  // ---------------------------------------------------------
  Widget _buildPickUi() {
    return Column(
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
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _pickFromCamera,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Odfotiť'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickFromGallery,
                icon: const Icon(Icons.photo_library),
                label: const Text('Z galérie'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAiLoader() {
    final step = _progressSteps[_progressIndex];

    return Column(
      children: [
        const SizedBox(height: 16),
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
        const SizedBox(height: 18),
        const CircularProgressIndicator(),
        const SizedBox(height: 12),
        Text(step, style: const TextStyle(fontSize: 16)),
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
        TextField(
          controller: _brandController,
          decoration: const InputDecoration(
            labelText: 'Značka',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),

        CategoryPicker(
          initialMainGroup: _selectedMainGroupKey,
          initialCategory: _selectedCategoryKey,
          initialSubCategory: _selectedSubCategoryKey,
          onChanged: (data) {
            final main = data['mainGroup'];
            final cat = data['category'];
            final sub = data['subCategory'];

            final subLabel = (sub != null && sub.isNotEmpty)
                ? (subCategoryLabels[sub] ?? sub)
                : '';

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

        SwitchListTile(
          title: const Text('Čisté'),
          value: _isClean,
          onChanged: (v) => setState(() => _isClean = v),
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
              if (showPick) _buildPickUi(),
              if (showLoader) _buildAiLoader(),
              if (_aiFailed) _buildAiError(),
              if (showForm) _buildForm(),
            ],
          ),
        ),
      ),
    );
  }
}
