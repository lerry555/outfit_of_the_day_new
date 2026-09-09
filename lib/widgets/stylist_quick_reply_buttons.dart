import 'package:flutter/material.dart';

bool shouldShowStylistQuickReplies({
  required String quickReplyMode,
  required bool isUser,
  required bool isLatest,
  required bool isSending,
  required bool hasPendingImage,
  required bool isPhotoConversationActive,
  required bool hasAlternativeActions,
}) {
  return quickReplyMode == 'yes_no' &&
      !isUser &&
      isLatest &&
      !isSending &&
      !hasPendingImage &&
      !isPhotoConversationActive &&
      !hasAlternativeActions;
}

/// Compact replies for a server-confirmed yes/no shopping follow-up. The
/// question deliberately lives with the controls, so an outfit message can be
/// rendered as: explanation -> wardrobe cards -> CTA -> Áno/Nie.
/// The selected value goes through the ordinary chat send path, preserving full
/// conversation context and entitlement handling.
class StylistQuickReplyButtons extends StatelessWidget {
  const StylistQuickReplyButtons({super.key, this.prompt, required this.onSelected});

  final String? prompt;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFC8A36A);
    const darkText = Color(0xFF191512);
    const lightText = Color(0xFFF1F0EC);
    const secondaryText = Color(0xFFCBC6BC);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          (prompt ?? '').trim().isNotEmpty
              ? prompt!.trim()
              : 'Chceš, aby som ti vybral vhodnejší kúsok do šatníka?',
          key: const ValueKey('stylist-quick-reply-prompt'),
          style: const TextStyle(
            color: secondaryText,
            fontSize: 13,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 36,
                child: FilledButton(
                  key: const ValueKey('stylist-quick-reply-yes'),
                  onPressed: () => onSelected('Áno'),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: darkText,
                    shape: shape,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text(
                    'Áno',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 36,
                child: OutlinedButton(
                  key: const ValueKey('stylist-quick-reply-no'),
                  onPressed: () => onSelected('Nie'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: lightText,
                    side: BorderSide(color: accent.withValues(alpha: 0.72)),
                    shape: shape,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text(
                    'Nie',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
