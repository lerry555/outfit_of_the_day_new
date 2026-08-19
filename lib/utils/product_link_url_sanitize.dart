bool _isTrackingQueryKey(String key) {
  final k = key.toLowerCase();
  if (k.startsWith('utm_')) return true;
  return k == 'gclid' ||
      k == 'fbclid' ||
      k == 'igshid' ||
      k == 'mc_eid' ||
      k == 'mc_cid' ||
      k == 'msclkid' ||
      k == '_ga' ||
      k == '_gl';
}

String canonicalProductLinkUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return trimmed;
  try {
    final uri = Uri.parse(trimmed.contains('://') ? trimmed : 'https://$trimmed');
    final kept = <String, String>{};
    for (final entry in uri.queryParameters.entries) {
      if (_isTrackingQueryKey(entry.key)) continue;
      kept[entry.key] = entry.value;
    }
    return Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      queryParameters: kept.isEmpty ? null : kept,
    ).toString();
  } catch (_) {
    return trimmed;
  }
}
