// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'screens/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  ThemeData _buildTheme() {
    final base = ThemeData.light();
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: const Color(0xFF7C4DFF),
        secondary: const Color(0xFFFFC400),
      ),
      scaffoldBackgroundColor: const Color(0xFFF7F2FF),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      useMaterial3: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Outfit Of The Day',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),

      // ✅ Namiesto MainNavigation dáme AuthGate
      // ten sám rozhodne: neprihlásený -> LoginScreen, prihlásený -> MainNavigation
      home: const AuthGate(),
    );
  }
}
