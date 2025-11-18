// lib/screens/outfit_display_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

import 'package:outfitofTheDay/constants/app_constants.dart';

class OutfitDisplayScreen extends StatefulWidget {
  final Map<String, dynamic>? initialOutfitData;
  final double currentTemperature;
  final List<Map<String, dynamic>> wardrobeItems;
  final List<String> userPreferredStyles;
  final List<String> userFavoriteColors;
  final List<Map<String, dynamic>> likedOutfits;
  final List<Map<String, dynamic>> dislikedOutfits;
  final List<String> userDislikedColorCombinations;

  const OutfitDisplayScreen({
    Key? key,
    this.initialOutfitData,
    required this.currentTemperature,
    required this.wardrobeItems,
    required this.userPreferredStyles,
    required this.userFavoriteColors,
    required this.likedOutfits,
    required this.dislikedOutfits,
    required this.userDislikedColorCombinations,
  }) : super(key: key);

  @override
  _OutfitDisplayScreenState createState() => _OutfitDisplayScreenState();
}

class _OutfitDisplayScreenState extends State<OutfitDisplayScreen> {
  Map<String, dynamic>? _currentOutfit;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _user = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _currentOutfit = widget.initialOutfitData;
    if (_currentOutfit == null) {
      _generateOutfit(initial: true);
    }
  }

  Map<String, dynamic>? _selectSmartItem(
      List<Map<String, dynamic>> items,
      {String? requiredStyle,
        String? requiredCategoryPart,
        String? requiredSeason,
        List<String>? avoidColors}) {

    if (items.isEmpty) return null;

    final random = Random();

    List<Map<String, dynamic>> seasonalCandidates = items.where((item) {
      List<String> itemSeasons = List<String>.from(item['season'] ?? []);
      return itemSeasons.any((s) => s.toLowerCase() == requiredSeason?.toLowerCase() || s.toLowerCase() == 'celoročné');
    }).toList();

    if (seasonalCandidates.isEmpty) {
      seasonalCandidates = items;
    }

    final List<Map<String, dynamic>> scoredItems = seasonalCandidates.map((item) {
      double score = 1.0;

      if (widget.userFavoriteColors.isNotEmpty) {
        List<String> itemColors = List<String>.from(item['color'] ?? []);
        if (itemColors.any((c) => widget.userFavoriteColors.contains(c))) {
          score += 0.5;
        }
      }

      if (widget.userPreferredStyles.isNotEmpty) {
        List<String> itemStyles = List<String>.from(item['style'] ?? []);
        if (itemStyles.any((s) => widget.userPreferredStyles.contains(s))) {
          score += 0.5;
        }
      }

      final int wearCount = item['wearCount'] as int? ?? 0;
      if (wearCount < 5) {
        score += 0.5 * (1 - (wearCount / 5));
      }

      if (widget.userDislikedColorCombinations.isNotEmpty) {
        List<String> itemColors = List<String>.from(item['color'] ?? []);
        if (itemColors.any((c) => widget.userDislikedColorCombinations.contains(c))) {
          score -= 0.5;
        }
      }

      final Set<String> dislikedItemIds = widget.dislikedOutfits.expand((outfit) {
        List<dynamic> itemsInOutfit = outfit['outfitItems'] ?? [];
        return itemsInOutfit.map((item) => item['itemId'] as String).toSet();
      }).toSet();
      if (item['id'] != null && dislikedItemIds.contains(item['id'])) {
        score -= 2.0;
      }

      score = max(0.1, score);

      return {'item': item, 'score': score};
    }).toList();

    if (scoredItems.isEmpty) return null;

    final double totalScore = scoredItems.map((e) => e['score'] as double).reduce((a, b) => a + b);
    final List<double> probabilities = scoredItems.map((e) => (e['score'] as double) / totalScore).toList();

    double randomValue = random.nextDouble();
    double cumulativeProbability = 0.0;

    for (int i = 0; i < scoredItems.length; i++) {
      cumulativeProbability += probabilities[i];
      if (randomValue <= cumulativeProbability) {
        return scoredItems[i]['item'] as Map<String, dynamic>;
      }
    }

    scoredItems.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    return scoredItems.first['item'] as Map<String, dynamic>;
  }

  void _generateOutfit({bool initial = false, String? partToRegenerate}) {
    List<Map<String, dynamic>> availableTops = [];
    List<Map<String, dynamic>> availableBottoms = [];
    List<Map<String, dynamic>> availableFootwear = [];
    List<Map<String, dynamic>> availableOuterwear = [];

    List<Map<String, dynamic>> cleanWardrobeItems = widget.wardrobeItems.where((item) => item['isClean'] == true).toList();

    if (cleanWardrobeItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Váš šatník je prázdny alebo nič nie je čisté. Pre generovanie outfitu pridajte oblečenie.')),
      );
      Navigator.of(context).pop();
      return;
    }

    for (var item in cleanWardrobeItems) {
      String category = item['category'];
      String lowerCaseCategory = category.toLowerCase();

      if (['tričká', 'košele', 'blúzky', 'svetre', 'topy'].any((element) => lowerCaseCategory.contains(element.toLowerCase()))) {
        availableTops.add(item);
      } else if (['nohavice', 'kraťasy', 'sukne', 'šortky'].any((element) => lowerCaseCategory.contains(element.toLowerCase()))) {
        availableBottoms.add(item);
      } else if (['topánky', 'tenisky', 'sandále', 'lodičky'].any((element) => lowerCaseCategory.contains(element.toLowerCase()))) {
        availableFootwear.add(item);
      } else if (['bundy', 'kabáty', 'mikiny', 'saká'].any((element) => lowerCaseCategory.contains(element.toLowerCase()))) {
        availableOuterwear.add(item);
      }
    }

    // NOVÉ A OPRAVENÉ: Filrované zoznamy podľa sezóny
    String currentSeason = 'Celoročné';
    int month = DateTime.now().month;
    if (month >= 3 && month <= 5) {
      currentSeason = 'Jar';
    } else if (month >= 6 && month <= 8) {
      currentSeason = 'Leto';
    } else if (month >= 9 && month <= 11) {
      currentSeason = 'Jeseň';
    } else {
      currentSeason = 'Zima';
    }

    List<Map<String, dynamic>> filteredAvailableTops = availableTops.where((item) {
      List<String> itemSeasons = List<String>.from(item['season'] ?? []);
      return itemSeasons.any((s) => s.toLowerCase() == currentSeason.toLowerCase() || s.toLowerCase() == 'celoročné');
    }).toList();
    List<Map<String, dynamic>> filteredAvailableBottoms = availableBottoms.where((item) {
      List<String> itemSeasons = List<String>.from(item['season'] ?? []);
      return itemSeasons.any((s) => s.toLowerCase() == currentSeason.toLowerCase() || s.toLowerCase() == 'celoročné');
    }).toList();
    List<Map<String, dynamic>> filteredAvailableFootwear = availableFootwear.where((item) {
      List<String> itemSeasons = List<String>.from(item['season'] ?? []);
      return itemSeasons.any((s) => s.toLowerCase() == currentSeason.toLowerCase() || s.toLowerCase() == 'celoročné');
    }).toList();
    List<Map<String, dynamic>> filteredAvailableOuterwear = availableOuterwear.where((item) {
      List<String> itemSeasons = List<String>.from(item['season'] ?? []);
      return itemSeasons.any((s) => s.toLowerCase() == currentSeason.toLowerCase() || s.toLowerCase() == 'celoročné');
    }).toList();


    Map<String, dynamic>? selectedTop = _currentOutfit?['top'];
    Map<String, dynamic>? selectedBottom = _currentOutfit?['bottom'];
    Map<String, dynamic>? selectedFootwear = _currentOutfit?['footwear'];
    Map<String, dynamic>? selectedOuterwear = _currentOutfit?['outerwear'];

    String defaultAIStyle = 'Ležérny';

    if (widget.currentTemperature > 20) {
      selectedTop = _selectSmartItem(filteredAvailableTops, requiredStyle: defaultAIStyle, requiredSeason: currentSeason, avoidColors: widget.userDislikedColorCombinations);
      selectedBottom = _selectSmartItem(filteredAvailableBottoms, requiredStyle: defaultAIStyle, requiredCategoryPart: 'kraťasy', requiredSeason: currentSeason, avoidColors: widget.userDislikedColorCombinations);
      if (selectedBottom == null) selectedBottom = _selectSmartItem(filteredAvailableBottoms, requiredStyle: defaultAIStyle, requiredSeason: currentSeason, avoidColors: widget.userDislikedColorCombinations);
      selectedFootwear = _selectSmartItem(filteredAvailableFootwear, requiredStyle: defaultAIStyle, requiredCategoryPart: 'sandále', requiredSeason: currentSeason, avoidColors: widget.userDislikedColorCombinations);
      if (selectedFootwear == null) selectedFootwear = _selectSmartItem(filteredAvailableFootwear, requiredStyle: defaultAIStyle, requiredCategoryPart: 'tenisky', requiredSeason: currentSeason, avoidColors: widget.userDislikedColorCombinations);
      if (selectedFootwear == null) selectedFootwear = _selectSmartItem(filteredAvailableFootwear, requiredStyle: defaultAIStyle, requiredSeason: currentSeason, avoidColors: widget.userDislikedColorCombinations);
      selectedOuterwear = null;

    } else if (widget.currentTemperature > 10) {
      selectedTop = _selectSmartItem(filteredAvailableTops, requiredStyle: defaultAIStyle, requiredSeason: currentSeason, avoidColors: widget.userDislikedColorCombinations);
      selectedBottom = _selectSmartItem(filteredAvailableBottoms, requiredStyle: defaultAIStyle, requiredSeason: currentSeason, avoidColors: widget.userDislikedColorCombinations);
      selectedOuterwear = _selectSmartItem(filteredAvailableOuterwear, requiredStyle: defaultAIStyle, requiredCategoryPart: 'mikiny', requiredSeason: currentSeason, avoidColors: widget.userDislikedColorCombinations);
      if (selectedOuterwear == null) selectedOuterwear = _selectSmartItem(availableOuterwear, requiredStyle: defaultAIStyle, requiredCategoryPart: 'bundy', requiredSeason: currentSeason, avoidColors: widget.userDislikedColorCombinations);
      if (selectedOuterwear == null) selectedOuterwear = _selectSmartItem(availableOuterwear, requiredStyle: defaultAIStyle, requiredSeason: currentSeason, avoidColors: widget.userDislikedColorCombinations);

      selectedFootwear = _selectSmartItem(filteredAvailableFootwear, requiredStyle: defaultAIStyle, requiredCategoryPart: 'tenisky', requiredSeason: currentSeason, avoidColors: widget.userDislikedColorCombinations);
      if (selectedFootwear == null) selectedFootwear = _selectSmartItem(filteredAvailableFootwear, requiredStyle: defaultAIStyle, requiredSeason: currentSeason, avoidColors: widget.userDislikedColorCombinations);

    } else {
      selectedTop = _selectSmartItem(filteredAvailableTops, requiredStyle: defaultAIStyle, requiredSeason: currentSeason, avoidColors: widget.userDislikedColorCombinations);
      selectedBottom = _selectSmartItem(filteredAvailableBottoms, requiredStyle: defaultAIStyle, requiredSeason: currentSeason, avoidColors: widget.userDislikedColorCombinations);
      selectedFootwear = _selectSmartItem(filteredAvailableFootwear, requiredStyle: defaultAIStyle, requiredSeason: currentSeason, avoidColors: widget.userDislikedColorCombinations);
      if (selectedFootwear == null) selectedFootwear = _selectSmartItem(filteredAvailableFootwear, requiredStyle: defaultAIStyle, requiredCategoryPart: 'topánky', requiredSeason: currentSeason, avoidColors: widget.userDislikedColorCombinations);
      if (selectedFootwear == null) selectedFootwear = _selectSmartItem(filteredAvailableFootwear, requiredStyle: defaultAIStyle, requiredSeason: currentSeason, avoidColors: widget.userDislikedColorCombinations);
      selectedOuterwear = _selectSmartItem(filteredAvailableOuterwear, requiredStyle: defaultAIStyle, requiredCategoryPart: 'kabáty', requiredSeason: currentSeason, avoidColors: widget.userDislikedColorCombinations);
      if (selectedOuterwear == null) selectedOuterwear = _selectSmartItem(availableOuterwear, requiredStyle: defaultAIStyle, requiredCategoryPart: 'bundy', requiredSeason: currentSeason, avoidColors: widget.userDislikedColorCombinations);
      if (selectedOuterwear == null) selectedOuterwear = _selectSmartItem(availableOuterwear, requiredStyle: defaultAIStyle, requiredSeason: currentSeason, avoidColors: widget.userDislikedColorCombinations);
    }

    setState(() {
      _currentOutfit = {
        'top': selectedTop,
        'bottom': selectedBottom,
        'footwear': selectedFootwear,
        'outerwear': selectedOuterwear,
      };
    });

    if (!initial) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Outfit bol vygenerovaný!')),
      );
    }
  }

  Future<void> _recordOutfitFeedback(bool liked) async {
    if (_user == null || _currentOutfit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pre záznam spätnej väzby musí byť outfit vygenerovaný a používateľ prihlásený.')),
      );
      return;
    }

    List<Map<String, dynamic>> outfitItemsDetails = [];
    if (_currentOutfit!['top'] != null) {
      outfitItemsDetails.add({
        'itemId': _currentOutfit!['top']!['id'],
        'category': _currentOutfit!['top']!['category'],
        'color': _currentOutfit!['top']!['color'],
      });
    }
    if (_currentOutfit!['bottom'] != null) {
      outfitItemsDetails.add({
        'itemId': _currentOutfit!['bottom']!['id'],
        'category': _currentOutfit!['bottom']!['category'],
        'color': _currentOutfit!['bottom']!['color'],
      });
    }
    if (_currentOutfit!['footwear'] != null) {
      outfitItemsDetails.add({
        'itemId': _currentOutfit!['footwear']!['id'],
        'category': _currentOutfit!['footwear']!['category'],
        'color': _currentOutfit!['footwear']!['color'],
      });
    }
    if (_currentOutfit!['outerwear'] != null) {
      outfitItemsDetails.add({
        'itemId': _currentOutfit!['outerwear']!['id'],
        'category': _currentOutfit!['outerwear']!['category'],
        'color': _currentOutfit!['outerwear']!['color'],
      });
    }

    try {
      await _firestore.collection('users').doc(_user!.uid).collection('outfitFeedback').add({
        'outfitItems': outfitItemsDetails,
        'liked': liked,
        'timestamp': FieldValue.serverTimestamp(),
        'temperature': widget.currentTemperature,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Outfit bol označený ako: ${liked ? "Páči sa!" : "Nepáči sa."}')),
      );

      for (var item in outfitItemsDetails) {
        if (item['itemId'] != null) {
          final itemRef = _firestore.collection('users').doc(_user!.uid).collection('wardrobe').doc(item['itemId']);
          final doc = await itemRef.get();
          if (doc.exists) {
            final int currentWearCount = doc.data()?['wearCount'] ?? 0;
            await itemRef.update({'wearCount': currentWearCount + 1});
          }
        }
      }

      Navigator.of(context).pop();

    } catch (e) {
      print('Chyba pri ukladaní spätnej väzby: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba pri ukladaní spätnej väzby: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentOutfit == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Váš Outfit')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Váš Outfit Dňa'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Vygenerovať celý outfit znova',
            onPressed: () => _generateOutfit(partToRegenerate: 'all'),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFEFEBE9),
              Color(0xFFD7CCC8),
              Color(0xFFBCAAA4),
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('Teplota: ${widget.currentTemperature.toStringAsFixed(1)}°C', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text('Váš Outfit Dňa:', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),

              _buildOutfitGallery(),

              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.thumb_up, color: Colors.green, size: 36),
                    tooltip: 'Páči sa mi!',
                    onPressed: () => _recordOutfitFeedback(true),
                  ),
                  const SizedBox(width: 30),
                  IconButton(
                    icon: const Icon(Icons.thumb_down, color: Colors.red, size: 36),
                    tooltip: 'Nepáči sa mi.',
                    onPressed: () => _recordOutfitFeedback(false),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Späť na hlavnú obrazovku'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOutfitGallery() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildOutfitItem(
              label: 'Vrchný diel',
              itemData: _currentOutfit?['top'],
              onRegenerate: () => _generateOutfit(partToRegenerate: 'top'),
            ),
            _buildOutfitItem(
              label: 'Spodný diel',
              itemData: _currentOutfit?['bottom'],
              onRegenerate: () => _generateOutfit(partToRegenerate: 'bottom'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildOutfitItem(
              label: 'Vrchná vrstva',
              itemData: _currentOutfit?['outerwear'],
              onRegenerate: () => _generateOutfit(partToRegenerate: 'outerwear'),
            ),
            _buildOutfitItem(
              label: 'Obuv',
              itemData: _currentOutfit?['footwear'],
              onRegenerate: () => _generateOutfit(partToRegenerate: 'footwear'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOutfitItem({
    required String label,
    required Map<String, dynamic>? itemData,
    required VoidCallback onRegenerate,
  }) {
    final String imageUrl = itemData?['imageUrl'] as String? ?? '';
    final String itemCategory = itemData?['category'] as String? ?? '';
    final String itemColor = itemData?['color'] is List ? (itemData?['color'] as List).join('/') : itemData?['color'] as String? ?? '';

    return SizedBox(
      width: 150,
      child: Column(
        children: [
          Container(
            height: 150,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: imageUrl.isNotEmpty
                  ? Image.network(
                imageUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
                errorBuilder: (context, error, stackTrace) {
                  return const Center(child: Icon(Icons.broken_image, size: 50));
                },
              )
                  : Center(
                child: Text(
                  'Žiadny $label',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            itemCategory.isNotEmpty ? '$itemCategory ($itemColor)' : label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          ElevatedButton.icon(
            onPressed: onRegenerate,
            icon: const Icon(Icons.cached, size: 16),
            label: const Text('Zmeniť', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}