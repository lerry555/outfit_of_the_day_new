import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Outfit of the Day',
      debugShowCheckedModeBanner: false,

      // 🔤 Povieme Flutteru, že podporujeme viac jazykov
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // 🌍 Zoznam jazykov, ktoré appka „rozumie“
      supportedLocales: const <Locale>[
        Locale('sk'),
        Locale('cs'),
        Locale('en'),
        Locale('de'),
        Locale('pl'),
        Locale('fr'),
        Locale('es'),
      ],

      // domovská obrazovka
      home: const HomeScreen(),
    );
  }
}
