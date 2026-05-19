import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'wardrobe_screen.dart';
import 'add_clothing_screen.dart';
import 'stylist_chat_screen.dart';
import '../Services/share_intent_service.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({Key? key}) : super(key: key);

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  static const Color _goldTop = Color(0xFFC8A36A);
  static const Color _goldBottom = Color(0xFF9D7C4C);
  static const Color _goldBorder = Color(0x73C8A36A);
  static const Color _darkText = Color(0xFF191512);

  int _currentIndex = 0;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();

    _screens = [
      const HomeScreen(),
      const WardrobeScreen(),
      const StylistChatScreen(),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ShareIntentService.start(context);
    });
  }

  Future<void> _onTabTapped(int index) async {
    if (index == 2) {
      await AddClothingScreen.openFromPicker(context);
      return;
    }

    final screenIndex = index == 3 ? 2 : index;
    setState(() {
      _currentIndex = screenIndex;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;

        if (_currentIndex != 0) {
          setState(() {
            _currentIndex = 0;
          });
        } else {
          Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _goldTop,
                _goldBottom,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: _goldTop.withOpacity(0.26),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
            border: Border(
              top: BorderSide(
                color: _goldBorder,
                width: 1,
              ),
            ),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              canvasColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: _onTabTapped,
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedItemColor: _darkText,
              unselectedItemColor: _darkText.withOpacity(0.65),
              selectedFontSize: 12,
              unselectedFontSize: 12,
              showUnselectedLabels: true,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home),
                  label: 'Domov',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.checkroom_outlined),
                  activeIcon: Icon(Icons.checkroom),
                  label: 'Šatník',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.add_circle_outline_rounded),
                  activeIcon: Icon(Icons.add_circle_rounded),
                  label: 'Pridať',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.face_retouching_natural_rounded),
                  activeIcon: Icon(Icons.face_retouching_natural_rounded),
                  label: 'AI Stylista',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}