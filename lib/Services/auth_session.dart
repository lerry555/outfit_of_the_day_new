import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'fcm_service.dart';

/// Production sign-out: FCM cleanup while auth is still valid, then Auth.
class AuthSession {
  AuthSession({
    Future<void> Function()? clearFcmRegistration,
    Future<void> Function()? signOutAuth,
  }) : _clearFcmRegistration = clearFcmRegistration,
       _signOutAuth = signOutAuth;

  static final AuthSession instance = AuthSession();

  final Future<void> Function()? _clearFcmRegistration;
  final Future<void> Function()? _signOutAuth;

  /// Removes this device token from the current user, then signs out.
  /// FCM failures are logged and do not block Auth sign-out.
  Future<void> signOut() async {
    try {
      await (_clearFcmRegistration ??
          FcmService.instance.clearLocalRegistration)();
    } catch (e) {
      debugPrint('FCM cleanup on sign-out error: $e');
    }
    await (_signOutAuth ?? FirebaseAuth.instance.signOut)();
  }
}
