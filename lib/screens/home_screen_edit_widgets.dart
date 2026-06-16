part of 'home_screen.dart';

/// =======================
/// Ostatné widgety (nezmenené)
/// =======================
class _HeroEditActionSheet extends StatelessWidget {
  const _HeroEditActionSheet({
    required this.onAiSuggest,
    required this.onManualPick,
    required this.onFeedback,
  });

  final VoidCallback onAiSuggest;
  final VoidCallback onManualPick;
  final VoidCallback onFeedback;

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, 14 + safeBottom),
      child: HomeGlassSurface(
        borderRadius: 20,
        blurSigma: 18,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HeroEditSheetAction(
              emoji: '✨',
              title: 'AI navrhne inú',
              onTap: onAiSuggest,
            ),
            const SizedBox(height: 8),
            _HeroEditSheetAction(
              emoji: '👕',
              title: 'Vyberiem si sám',
              onTap: onManualPick,
            ),
            const SizedBox(height: 8),
            _HeroEditSheetAction(
              emoji: '💬',
              title: 'Napíš čo ti vadí',
              onTap: onFeedback,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroEditSheetAction extends StatelessWidget {
  const _HeroEditSheetAction({
    required this.emoji,
    required this.title,
    required this.onTap,
  });
  final String emoji;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: HomeLuxuryPalette.surface.withOpacity(0.5),
            border: Border.all(color: HomeLuxuryPalette.border),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  color: HomeLuxuryPalette.textPrimary.withOpacity(0.95),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualCategoryOption {
  const _ManualCategoryOption({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

class _EditHelperPanel extends StatelessWidget {
  const _EditHelperPanel({
    this.withGlassBackground = false,
  });

  final bool withGlassBackground;

  @override
  Widget build(BuildContext context) {
    final helperContent = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vyber kúsok na úpravu',
            style: TextStyle(
              color: HomeLuxuryPalette.textPrimary.withOpacity(0.96),
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.08,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Môžeš ho zmeniť alebo odstrániť z outfitu.',
            style: TextStyle(
              color: HomeLuxuryPalette.textSecondary.withOpacity(0.92),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 10, right: 6),
        child: withGlassBackground
            ? Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: HomeLuxuryPalette.surfaceSoft.withOpacity(0.26),
                  border: Border.all(
                    color: HomeLuxuryPalette.accent.withOpacity(0.12),
                  ),
                ),
                child: HomeGlassSurface(
                  borderRadius: 16,
                  blurSigma: 10,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: helperContent,
                ),
              )
            : helperContent,
      ),
    );
  }
}
