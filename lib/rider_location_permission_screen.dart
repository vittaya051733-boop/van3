import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'l10n/l10n.dart';

class RiderLocationPermissionScreen extends StatefulWidget {
  const RiderLocationPermissionScreen({super.key});

  @override
  State<RiderLocationPermissionScreen> createState() =>
      _RiderLocationPermissionScreenState();
}

class _RiderLocationPermissionScreenState
    extends State<RiderLocationPermissionScreen> {
  bool _isLoading = false;
  String? _error;

  Future<void> _requestAndContinue() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _error = L10n.enableGpsFirst;
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        setState(() {
          _error = L10n.locationPermissionDenied;
        });
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _error = L10n.locationPermissionDeniedForever;
        });
        return;
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  Future<void> _openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.locationPermissionTitle),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.location_on_rounded, size: 46, color: Color(0xFFFF7A00)),
            const SizedBox(height: 12),
            Text(
              L10n.locationPermissionBeforeReady,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              L10n.locationPermissionBody,
              style: const TextStyle(fontSize: 15, color: Color(0xFF4B5563)),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E8),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFFC89A)),
              ),
              child: Text(
                L10n.locationEmulatorHint,
                style: const TextStyle(fontSize: 13, color: Color(0xFF9A3412)),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: const TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.w600),
              ),
            ],
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _openLocationSettings,
                    child: Text(L10n.enableGps),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _openAppSettings,
                    child: Text(L10n.openAppSettings),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _requestAndContinue,
                icon: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline_rounded),
                label: Text(L10n.allowAndContinue),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
