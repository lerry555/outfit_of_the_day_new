// Web-only browser image renderer with per-item URL fallback.
// Native <img> can load Firebase Storage URLs without Flutter CanvasKit CORS.
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/widgets.dart';

int _nextImageId = 0;

Widget? wardrobeWebImage({
  required List<String> urls,
  BoxFit fit = BoxFit.contain,
}) {
  if (urls.isEmpty) return const SizedBox.expand();
  final id = 'wardrobe-native-img-${_nextImageId++}';
  ui_web.platformViewRegistry.registerViewFactory(id, (int viewId) {
    final img = html.ImageElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = fit == BoxFit.cover ? 'cover' : 'contain'
      ..style.objectPosition = 'center';
    var index = 0;
    img.onError.listen((_) {
      index++;
      if (index < urls.length) {
        img.src = urls[index];
      } else {
        img.style.opacity = '0';
        html.window.console.warn('Wardrobe image unavailable after ${urls.length} candidates');
      }
    });
    img.src = urls.first;
    return img;
  });
  return HtmlElementView(viewType: id);
}
