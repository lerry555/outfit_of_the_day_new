part of 'home_screen.dart';

/// Glass segmented controls — replaces stacked gold CTAs.
class _HeroOutfitActionBar extends StatelessWidget {
  const _HeroOutfitActionBar({
    required this.onNewOutfit,
    required this.onSwapPiece,
    required this.onLike,
    this.likeActive = false,
    this.likePulseTick = 0,
    this.newOutfitLoading = false,
  });

  final VoidCallback onNewOutfit;
  final VoidCallback onSwapPiece;
  final VoidCallback onLike;
  final bool likeActive;
  final int likePulseTick;
  final bool newOutfitLoading;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
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
                  label: newOutfitLoading ? 'Generujem…' : 'Nový outfit',
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
                child: TweenAnimationBuilder<double>(
                  key: ValueKey('likePulse_$likePulseTick'),
                  tween: Tween<double>(begin: 1.06, end: 1.0),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  builder: (context, scale, child) {
                    return Transform.scale(scale: scale, child: child);
                  },
                  child: _BarHit(
                    emoji: '✅',
                    label: 'Páči sa mi',
                    onTap: onLike,
                    active: likeActive,
                  ),
                ),
              ),
            ],
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
    this.active = false,
  });

  final String emoji;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: HomeLuxuryPalette.accent.withOpacity(active ? 0.10 : 0.06),
        highlightColor:
            HomeLuxuryPalette.accent.withOpacity(active ? 0.06 : 0.04),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: active
                ? Border.all(
                    color: HomeLuxuryPalette.accent.withOpacity(0.34),
                    width: 0.8,
                  )
                : null,
            gradient: active
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      HomeLuxuryPalette.accent.withOpacity(0.14),
                      HomeLuxuryPalette.accent.withOpacity(0.05),
                    ],
                  )
                : null,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: HomeLuxuryPalette.accent.withOpacity(0.20),
                      blurRadius: 14,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  emoji,
                  style: TextStyle(
                    fontSize: 13,
                    color: active ? HomeLuxuryPalette.accent : null,
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active
                          ? HomeLuxuryPalette.textPrimary.withOpacity(0.96)
                          : HomeLuxuryPalette.textPrimary.withOpacity(0.88),
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
