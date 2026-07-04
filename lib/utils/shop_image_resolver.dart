import 'package:cloud_firestore/cloud_firestore.dart';

class ShopImageResolver {
  ShopImageResolver._();

  static String? readFromOrder(Map<String, dynamic> data) {
    final direct = _readTrimmed(
      data['shopImageUrl'],
      data['imageUrl'],
      data['photoUrl'],
    );
    if (direct != null) {
      return direct;
    }

    final shopSnapshot = data['shopSnapshot'];
    if (shopSnapshot is Map) {
      final fromSnapshot = _readTrimmed(
        shopSnapshot['shopImageUrl'],
        shopSnapshot['photoUrl'],
        shopSnapshot['imageUrl'],
      );
      if (fromSnapshot != null) {
        return fromSnapshot;
      }
    }

    final rawProducts = data['products'];
    if (rawProducts is List) {
      for (final item in rawProducts) {
        if (item is! Map) {
          continue;
        }
        final fromProduct = _readTrimmed(
          item['shopImageUrl'],
          item['storeImageUrl'],
          item['shopPhotoUrl'],
          item['merchantImageUrl'],
          item['businessImageUrl'],
        );
        if (fromProduct != null) {
          return fromProduct;
        }
      }
    }

    return null;
  }

  static Future<String?> resolveForOrder(
    Map<String, dynamic> data, {
    String? shopOwnerUid,
  }) async {
    final direct = readFromOrder(data);
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final uid = (shopOwnerUid ?? data['shopOwnerId'] ?? data['shopId'])
        ?.toString()
        .trim();
    if (uid == null || uid.isEmpty) {
      return null;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('public_shops')
          .doc(uid)
          .get();
      if (!doc.exists) {
        return null;
      }
      return readFromPublicShop(doc.data());
    } catch (_) {
      return null;
    }
  }

  static String? readFromPublicShop(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }
    return _readTrimmed(
      data['shopImageUrl'],
      data['photoUrl'],
      data['imageUrl'],
      data['logoUrl'],
      data['storeImageUrl'],
    );
  }

  static String? readProductImageUrl(
    Map<dynamic, dynamic> item, {
    String? fallbackShopImageUrl,
  }) {
    final imageUrls = item['imageUrls'];
    if (imageUrls is List) {
      for (final entry in imageUrls) {
        final url = entry?.toString().trim();
        if (url != null && url.isNotEmpty) {
          return url;
        }
      }
    }

    final thumbnailUrls = item['thumbnailUrls'];
    if (thumbnailUrls is List) {
      for (final entry in thumbnailUrls) {
        final url = entry?.toString().trim();
        if (url != null && url.isNotEmpty) {
          return url;
        }
      }
    }

    final direct = _readTrimmed(
      item['imageUrl'],
      item['photoUrl'],
      item['image'],
      item['productImage'],
    );
    if (direct != null) {
      return direct;
    }

    final fallback = fallbackShopImageUrl?.trim();
    return fallback == null || fallback.isEmpty ? null : fallback;
  }

  static String? _readTrimmed(
    Object? first, [
    Object? second,
    Object? third,
    Object? fourth,
    Object? fifth,
  ]) {
    for (final candidate in [first, second, third, fourth, fifth]) {
      final value = candidate?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }
}
