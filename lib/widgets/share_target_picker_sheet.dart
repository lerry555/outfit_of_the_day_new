import 'package:flutter/material.dart';

/// ✅ Unikátny názov aby sa to nebilo s ničím v appke
enum ShareDestination {
  stylistChat,
  wishlist,
}

class ShareTargetPickerSheet extends StatelessWidget {
  final String sharedUrl;

  const ShareTargetPickerSheet({
    super.key,
    required this.sharedUrl,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kam chceš pridať tento odkaz?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              sharedUrl,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 14),

            _option(
              context,
              icon: Icons.chat_bubble_outline,
              title: 'Stylist chat',
              subtitle: 'Pošli odkaz stylistovi a nech ti poradí.',
              onTap: () => Navigator.pop(context, ShareDestination.stylistChat),
            ),
            const SizedBox(height: 6),

            _option(
              context,
              icon: Icons.favorite_border,
              title: 'Wishlist',
              subtitle: 'Uložiť na neskôr.',
              onTap: () => Navigator.pop(context, ShareDestination.wishlist),
            ),
          ],
        ),
      ),
    );
  }

  Widget _option(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String subtitle,
        required VoidCallback onTap,
      }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 42,
                height: 42,
                child: Center(child: Icon(icon)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
