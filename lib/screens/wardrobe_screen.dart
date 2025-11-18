// lib/screens/wardrobe_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:outfitofTheDay/constants/app_constants.dart';
import 'package:outfitofTheDay/screens/clothing_detail_screen.dart';

class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({Key? key}) : super(key: key);

  @override
  _WardrobeScreenState createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance.currentUser;

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

    final List<String> _categories = const [
      'Tričká',
      'Košele',
      'Blúzky',
      'Svetre',
      'Topy',
      'Nohavice',
      'Kraťasy',
      'Sukne',
      'Šortky',
      'Topánky',
      'Tenisky',
      'Sandále',
      'Lodičky',
      'Bundy',
      'Kabáty',
      'Mikiny',
      'Saká',
      'Ostatné'
    ];

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
            return StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('users')
                  .doc(_auth!.uid)
                  .collection('wardrobe')
                  .where('category', isEqualTo: category)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return const Center(
                      child:
                      Text('Nastala chyba pri načítaní položiek.'));
                }

                final items = snapshot.data?.docs ?? [];

                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      'V kategórii "$category" nemáte žiadne oblečenie.',
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
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final itemData =
                    items[index].data() as Map<String, dynamic>;
                    final imageUrl = itemData['imageUrl'] as String? ?? '';
                    final isClean = itemData['isClean'] as bool? ?? true;
                    final colors = itemData['color'] is List
                        ? (itemData['color'] as List).join(', ')
                        : itemData['color'] as String? ?? 'Neznáma';
                    final itemId = items[index].id;
                    final name =
                        itemData['name'] as String? ?? 'Neznáma položka';

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
                                borderRadius: const BorderRadius.vertical(
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
                                    // debug výpis chyby
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
            );
          }).toList(),
        ),
      ),
    );
  }
}
