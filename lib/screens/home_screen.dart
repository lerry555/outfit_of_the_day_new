// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:dio/dio.dart'; // ZMENA: importujeme knižnicu dio
import 'dart:convert';
import 'stylist_chat_screen.dart';
import 'wardrobe_screen.dart';
import 'add_clothing_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _currentAddress;
  Position? _currentPosition;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();
  final List<Map<String, dynamic>> _outfits = [];
  final Dio _dio = Dio(); // NOVÉ: Inštancia dio klienta

  @override
  void initState() {
    super.initState();
    _checkPermissionAndGetCurrentLocation();
    _loadOutfits();
  }

  Future<void> _checkPermissionAndGetCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Služby určovania polohy sú vypnuté.')),
      );
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Povolenia na určovanie polohy sú zamietnuté.')),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Povolenia na určovanie polohy sú natrvalo zamietnuté, nemôžeme žiadať o povolenie.')),
      );
      return;
    }

    Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
        .then((Position position) {
      setState(() {
        _currentPosition = position;
      });
      print('Aktuálna poloha: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
    })
        .catchError((e) {
      print(e);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nepodarilo sa získať polohu. Skúste to prosím znova.')),
      );
    });
  }

  Future<void> _loadOutfits() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final querySnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('outfitFeedback')
          .where('liked', isEqualTo: true)
          .orderBy('timestamp', descending: true)
          .limit(10)
          .get();

      setState(() {
        _outfits.clear();
        for (var doc in querySnapshot.docs) {
          _outfits.add(doc.data());
        }
        print('Šatník načítaný: ${_outfits.length} položiek.');
      });
    } catch (e) {
      print('Chyba pri načítaní spätnej väzby: $e');
    }
  }

  // PÔVODNÁ FUNKCIA NA NAHRANIE OBRÁZKA (UPRAVENÁ)
  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      _uploadAndAnalyzeImage(File(pickedFile.path));
    }
  }

  // NOVÁ FUNKCIA NA NAHRATIE A ANALÝZU OBRÁZKA
  Future<void> _uploadAndAnalyzeImage(File image) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pre nahrávanie obrázka sa musíte prihlásiť.')),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nahrávam obrázok a analyzujem...')),
      );

      final fileName = 'outfits/${user.uid}/${DateTime.now().toIso8601String()}.png';
      final storageRef = _storage.ref().child(fileName);

      await storageRef.putFile(image);
      final downloadUrl = await storageRef.getDownloadURL();

      // ZMENA: Volanie novej Firebase funkcie na analýzu obrázka pomocou dio
      const String analyzeFunctionUrl =
          'https://us-central1-outfitoftheday-4d401.cloudfunctions.net/analyzeClothingImage';
      ;
      final response = await _dio.post(
        analyzeFunctionUrl,
        data: {
          'imageUrl': downloadUrl,
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> aiData = response.data;

        // Prechod na obrazovku na pridanie oblečenia s predvyplnenými údajmi
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AddClothingScreen(
              initialData: aiData,
              imageUrl: downloadUrl,
            ),
          ),
        );
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Analýza úspešná. Skontrolujte a uložte dáta.')),
        );
      } else {
        throw Exception('Chyba pri analýze obrázka: ${response.data}');
      }
    } catch (e) {
      print('Chyba pri nahrávaní alebo analýze obrázka: $e');
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba pri nahrávaní alebo analýze obrázka: ${e.toString()}')),
      );
    }
  }

  // NOVÁ METÓDA NA PRIDANIE DÁT DO ŠATNÍKA
  Future<void> _addSampleWardrobe() async {
    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pre pridanie šatníka sa musíte prihlásiť.')),
      );
      return;
    }

    final List<Map<String, dynamic>> sampleWardrobeItems = [
      {'name': 'Modré tričko', 'type': 'tričko', 'color': 'modrá', 'style': 'ležérny', 'category': 'Tričká', 'imageUrl': 'https://example.com/modre_tricko.jpg'},
      {'name': 'Biela košeľa', 'type': 'košeľa', 'color': 'biela', 'style': 'elegantný', 'category': 'Košele', 'imageUrl': 'https://example.com/biela_kosela.jpg'},
      {'name': 'Modré džínsy', 'type': 'nohavice', 'color': 'modrá', 'style': 'ležérny', 'category': 'Nohavice', 'imageUrl': 'https://example.com/modre_dzinsy.jpg'},
      {'name': 'Čierne nohavice', 'type': 'nohavice', 'color': 'čierna', 'style': 'elegantný', 'category': 'Nohavice', 'imageUrl': 'https://example.com/cierne_nohavice.jpg'},
      {'name': 'Biele tenisky', 'type': 'topánky', 'color': 'biela', 'style': 'športový', 'category': 'Topánky', 'imageUrl': 'https://example.com/biele_tenisky.jpg'},
      {'name': 'Hnedé poltopánky', 'type': 'topánky', 'color': 'hnedá', 'style': 'elegantný', 'category': 'Topánky', 'imageUrl': 'https://example.com/hnede_poltopanky.jpg'},
    ];
    final Map<String, dynamic> samplePreferences = {
      'favColor': 'modrá',
      'favStyle': 'ležérny',
    };

    try {
      await _firestore.collection('users').doc(user.uid).set({
        'userPreferences': samplePreferences,
      }, SetOptions(merge: true));

      final wardrobeCollection = _firestore.collection('users').doc(user.uid).collection('wardrobe');
      for (var item in sampleWardrobeItems) {
        await wardrobeCollection.add(item);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vzorový šatník bol úspešne pridaný!')),
      );
    } catch (e) {
      print('Chyba pri pridávaní vzorového šatníka: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chyba pri pridávaní vzorového šatníka.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Outfit of the Day'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _auth.signOut();
              if (mounted) {
                // Navigácia späť na úvodnú obrazovku po odhlásení
              }
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('Vitajte v aplikácii Outfit of the Day!'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _pickImage(ImageSource.gallery),
              child: const Text('Nahrať fotku z galérie'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () => _pickImage(ImageSource.camera),
              child: const Text('Odfotiť outfit'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const StylistChatScreen(),
                  ),
                );
              },
              child: const Text('Poradiť sa s AI stylistom'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const WardrobeScreen(),
                  ),
                );
              },
              child: const Text('Môj šatník'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _addSampleWardrobe,
              child: const Text('Pridať vzorový šatník'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            ),
          ],
        ),
      ),
    );
  }
}