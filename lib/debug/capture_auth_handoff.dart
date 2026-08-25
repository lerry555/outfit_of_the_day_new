import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// One-shot, debug-only Firebase ID token handoff for the local capture tool.
///
/// The token is sent only to an adb-reversed loopback port and is never logged
/// or persisted by this code path.
abstract final class CaptureAuthHandoff {
  static const _enabled = bool.fromEnvironment('OOTD_CAPTURE_AUTH_HANDOFF');
  static const _port = int.fromEnvironment('OOTD_CAPTURE_AUTH_PORT');
  static const _nonce = String.fromEnvironment('OOTD_CAPTURE_AUTH_NONCE');

  static Future<bool> runIfEnabled() async {
    if (!kDebugMode || !_enabled) return false;
    if (_port < 1 || _port > 65535 || _nonce.length < 32) {
      throw StateError('capture_auth_handoff_invalid_configuration');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('capture_auth_unavailable');
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw StateError('capture_auth_unavailable');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:$_port/capture-auth'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'nonce': _nonce, 'token': token}));
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      await response.drain<void>();
      if (response.statusCode != HttpStatus.noContent) {
        throw StateError('capture_auth_handoff_rejected');
      }
      return true;
    } finally {
      client.close(force: true);
    }
  }
}
