import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'l10n/l10n.dart';
import 'rider_registration_screen.dart';
import 'services/rider_auth_sign_out.dart';
import 'services/rider_registration_service.dart';

class RiderOnboardingGate extends StatefulWidget {
  const RiderOnboardingGate({super.key, required this.child});

  final Widget child;

  @override
  State<RiderOnboardingGate> createState() => _RiderOnboardingGateState();
}

class _RiderOnboardingGateState extends State<RiderOnboardingGate> {
  static const Duration _loadTimeout = Duration(seconds: 15);

  StreamSubscription<RiderAccessStatus>? _statusSubscription;
  Timer? _loadTimeoutTimer;
  bool _loading = true;
  RiderAccessStatus? _status;
  String? _rejectReason;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _listenForAccessChanges();
  }

  @override
  void dispose() {
    _loadTimeoutTimer?.cancel();
    _statusSubscription?.cancel();
    super.dispose();
  }

  void _startLoadTimeout() {
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = Timer(_loadTimeout, () {
      if (!mounted || !_loading) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = L10n.riderStatusLoadTimeout;
      });
    });
  }

  void _listenForAccessChanges() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _loading = false;
        _status = RiderAccessStatus.needsRegistration;
      });
      return;
    }

    _statusSubscription?.cancel();
    setState(() {
      _loading = true;
      _loadError = null;
    });
    _startLoadTimeout();
    _statusSubscription =
        RiderRegistrationService.watchAccessStatus(uid).listen(
      (status) {
        if (!mounted) {
          return;
        }
        _loadTimeoutTimer?.cancel();
        setState(() {
          _loading = false;
          _status = status;
          _loadError = null;
          if (status != RiderAccessStatus.rejected) {
            _rejectReason = null;
          }
        });
        if (status == RiderAccessStatus.rejected) {
          _loadRejectReason(uid);
        }
      },
      onError: (error) {
        if (!mounted) {
          return;
        }
        _loadTimeoutTimer?.cancel();
        setState(() {
          _loading = false;
          _loadError = _formatLoadError(error);
        });
      },
    );
  }

  String _formatLoadError(Object error) {
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return L10n.riderStatusPermissionDenied;
      }
      return L10n.riderStatusLoadFailed(error.code);
    }
    return error.toString();
  }

  Future<void> _signOut() async {
    await RiderAuthSignOut.signOut();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (_) => false);
  }

  Future<void> _loadRejectReason(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(RiderRegistrationService.collection)
          .doc(uid)
          .get();
      final reason = doc.data()?['reviewNote']?.toString();
      if (!mounted) {
        return;
      }
      setState(() => _rejectReason = reason);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 48),
                const SizedBox(height: 16),
                Text(
                  L10n.riderStatusLoadFailedTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _loadError = null;
                    });
                    _listenForAccessChanges();
                  },
                  child: Text(L10n.retry),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _signOut,
                  child: Text(L10n.signOut),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return switch (_status) {
      RiderAccessStatus.approved => widget.child,
      RiderAccessStatus.pending => const RiderRegistrationPendingScreen(),
      RiderAccessStatus.rejected => RiderRegistrationScreen(
          rejectedReason: _rejectReason,
        ),
      RiderAccessStatus.needsRegistration => const RiderRegistrationScreen(),
      null => const RiderRegistrationScreen(),
    };
  }
}
