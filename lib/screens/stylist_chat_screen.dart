// lib/screens/stylist_chat_screen.dart

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

/// Jednoduchý model správy v chate ( text + obrázky + info či je to užívateľ )
class Message {
  final String text;
  final List<String> imageUrls;
  final bool isUser;

  Message({
    required this.text,
    this.imageUrls = const [],
    required this.isUser,
  });
}

class StylistChatScreen extends StatefulWidget {
  /// Voliteľný počiatočný prompt, ktorý môžeme poslať automaticky (napr. "outfit na dnes")
  final String? initialPrompt;

  /// Ak je true a initialPrompt nie je null → správa sa odošle automaticky po načítaní dát
  final bool autoSendInitialPrompt;

  /// Dáta o konkrétnom kúsku, o ktorom sa ideme radiť (napr. z "Poradiť sa o tomto kúsku")
  final Map<String, dynamic>? initialItemData;

  const StylistChatScreen({
    Key? key,
    this.initialPrompt,
    this.autoSendInitialPrompt = false,
    this.initialItemData,
  }) : super(key: key);

  @override
  State<StylistChatScreen> createState() => _StylistChatScreenState();
}

class _StylistChatScreenState extends State<StylistChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isSending = false;
  bool _isLoadingData = true;

  List<Message> _messages = [];
  List<Map<String, dynamic>> _wardrobe = [];

  Position? _currentPosition;
  Map<String, dynamic>? _currentWeather; // zatiaľ voliteľné / budúce použitie

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    try {
      await Future.wait([
        _loadWardrobeFromFirestore(),
        _loadLocationAndMaybeWeather(),
      ]);
    } catch (e) {
      debugPrint('Chyba pri init dát: $e');
    }

    setState(() {
      _isLoadingData = false;
    });

    // 🧥 Ak prišiel konkrétny kúsok (napr. z "Poradiť sa o tomto kúsku"),
    // ukážeme ho hneď na začiatku – AI správa + fotka
    if (widget.initialItemData != null) {
      final item = widget.initialItemData!;
      final String imageUrl = (item['imageUrl'] as String?) ?? '';
      final String name = (item['name'] as String?) ?? '';
      final String mainCategory = (item['mainCategory'] as String?) ?? '';
      final String category = (item['category'] as String?) ?? '';

      final buffer = StringBuffer();
      buffer.writeln('Toto je kúsok, o ktorom sa ideme rozprávať.');

      if (name.isNotEmpty) buffer.writeln('Názov: $name.');
      if (mainCategory.isNotEmpty) buffer.writeln('Kategória: $mainCategory.');
      if (category.isNotEmpty) buffer.writeln('Typ: $category.');

      buffer.writeln('Čo by si chcel vedieť o tomto kúsku?');

      _addMessage(
        Message(
          text: buffer.toString(),
          imageUrls: imageUrl.isNotEmpty ? [imageUrl] : const [],
          isUser: false,
        ),
      );
    }

    // Ak prišiel initialPrompt a máme ho poslať automaticky (napr. z iného miesta)
    if (widget.initialPrompt != null && widget.autoSendInitialPrompt) {
      Future.microtask(() {
        _handleSubmitted(widget.initialPrompt!.trim());
      });
    }
  }

  Future<void> _loadWardrobeFromFirestore() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('wardrobe')
          .get();

      final data = snapshot.docs.map((doc) {
        final d = doc.data();
        d['id'] = doc.id;
        return d;
      }).toList();

      _wardrobe = List<Map<String, dynamic>>.from(data);
      debugPrint('Šatník načítaný: ${_wardrobe.length} položiek');
    } catch (e) {
      debugPrint('Chyba pri načítaní šatníka: $e');
      _wardrobe = [];
    }
  }

  Future<void> _loadLocationAndMaybeWeather() async {
    bool serviceEnabled;
    LocationPermission permission;

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services disabled');
        return;
      }

      permission = await Geolocator.checkPermission();
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

      // TODO: zavolať Cloud Function / OpenWeather a uložiť do _currentWeather
    } catch (e) {
      debugPrint('Chyba pri získavaní polohy: $e');
    }
  }

  void _addMessage(Message message) {
    setState(() {
      _messages.add(message);
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 60,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _handleSubmitted(String text) async {
    if (text.isEmpty || _isSending) return;

    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nie si prihlásený.')),
      );
      return;
    }

    _textController.clear();
    _addMessage(Message(text: text, isUser: true));

    setState(() {
      _isSending = true;
    });

    try {
      final response = await _callStylistApi(
        userMessage: text,
        wardrobe: _wardrobe,
        position: _currentPosition,
        weather: _currentWeather,
      );

      final replyText = response['replyText'] as String? ??
          'Prepáč, teraz sa mi trochu zauzlili módne myšlienky. Skús to prosím ešte raz neskôr. 💫';

      final imageUrls = (response['imageUrls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      _addMessage(
        Message(text: replyText, imageUrls: imageUrls, isUser: false),
      );
    } catch (e) {
      debugPrint('Chyba pri volaní stylist API: $e');
      _addMessage(
        Message(
          text:
              'Ups, niečo sa pokazilo. Skús to prosím o chvíľku znova. 🌧️ (Technické info: $e)',
          isUser: false,
        ),
      );
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  Future<Map<String, dynamic>> _callStylistApi({
    required String userMessage,
    required List<Map<String, dynamic>> wardrobe,
    Position? position,
    Map<String, dynamic>? weather,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not logged in');
    }

    // ⚙️ Konverzia šatníka do formátu, ktorý vie jsonEncode spracovať
    final wardrobeForApi = wardrobe.map((item) {
      return item.map((key, value) {
        if (value is Timestamp) {
          return MapEntry(
            key,
            value.toDate().toIso8601String(),
          );
        }
        return MapEntry(key, value);
      });
    }).toList();

    // TODO: nahraď túto URL reálnou HTTPS Cloud Function adresou
    const String functionUrl =
        'https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/chatWithStylist';

    final body = {
      'userId': user.uid,
      'userMessage': userMessage,
      'wardrobe': wardrobeForApi,
      'location': position == null
          ? null
          : {
              'lat': position.latitude,
              'lon': position.longitude,
            },
      'weather': weather,
      // v budúcnosti sem môžeme pridať aj widget.initialItemData
    };

    final response = await http.post(
      Uri.parse(functionUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      debugPrint(
          'Stylist API error: ${response.statusCode} - ${response.body}');
      throw Exception('Stylist API returned status ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data;
  }

  Widget _buildMessageBubble(Message message) {
    final alignment =
        message.isUser ? Alignment.centerRight : Alignment.centerLeft;
    final bgColor =
        message.isUser ? const Color(0xFF4E5AE8) : Colors.grey.shade200;
    final textColor = message.isUser ? Colors.white : Colors.black87;

    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Column(
          crossAxisAlignment:
              message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (message.text.isNotEmpty)
              Text(
                message.text,
                style: TextStyle(color: textColor, fontSize: 15),
              ),
            if (message.imageUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              Column(
                children: message.imageUrls
                    .map(
                      (url) => Container(
                        margin: const EdgeInsets.only(top: 4.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8.0),
                          child: Image.network(
                            url,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Stylista'),
      ),
      body: Column(
        children: [
          if (_isLoadingData) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _buildMessageBubble(message);
              },
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (value) =>
                          _handleSubmitted(value.trim()),
                      decoration: const InputDecoration.collapsed(
                        hintText: 'Spýtaj sa stylistu…',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    color: const Color(0xFF4E5AE8),
                    onPressed: _isSending
                        ? null
                        : () => _handleSubmitted(
                              _textController.text.trim(),
                            ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}