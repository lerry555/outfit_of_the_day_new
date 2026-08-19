// lib/main.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'Services/color_naming_service.dart';
import 'Services/fcm_service.dart';
import 'Services/firebase_app_check_bootstrap.dart';
import 'app/app_router.dart';
import 'debug/capture_auth_handoff.dart';
import 'debug/controlled_shadow_smoke.dart';
import 'debug/stylist_qa_runtime.dart';
import 'debug/wardrobe_authority_disabled_smoke.dart';
import 'screens/auth_gate.dart';
import 'domain/wardrobe_v2/wardrobe_ontology_v2.dart';
import 'utils/home_debug_logging.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  verifyWardrobeV2ProductionFlags();
  StylistQaAppSession.ensureInitialized();
  await ColorNamingService.instance.load();
  await WardrobeOntologyV2.load();
  await Firebase.initializeApp();
  // App Check must run after Firebase.initializeApp and before wardrobe
  // authority/lifecycle callables (soft-defer if activation fails).
  await FirebaseAppCheckBootstrap.instance.ensureInitialized();
  if (await CaptureAuthHandoff.runIfEnabled()) return;
  final smokeScheduled =
      WardrobeAuthorityDisabledSmoke.scheduleAfterAuthIfEnabled();
  // Push notifikácie stylistu (odpoveď aj keď je appka na pozadí).
  FirebaseMessaging.onBackgroundMessage(stylistFcmBackgroundHandler);
  await initializeDateFormatting('sk_SK', null);
  tz_data.initializeTimeZones();
  runApp(const MyApp());
  if (smokeScheduled) {
    debugPrint('WARDROBE_AUTHORITY_DISABLED_SMOKE waiting_for_google_sign_in');
  }
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: const DividerThemeData(
        color: softDivider,
        thickness: 1,
        space: 1,
      ),
      iconTheme: const IconThemeData(color: primaryText, size: 22),
      textTheme: base.textTheme
          .apply(bodyColor: primaryText, displayColor: primaryText)
          .copyWith(
            bodyMedium: base.textTheme.bodyMedium?.copyWith(color: primaryText),
            bodySmall: base.textTheme.bodySmall?.copyWith(color: secondaryText),
            titleMedium: base.textTheme.titleMedium?.copyWith(
              color: primaryText,
            ),
            titleSmall: base.textTheme.titleSmall?.copyWith(
              color: secondaryText,
            ),
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
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
      navigatorKey: rootNavigatorKey,
      title: 'Outfit Of The Day',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      locale: const Locale('sk', 'SK'),
      supportedLocales: const [Locale('sk', 'SK'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: ControlledShadowSmoke.overlay(const AuthGate()),
    );
  }
}
