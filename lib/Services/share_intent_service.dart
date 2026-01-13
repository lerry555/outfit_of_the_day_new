import 'dart:async';

import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../widgets/share_target_picker_sheet.dart';
import '../screens/outfit_builder_screen.dart';

class ShareIntentService {
  static StreamSubscription? _sub;
  static bool _started = false;

  static void start(BuildContext context) {
    if (_started) return;
    _started = true;

    // ✅ 1) STREAM – keď appka beží a príde share (väčšina verzií má MEDIA stream)
    _sub = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> files) async {
      if (files.isEmpty) return;
      final maybeText = files.first.path.trim();
      if (maybeText.isNotEmpty) {
        await _handleIncomingSharedText(context, maybeText);
      }
    }, onError: (_) {});

    // ✅ 2) INITIAL – keď appka bola spustená cez share
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> files) async {
      if (files.isEmpty) return;
      final maybeText = files.first.path.trim();
      if (maybeText.isNotEmpty) {
        await _handleIncomingSharedText(context, maybeText);
      }
    });
  }

  static Future<void> _handleIncomingSharedText(BuildContext context, String raw) async {
    final url = raw.trim();
    if (url.isEmpty) return;

    final ShareDestination? dest = await showModalBottomSheet<ShareDestination>(
      context: context,
      showDragHandle: true,
      builder: (_) => ShareTargetPickerSheet(sharedUrl: url),
    );

    if (dest == null) return;
    if (!context.mounted) return;

    switch (dest) {
      case ShareDestination.outfitBuilder:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OutfitBuilderScreen(incomingExternalUrl: url),
          ),
        );
        break;

      case ShareDestination.stylistChat:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stylist chat napojíme ako ďalší krok.')),
        );
        break;

      case ShareDestination.wishlist:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wishlist napojíme ako ďalší krok.')),
        );
        break;
    }

    try {
      ReceiveSharingIntent.instance.reset();
    } catch (_) {}
  }

  static void stop() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }
}
