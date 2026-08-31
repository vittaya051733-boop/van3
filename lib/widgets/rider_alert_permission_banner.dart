import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/rider_alert_permissions.dart';

/// Banner prompting riders to enable full-screen and overlay permissions for order alerts.
class RiderAlertPermissionBanner extends StatefulWidget {
  const RiderAlertPermissionBanner({super.key});

  @override
  State<RiderAlertPermissionBanner> createState() =>
      _RiderAlertPermissionBannerState();
}

class _RiderAlertPermissionBannerState extends State<RiderAlertPermissionBanner> {
  RiderAlertPermissionStatus? _status;
  bool _checking = true;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      _checking = false;
      return;
    }
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final status = await RiderAlertPermissions.checkAll();
    if (!mounted) {
      return;
    }
    setState(() {
      _status = status;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking || _dismissed || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const SizedBox.shrink();
    }

    final status = _status;
    if (status == null || status.isFullyReady) {
      return const SizedBox.shrink();
    }

    final messages = <String>[];
    if (status.needsFullScreenIntent) {
      messages.add(L10n.alertFullScreenNeeded);
    }
    if (status.needsOverlay) {
      messages.add(L10n.alertOverlayNeeded);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFEA580C)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      L10n.orderAlertSettingsTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF9A3412),
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _dismissed = true),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                messages.join('\n'),
                style: const TextStyle(
                  color: Color(0xFF7C2D12),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  if (status.needsFullScreenIntent)
                    OutlinedButton(
                      onPressed: () async {
                        await RiderAlertPermissions.openFullScreenIntentSettings();
                        await _refresh();
                      },
                      child: Text(L10n.alertEnableFullScreen),
                    ),
                  if (status.needsOverlay)
                    OutlinedButton(
                      onPressed: () async {
                        await RiderAlertPermissions.openOverlaySettings();
                        await _refresh();
                      },
                      child: Text(L10n.alertEnableOverlay),
                    ),
                  TextButton(
                    onPressed: _refresh,
                    child: Text(L10n.alertRecheck),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
