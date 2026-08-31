import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/security_pin_service.dart';
import 'security_pin_keypad.dart';

/// Returns true when the user entered the correct security PIN.
Future<bool> showSecurityPinVerifyDialog(
  BuildContext context, {
  required String title,
  String? subtitle,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    return false;
  }

  final keypadKey = GlobalKey<SecurityPinKeypadState>();
  var verifying = false;
  String? errorText;

  final verified = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> submit(String pin) async {
            if (verifying) {
              return;
            }
            if (!SecurityPinService.instance.isValidPinFormat(pin)) {
              setState(() => errorText = L10n.pinEnterRequired);
              return;
            }
            setState(() {
              verifying = true;
              errorText = null;
            });
            try {
              final ok = await SecurityPinService.instance.verifyPin(uid, pin);
              if (!context.mounted) {
                return;
              }
              if (ok) {
                Navigator.of(context).pop(true);
                return;
              }
              keypadKey.currentState?.clear();
              setState(() {
                verifying = false;
                errorText = L10n.pinIncorrect;
              });
            } catch (error) {
              if (!context.mounted) {
                return;
              }
              keypadKey.currentState?.clear();
              setState(() {
                verifying = false;
                errorText = L10n.pinVerifyFailedRetry;
              });
            }
          }

          return AlertDialog(
            backgroundColor: Colors.white,
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(subtitle ?? L10n.pinVerifyDefaultSubtitle),
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorText!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 8),
                if (verifying)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  SecurityPinKeypad(
                    key: keypadKey,
                    enabled: !verifying,
                    onCompleted: submit,
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: verifying
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: Text(L10n.cancel),
              ),
            ],
          );
        },
      );
    },
  );

  return verified == true;
}

/// Guard for wallet / admin support flows.
Future<bool> verifySecurityPinForSensitiveAction(
  BuildContext context, {
  required String title,
  String? subtitle,
}) {
  return showSecurityPinVerifyDialog(
    context,
    title: title,
    subtitle: subtitle ?? L10n.pinVerifyDefaultSubtitle,
  );
}
