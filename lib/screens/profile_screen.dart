import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'premium_screen.dart';
import 'style_preferences_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color _bgTop = Color(0xFF111111);
  static const Color _bgMid = Color(0xFF0C0C0D);
  static const Color _bgBottom = Color(0xFF080809);
  static const Color _accent = Color(0xFFC8A36A);
  static const Color _textPrimary = Color(0xFFF1F0EC);
  static const Color _textSecondary = Color(0xFFAAA59B);
  static const Color _border = Color(0x26FFFFFF);

  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isSigningOut = false;

  Future<void> _onSignOut() async {
    if (_isSigningOut) return;

    setState(() {
      _isSigningOut = true;
    });

    try {
      await _auth.signOut();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Odhlásenie sa nepodarilo. Skús to prosím znova.'),
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isSigningOut = false;
      });
    }
  }

  Future<void> _confirmSignOut() async {
    if (_isSigningOut) return;

    final shouldSignOut = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF171719),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _border),
          ),
          title: const Text(
            'Odhlásiť sa?',
            style: TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: const Text(
            'Naozaj sa chceš odhlásiť z tohto účtu?',
            style: TextStyle(color: _textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Zrušiť',
                style: TextStyle(color: _textSecondary),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: const Color(0xFF191512),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Odhlásiť sa'),
            ),
          ],
        );
      },
    );

    if (shouldSignOut == true) {
      await _onSignOut();
    }
  }

  void _openSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            decoration: const BoxDecoration(
              color: Color(0xFF111113),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              border: Border(
                top: BorderSide(color: _border),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                _SettingsSheetHandle(),
                SizedBox(height: 12),
                _SettingsItem(
                  icon: Icons.notifications_none,
                  label: 'Notifikácie',
                ),
                SizedBox(height: 8),
                _SettingsItem(
                  icon: Icons.lock_outline,
                  label: 'Súkromie a dáta',
                ),
                SizedBox(height: 8),
                _SettingsItem(
                  icon: Icons.language,
                  label: 'Jazyk aplikácie',
                ),
                SizedBox(height: 8),
                _SettingsItem(
                  icon: Icons.palette_outlined,
                  label: 'Vzhľad aplikácie',
                ),
                SizedBox(height: 8),
                _SettingsItem(
                  icon: Icons.person_outline,
                  label: 'Účet',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final displayName = (user?.displayName?.trim().isNotEmpty ?? false)
        ? user!.displayName!.trim()
        : 'Používateľ';
    final email = (user?.email?.trim().isNotEmpty ?? false) ? user!.email! : null;

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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _ProfileHeader(
                displayName: displayName,
                email: email,
              ),
              const SizedBox(height: 18),
              _SectionCard(
                icon: Icons.style_outlined,
                title: 'Štýlové preferencie',
                subtitle: 'Farby, obľúbené kúsky a celkový štýl.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const StylePreferencesScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _SectionCard(
                icon: Icons.workspace_premium_outlined,
                title: 'Premium',
                subtitle: 'Správa predplatného a výhody členstva.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PremiumScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _SectionCard(
                icon: Icons.settings_outlined,
                title: 'Nastavenia',
                subtitle: 'Jazyk, vzhľad aplikácie a preferencie.',
                onTap: _openSettingsSheet,
              ),
              const SizedBox(height: 12),
              _SectionCard(
                icon: Icons.logout_rounded,
                title: 'Odhlásiť sa',
                subtitle: _isSigningOut
                    ? 'Prebieha odhlasovanie...'
                    : 'Bezpečne odhlásiť aktuálny účet.',
                trailing: _isSigningOut
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(_accent),
                        ),
                      )
                    : const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: _textSecondary,
                      ),
                onTap: _confirmSignOut,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.displayName,
    required this.email,
  });

  final String displayName;
  final String? email;

  @override
  Widget build(BuildContext context) {
    final initials = displayName.isNotEmpty
        ? displayName.trim().substring(0, 1).toUpperCase()
        : 'P';

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _ProfileScreenState._border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33C8A36A),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFC8A36A), Color(0xFF9D7C4C)],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Color(0xFF191512),
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Profil',
                      style: TextStyle(
                        color: _ProfileScreenState._accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: _ProfileScreenState._textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (email != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        email!,
                        style: const TextStyle(
                          color: _ProfileScreenState._textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _ProfileScreenState._border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: const Color(0x26C8A36A),
                      border: Border.all(
                        color: const Color(0x44C8A36A),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      icon,
                      color: _ProfileScreenState._accent,
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
                            color: _ProfileScreenState._textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: _ProfileScreenState._textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  trailing ??
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: _ProfileScreenState._textSecondary,
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSheetHandle extends StatelessWidget {
  const _SettingsSheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  const _SettingsItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: _ProfileScreenState._border),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: _ProfileScreenState._accent,
        ),
        title: Text(
          label,
          style: const TextStyle(
            color: _ProfileScreenState._textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: _ProfileScreenState._textSecondary,
        ),
        onTap: () {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$label pripravujeme.')),
          );
        },
      ),
    );
  }
}
