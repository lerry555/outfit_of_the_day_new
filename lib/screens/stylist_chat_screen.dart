// lib/screens/stylist_chat_screen.dart

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

// Definícia novej triedy Message na ukladanie textu a obrázkov
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
  const StylistChatScreen({super.key});

  @override
  _StylistChatScreenState createState() => _StylistChatScreenState();
}

class _StylistChatScreenState extends State<StylistChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<Message> _messages = [];
  bool _isSending = false;
  List<Map<String, dynamic>> _wardrobe = [];
  Map<String, dynamic> _userPreferences = {};
  bool _isLoadingData = true;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await Future.wait([
      _loadWardrobeFromFirestore(),
      _loadUserPreferencesFromFirestore(),
    ]);

    setState(() {
      _isLoadingData = false;
    });
  }

  Future<void> _loadWardrobeFromFirestore() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('Používateľ nie je prihlásený.');
        return;
      }

      final wardrobeSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('wardrobe')
          .get();

      final wardrobeData = wardrobeSnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      setState(() {
        _wardrobe = List<Map<String, dynamic>>.from(wardrobeData);
      });

      print('Šatník načítaný: ${_wardrobe.length} položiek.');
    } catch (e) {
      print('Chyba pri načítaní šatníka: $e');
      setState(() {
        _wardrobe = [];
      });
    }
  }

  Future<void> _loadUserPreferencesFromFirestore() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('Používateľ nie je prihlásený.');
        return;
      }

      final docSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('settings')
          .doc('preferences')
          .get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data();
        if (data != null) {
          setState(() {
            _userPreferences = Map<String, dynamic>.from(data);
          });
        }
      } else {
        print('Žiadne preferencie nenájdené, používam prázdne nastavenia.');
        setState(() {
          _userPreferences = {};
        });
      }
    } catch (e) {
      print('Chyba pri načítaní preferencií: $e');
      setState(() {
        _userPreferences = {};
      });
    }
  }

  // 🔹 Pomocná funkcia – získanie polohy z mobilu
  Future<Position?> _getCurrentPosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Je zapnutá služba polohy?
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Služba polohy je vypnutá – nebudeme riešiť, len vrátime null
      return null;
    }

    // Kontrola povolení
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Používateľ odmietol – nepošleme polohu
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Používateľ zakázal navždy – nepošleme polohu
      return null;
    }

    // Všetko OK – získame aktuálnu pozíciu
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
    );
  }

  // 🔹 Timestamp → String, aby šlo jsonEncode
  dynamic _sanitizeValue(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toIso8601String();
    } else if (value is Map<String, dynamic>) {
      return _sanitizeMapForJson(value);
    } else if (value is List) {
      return value.map((v) => _sanitizeValue(v)).toList();
    }
    return value;
  }

  Map<String, dynamic> _sanitizeMapForJson(Map<String, dynamic> input) {
    final result = <String, dynamic>{};
    input.forEach((key, value) {
      result[key] = _sanitizeValue(value);
    });
    return result;
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  Future<void> _handleSubmitted(String text) async {
    if (text.isEmpty || _isLoadingData) return;
    _textController.clear();

    setState(() {
      _messages.add(Message(text: text, isUser: true));
      _isSending = true;
    });
    _scheduleScrollToBottom();

    // 1) Skúsime získať polohu z mobilu
    Position? position;
    try {
      position = await _getCurrentPosition();
    } catch (e) {
      position = null;
    }

    try {
      const String functionUrl =
          'https://us-central1-outfitoftheday-4d401.cloudfunctions.net/chatWithStylist';

      // 🔹 2) Očistíme šatník a preferencie od Timestampov
      final List<Map<String, dynamic>> sanitizedWardrobe =
      _wardrobe.map((item) => _sanitizeMapForJson(item)).toList();

      final Map<String, dynamic> sanitizedPreferences =
      _sanitizeMapForJson(_userPreferences);

      // 🔹 3) Pripravíme krátku históriu chatu (posledných ~10 správ)
      final int historyLength = 10;
      final List<Message> lastMessages = _messages.length <= historyLength
          ? _messages
          : _messages.sublist(_messages.length - historyLength);

      final List<Map<String, dynamic>> history = lastMessages
          .map((m) => {
        'role': m.isUser ? 'user' : 'assistant',
        'content': m.text,
      })
          .toList();

      // 4) Poskladáme telo requestu
      final Map<String, dynamic> body = {
        'userQuery': text,
        'wardrobe': sanitizedWardrobe,
        'userPreferences': sanitizedPreferences,
        'history': history,
      };

      if (position != null) {
        body['location'] = {
          'latitude': position.latitude,
          'longitude': position.longitude,
        };
      }

      // 5) Pošleme request na backend
      final response = await http.post(
        Uri.parse(functionUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          final responseText =
              data['text'] as String? ?? 'Prepáč, momentálne ti neviem pomôcť.';
          final outfitImages = data['outfit_images'] as List<dynamic>?;

          if (outfitImages != null && outfitImages.isNotEmpty) {
            _messages.add(
              Message(
                text: responseText,
                imageUrls: List<String>.from(outfitImages),
                isUser: false,
              ),
            );
          } else {
            _messages.add(
              Message(
                text: responseText,
                isUser: false,
              ),
            );
          }
          _isSending = false;
        });
        _scheduleScrollToBottom();
      } else {
        setState(() {
          _messages.add(
            Message(
              text:
              'Prepáč, nastala chyba na serveri (kód ${response.statusCode}).',
              isUser: false,
            ),
          );
          _isSending = false;
        });
        _scheduleScrollToBottom();
      }
    } catch (e, st) {
      print('Neočakávaná chyba: $e\n$st');
      if (!mounted) return;
      setState(() {
        _messages.add(
          Message(
            text:
            'Prepáč, došlo k nečakanej chybe. Skús to prosím neskôr.',
            isUser: false,
          ),
        );
        _isSending = false;
      });
      _scheduleScrollToBottom();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildMessageBubble(Message message) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 14.0),
        decoration: BoxDecoration(
          color:
          message.isUser ? const Color(0xFF4E5AE8) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Column(
          crossAxisAlignment: message.isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: message.isUser ? Colors.white : Colors.black,
              ),
            ),
            if (message.imageUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: message.imageUrls.map((url) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      child: Image.network(
                        url,
                        height: 160,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 160,
                            color: Colors.grey.shade300,
                            child: const Center(
                              child: Icon(Icons.broken_image),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('#OOTD AI Stylista'),
        backgroundColor: const Color(0xFF4E5AE8),
      ),
      body: Column(
        children: [
          if (_isLoadingData) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: Container(
              color: Colors.grey.shade100,
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(8.0),
                reverse: false,
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return _buildMessageBubble(message);
                },
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: theme.cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  offset: const Offset(0, -1),
                  blurRadius: 4,
                ),
              ],
            ),
            padding:
            const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      onSubmitted:
                      _isSending ? null : (value) => _handleSubmitted(value),
                      decoration: const InputDecoration.collapsed(
                        hintText: 'Napíš, kam ideš alebo čo potrebuješ...',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: _isSending
                        ? const SizedBox(
                      width: 20,
                      height: 20,
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
