import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../domain/style_preferences/user_style_preferences.dart';

/// Reads the live style-preference store. Never reads legacy user-root fields.
class UserStylePreferencesReader {
  UserStylePreferencesReader({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _firestore = firestore,
       _auth = auth;

  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;
  FirebaseAuth get _firebaseAuth => _auth ?? FirebaseAuth.instance;

  static const String collectionId = 'stylePreferences';
  static const String documentId = 'main';

  Future<UserStylePreferences> loadForCurrentUser() {
    return loadForUid(_firebaseAuth.currentUser?.uid);
  }

  Future<UserStylePreferences> loadForUid(String? uid) async {
    if (uid == null || uid.isEmpty) return UserStylePreferences.empty;
    try {
      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection(collectionId)
          .doc(documentId)
          .get();
      if (!snap.exists) return UserStylePreferences.empty;
      return UserStylePreferences.fromMap(snap.data());
    } catch (error) {
      debugPrint('style preferences read failed: $error');
      return UserStylePreferences.empty;
    }
  }
}
