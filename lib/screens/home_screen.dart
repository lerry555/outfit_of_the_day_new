import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'add_clothing_screen.dart';
import 'select_outfit_screen.dart';
import 'recommended_screen.dart';
import 'friends_screen.dart';
import 'messages_screen.dart';
import 'user_preferences_screen.dart';
import 'stylist_chat_screen.dart';

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
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 👋 Greeting
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
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 18),

              // 🎯 HERO (vylepšený)
              _HeroBannerV2(
                title: "Today's Outfit",
                subtitle: "Dnešný look pripravený • 1 tap na úpravu",
                chips: const [
                  _HeroChip(icon: Icons.thermostat, label: "4°C"),
                  _HeroChip(icon: Icons.air, label: "vietor"),
                  _HeroChip(icon: Icons.wb_cloudy, label: "zamračené"),
                ],
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SelectOutfitScreen()),
                  );
                },
              ),

              const SizedBox(height: 14),

              // ⚡ QUICK ACTIONS (vylepšené)
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
                    icon: Icons.calendar_today,
                    label: 'Kalendár',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Kalendár zatiaľ nie je hotový.')),
                      );
                    },
                  ),
                  _QuickAction(
                    icon: Icons.add_photo_alternate_outlined,
                    label: 'Pridať',
                    onTap: () => AddClothingScreen.openFromPicker(context),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              // ⭐ RECOMMENDED (vylepšený + badge)
              _RecommendedCarouselV2(
                onOpenRecommended: _openRecommended,
              ),

              const SizedBox(height: 18),

              // 🧭 UPCOMING (nové)
              _UpcomingCard(
                title: 'Nadchádzajúce',
                subtitle: 'Piatok • večera v meste',
                cta: 'Navrhni outfit',
                icon: Icons.event,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StylistChatScreen()),
                  );
                },
              ),

              const SizedBox(height: 18),

              // 🤖 AI Stylist CTA (emo)
              _AiStylistCtaCardV2(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StylistChatScreen()),
                  );
                },
              ),

              const SizedBox(height: 18),

              // 👕 Wardrobe summary placeholder (vylepšené)
              _WardrobeSummaryCardV2(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Prehľad šatníka doplníme neskôr.')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
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
                Navigator.push(context, MaterialPageRoute(builder: (_) => const FriendsScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.diversity_2, color: Colors.white70),
              title: const Text('Správy a zladenie outfitov', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.push(context, MaterialPageRoute(builder: (_) => const MessagesScreen()));
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
// =======================
// Small helpers
// =======================
class _CardShell extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  const _CardShell({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: child,
    );

    if (onTap == null) return content;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: content,
    );
  }
}

// =======================
// HERO V2
// =======================
class _HeroBannerV2 extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<_HeroChip> chips;
  final VoidCallback onTap;

  const _HeroBannerV2({
    required this.title,
    required this.subtitle,
    required this.chips,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        height: 190,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white10),
          gradient: const LinearGradient(
            colors: [Color(0xFF2A2A2A), Color(0xFF121212)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            // subtle “fashion” glow shapes
            Positioned(
              left: -40,
              top: -50,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ),
            Positioned(
              right: -30,
              bottom: -40,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.04),
                ),
              ),
            ),

            // mannequin placeholder (right)
            Positioned(
              right: 12,
              bottom: 10,
              child: Opacity(
                opacity: 0.18,
                child: Icon(
                  Icons.accessibility_new,
                  size: 160,
                  color: Colors.white,
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
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
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: chips,
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Upraviť outfit',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
                    ],
                  ),
                ],
              ),
            ),
          ],
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
        color: Colors.white.withOpacity(0.08),
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

// =======================
// QUICK ACTIONS GRID
// =======================
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

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
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
              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// =======================
// SECTION TITLE
// =======================
class _SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onSeeAll;

  const _SectionTitle({
    required this.title,
    this.subtitle,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
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

// =======================
// RECOMMENDED V2
// =======================
class _RecommendedCarouselV2 extends StatelessWidget {
  final VoidCallback onOpenRecommended;

  const _RecommendedCarouselV2({required this.onOpenRecommended});

  @override
  Widget build(BuildContext context) {
    const items = [
      _RecItemV2(brand: 'ZARA', name: 'Oversize hoodie', price: '34,99 €', matchLabel: 'Match 87%', icon: Icons.checkroom),
      _RecItemV2(brand: 'Nike', name: 'Air sneakers', price: '129,00 €', matchLabel: 'K tvojim rifliam', icon: Icons.directions_run),
      _RecItemV2(brand: 'H&M', name: 'Basic tričko', price: '9,99 €', matchLabel: 'Minimal vibe', icon: Icons.heat_pump),
      _RecItemV2(brand: 'Levi’s', name: 'Slim rifle', price: '89,90 €', matchLabel: 'Na každý deň', icon: Icons.local_mall_outlined),
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
            itemBuilder: (context, index) {
              final it = items[index];
              return _RecommendedCardV2(item: it, onTap: onOpenRecommended);
            },
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
            // image placeholder + badge
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
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              item.brand,
              style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5),
            ),
            const SizedBox(height: 4),
            Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Row(
              children: [
                Text(
                  item.price,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
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

// =======================
// UPCOMING CARD
// =======================
class _UpcomingCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String cta;
  final IconData icon;
  final VoidCallback onTap;

  const _UpcomingCard({
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    cta,
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white54),
        ],
      ),
    );
  }
}

// =======================
// AI STYLIST CTA V2
// =======================
class _AiStylistCtaCardV2 extends StatelessWidget {
  final VoidCallback onTap;

  const _AiStylistCtaCardV2({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFF111111), Color(0xFF1C1C1C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              height: 56,
              width: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.white.withOpacity(0.08),
              ),
              child: const Icon(Icons.smart_toy_outlined, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Stylista',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Neviem čo si obliecť…\nSpýtaj sa a navrhnem kombináciu.',
                    style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.25),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
          ],
        ),
      ),
    );
  }
}

// =======================
// WARDROBE SUMMARY V2
// =======================
class _WardrobeSummaryCardV2 extends StatelessWidget {
  final VoidCallback onTap;

  const _WardrobeSummaryCardV2({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tvoj šatník',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'Rýchly prehľad a kategórie (napojíme live dáta).',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white54),
        ],
      ),
    );
  }
}
