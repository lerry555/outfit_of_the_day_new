import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../domain/wardrobe_v2/wardrobe_item_v2.dart';
import '../domain/wardrobe_v2/wardrobe_v2_adapters.dart';
import '../domain/wardrobe_v2/wardrobe_set_v2.dart';
import '../Services/wardrobe_set_repository.dart';

import 'package:outfitofTheDay/constants/app_constants.dart';
import 'package:outfitofTheDay/screens/clothing_detail_screen.dart';
import 'package:outfitofTheDay/data/clothing_knowledge_base.dart';
import 'package:outfitofTheDay/utils/wardrobe_image_processing.dart';
import 'package:outfitofTheDay/utils/wardrobe_image_url_priority.dart';
import 'package:outfitofTheDay/utils/wardrobe_list_utils.dart';
import 'package:outfitofTheDay/widgets/wardrobe_processing_banner.dart';
import 'package:outfitofTheDay/widgets/wardrobe_processing_spinner.dart';

bool _wardrobeV2MatchesSearch(
  Map<String, dynamic> data,
  String query,
  String Function(String) normalize,
) {
  final q = normalize(query);
  if (q.isEmpty) return true;
  try {
    final item = WardrobeItemV2.fromMap(data);
    final humanLabels = <String>[
      (data['name'] ?? '').toString(),
      (data['brand'] ?? '').toString(),
      (data['categoryLabel'] ?? '').toString(),
      (data['subCategoryLabel'] ?? '').toString(),
    ];
    final searchable = <String>{
      ...WardrobeSearchProjectionV2.tokens(item),
      ...humanLabels,
    }.join(' ');
    return normalize(searchable).contains(q);
  } catch (_) {
    return false;
  }
}

class _WardrobeLuxuryPalette {
  static const Color bgTop = Color(0xFF111111);
  static const Color bgMid = Color(0xFF0C0C0D);
  static const Color bgBottom = Color(0xFF080809);

  static const Color accent = Color(0xFFC8A36A);
  static const Color accentGlow = Color(0x66C8A36A);
}

bool _wardrobeItemBelongsToMainGroup(
  Map<String, dynamic> data,
  String mainGroupKey,
) {
  final direct = (data['mainGroup'] ?? data['mainGroupKey'] ?? '').toString();
  if (direct == mainGroupKey) return true;
  final projected = data['uiProjection'];
  if (projected is Map &&
      (projected['mainCategory'] ?? '').toString() == mainGroupKey) {
    return true;
  }
  final categoryKey = ClothingKnowledgeBase.wardrobeDisplayCategoryKey(data);
  return (categoryTree[mainGroupKey] ?? const <String>[]).contains(categoryKey);
}

String _wardrobeNormalizeText(String input) {
  final lower = input.toLowerCase();

  const from = 'áäčďéěíĺľňóôŕřšťúůýžÁÄČĎÉĚÍĹĽŇÓÔŔŘŠŤÚŮÝŽ';
  const to = 'aacdeeillnoorrstuuyzAACDEEILLNOORRSTUUYZ';

  var result = lower;
  for (var i = 0; i < from.length; i++) {
    result = result.replaceAll(from[i], to[i].toLowerCase());
  }
  return result;
}

String? _legacyMainToNewMainGroup(String legacyMain) {
  final lm = _wardrobeNormalizeText(legacyMain);
  if (lm == _wardrobeNormalizeText('Vrch') ||
      lm == _wardrobeNormalizeText('Spodok')) {
    return 'oblecenie';
  }
  if (lm == _wardrobeNormalizeText('Obuv')) return 'obuv';
  if (lm == _wardrobeNormalizeText('Doplnky')) return 'doplnky';
  return null;
}

Map<String, String?> _legacyCategoryToNewKeys(
  String legacyCategory,
  String mainGroup,
) {
  final lc = _wardrobeNormalizeText(legacyCategory);

  if (mainGroup == 'oblecenie') {
    if (lc.contains(_wardrobeNormalizeText('tričko')) ||
        lc.contains(_wardrobeNormalizeText('tricko')) ||
        lc.contains('tshirt')) {
      return {'categoryKey': 'tricka_topy', 'subCategoryKey': 'tricko'};
    }
    if (lc.contains(_wardrobeNormalizeText('košeľa')) ||
        lc.contains(_wardrobeNormalizeText('kosela')) ||
        lc.contains('shirt')) {
      return {'categoryKey': 'kosele', 'subCategoryKey': 'kosela_klasicka'};
    }
    if (lc.contains(_wardrobeNormalizeText('mikina')) ||
        lc.contains('hoodie') ||
        lc.contains('sweat')) {
      return {'categoryKey': 'mikiny', 'subCategoryKey': 'mikina_klasicka'};
    }
    if (lc.contains(_wardrobeNormalizeText('sveter')) ||
        lc.contains(_wardrobeNormalizeText('svetre')) ||
        lc.contains(_wardrobeNormalizeText('rolák')) ||
        lc.contains(_wardrobeNormalizeText('rolak'))) {
      return {'categoryKey': 'svetre', 'subCategoryKey': 'sveter_rolak'};
    }
    if (lc.contains(_wardrobeNormalizeText('bunda')) ||
        lc.contains(_wardrobeNormalizeText('kabát')) ||
        lc.contains(_wardrobeNormalizeText('kabat')) ||
        lc.contains('jacket') ||
        lc.contains('coat')) {
      return {
        'categoryKey': 'bundy_kabaty',
        'subCategoryKey': 'bunda_prechodna',
      };
    }
    if (lc.contains(_wardrobeNormalizeText('nohavice')) ||
        lc.contains(_wardrobeNormalizeText('rifle')) ||
        lc.contains('jeans') ||
        lc.contains('pants')) {
      return {'categoryKey': 'nohavice_rifle', 'subCategoryKey': 'rifle'};
    }
    if (lc.contains(_wardrobeNormalizeText('šortky')) ||
        lc.contains(_wardrobeNormalizeText('sortky')) ||
        lc.contains(_wardrobeNormalizeText('kraťasy')) ||
        lc.contains(_wardrobeNormalizeText('kratasy')) ||
        lc.contains(_wardrobeNormalizeText('sukňa')) ||
        lc.contains(_wardrobeNormalizeText('sukna'))) {
      return {'categoryKey': 'sortky_sukne', 'subCategoryKey': 'sortky'};
    }
    if (lc.contains(_wardrobeNormalizeText('šaty')) ||
        lc.contains(_wardrobeNormalizeText('saty')) ||
        lc.contains('dress') ||
        lc.contains(_wardrobeNormalizeText('overal'))) {
      return {'categoryKey': 'saty_overaly', 'subCategoryKey': 'saty_kratke'};
    }
    return {'categoryKey': null, 'subCategoryKey': null};
  }

  if (mainGroup == 'obuv') {
    if (lc.contains(_wardrobeNormalizeText('tenisky')) ||
        lc.contains('sneaker')) {
      return {'categoryKey': 'tenisky', 'subCategoryKey': 'tenisky_fashion'};
    }
    if (lc.contains(_wardrobeNormalizeText('čižmy')) ||
        lc.contains(_wardrobeNormalizeText('cizmy')) ||
        lc.contains('boots')) {
      return {'categoryKey': 'cizmy', 'subCategoryKey': 'cizmy_clenkove'};
    }
    if (lc.contains(_wardrobeNormalizeText('sandále')) ||
        lc.contains(_wardrobeNormalizeText('sandale')) ||
        lc.contains('sandal')) {
      return {'categoryKey': 'letna_obuv', 'subCategoryKey': 'sandale'};
    }
    return {'categoryKey': null, 'subCategoryKey': null};
  }

  if (mainGroup == 'doplnky') {
    if (lc.contains(_wardrobeNormalizeText('čiapka')) ||
        lc.contains(_wardrobeNormalizeText('ciapka')) ||
        lc.contains('beanie')) {
      return {'categoryKey': 'dopl_hlava', 'subCategoryKey': 'ciapka'};
    }
    if (lc.contains(_wardrobeNormalizeText('šál')) ||
        lc.contains(_wardrobeNormalizeText('sal')) ||
        lc.contains('scarf')) {
      return {'categoryKey': 'dopl_saly_rukavice', 'subCategoryKey': 'sal'};
    }
    if (lc.contains(_wardrobeNormalizeText('rukavice')) ||
        lc.contains('gloves')) {
      return {
        'categoryKey': 'dopl_saly_rukavice',
        'subCategoryKey': 'rukavice',
      };
    }
    if (lc.contains(_wardrobeNormalizeText('opasok')) || lc.contains('belt')) {
      return {'categoryKey': 'dopl_ostatne', 'subCategoryKey': 'opasok'};
    }
    if (lc.contains(_wardrobeNormalizeText('okuliare')) ||
        lc.contains('glasses')) {
      return {
        'categoryKey': 'dopl_ostatne',
        'subCategoryKey': 'slnecne_okuliare',
      };
    }
    return {'categoryKey': null, 'subCategoryKey': null};
  }

  if (mainGroup == 'sport') {
    return {'categoryKey': 'sport_oblecenie', 'subCategoryKey': 'sport_tricko'};
  }

  return {'categoryKey': null, 'subCategoryKey': null};
}

Map<String, dynamic> normalizeKeysForDisplay(Map<String, dynamic> input) {
  final data = Map<String, dynamic>.from(input);

  final String? mainGroup = data['mainGroup'] as String?;
  final String? categoryKey = data['categoryKey'] as String?;
  final String? subCategoryKey = data['subCategoryKey'] as String?;

  if (mainGroup != null &&
      categoryKey != null &&
      subCategoryKey != null &&
      mainCategoryGroups.containsKey(mainGroup)) {
    data['mainGroupLabel'] =
        (data['mainGroupLabel'] as String?) ??
        (mainCategoryGroups[mainGroup] ?? mainGroup);
    data['categoryLabel'] =
        (data['categoryLabel'] as String?) ??
        (categoryLabels[categoryKey] ?? categoryKey);
    data['subCategoryLabel'] =
        (data['subCategoryLabel'] as String?) ??
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
          (e) =>
              _wardrobeNormalizeText(e.value) ==
              _wardrobeNormalizeText(mainLabel),
          orElse: () => const MapEntry('', ''),
        )
        .key;
    if (mgKey.isEmpty) mgKey = null;
  }

  String? ck;
  if (categoryLabel != null && categoryLabel.isNotEmpty) {
    ck = categoryLabels.entries
        .firstWhere(
          (e) =>
              _wardrobeNormalizeText(e.value) ==
              _wardrobeNormalizeText(categoryLabel),
          orElse: () => const MapEntry('', ''),
        )
        .key;
    if (ck.isEmpty) ck = null;
  }

  String? sk;
  if (subLabel != null && subLabel.isNotEmpty) {
    sk = subCategoryLabels.entries
        .firstWhere(
          (e) =>
              _wardrobeNormalizeText(e.value) ==
              _wardrobeNormalizeText(subLabel),
          orElse: () => const MapEntry('', ''),
        )
        .key;
    if (sk.isEmpty) sk = null;
  }

  final String legacyMain = (data['mainCategory'] as String?) ?? '';
  final String legacyCat = (data['category'] as String?) ?? '';

  var mgKeyResolved = mgKey ?? _legacyMainToNewMainGroup(legacyMain);

  if (mgKeyResolved != null && mgKeyResolved.isNotEmpty) {
    final mapped = _legacyCategoryToNewKeys(legacyCat, mgKeyResolved);
    ck ??= mapped['categoryKey'];
    sk ??= mapped['subCategoryKey'];
  }

  if (mgKeyResolved != null && mgKeyResolved.isNotEmpty) {
    final cats = categoryTree[mgKeyResolved] ?? [];
    ck ??= cats.isNotEmpty ? cats.first : null;

    if (ck != null) {
      final subs = subCategoryTree[ck] ?? [];
      sk ??= subs.isNotEmpty ? subs.first : null;
    }
  }

  if (mgKeyResolved != null) data['mainGroup'] = mgKeyResolved;
  if (ck != null) data['categoryKey'] = ck;
  if (sk != null) data['subCategoryKey'] = sk;

  if (mgKeyResolved != null) {
    data['mainGroupLabel'] = mainCategoryGroups[mgKeyResolved] ?? mgKeyResolved;
  }
  if (ck != null) data['categoryLabel'] = categoryLabels[ck] ?? ck;
  if (sk != null) data['subCategoryLabel'] = subCategoryLabels[sk] ?? sk;

  return data;
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
  Future<void> _confirmAndDelete(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
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
        content: Text(
          'Naozaj chceš vymazať „$name“ zo šatníka?\n\nToto sa nedá vrátiť späť.',
        ),
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
      final membership = data['setMembership'];
      final setId = membership is Map
          ? (membership['setId'] ?? '').toString()
          : '';
      if (setId.isNotEmpty) {
        await WardrobeSetRepository().removeMember(setId, id);
      }
      // 1) Delete Firestore document
      await _firestore
          .collection('users')
          .doc(_authUser.uid)
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Kúsok bol vymazaný.')));
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

  // -----------------------------
  // Helpers – vyhľadávanie (bez diakritiky)
  // -----------------------------
  bool _matchesSearch(Map<String, dynamic> data, String query) {
    return _wardrobeV2MatchesSearch(data, query, _normalizeText);
  }

  String _normalizeText(String input) => _wardrobeNormalizeText(input);

  // -----------------------------
  // Helpers – triedenie
  // -----------------------------
  int _compareDocs(Map<String, dynamic> a, Map<String, dynamic> b) {
    return wardrobeCompareItems(a, b, sortOption: _sortOption);
  }

  // -----------------------------
  // UI
  // -----------------------------
  @override
  Widget build(BuildContext context) {
    if (_authUser == null) {
      return const Scaffold(
        body: Center(
          child: Text('Pre zobrazenie šatníka sa musíte prihlásiť.'),
        ),
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
                      subtitle: 'Tvoje oblečenie pripravené na outfity.',
                    ),
                  ),

                  // ✅ tabs in glass pill
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: _GlassTabs(
                      tabs: mainGroupKeys
                          .map((k) => mainCategoryGroups[k] ?? k)
                          .toList(),
                    ),
                  ),

                  Expanded(
                    child: TabBarView(
                      children: mainGroupKeys.map((mainGroupKey) {
                        return _WardrobeTabBody(
                          firestore: _firestore,
                          authUid: _authUser.uid,
                          mainGroupKey: mainGroupKey,
                          sortOption: _sortOption,
                          sortOptions: _sortOptions,
                          searchController: _searchController,
                          searchQuery: _searchQuery,
                          onSearchChanged: (v) =>
                              setState(() => _searchQuery = v),
                          onSortChanged: (v) => setState(() => _sortOption = v),
                          normalizeKeysForDisplay: normalizeKeysForDisplay,
                          matchesSearch: _matchesSearch,
                          compareDocs: _compareDocs,
                          hasActiveProcessing: wardrobeItemHasActiveProcessing,
                          onDeleteItem: (item) =>
                              _confirmAndDelete(context, item),
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

  final Map<String, dynamic> Function(Map<String, dynamic> raw)
  normalizeKeysForDisplay;
  final bool Function(Map<String, dynamic> data, String query) matchesSearch;
  final int Function(Map<String, dynamic> a, Map<String, dynamic> b)
  compareDocs;
  final bool Function(Map<String, dynamic> item) hasActiveProcessing;

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
    required this.hasActiveProcessing,
    required this.onDeleteItem,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('users')
          .doc(authUid)
          .collection('wardrobe')
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
          final raw = Map<String, dynamic>.from(d.data() as Map);
          final data = normalizeKeysForDisplay(raw);
          data['__id'] = d.id;
          if (!_wardrobeItemBelongsToMainGroup(data, mainGroupKey)) {
            continue;
          }

          if (searchQuery.trim().isNotEmpty &&
              !matchesSearch(data, searchQuery.trim())) {
            continue;
          }

          normalized.add(data);
        }

        normalized.sort((a, b) => compareDocs(a, b));
        final hasAnyProcessing = normalized.any(hasActiveProcessing);

        final Map<String, List<Map<String, dynamic>>> byCategory = {};
        for (final item in normalized) {
          var ck = ClothingKnowledgeBase.wardrobeDisplayCategoryKey(item);
          if (ck.isEmpty) {
            final projected = item['uiProjection'];
            if (projected is Map) {
              ck = (projected['category'] ?? '').toString();
            }
          }
          if (ck.isEmpty) continue;
          byCategory.putIfAbsent(ck, () => []);
          byCategory[ck]!.add(item);
        }
        for (final list in byCategory.values) {
          sortWardrobeItemsNewestFirst(list);
        }

        final categoryKeysInOrder = categoryTree[mainGroupKey] ?? [];
        final totalCount = byCategory.values.fold<int>(
          0,
          (p, e) => p + e.length,
        );
        final visibleCategories = [
          for (final ck in categoryKeysInOrder)
            if ((byCategory[ck] ?? []).isNotEmpty) ck,
        ];
        final headerCount = hasAnyProcessing ? 2 : 1;
        final bodyCount = totalCount == 0 ? 1 : visibleCategories.length;

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
          itemCount: headerCount + bodyCount,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _WardrobeCompactControls(
                searchQuery: searchQuery,
                sortValue: sortOption,
                sortOptions: sortOptions,
                searchController: searchController,
                onSearchChanged: onSearchChanged,
                onSortChanged: onSortChanged,
              );
            }
            if (hasAnyProcessing && index == 1) {
              return const Padding(
                padding: EdgeInsets.only(top: 12),
                child: WardrobeProcessingBanner(),
              );
            }
            final bodyIndex = index - headerCount;
            if (totalCount == 0) {
              return const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(
                  child: Text(
                    'Zatiaľ tu nemáš žiadne kúsky.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              );
            }
            final ck = visibleCategories[bodyIndex];
            return Padding(
              padding: EdgeInsets.only(top: bodyIndex == 0 ? 12 : 0),
              child: _CategorySectionGlass(
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
            );
          },
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
  final String subtitle;

  const _GlassAppBar({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _WardrobeLuxuryPalette.accent.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _WardrobeLuxuryPalette.accent.withOpacity(0.42),
                  ),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.checkroom_rounded,
                  size: 20,
                  color: _WardrobeLuxuryPalette.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
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

class _GlassTabs extends StatelessWidget {
  final List<String> tabs;
  const _GlassTabs({required this.tabs});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.25),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: TabBar(
            isScrollable: true,
            indicator: const UnderlineTabIndicator(
              borderSide: BorderSide(color: Colors.transparent, width: 0),
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
    );
  }
}

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
      child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
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
                  const Text(
                    'Triediť:',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
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
    final preview = items.take(kWardrobeCategoryPreviewTileCount).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
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
                          color: _WardrobeLuxuryPalette.accent.withOpacity(
                            0.88,
                          ),
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
                    final tileWidth =
                        (available - gap * 2) / 3; // 3 tiles => 2 medzery
                    final tileHeight =
                        tileWidth / 0.92; // približne rovnaký pomer ako v gride

                    return SizedBox(
                      height: tileHeight,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: preview.length,
                        separatorBuilder: (_, __) => const SizedBox(width: gap),
                        itemBuilder: (context, index) {
                          final data = preview[index];

                          // Spinner logic
                          final cutoutStatus = _statusFromProcessing(
                            data,
                            'cutout',
                          );
                          final productStatus = _statusFromProcessing(
                            data,
                            'product',
                          );

                          final String? cleanImage =
                              data['cleanImageUrl'] as String?;
                          final String? cutoutImage =
                              data['cutoutImageUrl'] as String?;
                          final String? productImage =
                              data['productImageUrl'] as String?;

                          final bool hasCutoutOrClean =
                              _isUrlFilled(cleanImage) ||
                              _isUrlFilled(cutoutImage);
                          final bool hasProduct = _isUrlFilled(productImage);

                          final bool cutoutInProgress =
                              !hasCutoutOrClean &&
                              (cutoutStatus == 'queued' ||
                                  cutoutStatus == 'running');

                          final bool productInProgress =
                              hasCutoutOrClean &&
                              !hasProduct &&
                              (productStatus == 'queued' ||
                                  productStatus == 'running');

                          final bool showSpinner =
                              cutoutInProgress ||
                              productInProgress ||
                              wardrobeItemShowsImageProcessingBadge(data);
                          final bool showError =
                              (!showSpinner) &&
                              (cutoutStatus == 'error' ||
                                  productStatus == 'error');

                          final name =
                              (data['name'] as String?)?.trim().isNotEmpty ==
                                  true
                              ? data['name'] as String
                              : (data['subCategoryLabel'] as String?) ??
                                    'Neznámy kúsok';

                          final subline =
                              ClothingKnowledgeBase.wardrobeDisplayCategoryLabel(
                                data,
                              );

                          return SizedBox(
                            width: tileWidth,
                            child: _WardrobeTileGlass(
                              data: data,
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
      );
  }
}

/// ============================================================================
/// Glass tile card used both in preview and category screen
/// ============================================================================
class _WardrobeTileGlass extends StatelessWidget {
  final Map<String, dynamic> data;
  final String title;
  final String subtitle;
  final bool showSpinner;
  final bool showError;
  final VoidCallback onDelete;
  final VoidCallback onOpenDetail;

  const _WardrobeTileGlass({
    required this.data,
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
      child: WardrobeProcessingSpinner(),
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
    debugLogWardrobeCardImage(data);
    final imageUrl = getBestWardrobeImageUrl(data);
    final membership = data['setMembership'];
    final setId = membership is Map
        ? (membership['setId'] ?? '').toString()
        : '';
    final pendingSet = data['pendingSetDraft'] is Map;
    final setColor = setId.isEmpty
        ? null
        : WardrobeSetPresentationV2.borderColor(setId);

    return InkWell(
      onTap: onOpenDetail,
      borderRadius: BorderRadius.circular(18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
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
            border: Border.all(
              color: setColor ?? Colors.white10,
              width: setColor == null ? 1 : 3,
            ),
          ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: wardrobeItemImage(
                            data: data,
                            imageUrl: imageUrl,
                            showSpinner: showSpinner,
                            cacheWidth: kWardrobeTileImageCacheWidth,
                          ),
                        ),
                        if (showSpinner) _topLeftSpinner(),
                        _topRightDeleteButton(),
                        if (setId.isNotEmpty)
                          Positioned(
                            left: 8,
                            bottom: 8,
                            child: Tooltip(
                              message: 'Súčasť setu',
                              child: CircleAvatar(
                                radius: 14,
                                backgroundColor: setColor,
                                child: Icon(
                                  WardrobeSetPresentationV2.icon(setId),
                                  size: 16,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        if (pendingSet)
                          const Positioned(
                            left: 8,
                            top: 8,
                            child: Tooltip(
                              message: 'Nedokončený set',
                              child: Icon(
                                Icons.help_outline,
                                color: Colors.amber,
                              ),
                            ),
                          ),
                        if (showError)
                          const Positioned(
                            bottom: 8,
                            right: 8,
                            child: Icon(
                              Icons.error_outline,
                              size: 16,
                              color: Colors.redAccent,
                            ),
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

  Future<void> _confirmAndDelete(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
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
        content: Text(
          'Naozaj chceš vymazať „$name“ zo šatníka?\n\nToto sa nedá vrátiť späť.',
        ),
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
      final membership = data['setMembership'];
      final setId = membership is Map
          ? (membership['setId'] ?? '').toString()
          : '';
      if (setId.isNotEmpty) {
        await WardrobeSetRepository().removeMember(setId, id);
      }
      await _firestore
          .collection('users')
          .doc(_authUser.uid)
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Kúsok bol vymazaný.')));
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

  String _normalizeText(String input) => _wardrobeNormalizeText(input);

  bool _matchesSearch(Map<String, dynamic> data, String query) {
    return _wardrobeV2MatchesSearch(data, query, _normalizeText);
  }

  int _compareDocs(Map<String, dynamic> a, Map<String, dynamic> b) {
    return wardrobeCompareItems(a, b, sortOption: _sortOption);
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
        body: Center(
          child: Text('Pre zobrazenie šatníka sa musíte prihlásiť.'),
        ),
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
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
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
                        .doc(_authUser.uid)
                        .collection('wardrobe')
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
                            'Chyba pri načítaní položiek.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        );
                      }

                      final allItems = (snapshot.data?.docs ?? []).map((d) {
                        final raw = Map<String, dynamic>.from(d.data() as Map);
                        final data = normalizeKeysForDisplay(raw);
                        data['__id'] = d.id;
                        return data;
                      }).where((data) => _wardrobeItemBelongsToMainGroup(
                        data,
                        widget.mainGroupKey,
                      )).toList();

                      final hasAnyProcessing = wardrobeListHasActiveProcessing(
                        allItems,
                      );

                      var items = allItems
                          .where(
                            (m) =>
                                ClothingKnowledgeBase.wardrobeDisplayCategoryKey(
                                  m,
                                ) ==
                                widget.categoryKey,
                          )
                          .toList();

                      if (_selectedSubKey != null) {
                        items = items
                            .where(
                              (m) =>
                                  ClothingKnowledgeBase.wardrobeDisplaySubCategoryKey(
                                    m,
                                  ) ==
                                  _selectedSubKey,
                            )
                            .toList();
                      }

                      if (_searchQuery.trim().isNotEmpty) {
                        items = items
                            .where(
                              (m) => _matchesSearch(m, _searchQuery.trim()),
                            )
                            .toList();
                      }

                      items.sort((a, b) => _compareDocs(a, b));

                      if (items.isEmpty) {
                        return const Center(
                          child: Text(
                            'V tejto kategórii zatiaľ nič nemáš.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (hasAnyProcessing) ...[
                            const Padding(
                              padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: WardrobeProcessingBanner(),
                            ),
                          ],
                          Expanded(
                            child: GridView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    childAspectRatio: 0.78,
                                  ),
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                final data = items[index];

                                final cutoutStatus = _statusFromProcessing(
                                  data,
                                  'cutout',
                                );
                                final productStatus = _statusFromProcessing(
                                  data,
                                  'product',
                                );

                                final String? cleanImage =
                                    data['cleanImageUrl'] as String?;
                                final String? cutoutImage =
                                    data['cutoutImageUrl'] as String?;
                                final String? productImage =
                                    data['productImageUrl'] as String?;

                                final bool hasCutoutOrClean =
                                    _isUrlFilled(cleanImage) ||
                                    _isUrlFilled(cutoutImage);
                                final bool hasProduct = _isUrlFilled(
                                  productImage,
                                );

                                final bool cutoutInProgress =
                                    !hasCutoutOrClean &&
                                    (cutoutStatus == 'queued' ||
                                        cutoutStatus == 'running');

                                final bool productInProgress =
                                    hasCutoutOrClean &&
                                    !hasProduct &&
                                    (productStatus == 'queued' ||
                                        productStatus == 'running');

                                final bool showSpinner =
                                    cutoutInProgress ||
                                    productInProgress ||
                                    wardrobeItemShowsImageProcessingBadge(data);
                                final bool showError =
                                    (!showSpinner) &&
                                    (cutoutStatus == 'error' ||
                                        productStatus == 'error');

                                final name =
                                    (data['name'] as String?)
                                            ?.trim()
                                            .isNotEmpty ==
                                        true
                                    ? data['name'] as String
                                    : (data['subCategoryLabel'] as String?) ??
                                          'Neznámy kúsok';

                                final subline =
                                    ClothingKnowledgeBase.wardrobeDisplayCategoryLabel(
                                      data,
                                    );

                                return _WardrobeTileGlass(
                                  data: data,
                                  title: name,
                                  subtitle: subline,
                                  showSpinner: showSpinner,
                                  showError: showError,
                                  onDelete: () =>
                                      _confirmAndDelete(context, data),
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
                            ),
                          ),
                        ],
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
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: spaced),
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
          color: selected
              ? Colors.white.withOpacity(0.92)
              : Colors.white.withOpacity(0.06),
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
    final label = searchQuery.trim().isEmpty
        ? 'Hľadať v šatníku...'
        : searchQuery.trim();

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
