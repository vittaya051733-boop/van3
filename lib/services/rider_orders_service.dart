import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Shares one Firestore listener for all rider order screens.
class RiderOrdersService {
  RiderOrdersService._();

  static final RiderOrdersService instance = RiderOrdersService._();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  StreamController<QuerySnapshot<Map<String, dynamic>>>? _controller;
  String? _activeUid;

  Stream<QuerySnapshot<Map<String, dynamic>>> get ordersStream {
    final controller = _controller;
    if (controller == null) {
      return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }
    return controller.stream;
  }

  void initialize() {
    FirebaseAuth.instance.authStateChanges().listen(_bindToUser);
    _bindToUser(FirebaseAuth.instance.currentUser);
  }

  void _bindToUser(User? user) {
    final uid = user?.uid;
    if (uid == null || uid.isEmpty) {
      _subscription?.cancel();
      _subscription = null;
      _activeUid = null;
      _controller?.close();
      _controller = null;
      return;
    }

    if (_activeUid == uid && _subscription != null) {
      return;
    }

    _subscription?.cancel();
    _controller?.close();
    _activeUid = uid;
    _controller = StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast();

    _subscription = FirebaseFirestore.instance
        .collection('orders')
        .where('driverId', isEqualTo: uid)
        .snapshots()
        .listen(
          _controller!.add,
          onError: _controller!.addError,
        );
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _controller?.close();
    _controller = null;
    _activeUid = null;
  }
}
