// lib/screens/daily_outfit_screen.dart

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// Obrazovka, ktorá zobrazí outfit od AI stylistu
/// isTomorrow = false -> dnešný outfit
/// isTomorrow = true  -> zajtrajší outfit
class DailyOutfitScreen extends StatefulWidget {
  /// Ak je true, generuje sa outfit na zajtra. Inak na dnes.
  final bool isTomorrow;

  /// Ak je true, ide o outfit na konkrétnu udalosť (party, rande, práca...),
  /// nie len bežný deň.
  final bool isEvent;

  /// Názov udalosti, napr. "Vianočný večierok v práci".
  final String? eventTitle;

  /// Typ udalosti, napr. "party", "rande", "práca" (do budúcna z kalendára).
  final String? eventType;

  /// Dátum udalosti (dnes / zajtra), môžeme ho neskôr využiť v AI logike.
  final DateTime? eventDate;

  /// Miesto udalosti (mesto, podnik...), aby AI vedel lepšie odhadnúť kontext.
  final String? eventLocation;

  const DailyOutfitScreen({
    Key? key,
    required this.isTomorrow,
    this.isEvent = false,
    this.eventTitle,
    this.eventType,
    this.eventDate,
    this.eventLocation,
  }) : super(key: key);

  @override
  State<DailyOutfitScreen> createState() => _DailyOutfitScreenState();
}

class _DailyOutfitScreenState extends State<DailyOutfitScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  bool _isError = false;
  String _errorMessage = '';

  Map<String, dynamic> _userPreferences = {};
  List<Map<String, dynamic>> _wardrobe = [];
  Position? _currentPosition;

  String? _stylistResponse;
  List<String> _outfitImageUrls = [];
  List<Map<String, dynamic>> _chosenItems = [];

  @override
  void initState() {
    super.initState();
    _loadDataAndRequestOutfit();
  }

  Future<void> _loadDataAndRequestOutfit() async {
    setState(() {
      _isLoading = true;
      _isError = false;
      _errorMessage = '';
    });

    try {
      await _determinePosition();
      await _loadWardrobe();
      await _loadUserPreferences();
      await _requestOutfitFromStylist();
    } catch (e) {
      debugPrint('Chyba pri načítaní dát/outfitu: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isError = true;
          _errorMessage = 'Ups, niečo sa pokazilo pri načítaní outfitu.';
        });
      }
    }
  }

  Future<void> _determinePosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services disabled');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permission denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permission denied forever');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _currentPosition = position;
      debugPrint(
          '📍 Poloha: lat=${position.latitude}, lon=${position.longitude}');
    } catch (e) {
      debugPrint('Chyba pri zisťovaní polohy: $e');
    }
  }

  Future<void> _loadWardrobe() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final snapshot = await _firestore
          .collection('wardrobe')
          .doc(user.uid)
          .collection('items')
          .get();

      final data = snapshot.docs
          .map((doc) => {
                'id': doc.id,
                ...doc.data(),
              })
          .toList();

      _wardrobe = List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('Chyba pri načítaní šatníka: $e');
      _wardrobe = [];
    }
  }

  Future<void> _loadUserPreferences() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc =
          await _firestore.collection('users').doc(user.uid).get();

      if (doc.exists) {
        _userPreferences = doc.data() ?? {};
      }
    } catch (e) {
      debugPrint('Chyba pri načítaní preferencií: $e');
      _userPreferences = {};
    }
  }

  Future<void> _requestOutfitFromStylist() async {
    final user = _auth.currentUser;
    debugPrint("🔥 _requestOutfitFromStylist spustené — LANGUAGE CHECK RUNNING");

    if (user == null) return;

    if (_wardrobe.isEmpty) {
      setState(() {
        _isLoading = false;
        _isError = true;
        _errorMessage =
            'V šatníku zatiaľ nemáš žiadne oblečenie. Skús najprv pridať pár kúskov.';
      });
      return;
    }

    const String functionUrl =
        'https://us-central1-outfitoftheday-4d401.cloudfunctions.net/chatWithStylist';

    // ✨ Pripravíme správu pre AI podľa toho,
    // či ide o bežný deň alebo špeciálnu udalosť.
    late final String userQuery;

    if (widget.isEvent) {
      // Špeciálny mód pre udalosti – AI sa snaží vybrať skôr "vylepšený" outfit.
      final String whenText = widget.isTomorrow
          ? 'na zajtrajšiu špeciálnu udalosť'
          : 'na dnešnú špeciálnu udalosť';

      final String titlePart =
          (widget.eventTitle != null && widget.eventTitle!.trim().isNotEmpty)
              ? ' Udalosť: ${widget.eventTitle}.'
              : '';

      final String typePart =
          (widget.eventType != null && widget.eventType!.trim().isNotEmpty)
              ? ' Typ udalosti: ${widget.eventType}.'
              : '';

      final String locationPart = (widget.eventLocation != null &&
              widget.eventLocation!.trim().isNotEmpty)
          ? ' Miesto: ${widget.eventLocation}.'
          : '';

      userQuery =
          'Prosím, navrhni mi outfit $whenText podľa počasia a môjho šatníka.'
          '$titlePart$typePart$locationPart '
          'Outfit by mal pôsobiť vhodne na túto udalosť (môže byť o trochu viac štýlový alebo formálny, ak to dáva zmysel), '
          'ale stále musí byť praktický vzhľadom na počasie.';
    } else {
      // Pôvodné správanie pre bežný deň (dnes / zajtra)
      userQuery = widget.isTomorrow
          ? 'Prosím, navrhni mi outfit na zajtra podľa počasia a môjho šatníka. Ide o denný outfit na bežný deň.'
          : 'Prosím, navrhni mi outfit na dnešok od teraz do večera podľa počasia a môjho šatníka. Ide o dnešný bežný deň.';
    }

    // 👇 Zistenie jazyka priamo zo systému (Android/iOS), nie z lokalizácie appky
    final ui.Locale systemLocale = ui.PlatformDispatcher.instance.locale;
    final String languageCode =
        systemLocale.languageCode; // napr. "sk", "en", "de", "fr"...

    debugPrint(
        '📱 System locale: ${systemLocale.toLanguageTag()} | languageCode: $languageCode');

    final Map<String, dynamic> body = {
      'userQuery': userQuery,
      'wardrobe': _wardrobe,
      'userPreferences': _userPreferences,
      'isTomorrow': widget.isTomorrow,
      'isEvent': widget.isEvent,
      'language': languageCode, // 🔥 ODTIAĽTO SA PRENESIE DO BACKENDU
    };

    // Ak ide o špeciálnu udalosť, pošleme do backendu aj základné meta-dáta.
    if (widget.isEvent) {
      body['event'] = {
        'title': widget.eventTitle,
        'type': widget.eventType,
        'date': widget.eventDate?.toIso8601String(),
        'location': widget.eventLocation,
      };
    }

    if (_currentPosition != null) {
      body['location'] = {
        'latitude': _currentPosition!.latitude,
        'longitude': _currentPosition!.longitude,
      };
    }

    try {
      final response = await http.post(
        Uri.parse(functionUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (!mounted) return;

      if (response.statusCode != 200) {
        debugPrint(
            'chatWithStylist error: ${response.statusCode} – ${response.body}');
        setState(() {
          _isLoading = false;
          _isError = true;
          _errorMessage =
              'Stylista teraz neodpovedá (chyba ${response.statusCode}). Skús to prosím neskôr znova.';
        });
        return;
      }

      final data =
          jsonDecode(response.body) as Map<String, dynamic>? ??
              <String, dynamic>{};

      final text = data['text'] as String? ??
          'Pozrel som sa do tvojho šatníka a vybral som outfit, ale nepodarilo sa načítať detailný popis.';

      final outfitImagesDynamic =
          data['outfit_images'] as List<dynamic>? ?? [];
      final chosenItemsDynamic =
          data['chosen_items'] as List<dynamic>? ?? [];

      _outfitImageUrls = outfitImagesDynamic
          .whereType<String>()
          .toList();

      _chosenItems = chosenItemsDynamic
          .whereType<Map<String, dynamic>>()
          .toList();

      setState(() {
        _isLoading = false;
        _stylistResponse = text;
      });
    } catch (e) {
      debugPrint('Výnimka pri volaní chatWithStylist: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isError = true;
        _errorMessage =
            'Nepodarilo sa spojiť so stylistom. Skontroluj internet a skús znova.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String title = widget.isEvent
        ? (widget.isTomorrow ? 'Outfit na zajtrajšiu udalosť'
                             : 'Outfit na dnešnú udalosť')
        : (widget.isTomorrow ? 'Outfit na zajtra' : 'Dnešný outfit');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isError
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _errorMessage,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_stylistResponse != null) ...[
            Text(
              'Návrh od stylistu:',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _stylistResponse!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
          ],
          if (_outfitImageUrls.isNotEmpty) ...[
            Text(
              'Náhľad outfitu:',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _outfitImageUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final url = _outfitImageUrls[index];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      url,
                      fit: BoxFit.cover,
                      width: 160,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 160,
                          color: Colors.grey[300],
                          child: const Center(
                            child: Icon(Icons.broken_image),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_chosenItems.isNotEmpty) ...[
            Text(
              'Vybrané kúsky zo šatníka:',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Column(
              children: _chosenItems.map((item) {
                final name = item['name'] ?? 'Bez názvu';
                final category = item['category'] ?? 'Neznáma kategória';
                return ListTile(
                  leading: const Icon(Icons.check),
                  title: Text(name.toString()),
                  subtitle: Text(category.toString()),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () {
                // Neskôr: otvoriť chat so stylistom a odovzdať tento outfit
                Navigator.pop(context);
              },
              child: const Text('Upraviť outfit v chate'),
            ),
          ),
        ],
      ),
    );
  }
}