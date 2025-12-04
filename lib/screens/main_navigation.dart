import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'wardrobe_screen.dart';
import 'calendar_screen.dart';
import 'trip_planner_screen.dart';
import 'recommended_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({Key? key}) : super(key: key);

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const HomeScreen(),
      const WardrobeScreen(),
      const CalendarScreen(),
      const TripPlannerScreen(),              // ✈️ Cesty (dovolenka/práca)
      const RecommendedScreen(initialTab: 1), // 🛍 Tab "Nakupovať"
    ];
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: theme.colorScheme.primary,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: 'Domov',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.checkroom_outlined),
            label: 'Šatník',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.event_note_outlined),
            label: 'Kalendár',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.flight_takeoff_outlined), // ✈️ Cesty
            label: 'Cesty',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_bag_outlined),
            label: 'Nakupovať',
          ),
        ],
      ),
    );
  }
}
