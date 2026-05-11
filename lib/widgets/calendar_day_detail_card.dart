import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/calendar_outfit_models.dart';
import '../Services/date_weather_service.dart';
import 'luxury_primary_button.dart';
import 'outfit_preview_tiles.dart';

class CalendarDayDetailCard extends StatelessWidget {
  const CalendarDayDetailCard({
    super.key,
    required this.date,
    required this.weather,
    required this.outfitDay,
    required this.isOutfitLoading,
    required this.isGenerating,
    required this.isGenerationLocked,
    required this.onGenerate,
    required this.onUnlockPlanning,
    required this.onEditOutfit,
  });

  final DateTime date;
  final DateWeatherSnapshot weather;
  final CalendarOutfitDay? outfitDay;
  final bool isOutfitLoading;
  final bool isGenerating;
  final bool isGenerationLocked;
  final VoidCallback onGenerate;
  final VoidCallback onUnlockPlanning;
  final VoidCallback onEditOutfit;

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat('d. MMMM yyyy', 'sk_SK').format(date);
    final theme = Theme.of(context);
    final items = outfitDay?.outfitItems ?? const <CalendarOutfitItem>[];
    final hasOutfit = items.isNotEmpty;
    final weatherTags = <String>[
      if (weather.isWindy) 'vietor',
      if (weather.isRainy) 'dážď',
      if (!weather.isWindy && !weather.isRainy) 'jasno',
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.22),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.09)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 22,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formattedDate,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.10),
                        ),
                      ),
                      child: Text(
                        weather.sourceLabel,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${weather.tempC}°C • ${weatherTags.join(' • ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              Text(
                hasOutfit ? 'Outfit pre tento deň' : 'Outfit pre tento deň ešte nie je vytvorený',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _buildOutfitSection(),
              ),



              const SizedBox(height: 14),

              if (!hasOutfit || isGenerating)
                SizedBox(
                  width: double.infinity,
                  child: isGenerationLocked
                      ? _LockedPlanningButton(onTap: onUnlockPlanning)
                      : LuxuryPrimaryButton(
                          text: isGenerating
                              ? 'Generujem outfit...'
                              : 'Vygenerovať outfit',
                          isLoading: isGenerating,
                          onTap: onGenerate,
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOutfitSection() {
    if (isOutfitLoading) {
      return SizedBox(
        key: const ValueKey('outfit-loading'),
        height: 140,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 4,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            return const _SkeletonTile();
          },
        ),
      );
    }

    final items = outfitDay?.outfitItems ?? const <CalendarOutfitItem>[];
    final hasOutfit = items.isNotEmpty;

    if (!hasOutfit) {
      return Container(
        key: const ValueKey('outfit-empty'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.redAccent.withOpacity(0.25)),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.redAccent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Na tento deň zatiaľ nemáš uložený outfit. Stlač tlačidlo nižšie a outfit sa vygeneruje podľa počasia a tvojho šatníka.',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      key: const ValueKey('outfit-present'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutfitPreviewTiles(
            items: items,
            showLabels: true,
          ),
          if (outfitDay?.reason != null && outfitDay!.reason!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              outfitDay!.reason!,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12.6,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (outfitDay != null && hasOutfit) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: LuxuryPrimaryButton(
                text: 'Upraviť outfit',
                onTap: onEditOutfit,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12.0),
      child: Container(
        width: 96,
        height: 130,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.white.withOpacity(0.04),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Colors.white.withOpacity(0.06),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 70,
              height: 10,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: Colors.white.withOpacity(0.06),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LockedPlanningButton extends StatelessWidget {
  const _LockedPlanningButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.lock_outline_rounded, size: 18),
      label: const Text(
        'Odomknúť plánovanie',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        foregroundColor: const Color(0xFFC8A36A),
        side: const BorderSide(color: Color(0x66C8A36A)),
        backgroundColor: const Color(0x2224252A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}