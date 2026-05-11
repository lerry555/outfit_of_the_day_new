import 'package:flutter/material.dart';

/// Shared luxury dark tokens for Home and related surfaces.
abstract final class HomeLuxuryPalette {
  static const double horizontalPadding = 22;

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

  /// Primary home greeting — large, editorial.
  static const TextStyle homeGreeting = TextStyle(
    color: textPrimary,
    fontSize: 36,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.0,
    height: 1.06,
  );

  /// Small gold masthead above greeting.
  static const TextStyle homeGoldLabel = TextStyle(
    color: accent,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.4,
    height: 1.2,
  );

  static TextStyle titleLarge = const TextStyle(
    color: textPrimary,
    fontSize: 26,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    height: 1.15,
  );

  static TextStyle titleMedium = const TextStyle(
    color: textPrimary,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  static TextStyle labelMuted = TextStyle(
    color: textSecondary.withOpacity(0.78),
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.1,
  );

  /// Personal subtitle under greeting.
  static TextStyle homeTagline = TextStyle(
    color: textSecondary.withOpacity(0.9),
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.15,
  );
}
