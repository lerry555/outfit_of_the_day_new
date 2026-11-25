// Web-only: browser-native <img> displays cross-origin Storage download URLs
// without requiring CanvasKit to fetch image bytes through CORS.
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/widgets.dart';

int _nextImageId = 0;

Widget? wardrobeWebImage(String url, {BoxFit fit = BoxFit.contain}) {
  final id = 'wardrobe-native-img-${_nextImageId++}';
  ui_web.platformViewRegistry.registerViewFactory(id, (int viewId) {
    final img = html.ImageElement(src: url)
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = fit == BoxFit.cover ? 'cover' : 'contain'
      ..style.objectPosition = 'center';
    return img;
  });
  return HtmlElementView(viewType: id);
}
