import 'package:flutter/material.dart';

import 'home/home_luxury_palette.dart';

/// Dark luxury backdrop with top-center gold glow — matches Home screen.
class OotdLuxuryBackground extends StatelessWidget {
  const OotdLuxuryBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  /// Background layers only (for custom [Stack] layouts).
  static List<Widget> layers() {
    return [
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
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0B0B0D).withOpacity(0.32),
                  Colors.transparent,
                  Color(0xFF09090A).withOpacity(0.24),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ...layers(),
        child,
      ],
    );
  }
}
