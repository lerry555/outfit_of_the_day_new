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

  // Tu si pamätáme, ktorá podkategória je vybraná pre každý hlavný "tab"
  final Map<String, String?> _selectedSubCategory = {};

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

                      // Ak je vybraná podkategória, filtrujeme podľa field-u "category"
                      final filteredItems = selectedSub == null
                          ? allItems
                          : allItems.where((doc) {
                        final data =
                        doc.data() as Map<String, dynamic>;
                        final itemCategory =
                            data['category'] as String? ?? '';
                        return itemCategory == selectedSub;
                      }).toList();

                      if (filteredItems.isEmpty) {
                        final emptyText = selectedSub == null
                            ? 'V kategórii "$category" nemáte žiadne oblečenie.'
                            : 'V podkategórii "$selectedSub" nemáte žiadne oblečenie.';

                        return Center(
                          child: Text(
                            emptyText,
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

                          // ➜ kategória (Tričko, Bunda, Tepláky…)
                          final itemCategory =
                              itemData['category'] as String? ?? '';

                          // ➜ typ sezóny (letná / prechodná / zimná) – zatiaľ dobrovoľné
                          final seasonType =
                          itemData['seasonType'] as String?;
                          String seasonLabel = '';
                          switch (seasonType) {
                            case 'winter':
                              seasonLabel = 'Zimná';
                              break;
                            case 'mid':
                              seasonLabel = 'Prechodná';
                              break;
                            case 'summer':
                              seasonLabel = 'Letná';
                              break;
                            default:
                              seasonLabel = '';
                          }

                          // Text v štýle "Bunda • Zimná" alebo len "Bunda"
                          final String categoryLine = seasonLabel.isNotEmpty
                              ? '$itemCategory • $seasonLabel'
                              : itemCategory;

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
                                          fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  // ➜ tu zobrazíme "Bunda • Zimná" alebo podobne
                                  if (categoryLine.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8.0,
                                      ),
                                      child: Text(
                                        categoryLine,
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontSize: 12,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8.0,
                                      vertical: 4.0,
                                    ),
                                    child: Text(
                                      colors,
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Row(
                                    mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            left: 8.0),
                                        child: Text(
                                          isClean ? 'Čisté' : 'Špinavé',
                                          style: TextStyle(
                                            color: isClean
                                                ? Colors.green.shade700
                                                : Colors.red.shade700,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          isClean
                                              ? Icons.check_circle
                                              : Icons.warning,
                                          color: isClean
                                              ? Colors.green
                                              : Colors.red,
                                        ),
                                        onPressed: () async {
                                          try {
                                            await _firestore
                                                .collection('users')
                                                .doc(_auth!.uid)
                                                .collection('wardrobe')
                                                .doc(itemId)
                                                .update(
                                              {'isClean': !isClean},
                                            );
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Položka označená ako ${isClean ? 'špinavá' : 'čistá'}.',
                                                ),
                                              ),
                                            );
                                          } catch (e) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Chyba pri aktualizácii stavu: ${e.toString()}',
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                        tooltip: isClean
                                            ? 'Označ ako špinavé'
                                            : 'Označ ako čisté',
                                      ),
                                    ],
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
}
