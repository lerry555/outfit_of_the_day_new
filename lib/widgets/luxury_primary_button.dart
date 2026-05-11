import 'package:flutter/material.dart';

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
    const goldTop = Color(0xFFC8A36A);
    const goldBottom = Color(0xFF9D7C4C);
    const darkText = Color(0xFF191512);

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [goldTop, goldBottom],
          ),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: goldTop.withOpacity(0.45)),
          boxShadow: [
            BoxShadow(
              color: goldTop.withOpacity(0.26),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(darkText),
                ),
              )
            else
              Text(
                text,
                style: const TextStyle(
                  color: darkText,
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (!isLoading) const SizedBox(width: 10),
            if (!isLoading)
              Icon(
                Icons.arrow_forward_ios,
                color: darkText.withOpacity(0.85),
                size: 16,
              ),
          ],
        ),
      ),
    );
  }
}

