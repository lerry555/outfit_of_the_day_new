// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:outfitofTheDay/screens/home_screen.dart';
import 'package:outfitofTheDay/screens/wardrobe_screen.dart';
import 'package:outfitofTheDay/screens/user_preferences_screen.dart';
import 'package:outfitofTheDay/screens/public_wardrobe_screen.dart';
import 'package:outfitofTheDay/screens/stylist_chat_screen.dart';
import 'package:outfitofTheDay/screens/auth_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

// Hlavná trieda aplikácie
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OutfitOfTheDay',
      theme: ThemeData(
        // === NOVÁ FAREBNÁ PALETA A TÉMA (inšpirovaná šatníkom) ===
        primarySwatch: Colors.blueGrey,
        primaryColor: const Color(0xFFBCAAA4), // Jemná hnedá/béžová (inšpirovaná drevom)
        hintColor: const Color(0xFF8D6E63), // Tmavo hnedá pre akcenty
        scaffoldBackgroundColor: Colors.transparent, // Transparentné, aby bolo vidieť gradient
        cardColor: Colors.white.withOpacity(0.9), // Jemne priehľadná biela pre karty
        appBarTheme: const AppBarTheme(
          color: Color(0xFFBCAAA4), // Farba App Baru
          foregroundColor: Colors.white, // Farba textu a ikon na App Bare
          elevation: 0, // Žiadny tieň pre čistejší vzhľad
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: const Color(0xFF8D6E63), // Farba FAB (tmavo hnedá)
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF8D6E63), // Farba Elevated Buttonu (tmavo hnedá)
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10), // Zaoblené rohy
            ),
            elevation: 2,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF8D6E63), // Farba textových tlačidiel (tmavo hnedá)
          ),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicator: UnderlineTabIndicator(
            borderSide: BorderSide(color: Colors.white, width: 2.0),
          ),
        ),
        chipTheme: ChipThemeData(
          selectedColor: const Color(0xFFD7CCC8), // Svetlejšia hnedá pre vybraný čip
          checkmarkColor: Colors.black, // Čierna pre odškrtávací znak
          labelStyle: TextStyle(color: Colors.grey.shade800),
          secondaryLabelStyle: const TextStyle(color: Colors.black),
          backgroundColor: Colors.grey.shade200,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          labelPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white.withOpacity(0.7),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontSize: 96, fontWeight: FontWeight.w300, color: Color(0xFF333333)),
          displayMedium: TextStyle(fontSize: 60, fontWeight: FontWeight.w300, color: Color(0xFF333333)),
          displaySmall: TextStyle(fontSize: 48, fontWeight: FontWeight.w400, color: Color(0xFF333333)),
          headlineLarge: TextStyle(fontSize: 34, fontWeight: FontWeight.w400, color: Color(0xFF333333)),
          headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF333333)),
          headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF333333)),
          titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: Color(0xFF333333)),
          titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w400, color: Color(0xFF333333)),
          titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF333333)),
          bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: Color(0xFF333333)),
          bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: Color(0xFF333333)),
          bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: Color(0xFF333333)),
          labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
          labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF333333)),
          labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w400, color: Color(0xFF333333)),
        ),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildImageBackground(const Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasData) {
            return const MainNavigator();
          }
          // Ak nie je používateľ prihlásený, ukáž obrazovku na prihlásenie.
          return const AuthScreen();
        },
      ),
    );
  }

  // Funkcia na obalenie akejkoľvek obrazovky obrázkovým pozadím
  Widget _buildImageBackground(Widget child) {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/satnik.jpg'),
          fit: BoxFit.cover,
        ),
      ),
      child: Container(
        // Pridá jemný gradient, aby bol text lepšie čitateľný
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5), // Jemná tmavá priesvitná vrstva
        ),
        child: child,
      ),
    );
  }
}

// === WIDGET PRE HLAVNÚ NAVIGÁCIU ===
class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  int _selectedIndex = 0; // Aktuálne vybraná záložka
  late PageController _pageController; // Controller pre PageView

  // Zoznam obrazoviek, ktoré budeme prepínať
  // Teraz obsahuje aj chat so stylistom, ale potrebuje dáta!
  final List<Widget> _screens = [
    const HomeScreen(),
    const WardrobeScreen(),
    const PublicWardrobeScreen(),
    const UserPreferencesScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _pageController.jumpToPage(index); // Okamžite prejde na vybranú stránku
  }

  // Funkcia na obalenie akejkoľvek obrazovky obrázkovým pozadím
  Widget _buildImageBackground(Widget child) {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/satnik.jpg'),
          fit: BoxFit.cover,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // === NOVÁ LOGIKA PRE ZOBRAZENIE CHATU ===
    // Aby mohol chat fungovať, musí mať prístup k šatníku a preferenciám používateľa.
    // Tieto dáta načítaš z Firebase a pošleš do chatovacej obrazovky.
    // Pre zjednodušenie a otestovanie to zatiaľ prepojíme s jednoduchým tlačidlom.

    return Scaffold(
      extendBody: true,
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        children: _screens.map((screen) => _buildImageBackground(screen)).toList(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Theme.of(context).primaryColor.withOpacity(0.9),
        selectedItemColor: Theme.of(context).cardColor,
        unselectedItemColor: Theme.of(context).cardColor.withOpacity(0.6),
        type: BottomNavigationBarType.fixed,
        elevation: 10,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Domov',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dry_cleaning_outlined),
            activeIcon: Icon(Icons.dry_cleaning),
            label: 'Môj šatník',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.public),
            activeIcon: Icon(Icons.public),
            label: 'Verejné',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Nastavenia',
          ),
        ],
      ),
    );
  }
}