import 'package:flutter/material.dart';

import 'home/home_luxury_palette.dart';

/// Shared OOTD CTA + header tokens (gold primary, dark secondary).
abstract final class OotdCtaColors {
  static const Color gold = HomeLuxuryPalette.accent;
  static const Color goldSoft = HomeLuxuryPalette.accentSoft;
  static const Color onGold = Color(0xFF191512);
  static const Color onGoldIcon = Colors.black87;
}

/// Typography for luxury dark screens.
abstract final class OotdHeaderStyle {
  static TextStyle screenTitle({
    double fontSize = 18,
    FontWeight fontWeight = FontWeight.w800,
  }) {
    return HomeLuxuryPalette.titleMedium.copyWith(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: OotdCtaColors.gold,
    );
  }

  static TextStyle sectionTitle({
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.w800,
  }) {
    return TextStyle(
      color: OotdCtaColors.gold,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: -0.2,
    );
  }

  static TextStyle subtitle({
    double fontSize = 12.5,
    FontWeight fontWeight = FontWeight.w600,
  }) {
    return HomeLuxuryPalette.homeTagline.copyWith(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: HomeLuxuryPalette.textSecondary,
    );
  }
}

/// Circular back control — gold arrow on dark glass chip.
class OotdBackButton extends StatelessWidget {
  const OotdBackButton({
    super.key,
    required this.onTap,
    this.size = 40,
    this.iconSize = 20,
  });

  final VoidCallback onTap;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: HomeLuxuryPalette.surface.withOpacity(0.65),
          border: Border.all(color: HomeLuxuryPalette.border),
        ),
        child: Icon(
          Icons.arrow_back_rounded,
          color: OotdCtaColors.gold,
          size: iconSize,
        ),
      ),
    );
  }
}

/// Gold pill — main confirmation actions.
class OotdPrimaryButton extends StatelessWidget {
  const OotdPrimaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.showTrailingArrow = true,
    this.leadingIcon,
    this.height,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    this.borderRadius = 999,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool showTrailingArrow;
  final IconData? leadingIcon;
  final double? height;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    Widget button = InkWell(
      onTap: isLoading ? null : onPressed,
      borderRadius: radius,
      child: Container(
        width: height != null ? double.infinity : null,
        height: height,
        alignment: height != null ? Alignment.center : null,
        padding: padding,
        decoration: BoxDecoration(
          color: OotdCtaColors.gold,
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.32),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: OotdCtaColors.gold.withOpacity(0.45),
              blurRadius: 22,
              spreadRadius: -2,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: OotdCtaColors.onGoldIcon,
                ),
              ),
              const SizedBox(width: 10),
            ] else if (leadingIcon != null) ...[
              Icon(leadingIcon, size: 18, color: OotdCtaColors.onGoldIcon),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: OotdCtaColors.onGoldIcon,
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            if (!isLoading && showTrailingArrow) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: OotdCtaColors.onGoldIcon,
              ),
            ],
          ],
        ),
      ),
    );

    if (height != null) {
      return SizedBox(
        width: double.infinity,
        height: height,
        child: button,
      );
    }

    return button;
  }
}

/// Dark pill — utility / secondary actions.
class OotdSecondaryButton extends StatelessWidget {
  const OotdSecondaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.active = false,
  });

  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final fg = !enabled
        ? HomeLuxuryPalette.textSecondary.withOpacity(0.45)
        : HomeLuxuryPalette.textPrimary;

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? HomeLuxuryPalette.textPrimary.withOpacity(0.22)
                : HomeLuxuryPalette.border,
          ),
          color: active
              ? HomeLuxuryPalette.surfaceElevated.withOpacity(0.72)
              : HomeLuxuryPalette.surface.withOpacity(0.55),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: fg),
              const SizedBox(width: 8),
            ],
            Text(
              text,
              style: TextStyle(
                color: fg,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Text-only secondary action (e.g. Zrušiť in sheets).
class OotdSecondaryTextButton extends StatelessWidget {
  const OotdSecondaryTextButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(
          color: HomeLuxuryPalette.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
