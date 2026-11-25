// Web-only native image renderer. Stable view types prevent recreating <img>
// and re-requesting Firebase Storage photos on every carousel drag frame.
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/widgets.dart';

final Map<String, String> _registeredImageViews = <String, String>{};
int _nextImageId = 0;

Widget? wardrobeWebImage({
  required List<String> urls,
  BoxFit fit = BoxFit.contain,
}) {
  if (urls.isEmpty) return const SizedBox.expand();
  final candidates = List<String>.unmodifiable(urls);
  final key = '${fit.name}|' + candidates.join('\u0001');
  var id = _registeredImageViews[key];
  if (id == null) {
    id = 'wardrobe-native-img-${_nextImageId++}';
    final viewType = id;
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final img = html.ImageElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = fit == BoxFit.cover ? 'cover' : 'contain'
        ..style.objectPosition = 'center'
        ..style.display = 'block';
      var index = 0;
      img.onError.listen((_) {
        index++;
        if (index < candidates.length) {
          img.src = candidates[index];
        } else {
          img.style.opacity = '0';
          html.window.console.warn('Wardrobe image unavailable after ${candidates.length} candidates');
        }
      });
      img.src = candidates.first;
      return img;
    });
    _registeredImageViews[key] = id;
  }
  return HtmlElementView(viewType: id);
}

// Warm the browser's image cache before an inertial flick reaches these items.
// Keep references alive; otherwise browsers may discard in-flight requests.
final Map<String, html.ImageElement> _prefetched = <String, html.ImageElement>{};
void prefetchWardrobeImages(List<String> urls) {
  for (final url in urls) {
    if (url.isEmpty || _prefetched.containsKey(url)) continue;
    final img = html.ImageElement()..src = url;
    _prefetched[url] = img;
    // Limit retained decoded resources on mobile browsers.
    if (_prefetched.length > 36) {
      _prefetched.remove(_prefetched.keys.first);
    }
  }
}
