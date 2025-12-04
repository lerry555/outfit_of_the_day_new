import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:outfitofTheDay/constants/app_constants.dart';
import 'premium_screen.dart';

class RecommendedScreen extends StatefulWidget {
  /// 0 = Odporúčané pre teba
  /// 1 = Nakupovať
  /// 2 = Wishlist
  final int initialTab;

  const RecommendedScreen({Key? key, this.initialTab = 0}) : super(key: key);

  @override
  State<RecommendedScreen> createState() => _RecommendedScreenState();
}

class _RecommendedScreenState extends State<RecommendedScreen> {
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  bool _showSuggestions = false;

  String _selectedGroupId = 'oblecenie';
  String? _selectedCategoryId;
  String? _selectedSubcategoryId;

  late final List<String> _allSuggestions;

  // Firebase – wishlist
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Set<String> _wishlistedIds = {};
  bool _loadingWishlist = false;

  /// DEMO produkty – neskôr veľkosti doplní AI z URL produktu
  final List<_DemoItem> _demoItems = [
    _DemoItem(
      id: 'demo_tricko_biele_nike',
      title: 'Biele basic tričko',
      brand: 'Nike',
      priceText: '24,99 €',
      imageUrl:
      'https://images.pexels.com/photos/10026491/pexels-photo-10026491.jpeg?auto=compress&cs=tinysrgb&w=400',
      groupId: 'oblecenie',
      categoryId: 'tricka_topy',
      subCategoryId: 'tricko',
      sizes: ['XS', 'S', 'M', 'L', 'XL', 'XXL'],
    ),
    _DemoItem(
      id: 'demo_rifle_skinny',
      title: 'Čierne skinny rifle',
      brand: 'Pull&Bear',
      priceText: '39,99 €',
      imageUrl:
      'https://images.pexels.com/photos/7671166/pexels-photo-7671166.jpeg?auto=compress&cs=tinysrgb&w=400',
      groupId: 'oblecenie',
      categoryId: 'nohavice',
      subCategoryId: 'rifle_skinny',
      sizes: ['28', '30', '31', '32', '33', '34', '36', '38', '40'],
    ),
    _DemoItem(
      id: 'demo_kabat_bezovy',
      title: 'Béžový kabát',
      brand: 'Zara',
      priceText: '89,99 €',
      imageUrl:
      'https://images.pexels.com/photos/7671167/pexels-photo-7671167.jpeg?auto=compress&cs=tinysrgb&w=400',
      groupId: 'oblecenie',
      categoryId: 'bundy_kabaty',
      subCategoryId: 'kabat',
      sizes: ['XS', 'S', 'M', 'L', 'XL'],
    ),
    _DemoItem(
      id: 'demo_tenisky_biele',
      title: 'Biele tenisky',
      brand: 'Adidas',
      priceText: '64,99 €',
      imageUrl:
      'https://images.pexels.com/photos/2529148/pexels-photo-2529148.jpeg?auto=compress&cs=tinysrgb&w=400',
      groupId: 'obuv',
      categoryId: 'tenisky',
      subCategoryId: 'tenisky_fashion',
      sizes: ['36', '37', '38', '39', '40', '41', '42', '43', '44', '45'],
    ),
    _DemoItem(
      id: 'demo_kabelka_kozena',
      title: 'Kožená kabelka',
      brand: 'Guess',
      priceText: '129,00 €',
      imageUrl:
      'https://images.pexels.com/photos/167703/pexels-photo-167703.jpeg?auto=compress&cs=tinysrgb&w=400',
      groupId: 'doplnky',
      categoryId: 'dopl_tasky',
      subCategoryId: 'kabelka',
      sizes: ['ONE SIZE'],
    ),
    _DemoItem(
      id: 'demo_plavky_bikiny',
      title: 'Jednodielne plavky',
      brand: 'Calzedonia',
      priceText: '49,99 €',
      imageUrl:
      'https://images.pexels.com/photos/947307/pexels-photo-947307.jpeg?auto=compress&cs=tinysrgb&w=400',
      groupId: 'plavky',
      categoryId: 'plavky_damske',
      subCategoryId: 'bikiny',
      sizes: ['36 B', '38 B', '38 C', '40 B', '40 D'],
    ),
    _DemoItem(
      id: 'demo_sport_leginy',
      title: 'Športové legíny',
      brand: 'Nike',
      priceText: '39,99 €',
      imageUrl:
      'https://images.pexels.com/photos/3764375/pexels-photo-3764375.jpeg?auto=compress&cs=tinysrgb&w=400',
      groupId: 'sport',
      categoryId: 'sport_oblecenie',
      subCategoryId: 'sport_leginy',
      sizes: ['XS', 'S', 'M', 'L'],
    ),
  ];

  @override
  void initState() {
    super.initState();

    _allSuggestions = [
      ...categoryLabels.values,
      ...subCategoryLabels.values,
    ];

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
        _showSuggestions = _searchQuery.trim().isNotEmpty;
      });
    });

    _loadWishlist();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ---------------- NORMALIZÁCIA TEXTU (bez diakritiky) ----------------

  String _normalize(String input) {
    const Map<String, String> map = {
      'á': 'a',
      'ä': 'a',
      'č': 'c',
      'ď': 'd',
      'é': 'e',
      'í': 'i',
      'ĺ': 'l',
      'ľ': 'l',
      'ň': 'n',
      'ó': 'o',
      'ô': 'o',
      'ŕ': 'r',
      'š': 's',
      'ť': 't',
      'ú': 'u',
      'ý': 'y',
      'ž': 'z',
    };

    final lower = input.toLowerCase();
    final buffer = StringBuffer();
    for (final codeUnit in lower.codeUnits) {
      final ch = String.fromCharCode(codeUnit);
      buffer.write(map[ch] ?? ch);
    }
    return buffer.toString();
  }

  List<String> get _filteredSuggestions {
    if (!_showSuggestions || _searchQuery.trim().isEmpty) {
      return [];
    }
    final q = _normalize(_searchQuery.trim());
    return _allSuggestions
        .where((s) => _normalize(s).contains(q))
        .take(15)
        .toList();
  }

  List<_DemoItem> get _filteredItems {
    Iterable<_DemoItem> items = _demoItems;

    if (_selectedGroupId.isNotEmpty) {
      items = items.where((i) => i.groupId == _selectedGroupId);
    }
    if (_selectedCategoryId != null) {
      items = items.where((i) => i.categoryId == _selectedCategoryId);
    }
    if (_selectedSubcategoryId != null) {
      items = items.where((i) => i.subCategoryId == _selectedSubcategoryId);
    }

    if (_searchQuery.trim().isNotEmpty) {
      final q = _normalize(_searchQuery.trim());
      items = items.where((i) {
        final text =
        _normalize('${i.title} ${i.brand} ${i.priceText ?? ''}');
        return text.contains(q);
      });
    }

    return items.toList();
  }

  List<_DemoItem> get _wishlistItems {
    return _demoItems.where((i) => _wishlistedIds.contains(i.id)).toList();
  }

  // ---------------- WISHLIST – FIRESTORE ----------------

  Future<void> _loadWishlist() async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() {
      _loadingWishlist = true;
    });

    try {
      final snap = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('wishlist')
          .get();

      final ids = <String>{};

      for (final doc in snap.docs) {
        final id = doc.id;
        ids.add(id);

        final data = doc.data();

        // vyber zvolených veľkostí – podporíme aj staré pole 'selectedSize'
        List<String> selectedSizes = [];
        final rawSizes = data['selectedSizes'];
        if (rawSizes is List) {
          selectedSizes =
              rawSizes.map((e) => e.toString()).toList(growable: true);
        } else if (data['selectedSize'] is String) {
          selectedSizes = [data['selectedSize'] as String];
        }

        final targetPriceNum = data['targetPrice'] as num?;
        final targetPrice =
        targetPriceNum != null ? targetPriceNum.toDouble() : null;

        final index = _demoItems.indexWhere((e) => e.id == id);
        if (index != -1) {
          _demoItems[index].selectedSizes = selectedSizes;
          _demoItems[index].targetPrice = targetPrice;
        }
      }

      setState(() {
        _wishlistedIds = ids;
      });
    } catch (e) {
      debugPrint('Error loading wishlist: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingWishlist = false;
        });
      }
    }
  }

  Future<void> _toggleWishlist(_DemoItem item) async {
    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pre wishlist sa prosím prihlás.'),
        ),
      );
      return;
    }

    final docRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('wishlist')
        .doc(item.id);

    final alreadyIn = _wishlistedIds.contains(item.id);

    try {
      if (alreadyIn) {
        await docRef.delete();
      } else {
        await docRef.set({
          'title': item.title,
          'brand': item.brand,
          'priceText': item.priceText,
          'imageUrl': item.imageUrl,
          'groupId': item.groupId,
          'categoryId': item.categoryId,
          'subCategoryId': item.subCategoryId,
          'selectedSizes': item.selectedSizes,
          'targetPrice': item.targetPrice,
          'currency': 'EUR',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      setState(() {
        if (alreadyIn) {
          _wishlistedIds.remove(item.id);
          item.selectedSizes = [];
          item.targetPrice = null;
        } else {
          _wishlistedIds.add(item.id);
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            alreadyIn
                ? 'Odstránené z wishlistu.'
                : 'Pridané do wishlistu 💜',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error toggle wishlist: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nepodarilo sa upraviť wishlist: $e'),
        ),
      );
    }
  }

  /// Pridá alebo odstráni konkrétnu veľkosť v zozname sledovaných veľkostí.
  Future<void> _toggleSizeForItem(_DemoItem item, String size) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final newSizes = List<String>.from(item.selectedSizes);
    if (newSizes.contains(size)) {
      newSizes.remove(size);
    } else {
      newSizes.add(size);
    }

    final docRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('wishlist')
        .doc(item.id);

    try {
      await docRef.set(
        {
          'selectedSizes': newSizes,
        },
        SetOptions(merge: true),
      );

      setState(() {
        item.selectedSizes = newSizes;
      });
    } catch (e) {
      debugPrint('Error setting sizes: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nepodarilo sa uložiť veľkosti: $e'),
        ),
      );
    }
  }

  Future<void> _setTargetPrice(_DemoItem item, double? price) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final docRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('wishlist')
        .doc(item.id);

    try {
      await docRef.set(
        {
          'targetPrice': price,
          'currency': 'EUR',
        },
        SetOptions(merge: true),
      );

      setState(() {
        item.targetPrice = price;
      });
    } catch (e) {
      debugPrint('Error setting target price: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nepodarilo sa uložiť cenu: $e'),
        ),
      );
    }
  }

  Future<void> _showTargetPriceDialog(_DemoItem item) async {
    final controller = TextEditingController(
      text: item.targetPrice != null
          ? item.targetPrice!.toStringAsFixed(2)
          : '',
    );

    final result = await showDialog<double?>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('Strážiť cenu'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Cenu môžeš sledovať aj bez zvolenej veľkosti.\n'
                    'Alebo naopak – nastav len veľkosti a cenu nechaj prázdnu.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Cieľová cena (voliteľné)',
                  suffixText: '€',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Zrušiť'),
            ),
            ElevatedButton(
              onPressed: () {
                final raw = controller.text.trim();
                if (raw.isEmpty) {
                  Navigator.pop(context, null);
                  return;
                }
                final normalized = raw.replaceAll(',', '.');
                final value = double.tryParse(normalized);
                if (value == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Zadaj platnú cenu.'),
                    ),
                  );
                  return;
                }
                Navigator.pop(context, value);
              },
              child: const Text('Uložiť'),
            ),
          ],
        );
      },
    );

    // result == null → zrušené alebo vymazané
    if (result == null && controller.text.trim().isEmpty) {
      await _setTargetPrice(item, null);
    } else if (result != null) {
      await _setTargetPrice(item, result);
    }
  }

  // ---------------- UI – BUILD ----------------

  @override
  Widget build(BuildContext context) {
    final initialIndex = widget.initialTab.clamp(0, 2);

    return DefaultTabController(
      length: 3,
      initialIndex: initialIndex,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Scaffold(
            appBar: AppBar(
              title: const Text('#OOTD'),
              centerTitle: true,
              elevation: 0,
              bottom: const TabBar(
                isScrollable: false,
                tabs: [
                  Tab(text: 'Odporúčané pre teba'),
                  Tab(text: 'Nakupovať'),
                  Tab(text: 'Wishlist'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _buildShoppingContent(
                  theme,
                  title: 'Odporúčané kúsky pre teba',
                ),
                _buildShoppingContent(
                  theme,
                  title: 'Vyber si z kategórií a značiek',
                ),
                _buildWishlistTab(theme),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------------- UI – spoločné časti ----------------

  Widget _buildSearchBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Hľadať značky, produkty a iné…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.close),
            onPressed: _onClearSearch,
          )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(32),
          ),
          filled: true,
        ),
      ),
    );
  }

  Widget _buildSuggestions(ThemeData theme) {
    final suggestions = _filteredSuggestions;
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: suggestions.length,
        separatorBuilder: (_, __) =>
        const Divider(height: 1, thickness: 0.5),
        itemBuilder: (context, index) {
          final s = suggestions[index];
          return ListTile(
            leading: const Icon(Icons.search, size: 20),
            title: Text(s),
            onTap: () => _onSuggestionTap(s),
          );
        },
      ),
    );
  }

  void _onSuggestionTap(String suggestion) {
    _searchController.text = suggestion;
    setState(() {
      _searchQuery = suggestion;
      _showSuggestions = false;
    });
  }

  void _onClearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _showSuggestions = false;
    });
  }

  // ---------------- UI – SHOPPING TABS ----------------

  Widget _buildShoppingContent(ThemeData theme, {required String title}) {
    final groupEntries = mainCategoryGroups.entries.toList();

    // pridáme Premium dlaždicu, ak tam ešte nie je
    final hasPremium = groupEntries.any((e) => e.key == 'premium');
    if (!hasPremium) {
      groupEntries.add(const MapEntry('premium', 'Premium'));
    }

    return Column(
      children: [
        _buildSearchBar(theme),
        _buildSuggestions(theme),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kategórie',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                // GRID KATEGÓRIÍ (vrátane Premium)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: groupEntries.length,
                  gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.9,
                  ),
                  itemBuilder: (context, index) {
                    final entry = groupEntries[index];
                    final isSelected = entry.key == _selectedGroupId;
                    final isPremium = entry.key == 'premium';

                    return GestureDetector(
                      onTap: () {
                        if (isPremium) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const PremiumScreen(),
                            ),
                          );
                        } else {
                          setState(() {
                            _selectedGroupId = entry.key;
                            _selectedCategoryId = null;
                            _selectedSubcategoryId = null;
                          });
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected && !isPremium
                              ? theme.colorScheme.primary.withOpacity(0.08)
                              : theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected && !isPremium
                                ? theme.colorScheme.primary
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isPremium
                                  ? Icons.workspace_premium_outlined
                                  : _iconForGroup(entry.key),
                              size: 32,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              entry.value,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: isSelected && !isPremium
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 16),

                if (_selectedGroupId.isNotEmpty)
                  _buildCategoryFilters(theme),

                const SizedBox(height: 8),

                if (_selectedCategoryId != null)
                  _buildSubcategoryFilters(theme),

                const SizedBox(height: 16),

                Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                _buildProductList(theme, items: _filteredItems),
              ],
            ),
          ),
        ),
      ],
    );
  }

  IconData _iconForGroup(String groupId) {
    switch (groupId) {
      case 'oblecenie':
        return Icons.checkroom_outlined;
      case 'obuv':
        return Icons.directions_walk_outlined;
      case 'doplnky':
        return Icons.work_outline;
      case 'plavky':
        return Icons.beach_access_outlined;
      case 'sport':
        return Icons.fitness_center_outlined;
      default:
        return Icons.category_outlined;
    }
  }

  Widget _buildCategoryFilters(ThemeData theme) {
    final cats = categoryTree[_selectedGroupId] ?? [];
    if (cats.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Filtrovať podľa kategórie',
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: cats.map((catId) {
              final label = categoryLabels[catId] ?? catId;
              final selected = catId == _selectedCategoryId;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) {
                    setState(() {
                      if (selected) {
                        _selectedCategoryId = null;
                        _selectedSubcategoryId = null;
                      } else {
                        _selectedCategoryId = catId;
                        _selectedSubcategoryId = null;
                      }
                    });
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSubcategoryFilters(ThemeData theme) {
    final subs = subCategoryTree[_selectedCategoryId] ?? [];
    if (subs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Spresniť typ',
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: subs.map((subId) {
            final label = subCategoryLabels[subId] ?? subId;
            final selected = subId == _selectedSubcategoryId;
            return ChoiceChip(
              label: Text(label),
              selected: selected,
              onSelected: (_) {
                setState(() {
                  if (selected) {
                    _selectedSubcategoryId = null;
                  } else {
                    _selectedSubcategoryId = subId;
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildProductList(ThemeData theme,
      {required List<_DemoItem> items}) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        child: Center(
          child: Text(
            'Nenašli sme žiadne kúsky podľa zvolených filtrov.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        final isWishlisted = _wishlistedIds.contains(item.id);

        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
                child: Image.network(
                  item.imageUrl,
                  width: 90,
                  height: 90,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 90,
                      height: 90,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.image_not_supported),
                    );
                  },
                ),
              ),
              Expanded(
                child: Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.brand,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      if (item.priceText != null)
                        Text(
                          item.priceText!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  isWishlisted ? Icons.favorite : Icons.favorite_border,
                  color: isWishlisted ? Colors.pink : null,
                ),
                onPressed: () => _toggleWishlist(item),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------- UI – WISHLIST TAB ----------------

  Widget _buildWishlistTab(ThemeData theme) {
    if (_loadingWishlist) {
      return const Center(child: CircularProgressIndicator());
    }

    final items = _wishlistItems;

    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32.0),
        child: Center(
          child: Text(
            'Zatiaľ nemáš v wishliste žiadne kúsky.\n'
                'Klikni na srdiečko pri produktoch a ulož si, čo sa ti páči.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Wishlist',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Vyber si, čo chceš strážiť – veľkosti, cenu alebo obe naraz. '
                'Keď sa tvoja veľkosť objaví na sklade alebo cena klesne pod cieľ, pošleme ti upozornenie. '
                'Upozornenia si môžeš kedykoľvek vypnúť v nastaveniach aplikácie.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          _buildWishlistList(theme, items),
        ],
      ),
    );
  }

  Widget _buildWishlistList(ThemeData theme, List<_DemoItem> items) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];

        final hasSizes = item.selectedSizes.isNotEmpty;
        final hasPrice = item.targetPrice != null;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      item.imageUrl,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 80,
                          height: 80,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.image_not_supported),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.brand, style: theme.textTheme.bodySmall),
                        const SizedBox(height: 2),
                        Text(
                          item.title,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        if (item.priceText != null)
                          Text(
                            item.priceText!,
                            style: theme.textTheme.bodyMedium,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              Text(
                'Ktoré veľkosti chceš sledovať? (môžeš označiť aj viac)',
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: item.sizes.map((size) {
                    final selected = item.selectedSizes.contains(size);
                    return Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: FilterChip(
                        label: Text(size),
                        selected: selected,
                        onSelected: (_) => _toggleSizeForItem(item, size),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: Text(
                      hasPrice
                          ? 'Strážiť cenu pod: '
                          '${item.targetPrice!.toStringAsFixed(2)} €'
                          : 'Strážiť cenu (voliteľné)',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  if (hasPrice)
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Zrušiť cenu',
                      onPressed: () => _setTargetPrice(item, null),
                    ),
                  TextButton(
                    onPressed: () => _showTargetPriceDialog(item),
                    child: Text(
                      hasPrice ? 'Upraviť' : 'Nastaviť cenu',
                    ),
                  ),
                ],
              ),

              if (!hasSizes && !hasPrice) ...[
                const SizedBox(height: 4),
                Text(
                  'Tip: nastav veľkosť alebo cenu, aby sme ti vedeli dať vedieť, keď sa niečo zmení.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.grey[500]),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ---------------- MODEL ----------------

class _DemoItem {
  final String id;
  final String title;
  final String brand;
  final String? priceText;
  final String imageUrl;

  final String groupId;
  final String categoryId;
  final String subCategoryId;

  final List<String> sizes;
  List<String> selectedSizes;
  double? targetPrice;

  _DemoItem({
    required this.id,
    required this.title,
    required this.brand,
    required this.priceText,
    required this.imageUrl,
    required this.groupId,
    required this.categoryId,
    required this.subCategoryId,
    required this.sizes,
    this.selectedSizes = const [],
    this.targetPrice,
  });
}
