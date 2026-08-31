import 'package:flutter/material.dart';

import 'l10n/l10n.dart';
import 'services/notification_service.dart';
import 'services/privacy_consent_service.dart';

class PrivacyLaunchGate extends StatefulWidget {
  const PrivacyLaunchGate({
    super.key,
    required this.child,
    required this.app,
  });

  final Widget child;
  final String app;

  @override
  State<PrivacyLaunchGate> createState() => _PrivacyLaunchGateState();
}

class _PrivacyLaunchGateState extends State<PrivacyLaunchGate> {
  bool _ready = false;
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runGate());
  }

  Future<void> _runGate() async {
    final accepted = await PrivacyConsentService.instance.ensureConsent(
      context,
      app: widget.app,
      source: 'launch_gate',
    );
    if (!mounted) return;
    if (!accepted) {
      setState(() => _blocked = true);
      return;
    }

    final local = await PrivacyConsentService.instance.loadLocalSnapshot();
    if (local?.pushOptIn == true) {
      await NotificationService().enablePushNotifications();
    }

    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    if (_blocked) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.policy_outlined, size: 48),
                const SizedBox(height: 16),
                Text(
                  L10n.privacyMustAcceptGate,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _runGate,
                  child: Text(L10n.privacyReviewTermsAgain),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
