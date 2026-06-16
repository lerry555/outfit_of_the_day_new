part of 'home_screen.dart';

/// Scale factors for PNG previews — tops/pants run large if over-scaled; shoes stay slightly bolder.
double _heroOutfitImageScale(_HeroWearType type, {required bool compact}) {
  if (compact) {
    switch (type) {
      case _HeroWearType.top:
        return 1.02;
      case _HeroWearType.bottom:
        return 0.94;
      case _HeroWearType.outerwear:
        return 0.98;
      case _HeroWearType.shoes:
        return 1.08;
    }
  }
  switch (type) {
    case _HeroWearType.top:
      return 1.0;
    case _HeroWearType.bottom:
      return 0.92;
    case _HeroWearType.outerwear:
      return 0.96;
    case _HeroWearType.shoes:
      return 1.06;
  }
}

enum _HeroImageRole { top, outerwear, pants, shorts, shoes, other }

_HeroImageRole _heroImageRole({
  required _HeroWearType wearType,
  required String? categoryKey,
  required String? subCategoryKey,
  required String? label,
}) {
  final blob = _normalizedScaleToken('$categoryKey $subCategoryKey $label');
  bool has(List<String> words) =>
      words.any((w) => blob.contains(_normalizedScaleToken(w)));
  if (wearType == _HeroWearType.shoes ||
      has(['sneaker', 'tenisky', 'topanky', 'topánky', 'obuv', 'shoes'])) {
    return _HeroImageRole.shoes;
  }
  if (has(['short', 'kratasy', 'kraťasy'])) return _HeroImageRole.shorts;
  if (has(['jeans', 'rifle', 'nohavice', 'pants'])) {
    return _HeroImageRole.pants;
  }
  if (wearType == _HeroWearType.outerwear ||
      has([
        'hoodie',
        'mikina',
        'jacket',
        'bunda',
        'coat',
        'kabat',
        'kabát',
        'blazer',
        'sako',
      ])) {
    return _HeroImageRole.outerwear;
  }
  if (wearType == _HeroWearType.top ||
      has([
        't-shirt',
        'tricko',
        'tričko',
        'tank',
        'tielko',
        'shirt',
        'kosela',
        'koše',
      ])) {
    return _HeroImageRole.top;
  }
  return _HeroImageRole.other;
}

double _heroCategoryScaleBoost({
  required _HeroWearType wearType,
  required String? categoryKey,
  required String? subCategoryKey,
  required String? label,
  required bool compact,
}) {
  final role = _heroImageRole(
    wearType: wearType,
    categoryKey: categoryKey,
    subCategoryKey: subCategoryKey,
    label: label,
  );
  switch (role) {
    case _HeroImageRole.top:
      return 0.0;
    case _HeroImageRole.outerwear:
      return compact ? -0.02 : -0.02;
    case _HeroImageRole.pants:
      return compact ? -0.08 : -0.07;
    case _HeroImageRole.shorts:
      return 0.0;
    case _HeroImageRole.shoes:
      return compact ? 0.02 : 0.02;
    case _HeroImageRole.other:
      return 0.0;
  }
}

double _heroCategoryInsetAdjust({
  required _HeroWearType wearType,
  required String? categoryKey,
  required String? subCategoryKey,
  required String? label,
  required bool compact,
}) {
  final role = _heroImageRole(
    wearType: wearType,
    categoryKey: categoryKey,
    subCategoryKey: subCategoryKey,
    label: label,
  );
  switch (role) {
    case _HeroImageRole.top:
      return 0.0;
    case _HeroImageRole.outerwear:
      return compact ? 0.2 : 0.2;
    case _HeroImageRole.pants:
      return compact ? 0.9 : 0.8;
    case _HeroImageRole.shorts:
      return 0.0;
    case _HeroImageRole.shoes:
      return -0.2;
    case _HeroImageRole.other:
      return 0.0;
  }
}

String _normalizedScaleToken(String raw) {
  return raw
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('ä', 'a')
      .replaceAll('č', 'c')
      .replaceAll('ď', 'd')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ľ', 'l')
      .replaceAll('ĺ', 'l')
      .replaceAll('ň', 'n')
      .replaceAll('ó', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('ŕ', 'r')
      .replaceAll('š', 's')
      .replaceAll('ť', 't')
      .replaceAll('ú', 'u')
      .replaceAll('ý', 'y')
      .replaceAll('ž', 'z');
}

class _HeroOutfitTileCard extends StatelessWidget {
  const _HeroOutfitTileCard({
    required this.heroDayKey,
    required this.visualSlotKey,
    required this.item,
    this.compact = false,
    this.imageScaleMultiplier = 1.0,
    this.recreatedShoeScaleBoost = 1.0,
    this.expandCell = false,
    this.editMode = false,
    this.selected = true,
    this.onTap,
    this.onRemoveTap,
    this.optionalInfoHint,
  });

  final String heroDayKey;
  final String visualSlotKey;
  final _HeroOutfitItem item;
  final bool compact;
  final double imageScaleMultiplier;
  final double recreatedShoeScaleBoost;

  /// Fill a flex cell in the 2×2 shared-height grid (non-square cell).
  final bool expandCell;
  final bool editMode;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onRemoveTap;
  final String? optionalInfoHint;

  @override
  Widget build(BuildContext context) {
    final outerR = compact ? 16.0 : 18.0;
    final innerR = compact ? 14.0 : 14.0;
    final pad = compact ? 5.0 : 5.0;

    Widget heroTileImage() {
      return _HeroOutfitImageView(
        heroDayKey: heroDayKey,
        imageUrl: item.imageUrl,
        wardrobeItemId: item.wardrobeItemId,
        visualSlotKey: visualSlotKey,
        fallbackIcon: item.icon,
        wearType: item.type,
        categoryKey: item.categoryKey,
        subCategoryKey: item.subCategoryKey,
        itemLabel: item.label,
        compact: compact,
        imageScaleMultiplier: imageScaleMultiplier,
        recreatedShoeScaleBoost: recreatedShoeScaleBoost,
        showProcessingBadge: item.imageProcessing,
      );
    }

    final tileDecoration = BoxDecoration(
      borderRadius: BorderRadius.circular(outerR),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          HomeLuxuryPalette.surface.withOpacity(0.34),
          HomeLuxuryPalette.surfaceSoft.withOpacity(0.14),
        ],
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.14),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
        if (editMode)
          BoxShadow(
            color: HomeLuxuryPalette.accent.withOpacity(selected ? 0.24 : 0.12),
            blurRadius: selected ? 20 : 14,
            spreadRadius: 0,
          ),
      ],
      border: Border.all(
        color: editMode
            ? HomeLuxuryPalette.accent.withOpacity(selected ? 0.34 : 0.12)
            : Colors.transparent,
        width: editMode ? 1.1 : 0,
      ),
    );

    final core = editMode
        ? AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.all(pad),
            decoration: tileDecoration,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(innerR),
              child: heroTileImage(),
            ),
          )
        : Container(
            padding: EdgeInsets.all(pad),
            decoration: tileDecoration,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(innerR),
              child: heroTileImage(),
            ),
          );

    final showOptionalInfo =
        !editMode && (optionalInfoHint?.trim().isNotEmpty ?? false);

    Widget optionalInfoOverlay() {
      final hint = optionalInfoHint!.trim();
      final label = item.label.trim().isNotEmpty ? item.label.trim() : 'Položka';
      return Positioned(
        left: 6,
        right: 6,
        bottom: 6,
        child: Material(
          color: Colors.transparent,
          child: HomeGlassSurface(
            borderRadius: 10,
            blurSigma: 10,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: HomeLuxuryPalette.textPrimary.withOpacity(0.94),
                      fontSize: compact ? 10.5 : 11.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    HomeOutfitItemInfoSheet.show(
                      context,
                      title: label,
                      body: hint,
                    );
                  },
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Text('ℹ️', style: TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final body = editMode
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(outerR),
                    splashColor: HomeLuxuryPalette.accent.withOpacity(0.08),
                    highlightColor: HomeLuxuryPalette.accent.withOpacity(0.04),
                    child: core,
                  ),
                ),
              ),
              Positioned(
                top: 7,
                right: 7,
                child: _HeroRemoveChip(onTap: onRemoveTap),
              ),
            ],
          )
        : showOptionalInfo
            ? Stack(
                clipBehavior: Clip.none,
                children: [
                  core,
                  optionalInfoOverlay(),
                ],
              )
            : core;

    if (expandCell) {
      return SizedBox.expand(child: body);
    }

    return AspectRatio(
      aspectRatio: 1,
      child: body,
    );
  }
}

class _HeroRemoveChip extends StatelessWidget {
  const _HeroRemoveChip({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: HomeGlassSurface(
          borderRadius: 999,
          blurSigma: 10,
          padding: const EdgeInsets.all(6),
          child: Text(
            '✕',
            style: TextStyle(
              color: HomeLuxuryPalette.accent.withOpacity(0.95),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroOutfitImageView extends StatelessWidget {
  final String heroDayKey;
  final String? imageUrl;
  final String? wardrobeItemId;
  final String? visualSlotKey;
  final IconData fallbackIcon;
  final _HeroWearType wearType;
  final String? categoryKey;
  final String? subCategoryKey;
  final String? itemLabel;
  final bool compact;
  final double imageScaleMultiplier;
  final double recreatedShoeScaleBoost;
  final bool showProcessingBadge;

  const _HeroOutfitImageView({
    required this.heroDayKey,
    required this.imageUrl,
    this.wardrobeItemId,
    this.visualSlotKey,
    required this.fallbackIcon,
    required this.wearType,
    this.categoryKey,
    this.subCategoryKey,
    this.itemLabel,
    this.compact = false,
    this.imageScaleMultiplier = 1.0,
    this.recreatedShoeScaleBoost = 1.0,
    this.showProcessingBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedImageUrl = imageUrl?.trim();
    final hasImage = normalizedImageUrl != null && normalizedImageUrl.isNotEmpty;
    final ph = compact ? 26.0 : 36.0;
    final baseInset = compact ? 5.0 : 6.0;
    final baseScale = _heroOutfitImageScale(wearType, compact: compact);
    final categoryBoost = _heroCategoryScaleBoost(
      wearType: wearType,
      categoryKey: categoryKey,
      subCategoryKey: subCategoryKey,
      label: itemLabel,
      compact: compact,
    );
    final insetAdjust = _heroCategoryInsetAdjust(
      wearType: wearType,
      categoryKey: categoryKey,
      subCategoryKey: subCategoryKey,
      label: itemLabel,
      compact: compact,
    );
    final role = _heroImageRole(
      wearType: wearType,
      categoryKey: categoryKey,
      subCategoryKey: subCategoryKey,
      label: itemLabel,
    );
    final inset = (baseInset + insetAdjust).clamp(2.2, 7.0).toDouble();
    double insetX = inset;
    double insetY = inset;
    if (role == _HeroImageRole.pants) {
      insetY = (inset + (compact ? 1.0 : 0.8)).clamp(2.2, 8.0);
      insetX = (inset - 0.4).clamp(1.8, 6.6);
    } else if (role == _HeroImageRole.shoes) {
      insetX = (inset - (compact ? 0.7 : 0.5)).clamp(1.6, 6.4);
      insetY = (inset + 0.2).clamp(2.2, 7.6);
    } else if (role == _HeroImageRole.outerwear) {
      insetY = (inset + 0.3).clamp(2.2, 7.6);
    }
    final localShoeBoost =
        wearType == _HeroWearType.shoes ? recreatedShoeScaleBoost : 1.0;
    final scale =
        ((baseScale + categoryBoost) * imageScaleMultiplier * localShoeBoost)
            .clamp(0.72, compact ? 2.08 : 1.84)
            .toDouble();

    Widget previewBody({required Widget child}) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: insetX, vertical: insetY),
        child: Center(
          child: Transform.scale(
            scale: scale,
            child: child,
          ),
        ),
      );
    }

    if (!hasImage) {
      return previewBody(
        child: _OutfitPreviewPlaceholder(icon: fallbackIcon, size: ph),
      );
    }

    final slotKey = visualSlotKey?.trim();
    final imageChild = Image.network(
      normalizedImageUrl,
      key: slotKey != null && slotKey.isNotEmpty ? ValueKey(slotKey) : null,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      alignment: Alignment.center,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );

    if (!showProcessingBadge) {
      return previewBody(child: imageChild);
    }

    return previewBody(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          imageChild,
          Positioned(
            top: compact ? 4 : 6,
            right: compact ? 4 : 6,
            child: Container(
              width: compact ? 20 : 22,
              height: compact ? 20 : 22,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.35)),
              ),
              padding: const EdgeInsets.all(3),
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutfitPreviewPlaceholder extends StatelessWidget {
  final IconData icon;
  final double size;

  const _OutfitPreviewPlaceholder({
    required this.icon,
    this.size = 34,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        icon,
        color: HomeLuxuryPalette.textSecondary.withOpacity(0.92),
        size: size,
      ),
    );
  }
}
