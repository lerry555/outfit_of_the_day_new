import 'package:flutter/material.dart';

import 'home_glass_surface.dart';
import 'home_luxury_palette.dart';

class HomeOutfitExplanationSheet extends StatelessWidget {
  const HomeOutfitExplanationSheet({
    super.key,
    required this.narrative,
    this.supplementalBody,
  });

  final String narrative;
  final String? supplementalBody;

  static Future<void> show(
    BuildContext context, {
    required String narrative,
    String? supplementalBody,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (context) {
        return SafeArea(
          top: false,
          child: HomeOutfitExplanationSheet(
            narrative: narrative,
            supplementalBody: supplementalBody,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.82;
    final primary =
        (supplementalBody?.trim().isNotEmpty == true
                ? supplementalBody!.trim()
                : narrative.trim())
            .trim();

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, 14 + bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: HomeGlassSurface(
          borderRadius: 24,
          blurSigma: 20,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: HomeLuxuryPalette.textSecondary.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Row(
                children: [
                  Text(
                    '💡',
                    style: TextStyle(
                      fontSize: 18,
                      color: HomeLuxuryPalette.accent.withOpacity(0.95),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Prečo tento outfit?',
                      style: TextStyle(
                        color: HomeLuxuryPalette.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close_rounded,
                      color: HomeLuxuryPalette.textSecondary.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (primary.isNotEmpty)
                        ...primary.split('\n\n').map((paragraph) {
                          final text = paragraph.trim();
                          if (text.isEmpty) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Text(
                              text,
                              style: TextStyle(
                                color: HomeLuxuryPalette.textPrimary
                                    .withOpacity(0.94),
                                fontSize: 15,
                                height: 1.55,
                                fontWeight: FontWeight.w500,
                                letterSpacing: -0.1,
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
