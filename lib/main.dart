// lib/main.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await initializeDateFormatting('sk_SK', null);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  ThemeData _buildTheme() {
    final base = ThemeData.light(useMaterial3: true);
    const primaryBackground = Color(0xFFF5F4F2);
    const cardBackground = Color(0xFFFFFFFF);
    const primaryText = Color(0xFF2F3136);
    const secondaryText = Color(0xFF72757E);
    const softDivider = Color(0xFFE9E7E3);
    const subtleShadow = Color(0x14000000);

    final lightColorScheme = base.colorScheme.copyWith(
      primary: const Color(0xFF7C4DFF),
      secondary: const Color(0xFFFFC400),
      surface: cardBackground,
      onSurface: primaryText,
      onPrimary: Colors.white,
      onSecondary: const Color(0xFF2A2A2A),
      outline: softDivider,
    );

    return base.copyWith(
      colorScheme: lightColorScheme,
      scaffoldBackgroundColor: primaryBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: primaryText,
        elevation: 0,
      ),
      cardColor: cardBackground,
      cardTheme: base.cardTheme.copyWith(
        color: cardBackground,
        shadowColor: subtleShadow,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: softDivider,
        thickness: 1,
        space: 1,
      ),
      iconTheme: const IconThemeData(
        color: primaryText,
        size: 22,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: primaryText,
        displayColor: primaryText,
      ).copyWith(
        bodyMedium: base.textTheme.bodyMedium?.copyWith(color: primaryText),
        bodySmall: base.textTheme.bodySmall?.copyWith(color: secondaryText),
        titleMedium: base.textTheme.titleMedium?.copyWith(color: primaryText),
        titleSmall: base.textTheme.titleSmall?.copyWith(color: secondaryText),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: lightColorScheme.primary,
          foregroundColor: Colors.white,
          shadowColor: subtleShadow,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardBackground,
        hintStyle: const TextStyle(color: secondaryText),
        labelStyle: const TextStyle(color: secondaryText),
        floatingLabelStyle: TextStyle(color: lightColorScheme.primary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: softDivider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: softDivider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: lightColorScheme.primary, width: 1.4),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Outfit Of The Day',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      locale: const Locale('sk', 'SK'),
      supportedLocales: const [
        Locale('sk', 'SK'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AuthGate(),
    );
  }
}