import 'package:flutter/material.dart';

import 'home_glass_surface.dart';
import 'home_luxury_palette.dart';

class HomeAiExplanationCard extends StatefulWidget {
  const HomeAiExplanationCard({
    super.key,
    required this.body,
    this.isPlaceholder = false,
  });

  final String body;
  final bool isPlaceholder;

  /// Keeps copy readable on-screen without altering upstream strings permanently.
  static String readableExcerpt(String raw) {
    final t = raw.trim();
    if (t.length <= 260) return t;
    final cut = t.substring(0, 260);
    final dot = cut.lastIndexOf('.');
    if (dot > 100) return '${cut.substring(0, dot + 1)}…';
    return '$cut…';
  }

  @override
  State<HomeAiExplanationCard> createState() => _HomeAiExplanationCardState();
}

class _HomeAiExplanationCardState extends State<HomeAiExplanationCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  String _collapsedPreview(String text) {
    final clean = text.trim().replaceAll('\n', ' ');
    if (clean.isEmpty) return '';
    final words = clean.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '';
    final take = words.length >= 5 ? 5 : words.length;
    final teaser = words.take(take).join(' ');
    return '$teaser...';
  }

  @override
  Widget build(BuildContext context) {
    final display = HomeAiExplanationCard.readableExcerpt(widget.body);
    final collapsedPreview = _collapsedPreview(display);
    final subtitleColor = HomeLuxuryPalette.textSecondary.withOpacity(0.84);
    final bodyColor = widget.isPlaceholder
        ? HomeLuxuryPalette.textSecondary.withOpacity(0.72)
        : HomeLuxuryPalette.textSecondary.withOpacity(0.94);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(20),
        splashColor: HomeLuxuryPalette.accent.withOpacity(0.06),
        highlightColor: HomeLuxuryPalette.accent.withOpacity(0.03),
        child: HomeGlassSurface(
          borderRadius: 20,
          blurSigma: 18,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '✨',
                      style: TextStyle(
                        fontSize: 14,
                        color: HomeLuxuryPalette.accent.withOpacity(0.95),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Prečo tento outfit?',
                        style: TextStyle(
                          color: HomeLuxuryPalette.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.25,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: HomeLuxuryPalette.textSecondary.withOpacity(0.86),
                        size: 20,
                      ),
                    ),
                  ],
                ),
                if (!_expanded) ...[
                  const SizedBox(height: 5),
                  Text(
                    collapsedPreview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: subtitleColor,
                      fontSize: 12.4,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.02,
                    ),
                  ),
                ],
                if (_expanded) ...[
                  const SizedBox(height: 10),
                  Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          HomeLuxuryPalette.accent.withOpacity(0.0),
                          HomeLuxuryPalette.accent.withOpacity(0.28),
                          HomeLuxuryPalette.accent.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    display,
                    style: TextStyle(
                      color: bodyColor,
                      fontSize: 13.4,
                      height: 1.46,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
