import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class FcmTokenSyncService {
  FcmTokenSyncService._();

  static final FcmTokenSyncService instance = FcmTokenSyncService._();

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  String? _activeUid;
  String? _lastSavedToken;

  Future<void> initialize() async {
    if (_authSubscription != null) {
      return;
    }

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      unawaited(_handleAuthChange(user));
    });

    await _handleAuthChange(FirebaseAuth.instance.currentUser);
  }

  Future<void> _handleAuthChange(User? user) async {
    final uid = user?.uid;
    _activeUid = uid;
    _lastSavedToken = null;

    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;

    if (uid == null || uid.isEmpty) {
      return;
    }

    _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      unawaited(_saveToken(uid, token));
    });

    await syncNow();
  }

  Future<void> syncNow() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid.isEmpty) {
      return;
    }

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.trim().isEmpty) {
      return;
    }

    await _saveToken(user.uid, token.trim());
  }

  Future<void> _saveToken(String uid, String token) async {
    if (uid.isEmpty || token.isEmpty) {
      return;
    }

    if (_activeUid == uid && _lastSavedToken == token) {
      return;
    }

    await FirebaseFirestore.instance.collection('riders').doc(uid).set({
      'fcmToken': token,
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (_activeUid == uid) {
      _lastSavedToken = token;
    }
  }

  Future<void> clearTokenBeforeLogout() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid.isEmpty) {
      return;
    }

    await FirebaseFirestore.instance.collection('riders').doc(user.uid).set({
      'fcmToken': FieldValue.delete(),
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _lastSavedToken = null;
  }
}