import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:outfitofTheDay/constants/app_constants.dart';
import 'package:outfitofTheDay/screens/clothing_detail_screen.dart';
import 'package:outfitofTheDay/screens/wardrobe_analysis_screen.dart';
class _WardrobeLuxuryPalette {
  static const Color bgTop = Color(0xFF111111);
  static const Color bgMid = Color(0xFF0C0C0D);
  static const Color bgBottom = Color(0xFF080809);

  static const Color surface = Color(0xFF151517);
  static const Color surfaceSoft = Color(0xFF1B1B1F);
  static const Color surfaceElevated = Color(0xFF242329);

  static const Color textPrimary = Color(0xFFF1F0EC);
  static const Color textSecondary = Color(0xFFAAA59B);

  static const Color accent = Color(0xFFC8A36A);
  static const Color accentSoft = Color(0xFF9D7C4C);
  static const Color accentGlow = Color(0x66C8A36A);
  static const Color border = Color(0x26FFFFFF);
}
class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({Key? key}) : super(key: key);

  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _authUser = FirebaseAuth.instance.currentUser;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  String _sortOption = 'Najnovšie';
  final List<String> _sortOptions = const [
    'Najnovšie',
    'Najstaršie',
    'Značka',
    'Farba',
    'Najčastejšie nosené',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // ✅ DELETE helpers
  // ---------------------------------------------------------------------------
  Future<void> _confirmAndDelete(BuildContext context, Map<String, dynamic> data) async {
    if (_authUser == null) return;

    final id = data['__id'] as String?;
    if (id == null || id.isEmpty) return;

    final name = (data['name'] as String?)?.trim().isNotEmpty == true
        ? (data['name'] as String)
        : (data['subCategoryLabel'] as String?) ?? 'Tento kúsok';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vymazať oblečenie?'),
        content: Text('Naozaj chceš vymazať „$name“ zo šatníka?\n\nToto sa nedá vrátiť späť.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Zrušiť'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Vymazať'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      // 1) Delete Firestore document
      await _firestore
          .collection('users')
          .doc(_authUser!.uid)
          .collection('wardrobe')
          .doc(id)
          .delete();

      // 2) Best-effort delete Storage files (ak sú to Firebase Storage URL)
      final urls = <String?>[
        data['productImageUrl'] as String?,
        data['cleanImageUrl'] as String?,
        data['cutoutImageUrl'] as String?,
        data['originalImageUrl'] as String?,
        data['imageUrl'] as String?, // legacy
      ];

      for (final u in urls) {
        await _tryDeleteStorageUrl(u);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kúsok bol vymazaný.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nepodarilo sa vymazať kúsok: $e')),
      );
    }
  }

  Future<void> _tryDeleteStorageUrl(String? url) async {
    final u = url?.trim();
    if (u == null || u.isEmpty) return;

    try {
      final ref = FirebaseStorage.instance.refFromURL(u);
      await ref.delete();
    } catch (_) {
      // ticho ignorujeme: nie je Storage URL, alebo už neexistuje, alebo nemáme práva
    }
  }

  // ---------------------------------------------------------------------------
  // Legend bottom sheet
  // ---------------------------------------------------------------------------
  void _showProcessingLegend(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _SheetHandle(),
                SizedBox(height: 12),
                Text(
                  'Úprava fotiek',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4A6CF7)),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Modrý kruh znamená, že fotka sa ešte spracováva na pozadí '
                            '(vymazanie pozadia alebo vytvorenie produktovej fotky). '
                            'Keď úprava skončí, kruh zmizne a zostane finálna verzia fotky.',
                        style: TextStyle(color: Colors.white70, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // -----------------------------
  // Helpers – normalizácia listov
  // -----------------------------
  List<String> _normalizeList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.map((e) => e.toString()).toList();
    if (value is String && value.isNotEmpty) return [value];
    return [];
  }

  // -----------------------------
  // Helpers – vyhľadávanie (bez diakritiky)
  // -----------------------------
  bool _matchesSearch(Map<String, dynamic> data, String query) {
    final q = _normalizeText(query);
    if (q.isEmpty) return true;

    final buffer = StringBuffer();

    void addField(dynamic v) {
      if (v == null) return;
      if (v is List) {
        buffer.write(' ');
        buffer.write(v.join(' '));
      } else {
        buffer.write(' ');
        buffer.write(v.toString());
      }
    }

    addField(data['name']);
    addField(data['brand']);

    addField(data['mainGroupLabel']);
    addField(data['categoryLabel']);
    addField(data['subCategoryLabel']);
    addField(data['mainGroup']);
    addField(data['categoryKey']);
    addField(data['subCategoryKey']);

    addField(data['mainCategory']);
    addField(data['category']);

    addField(data['color']);
    addField(data['style']);
    addField(data['pattern']);
    addField(data['season']);

    final text = _normalizeText(buffer.toString());
    return text.contains(q);
  }

  String _normalizeText(String input) {
    final lower = input.toLowerCase();

    const from = 'áäčďéěíĺľňóôŕřšťúůýžÁÄČĎÉĚÍĹĽŇÓÔŔŘŠŤÚŮÝŽ';
    const to = 'aacdeeillnoorrstuuyzAACDEEILLNOORRSTUUYZ';

    String result = lower;
    for (int i = 0; i < from.length; i++) {
      result = result.replaceAll(from[i], to[i].toLowerCase());
    }
    return result;
  }

  // -----------------------------
  // Helpers – triedenie
  // -----------------------------
  int _compareDocs(Map<String, dynamic> a, Map<String, dynamic> b) {
    switch (_sortOption) {
      case 'Najnovšie':
        return _compareByUploadedAt(a, b, desc: true);
      case 'Najstaršie':
        return _compareByUploadedAt(a, b, desc: false);
      case 'Značka':
        return _compareString((a['brand'] as String?) ?? '', (b['brand'] as String?) ?? '');
      case 'Farba':
        final ca = _normalizeList(a['color']);
        final cb = _normalizeList(b['color']);
        final firstA = ca.isNotEmpty ? ca.first : '';
        final firstB = cb.isNotEmpty ? cb.first : '';
        return _compareString(firstA, firstB);
      case 'Najčastejšie nosené':
        final wa = (a['wearCount'] is int) ? a['wearCount'] as int : 0;
        final wb = (b['wearCount'] is int) ? b['wearCount'] as int : 0;
        return wb.compareTo(wa);
      default:
        return 0;
    }
  }

  int _compareByUploadedAt(Map<String, dynamic> a, Map<String, dynamic> b, {required bool desc}) {
    final ta = a['uploadedAt'];
    final tb = b['uploadedAt'];

    DateTime da = DateTime.fromMillisecondsSinceEpoch(0);
    DateTime db = DateTime.fromMillisecondsSinceEpoch(0);

    if (ta is Timestamp) da = ta.toDate();
    if (tb is Timestamp) db = tb.toDate();

    final cmp = da.compareTo(db);
    return desc ? -cmp : cmp;
  }

  int _compareString(String a, String b) {
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  // -----------------------------
  // Tichý fallback mapping (bez "Nezaradené")
  // -----------------------------
  Map<String, dynamic> _normalizeKeysForDisplay(Map<String, dynamic> raw) {
    final data = Map<String, dynamic>.from(raw);

    final String? mainGroup = data['mainGroup'] as String?;
    final String? categoryKey = data['categoryKey'] as String?;
    final String? subCategoryKey = data['subCategoryKey'] as String?;

    if (mainGroup != null &&
        categoryKey != null &&
        subCategoryKey != null &&
        mainCategoryGroups.containsKey(mainGroup)) {
      data['mainGroupLabel'] =
          (data['mainGroupLabel'] as String?) ?? (mainCategoryGroups[mainGroup] ?? mainGroup);
      data['categoryLabel'] =
          (data['categoryLabel'] as String?) ?? (categoryLabels[categoryKey] ?? categoryKey);
      data['subCategoryLabel'] = (data['subCategoryLabel'] as String?) ??
          (subCategoryLabels[subCategoryKey] ?? subCategoryKey);
      return data;
    }

    final String? categoryLabel = data['categoryLabel'] as String?;
    final String? subLabel = data['subCategoryLabel'] as String?;
    final String? mainLabel = data['mainGroupLabel'] as String?;

    String? mgKey;
    if (mainLabel != null && mainLabel.isNotEmpty) {
      mgKey = mainCategoryGroups.entries
          .firstWhere(
            (e) => _normalizeText(e.value) == _normalizeText(mainLabel),
        orElse: () => const MapEntry('', ''),
      )
          .key;
      if (mgKey.isEmpty) mgKey = null;
    }

    String? ck;
    if (categoryLabel != null && categoryLabel.isNotEmpty) {
      ck = categoryLabels.entries
          .firstWhere(
            (e) => _normalizeText(e.value) == _normalizeText(categoryLabel),
        orElse: () => const MapEntry('', ''),
      )
          .key;
      if (ck.isEmpty) ck = null;
    }

    String? sk;
    if (subLabel != null && subLabel.isNotEmpty) {
      sk = subCategoryLabels.entries
          .firstWhere(
            (e) => _normalizeText(e.value) == _normalizeText(subLabel),
        orElse: () => const MapEntry('', ''),
      )
          .key;
      if (sk.isEmpty) sk = null;
    }

    final String legacyMain = (data['mainCategory'] as String?) ?? '';
    final String legacyCat = (data['category'] as String?) ?? '';

    mgKey ??= _legacyMainToNewMainGroup(legacyMain);

    if (mgKey != null && mgKey.isNotEmpty) {
      final mapped = _legacyCategoryToNewKeys(legacyCat, mgKey);
      ck ??= mapped['categoryKey'];
      sk ??= mapped['subCategoryKey'];
    }

    if (mgKey != null && mgKey.isNotEmpty) {
      final cats = categoryTree[mgKey] ?? [];
      ck ??= cats.isNotEmpty ? cats.first : null;

      if (ck != null) {
        final subs = subCategoryTree[ck] ?? [];
        sk ??= subs.isNotEmpty ? subs.first : null;
      }
    }

    if (mgKey != null) data['mainGroup'] = mgKey;
    if (ck != null) data['categoryKey'] = ck;
    if (sk != null) data['subCategoryKey'] = sk;

    if (mgKey != null) data['mainGroupLabel'] = mainCategoryGroups[mgKey] ?? mgKey;
    if (ck != null) data['categoryLabel'] = categoryLabels[ck] ?? ck;
    if (sk != null) data['subCategoryLabel'] = subCategoryLabels[sk] ?? sk;

    return data;
  }

  String? _legacyMainToNewMainGroup(String legacyMain) {
    final lm = _normalizeText(legacyMain);
    if (lm == _normalizeText('Vrch') || lm == _normalizeText('Spodok')) return 'oblecenie';
    if (lm == _normalizeText('Obuv')) return 'obuv';
    if (lm == _normalizeText('Doplnky')) return 'doplnky';
    return null;
  }

  Map<String, String?> _legacyCategoryToNewKeys(String legacyCategory, String mainGroup) {
    final lc = _normalizeText(legacyCategory);

    if (mainGroup == 'oblecenie') {
      if (lc.contains(_normalizeText('tričko')) || lc.contains(_normalizeText('tricko')) || lc.contains('tshirt')) {
        return {'categoryKey': 'tricka_topy', 'subCategoryKey': 'tricko'};
      }
      if (lc.contains(_normalizeText('košeľa')) || lc.contains(_normalizeText('kosela')) || lc.contains('shirt')) {
        return {'categoryKey': 'kosele', 'subCategoryKey': 'kosela_klasicka'};
      }
      if (lc.contains(_normalizeText('mikina')) || lc.contains('hoodie') || lc.contains('sweat')) {
        return {'categoryKey': 'mikiny', 'subCategoryKey': 'mikina_klasicka'};
      }
      if (lc.contains(_normalizeText('sveter')) ||
          lc.contains(_normalizeText('svetre')) ||
          lc.contains(_normalizeText('rolák')) ||
          lc.contains(_normalizeText('rolak'))) {
        return {'categoryKey': 'svetre', 'subCategoryKey': 'sveter_rolak'};
      }
      if (lc.contains(_normalizeText('bunda')) ||
          lc.contains(_normalizeText('kabát')) ||
          lc.contains(_normalizeText('kabat')) ||
          lc.contains('jacket') ||
          lc.contains('coat')) {
        return {'categoryKey': 'bundy_kabaty', 'subCategoryKey': 'bunda_prechodna'};
      }
      if (lc.contains(_normalizeText('nohavice')) || lc.contains(_normalizeText('rifle')) || lc.contains('jeans') || lc.contains('pants')) {
        return {'categoryKey': 'nohavice', 'subCategoryKey': 'rifle'};
      }
      if (lc.contains(_normalizeText('šortky')) ||
          lc.contains(_normalizeText('sortky')) ||
          lc.contains(_normalizeText('kraťasy')) ||
          lc.contains(_normalizeText('kratasy')) ||
          lc.contains(_normalizeText('sukňa')) ||
          lc.contains(_normalizeText('sukna'))) {
        return {'categoryKey': 'sortky_sukne', 'subCategoryKey': 'sortky'};
      }
      if (lc.contains(_normalizeText('šaty')) || lc.contains(_normalizeText('saty')) || lc.contains('dress') || lc.contains(_normalizeText('overal'))) {
        return {'categoryKey': 'saty_overaly', 'subCategoryKey': 'saty_kratke'};
      }
      return {'categoryKey': null, 'subCategoryKey': null};
    }

    if (mainGroup == 'obuv') {
      if (lc.contains(_normalizeText('tenisky')) || lc.contains('sneaker')) {
        return {'categoryKey': 'tenisky', 'subCategoryKey': 'tenisky_fashion'};
      }
      if (lc.contains(_normalizeText('čižmy')) || lc.contains(_normalizeText('cizmy')) || lc.contains('boots')) {
        return {'categoryKey': 'cizmy', 'subCategoryKey': 'cizmy_clenkove'};
      }
      if (lc.contains(_normalizeText('sandále')) || lc.contains(_normalizeText('sandale')) || lc.contains('sandal')) {
        return {'categoryKey': 'letna_obuv', 'subCategoryKey': 'sandale'};
      }
      return {'categoryKey': null, 'subCategoryKey': null};
    }

    if (mainGroup == 'doplnky') {
      if (lc.contains(_normalizeText('čiapka')) || lc.contains(_normalizeText('ciapka')) || lc.contains('beanie')) {
        return {'categoryKey': 'dopl_hlava', 'subCategoryKey': 'ciapka'};
      }
      if (lc.contains(_normalizeText('šál')) || lc.contains(_normalizeText('sal')) || lc.contains('scarf')) {
        return {'categoryKey': 'dopl_saly_rukavice', 'subCategoryKey': 'sal'};
      }
      if (lc.contains(_normalizeText('rukavice')) || lc.contains('gloves')) {
        return {'categoryKey': 'dopl_saly_rukavice', 'subCategoryKey': 'rukavice'};
      }
      if (lc.contains(_normalizeText('opasok')) || lc.contains('belt')) {
        return {'categoryKey': 'dopl_ostatne', 'subCategoryKey': 'opasok'};
      }
      if (lc.contains(_normalizeText('okuliare')) || lc.contains('glasses')) {
        return {'categoryKey': 'dopl_ostatne', 'subCategoryKey': 'slnecne_okuliare'};
      }
      return {'categoryKey': null, 'subCategoryKey': null};
    }

    if (mainGroup == 'sport') {
      return {'categoryKey': 'sport_oblecenie', 'subCategoryKey': 'sport_tricko'};
    }

    return {'categoryKey': null, 'subCategoryKey': null};
  }

  // -----------------------------
  // UI
  // -----------------------------
  @override
  Widget build(BuildContext context) {
    if (_authUser == null) {
      return const Scaffold(
        body: Center(child: Text('Pre zobrazenie šatníka sa musíte prihlásiť.')),
      );
    }

    final mainGroupKeys = <String>[
      'oblecenie',
      'obuv',
      'doplnky',
      'sport',
    ].where((k) => mainCategoryGroups.containsKey(k)).toList();

    return DefaultTabController(
      length: mainGroupKeys.length,
      child: Scaffold(
        backgroundColor: _WardrobeLuxuryPalette.bgBottom,
        body: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _WardrobeLuxuryPalette.bgTop,
                      _WardrobeLuxuryPalette.bgMid,
                      _WardrobeLuxuryPalette.bgBottom,
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-0.1, -0.9),
                      radius: 1.08,
                      colors: [
                        _WardrobeLuxuryPalette.accentGlow.withOpacity(0.22),
                        _WardrobeLuxuryPalette.accentGlow.withOpacity(0.10),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.28, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF0B0B0D).withOpacity(0.32),
                      Colors.transparent,
                      const Color(0xFF09090A).withOpacity(0.24),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  // ✅ glass appbar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: _GlassAppBar(
                      title: 'Môj šatník',
                      onInfo: () => _showProcessingLegend(context),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: _WardrobePrimaryButton(
                      text: 'Analýza šatníka',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const WardrobeAnalysisScreen(),
                          ),
                        );
                      },
                    ),
                  ),

// ✅ tabs in glass pill
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: _GlassTabs(
                      tabs: mainGroupKeys.map((k) => mainCategoryGroups[k] ?? k).toList(),
                    ),
                  ),

                  Expanded(
                    child: TabBarView(
                      children: mainGroupKeys.map((mainGroupKey) {
                        return _WardrobeTabBody(
                          firestore: _firestore,
                          authUid: _authUser!.uid,
                          mainGroupKey: mainGroupKey,
                          sortOption: _sortOption,
                          sortOptions: _sortOptions,
                          searchController: _searchController,
                          searchQuery: _searchQuery,
                          onSearchChanged: (v) => setState(() => _searchQuery = v),
                          onSortChanged: (v) => setState(() => _sortOption = v),
                          normalizeKeysForDisplay: _normalizeKeysForDisplay,
                          matchesSearch: _matchesSearch,
                          compareDocs: _compareDocs,
                          onDeleteItem: (item) => _confirmAndDelete(context, item),
                        );
                      }).toList(),
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

/// ============================================================================
/// Tab body (search + sort + content)
/// ============================================================================
class _WardrobeTabBody extends StatelessWidget {
  final FirebaseFirestore firestore;
  final String authUid;
  final String mainGroupKey;

  final String sortOption;
  final List<String> sortOptions;

  final TextEditingController searchController;
  final String searchQuery;

  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSortChanged;

  final Map<String, dynamic> Function(Map<String, dynamic> raw) normalizeKeysForDisplay;
  final bool Function(Map<String, dynamic> data, String query) matchesSearch;
  final int Function(Map<String, dynamic> a, Map<String, dynamic> b) compareDocs;

  final void Function(Map<String, dynamic> item) onDeleteItem;

  const _WardrobeTabBody({
    required this.firestore,
    required this.authUid,
    required this.mainGroupKey,
    required this.sortOption,
    required this.sortOptions,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onSortChanged,
    required this.normalizeKeysForDisplay,
    required this.matchesSearch,
    required this.compareDocs,
    required this.onDeleteItem,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('users')
          .doc(authUid)
          .collection('wardrobe')
          .where('mainGroup', isEqualTo: mainGroupKey)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Nastala chyba pri načítaní šatníka.',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        final normalized = <Map<String, dynamic>>[];
        for (final d in docs) {
          final m = d.data() as Map<String, dynamic>;
          final data = normalizeKeysForDisplay(m);
          data['__id'] = d.id;

          if (searchQuery.trim().isNotEmpty &&
              !matchesSearch(data, searchQuery.trim())) {
            continue;
          }

          normalized.add(data);
        }

        normalized.sort((a, b) => compareDocs(a, b));

        final Map<String, List<Map<String, dynamic>>> byCategory = {};
        for (final item in normalized) {
          final ck = (item['categoryKey'] as String?) ?? '';
          if (ck.isEmpty) continue;
          byCategory.putIfAbsent(ck, () => []);
          byCategory[ck]!.add(item);
        }

        final categoryKeysInOrder = categoryTree[mainGroupKey] ?? [];
        final totalCount =
        byCategory.values.fold<int>(0, (p, e) => p + e.length);

        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
          children: [
            _WardrobeCompactControls(
              searchQuery: searchQuery,
              sortValue: sortOption,
              sortOptions: sortOptions,
              searchController: searchController,
              onSearchChanged: onSearchChanged,
              onSortChanged: onSortChanged,
            ),
            const SizedBox(height: 12),

            if (totalCount == 0)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(
                  child: Text(
                    'Zatiaľ tu nemáš žiadne kúsky.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              )
            else
              for (final ck in categoryKeysInOrder)
                if ((byCategory[ck] ?? []).isNotEmpty)
                  _CategorySectionGlass(
                    title: categoryLabels[ck] ?? ck,
                    items: byCategory[ck]!,
                    onOpenAll: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WardrobeCategoryScreen(
                            mainGroupKey: mainGroupKey,
                            categoryKey: ck,
                          ),
                        ),
                      );
                    },
                    onDeleteItem: onDeleteItem,
                  ),
          ],
        );
      },
    );
  }
}

/// ============================================================================
/// GLASS UI pieces
/// ============================================================================
class _GlassAppBar extends StatelessWidget {
  final String title;
  final VoidCallback onInfo;

  const _GlassAppBar({required this.title, required this.onInfo});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(color: Colors.white.withOpacity(0.10)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: onInfo,
                tooltip: 'Čo znamená ten kruh?',
                icon: const Icon(Icons.info_outline, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassTabs extends StatelessWidget {
  final List<String> tabs;
  const _GlassTabs({required this.tabs});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.25),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: TabBar(
            isScrollable: true,
            indicator: const UnderlineTabIndicator(
              borderSide: BorderSide(
                color: Colors.transparent,
                width: 0,
              ),
            ),
            labelColor: _WardrobeLuxuryPalette.accent,
            unselectedLabelColor: Colors.white70,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
            dividerColor: Colors.transparent,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            tabs: tabs.map((t) => Tab(text: t)).toList(),
          ),
        ),
      ),
    );
  }}

class _GlassSearchAndSort extends StatelessWidget {
  final TextEditingController controller;
  final String hint;

  final String sortValue;
  final List<String> sortOptions;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSortChanged;

  const _GlassSearchAndSort({
    required this.controller,
    required this.hint,
    required this.sortValue,
    required this.sortOptions,
    required this.onSearchChanged,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: Column(
            children: [
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white70,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  hintText: hint,
                  hintStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.black.withOpacity(0.28),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: onSearchChanged,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.sort, color: Colors.white60, size: 18),
                  const SizedBox(width: 8),
                  const Text('Triediť:', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  _GlassDropdown(
                    value: sortValue,
                    items: sortOptions,
                    onChanged: onSortChanged,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  const _GlassDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(color: Colors.white.withOpacity(0.10)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          dropdownColor: const Color(0xFF1A1A1A),
          iconEnabledColor: Colors.white70,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          items: items.map((opt) {
            return DropdownMenuItem<String>(value: opt, child: Text(opt));
          }).toList(),
          onChanged: (v) {
            if (v == null) return;
            onChanged(v);
          },
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}
/// ============================================================================
/// CATEGORY SECTION (glass) + preview HORIZONTAL (3 vedľa seba)
/// ============================================================================
class _CategorySectionGlass extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> items;
  final VoidCallback onOpenAll;
  final void Function(Map<String, dynamic> item) onDeleteItem;

  const _CategorySectionGlass({
    required this.title,
    required this.items,
    required this.onOpenAll,
    required this.onDeleteItem,
  });

  List<String> _normalizeList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.map((e) => e.toString()).toList();
    if (value is String && value.isNotEmpty) return [value];
    return [];
  }

  String _statusFromProcessing(Map<String, dynamic> data, String key) {
    final p = data['processing'];
    if (p is Map) {
      final m = p.cast<String, dynamic>();
      final v = (m[key] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    final dotted = data['processing.$key'];
    if (dotted != null) {
      final v = dotted.toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  bool _isUrlFilled(String? s) => s != null && s.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    // koľko zobrazíme v preview (scroll do strany)
    final preview = items.take(12).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white10),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.07),
                  Colors.white.withOpacity(0.03),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.40),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: _WardrobeLuxuryPalette.accent,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: onOpenAll,
                      child: Text(
                        'Zobraziť všetko (${items.length})',
                        style: TextStyle(
                          color: _WardrobeLuxuryPalette.accent.withOpacity(0.88),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // ✅ 3 vedľa seba + horizontal scroll
                LayoutBuilder(
                  builder: (context, c) {
                    // aby vyšli 3 tiles vedľa seba s medzerami
                    const gap = 12.0;
                    final available = c.maxWidth;
                    final tileWidth = (available - gap * 2) / 3; // 3 tiles => 2 medzery
                    final tileHeight = tileWidth / 0.92; // približne rovnaký pomer ako v gride

                    return SizedBox(
                      height: tileHeight,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: preview.length,
                        separatorBuilder: (_, __) => const SizedBox(width: gap),
                        itemBuilder: (context, index) {
                          final data = preview[index];

                          // IMAGE priority
                          final String? productImage = data['productImageUrl'] as String?;
                          final String? cleanImage = data['cleanImageUrl'] as String?;
                          final String? cutoutImage = data['cutoutImageUrl'] as String?;
                          final String? originalImage = data['originalImageUrl'] as String?;
                          final String? legacyImage = data['imageUrl'] as String?;

                          final imageUrl = (_isUrlFilled(productImage))
                              ? productImage!
                              : (_isUrlFilled(cleanImage))
                              ? cleanImage!
                              : (_isUrlFilled(cutoutImage))
                              ? cutoutImage!
                              : (_isUrlFilled(originalImage))
                              ? originalImage!
                              : (legacyImage ?? '');

                          // Spinner logic
                          final cutoutStatus = _statusFromProcessing(data, 'cutout');
                          final productStatus = _statusFromProcessing(data, 'product');

                          final bool hasCutoutOrClean = _isUrlFilled(cleanImage) || _isUrlFilled(cutoutImage);
                          final bool hasProduct = _isUrlFilled(productImage);

                          final bool cutoutInProgress =
                              !hasCutoutOrClean && (cutoutStatus == 'queued' || cutoutStatus == 'running');

                          final bool productInProgress =
                              hasCutoutOrClean && !hasProduct && (productStatus == 'queued' || productStatus == 'running');

                          final bool showSpinner = cutoutInProgress || productInProgress;
                          final bool showError = (!showSpinner) && (cutoutStatus == 'error' || productStatus == 'error');

                          final name = (data['name'] as String?)?.trim().isNotEmpty == true
                              ? data['name'] as String
                              : (data['subCategoryLabel'] as String?) ?? 'Neznámy kúsok';

                          final categoryLine = (data['categoryLabel'] as String?) ?? '';
                          final seasons = _normalizeList(data['season']);
                          String subline = '';
                          if (categoryLine.isNotEmpty && seasons.isNotEmpty) {
                            subline = '$categoryLine • ${seasons.join(', ')}';
                          } else if (categoryLine.isNotEmpty) {
                            subline = categoryLine;
                          } else if (seasons.isNotEmpty) {
                            subline = seasons.join(', ');
                          }

                          return SizedBox(
                            width: tileWidth,
                            child: _WardrobeTileGlass(
                              data: data,
                              imageUrl: imageUrl,
                              title: name,
                              subtitle: subline,
                              showSpinner: showSpinner,
                              showError: showError,
                              onDelete: () => onDeleteItem(data),
                              onOpenDetail: () {
                                final id = data['__id'] as String?;
                                if (id == null) return;

                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ClothingDetailScreen(
                                      clothingItemId: id,
                                      clothingItemData: data,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ============================================================================
/// Glass tile card used both in preview and category screen
/// ============================================================================
class _WardrobeTileGlass extends StatelessWidget {
  final Map<String, dynamic> data;
  final String imageUrl;
  final String title;
  final String subtitle;
  final bool showSpinner;
  final bool showError;
  final VoidCallback onDelete;
  final VoidCallback onOpenDetail;

  const _WardrobeTileGlass({
    required this.data,
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.showSpinner,
    required this.showError,
    required this.onDelete,
    required this.onOpenDetail,
  });

  Widget _topLeftSpinner() {
    return const Positioned(
      top: 10,
      left: 10,
      child: SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 1.6,
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4A6CF7)),
        ),
      ),
    );
  }

  Widget _topRightDeleteButton() {
    return Positioned(
      top: 6,
      right: 6,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDelete,
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.30),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white10),
          ),
          child: const Icon(
            Icons.delete_outline,
            size: 16,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpenDetail,
      borderRadius: BorderRadius.circular(18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withOpacity(0.12),
                  Colors.white.withOpacity(0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.35),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.35),
                                  blurRadius: 25,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: imageUrl.trim().isNotEmpty
                              ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                          )
                              : Container(
                            color: Colors.white.withOpacity(0.06),
                            child: const Center(
                              child: Icon(
                                Icons.image_not_supported,
                                size: 42,
                                color: Colors.white38,
                              ),
                            ),
                          ),
                        ),
                        if (showSpinner) _topLeftSpinner(),
                        _topRightDeleteButton(),
                        if (showError)
                          const Positioned(
                            bottom: 8,
                            right: 8,
                            child: Icon(Icons.error_outline, size: 16, color: Colors.redAccent),
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 60,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.55),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(9, 8, 9, 3),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                if (subtitle.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(9, 0, 9, 8),
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ============================================================================
/// Screen: všetky kúsky v jednej kategórii (podkategórie + filtre)
/// ============================================================================
class WardrobeCategoryScreen extends StatefulWidget {
  final String mainGroupKey;
  final String categoryKey;

  const WardrobeCategoryScreen({
    Key? key,
    required this.mainGroupKey,
    required this.categoryKey,
  }) : super(key: key);

  @override
  State<WardrobeCategoryScreen> createState() => _WardrobeCategoryScreenState();
}

class _WardrobeCategoryScreenState extends State<WardrobeCategoryScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _authUser = FirebaseAuth.instance.currentUser;

  String? _selectedSubKey;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  String _sortOption = 'Najnovšie';
  final List<String> _sortOptions = const [
    'Najnovšie',
    'Najstaršie',
    'Značka',
    'Farba',
    'Najčastejšie nosené',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _confirmAndDelete(BuildContext context, Map<String, dynamic> data) async {
    if (_authUser == null) return;

    final id = data['__id'] as String?;
    if (id == null || id.isEmpty) return;

    final name = (data['name'] as String?)?.trim().isNotEmpty == true
        ? (data['name'] as String)
        : (data['subCategoryLabel'] as String?) ?? 'Tento kúsok';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vymazať oblečenie?'),
        content: Text('Naozaj chceš vymazať „$name“ zo šatníka?\n\nToto sa nedá vrátiť späť.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Zrušiť'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Vymazať'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _firestore
          .collection('users')
          .doc(_authUser!.uid)
          .collection('wardrobe')
          .doc(id)
          .delete();

      final urls = <String?>[
        data['productImageUrl'] as String?,
        data['cleanImageUrl'] as String?,
        data['cutoutImageUrl'] as String?,
        data['originalImageUrl'] as String?,
        data['imageUrl'] as String?,
      ];
      for (final u in urls) {
        await _tryDeleteStorageUrl(u);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kúsok bol vymazaný.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nepodarilo sa vymazať kúsok: $e')),
      );
    }
  }

  Future<void> _tryDeleteStorageUrl(String? url) async {
    final u = url?.trim();
    if (u == null || u.isEmpty) return;

    try {
      final ref = FirebaseStorage.instance.refFromURL(u);
      await ref.delete();
    } catch (_) {}
  }

  List<String> _normalizeList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.map((e) => e.toString()).toList();
    if (value is String && value.isNotEmpty) return [value];
    return [];
  }

  String _normalizeText(String input) {
    final lower = input.toLowerCase();

    const from = 'áäčďéěíĺľňóôŕřšťúůýžÁÄČĎÉĚÍĹĽŇÓÔŔŘŠŤÚŮÝŽ';
    const to = 'aacdeeillnoorrstuuyzAACDEEILLNOORRSTUUYZ';

    String result = lower;
    for (int i = 0; i < from.length; i++) {
      result = result.replaceAll(from[i], to[i].toLowerCase());
    }
    return result;
  }

  bool _matchesSearch(Map<String, dynamic> data, String query) {
    final q = _normalizeText(query);
    if (q.isEmpty) return true;

    final buffer = StringBuffer();
    void addField(dynamic v) {
      if (v == null) return;
      if (v is List) {
        buffer.write(' ');
        buffer.write(v.join(' '));
      } else {
        buffer.write(' ');
        buffer.write(v.toString());
      }
    }

    addField(data['name']);
    addField(data['brand']);
    addField(data['categoryLabel']);
    addField(data['subCategoryLabel']);
    addField(data['color']);
    addField(data['style']);
    addField(data['pattern']);
    addField(data['season']);

    return _normalizeText(buffer.toString()).contains(q);
  }

  int _compareDocs(Map<String, dynamic> a, Map<String, dynamic> b) {
    switch (_sortOption) {
      case 'Najnovšie':
        return _compareByUploadedAt(a, b, desc: true);
      case 'Najstaršie':
        return _compareByUploadedAt(a, b, desc: false);
      case 'Značka':
        return ((a['brand'] as String?) ?? '').toLowerCase().compareTo(((b['brand'] as String?) ?? '').toLowerCase());
      case 'Farba':
        final ca = _normalizeList(a['color']);
        final cb = _normalizeList(b['color']);
        final firstA = ca.isNotEmpty ? ca.first : '';
        final firstB = cb.isNotEmpty ? cb.first : '';
        return firstA.toLowerCase().compareTo(firstB.toLowerCase());
      case 'Najčastejšie nosené':
        final wa = (a['wearCount'] is int) ? a['wearCount'] as int : 0;
        final wb = (b['wearCount'] is int) ? b['wearCount'] as int : 0;
        return wb.compareTo(wa);
      default:
        return 0;
    }
  }

  int _compareByUploadedAt(Map<String, dynamic> a, Map<String, dynamic> b, {required bool desc}) {
    final ta = a['uploadedAt'];
    final tb = b['uploadedAt'];

    DateTime da = DateTime.fromMillisecondsSinceEpoch(0);
    DateTime db = DateTime.fromMillisecondsSinceEpoch(0);

    if (ta is Timestamp) da = ta.toDate();
    if (tb is Timestamp) db = tb.toDate();

    final cmp = da.compareTo(db);
    return desc ? -cmp : cmp;
  }

  String _statusFromProcessing(Map<String, dynamic> data, String key) {
    final p = data['processing'];
    if (p is Map) {
      final m = p.cast<String, dynamic>();
      final v = (m[key] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    final dotted = data['processing.$key'];
    if (dotted != null) {
      final v = dotted.toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  bool _isUrlFilled(String? s) => s != null && s.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final title = categoryLabels[widget.categoryKey] ?? widget.categoryKey;
    final subKeys = subCategoryTree[widget.categoryKey] ?? [];

    if (_authUser == null) {
      return const Scaffold(
        body: Center(child: Text('Pre zobrazenie šatníka sa musíte prihlásiť.')),
      );
    }

    return Scaffold(
      backgroundColor: _WardrobeLuxuryPalette.bgBottom,
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _WardrobeLuxuryPalette.bgTop,
                    _WardrobeLuxuryPalette.bgMid,
                    _WardrobeLuxuryPalette.bgBottom,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.1, -0.9),
                    radius: 1.08,
                    colors: [
                      _WardrobeLuxuryPalette.accentGlow.withOpacity(0.22),
                      _WardrobeLuxuryPalette.accentGlow.withOpacity(0.10),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.28, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x520B0B0D),
                    Colors.transparent,
                    Color(0x3D09090A),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: _GlassSearchAndSort(
                    controller: _searchController,
                    hint: 'Hľadať v kategórii…',
                    sortValue: _sortOption,
                    sortOptions: _sortOptions,
                    onSearchChanged: (v) => setState(() => _searchQuery = v),
                    onSortChanged: (v) => setState(() => _sortOption = v),
                  ),
                ),
                if (subKeys.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: _GlassChipsRow(
                      children: [
                        _GlassChoiceChip(
                          label: 'Všetko',
                          selected: _selectedSubKey == null,
                          onTap: () => setState(() => _selectedSubKey = null),
                        ),
                        ...subKeys.map((sk) {
                          final label = subCategoryLabels[sk] ?? sk;
                          return _GlassChoiceChip(
                            label: label,
                            selected: _selectedSubKey == sk,
                            onTap: () => setState(() => _selectedSubKey = sk),
                          );
                        }),
                      ],
                    ),
                  ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('users')
                        .doc(_authUser!.uid)
                        .collection('wardrobe')
                        .where('mainGroup', isEqualTo: widget.mainGroupKey)
                        .where('categoryKey', isEqualTo: widget.categoryKey)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      }
                      if (snapshot.hasError) {
                        return const Center(
                          child: Text('Chyba pri načítaní položiek.', style: TextStyle(color: Colors.white70)),
                        );
                      }

                      var items = (snapshot.data?.docs ?? []).map((d) {
                        final m = d.data() as Map<String, dynamic>;
                        m['__id'] = d.id;
                        return m;
                      }).toList();

                      if (_selectedSubKey != null) {
                        items = items.where((m) => (m['subCategoryKey'] as String?) == _selectedSubKey).toList();
                      }

                      if (_searchQuery.trim().isNotEmpty) {
                        items = items.where((m) => _matchesSearch(m, _searchQuery.trim())).toList();
                      }

                      items.sort((a, b) => _compareDocs(a, b));

                      if (items.isEmpty) {
                        return const Center(
                          child: Text('V tejto kategórii zatiaľ nič nemáš.', style: TextStyle(color: Colors.white70)),
                        );
                      }

                      return GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.78,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final data = items[index];

                          final String? productImage = data['productImageUrl'] as String?;
                          final String? cleanImage = data['cleanImageUrl'] as String?;
                          final String? cutoutImage = data['cutoutImageUrl'] as String?;
                          final String? originalImage = data['originalImageUrl'] as String?;
                          final String? legacyImage = data['imageUrl'] as String?;

                          final imageUrl = (_isUrlFilled(productImage))
                              ? productImage!
                              : (_isUrlFilled(cleanImage))
                              ? cleanImage!
                              : (_isUrlFilled(cutoutImage))
                              ? cutoutImage!
                              : (_isUrlFilled(originalImage))
                              ? originalImage!
                              : (legacyImage ?? '');

                          final cutoutStatus = _statusFromProcessing(data, 'cutout');
                          final productStatus = _statusFromProcessing(data, 'product');

                          final bool hasCutoutOrClean = _isUrlFilled(cleanImage) || _isUrlFilled(cutoutImage);
                          final bool hasProduct = _isUrlFilled(productImage);

                          final bool cutoutInProgress =
                              !hasCutoutOrClean && (cutoutStatus == 'queued' || cutoutStatus == 'running');

                          final bool productInProgress =
                              hasCutoutOrClean && !hasProduct && (productStatus == 'queued' || productStatus == 'running');

                          final bool showSpinner = cutoutInProgress || productInProgress;
                          final bool showError = (!showSpinner) && (cutoutStatus == 'error' || productStatus == 'error');

                          final name = (data['name'] as String?)?.trim().isNotEmpty == true
                              ? data['name'] as String
                              : (data['subCategoryLabel'] as String?) ?? 'Neznámy kúsok';

                          final seasons = _normalizeList(data['season']);
                          final subline = seasons.isNotEmpty ? seasons.join(', ') : '';

                          return _WardrobeTileGlass(
                            data: data,
                            imageUrl: imageUrl,
                            title: name,
                            subtitle: subline,
                            showSpinner: showSpinner,
                            showError: showError,
                            onDelete: () => _confirmAndDelete(context, data),
                            onOpenDetail: () {
                              final id = data['__id'] as String?;
                              if (id == null) return;

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ClothingDetailScreen(
                                    clothingItemId: id,
                                    clothingItemData: data,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ============================================================================
/// Glass chips row + chip
/// ============================================================================
class _GlassChipsRow extends StatelessWidget {
  final List<Widget> children;
  const _GlassChipsRow({required this.children});

  @override
  Widget build(BuildContext context) {
    final spaced = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      spaced.add(children[i]);
      if (i != children.length - 1) {
        spaced.add(const SizedBox(width: 8));
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(color: Colors.white.withOpacity(0.10)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: spaced),
          ),
        ),
      ),
    );
  }
}

class _GlassChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GlassChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected ? Colors.white.withOpacity(0.92) : Colors.white.withOpacity(0.06),
          border: Border.all(color: selected ? Colors.white24 : Colors.white10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
class _WardrobePrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _WardrobePrimaryButton({
    required this.text,
    required this.onTap,
  });

  static const Color _goldTop = Color(0xFFC8A36A);
  static const Color _goldBottom = Color(0xFF9D7C4C);
  static const Color _darkText = Color(0xFF191512);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _goldTop,
              _goldBottom,
            ],
          ),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _goldTop.withOpacity(0.45)),
          boxShadow: [
            BoxShadow(
              color: _goldTop.withOpacity(0.26),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              text,
              style: const TextStyle(
                color: _darkText,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.arrow_forward_ios,
              color: _darkText.withOpacity(0.8),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
class _WardrobeCompactControls extends StatelessWidget {
  final String searchQuery;
  final String sortValue;
  final List<String> sortOptions;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSortChanged;

  const _WardrobeCompactControls({
    required this.searchQuery,
    required this.sortValue,
    required this.sortOptions,
    required this.searchController,
    required this.onSearchChanged,
    required this.onSortChanged,
  });

  void _openSearchSheet(BuildContext context) {
    searchController.text = searchQuery;
    searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: searchController.text.length),
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            14,
            16,
            MediaQuery.of(sheetContext).viewInsets.bottom + 18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                cursorColor: _WardrobeLuxuryPalette.accent,
                decoration: InputDecoration(
                  hintText: 'Hľadať v šatníku...',
                  hintStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: onSearchChanged,
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _openSortSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                for (final option in sortOptions) ...[
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    tileColor: option == sortValue
                        ? _WardrobeLuxuryPalette.accent.withOpacity(0.12)
                        : Colors.transparent,
                    title: Text(
                      option,
                      style: TextStyle(
                        color: option == sortValue
                            ? _WardrobeLuxuryPalette.accent
                            : Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () {
                      onSortChanged(option);
                      Navigator.pop(sheetContext);
                    },
                  ),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final label =
    searchQuery.trim().isEmpty ? 'Hľadať v šatníku...' : searchQuery.trim();

    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => _openSearchSheet(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.24),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Colors.white70, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: searchQuery.trim().isEmpty
                            ? Colors.white54
                            : Colors.white,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _openSortSheet(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.24),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withOpacity(0.10)),
            ),
            child: Row(
              children: [
                Text(
                  sortValue,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.expand_more, color: Colors.white70, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }
}