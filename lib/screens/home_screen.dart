import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'add_clothing_screen.dart';
import 'calendar_screen.dart';
import 'friends_screen.dart';
import 'messages_screen.dart';
import 'recommended_screen.dart';
import 'select_outfit_screen.dart';
import 'stylist_chat_screen.dart';
import 'user_preferences_screen.dart';
import 'wardrobe_screen.dart';

enum HeroWeatherType { winter, rain, summer }

class HeroVariant {
  final String assetPath;
  final Offset offset; // ✅ posun v pixeloch (dx, dy)
  final double scale; // ✅ zväčšenie, aby bol priestor na posun

  const HeroVariant({
    required this.assetPath,
    this.offset = Offset.zero,
    this.scale = 1.25,
  });
}

// ✅ tu si budeš ladiť každý hero zvlášť
const Map<HeroWeatherType, HeroVariant> kHeroVariants = {
  HeroWeatherType.winter: HeroVariant(
    assetPath: 'assets/hero/winter.png',
    offset: Offset(60, -40),
    scale: 1.30,
  ),
  HeroWeatherType.rain: HeroVariant(
    assetPath: 'assets/hero/rain.png',
    offset: Offset(50, 10),
    scale: 1.35,
  ),
  HeroWeatherType.summer: HeroVariant(
    assetPath: 'assets/hero/summer.png',
    offset: Offset(80, -30),
    scale: 1.25,
  ),
};

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final greetingName = _getGreetingName(user);

    // ✅ len na test prepínaj tu
    final heroType = HeroWeatherType.rain;
    final hero = kHeroVariants[heroType]!;

    return WillPopScope(
      onWillPop: () async => true,
      child: Scaffold(
        backgroundColor: const Color(0xFF0E0E0E),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            'Outfit Of The Day',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async => _auth.signOut(),
            ),
          ],
        ),
        drawer: _buildDrawer(context),
        floatingActionButton: FloatingActionButton(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          onPressed: () => AddClothingScreen.openFromPicker(context),
          child: const Icon(Icons.add),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greetingName 👋',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Poďme vybrať tvoj dnešný outfit.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 18),

              _WeatherHeroBanner(
                title: "Today's Outfit",
                subtitle: "Zima • 4°C • vietor • zamračené",
                imageAssetPath: hero.assetPath,
                imageOffset: hero.offset,
                imageScale: hero.scale,
                chips: const [
                  _HeroChip(icon: Icons.thermostat, label: "4°C"),
                  _HeroChip(icon: Icons.air, label: "vietor"),
                  _HeroChip(icon: Icons.wb_cloudy, label: "zamračené"),
                ],
                ctaText: "Upraviť outfit",
                onTap: () => _openHeroDayPicker(context),
              ),

              const SizedBox(height: 14),

              _QuickActionsGrid(
                items: [
                  _QuickAction(
                    icon: Icons.style,
                    label: 'Outfit',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SelectOutfitScreen()),
                      );
                    },
                  ),
                  _QuickAction(
                    icon: Icons.smart_toy_outlined,
                    label: 'Stylist',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const StylistChatScreen()),
                      );
                    },
                  ),
                  _QuickAction(
                    icon: Icons.inventory_2_outlined,
                    label: 'Šatník',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const WardrobeScreen()),
                      );
                    },
                  ),
                  _QuickAction(
                    icon: Icons.calendar_today,
                    label: 'Kalendár',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CalendarScreen()),
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: 22),

              _RecommendedCarouselV2(
                onOpenRecommended: _openRecommended,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openHeroDayPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Pre ktorý deň chceš outfit?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SheetChoiceTile(
                    icon: Icons.today,
                    title: 'Dnes',
                    subtitle: 'Vybrať outfit na dnešok',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SelectOutfitScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _SheetChoiceTile(
                    icon: Icons.wb_sunny_outlined,
                    title: 'Zajtra',
                    subtitle: 'Vybrať outfit na zajtra',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SelectOutfitScreen()),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Zajtra: zatiaľ rovnaký výber (napojíme dátum neskôr).'),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openRecommended() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecommendedScreen(initialTab: 0)),
    );
  }

  Drawer _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF121212),
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              child: Text(
                'Menu',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.people_outline, color: Colors.white70),
              title: const Text('Priatelia', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FriendsScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.diversity_2, color: Colors.white70),
              title: const Text('Správy a zladenie outfitov', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MessagesScreen()),
                );
              },
            ),
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.settings, color: Colors.white70),
              title: const Text('Nastavenia', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const UserPreferencesScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _getGreetingName(User? user) {
    if (user == null) return 'Ahoj';
    final name = user.displayName;
    if (name == null || name.trim().isEmpty) return 'Ahoj';
    return 'Ahoj, ${name.split(' ').first}';
  }
}

class _SheetChoiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SheetChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }
}

class _WeatherHeroBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imageAssetPath;
  final Offset imageOffset;
  final double imageScale;
  final List<_HeroChip> chips;
  final String ctaText;
  final VoidCallback onTap;

  const _WeatherHeroBanner({
    required this.title,
    required this.subtitle,
    required this.imageAssetPath,
    required this.imageOffset,
    required this.imageScale,
    required this.chips,
    required this.ctaText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white10),
          color: const Color(0xFF121212),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              // ✅ HERO IMAGE (ako včera): fitHeight + scale + translate + clamp (žiadne pruhy)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final double zoom = imageScale;

                    // posun v pixeloch (ladiš v mapke)
                    final double dx = imageOffset.dx;
                    final double dy = imageOffset.dy;

                    // maximum posunu bez prázdnych okrajov
                    final maxDx = (c.maxWidth * (zoom - 1)) / 2;
                    final maxDy = (c.maxHeight * (zoom - 1)) / 2;

                    final clampedDx = dx.clamp(-maxDx, maxDx);
                    final clampedDy = dy.clamp(-maxDy, maxDy);

                    return Transform.translate(
                      offset: Offset(clampedDx.toDouble(), clampedDy.toDouble()),
                      child: Transform.scale(
                        scale: zoom,
                        child: Image.asset(
                          imageAssetPath,
                          fit: BoxFit.fitHeight, // ✅ toto je kľúč
                          alignment: Alignment.center,
                        ),
                      ),
                    );
                  },
                ),
              ),

              // ✅ gradienty (nechávame tvoje)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withOpacity(0.80),
                        Colors.black.withOpacity(0.55),
                        Colors.black.withOpacity(0.25),
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                ),
              ),

              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.55),
                      ],
                      radius: 1.05,
                      center: const Alignment(0.0, -0.2),
                    ),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: chips.take(3).toList(),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            ctaText,
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(Icons.arrow_forward_ios,
                            color: Colors.white70, size: 16),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
// QUICK ACTIONS GRID
class _QuickActionsGrid extends StatelessWidget {
  final List<_QuickAction> items;
  const _QuickActionsGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _QuickActionTile(action: items[0])),
        const SizedBox(width: 10),
        Expanded(child: _QuickActionTile(action: items[1])),
        const SizedBox(width: 10),
        Expanded(child: _QuickActionTile(action: items[2])),
        const SizedBox(width: 10),
        Expanded(child: _QuickActionTile(action: items[3])),
      ],
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.onTap});
}

class _QuickActionTile extends StatelessWidget {
  final _QuickAction action;
  const _QuickActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: action.onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white10),
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A1A), Color(0xFF141414)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(action.icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              action.label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onSeeAll;

  const _SectionTitle({required this.title, this.subtitle, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ],
          ),
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            child: const Text('Zobraziť', style: TextStyle(color: Colors.white70)),
          ),
      ],
    );
  }
}

class _RecommendedCarouselV2 extends StatelessWidget {
  final VoidCallback onOpenRecommended;
  const _RecommendedCarouselV2({required this.onOpenRecommended});

  @override
  Widget build(BuildContext context) {
    const items = [
      _RecItemV2(
          brand: 'ZARA',
          name: 'Oversize hoodie',
          price: '34,99 €',
          matchLabel: 'Match 87%',
          icon: Icons.checkroom),
      _RecItemV2(
          brand: 'Nike',
          name: 'Air sneakers',
          price: '129,00 €',
          matchLabel: 'K tvojim rifliam',
          icon: Icons.directions_run),
      _RecItemV2(
          brand: 'H&M',
          name: 'Basic tričko',
          price: '9,99 €',
          matchLabel: 'Minimal vibe',
          icon: Icons.heat_pump),
      _RecItemV2(
          brand: 'Levi’s',
          name: 'Slim rifle',
          price: '89,90 €',
          matchLabel: 'Na každý deň',
          icon: Icons.local_mall_outlined),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: 'Odporúčané pre teba',
          subtitle: 'Podľa tvojich kúskov a štýlu',
          onSeeAll: onOpenRecommended,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) =>
                _RecommendedCardV2(item: items[index], onTap: onOpenRecommended),
          ),
        ),
      ],
    );
  }
}

class _RecItemV2 {
  final String brand;
  final String name;
  final String price;
  final String matchLabel;
  final IconData icon;

  const _RecItemV2({
    required this.brand,
    required this.name,
    required this.price,
    required this.matchLabel,
    required this.icon,
  });
}

class _RecommendedCardV2 extends StatelessWidget {
  final _RecItemV2 item;
  final VoidCallback onTap;

  const _RecommendedCardV2({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 92,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2D2D2D), Color(0xFF141414)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Center(
                    child: Icon(item.icon, color: Colors.white24, size: 42),
                  ),
                ),
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text(
                      item.matchLabel,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              item.brand,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(item.price,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.bookmark_border, color: Colors.white70, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
