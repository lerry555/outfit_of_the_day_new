import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:outfitofTheDay/constants/app_constants.dart';
import 'package:outfitofTheDay/screens/clothing_detail_screen.dart';

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
  // Legend bottom sheet
  // ---------------------------------------------------------------------------
  void _showProcessingLegend(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
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
              children: [
                const Text(
                  'Úprava fotiek',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
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
                        style: TextStyle(height: 1.35),
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
      data['subCategoryLabel'] =
          (data['subCategoryLabel'] as String?) ?? (subCategoryLabels[subCategoryKey] ?? subCategoryKey);
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
        appBar: AppBar(
          title: const Text('Môj šatník'),
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () => _showProcessingLegend(context),
              tooltip: 'Čo znamená ten kruh?',
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: mainGroupKeys.map((k) => Tab(text: mainCategoryGroups[k] ?? k)).toList(),
          ),
        ),
        body: TabBarView(
          children: mainGroupKeys.map((mainGroupKey) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Hľadať v šatníku…',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      isDense: true,
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text('Triediť podľa: '),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: _sortOption,
                        items: _sortOptions.map((opt) {
                          return DropdownMenuItem<String>(value: opt, child: Text(opt));
                        }).toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _sortOption = value);
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('users')
                        .doc(_authUser!.uid)
                        .collection('wardrobe')
                        .where('mainGroup', isEqualTo: mainGroupKey)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return const Center(child: Text('Nastala chyba pri načítaní šatníka.'));
                      }

                      final docs = snapshot.data?.docs ?? [];

                      final normalized = <Map<String, dynamic>>[];
                      for (final d in docs) {
                        final m = d.data() as Map<String, dynamic>;
                        final data = _normalizeKeysForDisplay(m);
                        data['__id'] = d.id;

                        if (_searchQuery.trim().isNotEmpty && !_matchesSearch(data, _searchQuery.trim())) {
                          continue;
                        }
                        normalized.add(data);
                      }

                      normalized.sort((a, b) => _compareDocs(a, b));

                      final Map<String, List<Map<String, dynamic>>> byCategory = {};
                      for (final item in normalized) {
                        final ck = (item['categoryKey'] as String?) ?? '';
                        if (ck.isEmpty) continue;
                        byCategory.putIfAbsent(ck, () => []);
                        byCategory[ck]!.add(item);
                      }

                      final categoryKeysInOrder = categoryTree[mainGroupKey] ?? [];

                      final totalCount = byCategory.values.fold<int>(0, (p, e) => p + e.length);
                      if (totalCount == 0) {
                        return Center(
                          child: Text(
                            'Zatiaľ tu nemáš žiadne kúsky.',
                            style: TextStyle(
                              color: Theme.of(context).textTheme.bodyLarge?.color?.withOpacity(0.6),
                            ),
                          ),
                        );
                      }

                      return ListView(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        children: [
                          for (final ck in categoryKeysInOrder)
                            if ((byCategory[ck] ?? []).isNotEmpty)
                              _CategorySection(
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
                              ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Sekcia v liste: Nadpis + preview (4 kúsky) + "Zobraziť všetko"
// -----------------------------------------------------------------------------
class _CategorySection extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> items;
  final VoidCallback onOpenAll;

  const _CategorySection({
    required this.title,
    required this.items,
    required this.onOpenAll,
  });

  List<String> _normalizeList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.map((e) => e.toString()).toList();
    if (value is String && value.isNotEmpty) return [value];
    return [];
  }

  String _statusFromProcessing(Map<String, dynamic> data, String key) {
    // prefer nested map: processing: { cutout: "...", product: "..." }
    final p = data['processing'];
    if (p is Map) {
      final m = p.cast<String, dynamic>();
      final v = (m[key] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    // legacy dotted fields (ak by náhodou existovali)
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
    final preview = items.take(4).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: onOpenAll,
                child: Text('Zobraziť všetko (${items.length})'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: preview.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.75,
            ),
            itemBuilder: (context, index) {
              final data = preview[index];

              // -----------------------------
              // IMAGE priority
              // -----------------------------
              final String? productImage = data['productImageUrl'] as String?;
              final String? cleanImage = data['cleanImageUrl'] as String?;
              final String? cutoutImage = data['cutoutImageUrl'] as String?;
              final String? originalImage = data['originalImageUrl'] as String?;
              final String? legacyImage = data['imageUrl'] as String?;

              final imageUrl =
              (_isUrlFilled(productImage))
                  ? productImage!
                  : (_isUrlFilled(cleanImage))
                  ? cleanImage!
                  : (_isUrlFilled(cutoutImage))
                  ? cutoutImage!
                  : (_isUrlFilled(originalImage))
                  ? originalImage!
                  : (legacyImage ?? '');

              // -----------------------------
              // ✅ Spinner logic (CUTOUT + PRODUCT)
              // -----------------------------
              final cutoutStatus = _statusFromProcessing(data, 'cutout'); // queued|running|done|error
              final productStatus = _statusFromProcessing(data, 'product'); // queued|running|done|error|disabled

              final bool hasCutoutOrClean = _isUrlFilled(cleanImage) || _isUrlFilled(cutoutImage);
              final bool hasProduct = _isUrlFilled(productImage);

              final bool cutoutInProgress =
                  !hasCutoutOrClean && (cutoutStatus == 'queued' || cutoutStatus == 'running');

              final bool productInProgress =
                  hasCutoutOrClean &&
                      !hasProduct &&
                      (productStatus == 'queued' || productStatus == 'running');

              final bool showSpinner = cutoutInProgress || productInProgress;

              final bool showError =
                  (!showSpinner) &&
                      (cutoutStatus == 'error' || productStatus == 'error');

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

              return InkWell(
                onTap: () {
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
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                          child: imageUrl.isNotEmpty
                              ? Stack(
                            children: [
                              Positioned.fill(
                                child: Image.network(imageUrl, fit: BoxFit.cover),
                              ),

                              if (showSpinner)
                                const Positioned(
                                  top: 8,
                                  right: 8,
                                  child: SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.6,
                                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4A6CF7)),
                                    ),
                                  ),
                                ),

                              if (showError)
                                const Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Icon(
                                    Icons.error_outline,
                                    size: 16,
                                    color: Colors.redAccent,
                                  ),
                                ),
                            ],
                          )
                              : Container(
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.image_not_supported, size: 50),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (subline.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                          child: Text(
                            subline,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Screen: všetky kúsky v jednej kategórii (podkategórie + filtre)
// -----------------------------------------------------------------------------
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
  String? _selectedSeason;
  String? _selectedStyle;
  String? _selectedPattern;

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
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Hľadať v kategórii…',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          if (subKeys.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Všetko'),
                      selected: _selectedSubKey == null,
                      onSelected: (_) => setState(() => _selectedSubKey = null),
                    ),
                    const SizedBox(width: 8),
                    ...subKeys.map((sk) {
                      final label = subCategoryLabels[sk] ?? sk;
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: _selectedSubKey == sk,
                          onSelected: (_) => setState(() => _selectedSubKey = sk),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('Triediť: '),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _sortOption,
                  items: _sortOptions.map((opt) => DropdownMenuItem<String>(value: opt, child: Text(opt))).toList(),
                  onChanged: (v) => setState(() => _sortOption = v ?? _sortOption),
                ),
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
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(child: Text('Chyba pri načítaní položiek.'));
                }

                var items = (snapshot.data?.docs ?? []).map((d) {
                  final m = d.data() as Map<String, dynamic>;
                  m['__id'] = d.id;
                  return m;
                }).toList();

                if (_selectedSubKey != null) {
                  items = items.where((m) => (m['subCategoryKey'] as String?) == _selectedSubKey).toList();
                }

                if (_selectedSeason != null) {
                  items = items.where((m) {
                    final s = m['season'];
                    if (s is String) return s == _selectedSeason;
                    if (s is List) return List<String>.from(s).contains(_selectedSeason);
                    return false;
                  }).toList();
                }

                if (_selectedStyle != null) {
                  items = items.where((m) {
                    final s = m['style'];
                    if (s is String) return s == _selectedStyle;
                    if (s is List) return List<String>.from(s).contains(_selectedStyle);
                    return false;
                  }).toList();
                }

                if (_selectedPattern != null) {
                  items = items.where((m) {
                    final p = m['pattern'];
                    if (p is String) return p == _selectedPattern;
                    if (p is List) return List<String>.from(p).contains(_selectedPattern);
                    return false;
                  }).toList();
                }

                if (_searchQuery.trim().isNotEmpty) {
                  items = items.where((m) => _matchesSearch(m, _searchQuery.trim())).toList();
                }

                items.sort((a, b) => _compareDocs(a, b));

                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      'V tejto kategórii zatiaľ nič nemáš.',
                      style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color?.withOpacity(0.6)),
                    ),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final data = items[index];

                    // IMAGE priority (rovnaké ako v preview)
                    final String? productImage = data['productImageUrl'] as String?;
                    final String? cleanImage = data['cleanImageUrl'] as String?;
                    final String? cutoutImage = data['cutoutImageUrl'] as String?;
                    final String? originalImage = data['originalImageUrl'] as String?;
                    final String? legacyImage = data['imageUrl'] as String?;

                    final imageUrl =
                    (_isUrlFilled(productImage))
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
                        hasCutoutOrClean &&
                            !hasProduct &&
                            (productStatus == 'queued' || productStatus == 'running');

                    final bool showSpinner = cutoutInProgress || productInProgress;

                    final bool showError =
                        (!showSpinner) &&
                            (cutoutStatus == 'error' || productStatus == 'error');

                    final name = (data['name'] as String?)?.trim().isNotEmpty == true
                        ? data['name'] as String
                        : (data['subCategoryLabel'] as String?) ?? 'Neznámy kúsok';

                    final seasons = _normalizeList(data['season']);
                    final subline = seasons.isNotEmpty ? seasons.join(', ') : '';

                    return InkWell(
                      onTap: () {
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
                      child: Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                child: imageUrl.isNotEmpty
                                    ? Stack(
                                  children: [
                                    Positioned.fill(
                                      child: Image.network(imageUrl, fit: BoxFit.cover),
                                    ),
                                    if (showSpinner)
                                      const Positioned(
                                        top: 8,
                                        right: 8,
                                        child: SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.6,
                                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4A6CF7)),
                                          ),
                                        ),
                                      ),
                                    if (showError)
                                      const Positioned(
                                        top: 6,
                                        right: 6,
                                        child: Icon(
                                          Icons.error_outline,
                                          size: 16,
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                  ],
                                )
                                    : Container(
                                  color: Colors.grey.shade200,
                                  child: const Icon(Icons.image_not_supported, size: 50),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (subline.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                                child: Text(
                                  subline,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
