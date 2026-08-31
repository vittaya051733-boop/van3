import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/guarded_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Lightweight order document for rider screens (Firestore or Cloud Function).
class RiderOrderDocument {
  const RiderOrderDocument({
    required this.id,
    required Map<String, dynamic> data,
  }) : _data = data;

  final String id;
  final Map<String, dynamic> _data;

  Map<String, dynamic> data() => Map<String, dynamic>.from(_data);
}

class RiderOrdersQuerySnapshot {
  const RiderOrdersQuerySnapshot({
    required this.docs,
    this.fromCloudFunction = false,
  });

  final List<RiderOrderDocument> docs;
  final bool fromCloudFunction;

  static const empty = RiderOrdersQuerySnapshot(docs: <RiderOrderDocument>[]);
}

/// Shares rider order loading across jobs/history/wallet/home screens.
class RiderOrdersService {
  RiderOrdersService._();

  static final RiderOrdersService instance = RiderOrdersService._();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  StreamController<RiderOrdersQuerySnapshot>? _controller;
  RiderOrdersQuerySnapshot _lastSnapshot = RiderOrdersQuerySnapshot.empty;
  String? _activeUid;
  bool _usingCloudFunctionFallback = false;
  Timer? _cloudPollTimer;
  bool _refreshInFlight = false;

  Stream<RiderOrdersQuerySnapshot> get ordersStream {
    _ensureBound();
    final controller = _controller;
    if (controller == null) {
      return Stream<RiderOrdersQuerySnapshot>.value(RiderOrdersQuerySnapshot.empty);
    }

    return Stream<RiderOrdersQuerySnapshot>.multi((multi) {
      multi.add(_lastSnapshot);

      final subscription = controller.stream.listen(
        multi.add,
        onError: (Object error, StackTrace stackTrace) {
          multi.addError(error, stackTrace);
        },
      );
      multi.onCancel = subscription.cancel;
    });
  }

  void initialize() {
    FirebaseAuth.instance.authStateChanges().listen(_bindToUser);
    _bindToUser(FirebaseAuth.instance.currentUser);
  }

  void _ensureBound() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid.isEmpty) {
      return;
    }
    if (_controller == null || _activeUid != user.uid) {
      _bindToUser(user);
    }
  }

  Future<void> refresh() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty || _refreshInFlight) {
      return;
    }
    _refreshInFlight = true;
    try {
      if (_usingCloudFunctionFallback) {
        await _loadViaCloudFunction(uid);
        return;
      }
      await _primeFromFirestoreGet(uid);
    } catch (_) {
      await _activateCloudFunctionFallback(uid);
    } finally {
      _refreshInFlight = false;
    }
  }

  void _bindToUser(User? user) {
    final uid = (user?.uid ?? '').trim();
    if (uid.isEmpty) {
      _tearDown();
      return;
    }

    if (_activeUid == uid && _subscription != null && _controller != null) {
      return;
    }

    _tearDown();
    _activeUid = uid;
    _usingCloudFunctionFallback = false;
    _controller = StreamController<RiderOrdersQuerySnapshot>.broadcast();

    unawaited(_startFirestoreListener(uid));
  }

  Future<void> _startFirestoreListener(String uid) async {
    try {
      await _primeFromFirestoreGet(uid);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[RiderOrdersService] prime failed: $error');
      }
      await _activateCloudFunctionFallback(uid, error: error, stackTrace: stackTrace);
      return;
    }

    _subscription = FirebaseFirestore.instance
        .collection('orders')
        .where('driverId', isEqualTo: uid)
        .snapshots()
        .listen(
          (snapshot) {
            _publishFirestoreSnapshot(snapshot);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (kDebugMode) {
              debugPrint('[RiderOrdersService] listener error: $error');
            }
            unawaited(
              _activateCloudFunctionFallback(
                uid,
                error: error,
                stackTrace: stackTrace,
              ),
            );
          },
        );
  }

  Future<void> _primeFromFirestoreGet(String uid) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('orders')
        .where('driverId', isEqualTo: uid)
        .get()
        .timeout(const Duration(seconds: 15));
    _publishFirestoreSnapshot(snapshot);
  }

  void _publishFirestoreSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final docs = snapshot.docs
        .map(
          (doc) => RiderOrderDocument(
            id: doc.id,
            data: doc.data(),
          ),
        )
        .toList(growable: false);

    _emit(RiderOrdersQuerySnapshot(docs: docs));
  }

  Future<void> _activateCloudFunctionFallback(
    String uid, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    if (_usingCloudFunctionFallback) {
      return;
    }
    _usingCloudFunctionFallback = true;
    await _subscription?.cancel();
    _subscription = null;

    try {
      await _loadViaCloudFunction(uid);
    } catch (cfError, cfStack) {
      final controller = _controller;
      if (controller != null && !controller.isClosed) {
        controller.addError(cfError, cfStack);
      }
      return;
    }

    _cloudPollTimer?.cancel();
    _cloudPollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_loadViaCloudFunction(uid));
    });

    if (error != null) {
      final controller = _controller;
      if (controller != null && !controller.isClosed && kDebugMode) {
        debugPrint('[RiderOrdersService] switched to CF fallback after: $error');
      }
    }
  }

  Future<void> _loadViaCloudFunction(String uid) async {
    final result = await GuardedFunctions.call('listRiderOrders');

    final payload = result.data is Map
        ? Map<String, dynamic>.from(result.data as Map)
        : const <String, dynamic>{};
    final rawOrders = payload['orders'];
    final docs = <RiderOrderDocument>[];

    if (rawOrders is List) {
      for (final entry in rawOrders) {
        if (entry is! Map) {
          continue;
        }
        final map = Map<String, dynamic>.from(entry);
        final id = map.remove('id')?.toString() ?? '';
        final nestedData = map['data'];
        final data = nestedData is Map
            ? Map<String, dynamic>.from(nestedData)
            : Map<String, dynamic>.from(map);
        if (id.isEmpty) {
          continue;
        }
        docs.add(RiderOrderDocument(id: id, data: data));
      }
    }

    _emit(
      RiderOrdersQuerySnapshot(
        docs: docs,
        fromCloudFunction: true,
      ),
    );
  }

  void _emit(RiderOrdersQuerySnapshot snapshot) {
    _lastSnapshot = snapshot;
    final controller = _controller;
    if (controller != null && !controller.isClosed) {
      controller.add(snapshot);
    }
  }

  void _tearDown() {
    _subscription?.cancel();
    _subscription = null;
    _cloudPollTimer?.cancel();
    _cloudPollTimer = null;
    _controller?.close();
    _controller = null;
    _activeUid = null;
    _lastSnapshot = RiderOrdersQuerySnapshot.empty;
    _usingCloudFunctionFallback = false;
  }

  void dispose() {
    _tearDown();
  }
}
