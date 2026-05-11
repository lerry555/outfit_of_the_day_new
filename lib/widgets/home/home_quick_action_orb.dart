import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'home_luxury_palette.dart';

const double _kSatelliteSize = 48;
const double _kLabelMaxWidth = 132;

typedef HomeQuickActionEntry = ({
  String emoji,
  String label,
  VoidCallback onTap,
});

/// Gold orb — actions fan **left** from the orb (luxury speed-dial), with floating label pills.
class HomeQuickActionOrb extends StatefulWidget {
  const HomeQuickActionOrb({
    super.key,
    required this.actions,
    this.bottomOffset = 92,
    this.rightOffset = 20,
  });

  final List<HomeQuickActionEntry> actions;
  final double bottomOffset;
  final double rightOffset;

  @override
  State<HomeQuickActionOrb> createState() => _HomeQuickActionOrbState();
}

class _HomeQuickActionOrbState extends State<HomeQuickActionOrb>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _radial;
  OverlayEntry? _menuOverlay;

  static const double _orbSize = 58;

  /// Fan angles (radians) opening **left** from the orb — wide arc so labels/icons do not overlap.
  static const double _fanStart = math.pi - 0.78;
  static const double _fanEnd = math.pi + 0.78;

  static const double _orbitRadius = 84;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);

    _radial = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  @override
  void dispose() {
    _closeMenu(immediate: true);
    _pulse.dispose();
    _radial.dispose();
    super.dispose();
  }

  void _closeMenu({bool immediate = false}) {
    if (_menuOverlay == null) return;

    if (immediate) {
      _menuOverlay?.remove();
      _menuOverlay = null;
      if (mounted) _radial.reset();
      return;
    }

    _radial.reverse().then((_) {
      if (!mounted) return;
      _menuOverlay?.remove();
      _menuOverlay = null;
      _radial.reset();
    });
  }

  void _openMenu() {
    if (_menuOverlay != null) return;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final orbTopLeft = box.localToGlobal(Offset.zero);
    final orbCenter = orbTopLeft +
        Offset(box.size.width / 2, box.size.height / 2);

    final overlayState = Overlay.of(context);

    _menuOverlay = OverlayEntry(
      builder: (overlayContext) {
        final media = MediaQuery.of(overlayContext);
        final sw = media.size.width;
        final sh = media.size.height;
        final pad = media.padding;

        return AnimatedBuilder(
          animation: _radial,
          builder: (context, _) {
            final tRaw = CurvedAnimation(
              parent: _radial,
              curve: Curves.easeOutCubic,
            ).value;
            final tMove = tRaw.clamp(0.0, 1.0).toDouble();

            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _closeMenu(),
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: 10 * tMove,
                          sigmaY: 10 * tMove,
                        ),
                        child: Container(
                          color: Color.lerp(
                            Colors.transparent,
                            const Color(0x99000000),
                            tMove,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                ...List<Widget>.generate(widget.actions.length, (i) {
                  final n = widget.actions.length;
                  final span = _fanEnd - _fanStart;
                  final angle = n <= 1
                      ? math.pi
                      : _fanStart + span * (i / (n - 1));

                  final orbit = _orbitRadius * tMove;
                  final raw = Offset.fromDirection(angle, orbit);

                  final staggerStart = (i * 0.11).clamp(0.0, 0.5);
                  // easeOutBack overshoots past 1.0 — invalid for Opacity.
                  final staggerRaw = Interval(
                    staggerStart,
                    1.0,
                    curve: Curves.easeOutBack,
                  ).transform(tMove.clamp(0.0, 1.0));
                  final stagger = staggerRaw.clamp(0.0, 1.0).toDouble();
                  final scaleRaw = 0.38 + 0.62 * stagger;
                  final scale = scaleRaw.clamp(0.0, 1.0).toDouble();

                  /// Emoji circle center (fan expands **left** from orb).
                  final emojiCx = orbCenter.dx + raw.dx;
                  final emojiCy = orbCenter.dy + raw.dy;

                  final rowHeight = _kSatelliteSize + 18;
                  final emojiRightEdge = emojiCx + _kSatelliteSize / 2;

                  var rowTop = emojiCy - rowHeight / 2;
                  rowTop = rowTop.clamp(
                    pad.top + 6,
                    sh - pad.bottom - rowHeight - 6,
                  );

                  /// Row = [pill][gap][emoji]; anchor **trailing** edge to emoji so alignment stays crisp.
                  var fromRight = sw - emojiRightEdge;
                  fromRight = fromRight.clamp(
                    pad.right + 6,
                    sw - pad.left - 48,
                  );

                  final entry = widget.actions[i];

                  return Positioned(
                    right: fromRight,
                    top: rowTop,
                    child: Opacity(
                      opacity: stagger,
                      child: Transform.scale(
                        scale: scale,
                        alignment: Alignment.centerRight,
                        child: _RadialActionRow(
                          emoji: entry.emoji,
                          label: entry.label,
                          onTap: () {
                            _closeMenu();
                            entry.onTap();
                          },
                        ),
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        );
      },
    );

    overlayState.insert(_menuOverlay!);
    _radial.forward(from: 0);
  }

  void _toggleMenu() {
    if (_menuOverlay != null) {
      _closeMenu();
      return;
    }
    _openMenu();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Positioned(
      right: widget.rightOffset,
      bottom: widget.bottomOffset + bottomInset,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final curved = CurvedAnimation(parent: _pulse, curve: Curves.easeInOut);
          final glow =
              (0.22 + 0.14 * curved.value).clamp(0.0, 1.0).toDouble();
          return DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: HomeLuxuryPalette.accent.withOpacity(glow),
                  blurRadius: 28 + 12 * curved.value,
                  spreadRadius: 0,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: child,
          );
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _toggleMenu,
            child: Ink(
              width: _orbSize,
              height: _orbSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    HomeLuxuryPalette.accent,
                    HomeLuxuryPalette.accentSoft,
                  ],
                ),
                border: Border.all(
                  color: HomeLuxuryPalette.accent.withOpacity(0.55),
                  width: 1.15,
                ),
              ),
              child: const Icon(
                Icons.bolt_rounded,
                color: Color(0xFF191512),
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadialActionRow extends StatelessWidget {
  const _RadialActionRow({
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        splashColor: Colors.white.withOpacity(0.05),
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _OrbActionCaption(text: label),
              const SizedBox(width: 14),
              _OrbEmojiCircle(emoji: emoji),
            ],
          ),
        ),
      ),
    );
  }
}

/// Informational caption — not a button chip (no stroke / heavy glass).
class _OrbActionCaption extends StatelessWidget {
  const _OrbActionCaption({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: _kLabelMaxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.black.withOpacity(0.16),
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: HomeLuxuryPalette.textSecondary.withOpacity(0.94),
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.02,
          height: 1.2,
        ),
      ),
    );
  }
}

class _OrbEmojiCircle extends StatelessWidget {
  const _OrbEmojiCircle({required this.emoji});

  final String emoji;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kSatelliteSize,
      height: _kSatelliteSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: HomeLuxuryPalette.accent.withOpacity(0.22),
              blurRadius: 14,
              spreadRadius: -2,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.42),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.14),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    HomeLuxuryPalette.surfaceSoft.withOpacity(0.88),
                    HomeLuxuryPalette.bgMid.withOpacity(0.78),
                  ],
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                emoji,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, height: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
