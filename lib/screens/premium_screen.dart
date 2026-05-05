import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  static const Color _bgTop = Color(0xFF111111);
  static const Color _bgMid = Color(0xFF0C0C0D);
  static const Color _bgBottom = Color(0xFF080809);
  static const Color _accent = Color(0xFFC8A36A);
  static const Color _textPrimary = Color(0xFFF1F0EC);
  static const Color _textSecondary = Color(0xFFAAA59B);
  static const Color _border = Color(0x26FFFFFF);

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  bool _isSaving = false;
  String _currentModeLabel = 'Free';
  bool get _isPremiumMode => _currentModeLabel == 'Premium';

  @override
  void initState() {
    super.initState();
    _loadCurrentMode();
  }

  Future<void> _loadCurrentMode() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final snap = await _firestore.collection('users').doc(user.uid).get();
      final data = snap.data();

      final status = (data?['subscriptionStatus'] ?? '').toString().toLowerCase();
      final isPremium = data?['isPremium'] == true;
      final isPremiumMode = status == 'premium' || isPremium;

      if (!mounted) return;
      setState(() {
        _currentModeLabel = isPremiumMode ? 'Premium' : 'Free';
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _currentModeLabel = 'Free';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveMode({
    required String subscriptionStatus,
    required bool isPremium,
  }) async {
    final user = _auth.currentUser;
    if (user == null || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      await _firestore.collection('users').doc(user.uid).set({
        'subscriptionStatus': subscriptionStatus,
        'isPremium': isPremium,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _currentModeLabel = isPremium ? 'Premium' : 'Free';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Režim uložený')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nepodarilo sa uložiť režim')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _isSaving = false);
    }
  }

  Future<void> _resetDailyLimit() async {
    final user = _auth.currentUser;
    if (user == null || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      await _firestore.collection('users').doc(user.uid).set({
        'dailyOutfitCount': 0,
        'lastGeneratedDate': '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Limit resetovaný')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nepodarilo sa resetovať limit')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgMid, _bgBottom],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(_accent),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: _textPrimary,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Premium (Developer)',
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Aktuálny režim',
                            style: TextStyle(
                              color: _accent,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Aktuálny režim: $_currentModeLabel',
                            style: const TextStyle(
                              color: _textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Toto je dočasný vývojový prepínač. Neskôr ho nahradí reálne predplatné.',
                            style: TextStyle(
                              color: _textSecondary,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _GlassCard(
                      child: Column(
                        children: [
                          _ActionButton(
                            label: 'Testovať ako Free',
                            icon: Icons.lock_open_rounded,
                            isPrimary: !_isPremiumMode,
                            onPressed: _isSaving
                                ? null
                                : () => _saveMode(
                                      subscriptionStatus: 'free',
                                      isPremium: false,
                                    ),
                          ),
                          const SizedBox(height: 10),
                          _ActionButton(
                            label: 'Testovať ako Premium',
                            icon: Icons.workspace_premium_rounded,
                            isPrimary: _isPremiumMode,
                            onPressed: _isSaving
                                ? null
                                : () => _saveMode(
                                      subscriptionStatus: 'premium',
                                      isPremium: true,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _GlassCard(
                      child: _ActionButton(
                        label: 'Resetovať dnešný limit outfitov',
                        icon: Icons.refresh_rounded,
                        onPressed: _isSaving ? null : _resetDailyLimit,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _PremiumScreenState._border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22C8A36A),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isPrimary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          backgroundColor:
              isPrimary ? _PremiumScreenState._accent : const Color(0xFF222227),
          foregroundColor:
              isPrimary ? const Color(0xFF191512) : _PremiumScreenState._textPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isPrimary
                  ? _PremiumScreenState._accent
                  : const Color(0x44C8A36A),
            ),
          ),
        ),
      ),
    );
  }
}
