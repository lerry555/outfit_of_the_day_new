import'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';



import 'add_clothing_screen.dart';
import 'calendar_screen.dart';
import 'friends_screen.dart';
import 'messages_screen.dart';
import 'premium_screen.dart';
import 'recommended_screen.dart';
import 'select_outfit_screen.dart';
import 'stylist_chat_screen.dart';
import 'user_preferences_screen.dart';
import 'wardrobe_analysis_screen.dart';
import 'wardrobe_screen.dart';
import '../utils/outfit_reason_builder.dart';
class _HomeLuxuryPalette {
  static const Color bgTop = Color(0xFF111111);
  static const Color bgMid = Color(0xFF0C0C0D);
  static const Color bgBottom = Color(0xFF080809);

  static const Color surface = Color(0xFF151517);
  static const Color surfaceSoft = Color(0xFF1B1B1F);
  static const Color surfaceElevated = Color(0xFF242329);

  static const Color textPrimary = Color(0xFFF1F0EC);
  static const Color textSecondary = Color(0xFFAAA59B);

  static const Color accent = Color(0xFFC8A36A);
  static const Color accentSoft = Color(0xFF9D7C4C);
  static const Color accentGlow = Color(0x66C8A36A);
  static const Color border = Color(0x26FFFFFF);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ✅ prepínač Dnes/Zajtra (UI)
  int _dayIndex = 0; // 0 = dnes, 1 = zajtra
  bool get _isTomorrow => _dayIndex == 1;

  void _setDayIndex(int index) => setState(() => _dayIndex = index);

  Stream<QuerySnapshot<Map<String, dynamic>>> _wardrobeStream(String uid) {
    return _firestore.collection('users').doc(uid).collection('wardrobe').snapshots();
  }

  _LocalWeather _weatherForDate(DateTime date) {
    // Dočasné bezpečné počasie (kým nie je napojený zdroj).
    // Cieľ: nikdy necrashnúť a vždy mať zmysluplný text.
    return _LocalWeather.fallbackFor(date);
  }

  _HeroTodayState _buildTodayHero({
    required DateTime date,
    required List<Map<String, dynamic>> wardrobe,
  }) {
    final w = _weatherForDate(date);
    final rec = _recommendOutfitForWeather(wardrobe: wardrobe, weather: w);

    if (rec == null) {
      return _HeroTodayState(
        vm: _HeroBannerVM(
          title: 'Dnešný outfit',
          subtitle: w.summarySubtitle,
          description:
          'Dnes zatiaľ nemám dosť vhodných kúskov na kompletný outfit. Skús pridať viac oblečenia do šatníka.',
          chips: w.toHeroChips(),
        ),
        outfitItems: const <_HeroOutfitItem>[],
      );
    }

    return _HeroTodayState(
      vm: _HeroBannerVM(
        title: 'Dnešný outfit',
        subtitle: w.summarySubtitle,
        description: rec.reason,
        chips: w.toHeroChips(),
      ),
      outfitItems: rec.items,
    );
  }

  _HeroOutfitRecommendation? _recommendOutfitForWeather({
    required List<Map<String, dynamic>> wardrobe,
    required _LocalWeather weather,
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

      print(
        'HERO TILE: label=${labelFor(p.item, fallback: fallbackLabelForType(p.type))} image=$resolvedImageUrl',
      );

      return _HeroOutfitItem(
        type: p.type,
        icon: iconForType(p.type),
        label: label,
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
          ...outerPick!,
          'typeKey': 'outerwear',
        },
    ];

    final reasonParagraph = OutfitReasonBuilder.build(
      tempC: weather.tempC,
      isRainy: weather.isRainy,
      isWindy: weather.isWindy,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const wardrobeBg = _HomeLuxuryPalette.bgBottom;
    final user = _auth.currentUser;
    final greetingName = _getGreetingName(user);

    final now = DateTime.now();
    final todayDate = now;
    final tomorrowDate = now.add(const Duration(days: 1));



    final activeDate = _isTomorrow ? tomorrowDate : todayDate;

    return WillPopScope(
      onWillPop: () async => true,
      child: Scaffold(
        backgroundColor: wardrobeBg,
        drawer: _buildDrawer(context),

        // ✅ FAB odstránený - pridávanie je v rýchlych akciách
        body: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _HomeLuxuryPalette.bgTop,
                      _HomeLuxuryPalette.bgMid,
                      _HomeLuxuryPalette.bgBottom,
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
                        _HomeLuxuryPalette.accentGlow.withOpacity(0.22),
                        _HomeLuxuryPalette.accentGlow.withOpacity(0.10),
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Builder(
                          builder: (context) => IconButton(
                            onPressed: () => Scaffold.of(context).openDrawer(),
                            icon: Icon(
                              Icons.menu,
                              color: _HomeLuxuryPalette.textSecondary,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Outfit Of The Day',
                          style: TextStyle(
                            color: _HomeLuxuryPalette.textSecondary.withOpacity(0.7),
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '$greetingName 👋',
                      style: TextStyle(
                        color: _HomeLuxuryPalette.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isTomorrow
                          ? 'Poďme vybrať tvoj zajtrajší outfit.'
                          : 'Poďme vybrať tvoj dnešný outfit.',
                      style: TextStyle(
                        color: _HomeLuxuryPalette.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 18),
                  if (_isTomorrow && user == null)
                    _HeroDayCard(
                      dayIndex: _dayIndex,
                      onChangeDay: _setDayIndex,
                      vm: _HeroBannerVM(
                        title: 'Zajtrajší outfit',
                        subtitle: _weatherForDate(tomorrowDate).summarySubtitle,
                        description:
                        'Prihlás sa, aby som vedel odporučiť outfit podľa tvojho šatníka aj na zajtra.',
                        chips: _weatherForDate(tomorrowDate).toHeroChips(),
                      ),
                      date: activeDate,
                      isTomorrow: true,
                      outfitItems: const <_HeroOutfitItem>[],
                      onTapSwapOne: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Vymeniť kúsok – napojíme neskôr.')),
                        );
                      },
                      onTapNewOutfit: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Nový outfit – napojíme neskôr.')),
                        );
                      },
                      onTapEdit: () => _openHeroEditSheet(context),
                    )
                  else if (_isTomorrow && user != null)
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _wardrobeStream(user.uid),
                      builder: (context, snap) {
                        final docs = snap.data?.docs ?? const [];
                        final wardrobe = docs.map((d) => d.data()).toList();
                        final hero = _buildTodayHero(date: tomorrowDate, wardrobe: wardrobe);

                        final tomorrowHero = _HeroTodayState(
                          vm: _HeroBannerVM(
                            title: 'Zajtrajší outfit',
                            subtitle: hero.vm.subtitle,
                            description: hero.vm.description,
                            chips: hero.vm.chips,
                          ),
                          outfitItems: hero.outfitItems,
                        );

                        return _HeroDayCard(
                          dayIndex: _dayIndex,
                          onChangeDay: _setDayIndex,
                          vm: tomorrowHero.vm,
                          date: activeDate,
                          isTomorrow: true,
                          outfitItems: tomorrowHero.outfitItems,
                          onTapSwapOne: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Vymeniť kúsok – napojíme neskôr.')),
                            );
                          },
                          onTapNewOutfit: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Nový outfit – napojíme neskôr.')),
                            );
                          },
                          onTapEdit: () => _openHeroEditSheet(context),
                        );
                      },
                    )
                  else if (user == null)
                  _HeroDayCard(
                    dayIndex: _dayIndex,
                    onChangeDay: _setDayIndex,
                    vm: _HeroBannerVM(
                      title: 'Dnešný outfit',
                      subtitle: _weatherForDate(todayDate).summarySubtitle,
                      description:
                      'Prihlás sa, aby som vedel odporučiť outfit podľa tvojho šatníka.',
                      chips: _weatherForDate(todayDate).toHeroChips(),
                    ),
                    date: activeDate,
                    isTomorrow: false,
                    outfitItems: const <_HeroOutfitItem>[],
                    onTapSwapOne: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Vymeniť kúsok – napojíme neskôr.')),
                      );
                    },
                    onTapNewOutfit: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Nový outfit – napojíme neskôr.')),
                      );
                    },
                    onTapEdit: () => _openHeroEditSheet(context),
                  )
                else
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _wardrobeStream(user.uid),
                    builder: (context, snap) {
                      final docs = snap.data?.docs ?? const [];
                      final wardrobe = docs.map((d) => d.data()).toList();
                      final hero = _buildTodayHero(date: todayDate, wardrobe: wardrobe);

                      return _HeroDayCard(
                        dayIndex: _dayIndex,
                        onChangeDay: _setDayIndex,
                        vm: hero.vm,
                        date: activeDate,
                        isTomorrow: false,
                        outfitItems: hero.outfitItems,
                        onTapSwapOne: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Vymeniť kúsok – napojíme neskôr.')),
                          );
                        },
                        onTapNewOutfit: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Nový outfit – napojíme neskôr.')),
                          );
                        },
                        onTapEdit: () => _openHeroEditSheet(context),
                      );
                    },
                  ),

                const SizedBox(height: 14),

                _QuickActionsGrid(
                  items: [
                    _QuickAction(
                      icon: Icons.add_circle_outline,
                      label: 'Pridať',
                      onTap: () => AddClothingScreen.openFromPicker(context),
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
                      icon: Icons.shopping_bag_outlined,
                      label: 'Shop',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RecommendedScreen(initialTab: 0),
                          ),
                        );
                      },
                    ),
                    _QuickAction(
                      icon: Icons.travel_explore,
                      label: 'Trip',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Trip planner – doplníme ako ďalší krok.'),
                          ),
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 22),

                const SizedBox(height: 18),

                _RecommendedCarouselV2(
                  onOpenRecommended: _openRecommended,
                ),
                ],
              ),
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
                      color: _HomeLuxuryPalette.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Upraviť outfit',
                      style: TextStyle(
                        color: _HomeLuxuryPalette.textPrimary,
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
      backgroundColor: _HomeLuxuryPalette.bgMid,
      child: Stack(
        children: [
      const Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
        gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          _HomeLuxuryPalette.bgTop,
          _HomeLuxuryPalette.bgMid,
          _HomeLuxuryPalette.bgBottom,
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
    _HomeLuxuryPalette.accent.withOpacity(0.25),
    _HomeLuxuryPalette.accent.withOpacity(0.10),
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
                border: Border.all(color: _HomeLuxuryPalette.border),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _HomeLuxuryPalette.bgTop,
                    _HomeLuxuryPalette.bgMid,
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
                        color: _HomeLuxuryPalette.accent.withOpacity(0.45),
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
                            color: _HomeLuxuryPalette.textPrimary,
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
                            color: _HomeLuxuryPalette.textSecondary.withOpacity(0.9),
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
              iconColor: _HomeLuxuryPalette.accent,
              textColor: _HomeLuxuryPalette.accent,
              leading: Icon(Icons.people_outline, color: _HomeLuxuryPalette.accent),
              title: Text(
                'Priatelia',
                style: TextStyle(color: _HomeLuxuryPalette.accent),
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
              iconColor: _HomeLuxuryPalette.accent,
              textColor: _HomeLuxuryPalette.accent,
              leading: Icon(Icons.diversity_2, color: _HomeLuxuryPalette.accent),
              title: Text(
                'Správy a zladenie outfitov',
                style: TextStyle(color: _HomeLuxuryPalette.accent),
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
              iconColor: _HomeLuxuryPalette.accent,
              textColor: _HomeLuxuryPalette.accent,
              leading: Icon(Icons.auto_awesome, color: _HomeLuxuryPalette.accent),
              title: Text(
                'Analýza šatníka',
                style: TextStyle(color: _HomeLuxuryPalette.accent),
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
                        _HomeLuxuryPalette.surfaceSoft.withOpacity(0.92),
                        _HomeLuxuryPalette.bgTop.withOpacity(0.95),
                      ],
                    ),
                    border: Border.all(
                      color: _HomeLuxuryPalette.accent.withOpacity(0.42),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _HomeLuxuryPalette.accent.withOpacity(0.12),
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
                          color: _HomeLuxuryPalette.accent.withOpacity(0.16),
                          border: Border.all(
                            color: _HomeLuxuryPalette.accent.withOpacity(0.40),
                          ),
                        ),
                        child: const Icon(
                          Icons.workspace_premium,
                          size: 18,
                          color: _HomeLuxuryPalette.accent,
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
                                color: _HomeLuxuryPalette.textPrimary,
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Odomkni pokročilé AI funkcie',
                              style: TextStyle(
                                color: _HomeLuxuryPalette.textSecondary,
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
              iconColor: _HomeLuxuryPalette.accent,
              textColor: _HomeLuxuryPalette.accent,
              leading: Icon(Icons.settings, color: _HomeLuxuryPalette.accent),
              title: Text(
                'Nastavenia',
                style: TextStyle(color: _HomeLuxuryPalette.accent),
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
            Divider(color: _HomeLuxuryPalette.border),
            ListTile(
              iconColor: _HomeLuxuryPalette.accent,
              textColor: _HomeLuxuryPalette.accent,
              leading: Icon(Icons.logout, color: _HomeLuxuryPalette.accent),
              title: Text(
                'Odhlásiť sa',
                style: TextStyle(color: _HomeLuxuryPalette.accent),
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
          color: _HomeLuxuryPalette.textSecondary.withOpacity(0.72),
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

/// =======================
/// HERO DAY CARD
/// =======================
class _HeroDayCard extends StatelessWidget {
  final int dayIndex; // 0 dnes, 1 zajtra
  final ValueChanged<int> onChangeDay;

  final _HeroBannerVM vm;
  final DateTime date;
  final bool isTomorrow;

  final List<_HeroOutfitItem> outfitItems;

  final VoidCallback onTapSwapOne;
  final VoidCallback onTapNewOutfit;
  final VoidCallback onTapEdit;

  const _HeroDayCard({
    required this.dayIndex,
    required this.onChangeDay,
    required this.vm,
    required this.date,
    required this.isTomorrow,
    required this.outfitItems,
    required this.onTapSwapOne,
    required this.onTapNewOutfit,
    required this.onTapEdit,
  });

  String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}';
  }

  @override
  Widget build(BuildContext context) {
    final hasOutfitTiles = outfitItems.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vm.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _HomeLuxuryPalette.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      vm.subtitle,
                      style: TextStyle(
                        color: _HomeLuxuryPalette.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _HeroSegmentedDay(
                  index: dayIndex,
                  onChange: onChangeDay,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Wrap(spacing: 8, children: vm.chips),
          const SizedBox(height: 10),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
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
            child: ConstrainedBox(
              key: ValueKey(isTomorrow ? 'tomorrow' : 'today'),
              constraints: const BoxConstraints(minHeight: 230),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasOutfitTiles)
                    _HeroOutfitTiles2Rows(
                      items: outfitItems,
                      description: vm.description,
                    )
                  else
                    Text(
                      vm.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _HomeLuxuryPalette.textSecondary,
                        fontSize: 12.6,
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: _HeroPrimaryButton(
                  text: 'Upraviť outfit',
                  onTap: onTapEdit,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: _HeroPrimaryButton(
                  text: 'Nový outfit',
                  onTap: onTapNewOutfit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroSegmentedDay extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChange;

  const _HeroSegmentedDay({
    required this.index,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 148,
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _HomeLuxuryPalette.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegItem(
              label: 'Dnes',
              active: index == 0,
              onTap: () => onChange(0),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _SegItem(
              label: 'Zajtra',
              active: index == 1,
              onTap: () => onChange(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegItem extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SegItem({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: active ? _HomeLuxuryPalette.surfaceElevated : Colors.transparent,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? _HomeLuxuryPalette.textPrimary : _HomeLuxuryPalette.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
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
          color: _HomeLuxuryPalette.surfaceSoft.withOpacity(0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _HomeLuxuryPalette.border),
        ),
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: _HomeLuxuryPalette.accent.withOpacity(0.11),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: _HomeLuxuryPalette.accent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(color: _HomeLuxuryPalette.textPrimary, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: _HomeLuxuryPalette.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: _HomeLuxuryPalette.textSecondary),
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
  final String? imageAssetPath;
  final String? imageUrl;

  const _HeroOutfitItem({
    required this.type,
    required this.icon,
    required this.label,
    this.imageAssetPath,
    this.imageUrl,
  });
}

class _HeroBannerVM {
  final String title;
  final String subtitle;
  final String description;
  final List<_HeroChip> chips;

  const _HeroBannerVM({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.chips,
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

  List<_HeroChip> toHeroChips() {
    final chips = <_HeroChip>[
      _HeroChip(icon: Icons.thermostat, label: '$tempC°C'),
    ];
    if (isWindy) chips.add(const _HeroChip(icon: Icons.air, label: 'vietor'));
    if (isRainy) chips.add(const _HeroChip(icon: Icons.grain, label: 'dážď'));
    if (!isWindy && !isRainy) chips.add(const _HeroChip(icon: Icons.wb_sunny, label: 'jasno'));
    return chips;
  }
}

class _HeroOutfitTiles2Rows extends StatelessWidget {
  final List<_HeroOutfitItem> items;
  final String description;

  const _HeroOutfitTiles2Rows({
    required this.items,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          description,
          maxLines: 6,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _HomeLuxuryPalette.textSecondary,
            fontSize: 12.6,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: orderedItems
              .map((item) => _HeroOutfitMiniTile(item: item))
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _HeroOutfitMiniTile extends StatelessWidget {
  final _HeroOutfitItem item;
  const _HeroOutfitMiniTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _HomeLuxuryPalette.border),
        color: _HomeLuxuryPalette.surface.withOpacity(0.58),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10), // menší radius vo vnútri
        child: SizedBox.expand(
          child: _HeroOutfitImageView(
            imageUrl: item.imageUrl,
            fallbackIcon: item.icon,
          ),
        ),
      ),
    );
  }
}

class _HeroOutfitImageView extends StatelessWidget {
  final String? imageUrl;
  final IconData fallbackIcon;

  const _HeroOutfitImageView({
    required this.imageUrl,
    required this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedImageUrl = imageUrl?.trim();
    final hasImage = normalizedImageUrl != null && normalizedImageUrl.isNotEmpty;

    if (!hasImage) {
      return _OutfitPreviewPlaceholder(icon: fallbackIcon);
    }

    final isShoes = fallbackIcon == Icons.directions_run;

    return Center(
      child: Transform.scale(
        scale: isShoes ? 1.75 : 1.45,
        child: Image.network(
          normalizedImageUrl,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return _OutfitPreviewPlaceholder(icon: fallbackIcon);
          },
          errorBuilder: (context, error, stackTrace) =>
              _OutfitPreviewPlaceholder(icon: fallbackIcon),
        ),
      ),
    );
  }
}

class _OutfitPreviewPlaceholder extends StatelessWidget {
  final IconData icon;
  const _OutfitPreviewPlaceholder({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        icon,
        color: _HomeLuxuryPalette.textSecondary.withOpacity(0.92),
        size: 22,
      ),
    );
  }
}

class _HeroGlassButton extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  const _HeroGlassButton({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _HomeLuxuryPalette.surfaceSoft.withOpacity(0.72),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _HomeLuxuryPalette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: _HomeLuxuryPalette.textSecondary),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                color: _HomeLuxuryPalette.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroPrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _HeroPrimaryButton({
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _HomeLuxuryPalette.accent.withOpacity(0.90),
              _HomeLuxuryPalette.accentSoft.withOpacity(0.94),
            ],
          ),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _HomeLuxuryPalette.accent.withOpacity(0.45)),
          boxShadow: [
            BoxShadow(
              color: _HomeLuxuryPalette.accent.withOpacity(0.26),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              text,
              style: TextStyle(
                color: const Color(0xFF191512),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.arrow_forward_ios,
              color: const Color(0xFF191512).withOpacity(0.8),
              size: 16,
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
        color: _HomeLuxuryPalette.surface.withOpacity(0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _HomeLuxuryPalette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _HomeLuxuryPalette.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: _HomeLuxuryPalette.textSecondary, fontSize: 12),
          ),
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
          border: Border.all(color: Colors.white.withOpacity(0.06)),
          color: _HomeLuxuryPalette.surfaceSoft.withOpacity(0.78),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.20),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _HomeLuxuryPalette.accent.withOpacity(0.11),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(action.icon, color: _HomeLuxuryPalette.accent, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              action.label,
              style: TextStyle(
                color: _HomeLuxuryPalette.textSecondary,
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
              Text(
                title,
                style: TextStyle(
                  color: _HomeLuxuryPalette.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(color: _HomeLuxuryPalette.textSecondary, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            child: Text('Zobraziť', style: TextStyle(color: _HomeLuxuryPalette.accent)),
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
          height: 220,
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
          color: _HomeLuxuryPalette.surfaceSoft.withOpacity(0.86),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.22),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
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
                    gradient: LinearGradient(
                      colors: [
                        _HomeLuxuryPalette.surfaceElevated,
                        _HomeLuxuryPalette.surface,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      item.icon,
                      color: _HomeLuxuryPalette.accent.withOpacity(0.34),
                      size: 42,
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: _HomeLuxuryPalette.surface.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withOpacity(0.07)),
                    ),
                    child: Text(
                      item.matchLabel,
                      style: TextStyle(
                        color: _HomeLuxuryPalette.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              item.brand,
              style: TextStyle(
                color: _HomeLuxuryPalette.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.name,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _HomeLuxuryPalette.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(item.price,
                    style: TextStyle(
                      color: _HomeLuxuryPalette.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    )),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: _HomeLuxuryPalette.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.bookmark_border,
                    color: _HomeLuxuryPalette.textSecondary,
                    size: 18,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

