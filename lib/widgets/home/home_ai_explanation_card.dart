import 'package:flutter/material.dart';

import '../../utils/outfit_explanation.dart';
import 'home_glass_surface.dart';
import 'home_luxury_palette.dart';
import 'home_outfit_explanation_sheet.dart';

class HomeAiExplanationCard extends StatelessWidget {
  const HomeAiExplanationCard({
    super.key,
    required this.explanations,
    this.supplementalBody,
    this.isPlaceholder = false,
    this.isLoadingReason = false,
  });

  final OutfitExplanationResult explanations;
  final String? supplementalBody;
  final bool isPlaceholder;
  final bool isLoadingReason;

  String get _teaser {
    if (isPlaceholder) {
      return 'Po vygenerovaní outfitu uvidíte prehľad rozhodnutí...';
    }
    if (isLoadingReason) {
      final body = supplementalBody?.trim() ?? '';
      return body.isNotEmpty
          ? body
          : 'Pripravujem stylistické vysvetlenie k tomuto outfitu.';
    }
    final body = supplementalBody?.trim() ?? '';
    if (body.isNotEmpty) return HomeAiExplanationCard.readableExcerpt(body);
    final fromItems = explanations.teaser;
    if (fromItems.isNotEmpty) return fromItems;
    if (body.isEmpty) return 'Klepnutím zobrazíte detail rozhodnutí stylistu.';
    return HomeAiExplanationCard.readableExcerpt(body);
  }

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
  Widget build(BuildContext context) {
    final subtitleColor = HomeLuxuryPalette.textSecondary.withOpacity(0.84);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isPlaceholder || isLoadingReason
            ? null
            : () => HomeOutfitExplanationSheet.show(
                context,
                narrative: explanations.narrative,
                supplementalBody: supplementalBody,
              ),
        borderRadius: BorderRadius.circular(20),
        splashColor: HomeLuxuryPalette.accent.withOpacity(0.06),
        highlightColor: HomeLuxuryPalette.accent.withOpacity(0.03),
        child: HomeGlassSurface(
          borderRadius: 20,
          blurSigma: 18,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              Text(
                '💡',
                style: TextStyle(
                  fontSize: 16,
                  color: HomeLuxuryPalette.accent.withOpacity(0.95),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Prečo tento outfit?',
                      style: TextStyle(
                        color: HomeLuxuryPalette.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.25,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _teaser,
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
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: HomeLuxuryPalette.textSecondary.withOpacity(0.86),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
