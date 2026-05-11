import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class StylePreferencesScreen extends StatefulWidget {
  const StylePreferencesScreen({super.key});

  @override
  State<StylePreferencesScreen> createState() => _StylePreferencesScreenState();
}

class _StylePreferencesScreenState extends State<StylePreferencesScreen> {
  static const Color _bgTop = Color(0xFF111111);
  static const Color _bgMid = Color(0xFF0C0C0D);
  static const Color _bgBottom = Color(0xFF080809);
  static const Color _accent = Color(0xFFC8A36A);
  static const Color _textPrimary = Color(0xFFF1F0EC);
  static const Color _textSecondary = Color(0xFFAAA59B);
  static const Color _border = Color(0x26FFFFFF);

  static const List<String> _colorOptions = <String>[
    'Čierna',
    'Biela',
    'Sivá',
    'Béžová',
    'Hnedá',
    'Modrá',
    'Zelená',
    'Červená',
    'Ružová',
    'Fialová',
  ];

  static const List<String> _styleOptions = <String>[
    'Casual',
    'Elegantný',
    'Streetwear',
    'Športový',
    'Minimalistický',
    'Business',
    'Romantický',
    'Luxusný',
  ];

  static const List<String> _commonBrands = <String>[
    'Nike',
    'Adidas',
    'Puma',
    'Zara',
    'H&M',
    'Reserved',
    'House',
    'Cropp',
    'Sinsay',
    'Pull&Bear',
    'Bershka',
    'Stradivarius',
    'Mango',
    'New Yorker',
    'Levi\'s',
    'Calvin Klein',
    'Tommy Hilfiger',
    'Guess',
    'Under Armour',
    'The North Face',
    'Columbia',
    'Jack&Jones',
    'C&A',
    'Decathlon',
  ];

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final TextEditingController _brandController = TextEditingController();
  final TextEditingController _topSizeController = TextEditingController();
  final TextEditingController _outerwearSizeController = TextEditingController();
  final TextEditingController _pantsSizeController = TextEditingController();
  final TextEditingController _shortsSizeController = TextEditingController();
  final TextEditingController _shoeSizeController = TextEditingController();

  final Set<String> _favoriteColors = <String>{};
  final Set<String> _avoidedColors = <String>{};
  final Set<String> _preferredStyles = <String>{};
  final List<String> _favoriteBrands = <String>[];

  bool _isLoading = true;
  bool _isSaving = false;
  String? _expandedSectionKey;

  @override
  void initState() {
    super.initState();
    _brandController.addListener(_onBrandTextChanged);
    _loadPreferences();
  }

  @override
  void dispose() {
    _brandController.removeListener(_onBrandTextChanged);
    _brandController.dispose();
    _topSizeController.dispose();
    _outerwearSizeController.dispose();
    _pantsSizeController.dispose();
    _shortsSizeController.dispose();
    _shoeSizeController.dispose();
    super.dispose();
  }

  void _onBrandTextChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPreferences() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('stylePreferences')
          .doc('main')
          .get();

      final data = doc.data();
      if (data != null) {
        _favoriteColors
          ..clear()
          ..addAll(_stringList(data['favoriteColors']));
        _avoidedColors
          ..clear()
          ..addAll(_stringList(data['avoidedColors']));
        _preferredStyles
          ..clear()
          ..addAll(_stringList(data['preferredStyles']));
        _favoriteBrands
          ..clear()
          ..addAll(_stringList(data['favoriteBrands']));
        _avoidedColors.removeWhere((color) => _favoriteColors.contains(color));

        final topSize = _stringValue(data['topSize']);
        final pantsSize = _stringValue(data['pantsSize']);
        final legacyBottomSize = _stringValue(data['bottomSize']);

        _topSizeController.text = topSize;
        _outerwearSizeController.text = _stringValue(data['outerwearSize']);
        _pantsSizeController.text =
            pantsSize.isNotEmpty ? pantsSize : legacyBottomSize;
        _shortsSizeController.text = _stringValue(data['shortsSize']);
        _shoeSizeController.text = _stringValue(data['shoeSize']);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nepodarilo sa načítať preferencie.'),
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<String> _stringList(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  String _stringValue(dynamic raw) {
    if (raw == null) return '';
    return raw.toString().trim();
  }

  void _toggleSelection(Set<String> target, String value) {
    setState(() {
      if (target.contains(value)) {
        target.remove(value);
      } else {
        target.add(value);
      }
    });
  }

  void _toggleFavoriteColor(String value) {
    setState(() {
      if (_favoriteColors.contains(value)) {
        _favoriteColors.remove(value);
      } else {
        _favoriteColors.add(value);
        _avoidedColors.remove(value);
      }
    });
  }

  void _toggleAvoidedColor(String value) {
    setState(() {
      if (_avoidedColors.contains(value)) {
        _avoidedColors.remove(value);
      } else {
        _avoidedColors.add(value);
        _favoriteColors.remove(value);
      }
    });
  }

  void _addBrand() {
    final value = _brandController.text.trim();
    if (value.isEmpty) return;
    if (_favoriteBrands.any((b) => b.toLowerCase() == value.toLowerCase())) {
      _brandController.clear();
      return;
    }
    setState(() {
      _favoriteBrands.add(value);
      _brandController.clear();
    });
  }

  List<String> get _brandSuggestions {
    final query = _brandController.text.trim().toLowerCase();
    if (query.isEmpty) return const <String>[];
    return _commonBrands
        .where((brand) => brand.toLowerCase().contains(query))
        .where(
          (brand) =>
              !_favoriteBrands.any((saved) => saved.toLowerCase() == brand.toLowerCase()),
        )
        .take(6)
        .toList();
  }

  void _removeBrand(String brand) {
    setState(() {
      _favoriteBrands.remove(brand);
    });
  }

  Future<void> _savePreferences() async {
    final user = _auth.currentUser;
    if (user == null || _isSaving) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isSaving = true;
    });

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('stylePreferences')
          .doc('main')
          .set({
        'favoriteColors': _favoriteColors.toList(),
        'avoidedColors': _avoidedColors.toList(),
        'preferredStyles': _preferredStyles.toList(),
        'favoriteBrands': _favoriteBrands,
        'topSize': _topSizeController.text.trim(),
        'outerwearSize': _outerwearSizeController.text.trim(),
        'pantsSize': _pantsSizeController.text.trim(),
        'shortsSize': _shortsSizeController.text.trim(),
        'shoeSize': _shoeSizeController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preferencie uložené')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nepodarilo sa uložiť preferencie.'),
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
    }
  }

  void _setSizeFromChip(TextEditingController controller, String value) {
    setState(() {
      controller.text = value;
    });
  }

  bool _isChipSelected(TextEditingController controller, String chip) {
    return controller.text.trim().toLowerCase() == chip.toLowerCase();
  }

  void _toggleExpandedSection(String key) {
    setState(() {
      _expandedSectionKey = _expandedSectionKey == key ? null : key;
    });
  }

  String _setPreview(Set<String> values, {int limit = 3}) {
    if (values.isEmpty) return 'Zatiaľ nič vybrané';
    final list = values.toList();
    if (list.length <= limit) return list.join(', ');
    final visible = list.take(limit).join(', ');
    return '$visible +${list.length - limit}';
  }

  String _sizesPreview() {
    final values = <String>[
      _topSizeController.text.trim(),
      _outerwearSizeController.text.trim(),
      _pantsSizeController.text.trim(),
      _shortsSizeController.text.trim(),
      _shoeSizeController.text.trim(),
    ].where((v) => v.isNotEmpty).toList();
    if (values.isEmpty) return 'Zatiaľ nič vybrané';
    return values.take(3).join(' / ');
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Štýlové preferencie'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: _textPrimary,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgMid, _bgBottom],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(_accent),
                  ),
                )
              : user == null
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Táto sekcia je dostupná len pre prihlásených používateľov.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _textPrimary),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 2),
                          child: Text(
                            'Pomôž AI stylistovi lepšie pochopiť tvoj štýl.',
                            style: TextStyle(
                              color: _textSecondary,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _ExpandableSectionCard(
                          isExpanded: _expandedSectionKey == 'favoriteColors',
                          onTap: () => _toggleExpandedSection('favoriteColors'),
                          title: 'Obľúbené farby',
                          preview: _setPreview(_favoriteColors),
                          child: _ChipsWrap(
                            options: _colorOptions,
                            selected: _favoriteColors,
                            onToggle: _toggleFavoriteColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _ExpandableSectionCard(
                          isExpanded: _expandedSectionKey == 'avoidedColors',
                          onTap: () => _toggleExpandedSection('avoidedColors'),
                          title: 'Farby, ktorým sa chceš vyhýbať',
                          preview: _setPreview(_avoidedColors),
                          child: _ChipsWrap(
                            options: _colorOptions,
                            selected: _avoidedColors,
                            onToggle: _toggleAvoidedColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _ExpandableSectionCard(
                          isExpanded: _expandedSectionKey == 'preferredStyles',
                          onTap: () => _toggleExpandedSection('preferredStyles'),
                          title: 'Preferovaný štýl',
                          preview: _setPreview(_preferredStyles),
                          child: _ChipsWrap(
                            options: _styleOptions,
                            selected: _preferredStyles,
                            onToggle: (value) =>
                                _toggleSelection(_preferredStyles, value),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SectionCard(
                          title: 'Obľúbené značky',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _brandController,
                                      style: const TextStyle(color: _textPrimary),
                                      decoration: _fieldDecoration(
                                        hint: 'Pridaj značku, napr. Zara, Nike...',
                                      ),
                                      onSubmitted: (_) => _addBrand(),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    onPressed: _addBrand,
                                    style: IconButton.styleFrom(
                                      backgroundColor:
                                          const Color(0x26C8A36A),
                                      foregroundColor: _accent,
                                    ),
                                    icon: const Icon(Icons.add),
                                  ),
                                ],
                              ),
                              if (_brandSuggestions.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF17171A),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: _border),
                                  ),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: _brandSuggestions
                                        .map(
                                          (brand) => ActionChip(
                                            label: Text(brand),
                                            onPressed: () {
                                              _brandController.text = brand;
                                              _addBrand();
                                            },
                                            labelStyle: const TextStyle(
                                              color: _textPrimary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            backgroundColor: const Color(0xFF222227),
                                            side: const BorderSide(
                                              color: Color(0x44C8A36A),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                              ],
                              if (_favoriteBrands.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _favoriteBrands
                                      .map(
                                        (brand) => Chip(
                                          label: Text(brand),
                                          labelStyle: const TextStyle(
                                            color: _textPrimary,
                                          ),
                                          deleteIconColor: _accent,
                                          onDeleted: () => _removeBrand(brand),
                                          backgroundColor: const Color(0xFF222227),
                                          side: const BorderSide(
                                            color: Color(0x44C8A36A),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _ExpandableSectionCard(
                          isExpanded: _expandedSectionKey == 'sizes',
                          onTap: () => _toggleExpandedSection('sizes'),
                          title: 'Veľkosti',
                          preview: _sizesPreview(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SizePreferenceCard(
                                title: 'Vrch / tričká / mikiny',
                                helper: 'Najčastejšia veľkosť pre tričká, mikiny a svetre.',
                                controller: _topSizeController,
                                options: const ['XS', 'S', 'M', 'L', 'XL', 'XXL'],
                                onChipTap: (value) =>
                                    _setSizeFromChip(_topSizeController, value),
                                isSelected: (chip) =>
                                    _isChipSelected(_topSizeController, chip),
                                onChanged: () => setState(() {}),
                              ),
                              const SizedBox(height: 10),
                              _SizePreferenceCard(
                                title: 'Bundy / kabáty',
                                helper: 'Ak nosíš bundu cez mikinu, pokojne zvoľ väčšiu veľkosť.',
                                controller: _outerwearSizeController,
                                options: const ['XS', 'S', 'M', 'L', 'XL', 'XXL'],
                                onChipTap: (value) =>
                                    _setSizeFromChip(_outerwearSizeController, value),
                                isSelected: (chip) =>
                                    _isChipSelected(_outerwearSizeController, chip),
                                onChanged: () => setState(() {}),
                              ),
                              const SizedBox(height: 10),
                              _SizePreferenceCard(
                                title: 'Nohavice / rifle',
                                helper:
                                    'Môžeš zvoliť písmenovú veľkosť alebo rifľové číslovanie ako 33/32.',
                                controller: _pantsSizeController,
                                options: const [
                                  'S',
                                  'M',
                                  'L',
                                  'XL',
                                  '30/32',
                                  '31/32',
                                  '32/32',
                                  '33/32',
                                  '34/32',
                                ],
                                onChipTap: (value) =>
                                    _setSizeFromChip(_pantsSizeController, value),
                                isSelected: (chip) =>
                                    _isChipSelected(_pantsSizeController, chip),
                                onChanged: () => setState(() {}),
                              ),
                              const SizedBox(height: 10),
                              _SizePreferenceCard(
                                title: 'Kraťasy / tepláky',
                                helper:
                                    'Pri voľnejších spodkoch často stačí písmenová veľkosť.',
                                controller: _shortsSizeController,
                                options: const ['S', 'M', 'L', 'XL', '30', '31', '32', '33', '34'],
                                onChipTap: (value) =>
                                    _setSizeFromChip(_shortsSizeController, value),
                                isSelected: (chip) =>
                                    _isChipSelected(_shortsSizeController, chip),
                                onChanged: () => setState(() {}),
                              ),
                              const SizedBox(height: 10),
                              _SizePreferenceCard(
                                title: 'Obuv',
                                helper: 'Zadaj najčastejšiu EU veľkosť, ktorú nosíš.',
                                controller: _shoeSizeController,
                                options: const ['38', '39', '40', '41', '42', '43', '44', '45', '46'],
                                onChipTap: (value) =>
                                    _setSizeFromChip(_shoeSizeController, value),
                                isSelected: (chip) =>
                                    _isChipSelected(_shoeSizeController, chip),
                                onChanged: () => setState(() {}),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Pri spodkoch môžeš zadať napr. M, L alebo 33/32 podľa toho, ako daný typ oblečenia nosíš.',
                                style: TextStyle(
                                  color: _textSecondary,
                                  fontSize: 12.5,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _savePreferences,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accent,
                              foregroundColor: const Color(0xFF191512),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(0xFF191512),
                                      ),
                                    ),
                                  )
                                : const Text(
                                    'Uložiť preferencie',
                                    style: TextStyle(fontWeight: FontWeight.w700),
                                  ),
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _textSecondary),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accent),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _StylePreferencesScreenState._border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22C8A36A),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _StylePreferencesScreenState._accent,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpandableSectionCard extends StatelessWidget {
  const _ExpandableSectionCard({
    required this.isExpanded,
    required this.onTap,
    required this.title,
    required this.preview,
    required this.child,
  });

  final bool isExpanded;
  final VoidCallback onTap;
  final String title;
  final String preview;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _StylePreferencesScreenState._border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22C8A36A),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: Column(
              children: [
                InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: _StylePreferencesScreenState._accent,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                preview,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _StylePreferencesScreenState._textSecondary,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AnimatedRotation(
                          turns: isExpanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeInOut,
                          child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: _StylePreferencesScreenState._accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isExpanded) ...[
                  Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    color: _StylePreferencesScreenState._border,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: child,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChipsWrap extends StatelessWidget {
  const _ChipsWrap({
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options
          .map(
            (option) => FilterChip(
              label: Text(option),
              selected: selected.contains(option),
              onSelected: (_) => onToggle(option),
              labelStyle: TextStyle(
                color: selected.contains(option)
                    ? const Color(0xFF191512)
                    : _StylePreferencesScreenState._textPrimary,
                fontWeight: FontWeight.w600,
              ),
              selectedColor: _StylePreferencesScreenState._accent,
              backgroundColor: const Color(0xFF222227),
              side: BorderSide(
                color: selected.contains(option)
                    ? _StylePreferencesScreenState._accent
                    : const Color(0x44C8A36A),
              ),
              checkmarkColor: const Color(0xFF191512),
            ),
          )
          .toList(),
    );
  }
}

class _SizePreferenceCard extends StatelessWidget {
  const _SizePreferenceCard({
    required this.title,
    required this.helper,
    required this.controller,
    required this.options,
    required this.onChipTap,
    required this.isSelected,
    required this.onChanged,
  });

  final String title;
  final String helper;
  final TextEditingController controller;
  final List<String> options;
  final ValueChanged<String> onChipTap;
  final bool Function(String chip) isSelected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _StylePreferencesScreenState._border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _StylePreferencesScreenState._textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            helper,
            style: const TextStyle(
              color: _StylePreferencesScreenState._textSecondary,
              fontSize: 12,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: options
                .map(
                  (chip) => FilterChip(
                    label: Text(chip),
                    selected: isSelected(chip),
                    onSelected: (_) => onChipTap(chip),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    labelStyle: TextStyle(
                      color: isSelected(chip)
                          ? const Color(0xFF191512)
                          : _StylePreferencesScreenState._textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    selectedColor: _StylePreferencesScreenState._accent,
                    backgroundColor: const Color(0xFF222227),
                    side: BorderSide(
                      color: isSelected(chip)
                          ? _StylePreferencesScreenState._accent
                          : const Color(0x44C8A36A),
                    ),
                    checkmarkColor: const Color(0xFF191512),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            onChanged: (_) => onChanged(),
            style: const TextStyle(color: _StylePreferencesScreenState._textPrimary),
            decoration: InputDecoration(
              hintText: 'Vlastná hodnota (voliteľné)',
              hintStyle: const TextStyle(color: _StylePreferencesScreenState._textSecondary),
              filled: true,
              fillColor: const Color(0xFF222227),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _StylePreferencesScreenState._border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _StylePreferencesScreenState._accent),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}
