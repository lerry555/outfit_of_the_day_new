import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class WardrobeAnalysisScreen extends StatefulWidget {
  const WardrobeAnalysisScreen({Key? key}) : super(key: key);

  @override
  State<WardrobeAnalysisScreen> createState() => _WardrobeAnalysisScreenState();
}

class _WardrobeAnalysisScreenState extends State<WardrobeAnalysisScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  bool _loading = true;
  String? _error;
  _AiWardrobeAnalysis? _analysis;

  @override
  void initState() {
    super.initState();
    _runAnalysis();
  }

  Future<void> _runAnalysis() async {
    setState(() {
      _loading = true;
      _error = null;
      _analysis = null;
    });

    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('Musíš byť prihlásený.');
      }

      final snap = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('wardrobe')
          .limit(250)
          .get();

      final items = snap.docs.map((d) {
        final data = (d.data());
        return _compactWardrobeItem(data);
      }).where((m) => m.isNotEmpty).toList();

      final functions = FirebaseFunctions.instanceFor(region: 'us-east1');
      final callable = functions.httpsCallable('analyzeWardrobeSmart');

      final res = await callable.call();

      final parsed = _AiWardrobeAnalysis.fromCallableResult(res.data);
      if (!mounted) return;
      setState(() {
        _analysis = parsed;
        _loading = false;
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message ?? 'Nepodarilo sa spustiť AI analýzu.';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Nepodarilo sa spustiť AI analýzu: $e';
        _loading = false;
      });
    }
  }

  Map<String, dynamic> _compactWardrobeItem(Map<String, dynamic> d) {
    List<String> _list(dynamic v) {
      if (v == null) return [];
      if (v is List) return v.map((e) => e.toString().trim()).where((x) => x.isNotEmpty).toList();
      final s = v.toString().trim();
      return s.isEmpty ? [] : [s];
    }

    final mainGroup = (d['mainGroupLabel'] ?? d['mainGroup'])?.toString().trim();
    final category = (d['categoryLabel'] ?? d['categoryKey'] ?? d['category'])?.toString().trim();
    final sub = (d['subCategoryLabel'] ?? d['subCategoryKey'])?.toString().trim();
    final brand = (d['brand'])?.toString().trim();
    final name = (d['name'])?.toString().trim();

    final colors = _list(d['color']);
    final styles = _list(d['style']);
    final patterns = _list(d['pattern']);
    final seasons = _list(d['season']);

    final out = <String, dynamic>{};
    if (mainGroup != null && mainGroup.isNotEmpty) out['g'] = mainGroup;
    if (category != null && category.isNotEmpty) out['c'] = category;
    if (sub != null && sub.isNotEmpty) out['s'] = sub;
    if (brand != null && brand.isNotEmpty) out['b'] = brand;
    if (name != null && name.isNotEmpty) out['n'] = name;
    if (colors.isNotEmpty) out['col'] = colors.take(3).toList();
    if (styles.isNotEmpty) out['sty'] = styles.take(3).toList();
    if (patterns.isNotEmpty) out['pat'] = patterns.take(1).toList();
    if (seasons.isNotEmpty) out['sea'] = seasons.take(3).toList();

    final wearCount = d['wearCount'];
    if (wearCount is int && wearCount > 0) out['w'] = wearCount;

    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'AI analýza šatníka',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF07070A),
                    Color(0xFF111116),
                    Color(0xFF050507),
                  ],
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
                    Colors.black.withOpacity(0.62),
                    Colors.black.withOpacity(0.18),
                    Colors.black.withOpacity(0.72),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              child: _loading
                  ? const _LoadingState()
                  : (_error != null)
                      ? _ErrorState(
                          message: _error!,
                          onRetry: _runAnalysis,
                        )
                      : _ResultView(analysis: _analysis),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiWardrobeAnalysis {
  final List<String> strengths;
  final List<String> missing;
  final List<String> buyFirst;
  final List<String> moreOutfits;

  const _AiWardrobeAnalysis({
    required this.strengths,
    required this.missing,
    required this.buyFirst,
    required this.moreOutfits,
  });

  static _AiWardrobeAnalysis fromCallableResult(dynamic data) {
    List<String> _asList(dynamic v) {
      if (v == null) return [];
      if (v is List) return v.map((e) => e.toString().trim()).where((x) => x.isNotEmpty).toList();
      return [v.toString().trim()].where((x) => x.isNotEmpty).toList();
    }

    if (data is Map) {
      final m = data.cast<String, dynamic>();
      return _AiWardrobeAnalysis(
        strengths: _asList(m['strengths']),
        missing: _asList(m['missing']),
        buyFirst: _asList(m['buyFirst']),
        moreOutfits: _asList(m['moreOutfits']),
      );
    }

    return const _AiWardrobeAnalysis(
      strengths: ['Nepodarilo sa načítať výsledok analýzy. Skús to prosím znova.'],
      missing: [],
      buyFirst: [],
      moreOutfits: [],
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white10),
            color: Colors.white.withOpacity(0.06),
          ),
          child: Row(
            children: const [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Analyzujem tvoj šatník…',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white10),
            color: Colors.white.withOpacity(0.06),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nepodarilo sa načítať analýzu',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(color: Colors.white70, height: 1.35),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onRetry,
                  child: const Text('Skúsiť znova', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  final _AiWardrobeAnalysis? analysis;
  const _ResultView({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final a = analysis ??
        const _AiWardrobeAnalysis(
          strengths: ['Nepodarilo sa načítať výsledok analýzy.'],
          missing: [],
          buyFirst: [],
          moreOutfits: [],
        );

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _SectionCard(
          title: 'Silné stránky tvojho šatníka',
          items: a.strengths,
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Čo ti chýba',
          items: a.missing,
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Čo dokúpiť ako prvé',
          items: a.buyFirst,
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Ako získať viac outfitov',
          items: a.moreOutfits,
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<String> items;

  const _SectionCard({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    final safeItems = items.where((x) => x.trim().isNotEmpty).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white10),
            color: Colors.white.withOpacity(0.06),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15.5,
                ),
              ),
              const SizedBox(height: 10),
              if (safeItems.isEmpty)
                const Text(
                  'Zatiaľ nič konkrétne.',
                  style: TextStyle(color: Colors.white70, height: 1.35),
                )
              else
                ...safeItems.map((t) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 3),
                          child: Icon(Icons.check_circle_outline, size: 16, color: Colors.white70),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            t,
                            style: const TextStyle(color: Colors.white70, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}

