// lib/screens/wardrobe_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:outfitofTheDay/constants/app_constants.dart';
import 'package:outfitofTheDay/screens/clothing_detail_screen.dart';

// Podkategórie pre jednotlivé hlavné kategórie šatníka
const Map<String, List<String>> subCategories = {
  'Vrch': [
    'Tričko',
    'Košeľa',
    'Mikina',
    'Bunda',
    'Vesta',
    'Svetre',
    'Top',
  ],
  'Spodok': [
    'Tepláky',
    'Nohavice',
    'Kraťasy',
    'Legíny',
    'Sukňa',
  ],
  'Obuv': [
    'Tenisky',
    'Topánky',
    'Sandále',
    'Lodičky',
  ],
  'Doplnky': [
    'Čiapka',
    'Šál',
    'Rukavice',
    'Okuliare',
    'Opasok',
  ],
};

class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({Key? key}) : super(key: key);

  @override
  _WardrobeScreenState createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance.currentUser;

  // ktorá podkategória je vybraná pre každý hlavný tab (Vrch/Spodok/...)
  final Map<String, String?> _selectedSubCategory = {};

  // sezónny filter pre každý hlavný tab (Vrch/Spodok/...)
  // null = "Všetky sezóny"
  final Map<String, String?> _selectedSeasonFilter = {};

  // štýlový filter pre každý hlavný tab
  // null = "Všetky štýly"
  final Map<String, String?> _selectedStyleFilter = {};

  // pattern (vzor) filter pre každý hlavný tab
  // null = "Všetky vzory"
  final Map<String, String?> _selectedPatternFilter = {};

  Future<void> _openAddClothingDialog() async {
    // Placeholder na pridanie oblečenia
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Pridať oblečenie'),
          content: const Text('Tu by bol formulár na pridanie oblečenia.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Zrušiť'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Uložiť'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // Máme pri danej kombinácii main + sub zobraziť sezónny filter?
  bool _shouldShowSeasonFilter(String mainCategory, String? subCategory) {
    if (subCategory == null) return false;

    // Bundy / kabáty
    if (mainCategory == 'Vrch' &&
        (subCategory == 'Bunda' || subCategory == 'Kabát')) {
      return true;
    }

    // "ťažšia" obuv – topánky
    if (mainCategory == 'Obuv' && subCategory == 'Topánky') {
      return true;
    }

    // Zimné doplnky
    if (mainCategory == 'Doplnky' &&
        (subCategory == 'Čiapka' ||
            subCategory == 'Šál' ||
            subCategory == 'Rukavice')) {
      return true;
    }

    // všade inde sezóny nefiltrujeme
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_auth == null) {
      return const Scaffold(
        body: Center(
          child: Text('Pre zobrazenie šatníka sa musíte prihlásiť.'),
        ),
      );
    }

    // Hlavné kategórie: Vrch, Spodok, Obuv, Doplnky
    final List<String> _categories = categories;

    return DefaultTabController(
      length: _categories.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Môj Šatník'),
          bottom: TabBar(
            isScrollable: true,
            tabs: _categories.map((category) => Tab(text: category)).toList(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _openAddClothingDialog,
            ),
          ],
        ),
        body: TabBarView(
          children: _categories.map((category) {
            // Zoberieme zoznam podkategórií pre daný mainCategory (napr. Spodok -> Tepláky, Nohavice…)
            final List<String> subList = subCategories[category] ?? [];
            final String? selectedSub = _selectedSubCategory[category];
            final String? selectedSeason = _selectedSeasonFilter[category];
            final String? selectedStyle = _selectedStyleFilter[category];
            final String? selectedPattern = _selectedPatternFilter[category];

            final bool showSeasonFilter =
                _shouldShowSeasonFilter(category, selectedSub);

            return Column(
              children: [
                // Riadok s podkategóriami – zobrazí sa len ak nejaké sú
                if (subList.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8.0,
                      horizontal: 8.0,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          // Tlačidlo "Všetko"
                          ChoiceChip(
                            label: const Text('Všetko'),
                            selected: selectedSub == null,
                            onSelected: (_) {
                              setState(() {
                                _selectedSubCategory[category] = null;
                                _selectedSeasonFilter[category] = null;
                                _selectedStyleFilter[category] = null;
                                _selectedPatternFilter[category] = null;
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          // Tlačidlá pre každú podkategóriu
                          ...subList.map((sub) {
                            return Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: ChoiceChip(
                                label: Text(sub),
                                selected: selectedSub == sub,
                                onSelected: (_) {
                                  setState(() {
                                    _selectedSubCategory[category] = sub;
                                    _selectedSeasonFilter[category] = null;
                                    _selectedStyleFilter[category] = null;
                                    _selectedPatternFilter[category] = null;
                                  });
                                },
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  ),

                // Sezónny filter – len ak ide o bundy/topánky/zimné doplnky
                if (showSeasonFilter)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4.0,
                      horizontal: 8.0,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Všetky sezóny'),
                            selected: selectedSeason == null,
                            onSelected: (_) {
                              setState(() {
                                _selectedSeasonFilter[category] = null;
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          ...seasons.map((season) {
                            final bool selected = selectedSeason == season;
                            return Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: ChoiceChip(
                                label: Text(season),
                                selected: selected,
                                onSelected: (_) {
                                  setState(() {
                                    _selectedSeasonFilter[category] = season;
                                  });
                                },
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  ),

                // Štýlový filter – ukážeme, keď je vybraná nejaká podkategória
                if (selectedSub != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4.0,
                      horizontal: 8.0,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Všetky štýly'),
                            selected: selectedStyle == null,
                            onSelected: (_) {
                              setState(() {
                                _selectedStyleFilter[category] = null;
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          ...styles.map((style) {
                            final bool selected = selectedStyle == style;
                            return Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: ChoiceChip(
                                label: Text(style),
                                selected: selected,
                                onSelected: (_) {
                                  setState(() {
                                    _selectedStyleFilter[category] = style;
                                  });
                                },
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  ),

                // Pattern (vzor) filter – tiež pri vybratej podkategórii
                if (selectedSub != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4.0,
                      horizontal: 8.0,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Všetky vzory'),
                            selected: selectedPattern == null,
                            onSelected: (_) {
                              setState(() {
                                _selectedPatternFilter[category] = null;
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          ...patterns.map((pattern) {
                            final bool selected = selectedPattern == pattern;
                            return Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: ChoiceChip(
                                label: Text(pattern),
                                selected: selected,
                                onSelected: (_) {
                                  setState(() {
                                    _selectedPatternFilter[category] = pattern;
                                  });
                                },
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  ),

                // Samotný obsah – grid s oblečením
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('users')
                        .doc(_auth!.uid)
                        .collection('wardrobe')
                        .where('mainCategory', isEqualTo: category)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return const Center(
                          child: Text('Nastala chyba pri načítaní položiek.'),
                        );
                      }

                      final allItems = snapshot.data?.docs ?? [];

                      // 1. filter podľa podkategórie (Tričko / Bunda / ...)
                      List<QueryDocumentSnapshot> filteredItems;
                      if (selectedSub == null) {
                        filteredItems = allItems;
                      } else {
                        filteredItems = allItems.where((doc) {
                          final data =
                              doc.data() as Map<String, dynamic>;
                          final itemCategory =
                              data['category'] as String? ?? '';
                          return itemCategory == selectedSub;
                        }).toList();
                      }

                      // 2. filter podľa sezóny (Celoročne / Jar/Jeseň / Leto / Zima)
                      if (showSeasonFilter && selectedSeason != null) {
                        filteredItems = filteredItems.where((doc) {
                          final data =
                              doc.data() as Map<String, dynamic>;
                          final dynamic seasonData = data['season'];

                          if (seasonData is List) {
                            final seasonsList =
                                List<String>.from(seasonData);
                            return seasonsList.contains(selectedSeason);
                          } else if (seasonData is String) {
                            return seasonData == selectedSeason;
                          }
                          return false;
                        }).toList();
                      }

                      // 3. filter podľa štýlu
                      if (selectedStyle != null) {
                        filteredItems = filteredItems.where((doc) {
                          final data =
                              doc.data() as Map<String, dynamic>;
                          final dynamic styleData = data['style'];
                          if (styleData is List) {
                            final stylesList =
                                List<String>.from(styleData);
                            return stylesList.contains(selectedStyle);
                          } else if (styleData is String) {
                            return styleData == selectedStyle;
                          }
                          return false;
                        }).toList();
                      }

                      // 4. filter podľa vzoru (pattern)
                      if (selectedPattern != null) {
                        filteredItems = filteredItems.where((doc) {
                          final data =
                              doc.data() as Map<String, dynamic>;
                          final dynamic patternData = data['pattern'];
                          if (patternData is List) {
                            final patternsList =
                                List<String>.from(patternData);
                            return patternsList.contains(selectedPattern);
                          } else if (patternData is String) {
                            return patternData == selectedPattern;
                          }
                          return false;
                        }).toList();
                      }

                      if (filteredItems.isEmpty) {
                        String base = '';
                        if (selectedSub == null) {
                          base = 'V kategórii "$category"';
                        } else {
                          base = 'V podkategórii "$selectedSub"';
                        }

                        if (showSeasonFilter && selectedSeason != null) {
                          base += ' a sezóne "$selectedSeason"';
                        }

                        if (selectedStyle != null) {
                          base += ' a štýle "$selectedStyle"';
                        }

                        if (selectedPattern != null) {
                          base += ' a vzore "$selectedPattern"';
                        }

                        return Center(
                          child: Text(
                            '$base nemáte žiadne oblečenie.',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.color
                                  ?.withOpacity(0.6),
                            ),
                          ),
                        );
                      }

                      return GridView.builder(
                        padding: const EdgeInsets.all(16.0),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16.0,
                          mainAxisSpacing: 16.0,
                          childAspectRatio: 0.75,
                        ),
                        itemCount: filteredItems.length,
                        itemBuilder: (context, index) {
                          final itemData = filteredItems[index].data()
                              as Map<String, dynamic>;
                          final imageUrl =
                              itemData['imageUrl'] as String? ?? '';
                          final colorsText = itemData['color'] is List
                              ? (itemData['color'] as List).join(', ')
                              : itemData['color'] as String? ?? 'Neznáma';
                          final itemId = filteredItems[index].id;
                          final name =
                              itemData['name'] as String? ?? 'Neznáma položka';

                          // kategória (Tričko, Bunda, Tepláky…)
                          final itemCategory =
                              itemData['category'] as String? ?? '';

                          // sezóny – môžu byť uložené ako list alebo string
                          final dynamic seasonData = itemData['season'];
                          String seasonText = '';
                          if (seasonData is List) {
                            seasonText =
                                List<String>.from(seasonData).join(', ');
                          } else if (seasonData is String) {
                            seasonText = seasonData;
                          }

                          // štýl – list alebo string
                          final dynamic styleData = itemData['style'];
                          String styleText = '';
                          if (styleData is List) {
                            styleText =
                                List<String>.fro',
    'Top',
  ],
  'Spodok': [
    'Tepláky',
    'Nohavice',
    'Kraťasy',
    'Legíny',
    'Sukňa',
  ],
  'Obuv': [
    'Tenisky',
    'Topánky',
    'Sandále',
    'Lodičky',
  ],
  'Doplnky': [
    'Čiapka',
    'Šál',
    'Rukavice',
    'Okuliare',
    'Opasok',
  ],
};

class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({Key? key}) : super(key: key);

  @override
  _WardrobeScreenState createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance.currentUser;

  // ktorá podkategória je vybraná pre každý hlavný tab (Vrch/Spodok/...)
  final Map<String, String?> _selectedSubCategory = {};

  // sezónny filter pre každý hlavný tab (Vrch/Spodok/...)
  // null = "Všetky"
  final Map<String, String?> _selectedSeasonFilter = {};

  Future<void> _openAddClothingDialog() async {
    // Placeholder na pridanie oblečenia
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Pridať oblečenie'),
          content: const Text('Tu by bol formulár na pridanie oblečenia.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Zrušiť'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Uložiť'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // Máme pri danej kombinácii main + sub zobraziť sezónny filter?
  bool _shouldShowSeasonFilter(String mainCategory, String? subCategory) {
    if (subCategory == null) return false;

    // Bundy / kabáty
    if (mainCategory == 'Vrch' &&
        (subCategory == 'Bunda' || subCategory == 'Kabát')) {
      return true;
    }

    // "ťažšia" obuv – topánky
    if (mainCategory == 'Obuv' && subCategory == 'Topánky') {
      return true;
    }

    // Zimné doplnky
    if (mainCategory == 'Doplnky' &&
        (subCategory == 'Čiapka' ||
            subCategory == 'Šál' ||
            subCategory == 'Rukavice')) {
      return true;
    }

    // všade inde sezóny nefiltrujeme
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_auth == null) {
      return const Scaffold(
        body: Center(
          child: Text('Pre zobrazenie šatníka sa musíte prihlásiť.'),
        ),
      );
    }

    // Hlavné kategórie: Vrch, Spodok, Obuv, Doplnky
    final List<String> _categories = categories;

    return DefaultTabController(
      length: _categories.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Môj Šatník'),
          bottom: TabBar(
            isScrollable: true,
            tabs: _categories.map((category) => Tab(text: category)).toList(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _openAddClothingDialog,
            ),
          ],
        ),
        body: TabBarView(
          children: _categories.map((category) {
            // Zoberieme zoznam podkategórií pre daný mainCategory (napr. Spodok -> Tepláky, Nohavice…)
            final List<String> subList = subCategories[category] ?? [];
            final String? selectedSub = _selectedSubCategory[category];
            final String? selectedSeason = _selectedSeasonFilter[category];

            final bool showSeasonFilter =
                _shouldShowSeasonFilter(category, selectedSub);

            return Column(
              children: [
                // Riadok s podkategóriami – zobrazí sa len ak nejaké sú
                if (subList.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8.0,
                      horizontal: 8.0,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          // Tlačidlo "Všetko"
                          ChoiceChip(
                            label: const Text('Všetko'),
                            selected: selectedSub == null,
                            onSelected: (_) {
                              setState(() {
                                _selectedSubCategory[category] = null;
                                // ak zrušíme podkategóriu, sezónny filter tiež nedáva zmysel
                                _selectedSeasonFilter[category] = null;
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          // Tlačidlá pre každú podkategóriu
                          ...subList.map((sub) {
                            return Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: ChoiceChip(
                                label: Text(sub),
                                selected: selectedSub == sub,
                                onSelected: (_) {
                                  setState(() {
                                    _selectedSubCategory[category] = sub;
                                    // pri zmene podkategórie resetneme sezónny filter na "Všetky"
                                    _selectedSeasonFilter[category] = null;
                                  });
                                },
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  ),

                // Sezónny filter – len ak ide o bundy/topánky/zimné doplnky
                if (showSeasonFilter)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4.0,
                      horizontal: 8.0,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Všetky'),
                            selected: selectedSeason == null,
                            onSelected: (_) {
                              setState(() {
                                _selectedSeasonFilter[category] = null;
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          ...seasons.map((season) {
                            final bool selected = selectedSeason == season;
                            return Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: ChoiceChip(
                                label: Text(season),
                                selected: selected,
                                onSelected: (_) {
                                  setState(() {
                                    _selectedSeasonFilter[category] = season;
                                  });
                                },
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  ),

                // Samotný obsah – grid s oblečením
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('users')
                        .doc(_auth!.uid)
                        .collection('wardrobe')
                        .where('mainCategory', isEqualTo: category)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return const Center(
                          child: Text('Nastala chyba pri načítaní položiek.'),
                        );
                      }

                      final allItems = snapshot.data?.docs ?? [];

                      // 1. filter podľa podkategórie (Tričko / Bunda / ...)
                      List<QueryDocumentSnapshot> filteredItems;
                      if (selectedSub == null) {
                        filteredItems = allItems;
                      } else {
                        filteredItems = allItems.where((doc) {
                          final data =
                              doc.data() as Map<String, dynamic>;
                          final itemCategory =
                              data['category'] as String? ?? '';
                          return itemCategory == selectedSub;
                        }).toList();
                      }

                      // 2. filter podľa sezóny (Celoročne / Jar/Jeseň / Leto / Zima)
                      if (showSeasonFilter && selectedSeason != null) {
                        filteredItems = filteredItems.where((doc) {
                          final data =
                              doc.data() as Map<String, dynamic>;
                          final dynamic seasonData = data['season'];

                          if (seasonData is List) {
                            final seasonsList =
                                List<String>.from(seasonData);
                            return seasonsList.contains(selectedSeason);
                          } else if (seasonData is String) {
                            return seasonData == selectedSeason;
                          }
                          return false;
                        }).toList();
                      }

                      if (filteredItems.isEmpty) {
                        String base = '';
                        if (selectedSub == null) {
                          base = 'V kategórii "$category"';
                        } else {
                          base = 'V podkategórii "$selectedSub"';
                        }

                        if (showSeasonFilter && selectedSeason != null) {
                          base += ' pre sezónu "$selectedSeason"';
                        }

                        return Center(
                          child: Text(
                            '$base nemáte žiadne oblečenie.',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.color
                                  ?.withOpacity(0.6),
                            ),
                          ),
                        );
                      }

                      return GridView.builder(
                        padding: const EdgeInsets.all(16.0),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16.0,
                          mainAxisSpacing: 16.0,
                          childAspectRatio: 0.75,
                        ),
                        itemCount: filteredItems.length,
                        itemBuilder: (context, index) {
                          final itemData = filteredItems[index].data()
                              as Map<String, dynamic>;
                          final imageUrl =
                              itemData['imageUrl'] as String? ?? '';
                          final isClean =
                              itemData['isClean'] as bool? ?? true;
                          final colors = itemData['color'] is List
                              ? (itemData['color'] as List).join(', ')
                              : itemData['color'] as String? ?? 'Neznáma';
                          final itemId = filteredItems[index].id;
                          final name =
                              itemData['name'] as String? ?? 'Neznáma položka';

                          // kategória (Tričko, Bunda, Tepláky…)
                          final itemCategory =
                              itemData['category'] as String? ?? '';

                          // sezóny – môžu byť uložené ako list alebo string
                          final dynamic seasonData = itemData['season'];
                          String seasonText = '';
                          if (seasonData is List) {
                            seasonText =
                                List<String>.from(seasonData).join(', ');
                          } else if (seasonData is String) {
                            seasonText = seasonData;
                          }

                          // Text v štýle "Bunda • Zima" alebo len "Bunda" / len sezóna
                          String categoryLine = '';
                          if (itemCategory.isNotEmpty &&
                              seasonText.isNotEmpty) {
                            categoryLine = '$itemCategory • $seasonText';
                          } else if (itemCategory.isNotEmpty) {
                            categoryLine = itemCategory;
                          } else if (seasonText.isNotEmpty) {
                            categoryLine = seasonText;
                          }

                          return InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ClothingDetailScreen(
                                    clothingItemId: itemId,
                                    clothingItemData: itemData,
                                  ),
                                ),
                              );
                            },
                            child: Card(
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.0),
                                side: BorderSide(
                                  color: isClean
                                      ? Colors.green.shade400
                                      : Colors.red.shade400,
                                  width: 2.0,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius:
                                          const BorderRadius.vertical(
                                        top: Radius.circular(12.0),
                                      ),
                                      child: imageUrl.isNotEmpty
                                          ? Image.network(
                                              imageUrl,
                                              fit: BoxFit.cover,
                                              loadingBuilder: (context, child,
                                                  loadingProgress) {
                                                if (loadingProgress == null) {
                                                  return child;
                                                }
                                                return Center(
                                                  child:
                                                      CircularProgressIndicator(
                                                    value: loadingProgress
                                                                .expectedTotalBytes !=
                                                            null
                                                        ? loadingProgress
                                                                .cumulativeBytesLoaded /
                                                            loadingProgress
                                                                .expectedTotalBytes!
                                                        : null,
                                                  ),
                                                );
                                              },
                                              errorBuilder: (context, error,
                                                  stackTrace) {
                                                debugPrint(
                                                    'Image error: $error');

                                                return Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    const Icon(
                                                      Icons.broken_image,
                                                      size: 40,
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      '$error',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                        fontSize: 8,
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              },
                                            )
                                          : const Center(
                                              child: Icon(
                                                Icons.image_not_supported,
                                                size: 50,
                                                color: Colors.grey,
                                              ),
                                            ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8.0,
                                      vertical: 4.0,
                                    ),
                                    child: Text(
                                      name,
                                      style: const TextStyle(
            