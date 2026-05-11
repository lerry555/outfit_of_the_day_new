import 'package:flutter/material.dart';

import 'home_glass_surface.dart';
import 'home_luxury_palette.dart';

class HomeRecommendedSection extends StatelessWidget {
  const HomeRecommendedSection({
    super.key,
    required this.onOpenRecommended,
  });

  final VoidCallback onOpenRecommended;

  static const _items = <_RecItem>[
    _RecItem(
      brand: 'ZARA',
      name: 'Oversize hoodie',
      price: '34,99 €',
      matchLabel: 'Hodí sa k tvojim rifliam',
      icon: Icons.checkroom,
    ),
    _RecItem(
      brand: 'Nike',
      name: 'Air sneakers',
      price: '129,00 €',
      matchLabel: 'Ležérny mestský tón',
      icon: Icons.directions_run,
    ),
    _RecItem(
      brand: 'H&M',
      name: 'Basic tričko',
      price: '9,99 €',
      matchLabel: 'Čistý základ šatníka',
      icon: Icons.heat_pump,
    ),
    _RecItem(
      brand: 'Levi’s',
      name: 'Slim rifle',
      price: '89,90 €',
      matchLabel: 'Na každodenné outfity',
      icon: Icons.local_mall_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Odporúčané pre teba',
                    style: TextStyle(
                      color: HomeLuxuryPalette.textPrimary,
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.25,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Kúsky, ktoré sa hodia do tvojho šatníka.',
                    style: TextStyle(
                      color: HomeLuxuryPalette.textSecondary.withOpacity(0.88),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onOpenRecommended,
              child: Text(
                'Zobraziť',
                style: TextStyle(
                  color: HomeLuxuryPalette.accent.withOpacity(0.95),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 268,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(right: 4),
            itemCount: _items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) =>
                _RecommendedCard(item: _items[index], onTap: onOpenRecommended),
          ),
        ),
      ],
    );
  }
}

class _RecItem {
  const _RecItem({
    required this.brand,
    required this.name,
    required this.price,
    required this.matchLabel,
    required this.icon,
  });

  final String brand;
  final String name;
  final String price;
  final String matchLabel;
  final IconData icon;
}

class _RecommendedCard extends StatelessWidget {
  const _RecommendedCard({
    required this.item,
    required this.onTap,
  });

  final _RecItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: HomeGlassSurface(
          borderRadius: 22,
          blurSigma: 14,
          padding: const EdgeInsets.all(15),
          child: SizedBox(
            width: 216,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    Container(
                      height: 118,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          colors: [
                            HomeLuxuryPalette.surfaceElevated.withOpacity(0.98),
                            HomeLuxuryPalette.surface.withOpacity(0.85),
                            HomeLuxuryPalette.bgMid.withOpacity(0.55),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(color: HomeLuxuryPalette.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          item.icon,
                          color: HomeLuxuryPalette.accent.withOpacity(0.42),
                          size: 48,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: HomeLuxuryPalette.surface.withOpacity(0.88),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: HomeLuxuryPalette.border),
                          boxShadow: [
                            BoxShadow(
                              color: HomeLuxuryPalette.accent.withOpacity(0.08),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Text(
                          item.matchLabel,
                          style: TextStyle(
                            color: HomeLuxuryPalette.textSecondary.withOpacity(0.94),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  item.brand.toUpperCase(),
                  style: TextStyle(
                    color: HomeLuxuryPalette.textSecondary.withOpacity(0.9),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: HomeLuxuryPalette.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Text(
                      item.price,
                      style: const TextStyle(
                        color: HomeLuxuryPalette.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: HomeLuxuryPalette.surfaceElevated.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: HomeLuxuryPalette.border),
                      ),
                      child: Icon(
                        Icons.bookmark_outline_rounded,
                        color: HomeLuxuryPalette.textSecondary.withOpacity(0.95),
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
