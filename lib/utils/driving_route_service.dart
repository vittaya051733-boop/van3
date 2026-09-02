import 'guarded_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class DrivingRouteResult {
  const DrivingRouteResult({
    required this.points,
    required this.durationSeconds,
  });

  final List<LatLng> points;
  final int durationSeconds;
}

class DrivingRouteService {
  DrivingRouteService._();

  static const Duration _requestTimeout = Duration(seconds: 15);

  static Future<DrivingRouteResult?> fetchDrivingRoute({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) {
      return null;
    }

    try {
      final result = await GuardedFunctions.call(
        'computeRouteMetrics',
        parameters: <String, Object>{
          'originLatitude': originLat,
          'originLongitude': originLng,
          'destinationLatitude': destinationLat,
          'destinationLongitude': destinationLng,
        },
      ).timeout(_requestTimeout);

      final payload = result.data;
      if (payload is! Map) {
        return null;
      }

      final durationSeconds = payload['durationSeconds'];
      final encodedPolyline = payload['encodedPolyline'];
      if (durationSeconds is! num ||
          encodedPolyline is! String ||
          encodedPolyline.isEmpty) {
        return null;
      }

      final points = decodeEncodedPolyline(encodedPolyline);
      if (points.length < 2) {
        return null;
      }

      return DrivingRouteResult(
        points: points,
        durationSeconds: durationSeconds.round(),
      );
    } catch (_) {
      return null;
    }
  }
}

List<LatLng> decodeEncodedPolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0;
  var lat = 0;
  var lng = 0;

  while (index < encoded.length) {
    var shift = 0;
    var result = 0;
    int byte;

    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);

    final deltaLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lat += deltaLat;

    shift = 0;
    result = 0;

    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);

    final deltaLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lng += deltaLng;

    points.add(LatLng(lat / 1e5, lng / 1e5));
  }

  return points;
}
