import 'package:flutter/material.dart';

import 'ootd_cta_system.dart';

/// Thin wrapper around [OotdPrimaryButton] for existing call sites.
class LuxuryPrimaryButton extends StatelessWidget {
  const LuxuryPrimaryButton({
    super.key,
    required this.text,
    required this.onTap,
    this.isLoading = false,
  });

  final String text;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return OotdPrimaryButton(
      text: text,
      onPressed: onTap,
      isLoading: isLoading,
      showTrailingArrow: true,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    );
  }
}
