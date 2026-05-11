import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../Services/calendar_outfit_service.dart';
import '../Services/date_weather_service.dart';
import '../models/calendar_outfit_models.dart';
import 'premium_screen.dart';
import '../widgets/calendar_day_detail_card.dart';
import '../widgets/calendar_month_grid.dart';

class CalendarOutfitScreen extends StatefulWidget {
  const CalendarOutfitScreen({super.key});

  @override
  State<CalendarOutfitScreen> createState() => _CalendarOutfitScreenState();
}

class _CalendarOutfitScreenState extends State<CalendarOutfitScreen> {
  final _auth = FirebaseAuth.instance;
  final _service = CalendarOutfitService();

  late DateTime _focusedMonth;
  late DateTime _selectedDay;

  late Future<DateWeatherSnapshot> _weatherFuture;

  bool _isGenerating = false;
  CalendarOutfitDay? _selectedDayOverride;
  int _generatedOutfitsToday = 0;

  /// Optimistic dates for red dot while Firestore stream updates.
  final Set<String> _optimisticOutfitKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _focusedMonth = DateTime.now();
    _selectedDay =
        DateTime(_focusedMonth.year, _focusedMonth.month, _focusedMonth.day);
    _weatherFuture = Future.value(
      DateWeatherService.getWeatherForDate(_selectedDay),
    );
  }

  String _monthLabel(DateTime month) {
    final m = month.month;
    const slovakMonths = <String>[
      '',
      'január',
      'február',
      'marec',
      'apríl',
      'máj',
      'jún',
      'júl',
      'august',
      'september',
      'október',
      'november',
      'december',
    ];
    final monthName = (m >= 1 && m <= 12) ? slovakMonths[m] : '';
    return '$monthName ${month.year}';
  }

  void _selectDay(DateTime day) {
    final normalized = DateTime(day.year, day.month, day.day);
    setState(() {
      _selectedDay = normalized;
      _selectedDayOverride = null;
      _isGenerating = false;
      _weatherFuture = Future.value(
        DateWeatherService.getWeatherForDate(_selectedDay),
      );
    });
  }

  Future<void> _onGeneratePressed({required bool isPremiumUser}) async {
    final user = _auth.currentUser;
    if (user == null) return;
    if (_isGenerating) return;

    if (!isPremiumUser) {
      if (_generatedOutfitsToday >= 3) {
        _showLimitBottomSheet();
        return;
      }
      setState(() {
        _generatedOutfitsToday++;
      });
    }

    setState(() {
      _isGenerating = true;
      _selectedDayOverride = null;
    });

    try {
      final weatherSnapshot = await _weatherFuture;

      final day = await _service.generateAndSaveDay(
        date: _selectedDay,
        weatherSnapshot: weatherSnapshot,
      );

      setState(() {
        _selectedDayOverride = day;
        _optimisticOutfitKeys.add(_service.dateKey(_selectedDay));
        _isGenerating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nepodarilo sa vygenerovať outfit pre tento deň. Skús to prosím znova.',
          ),
        ),
      );
    }
  }

  void _showPlanningPremiumSheet() {
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
                  'Plánovanie outfitov je Premium',
                  style: TextStyle(
                    color: Color(0xFFF1F0EC),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'S Premium si môžeš pripraviť outfity na viac dní dopredu.',
                  style: TextStyle(
                    color: Color(0xFFAAA59B),
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC8A36A),
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

  void _showLimitBottomSheet() {
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
                    color: Color(0xFFF1F0EC),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Dnes si už vytvoril 3 outfity. S Premium môžeš generovať neobmedzene a získať presnejšie odporúčania.',
                  style: TextStyle(
                    color: Color(0xFFAAA59B),
                    fontSize: 13.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC8A36A),
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

  void _changeMonth(int delta) {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + delta, 1);
    });
  }
  void _openEditOutfitSheet() {
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
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Upraviť outfit',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  _CalendarEditChoiceTile(
                    icon: Icons.swap_horiz,
                    title: 'Vymeniť kúsok',
                    subtitle: 'Vymeň jednu časť aktuálneho outfitu',
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Vymeniť kúsok napojíme v ďalšom kroku.'),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),

                  _CalendarEditChoiceTile(
                    icon: Icons.layers_outlined,
                    title: 'Pridať vrstvu',
                    subtitle: 'Pridať ďalšiu zmysluplnú vrstvu do outfitu',
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Pridať vrstvu napojíme v ďalšom kroku.'),
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
  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    const Color bgTop = Color(0xFF111111);
    const Color bgMid = Color(0xFF0C0C0D);
    const Color bgBottom = Color(0xFF080809);
    const Color accent = Color(0xFFC8A36A);
    const Color textPrimary = Color(0xFFF1F0EC);
    const Color textSecondary = Color(0xFFAAA59B);
    const Color border = Color(0x26FFFFFF);

    if (user == null) {
      return Scaffold(
        backgroundColor: bgBottom,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                'Kalendár outfitov je dostupný iba pre prihlásených používateľov.',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: textPrimary),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    final monthKeysStream = _service.watchMonthOutfitDateKeys(
      uid: user.uid,
      month: DateTime(_focusedMonth.year, _focusedMonth.month, 1),
    );
    final userDocStream =
        FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots();

    return Scaffold(
      backgroundColor: bgBottom,
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [bgTop, bgMid, bgBottom],
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
                    radius: 1.08,
                    colors: [
                      accent.withOpacity(0.22),
                      accent.withOpacity(0.10),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.28, 1.0],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.20),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: accent.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: accent.withOpacity(0.25)),
                              ),
                              child: const Icon(
                                Icons.calendar_month_outlined,
                                color: accent,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Kalendár outfitov',
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Vyber deň, pozri počasie a vygeneruj outfit.',
                                    style: TextStyle(
                                      color: textSecondary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      IconButton(
                        onPressed: () => _changeMonth(-1),
                        icon: const Icon(Icons.chevron_left),
                        color: textSecondary,
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            _monthLabel(_focusedMonth),
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _changeMonth(1),
                        icon: const Icon(Icons.chevron_right),
                        color: textSecondary,
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  const Row(
                    children: [
                      _Weekday('Po'),
                      _Weekday('Ut'),
                      _Weekday('St'),
                      _Weekday('Št'),
                      _Weekday('Pi'),
                      _Weekday('So'),
                      _Weekday('Ne'),
                    ],
                  ),
                  const SizedBox(height: 10),

                  StreamBuilder<Set<String>>(
                    stream: monthKeysStream,
                    builder: (context, snap) {
                      final keys = snap.data ?? _optimisticOutfitKeys;
                      final isLoading = snap.connectionState ==
                          ConnectionState.waiting &&
                          snap.data == null;

                      return Stack(
                        children: [
                          CalendarMonthGrid(
                            focusedMonth: _focusedMonth,
                            selectedDay: _selectedDay,
                            outfitDateKeys:
                                keys.union(_optimisticOutfitKeys),
                            onDaySelected: _selectDay,
                          ),
                          if (isLoading)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.18),
                                  ),
                                  child: const Center(
                                    child: SizedBox(
                                      width: 26,
                                      height: 26,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),

                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: userDocStream,
                    builder: (context, userSnap) {
                      final data = userSnap.data?.data();
                      final isPremiumUser = data?['isPremium'] == true ||
                          data?['subscriptionStatus'] == 'premium';
                      final today = DateTime.now();
                      final selected = DateTime(
                        _selectedDay.year,
                        _selectedDay.month,
                        _selectedDay.day,
                      );
                      final todayNormalized =
                          DateTime(today.year, today.month, today.day);
                      final dayDifference =
                          selected.difference(todayNormalized).inDays;
                      final isPlanningLocked =
                          !isPremiumUser && dayDifference > 1;

                      return FutureBuilder<DateWeatherSnapshot>(
                        future: _weatherFuture,
                        builder: (context, weatherSnap) {
                          if (weatherSnap.connectionState ==
                              ConnectionState.waiting) {
                            return _LoadingDayDetailCard();
                          }

                          final weather = weatherSnap.data ??
                              DateWeatherService.getWeatherForDate(_selectedDay);

                          final dayStream = _service.watchDayOutfit(
                            uid: user.uid,
                            date: _selectedDay,
                          );

                          return StreamBuilder<CalendarOutfitDay?>(
                            stream: dayStream,
                            builder: (context, outfitSnap) {
                              final fromStream = outfitSnap.data;
                              final effective =
                                  _selectedDayOverride ?? fromStream;
                              final isOutfitLoading =
                                  outfitSnap.connectionState ==
                                          ConnectionState.waiting &&
                                      effective == null;

                              return CalendarDayDetailCard(
                                date: _selectedDay,
                                weather: weather,
                                outfitDay: effective,
                                isOutfitLoading: isOutfitLoading,
                                isGenerating: _isGenerating,
                                isGenerationLocked: isPlanningLocked,
                                onGenerate: () => _onGeneratePressed(
                                  isPremiumUser: isPremiumUser,
                                ),
                                onUnlockPlanning: _showPlanningPremiumSheet,
                                onEditOutfit: _openEditOutfitSheet,
                              );
                            },
                          );
                        },
                      );
                    },
                  ),

                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Weekday extends StatelessWidget {
  const _Weekday(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withOpacity(0.60),
          fontWeight: FontWeight.w900,
          fontSize: 12.5,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _LoadingDayDetailCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.22),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.09)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 18, width: 220, decoration: _skBox()),
              const SizedBox(height: 14),
              Container(height: 72, width: double.infinity, decoration: _skBox()),
              const SizedBox(height: 14),
              Container(height: 18, width: 210, decoration: _skBox()),
              const SizedBox(height: 10),
              Row(
                children: const [
                  _SkeletonDayTile(),
                  _SkeletonDayTile(),
                  _SkeletonDayTile(),
                  _SkeletonDayTile(),
                ],
              ),
              const SizedBox(height: 14),
              Container(height: 48, width: double.infinity, decoration: _skBox()),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _skBox() {
    return BoxDecoration(
      color: Colors.white.withOpacity(0.05),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withOpacity(0.06)),
    );
  }
}

class _SkeletonDayTile extends StatelessWidget {
  const _SkeletonDayTile();

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 98,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
      ),
    );
  }
}
class _CalendarEditChoiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CalendarEditChoiceTile({
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
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFC8A36A).withOpacity(0.11),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: Color(0xFFC8A36A),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.68),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.white.withOpacity(0.6),
            ),
          ],
        ),
      ),
    );
  }
}
