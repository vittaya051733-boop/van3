import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/contact_phone_resolver.dart';
import 'chat_warmup_cache.dart';

class ChatWarmupService {
  ChatWarmupService._();

  static const int defaultMessageLimit = 50;
  static final Set<String> _prefetchedRooms = <String>{};

  static const List<String> _registrationCollections = <String>[
    'market_registrations',
    'shop_registrations',
    'restaurant_registrations',
    'pharmacy_registrations',
    'other_registrations',
  ];

  static String chatIdFor(String uidA, String uidB) {
    final sorted = <String>[uidA, uidB]..sort();
    return 'chat_${sorted.join('_')}';
  }

  static void prefetchRoom({
    required String myUid,
    required String peerUid,
    int messageLimit = defaultMessageLimit,
  }) {
    if (myUid.trim().isEmpty || peerUid.trim().isEmpty) {
      return;
    }

    final roomKey = '$myUid:$peerUid';
    if (_prefetchedRooms.contains(roomKey)) {
      return;
    }
    _prefetchedRooms.add(roomKey);

    final chatId = chatIdFor(myUid, peerUid);
    unawaited(_prefetchMessages(chatId, limit: messageLimit));
    unawaited(_prefetchPeerPhone(peerUid));
  }

  static Future<List<CachedRiderChatMessage>> prefetchMessages(
    String chatId, {
    int limit = defaultMessageLimit,
  }) {
    return _prefetchMessages(chatId, limit: limit);
  }

  static Future<List<CachedRiderChatMessage>> _prefetchMessages(
    String chatId, {
    required int limit,
  }) async {
    final cached = ChatWarmupCache.instance.peekMessages(chatId);
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      final messages = snapshot.docs
          .map(
            (doc) => CachedRiderChatMessage(
              id: doc.id,
              data: Map<String, dynamic>.from(doc.data()),
            ),
          )
          .toList(growable: false);

      if (messages.isNotEmpty) {
        ChatWarmupCache.instance.putMessages(chatId, messages);
      }
      return messages;
    } catch (_) {
      return const <CachedRiderChatMessage>[];
    }
  }

  static Future<void> _prefetchPeerPhone(String peerUid) async {
    final cached = ChatWarmupCache.instance.peekPhone(peerUid);
    if (cached != null) {
      return;
    }

    final phone = await _resolvePeerPhone(peerUid);
    if (phone != null) {
      ChatWarmupCache.instance.cachePhone(peerUid, phone);
    }
  }

  static Future<String?> resolvePeerPhone(String peerUid) async {
    final cached = ChatWarmupCache.instance.peekPhone(peerUid);
    if (cached != null) {
      return cached;
    }

    final phone = await _resolvePeerPhone(peerUid);
    if (phone != null) {
      ChatWarmupCache.instance.cachePhone(peerUid, phone);
    }
    return phone;
  }

  static Future<String?> _resolvePeerPhone(String peerUid) async {
    final fromRiders = await _readPhoneFromDoc(
      collection: 'riders',
      docId: peerUid,
    );
    if (fromRiders != null) {
      return fromRiders;
    }

    for (final collection in <String>[
      'customer_users',
      'users',
      ..._registrationCollections,
    ]) {
      final phone = await _readPhoneFromDoc(
        collection: collection,
        docId: peerUid,
      );
      if (phone != null) {
        return phone;
      }
    }

    return null;
  }

  static Future<String?> _readPhoneFromDoc({
    required String collection,
    required String docId,
  }) async {
    try {
      final doc =
          await FirebaseFirestore.instance.collection(collection).doc(docId).get();
      if (!doc.exists) {
        return null;
      }

      final data = doc.data();
      if (data == null) {
        return null;
      }

      return ContactPhoneResolver.readPhoneFromMap(data);
    } catch (_) {
      return null;
    }
  }

  static Stream<List<CachedRiderChatMessage>> watchMessages(
    String chatId, {
    int limit = defaultMessageLimit,
  }) {
    final ref = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(limit);

    return Stream<List<CachedRiderChatMessage>>.multi((controller) {
      final cached = ChatWarmupCache.instance.peekMessages(chatId);
      if (cached != null && cached.isNotEmpty) {
        controller.add(cached);
      }

      late StreamSubscription<QuerySnapshot<Map<String, dynamic>>> subscription;
      subscription = ref.snapshots().listen(
        (snapshot) {
          final messages = snapshot.docs
              .map(
                (doc) => CachedRiderChatMessage(
                  id: doc.id,
                  data: Map<String, dynamic>.from(doc.data()),
                ),
              )
              .toList(growable: false);
          if (messages.isNotEmpty) {
            ChatWarmupCache.instance.putMessages(chatId, messages);
          }
          controller.add(messages);
        },
        onError: controller.addError,
        onDone: controller.close,
        cancelOnError: false,
      );

      controller.onCancel = () => subscription.cancel();
    });
  }

  static void prefetchVisibleOrderChats({
    required Iterable<String> peerUids,
    int maxRooms = 6,
  }) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || myUid.trim().isEmpty) {
      return;
    }

    for (final peerUid in peerUids.take(maxRooms)) {
      prefetchRoom(myUid: myUid, peerUid: peerUid);
    }
  }
}
