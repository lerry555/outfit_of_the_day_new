part of 'home_screen.dart';

List<_HeroOutfitItem> _orderedHeroOutfitItems(List<_HeroOutfitItem> items) {
  final orderedItems = <_HeroOutfitItem>[];
  void addByType(_HeroWearType type) {
    for (final item in items) {
      if (item.type == type) {
        orderedItems.add(item);
        break;
      }
    }
  }

  addByType(_HeroWearType.outerwear);
  addByType(_HeroWearType.top);
  addByType(_HeroWearType.bottom);
  addByType(_HeroWearType.shoes);
  return orderedItems;
}

bool _isEmptyHeroEditSlot(_HeroOutfitItem item) {
  return (item.wardrobeItemId ?? '').trim().isEmpty &&
      (item.imageUrl ?? '').trim().isEmpty;
}

/// Edit-only optional outerwear tile. Not persisted; filling it does not force
/// a layer outside weather/context ranking.
List<_HeroOutfitItem> _heroEditDisplayItems({
  required List<_HeroOutfitItem> items,
  required bool editMode,
}) {
  final ordered = _orderedHeroOutfitItems(items);
  if (!editMode) return ordered;
  if (ordered.any((item) => item.type == _HeroWearType.outerwear)) {
    return ordered;
  }
  return [
    const _HeroOutfitItem(
      type: _HeroWearType.outerwear,
      icon: Icons.add,
      label: 'Pridať vrstvu',
    ),
    ...ordered,
  ];
}

String _heroOutfitVisualSlotKey(String dayPrefix, _HeroWearType type) {
  switch (type) {
    case _HeroWearType.top:
      return '${dayPrefix}_top_0';
    case _HeroWearType.bottom:
      return '${dayPrefix}_bottom_0';
    case _HeroWearType.shoes:
      return '${dayPrefix}_shoes_0';
    case _HeroWearType.outerwear:
      return '${dayPrefix}_outerwear_0';
  }
}

class _HeroOutfitTilesGrid extends StatelessWidget {
  final String heroDayKey;
  final List<_HeroOutfitItem> items;
  final bool compact;
  final double imageScaleMultiplier;
  final double recreatedShoeScaleBoost;
  final double spacingMultiplier;
  final double horizontalSpacingMultiplier;
  final double verticalSpacingMultiplier;
  final double fourItemRowSpacingExtra;
  final bool disableBoundedScroll;
  final bool editMode;
  final _HeroWearType? focusedType;
  final ValueChanged<_HeroOutfitItem>? onItemTap;
  final ValueChanged<_HeroOutfitItem>? onRemoveTap;
  final Map<_HeroWearType, String> optionalItemHints;

  const _HeroOutfitTilesGrid({
    super.key,
    required this.heroDayKey,
    required this.items,
    this.compact = false,
    this.imageScaleMultiplier = 1.0,
    this.recreatedShoeScaleBoost = 1.0,
    this.spacingMultiplier = 1.0,
    this.horizontalSpacingMultiplier = 1.0,
    this.verticalSpacingMultiplier = 1.0,
    this.fourItemRowSpacingExtra = 10.0,
    this.disableBoundedScroll = false,
    this.editMode = false,
    this.focusedType,
    this.onItemTap,
    this.onRemoveTap,
    this.optionalItemHints = const {},
  });

  /// Same layouts as before, without a bounded parent — used inside [SingleChildScrollView].
  Widget _buildLooseLayout({
    required double maxW,
    required int n,
    required double spacingMultiplier,
    required double horizontalSpacingMultiplier,
    required double verticalSpacingMultiplier,
    required Widget Function(int i) tile,
  }) {
    final narrow = maxW < 168;
    final baseGap = narrow ? 8.0 : (compact ? 10.0 : 14.0);
    final hGap = (baseGap * spacingMultiplier * horizontalSpacingMultiplier)
        .clamp(6.0, 16.0);
    final vGap =
        (baseGap * spacingMultiplier * verticalSpacingMultiplier).clamp(4.0, 16.0);

    if (n <= 3) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < n; i++) ...[
            if (i > 0) SizedBox(height: vGap),
            tile(i),
          ],
        ],
      );
    }

    if (n == 4) {
      final rowGap = (vGap + fourItemRowSpacingExtra).clamp(3.0, 22.0);
      const tileAspect = 0.82;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: hGap,
          mainAxisSpacing: rowGap,
          childAspectRatio: tileAspect,
        ),
        itemCount: 4,
        itemBuilder: (_, i) => tile(i),
      );
    }

    if (n == 5) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: hGap,
            mainAxisSpacing: vGap,
            childAspectRatio: 1,
            children: [tile(0), tile(1), tile(2), tile(3)],
          ),
          SizedBox(height: vGap),
          Align(
            alignment: Alignment.center,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: AspectRatio(
                aspectRatio: 1,
                child: tile(4),
              ),
            ),
          ),
        ],
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: hGap,
        mainAxisSpacing: vGap,
        childAspectRatio: 1,
      ),
      itemCount: n,
      itemBuilder: (_, i) => tile(i),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ordered = _heroEditDisplayItems(items: items, editMode: editMode);
    final display = ordered.length > 6 ? ordered.sublist(0, 6) : ordered;
    final n = display.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final narrow = maxW < 168;
        final baseGap = narrow ? 8.0 : (compact ? 10.0 : 14.0);
        final hGap =
            (baseGap * spacingMultiplier * horizontalSpacingMultiplier)
                .clamp(6.0, 16.0);
        final vGap =
            (baseGap * spacingMultiplier * verticalSpacingMultiplier)
                .clamp(4.0, 16.0);
        final maxH = constraints.maxHeight;
        final heightBounded =
            maxH.isFinite && maxH < double.infinity && maxH > 1;

        Widget tile(int i) {
          final item = display[i];
          final slotKey = _heroOutfitVisualSlotKey(heroDayKey, item.type);
          return _HeroOutfitTileCard(
            heroDayKey: heroDayKey,
            visualSlotKey: slotKey,
            item: item,
            compact: compact,
            imageScaleMultiplier: imageScaleMultiplier,
            recreatedShoeScaleBoost: recreatedShoeScaleBoost,
            editMode: editMode,
            selected: focusedType == null || focusedType == display[i].type,
            onTap: onItemTap == null ? null : () => onItemTap!(display[i]),
            onRemoveTap: onRemoveTap == null ? null : () => onRemoveTap!(item),
            optionalInfoHint: optionalItemHints[item.type],
          );
        }

        Widget tileFill(int i) {
          final item = display[i];
          final slotKey = _heroOutfitVisualSlotKey(heroDayKey, item.type);
          return _HeroOutfitTileCard(
            heroDayKey: heroDayKey,
            visualSlotKey: slotKey,
            item: item,
            compact: compact,
            imageScaleMultiplier: imageScaleMultiplier,
            recreatedShoeScaleBoost: recreatedShoeScaleBoost,
            expandCell: true,
            editMode: editMode,
            selected: focusedType == null || focusedType == display[i].type,
            onTap: onItemTap == null ? null : () => onItemTap!(display[i]),
            onRemoveTap: onRemoveTap == null ? null : () => onRemoveTap!(item),
            optionalInfoHint: optionalItemHints[item.type],
          );
        }

        if (n == 0) {
          return const SizedBox.shrink();
        }

        // Exactly 3 items: 2 tiles on top row, 1 tile on bottom-left.
        // Keeps the outfit compact and fully visible in shared hero body.
        if (n == 3 && heightBounded && !disableBoundedScroll) {
          final rowGap = (vGap * 0.92).clamp(4.0, 12.0);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: tileFill(0)),
                    SizedBox(width: hGap),
                    Expanded(child: tileFill(1)),
                  ],
                ),
              ),
              SizedBox(height: rowGap),
              Expanded(child: tileFill(2)),
            ],
          );
        }

        // 2×2 fills the shared hero body; equal row heights; no shrink-wrap grid height.
        if (n == 4 && heightBounded && !disableBoundedScroll) {
          final rowGap = vGap + 4;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: tileFill(0)),
                    SizedBox(width: hGap),
                    Expanded(child: tileFill(1)),
                  ],
                ),
              ),
              SizedBox(height: rowGap),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: tileFill(2)),
                    SizedBox(width: hGap),
                    Expanded(child: tileFill(3)),
                  ],
                ),
              ),
            ],
          );
        }

        final loose = _buildLooseLayout(
          maxW: maxW,
          n: n,
          spacingMultiplier: spacingMultiplier,
          horizontalSpacingMultiplier: horizontalSpacingMultiplier,
          verticalSpacingMultiplier: verticalSpacingMultiplier,
          tile: tile,
        );

        if (heightBounded && !disableBoundedScroll) {
          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: loose,
          );
        }

        return AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: loose,
        );
      },
    );
  }
}
