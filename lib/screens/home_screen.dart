import 'dart:ui' show ImageFilter;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/home/home_ai_explanation_card.dart';
import '../widgets/home/home_daily_briefing_row.dart';
import '../widgets/home/home_greeting_header.dart';
import '../widgets/home/home_inspiration_carousel.dart';
import '../widgets/home/home_luxury_palette.dart';
import '../widgets/home/home_quick_action_orb.dart';
import '../widgets/home/home_recommended_section.dart';

import 'add_clothing_screen.dart';
import 'friends_screen.dart';
import 'messages_screen.dart';
import 'premium_screen.dart';
import 'profile_screen.dart';
import 'recommended_screen.dart';
import 'trip_planner_screen.dart';
import 'user_preferences_screen.dart';
import 'wardrobe_analysis_screen.dart';
import '../utils/outfit_reason_builder.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  int generatedOutfitsToday = 0;

  // ✅ prepínač Dnes/Zajtra (UI)
  int _dayIndex = 0; // 0 = dnes, 1 = zajtra
  bool get _isTomorrow => _dayIndex == 1;

  void _setDayIndex(int index) => setState(() => _dayIndex = index);

  Future<bool> _isCurrentUserPremium() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final snap = await _firestore.collection('users').doc(user.uid).get();
      final data = snap.data();
      final status = (data?['subscriptionStatus'] ?? '').toString().toLowerCase();
      final isPremium = data?['isPremium'] == true;
      return isPremium || status == 'premium';
    } catch (_) {
      return false;
    }
  }

  Future<void> _handleNewOutfitPressed() async {
    final isPremiumMode = await _isCurrentUserPremium();
    if (isPremiumMode) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Premium režim: nový outfit vygenerujeme neskôr.'),
        ),
      );
      return;
    }

    if (generatedOutfitsToday < 3) {
      final nextCount = generatedOutfitsToday + 1;
      setState(() {
        generatedOutfitsToday = nextCount;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Nový outfit vygenerujeme neskôr. Test limitu: $nextCount/3',
          ),
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Limit outfitov dosiahnutý',
                  style: TextStyle(
                    color: HomeLuxuryPalette.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Dnes si už vytvoril 3 outfity. S Premium môžeš generovať neobmedzene a získať presnejšie odporúčania.',
                  style: TextStyle(
                    color: HomeLuxuryPalette.textSecondary,
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HomeLuxuryPalette.accent,
                      foregroundColor: const Color(0xFF191512),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PremiumScreen()),
                      );
                    },
                    child: const Text(
                      'Vyskúšať Premium',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleSwapPieceTap(BuildContext context) async {
    final isPremiumMode = await _isCurrentUserPremium();
    if (!mounted) return;
    if (isPremiumMode) {
      _openHeroEditSheet(context);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Vymeniť kúsok – napojíme neskôr.')),
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _wardrobeStream(String uid) {
    return _firestore.collection('users').doc(uid).collection('wardrobe').snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _userDocStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots();
  }

  _LocalWeather _weatherForDate(DateTime date) {
    // Dočasné bezpečné počasie (kým nie je napojený zdroj).
    // Cieľ: nikdy necrashnúť a vždy mať zmysluplný text.
    return _LocalWeather.fallbackFor(date);
  }

  _HeroTodayState _buildTodayHero({
    required DateTime date,
    required List<Map<String, dynamic>> wardrobe,
    required bool isPremiumUser,
  }) {
    final w = _weatherForDate(date);
    final rec = _recommendOutfitForWeather(
      wardrobe: wardrobe,
      weather: w,
      isPremiumUser: isPremiumUser,
    );

    if (rec == null) {
      return _HeroTodayState(
        vm: _HeroBannerVM(
          description:
          'Dnes zatiaľ nemám dosť vhodných kúskov na kompletný outfit. Skús pridať viac oblečenia do šatníka.',
        ),
        outfitItems: const <_HeroOutfitItem>[],
      );
    }

    return _HeroTodayState(
      vm: _HeroBannerVM(
        description: rec.reason,
      ),
      outfitItems: rec.items,
    );
  }

  _HeroOutfitRecommendation? _recommendOutfitForWeather({
    required List<Map<String, dynamic>> wardrobe,
    required _LocalWeather weather,
    required bool isPremiumUser,
  }) {
    // Minimálna, lokálna logika (bez AI / bez refaktorov).
    // Cieľ: vybrať Top + Bottom + Shoes + voliteľný Outerwear podľa počasia.



    final clean = wardrobe.where((raw) {
      final isClean = raw['isClean'];
      if (isClean is bool) return isClean;
      return true; // ak pole neexistuje, berieme ako OK
    }).toList();

    Map<String, dynamic> normalize(Map<String, dynamic> raw) {
      // Zjednotíme známe polia (nové aj staré verzie dát).
      final m = Map<String, dynamic>.from(raw);
      m['name'] = (m['name'] ?? '').toString();
      m['category'] = (m['categoryKey'] ?? m['category'] ?? '').toString();
      m['subCategory'] = (m['subCategoryKey'] ?? m['subCategory'] ?? '').toString();
      m['mainGroup'] = (m['mainGroupKey'] ?? m['mainGroup'] ?? '').toString();
      m['colors'] = m['colors'] ?? m['color'] ?? const [];
      m['seasons'] = m['seasons'] ?? m['season'] ?? const [];
      return m;
    }

    final items = clean.map(normalize).toList();
    if (items.isEmpty) return null;

    bool matchesSeason(Map<String, dynamic> item) {
      final seasonsDyn = item['seasons'];
      final seasons = <String>[
        if (seasonsDyn is List) ...seasonsDyn.map((e) => e.toString()),
        if (seasonsDyn is String && seasonsDyn.trim().isNotEmpty) seasonsDyn,
      ].map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toList();

      if (seasons.isEmpty) return true;
      final target = weather.seasonKey; // napr. "jar"
      return seasons.any((s) => s.contains('cel') || s.contains(target));
    }

    final seasonal = items.where(matchesSeason).toList();
    final pool = seasonal.isNotEmpty ? seasonal : items;

    bool containsAny(String haystack, List<String> needles) {
      final h = haystack.toLowerCase();
      return needles.any((n) => h.contains(n));
    }

    String blob(Map<String, dynamic> it) {
      return [
        (it['name'] ?? '').toString(),
        (it['category'] ?? '').toString(),
        (it['subCategory'] ?? '').toString(),
        (it['mainGroup'] ?? '').toString(),
      ].join(' ').toLowerCase();
    }

    bool isTop(Map<String, dynamic> it) {
      final b = blob(it);
      return containsAny(b, [
        'trič',
        'trick',
        't-shirt',
        'top',
        'koše',
        'kosel',
        'blúz',
        'bluz',
        'sveter',
        'shirt',
        'blouse',
      ]);
    }

    bool isBottom(Map<String, dynamic> it) {
      final b = blob(it);
      return containsAny(b, [
        'nohav',
        'rifl',
        'džín',
        'dzín',
        'jeans',
        'pants',
        'sukn',
        'skirt',
        'krať',
        'krat',
        'short',
      ]);
    }

    bool isShoes(Map<String, dynamic> it) {
      final b = blob(it);
      return containsAny(b, [
        'topán',
        'topan',
        'tenis',
        'sneaker',
        'boots',
        'čiž',
        'ciz',
        'sandál',
        'sandal',
        'obuv',
        'shoes',
      ]);
    }

    bool isOuterwear(Map<String, dynamic> it) {
      final b = blob(it);
      return containsAny(b, [
        'bunda',
        'kabát',
        'kabat',
        'mikina',
        'sako',
        'blazer',
        'coat',
        'jacket',
        'hoodie',
      ]);
    }

    bool isHeavyOuterwear(Map<String, dynamic> it) {
      final b = blob(it);
      return containsAny(b, ['kabát', 'kabat', 'coat', 'parka', 'čiž', 'ciz']);
    }

    bool isLightOuterwear(Map<String, dynamic> it) {
      final b = blob(it);
      return containsAny(b, ['mikina', 'hoodie', 'sako', 'blazer', 'bunda', 'jacket']);
    }

    bool isNeutral(Map<String, dynamic> it) {
      final colorsDyn = it['colors'];
      final colors = <String>[
        if (colorsDyn is List) ...colorsDyn.map((e) => e.toString()),
        if (colorsDyn is String && colorsDyn.trim().isNotEmpty) colorsDyn,
      ].map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toList();

      if (colors.isEmpty) return false;
      return colors.any((c) {
        return c.contains('čier') ||
            c.contains('cier') ||
            c.contains('black') ||
            c.contains('biel') ||
            c.contains('white') ||
            c.contains('siv') ||
            c.contains('gray') ||
            c.contains('grey') ||
            c.contains('béž') ||
            c.contains('bez') ||
            c.contains('beige') ||
            c.contains('navy') ||
            c.contains('tmavomod');
      });
    }

    _Scored pickBest(List<Map<String, dynamic>> candidates, double Function(Map<String, dynamic>) score) {
      if (candidates.isEmpty) return _Scored(null, -1);
      Map<String, dynamic>? best;
      var bestScore = -1e9;
      for (final c in candidates) {
        final s = score(c);
        if (s > bestScore) {
          bestScore = s;
          best = c;
        }
      }
      return _Scored(best, bestScore);
    }

    double baseScore(Map<String, dynamic> it) {
      // Preferuj neutrálne a "basic" kúsky, ak existujú.
      final b = blob(it);
      var s = 0.0;
      if (isNeutral(it)) s += 2.0;
      if (b.contains('basic')) s += 1.0;
      if ((it['brand'] ?? '').toString().trim().isNotEmpty) s += 0.2; // jemná preferencia "reálneho" kusu
      return s;
    }

    final tops = pool.where(isTop).toList();
    final bottoms = pool.where(isBottom).toList();
    final shoes = pool.where(isShoes).toList();
    final outerwear = pool.where(isOuterwear).toList();

    if (tops.isEmpty || bottoms.isEmpty || shoes.isEmpty) return null;

    final temp = weather.tempC;
    final isWarm = temp >= 20;
    final isMild = temp >= 10 && temp < 20;
    final isCold = temp < 10;
    final needsOuterwear = isCold || weather.isRainy;

    final topPick = pickBest(tops, (it) => baseScore(it));
    final bottomPick = pickBest(bottoms, (it) {
      final b = blob(it);
      var s = baseScore(it);
      if (isWarm && (b.contains('krať') || b.contains('short'))) s += 1.0;
      return s;
    });
    final shoesPick = pickBest(shoes, (it) {
      final b = blob(it);
      var s = baseScore(it);
      if (weather.isRainy && (b.contains('čiž') || b.contains('ciz') || b.contains('boots'))) s += 1.0;
      if (isWarm && (b.contains('sandál') || b.contains('sandal'))) s += 1.0;
      return s;
    });

    Map<String, dynamic>? outerPick;
    if (!isWarm && outerwear.isNotEmpty && (needsOuterwear || isMild)) {
      outerPick = pickBest(outerwear, (it) {
        var s = baseScore(it);
        if (isCold && isHeavyOuterwear(it)) s += 1.2;
        if (isMild && isLightOuterwear(it)) s += 1.0;
        if (weather.isRainy && blob(it).contains('bunda')) s += 0.4;
        return s;
      }).item;
    }

    String labelFor(Map<String, dynamic> it, {required String fallback}) {
      final name = (it['name'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;
      final sub = (it['subCategory'] ?? '').toString().trim();
      if (sub.isNotEmpty) return sub;
      final cat = (it['category'] ?? '').toString().trim();
      if (cat.isNotEmpty) return cat;
      return fallback;
    }

    IconData iconForType(_HeroWearType type) {
      if (type == _HeroWearType.top) return Icons.checkroom;
      if (type == _HeroWearType.bottom) return Icons.style;
      if (type == _HeroWearType.shoes) return Icons.directions_run;
      return Icons.umbrella;
    }

    String fallbackLabelForType(_HeroWearType type) {
      if (type == _HeroWearType.top) return 'Vrchný diel';
      if (type == _HeroWearType.bottom) return 'Spodný diel';
      if (type == _HeroWearType.shoes) return 'Obuv';
      return 'Vrstva';
    }

    final selected = <_TypedWardrobePick>[
      _TypedWardrobePick(type: _HeroWearType.top, item: topPick.item!),
      _TypedWardrobePick(type: _HeroWearType.bottom, item: bottomPick.item!),
      _TypedWardrobePick(type: _HeroWearType.shoes, item: shoesPick.item!),
      if (outerPick != null)
        _TypedWardrobePick(type: _HeroWearType.outerwear, item: outerPick),
    ];

    final outfitTiles = selected
        .map((p) {
      final label = labelFor(p.item, fallback: fallbackLabelForType(p.type));
      final resolvedImageUrl = _resolveHeroPreviewImageUrl(p.item);
      final safeImageUrl = resolvedImageUrl?.trim();
      final brandRaw = (p.item['brand'] ?? '').toString().trim();

      return _HeroOutfitItem(
        type: p.type,
        icon: iconForType(p.type),
        label: label,
        brandLine: brandRaw.isNotEmpty ? brandRaw : null,
        imageUrl: (safeImageUrl?.isNotEmpty ?? false) ? safeImageUrl : null,
      );
    })
        .toList();

    final hasOuter = outerPick != null;

    final selectedReasonItems = <Map<String, dynamic>>[
      {
        ...topPick.item!,
        'typeKey': 'top',
      },
      {
        ...bottomPick.item!,
        'typeKey': 'bottom',
      },
      {
        ...shoesPick.item!,
        'typeKey': 'shoes',
      },
      if (outerPick != null)
        {
          ...outerPick,
          'typeKey': 'outerwear',
        },
    ];

    final reasonParagraph = OutfitReasonBuilder.build(
      tempC: weather.tempC,
      isRainy: weather.isRainy,
      isWindy: weather.isWindy,
      isPremium: isPremiumUser,
      selectedItems: selectedReasonItems,
      hasOuterwear: hasOuter,
      seasonLabel: weather.seasonLabel,
    );

    final rec = _HeroOutfitRecommendation(
      items: outfitTiles,
      reason: reasonParagraph,
    );

    // bezpečnostná kontrola
    if (rec.items.length < 3) return null;
    return rec;
  }

  String? _resolveHeroPreviewImageUrl(Map<String, dynamic> item) {
    String? value(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    final cutout = value(item['cutoutImageUrl']);
    if (cutout != null) return cutout;

    final clean = value(item['cleanImageUrl']);
    if (clean != null) return clean;


    final image = value(item['imageUrl']);
    if (image != null) return image;

    return null;
  }

  /// Visual experiment: outfit (~65%) + daily briefing (~35%) on one row; action bar below.
  Widget _heroRowExperiment({
    required BuildContext context,
    required _HeroBannerVM vm,
    required DateTime activeDate,
    required bool cardIsTomorrow,
    required List<_HeroOutfitItem> outfitItems,
    required _LocalWeather w,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _UnifiedHeroSurface(
          dayIndex: _dayIndex,
          onChangeDay: _setDayIndex,
          vm: vm,
          weather: w,
          isTomorrow: cardIsTomorrow,
          outfitItems: outfitItems,
        ),
        const SizedBox(height: 22),
        _HeroOutfitActionBar(
          onNewOutfit: _handleNewOutfitPressed,
          onSwapPiece: () async {
            await _handleSwapPieceTap(context);
          },
          onLike: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ďakujeme — obľúbené uložíme čoskoro.')),
            );
          },
        ),
      ],
    );
  }

  Widget _homeSectionsAfterHero({
    required BuildContext context,
    required _HeroBannerVM vm,
    required List<_HeroOutfitItem> outfitItems,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        HomeAiExplanationCard(
          body: vm.description,
          isPlaceholder: outfitItems.isEmpty,
        ),
        const SizedBox(height: 32),
        HomeRecommendedSection(onOpenRecommended: _openRecommended),
        const SizedBox(height: 32),
        HomeInspirationCarousel(
          onRecreateVibe: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Recreate vibe — čoskoro v šatníku.')),
            );
          },
        ),
        const SizedBox(height: 120),
      ],
    );
  }

  List<HomeQuickActionEntry> _quickActionEntries(BuildContext context) {
    return [
      (
        emoji: '👕',
        label: 'Add clothing',
        onTap: () => AddClothingScreen.openFromPicker(context),
      ),
      (
        emoji: '✈️',
        label: 'Trip planner',
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TripPlannerScreen()),
          );
        },
      ),
      (
        emoji: '✨',
        label: 'Recreate vibe',
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recreate vibe — čoskoro v šatníku.')),
          );
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    const wardrobeBg = HomeLuxuryPalette.bgBottom;
    final user = _auth.currentUser;
    final greetingName = _getGreetingName(user);

    final now = DateTime.now();
    final todayDate = now;
    final tomorrowDate = now.add(const Duration(days: 1));

    final activeDate = _isTomorrow ? tomorrowDate : todayDate;

    Widget greetingHeader() {
      return Builder(
        builder: (innerContext) {
          return HomeGreetingHeader(
            greetingLine: '$greetingName 👋',
            onOpenMenu: () => Scaffold.of(innerContext).openDrawer(),
          );
        },
      );
    }

    Widget scrollContent() {
      if (_isTomorrow && user == null) {
        final w = _weatherForDate(tomorrowDate);
        final vm = _HeroBannerVM(
          description:
              'Prihlás sa, aby som vedel odporučiť outfit podľa tvojho šatníka aj na zajtra.',
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            greetingHeader(),
            const SizedBox(height: 26),
            _heroRowExperiment(
              context: context,
              vm: vm,
              activeDate: activeDate,
              cardIsTomorrow: true,
              outfitItems: const <_HeroOutfitItem>[],
              w: w,
            ),
            _homeSectionsAfterHero(
              context: context,
              vm: vm,
              outfitItems: const <_HeroOutfitItem>[],
            ),
          ],
        );
      }

      if (_isTomorrow && user != null) {
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _userDocStream(user.uid),
          builder: (context, userSnap) {
            final data = userSnap.data?.data();
            final isPremiumUser = data?['isPremium'] == true ||
                data?['subscriptionStatus'] == 'premium';
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _wardrobeStream(user.uid),
              builder: (context, snap) {
                final docs = snap.data?.docs ?? const [];
                final wardrobe = docs.map((d) => d.data()).toList();
                final hero = _buildTodayHero(
                  date: tomorrowDate,
                  wardrobe: wardrobe,
                  isPremiumUser: isPremiumUser,
                );

                final vm = _HeroBannerVM(
                  description: hero.vm.description,
                );
                final w = _weatherForDate(tomorrowDate);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    greetingHeader(),
                    const SizedBox(height: 26),
                    _heroRowExperiment(
                      context: context,
                      vm: vm,
                      activeDate: activeDate,
                      cardIsTomorrow: true,
                      outfitItems: hero.outfitItems,
                      w: w,
                    ),
                    _homeSectionsAfterHero(
                      context: context,
                      vm: vm,
                      outfitItems: hero.outfitItems,
                    ),
                  ],
                );
              },
            );
          },
        );
      }

      if (user == null) {
        final w = _weatherForDate(todayDate);
        final vm = _HeroBannerVM(
          description:
              'Prihlás sa, aby som vedel odporučiť outfit podľa tvojho šatníka.',
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            greetingHeader(),
            const SizedBox(height: 26),
            _heroRowExperiment(
              context: context,
              vm: vm,
              activeDate: activeDate,
              cardIsTomorrow: false,
              outfitItems: const <_HeroOutfitItem>[],
              w: w,
            ),
            _homeSectionsAfterHero(
              context: context,
              vm: vm,
              outfitItems: const <_HeroOutfitItem>[],
            ),
          ],
        );
      }

      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _userDocStream(user.uid),
        builder: (context, userSnap) {
          final data = userSnap.data?.data();
          final isPremiumUser = data?['isPremium'] == true ||
              data?['subscriptionStatus'] == 'premium';
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _wardrobeStream(user.uid),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? const [];
              final wardrobe = docs.map((d) => d.data()).toList();
              final hero = _buildTodayHero(
                date: todayDate,
                wardrobe: wardrobe,
                isPremiumUser: isPremiumUser,
              );
              final w = _weatherForDate(todayDate);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  greetingHeader(),
                  const SizedBox(height: 26),
                  _heroRowExperiment(
                    context: context,
                    vm: hero.vm,
                    activeDate: activeDate,
                    cardIsTomorrow: false,
                    outfitItems: hero.outfitItems,
                    w: w,
                  ),
                  _homeSectionsAfterHero(
                    context: context,
                    vm: hero.vm,
                    outfitItems: hero.outfitItems,
                  ),
                ],
              );
            },
          );
        },
      );
    }

    return WillPopScope(
      onWillPop: () async => true,
      child: Scaffold(
        backgroundColor: wardrobeBg,
        drawer: _buildDrawer(context),
        body: Stack(
          clipBehavior: Clip.none,
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      HomeLuxuryPalette.bgTop,
                      HomeLuxuryPalette.bgMid,
                      HomeLuxuryPalette.bgBottom,
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-0.1, -0.9),
                      radius: 1.05,
                      colors: [
                        HomeLuxuryPalette.accentGlow.withOpacity(0.22),
                        HomeLuxuryPalette.accentGlow.withOpacity(0.10),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.28, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF0B0B0D).withOpacity(0.32),
                      Colors.transparent,
                      const Color(0xFF09090A).withOpacity(0.24),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      HomeLuxuryPalette.horizontalPadding,
                      18,
                      HomeLuxuryPalette.horizontalPadding,
                      36 + MediaQuery.of(context).padding.bottom + 72,
                    ),
                    child: scrollContent(),
                  ),
                  HomeQuickActionOrb(
                    actions: _quickActionEntries(context),
                    bottomOffset: 104,
                    rightOffset: 12,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openHeroEditSheet(BuildContext context) {
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
                      color: HomeLuxuryPalette.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Upraviť outfit',
                      style: TextStyle(
                        color: HomeLuxuryPalette.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SheetChoiceTile(
                    icon: Icons.swap_horiz,
                    title: 'Vymeniť kúsok',
                    subtitle: 'Vymeň jednu časť aktuálneho outfitu',
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Vymeniť kúsok – napojíme ďalší krok.'),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _SheetChoiceTile(
                    icon: Icons.layers_outlined,
                    title: 'Pridať vrstvu',
                    subtitle: 'Pridať ďalšiu zmysluplnú vrstvu do outfitu',
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Pridať vrstvu – napojíme ďalší krok.'),
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
    final user = _auth.currentUser;
    final displayName = (user?.displayName?.trim().isNotEmpty ?? false)
        ? user!.displayName!.trim()
        : 'Používateľ';
    final email = (user?.email?.trim().isNotEmpty ?? false)
        ? user!.email!.trim()
        : 'bez emailu';
    final initial = displayName.isNotEmpty
        ? displayName.characters.first.toUpperCase()
        : 'P';
    final photoUrl = user?.photoURL;

    return Drawer(
      backgroundColor: HomeLuxuryPalette.bgMid,
      child: Stack(
        children: [
      const Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
        gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          HomeLuxuryPalette.bgTop,
          HomeLuxuryPalette.bgMid,
          HomeLuxuryPalette.bgBottom,
        ],
      ),
    ),
    ),
    ),
    Positioned.fill(
    child: IgnorePointer(
    child: DecoratedBox(
    decoration: BoxDecoration(
    gradient: RadialGradient(
    center: const Alignment(-0.4, -0.9),
    radius: 1.1,
    colors: [
    HomeLuxuryPalette.accent.withOpacity(0.25),
    HomeLuxuryPalette.accent.withOpacity(0.10),
    Colors.transparent,
    ],
    stops: const [0.0, 0.35, 1.0],
    ),
    ),
    ),
    ),
    ),
    Positioned.fill(
    child: DecoratedBox(
    decoration: BoxDecoration(
    gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
    Colors.transparent,
    Color(0xFF09090A).withOpacity(0.25),
    ],
    ),
    ),
    ),
    ),
    SafeArea(
    child: Column(
    children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: HomeLuxuryPalette.border),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    HomeLuxuryPalette.bgTop,
                    HomeLuxuryPalette.bgMid,
                  ],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: HomeLuxuryPalette.accent.withOpacity(0.45),
                      ),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFFC8A36A),
                          Color(0xFF9D7C4C),
                        ],
                      ),
                    ),
                    child: ClipOval(
                      child: (photoUrl != null && photoUrl.trim().isNotEmpty)
                          ? Image.network(
                              photoUrl.trim(),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) {
                                return Center(
                                  child: Text(
                                    initial,
                                    style: const TextStyle(
                                      color: Color(0xFF191512),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 22,
                                    ),
                                  ),
                                );
                              },
                            )
                          : Center(
                              child: Text(
                                initial,
                                style: const TextStyle(
                                  color: Color(0xFF191512),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 22,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: HomeLuxuryPalette.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: HomeLuxuryPalette.textSecondary.withOpacity(0.9),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                children: [
            _drawerSectionLabel('SOCIÁLNE'),
            ListTile(
              iconColor: HomeLuxuryPalette.accent,
              textColor: HomeLuxuryPalette.accent,
              leading: Icon(Icons.people_outline, color: HomeLuxuryPalette.accent),
              title: Text(
                'Priatelia',
                style: TextStyle(color: HomeLuxuryPalette.accent),
              ),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FriendsScreen()),
                );
              },
            ),
            ListTile(
              iconColor: HomeLuxuryPalette.accent,
              textColor: HomeLuxuryPalette.accent,
              leading: Icon(Icons.diversity_2, color: HomeLuxuryPalette.accent),
              title: Text(
                'Správy a zladenie outfitov',
                style: TextStyle(color: HomeLuxuryPalette.accent),
              ),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MessagesScreen()),
                );
              },
            ),
            const SizedBox(height: 10),
            _drawerSectionLabel('AI'),
            ListTile(
              iconColor: HomeLuxuryPalette.accent,
              textColor: HomeLuxuryPalette.accent,
              leading: Icon(Icons.auto_awesome, color: HomeLuxuryPalette.accent),
              title: Text(
                'Analýza šatníka',
                style: TextStyle(color: HomeLuxuryPalette.accent),
              ),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WardrobeAnalysisScreen()),
                );
              },
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PremiumScreen()),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        HomeLuxuryPalette.surfaceSoft.withOpacity(0.92),
                        HomeLuxuryPalette.bgTop.withOpacity(0.95),
                      ],
                    ),
                    border: Border.all(
                      color: HomeLuxuryPalette.accent.withOpacity(0.42),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: HomeLuxuryPalette.accent.withOpacity(0.12),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: HomeLuxuryPalette.accent.withOpacity(0.16),
                          border: Border.all(
                            color: HomeLuxuryPalette.accent.withOpacity(0.40),
                          ),
                        ),
                        child: const Icon(
                          Icons.workspace_premium,
                          size: 18,
                          color: HomeLuxuryPalette.accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Premium',
                              style: TextStyle(
                                color: HomeLuxuryPalette.textPrimary,
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Odomkni pokročilé AI funkcie',
                              style: TextStyle(
                                color: HomeLuxuryPalette.textSecondary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _drawerSectionLabel('ÚČET'),
            ListTile(
              iconColor: HomeLuxuryPalette.accent,
              textColor: HomeLuxuryPalette.accent,
              leading: Icon(Icons.person_outline, color: HomeLuxuryPalette.accent),
              title: Text(
                'Profil',
                style: TextStyle(color: HomeLuxuryPalette.accent),
              ),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
            ),
            ListTile(
              iconColor: HomeLuxuryPalette.accent,
              textColor: HomeLuxuryPalette.accent,
              leading: Icon(Icons.settings, color: HomeLuxuryPalette.accent),
              title: Text(
                'Nastavenia',
                style: TextStyle(color: HomeLuxuryPalette.accent),
              ),
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
            Divider(color: HomeLuxuryPalette.border),
            ListTile(
              iconColor: HomeLuxuryPalette.accent,
              textColor: HomeLuxuryPalette.accent,
              leading: Icon(Icons.logout, color: HomeLuxuryPalette.accent),
              title: Text(
                'Odhlásiť sa',
                style: TextStyle(color: HomeLuxuryPalette.accent),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await _auth.signOut();
              },
            ),
    ],
    )
    ),
    ],
      ),
    );
  }

  Widget _drawerSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          color: HomeLuxuryPalette.textSecondary.withOpacity(0.72),
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
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

/// Inline weather — editorial typography only (no chips/capsules).
class _HeroInlineWeather extends StatelessWidget {
  const _HeroInlineWeather({
    required this.weather,
    required this.compact,
  });

  final _LocalWeather weather;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final gap = compact ? 20.0 : 26.0;
    final style = TextStyle(
      color: HomeLuxuryPalette.textSecondary.withOpacity(0.82),
      fontSize: compact ? 12.5 : 13,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
      height: 1.25,
    );
    final emojiStyle = TextStyle(
      fontSize: compact ? 13 : 14,
      height: 1.2,
    );

    final String condEmoji;
    final String condLabel;
    if (weather.isRainy) {
      condEmoji = '🌧';
      condLabel = 'Dážď';
    } else if (weather.isWindy) {
      condEmoji = '💨';
      condLabel = 'Vietor';
    } else {
      condEmoji = '☀';
      condLabel = 'Jasno';
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('🌡', style: emojiStyle),
        Text(' ${weather.tempC}°C', style: style),
        SizedBox(width: gap),
        Text(condEmoji, style: emojiStyle),
        Text(' $condLabel', style: style),
      ],
    );
  }
}

/// Gaps before outfit grid — keep in sync with [HomeDailyBriefingRow] embedded bands.
const double _kHeroGapAfterToggle = 8.0;
const double _kHeroGapBeforeGrid = 14.0;

/// Shared outfit / briefing body: bounded height — kept moderate so tiles stay elegant, not oversized.
double _heroSharedBodyHeight(BuildContext context) {
  final h = MediaQuery.sizeOf(context).height;
  return (h * 0.198).clamp(226.0, 286.0);
}

/// =======================
/// UNIFIED HERO (outfit + briefing)
/// =======================
class _UnifiedHeroSurface extends StatelessWidget {
  const _UnifiedHeroSurface({
    required this.dayIndex,
    required this.onChangeDay,
    required this.vm,
    required this.weather,
    required this.isTomorrow,
    required this.outfitItems,
  });

  final int dayIndex;
  final ValueChanged<int> onChangeDay;
  final _HeroBannerVM vm;
  final _LocalWeather weather;
  final bool isTomorrow;
  final List<_HeroOutfitItem> outfitItems;

  @override
  Widget build(BuildContext context) {
    const compact = true;
    final hasOutfitTiles = outfitItems.isNotEmpty;
    const minGridEmpty = 100.0;
    final radius = BorderRadius.circular(20);
    final sharedBodyH = _heroSharedBodyHeight(context);

    final outfitSwitcher = AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        final slide = Tween<Offset>(
          begin: const Offset(0.02, 0),
          end: Offset.zero,
        ).animate(anim);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(isTomorrow ? 'tomorrow' : 'today'),
        child: !hasOutfitTiles
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    vm.description,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color:
                          HomeLuxuryPalette.textSecondary.withOpacity(0.92),
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ),
              )
            : _HeroOutfitTilesGrid(
                items: outfitItems,
                compact: compact,
              ),
      ),
    );

    // Bounded [SizedBox] gives the outfit grid a definite height; 4× fills via [Expanded] rows.
    // Non–4-item grids scroll inside the same height without breaking flex elsewhere.
    final leftColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeroSegmentedDay(
          index: dayIndex,
          onChange: onChangeDay,
          compact: compact,
        ),
        const SizedBox(height: _kHeroGapAfterToggle),
        _HeroInlineWeather(
          weather: weather,
          compact: compact,
        ),
        const SizedBox(height: _kHeroGapBeforeGrid),
        SizedBox(
          height: sharedBodyH,
          width: double.infinity,
          child: hasOutfitTiles
              ? outfitSwitcher
              : ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: minGridEmpty),
                  child: outfitSwitcher,
                ),
        ),
      ],
    );

    final rightColumn = HomeDailyBriefingRow(
      unifiedEmbedded: true,
      unifiedSharedBodyHeight: sharedBodyH,
      baseTempC: weather.tempC,
      isRainy: weather.isRainy,
      isWindy: weather.isWindy,
      sideColumn: true,
      compact: true,
    );

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 14, 14),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                HomeLuxuryPalette.surfaceSoft.withOpacity(0.34),
                HomeLuxuryPalette.surface.withOpacity(0.22),
                HomeLuxuryPalette.bgMid.withOpacity(0.28),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 11,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: leftColumn,
                ),
              ),
              Expanded(
                flex: 9,
                child: rightColumn,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Glass segmented controls — replaces stacked gold CTAs.
class _HeroOutfitActionBar extends StatelessWidget {
  const _HeroOutfitActionBar({
    required this.onNewOutfit,
    required this.onSwapPiece,
    required this.onLike,
  });

  final VoidCallback onNewOutfit;
  final VoidCallback onSwapPiece;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.09)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                HomeLuxuryPalette.surfaceSoft.withOpacity(0.62),
                HomeLuxuryPalette.surface.withOpacity(0.42),
              ],
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          child: Row(
            children: [
              Expanded(
                child: _BarHit(
                  emoji: '❌',
                  label: 'Nový outfit',
                  onTap: onNewOutfit,
                ),
              ),
              _barDivider(),
              Expanded(
                child: _BarHit(
                  emoji: '🔄',
                  label: 'Vymeniť kúsok',
                  onTap: onSwapPiece,
                ),
              ),
              _barDivider(),
              Expanded(
                child: _BarHit(
                  emoji: '✅',
                  label: 'Páči sa mi',
                  onTap: onLike,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barDivider() {
    return Container(
      width: 1,
      height: 26,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      color: HomeLuxuryPalette.textSecondary.withOpacity(0.12),
    );
  }
}

class _BarHit extends StatelessWidget {
  const _BarHit({
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: Colors.white.withOpacity(0.06),
        highlightColor: Colors.white.withOpacity(0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: HomeLuxuryPalette.textPrimary.withOpacity(0.88),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    letterSpacing: 0.05,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroSegmentedDay extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChange;
  final bool compact;

  const _HeroSegmentedDay({
    required this.index,
    required this.onChange,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final height = compact ? 42.0 : 46.0;
    final outerPad = compact ? 5.0 : 6.0;
    final gap = compact ? 6.0 : 8.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          width: double.infinity,
          height: height,
          padding: EdgeInsets.all(outerPad),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withOpacity(0.11)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.09),
                Colors.white.withOpacity(0.03),
              ],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _SegItem(
                  label: 'Dnes',
                  active: index == 0,
                  compact: compact,
                  onTap: () => onChange(0),
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: _SegItem(
                  label: 'Zajtra',
                  active: index == 1,
                  compact: compact,
                  onTap: () => onChange(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegItem extends StatelessWidget {
  final String label;
  final bool active;
  final bool compact;
  final VoidCallback onTap;

  const _SegItem({
    required this.label,
    required this.active,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final fs = compact ? 13.5 : 14.5;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        splashColor: Colors.white.withOpacity(0.07),
        highlightColor: Colors.white.withOpacity(0.05),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: compact ? 7 : 9,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active
                  ? HomeLuxuryPalette.accent.withOpacity(0.42)
                  : Colors.transparent,
            ),
            gradient: active
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      HomeLuxuryPalette.accent.withOpacity(0.26),
                      HomeLuxuryPalette.accent.withOpacity(0.10),
                    ],
                  )
                : null,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: HomeLuxuryPalette.accent.withOpacity(0.32),
                      blurRadius: 16,
                      spreadRadius: 0,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: active
                    ? HomeLuxuryPalette.textPrimary
                    : HomeLuxuryPalette.textSecondary.withOpacity(0.92),
                fontSize: fs,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.15,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// =======================
/// Ostatné widgety (nezmenené)
/// =======================
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
          color: HomeLuxuryPalette.surfaceSoft.withOpacity(0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: HomeLuxuryPalette.border),
        ),
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: HomeLuxuryPalette.accent.withOpacity(0.11),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: HomeLuxuryPalette.accent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(color: HomeLuxuryPalette.textPrimary, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: HomeLuxuryPalette.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: HomeLuxuryPalette.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _HeroOutfitItem {
  final _HeroWearType type;
  final IconData icon;
  final String label;
  final String? brandLine;
  final String? imageUrl;

  const _HeroOutfitItem({
    required this.type,
    required this.icon,
    required this.label,
    this.brandLine,
    this.imageUrl,
  });
}

class _HeroBannerVM {
  final String description;

  const _HeroBannerVM({
    required this.description,
  });
}

class _HeroTodayState {
  final _HeroBannerVM vm;
  final List<_HeroOutfitItem> outfitItems;

  const _HeroTodayState({
    required this.vm,
    required this.outfitItems,
  });
}

enum _HeroWearType { top, bottom, shoes, outerwear }

class _TypedWardrobePick {
  final _HeroWearType type;
  final Map<String, dynamic> item;

  const _TypedWardrobePick({required this.type, required this.item});
}

class _Scored {
  final Map<String, dynamic>? item;
  final double score;
  const _Scored(this.item, this.score);
}

class _HeroOutfitRecommendation {
  final List<_HeroOutfitItem> items;
  final String reason;

  const _HeroOutfitRecommendation({
    required this.items,
    required this.reason,
  });
}

class _LocalWeather {
  final int tempC;
  final bool isRainy;
  final bool isWindy;
  final String seasonLabel; // Jar/Leto/Jeseň/Zima

  const _LocalWeather({
    required this.tempC,
    required this.isRainy,
    required this.isWindy,
    required this.seasonLabel,
  });

  static _LocalWeather fallbackFor(DateTime date) {
    // Jednoduché, deterministické hodnoty aby UI fungovalo aj offline.
    final month = date.month;
    final seasonLabel = (month >= 3 && month <= 5)
        ? 'Jar'
        : (month >= 6 && month <= 8)
        ? 'Leto'
        : (month >= 9 && month <= 11)
        ? 'Jeseň'
        : 'Zima';

    int baseTemp;
    if (seasonLabel == 'Zima') {
      baseTemp = 2;
    } else if (seasonLabel == 'Jar') {
      baseTemp = 10;
    } else if (seasonLabel == 'Leto') {
      baseTemp = 24;
    } else {
      baseTemp = 12; // Jeseň
    }

    // jemné kolísanie podľa dňa v mesiaci (-2..+2)
    final delta = (date.day % 5) - 2;
    final tempC = baseTemp + delta;

    // šanca na dážď častejšie na jar/jeseň (deterministicky)
    final rainyMonths = <int>{3, 4, 5, 9, 10, 11};
    final isRainy = rainyMonths.contains(month) && (date.day % 3 == 0);
    final isWindy = date.day % 4 == 0;

    return _LocalWeather(
      tempC: tempC,
      isRainy: isRainy,
      isWindy: isWindy,
      seasonLabel: seasonLabel,
    );
  }

  String get seasonKey {
    final s = seasonLabel.toLowerCase();
    if (s.contains('jar')) return 'jar';
    if (s.contains('let')) return 'let';
    if (s.contains('jese')) return 'jese';
    return 'zim';
  }

  String get summarySubtitle {
    final parts = <String>[seasonLabel, '$tempC°C'];
    if (isWindy) parts.add('vietor');
    if (isRainy) parts.add('dážď');
    if (!isWindy && !isRainy) parts.add('jasno');
    return parts.join(' • ');
  }

}

List<_HeroOutfitItem> _orderedHeroOutfitItems(List<_HeroOutfitItem> items) {
  final orderedItems = <_HeroOutfitItem>[];
  void addByType(_HeroWearType type) {
    for (final item in items) {
      if (item.type == type) {
        orderedItems.add(item);
        break;
      }
    }
  }

  addByType(_HeroWearType.outerwear);
  addByType(_HeroWearType.top);
  addByType(_HeroWearType.bottom);
  addByType(_HeroWearType.shoes);
  return orderedItems;
}

class _HeroOutfitTilesGrid extends StatelessWidget {
  final List<_HeroOutfitItem> items;
  final bool compact;

  const _HeroOutfitTilesGrid({
    required this.items,
    this.compact = false,
  });

  /// Same layouts as before, without a bounded parent — used inside [SingleChildScrollView].
  Widget _buildLooseLayout({
    required double maxW,
    required int n,
    required Widget Function(int i) tile,
  }) {
    final narrow = maxW < 168;
    final gap = narrow ? 8.0 : (compact ? 10.0 : 14.0);

    if (n <= 3) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < n; i++) ...[
            if (i > 0) SizedBox(height: gap),
            tile(i),
          ],
        ],
      );
    }

    if (n == 4) {
      final rowGap = gap + 14;
      const tileAspect = 0.82;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: gap,
          mainAxisSpacing: rowGap,
          childAspectRatio: tileAspect,
        ),
        itemCount: 4,
        itemBuilder: (_, i) => tile(i),
      );
    }

    if (n == 5) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            childAspectRatio: 1,
            children: [tile(0), tile(1), tile(2), tile(3)],
          ),
          SizedBox(height: gap),
          Align(
            alignment: Alignment.center,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: AspectRatio(
                aspectRatio: 1,
                child: tile(4),
              ),
            ),
          ),
        ],
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: gap,
        mainAxisSpacing: gap,
        childAspectRatio: 1,
      ),
      itemCount: n,
      itemBuilder: (_, i) => tile(i),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ordered = _orderedHeroOutfitItems(items);
    final display = ordered.length > 6 ? ordered.sublist(0, 6) : ordered;
    final n = display.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final narrow = maxW < 168;
        final gap = narrow ? 8.0 : (compact ? 10.0 : 14.0);
        final maxH = constraints.maxHeight;
        final heightBounded =
            maxH.isFinite && maxH < double.infinity && maxH > 1;

        Widget tile(int i) => _HeroOutfitTileCard(
              item: display[i],
              compact: compact,
            );

        Widget tileFill(int i) => _HeroOutfitTileCard(
              item: display[i],
              compact: compact,
              expandCell: true,
            );

        if (n == 0) {
          return const SizedBox.shrink();
        }

        // 2×2 fills the shared hero body; equal row heights; no shrink-wrap grid height.
        if (n == 4 && heightBounded) {
          final rowGap = gap + 8;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: tileFill(0)),
                    SizedBox(width: gap),
                    Expanded(child: tileFill(1)),
                  ],
                ),
              ),
              SizedBox(height: rowGap),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: tileFill(2)),
                    SizedBox(width: gap),
                    Expanded(child: tileFill(3)),
                  ],
                ),
              ),
            ],
          );
        }

        final loose = _buildLooseLayout(
          maxW: maxW,
          n: n,
          tile: tile,
        );

        if (heightBounded) {
          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: loose,
          );
        }

        return loose;
      },
    );
  }
}

/// Scale factors for PNG previews — tops/pants run large if over-scaled; shoes stay slightly bolder.
double _heroOutfitImageScale(_HeroWearType type, {required bool compact}) {
  if (compact) {
    switch (type) {
      case _HeroWearType.top:
        return 1.07;
      case _HeroWearType.bottom:
        return 1.05;
      case _HeroWearType.outerwear:
        return 1.12;
      case _HeroWearType.shoes:
        return 1.64;
    }
  }
  switch (type) {
    case _HeroWearType.top:
      return 1.02;
    case _HeroWearType.bottom:
      return 1.0;
    case _HeroWearType.outerwear:
      return 1.06;
    case _HeroWearType.shoes:
      return 1.52;
  }
}

class _HeroOutfitTileCard extends StatelessWidget {
  const _HeroOutfitTileCard({
    required this.item,
    this.compact = false,
    this.expandCell = false,
  });

  final _HeroOutfitItem item;
  final bool compact;

  /// Fill a flex cell in the 2×2 shared-height grid (non-square cell).
  final bool expandCell;

  @override
  Widget build(BuildContext context) {
    final outerR = compact ? 16.0 : 18.0;
    final innerR = compact ? 14.0 : 14.0;
    final pad = compact ? 5.0 : 5.0;

    final core = Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(outerR),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.012),
            Colors.white.withOpacity(0.003),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(innerR),
        child: ColoredBox(
          color: HomeLuxuryPalette.bgMid.withOpacity(0.20),
          child: _HeroOutfitImageView(
            imageUrl: item.imageUrl,
            fallbackIcon: item.icon,
            wearType: item.type,
            compact: compact,
          ),
        ),
      ),
    );

    if (expandCell) {
      return SizedBox.expand(child: core);
    }

    return AspectRatio(
      aspectRatio: 1,
      child: core,
    );
  }
}

class _HeroOutfitImageView extends StatelessWidget {
  final String? imageUrl;
  final IconData fallbackIcon;
  final _HeroWearType wearType;
  final bool compact;

  const _HeroOutfitImageView({
    required this.imageUrl,
    required this.fallbackIcon,
    required this.wearType,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedImageUrl = imageUrl?.trim();
    final hasImage = normalizedImageUrl != null && normalizedImageUrl.isNotEmpty;
    final ph = compact ? 26.0 : 36.0;
    final inset = compact ? 5.0 : 6.0;
    final scale = _heroOutfitImageScale(wearType, compact: compact);

    Widget previewBody({required Widget child}) {
      return Padding(
        padding: EdgeInsets.all(inset),
        child: Center(
          child: Transform.scale(
            scale: scale,
            child: child,
          ),
        ),
      );
    }

    if (!hasImage) {
      return previewBody(
        child: _OutfitPreviewPlaceholder(icon: fallbackIcon, size: ph),
      );
    }

    return previewBody(
      child: Image.network(
        normalizedImageUrl,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        alignment: Alignment.center,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _OutfitPreviewPlaceholder(icon: fallbackIcon, size: ph);
        },
        errorBuilder: (context, error, stackTrace) =>
            _OutfitPreviewPlaceholder(icon: fallbackIcon, size: ph),
      ),
    );
  }
}

class _OutfitPreviewPlaceholder extends StatelessWidget {
  final IconData icon;
  final double size;

  const _OutfitPreviewPlaceholder({
    required this.icon,
    this.size = 34,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        icon,
        color: HomeLuxuryPalette.textSecondary.withOpacity(0.92),
        size: size,
      ),
    );
  }
}

