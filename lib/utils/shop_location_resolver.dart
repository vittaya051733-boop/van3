import 'package:cloud_firestore/cloud_firestore.dart';

class ShopLocationResolver {
  ShopLocationResolver._();

  static Map<String, double>? readFromOrder(Map<String, dynamic> data) {
    final direct = readCoordinatesFromRecord(data);
    if (direct != null) {
      return direct;
    }

    final shopSnapshot = data['shopSnapshot'];
    if (shopSnapshot is Map) {
      final fromSnapshot = readCoordinatesFromRecord(
        Map<String, dynamic>.from(shopSnapshot),
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
        final fromProduct = readCoordinatesFromRecord(
          Map<String, dynamic>.from(item),
        );
        if (fromProduct != null) {
          return fromProduct;
        }
      }
    }

    return null;
  }

  static Future<Map<String, double>?> resolveForOrder(
    Map<String, dynamic> data, {
    String? shopOwnerUid,
  }) async {
    final direct = readFromOrder(data);
    if (direct != null) {
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
      return readCoordinatesFromRecord(doc.data());
    } catch (_) {
      return null;
    }
  }

  static Map<String, double>? readCoordinatesFromRecord(
    Map<String, dynamic>? data,
  ) {
    if (data == null || data.isEmpty) {
      return null;
    }

    final directLat =
        _toDouble(data['shopLatitude']) ??
        _toDouble(data['latitude']) ??
        _toDouble(data['lat']);
    final directLng =
        _toDouble(data['shopLongitude']) ??
        _toDouble(data['longitude']) ??
        _toDouble(data['lng']) ??
        _toDouble(data['lon']) ??
        _toDouble(data['long']);
    if (_isValidCoordinatePair(directLat, directLng)) {
      return <String, double>{'lat': directLat!, 'lng': directLng!};
    }

    for (final locationKey in <String>[
      'shopLocation',
      'location',
      'geoPoint',
      'coordinates',
    ]) {
      final location = data[locationKey];
      final resolved = _readCoordinatesFromDynamic(location);
      if (resolved != null) {
        return resolved;
      }
    }

    return null;
  }

  static Map<String, double>? _readCoordinatesFromDynamic(Object? location) {
    if (location is GeoPoint) {
      return _validatePair(location.latitude, location.longitude);
    }
    if (location is Map) {
      final lat =
          _toDouble(location['latitude']) ??
          _toDouble(location['lat']);
      final lng =
          _toDouble(location['longitude']) ??
          _toDouble(location['lng']) ??
          _toDouble(location['lon']) ??
          _toDouble(location['long']);
      return _validatePair(lat, lng);
    }
    return null;
  }

  static Map<String, double>? _validatePair(double? lat, double? lng) {
    if (!_isValidCoordinatePair(lat, lng)) {
      return null;
    }
    return <String, double>{'lat': lat!, 'lng': lng!};
  }

  static bool _isValidCoordinatePair(double? lat, double? lng) {
    if (lat == null || lng == null) {
      return false;
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return false;
    }
    if (lat == 0 && lng == 0) {
      return false;
    }
    return true;
  }

  static double? _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim());
    }
    return null;
  }
}
