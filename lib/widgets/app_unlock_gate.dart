import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/app_unlock_session.dart';
import '../services/biometric_auth_service.dart';
import '../services/security_pin_service.dart';
import '../utils/app_colors.dart';
import 'security_pin_keypad.dart';

/// Blocks app content until biometric or security PIN unlock.
/// Also forces PIN setup for signed-in users who have not set one yet.
class AppUnlockGate extends StatefulWidget {
  const AppUnlockGate({
    super.key,
    required this.child,
    this.logoAsset,
  });

  final Widget child;
  final String? logoAsset;

  @override
  State<AppUnlockGate> createState() => _AppUnlockGateState();
}

class _AppUnlockGateState extends State<AppUnlockGate> with WidgetsBindingObserver {
  final _biometricAuthService = BiometricAuthService();
  final _unlockKeypadKey = GlobalKey<SecurityPinKeypadState>();
  final _setupKeypadKey = GlobalKey<SecurityPinKeypadState>();

  bool _loading = true;
  bool _needsSetup = false;
  bool _biometricEnabled = false;
  bool _submitting = false;
  String? _errorText;
  int _setupStep = 0;
  String _setupPinDraft = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      AppUnlockSession.lock();
    }
  }

  Future<void> _refreshState() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _loading = false;
        _needsSetup = false;
      });
      return;
    }

    final hasPin = await SecurityPinService.instance.hasPin(uid);
    final bioAvailable = !kIsWeb && await _biometricAuthService.canUseBiometrics();
    final bioEnabled = await SecurityPinService.instance.isBiometricUnlockEnabled();

    if (!mounted) {
      return;
    }

    setState(() {
      _loading = false;
      _needsSetup = !hasPin;
      _biometricEnabled = bioEnabled && bioAvailable;
      _errorText = null;
    });

    if (hasPin && AppUnlockSession.isUnlocked) {
      return;
    }

    if (hasPin && _biometricEnabled) {
      await _tryBiometricUnlock(silent: true);
    }
  }

  Future<void> _tryBiometricUnlock({bool silent = false}) async {
    if (_submitting) {
      return;
    }
    final ok = await _biometricAuthService.authenticate(
      reason: L10n.biometricUnlockReason,
    );
    if (!mounted) {
      return;
    }
    if (ok) {
      AppUnlockSession.unlock();
      setState(() {
        _errorText = null;
        _needsSetup = false;
      });
      return;
    }
    if (!silent) {
      setState(() => _errorText = L10n.biometricVerifyFailed);
    }
  }

  Future<void> _unlockWithPin(String pin) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _submitting) {
      return;
    }
    if (!SecurityPinService.instance.isValidPinFormat(pin)) {
      setState(() => _errorText = L10n.pinEnterRequired);
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    final ok = await SecurityPinService.instance.verifyPin(uid, pin);
    if (!mounted) {
      return;
    }

    if (ok) {
      AppUnlockSession.unlock();
      _unlockKeypadKey.currentState?.clear();
      setState(() => _submitting = false);
      return;
    }

    _unlockKeypadKey.currentState?.clear();
    setState(() {
      _submitting = false;
      _errorText = L10n.pinIncorrect;
    });
  }

  Future<void> _onSetupPinCompleted(String pin) async {
    if (_setupStep == 0) {
      setState(() {
        _setupPinDraft = pin;
        _setupStep = 1;
        _errorText = null;
      });
      _setupKeypadKey.currentState?.clear();
      return;
    }

    await _completePinSetup(pin);
  }

  Future<void> _completePinSetup(String confirmPin) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _submitting) {
      return;
    }

    if (!SecurityPinService.instance.isValidPinFormat(_setupPinDraft)) {
      setState(() {
        _errorText = L10n.pinSetRequired;
        _setupStep = 0;
        _setupPinDraft = '';
      });
      _setupKeypadKey.currentState?.clear();
      return;
    }
    if (_setupPinDraft != confirmPin) {
      setState(() {
        _errorText = L10n.pinMismatchRetry;
        _setupStep = 0;
        _setupPinDraft = '';
      });
      _setupKeypadKey.currentState?.clear();
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    await SecurityPinService.instance.setPin(uid, _setupPinDraft);
    AppUnlockSession.unlock();

    if (!mounted) {
      return;
    }

    setState(() {
      _submitting = false;
      _needsSetup = false;
      _setupStep = 0;
      _setupPinDraft = '';
    });
    _setupKeypadKey.currentState?.clear();
  }

  void _restartSetupPin() {
    setState(() {
      _setupStep = 0;
      _setupPinDraft = '';
      _errorText = null;
    });
    _setupKeypadKey.currentState?.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!AppUnlockSession.isUnlocked && _needsSetup) {
      return _buildSetupScreen();
    }

    if (!AppUnlockSession.isUnlocked) {
      return _buildUnlockScreen();
    }

    return widget.child;
  }

  Widget _buildBrandMark() {
    final asset = (widget.logoAsset != null && widget.logoAsset!.isNotEmpty)
        ? widget.logoAsset!
        : 'assets/app_logo.png';
    return Center(
      child: Image.asset(asset, height: 96, fit: BoxFit.contain),
    );
  }

  Widget _buildSetupScreen() {
    final setupLabel = _setupStep == 0
        ? L10n.pinSetTitle
        : L10n.pinConfirmTitle;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              _buildBrandMark(),
              const SizedBox(height: 24),
              Text(
                setupLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                L10n.pinUsageHint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              if (_setupStep == 1) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _submitting ? null : _restartSetupPin,
                  child: Text(L10n.pinChangeExisting),
                ),
              ],
              if (_errorText != null) ...[
                const SizedBox(height: 8),
                Text(_errorText!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              if (_submitting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                SecurityPinKeypad(
                  key: _setupKeypadKey,
                  enabled: !_submitting,
                  onCompleted: _onSetupPinCompleted,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnlockScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              _buildBrandMark(),
              const SizedBox(height: 20),
              Text(
                L10n.unlockTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                L10n.unlockMethodHint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              if (_biometricEnabled) ...[
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _submitting
                      ? null
                      : () => _tryBiometricUnlock(silent: false),
                  icon: const Icon(Icons.fingerprint),
                  label: Text(L10n.unlockWithBiometric),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.accent),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 12),
                Text(L10n.unlockOrEnterPin, textAlign: TextAlign.center),
              ],
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(_errorText!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 8),
              Expanded(
                child: _submitting
                    ? const Center(child: CircularProgressIndicator())
                    : SecurityPinKeypad(
                        key: _unlockKeypadKey,
                        enabled: !_submitting,
                        onCompleted: _unlockWithPin,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
