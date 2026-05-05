import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../call_screen.dart';
import '../models/user_profile.dart';
import '../services/notification_service.dart';

class OrderCallLauncher {
  const OrderCallLauncher._();

  static const List<String> _shopProfileCollections = <String>[
    'users',
    'customer_users',
    'market_registrations',
    'shop_registrations',
    'restaurant_registrations',
    'pharmacy_registrations',
    'other_registrations',
  ];

  static Future<void> startVoiceCall({
    required BuildContext context,
    required String peerUid,
    required String peerLabel,
    required Map<String, dynamic> orderData,
    String? phoneNumber,
    String? photoUrl,
  }) async {
    final trimmedPeerUid = peerUid.trim().isNotEmpty
        ? peerUid.trim()
        : _readShopOwnerUid(orderData)?.trim() ?? '';
    if (trimmedPeerUid.isEmpty) {
      _showSnack(context, 'ไม่พบบัญชีปลายทางสำหรับเริ่มการโทร');
      return;
    }

    try {
      final caller = await _buildCurrentUserProfile();
      if (caller.uid == trimmedPeerUid) {
        throw Exception('ไม่สามารถเริ่มการโทรหาบัญชีตัวเองได้');
      }

      final callee = await _buildCalleeProfile(
        uid: trimmedPeerUid,
        fallbackLabel: peerLabel,
        fallbackPhone: phoneNumber,
        fallbackPhotoUrl: photoUrl,
        orderData: orderData,
      );

      final callData = await NotificationService().initiateCall(
        caller: caller,
        callee: callee,
        isVideo: false,
      );

      if (!context.mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CallScreen(
            channelName:
                (callData['channelId'] as String?) ??
                _fallbackChannelId(caller.uid, callee.uid),
            isVideo: false,
            targetProfile: callee,
            appIdOverride: callData['appId'] as String?,
            tokenOverride: callData['token'] as String?,
            isIncoming: false,
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showSnack(context, 'เริ่มการโทรไม่สำเร็จ: $error');
    }
  }

  static String readCustomerLabel(Map<String, dynamic> orderData) {
    final candidates = <String?>[
      orderData['customerName'] as String?,
      orderData['buyerName'] as String?,
      orderData['userName'] as String?,
      _readStringFromMap(orderData['customerSnapshot'], 'displayName'),
      _readStringFromMap(orderData['customerSnapshot'], 'name'),
      _readStringFromMap(orderData['customerSnapshot'], 'customerName'),
    ];
    for (final value in candidates) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return 'ลูกค้า';
  }

  static String readShopLabel(Map<String, dynamic> orderData) {
    final candidates = <String?>[
      orderData['shopName'] as String?,
      _readStringFromMap(orderData['shopSnapshot'], 'shopName'),
      _readStringFromMap(orderData['shopSnapshot'], 'displayName'),
      _readStringFromMap(orderData['shopSnapshot'], 'name'),
    ];
    for (final value in candidates) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return 'ร้านค้า';
  }

  static String? readCustomerPhotoUrl(Map<String, dynamic> orderData) {
    return _firstNonEmpty(<String?>[
      orderData['customerPhotoUrl'] as String?,
      orderData['customerImageUrl'] as String?,
      _readStringFromMap(orderData['customerSnapshot'], 'photoUrl'),
      _readStringFromMap(orderData['customerSnapshot'], 'imageUrl'),
      _readStringFromMap(orderData['customerSnapshot'], 'avatarUrl'),
    ]);
  }

  static String? readShopPhotoUrl(Map<String, dynamic> orderData) {
    return _firstNonEmpty(<String?>[
      orderData['shopImageUrl'] as String?,
      orderData['shopPhotoUrl'] as String?,
      _readStringFromMap(orderData['shopSnapshot'], 'shopImageUrl'),
      _readStringFromMap(orderData['shopSnapshot'], 'photoUrl'),
      _readStringFromMap(orderData['shopSnapshot'], 'imageUrl'),
    ]);
  }

  static Future<UserProfile> _buildCalleeProfile({
    required String uid,
    required String fallbackLabel,
    required Map<String, dynamic> orderData,
    String? fallbackPhone,
    String? fallbackPhotoUrl,
  }) async {
    for (final collection in _shopProfileCollections) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection(collection)
            .doc(uid)
            .get();
        if (!doc.exists) continue;
        final data = doc.data();
        if (data == null) continue;
        return UserProfile.fromMap(uid, <String, dynamic>{
          ...data,
          if ((data['phoneNumber'] ?? data['phone']) == null &&
              fallbackPhone?.trim().isNotEmpty == true)
            'phoneNumber': fallbackPhone!.trim(),
          if ((data['photoUrl'] ?? data['imageUrl'] ?? data['shopImageUrl']) ==
                  null &&
              fallbackPhotoUrl?.trim().isNotEmpty == true)
            'photoUrl': fallbackPhotoUrl!.trim(),
        });
      } catch (_) {
        // Try the next profile collection.
      }
    }

    return UserProfile(
      uid: uid,
      displayName: _sanitizeLabel(fallbackLabel, fallback: 'ผู้ติดต่อ'),
      phoneNumber: fallbackPhone,
      photoUrl: fallbackPhotoUrl ?? readShopPhotoUrl(orderData),
    );
  }

  static Future<UserProfile> _buildCurrentUserProfile() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw Exception('ไม่พบผู้ใช้ปัจจุบัน');
    }

    try {
      final riderDoc = await FirebaseFirestore.instance
          .collection('riders')
          .doc(currentUser.uid)
          .get();
      if (riderDoc.exists) {
        return UserProfile.fromMap(currentUser.uid, riderDoc.data());
      }
    } catch (_) {
      // Fall back to Firebase Auth profile when Firestore lookup fails.
    }

    return UserProfile(
      uid: currentUser.uid,
      displayName: _sanitizeLabel(currentUser.displayName, fallback: 'ไรเดอร์'),
      phoneNumber: currentUser.phoneNumber,
      photoUrl: currentUser.photoURL,
    );
  }

  static String _fallbackChannelId(String uidA, String uidB) {
    final sorted = <String>[uidA, uidB]..sort();
    return 'call_${sorted.join('_')}';
  }

  static void _showSnack(BuildContext context, String message) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _sanitizeLabel(String? value, {required String fallback}) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? fallback : trimmed;
  }

  static String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }

  static String? _readStringFromMap(Object? source, String key) {
    if (source is! Map) {
      return null;
    }
    final value = source[key];
    return value is String ? value : value?.toString();
  }

  static String? _readShopOwnerUid(Map<String, dynamic> orderData) {
    return _firstNonEmpty(<String?>[
      orderData['shopOwnerId'] as String?,
      orderData['shopId'] as String?,
      orderData['merchantId'] as String?,
      orderData['sellerId'] as String?,
      _readStringFromMap(orderData['shopSnapshot'], 'ownerId'),
      _readStringFromMap(orderData['shopSnapshot'], 'shopOwnerId'),
      _readStringFromMap(orderData['shopSnapshot'], 'uid'),
    ]);
  }
}
