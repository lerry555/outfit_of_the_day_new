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
/// eventData != null -> outfit na konkrétnu udalosť z kalendára
class DailyOutfitScreen extends StatefulWidget {
  final bool isTomorrow;
  final Map<String, dynamic>? eventData;

  const DailyOutfitScreen({
    Key? key,
    required this.isTomorrow,
    this.eventData,
  }) : super(key: key);

  @override
  State<DailyOutfitScreen> createState() => _DailyOutfitScreenState();
}

class _DailyOutfitScreenState extends State<DailyOutfitScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  bool _isError = false;
  String? _errorMessage;

  String? _aiText;
  List<String> _outfitImages = [];

  List<Map<String, dynamic>> _wardrobe = [];
  Map<String, dynamic> _userPreferences = {};
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();

    final ui.Locale loc = ui.PlatformDispatcher.instance.locale;
    print(
        "🔥🔥 INIT STATE — SYSTEM LOCALE: ${loc.languageCode}-${loc.countryCode}");
    print(
        "🔥🔥 INIT STATE — ALL LOCALES: ${ui.PlatformDispatcher.instance.locales}");

    _loadDataAndGenerateOutfit();
  }

  /// Helper: konvertuje všetky Timestampy na ISO string,
  /// aby ich vedel jsonEncode() zakódovať.
  Map<String, dynamic> _normalizeMapForJson(Map<String, dynamic> data) {
    final result = <String, dynamic>{};

    data.forEach((key, value) {
      if (value is Timestamp) {
        result[key] = value.toDate().toIso8601String();
      } else if (value is Map<String, dynamic>) {
        result[key] = _normalizeMapForJson(value);
      } else if (value is List) {
        result[key] = value.map((e) {
          if (e is Timestamp) {
            return e.toDate().toIso8601String();
          } else if (e is Map<String, dynamic>) {
            return _normalizeMapForJson(e);
          } else {
            return e;
          }
        }).toList();
      } else {
        result[key] = value;
      }
    });

    return result;
  }

  Future<void> _loadDataAndGenerateOutfit() async {
    print("🔥🔥 FUNCTION STARTED: _loadDataAndGenerateOutfit()");

    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
        _isError = true;
        _errorMessage = 'Nie si prihlásený.';
      });
      return;
    }

    try {
      await Future.wait([
        _loadWardrobe(),
        _loadUserPreferences(),
        _loadLocation(),
      ]);

      if (!mounted) return;

      await _callStylistForOutfit();
    } catch (e) {
      debugPrint('Chyba v _loadDataAndGenerateOutfit: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isError = true;
        _errorMessage =
        'Nepodarilo sa načítať údaje pre outfit. Skús to prosím znova.';
      });
    }
  }

  Future<void> _loadWardrobe() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final snap = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('wardrobe')
          .get();

      final data = snap.docs.map((doc) {
        final raw = doc.data();
        final normalized =
        _normalizeMapForJson(Map<String, dynamic>.from(raw));
        normalized['id'] = doc.id;
        return normalized;
      }).toList();

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
      await _firestore.collection('userPreferences').doc(user.uid).get();
      if (doc.exists) {
        final raw = doc.data() ?? {};
        _userPreferences = _normalizeMapForJson(
          Map<String, dynamic>.from(raw),
        );
      } else {
        _userPreferences = {};
      }
    } catch (e) {
      debugPrint('Chyba pri načítaní userPreferences: $e');
      _userPreferences = {};
    }
  }

  Future<void> _loadLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
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
    } catch (e) {
      debugPrint('Chyba pri získavaní polohy: $e');
    }
  }

  Future<void> _callStylistForOutfit() async {
    final user = _auth.currentUser;
    final ui.Locale loc = ui.PlatformDispatcher.instance.locale;
    print(
        "🔥🔥🔥 SYSTEM LOCALE DETECTED: ${loc.languageCode}-${loc.countryCode}");
    print(
        "🔥🔥🔥 ALL LOCALES: ${ui.PlatformDispatcher.instance.locales}");
    print(
        "🔥🔥 ENTERED _callStylistForOutfit() — LANGUAGE CHECK RUNNING (eventData: ${widget.eventData})");

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

    // Ak máme udalosť z kalendára, outfit sa generuje špeciálne pre túto udalosť.
    String userQuery;
    if (widget.eventData != null) {
      final event = widget.eventData!;
      final String rawTitle = (event['title'] as String? ?? '').trim();
      final String location = (event['location'] as String? ?? '').trim();
      final String startTime = (event['startTime'] as String? ?? '').trim();
      final String endTime = (event['endTime'] as String? ?? '').trim();

      final String locationPart =
      location.isNotEmpty ? ' Miesto: $location.' : '';
      final String timePart = (startTime.isNotEmpty || endTime.isNotEmpty)
          ? ' Čas: ${startTime.isNotEmpty ? startTime : ''}'
          '${endTime.isNotEmpty ? ' – $endTime' : ''}.'
          : '';

      final String whenText =
      widget.isTomorrow ? 'Udalosť je zajtra.' : 'Udalosť je dnes.';

      userQuery =
      'Mám naplánovanú udalosť: "$rawTitle".$locationPart$timePart '
          'Text udalosti je napísaný používateľom a môže obsahovať chyby alebo slang. '
          'Prosím, pochop z neho, o aký typ udalosti ide (napr. svadba, rande, večera v reštaurácii, koncert, pracovné stretnutie...) '
          'a navrhni outfit vhodný konkrétne na túto udalosť podľa počasia a môjho šatníka. '
          'Ak je popis nejasný, sprav radšej konzervatívny, bezpečný odhad. '
          '$whenText';
    } else {
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
      'language':
      languageCode, // 🔥 ODTIAĽTO SA PRENESIE DO BACKENDU (LLM odpovie týmto jazykom)
    };

    // Extra info pre backend / AI: či ide o eventový outfit
    if (widget.eventData != null) {
      final event = widget.eventData!;
      body['isEventOutfit'] = true;
      body['eventContext'] = {
        'title': (event['title'] as String? ?? '').trim(),
        'location': (event['location'] as String? ?? '').trim(),
        'startTime': (event['startTime'] as String? ?? '').trim(),
        'endTime': (event['endTime'] as String? ?? '').trim(),
        'date': event['date'],
        'rawTitle': (event['title'] as String? ?? '').trim(),
      };
    } else {
      body['isEventOutfit'] = false;
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

      final data = jsonDecode(response.body) as Map<String, dynamic>? ??
          <String, dynamic>{};

      final text = data['text'] as String? ??
          'Pozrel som sa do tvojho šatníka a vybral som outfit, ale nepodarilo sa načítať detailný popis.';

      final outfitImagesDynamic =
          data['outfit_images'] as List<dynamic>? ?? [];
      final images = outfitImagesDynamic
          .map((item) => item is String ? item : null)
          .whereType<String>()
          .toList();

      setState(() {
        _isLoading = false;
        _isError = false;
        _errorMessage = null;
        _aiText = text;
        _outfitImages = images;
      });
    } catch (e) {
      debugPrint('Chyba pri volaní chatWithStylist: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isError = true;
        _errorMessage =
        'Ups, niečo sa pokazilo pri komunikácii s AI stylistom. Skús to neskôr znova.';
      });
    }
  }

  /// Jednoduché zobrazenie jedného kusu outfitu bez textového labelu.
  Widget _buildOutfitImage(String imageUrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 3 / 2,
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              color: Colors.grey.shade200,
              child: const Center(
                child: Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isEventOutfit = widget.eventData != null;
    final String title = isEventOutfit
        ? (widget.isTomorrow
        ? 'Outfit na zajtrajšiu udalosť'
        : 'Outfit na dnešnú udalosť')
        : (widget.isTomorrow ? 'Outfit na zajtra' : 'Dnešný outfit');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(),
      )
          : _isError
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _errorMessage ??
                'Stala sa chyba pri načítavaní outfitu.',
            textAlign: TextAlign.center,
          ),
        ),
      )
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            if (_outfitImages.isNotEmpty)
              ..._outfitImages
                  .map((url) => _buildOutfitImage(url))
                  .toList(),
            const SizedBox(height: 12),
            if (_aiText != null) ...[
              Text(
                'Prečo tento outfit:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _aiText!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      // TODO: uložiť outfit ako "OK, beriem" do Firestore (dailyOutfits)
                      Navigator.pop(context);
                    },
                    child: const Text('OK, beriem'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _isLoading = true;
                        _isError = false;
                        _errorMessage = null;
                        _aiText = null;
                        _outfitImages = [];
                      });
                      _loadDataAndGenerateOutfit();
                    },
                    child: const Text('Navrhni iný outfit'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
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
      ),
    );
  }
}
