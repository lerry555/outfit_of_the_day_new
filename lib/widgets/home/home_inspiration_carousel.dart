import 'package:flutter/material.dart';

import 'home_luxury_palette.dart';

/// Magazine-style “Inspirations for you” row — visual only.
class HomeInspirationCarousel extends StatelessWidget {
  const HomeInspirationCarousel({
    super.key,
    this.onOpenInspiration,
  });

  final VoidCallback? onOpenInspiration;

  static const _slides = <_MagSlide>[
    _MagSlide(
      title: 'Dinner vibe',
      gradient: [Color(0xFF2A1F18), Color(0xFF15100C), Color(0xFF0A0806)],
    ),
    _MagSlide(
      title: 'Airport fit',
      gradient: [Color(0xFF1C2430), Color(0xFF12161C), Color(0xFF080A0D)],
    ),
    _MagSlide(
      title: 'Clean luxury',
      gradient: [Color(0xFF232320), Color(0xFF141412), Color(0xFF090908)],
    ),
    _MagSlide(
      title: 'Couple outfit',
      gradient: [Color(0xFF2B1820), Color(0xFF160C10), Color(0xFF0B0608)],
    ),
    _MagSlide(
      title: 'Weekend city look',
      gradient: [Color(0xFF1E2528), Color(0xFF121618), Color(0xFF080A0B)],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final cardTap = onOpenInspiration;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Inšpirácie pre teba',
          style: TextStyle(
            color: HomeLuxuryPalette.textPrimary,
            fontSize: 19,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.25,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Outfity od tvorcov, ktoré by sa ti mohli páčiť.',
          style: TextStyle(
            color: HomeLuxuryPalette.textSecondary.withOpacity(0.88),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 212,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(right: 4),
            itemCount: _slides.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final s = _slides[index];
              return _MagazineCard(
                slide: s,
                onTap: cardTap,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MagSlide {
  const _MagSlide({
    required this.title,
    required this.gradient,
  });

  final String title;
  final List<Color> gradient;
}

class _MagazineCard extends StatelessWidget {
  const _MagazineCard({
    required this.slide,
    this.onTap,
  });

  final _MagSlide slide;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: 168,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: slide.gradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
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
                          Colors.black.withOpacity(0.05),
                          Colors.black.withOpacity(0.55),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      slide.title,
                      style: const TextStyle(
                        color: HomeLuxuryPalette.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
