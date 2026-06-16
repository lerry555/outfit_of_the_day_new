import 'package:flutter/material.dart';

import 'home_glass_surface.dart';
import 'home_luxury_palette.dart';

class HomeOutfitItemInfoSheet extends StatelessWidget {
  const HomeOutfitItemInfoSheet({
    super.key,
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String body,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (context) {
        return SafeArea(
          top: false,
          child: HomeOutfitItemInfoSheet(title: title, body: body),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, 14 + bottomInset),
      child: HomeGlassSurface(
        borderRadius: 20,
        blurSigma: 18,
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              alignment: Alignment.center,
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: HomeLuxuryPalette.textSecondary.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: HomeLuxuryPalette.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
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
            const SizedBox(height: 6),
            Text(
              body,
              style: TextStyle(
                color: HomeLuxuryPalette.textSecondary.withOpacity(0.96),
                fontSize: 14,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
