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

  // filter stavy
  final Map<String, String?> _selectedSubCategory = {};
  final Map<String, String?> _selectedSeasonFilter = {};
  final Map<String, String?> _selectedStyleFilter = {};
  final Map<String, String?> _selectedPatternFilter = {};

  bool _shouldShowSeasonFilter(String main, String? sub) {
    if (sub == null) return false;

    if (main == 'Vrch' && (sub == 'Bunda')) return true;
    if (main == 'Obuv' && sub == 'Topánky') return true;
    if (main == 'Doplnky' &&
        (sub == 'Čiapka' || sub == 'Šál' || sub == 'Rukavice')) return true;

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

    final List<String> _categories = categories;

    return DefaultTabController(
      length: _categories.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Môj Šatník'),
          bottom: TabBar(
            isScrollable: true,
            tabs: _categories.map((c) => Tab(text: c)).toList(),
          ),
        ),
        body: TabBarView(
          children: _categories.map((category) {
            final List<String> subList = subCategories[category] ?? [];
            final selectedSub = _selectedSubCategory[category];
            final selectedSeason = _selectedSeasonFilter[category];
            final selectedStyle = _selectedStyleFilter[category];
            final selectedPattern = _selectedPatternFilter[category];

            final bool showSeasonFilter =
                _shouldShowSeasonFilter(category, selectedSub);

            return Column(
              children: [
                // Podkategórie
                if (subList.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
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
                          ...subList.map(
                            (sub) => Padding(
                              padding: const EdgeInsets.only(left: 8),
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
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Sezóna
                if (showSeasonFilter)
                  Padding(
                    padding: const EdgeInsets.all(8),
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
                          ...seasons.map(
                            (s) => Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: ChoiceChip(
                                label: Text(s),
                                selected: selectedSeason == s,
                                onSelected: (_) {
                                  setState(() {
                                    _selectedSeasonFilter[category] = s;
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Štýl (iba ak máme subkategóriu)
                if (selectedSub != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                          ...styles.map(
                            (st) => Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: ChoiceChip(
                                label: Text(st),
                                selected: selectedStyle == st,
                                onSelected: (_) {
                                  setState(() {
                                    _selectedStyleFilter[category] = st;
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Pattern
                if (selectedSub != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                          ...patterns.map(
                            (pt) => Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: ChoiceChip(
                                label: Text(pt),
                                selected: selectedPattern == pt,
                                onSelected: (_) {
                                  setState(() {
                                    _selectedPatternFilter[category] = pt;
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Grid s oblečením
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
                            child: Text('Nastala chyba pri načítaní položiek.'));
                      }

                      List<QueryDocumentSnapshot> items =
                          snapshot.data?.docs ?? [];

                      // Filter 1 — podkategória
                      if (selectedSub != null) {
                        items = items.where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return data['category'] == selectedSub;
                        }).toList();
                      }

                      // Filter 2 — sezóna
                      if (selectedSeason != null) {
                        items = items.where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final dynamic s = data['season'];

                          if (s is String) return s == selectedSeason;
                          if (s is List) return s.contains(selectedSeason);
                          return false;
                        }).toList();
                      }

                      // Filter 3 — štýl
                      if (selectedStyle != null) {
                        items = items.where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final dynamic styleData = data['style'];

                          if (styleData is String) return styleData == selectedStyle;
                          if (styleData is List) {
                            return List<String>.from(styleData)
                                .contains(selectedStyle);
                          }
                          return false;
                        }).toList();
                      }

                      // Filter 4 — pattern
                      if (selectedPattern != null) {
                        items = items.where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final dynamic p = data['pattern'];

                          if (p is String) return p == selectedPattern;
                          if (p is List) {
                            return List<String>.from(p).contains(selectedPattern);
                          }
                          return false;
                        }).toList();
                      }

                      if (items.isEmpty) {
                        String msg = selectedSub == null
                            ? 'V kategórii "$category" nemáte žiadne oblečenie.'
                            : 'V podkategórii "$selectedSub" nemáte žiadne oblečenie.';

                        if (selectedSeason != null) {
                          msg += '\nFiltrované pre sezónu "$selectedSeason".';
                        }
                        if (selectedStyle != null) {
                          msg += '\nFiltrované pre štýl "$selectedStyle".';
                        }
                        if (selectedPattern != null) {
                          msg += '\nFiltrované pre vzor "$selectedPattern".';
                        }

                        return Center(
                          child: Text(
                            msg,
                            textAlign: TextAlign.center,
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
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.75,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final data =
                              items[index].data() as Map<String, dynamic>;
                          final imageUrl = data['imageUrl'] as String? ?? '';
                          final name = data['name'] as String? ?? 'Neznáma položka';

                          final categoryName = data['category'] as String? ?? '';
                          final seasonsList = _normalizeList(data['season']);

                          String subline = '';
                          if (categoryName.isNotEmpty &&
                              seasonsList.isNotEmpty) {
                            subline = '$categoryName • ${seasonsList.join(', ')}';
                          } else if (categoryName.isNotEmpty) {
                            subline = categoryName;
                          } else if (seasonsList.isNotEmpty) {
                            subline = seasonsList.join(', ');
                          }

                          return InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ClothingDetailScreen(
                                    clothingItemId: items[index].id,
                                    clothingItemData: data,
                                  ),
                                ),
                              );
                            },
                            child: Card(
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(12),
                                      ),
                                      child: imageUrl.isNotEmpty
                                          ? Image.network(
                                              imageUrl,
                                              fit: BoxFit.cover,
                                            )
                                          : Container(
                                              color: Colors.grey.shade200,
                                              child: const Icon(
                                                Icons.image_not_supported,
                                                size: 50,
                                              ),
                                            ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Text(
                                      name,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  if (subline.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          left: 8, right: 8, bottom: 8),
                                      child: Text(
                                        subline,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 12,
                                        ),
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
            );
          }).toList(),
        ),
      ),
    );
  }

  List<String> _normalizeList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.map((e) => e.toString()).toList();
    if (value is String && value.isNotEmpty) return [value];
    return [];
  }
}