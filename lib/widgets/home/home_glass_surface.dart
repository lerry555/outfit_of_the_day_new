import 'dart:ui';

import 'package:flutter/material.dart';

import 'home_luxury_palette.dart';

/// Frosted glass panel with gold hairline border.
class HomeGlassSurface extends StatelessWidget {
  const HomeGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.padding,
    this.blurSigma = 14,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(borderRadius);
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: r,
            border: Border.all(color: HomeLuxuryPalette.border),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                HomeLuxuryPalette.surfaceSoft.withOpacity(0.52),
                HomeLuxuryPalette.surface.withOpacity(0.38),
                HomeLuxuryPalette.bgMid.withOpacity(0.42),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: HomeLuxuryPalette.accent.withOpacity(0.06),
                blurRadius: 28,
                spreadRadius: -4,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
