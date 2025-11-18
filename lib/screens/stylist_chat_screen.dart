// lib/screens/stylist_chat_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Definícia novej triedy Message na ukladanie textu a obrázkov
class Message {
  final String text;
  final List<String> imageUrls;
  final bool isUser;

  Message({required this.text, this.imageUrls = const [], required this.isUser});
}

class StylistChatScreen extends StatefulWidget {
  const StylistChatScreen({
    Key? key,
  }) : super(key: key);

  @override
  _StylistChatScreenState createState() => _StylistChatScreenState();
}

class _StylistChatScreenState extends State<StylistChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final List<Message> _messages = []; // Zmenené na List<Message>
  bool _isSending = false;

  List<dynamic> _wardrobe = [];
  Map<String, dynamic> _userPreferences = {};
  bool _isLoadingData = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoadingData = true;
      _messages.add(
        Message(
          text: 'Pripravujem tvoj šatník a preferencie. Moment prosím...',
          isUser: false,
        ),
      );
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          _userPreferences = userDoc.data()?['userPreferences'] as Map<String, dynamic>? ?? {};
        }

        final wardrobeSnapshot = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('wardrobe').get();
        _wardrobe = wardrobeSnapshot.docs.map((doc) => doc.data()).toList();

        for (var item in _wardrobe) {
          if (item is Map<String, dynamic>) {
            item.forEach((key, value) {
              if (value is Timestamp) {
                item[key] = value.toDate().toIso8601String();
              }
            });
          }
        }

        setState(() {
          _isLoadingData = false;
          _messages.add(
            Message(
              text: 'Šatník a preferencie úspešne načítané. Som pripravený ti poradiť!',
              isUser: false,
            ),
          );
        });
      } catch (e) {
        print('Chyba pri načítaní dát: $e');
        setState(() {
          _isLoadingData = false;
          _messages.add(
            Message(
              text: 'Prepáč, došlo k chybe pri načítaní tvojich údajov. Skús to prosím neskôr.',
              isUser: false,
            ),
          );
        });
      }
    }
  }

  Future<void> _handleSubmitted(String text) async {
    if (text.isEmpty || _isLoadingData) return;
    _textController.clear();

    setState(() {
      _messages.add(Message(text: text, isUser: true));
      _isSending = true;
    });

    try {
      const String functionUrl =
          'https://us-central1-outfitoftheday-4d401.cloudfunctions.net/chatWithStylist';


      final response = await http.post(
        Uri.parse(functionUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'userQuery': text,
          'wardrobe': _wardrobe,
          'userPreferences': _userPreferences,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          final responseText = data['text'] as String? ?? 'Prepáč, momentálne ti neviem pomôcť.';
          final outfitImages = data['outfit_images'] as List<dynamic>?;

          if (outfitImages != null && outfitImages.isNotEmpty) {
            _messages.add(Message(
              text: responseText,
              imageUrls: List<String>.from(outfitImages),
              isUser: false,
            ));
          } else {
            _messages.add(Message(
              text: responseText,
              isUser: false,
            ));
          }
          _isSending = false;
        });
      } else {
        print('Chyba pri volaní funkcie. Status Code: ${response.statusCode}');
        print('Odpoveď: ${response.body}');
        setState(() {
          _messages.add(
            Message(
              text: 'Prepáč, došlo k chybe. Skús to prosím neskôr.',
              isUser: false,
            ),
          );
          _isSending = false;
        });
      }
    } catch (e) {
      print('Neočakávaná chyba: $e');
      setState(() {
        _messages.add(
          Message(
            text: 'Prepáč, došlo k nečakanej chybe. Skús to prosím neskôr.',
            isUser: false,
          ),
        );
        _isSending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Stylista'),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0),
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (_, int index) {
                final message = _messages[_messages.length - 1 - index];
                return ChatMessage(message: message);
              },
            ),
          ),
          const Divider(height: 1.0),
          SafeArea(
            child: _buildTextComposer(),
          ),
        ],
      ),
    );
  }

  Widget _buildTextComposer() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _textController,
              onSubmitted: _handleSubmitted,
              decoration: InputDecoration.collapsed(
                hintText: _isSending || _isLoadingData ? 'Odosielam...' : 'Napíšte správu...',
              ),
              enabled: !_isSending && !_isLoadingData,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4.0),
            child: IconButton(
              icon: const Icon(Icons.send),
              onPressed: _isSending || _isLoadingData ? null : () => _handleSubmitted(_textController.text),
            ),
          ),
        ],
      ),
    );
  }
}

// Zmenená trieda na zobrazenie správ
class ChatMessage extends StatelessWidget {
  final Message message;

  const ChatMessage({Key? key, required this.message}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: <Widget>[
          if (!message.isUser)
            Container(
              margin: const EdgeInsets.only(right: 16.0),
              child: const CircleAvatar(
                child: Icon(Icons.psychology),
              ),
            ),
          Flexible(
            child: Column(
              crossAxisAlignment: message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  message.isUser ? 'Vy' : 'AI Stylista',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 5.0),
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: message.isUser ? Colors.blue[100] : Colors.grey[200],
                    borderRadius: BorderRadius.circular(15.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(message.text),
                      if (message.imageUrls.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: message.imageUrls.length,
                          itemBuilder: (context, index) {
                            final imageUrl = message.imageUrls[index];
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Center(child: Icon(Icons.broken_image, size: 40));
                                },
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (message.isUser)
            Container(
              margin: const EdgeInsets.only(left: 16.0),
              child: const CircleAvatar(
                child: Icon(Icons.person),
              ),
            ),
        ],
      ),
    );
  }
}