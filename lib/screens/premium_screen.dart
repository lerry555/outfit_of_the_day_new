import 'package:flutter/material.dart';
import 'package:outfitofTheDay/constants/app_constants.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({Key? key}) : super(key: key);

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  bool _showSuggestions = false;

  String _selectedGroupId = 'oblecenie'; // oblecenie / obuv / doplnky
  String? _selectedCategoryId;
  String? _selectedSubcategoryId;
  String? _selectedBrand; // premium značka

  late final List<String> _allSuggestions;

  // Demo PREMIUM produkty – neskôr napojíme na reálne affiliate/AI
  final List<_PremiumItem> _demoItems = [
    _PremiumItem(
      title: 'Biele logo tričko',
      brand: 'Calvin Klein',
      priceText: '49,90 €',
      imageUrl:
      'https://images.pexels.com/photos/7671169/pexels-photo-7671169.jpeg?auto=compress&cs=tinysrgb&w=400',
      groupId: 'oblecenie',
      categoryId: 'tricka_topy',
      subCategoryId: 'tricko',
    ),
    _PremiumItem(
      title: 'Pruhovaný sveter',
      brand: 'Tommy Hilfiger',
      priceText: '129,00 €',
      imageUrl:
      'https://images.pexels.com/photos/7671170/pexels-photo-7671170.jpeg?auto=compress&cs=tinysrgb&w=400',
      groupId: 'oblecenie',
      categoryId: 'svetre',
      subCategoryId: 'sveter_klasicky',
    ),
    _PremiumItem(
      title: 'Modré slim rifle',
      brand: 'Diesel',
      priceText: '159,00 €',
      imageUrl:
      'https://images.pexels.com/photos/7671168/pexels-photo-7671168.jpeg?auto=compress&cs=tinysrgb&w=400',
      groupId: 'oblecenie',
      categoryId: 'nohavice',
      subCategoryId: 'rifle_skinny',
    ),
    _PremiumItem(
      title: 'Kožená bunda',
      brand: 'Boss',
      priceText: '349,00 €',
      imageUrl:
      'https://images.pexels.com/photos/7697314/pexels-photo-7697314.jpeg?auto=compress&cs=tinysrgb&w=400',
      groupId: 'oblecenie',
      categoryId: 'bundy_kabaty',
      subCategoryId: 'bunda_kozena',
    ),
    _PremiumItem(
      title: 'Biele premium tenisky',
      brand: 'Lacoste',
      priceText: '129,00 €',
      imageUrl:
      'https://images.pexels.com/photos/2529147/pexels-photo-2529147.jpeg?auto=compress&cs=tinysrgb&w=400',
      groupId: 'obuv',
      categoryId: 'tenisky',
      subCategoryId: 'tenisky_fashion',
    ),
    _PremiumItem(
      title: 'Kožené mokasíny',
      brand: 'Ralph Lauren',
      priceText: '219,00 €',
      imageUrl:
      'https://images.pexels.com/photos/6670804/pexels-photo-6670804.jpeg?auto=compress&cs=tinysrgb&w=400',
      groupId: 'obuv',
      categoryId: 'elegantna_obuv',
      subCategoryId: 'mokasiny',
    ),
    _PremiumItem(
      title: 'Crossbody kabelka',
      brand: 'Guess',
      priceText: '139,00 €',
      imageUrl:
      'https://images.pexels.com/photos/167703/pexels-photo-167703.jpeg?auto=compress&cs=tinysrgb&w=400',
      groupId: 'doplnky',
      categoryId: 'dopl_tasky',
      subCategoryId: 'taska_crossbody',
    ),
    _PremiumItem(
      title: 'Čierna listová kabelka',
      brand: 'Karl Lagerfeld',
      priceText: '189,00 €',
      imageUrl:
      'https://images.pexels.com/photos/322207/pexels-photo-322207.jpeg?auto=compress&cs=tinysrgb&w=400',
      groupId: 'doplnky',
      categoryId: 'dopl_tasky',
      subCategoryId: 'kabelka_listova',
    ),
  ];

  @override
  void initState() {
    super.initState();

    // suggestions = názvy kategórií + podkategórií + prémiové značky
    _allSuggestions = [
      ...categoryLabels.values,
      ...subCategoryLabels.values,
      ...premiumBrands,
    ];

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
        _showSuggestions = _searchQuery.trim().isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normalize(String input) {
    // jednoduché odstránenie diakritiky + lowerCase
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
    for (final ch in lower.characters) {
      buffer.write(map[ch] ?? ch);
    }
    return buffer.toString();
  }

  List<String> get _filteredSuggestions {
    if (!_showSuggestions || _searchQuery.trim().isEmpty) return [];
    final q = _normalize(_searchQuery.trim());
    return _allSuggestions
        .where((s) => _normalize(s).contains(q))
        .take(15)
        .toList();
  }

  List<_PremiumItem> get _filteredItems {
    Iterable<_PremiumItem> items = _demoItems;

    // skupina (oblecenie / obuv / doplnky)
    if (_selectedGroupId.isNotEmpty) {
      items = items.where((i) => i.groupId == _selectedGroupId);
    }
    // kategória
    if (_selectedCategoryId != null) {
      items = items.where((i) => i.categoryId == _selectedCategoryId);
    }
    // podkategória
    if (_selectedSubcategoryId != null) {
      items = items.where((i) => i.subCategoryId == _selectedSubcategoryId);
    }
    // značka
    if (_selectedBrand != null && _selectedBrand!.isNotEmpty) {
      items = items.where((i) => i.brand == _selectedBrand);
    }

    // textové vyhľadávanie
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

  void _onSuggestionTap(String suggestion) {
    // ak suggestion je značka, rovno ju použijeme ako filter
    if (premiumBrands.contains(suggestion)) {
      setState(() {
        _selectedBrand = suggestion;
        _searchController.text = suggestion;
        _searchQuery = suggestion;
        _showSuggestions = false;
      });
      return;
    }

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Premium používame len pre oblecenie/obuv/doplnky – tieto tri skupiny
    final premiumGroups = [
      'oblecenie',
      'obuv',
      'doplnky',
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Premium výber'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // HERO sekcia
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary.withOpacity(0.15),
                  theme.colorScheme.secondary.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Prémiové značky',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Objav kvalitné kúsky od značiek, ktoré nosíš aj vo svete módy.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(
                  Icons.workspace_premium_outlined,
                  size: 40,
                ),
              ],
            ),
          ),

          // SEARCH BAR
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Hľadať značky, kategórie a kúsky…',
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
          ),

          // SUGGESTIONS
          if (_filteredSuggestions.isNotEmpty)
            Container(
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
                itemCount: _filteredSuggestions.length,
                separatorBuilder: (_, __) =>
                const Divider(height: 1, thickness: 0.5),
                itemBuilder: (context, index) {
                  final s = _filteredSuggestions[index];
                  final isBrand = premiumBrands.contains(s);
                  return ListTile(
                    leading: Icon(
                      isBrand ? Icons.workspace_premium_outlined : Icons.search,
                      size: 20,
                    ),
                    title: Text(s),
                    onTap: () => _onSuggestionTap(s),
                  );
                },
              ),
            ),

          const SizedBox(height: 6),

          // Zvyšok obsahu
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // PREMIUM BRANDS – chips
                  Text(
                    'Značky',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: premiumBrands.map((brand) {
                        final selected = brand == _selectedBrand;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            label: Text(brand),
                            selected: selected,
                            onSelected: (_) {
                              setState(() {
                                if (selected) {
                                  _selectedBrand = null;
                                } else {
                                  _selectedBrand = brand;
                                }
                              });
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // CATEGORY GROUPS (oblecenie/obuv/doplnky)
                  Text(
                    'Typy produktov',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: premiumGroups.map((groupId) {
                      final label = mainCategoryGroups[groupId] ?? groupId;
                      final selected = groupId == _selectedGroupId;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            label: Text(label),
                            selected: selected,
                            onSelected: (_) {
                              setState(() {
                                _selectedGroupId = groupId;
                                _selectedCategoryId = null;
                                _selectedSubcategoryId = null;
                              });
                            },
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 12),

                  // KATEGÓRIE PODĽA SKUPINY
                  _buildCategoryFilters(theme),

                  const SizedBox(height: 8),

                  // PODKATEGÓRIE
                  if (_selectedCategoryId != null)
                    _buildSubcategoryFilters(theme),

                  const SizedBox(height: 16),

                  // PREMIUM ITEMS LIST
                  Text(
                    'Premium kúsky',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _buildProductList(theme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilters(ThemeData theme) {
    final cats = categoryTree[_selectedGroupId] ?? [];
    if (cats.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
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

  Widget _buildProductList(ThemeData theme) {
    final items = _filteredItems;

    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        child: Center(
          child: Text(
            'Pre zvolené filtre sme nenašli žiadne prémiové kúsky.',
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
                          fontWeight: FontWeight.w600,
                        ),
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
                icon: const Icon(Icons.favorite_border),
                onPressed: () {
                  // TODO: neskôr pridať do wishlistu
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Wishlist pre Premium ešte len chystáme 💜'),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PremiumItem {
  final String title;
  final String brand;
  final String? priceText;
  final String imageUrl;

  final String groupId;
  final String categoryId;
  final String subCategoryId;

  _PremiumItem({
    required this.title,
    required this.brand,
    required this.priceText,
    required this.imageUrl,
    required this.groupId,
    required this.categoryId,
    required this.subCategoryId,
  });
}
