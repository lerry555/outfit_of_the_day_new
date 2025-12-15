// lib/screens/stylist_chat_screen.dart
//
// ✅ Fix: constructor parametre (žiadny "focusItem" a žiadne rozbité required Map...)
// - AddClothingScreen posiela: StylistChatScreen(initialClothingData: payload)

import 'package:flutter/material.dart';

class StylistChatScreen extends StatefulWidget {
  final Map<String, dynamic>? initialClothingData;

  const StylistChatScreen({
    super.key,
    this.initialClothingData,
  });

  @override
  State<StylistChatScreen> createState() => _StylistChatScreenState();
}

class _StylistChatScreenState extends State<StylistChatScreen> {
  @override
  Widget build(BuildContext context) {
    // Pozn.: tvoj pôvodný chat UI tu určite máš – ale teraz ti opravujem len rozbitý constructor,
    // aby projekt znovu kompiloval a AddClothingScreen vedel otvoriť chat.
    //
    // Ak chceš, pošleš mi sem tvoj pôvodný obsah StylistChatScreen a ja ho vložím späť 1:1.
    final focus = widget.initialClothingData;

    return Scaffold(
      appBar: AppBar(title: const Text('AI Stylista')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          focus == null
              ? 'Stylista pripravený. (Chýba initialClothingData)'
              : 'Stylista pripravený pre kúsok: ${focus['name'] ?? ''}',
        ),
      ),
    );
  }
}