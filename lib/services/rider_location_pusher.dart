import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

/// On-demand rider location updater. Pushes the current GPS position to
/// `riders/{uid}` once per call. Use this at order action points (accept,
/// pickup scan, start delivering, deliver) instead of streaming.
class RiderLocationPusher {
  RiderLocationPusher._();

  static Future<void> pushOnce({
    String? uid,
    required String source,
    bool? forceOnlineReady,
    bool? forcePassengerReady,
  }) async {
    final resolvedUid = uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (resolvedUid == null || resolvedUid.isEmpty) {
      return;
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        ).timeout(const Duration(seconds: 8));
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        return;
      }

      final capturedAt = position.timestamp.toUtc();
      final ageSeconds = DateTime.now().toUtc().difference(capturedAt).inSeconds;

      final payload = <String, dynamic>{
        'uid': resolvedUid,
        'currentLocation': GeoPoint(position.latitude, position.longitude),
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'speed': position.speed,
        'heading': position.heading,
        'locationSource': source,
        'locationAgeSeconds': ageSeconds < 0 ? 0 : ageSeconds,
        'locationUpdatedAt': FieldValue.serverTimestamp(),
      };
      if (forceOnlineReady != null) {
        payload['onlineReady'] = forceOnlineReady;
      }
      if (forcePassengerReady != null) {
        payload['passengerReady'] = forcePassengerReady;
      }

      await FirebaseFirestore.instance
          .collection('riders')
          .doc(resolvedUid)
          .set(payload, SetOptions(merge: true));
    } catch (_) {
      // Ignore — this is a best-effort on-demand push.
    }
  }
}
