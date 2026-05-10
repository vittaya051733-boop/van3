import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'phone_login_helper.dart';

class ContactPhoneResolver {
  ContactPhoneResolver._();

  static const List<String> defaultRegistrationCollections = <String>[
    'market_registrations',
    'shop_registrations',
    'restaurant_registrations',
    'pharmacy_registrations',
    'other_registrations',
  ];

  static const List<String> _customerCollections = <String>[
    'customer_users',
    'users',
  ];

  static const List<String> _shopProfileCollections = <String>[
    'users',
  ];

  static Future<String?> resolveCustomerPhone({
    required Map<String, dynamic> orderData,
    String? customerUid,
  }) async {
    final direct = readCustomerPhoneFromOrder(orderData);
    if (direct != null) {
      return direct;
    }

    final uid = customerUid?.trim();
    if (uid == null || uid.isEmpty) {
      return null;
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid != uid) {
      // Rider app normally cannot read other users' profiles due to Firestore rules.
      return null;
    }

    for (final collection in _customerCollections) {
      final phone = await _readPhoneFromDoc(collection: collection, docId: uid);
      if (phone != null) {
        return phone;
      }
    }

    return null;
  }

  static Future<String?> resolveShopPhone({
    required Map<String, dynamic> orderData,
    String? ownerUid,
    List<String> registrationCollections = defaultRegistrationCollections,
  }) async {
    final direct = readShopPhoneFromOrder(orderData);
    if (direct != null) {
      return direct;
    }

    final uid = ownerUid?.trim();
    if (uid == null || uid.isEmpty) {
      return null;
    }

    for (final collection in registrationCollections) {
      final phone = await _readPhoneFromDoc(collection: collection, docId: uid);
      if (phone != null) {
        return phone;
      }
    }

    for (final collection in _shopProfileCollections) {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid == null || currentUid != uid) {
        // Avoid hitting denied collections (e.g. users/) when not self.
        break;
      }
      final phone = await _readPhoneFromDoc(collection: collection, docId: uid);
      if (phone != null) {
        return phone;
      }
    }

    return null;
  }

  static String normalizeDialable(String phone) {
    return PhoneLoginHelper.normalize(phone.trim());
  }

  static String? readCustomerPhoneFromOrder(Map<String, dynamic> orderData) {
    final direct = _pickFirst(<String?>[
      orderData['customerPhone'] as String?,
      orderData['customerPhoneNumber'] as String?,
      orderData['buyerPhone'] as String?,
      orderData['phoneNumber'] as String?,
      orderData['phone'] as String?,
      orderData['telephone'] as String?,
      orderData['tel'] as String?,
      orderData['mobile'] as String?,
      orderData['mobileNumber'] as String?,
      orderData['contactPhone'] as String?,
      orderData['contactNumber'] as String?,
    ]);
    if (direct != null) {
      return direct;
    }

    return readPhoneFromMap(orderData['customerSnapshot'] as Map?);
  }

  static String? readShopPhoneFromOrder(Map<String, dynamic> orderData) {
    final direct = _pickFirst(<String?>[
      orderData['shopPhone'] as String?,
      orderData['merchantPhone'] as String?,
      orderData['sellerPhone'] as String?,
      orderData['ownerPhone'] as String?,
      orderData['contactPhone'] as String?,
      orderData['contactNumber'] as String?,
      orderData['phoneNumber'] as String?,
      orderData['phone'] as String?,
      orderData['telephone'] as String?,
      orderData['tel'] as String?,
      orderData['mobile'] as String?,
      orderData['mobileNumber'] as String?,
    ]);
    if (direct != null) {
      return direct;
    }

    return readPhoneFromMap(orderData['shopSnapshot'] as Map?);
  }

  static String? readPhoneFromMap(Map? raw) {
    if (raw == null) {
      return null;
    }

    return _pickFirst(<String?>[
      raw['phone'] as String?,
      raw['phoneNumber'] as String?,
      raw['contactPhone'] as String?,
      raw['contactNumber'] as String?,
      raw['mobile'] as String?,
      raw['mobileNumber'] as String?,
      raw['telephone'] as String?,
      raw['tel'] as String?,
      raw['linePhone'] as String?,
      raw['shopPhone'] as String?,
      raw['customerPhone'] as String?,
      raw['ownerPhone'] as String?,
    ]);
  }

  static Future<String?> _readPhoneFromDoc({
    required String collection,
    required String docId,
  }) async {
    try {
      final doc = await FirebaseFirestore.instance.collection(collection).doc(docId).get();
      if (!doc.exists) {
        return null;
      }
      return readPhoneFromMap(doc.data());
    } catch (_) {
      return null;
    }
  }

  static String? _pickFirst(List<String?> candidates) {
    for (final candidate in candidates) {
      final value = candidate?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }
}