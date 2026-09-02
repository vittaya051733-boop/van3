import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'utils/guarded_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'services/fcm_token_sync_service.dart';
import 'services/notification_service.dart';
import 'services/privacy_consent_service.dart';
import 'l10n/l10n.dart';
import 'utils/app_colors.dart';
import 'utils/phone_login_helper.dart';
import 'apple_auth.dart';
import 'web_apple_auth.dart';

class _RiderLoginLookup {
  const _RiderLoginLookup({
    this.loginEmail,
    this.useEmailLogin = false,
    this.found = false,
  });

  final String? loginEmail;
  final bool useEmailLogin;
  final bool found;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const String _androidServerClientId = String.fromEnvironment(
    'GOOGLE_ANDROID_SERVER_CLIENT_ID',
    defaultValue: '802503541368-6sh9d08648ctf3e6ujlsd8l8400uu0ej.apps.googleusercontent.com',
  );

  static const String _iosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '802503541368-d362comn6pe4gf59kotjma4qvf2kb1eb.apps.googleusercontent.com',
  );

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isSocialLoading = false;
  bool _isPasswordVisible = false;
  String? _socialLoadingKey;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      unawaited(_handleWebOAuthRedirectResult());
    }
  }

  Future<void> _handleWebOAuthRedirectResult() async {
    try {
      final result = await handleWebOAuthRedirectResult();
      if (result?.user == null || !mounted) {
        return;
      }
      await _upsertRiderLoginUser(result!.user!);
      if (!mounted) {
        return;
      }
      await _finishLogin();
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }
      if (error.code != 'auth/redirect-initiated' &&
          error.code != 'redirect-initiated') {
        _showSnack(L10n.appleSignInFailed);
      }
    } catch (_) {}
  }

  Future<void> _finishLogin() async {
    final consentOk = await PrivacyConsentService.instance.ensureConsent(
      context,
      app: PrivacyAppKey.van3Rider,
      source: 'login_gate',
    );
    if (!consentOk || !mounted) {
      return;
    }

    final local = await PrivacyConsentService.instance.loadLocalSnapshot();
    if (local?.pushOptIn == true) {
      await NotificationService().enablePushNotifications();
      await FcmTokenSyncService.instance.syncNow();
    }

    if (!mounted) {
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
  }

  Future<void> _upsertRiderLoginUser(User user, {String? phoneInput}) async {
    final now = FieldValue.serverTimestamp();
    final normalizedPhone =
        (phoneInput != null && phoneInput.trim().isNotEmpty)
            ? PhoneLoginHelper.normalize(phoneInput)
            : null;
    final data = <String, dynamic>{
      'uid': user.uid,
      'email': user.email,
      'loginEmail': user.email,
      'displayName': (user.displayName?.trim().isNotEmpty ?? false)
          ? user.displayName!.trim()
          : L10n.adminSupportSourceRider,
      'role': 'rider',
      'userType': 'rider',
      'updatedAt': now,
      'lastLoginAt': now,
      'createdAt': now,
    };

    if (normalizedPhone != null && normalizedPhone.isNotEmpty) {
      data['phoneNumber'] = normalizedPhone;
    }

    await FirebaseFirestore.instance
      .collection('riders')
        .doc(user.uid)
        .set(data, SetOptions(merge: true));
  }

  Future<_RiderLoginLookup> _lookupRiderLogin(String normalizedPhone) async {
    try {
      final response = await GuardedFunctions.call(
        'resolveRiderLoginEmail',
        parameters: <String, dynamic>{'phoneNumber': normalizedPhone},
      );
      final data = response.data;
      if (data is Map) {
        final loginEmail = data['loginEmail']?.toString().trim();
        return _RiderLoginLookup(
          loginEmail: loginEmail?.isNotEmpty == true ? loginEmail : null,
          useEmailLogin: data['useEmailLogin'] == true,
          found: data['found'] == true,
        );
      }
    } on FirebaseFunctionsException catch (error) {
      if (kDebugMode) {
        debugPrint('resolveRiderLoginEmail failed: ${error.code} ${error.message}');
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('resolveRiderLoginEmail failed: $error');
      }
    }
    return const _RiderLoginLookup();
  }

  Future<void> _signInWithResolvedEmail({
    required String loginEmail,
    required String password,
    String? phoneInput,
  }) async {
    final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: loginEmail,
      password: password,
    );
    if (credential.user == null) {
      throw Exception(L10n.userMissingAfterSignIn);
    }
    await _upsertRiderLoginUser(
      credential.user!,
      phoneInput: phoneInput,
    );
    if (!mounted) {
      return;
    }
    setState(() => _isLoading = false);
    await _finishLogin();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithEmailOrPhone() async {
    final input = _emailController.text.trim();
    final password = _passwordController.text;
    if (input.isEmpty || password.isEmpty) {
      _showSnack(L10n.fillAllFields);
      return;
    }

    final isPhone = RegExp(r'^\+?[0-9]{9,}$').hasMatch(input);
    if (isPhone) {
      setState(() => _isLoading = true);
      try {
        final normalizedPhone = PhoneLoginHelper.normalize(input);
        final lookup = await _lookupRiderLogin(normalizedPhone);
        if (lookup.useEmailLogin) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          _showSnack(L10n.accountLinkedToEmail);
          return;
        }
        final loginCandidates = <String>{
          if (lookup.loginEmail != null && lookup.loginEmail!.isNotEmpty)
            lookup.loginEmail!,
          PhoneLoginHelper.pseudoEmail(normalizedPhone),
        };

        FirebaseAuthException? lastAuthError;
        for (final loginEmail in loginCandidates) {
          try {
            await _signInWithResolvedEmail(
              loginEmail: loginEmail,
              password: password,
              phoneInput: normalizedPhone,
            );
            return;
          } on FirebaseAuthException catch (error) {
            lastAuthError = error;
            if (error.code != 'user-not-found' && error.code != 'invalid-email') {
              rethrow;
            }
          }
        }

        if (!mounted) return;
        setState(() => _isLoading = false);
        if (lastAuthError?.code == 'wrong-password') {
          _showSnack(L10n.wrongPassword);
          return;
        }
        if (lastAuthError?.code == 'user-disabled') {
          _showSnack(L10n.accountDisabled);
          return;
        }
        _showSnack(L10n.phoneAccountNotFound);
        return;
      } on FirebaseAuthException catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        String message = L10n.signInFailed;
        if (e.code == 'wrong-password') {
          message = L10n.wrongPassword;
        } else if (e.code == 'user-disabled') {
          message = L10n.accountDisabled;
        }
        _showSnack(message);
        return;
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _showSnack(L10n.phoneSignInError(e));
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: input,
        password: password,
      );
      if (userCredential.user == null) {
        throw Exception(L10n.userMissingAfterSignIn);
      }

      await _upsertRiderLoginUser(userCredential.user!);

      if (!mounted) return;
      setState(() => _isLoading = false);
      await _finishLogin();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message = L10n.signInFailed;
      if (e.code == 'user-not-found') {
        message = L10n.userNotFoundRegisterFirst;
      } else if (e.code == 'wrong-password') {
        message = L10n.wrongPassword;
      } else if (e.code == 'invalid-email') {
        message = L10n.invalidEmailFormat;
      } else if (e.code == 'user-disabled') {
        message = L10n.accountDisabled;
      }
      _showSnack(message);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isSocialLoading = true;
      _socialLoadingKey = 'google';
    });

    try {
      if (Platform.isAndroid && _androidServerClientId.isEmpty) {
        throw StateError(L10n.googleAndroidClientIdNotSet);
      }
      if (Platform.isIOS && _iosClientId.isEmpty) {
        throw StateError(L10n.googleIosClientIdNotSet);
      }

      final googleSignIn = GoogleSignIn.instance;
      await googleSignIn.initialize(
        serverClientId: Platform.isAndroid ? _androidServerClientId : null,
        clientId: Platform.isIOS ? _iosClientId : null,
      );
      if (!googleSignIn.supportsAuthenticate()) {
        throw Exception(L10n.googleSignInNotSupported);
      }

      final googleUser = await googleSignIn.authenticate();
      final googleAuth = googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw FirebaseAuthException(code: 'missing-id-token', message: L10n.googleIdTokenMissing);
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      if (userCredential.user == null) {
        throw FirebaseAuthException(code: 'user-not-found', message: L10n.userMissingAfterSignIn);
      }
      await _upsertRiderLoginUser(userCredential.user!);

      if (!mounted) return;
      setState(() => _isSocialLoading = false);
      await _finishLogin();
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        if (kDebugMode) {
          debugPrint('Google sign-in failed: ${e.code} ${e.description ?? ''}');
        }
        _showSnack(L10n.googleSignInFailedWithCode(e.code.name));
      }
    } on StateError catch (e) {
      if (kDebugMode) {
        debugPrint('Google sign-in configuration error: ${e.message}');
      }
      _showSnack(L10n.googleSignInConfigIncomplete(e.message));
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        debugPrint('Firebase Google sign-in failed: ${e.code} ${e.message ?? ''}');
      }
      final message = e.message ?? '';
      if (e.code == 'internal-error' && message.contains('blocked')) {
        _showSnack(L10n.firebaseBlockedVan3);
      } else {
        _showSnack(L10n.googleSignInFailedFirebaseCode(e.code));
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Unexpected Google sign-in error: $error');
        debugPrint('$stackTrace');
      }
      _showSnack(L10n.googleSignInFailed);
    } finally {
      if (mounted) {
        setState(() {
          _isSocialLoading = false;
          _socialLoadingKey = null;
        });
      }
    }
  }

  Future<void> _signInWithApple() async {
    setState(() {
      _isSocialLoading = true;
      _socialLoadingKey = 'apple';
    });

    try {
      final userCredential = await signInWithApple();
      if (userCredential.user == null) {
        throw FirebaseAuthException(code: 'user-not-found', message: L10n.userMissingAfterSignIn);
      }
      await _upsertRiderLoginUser(userCredential.user!);

      if (!mounted) return;
      setState(() => _isSocialLoading = false);
      await _finishLogin();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'popup-closed-by-user' ||
          e.code == 'redirect-initiated' ||
          e.code == 'auth/redirect-initiated') {
        return;
      }
      if (kDebugMode) {
        debugPrint('Apple sign-in failed: ${e.code} ${e.message ?? ''}');
      }
      if (e.code == 'account-exists-with-different-credential' ||
          e.code == 'auth/account-exists-with-different-credential') {
        _showSnack(L10n.appleAccountExistsWithDifferentCredential);
      } else {
        _showSnack(L10n.appleSignInFailed);
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Unexpected Apple sign-in error: $error');
        debugPrint('$stackTrace');
      }
      _showSnack(L10n.appleSignInFailed);
    } finally {
      if (mounted) {
        setState(() {
          _isSocialLoading = false;
          _socialLoadingKey = null;
        });
      }
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _socialButton({
    required VoidCallback? onPressed,
    required String label,
    required Color backgroundColor,
    required Color foregroundColor,
    required String buttonKey,
    String? assetSvg,
    String? assetImage,
    IconData? icon,
  }) {
    final isLoading = _isSocialLoading && _socialLoadingKey == buttonKey;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: (_isLoading || _isSocialLoading) ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          side: BorderSide(color: Colors.grey.shade300),
        ),
        icon: isLoading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
                ),
              )
            : (assetImage != null
                ? Image.asset(assetImage, width: 22, height: 22, fit: BoxFit.contain)
                : assetSvg != null
                    ? SvgPicture.asset(assetSvg, height: 22, width: 22)
                    : Icon(icon, size: 22, color: foregroundColor)),
        label: Text(
          label,
          style: TextStyle(fontSize: 16, color: foregroundColor, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(L10n.signIn),
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _LoginHeader(),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username, AutofillHints.email],
              decoration: InputDecoration(
                labelText: L10n.emailOrPhone,
                hintText: L10n.emailOrPhoneHint,
                prefixIcon: const Icon(Icons.account_circle),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: !_isPasswordVisible,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: L10n.password,
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_isPasswordVisible ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              onFieldSubmitted: (_) {
                if (!_isLoading) {
                  _signInWithEmailOrPhone();
                }
              },
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pushNamed('/forgot'),
                child: Text(
                  L10n.forgotPasswordQuestion,
                  style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w500),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _signInWithEmailOrPhone,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(L10n.signIn, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 24),
            const _OrDivider(),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: _socialButton(
                onPressed: _isSocialLoading ? null : _signInWithGoogle,
                assetImage: 'assets/google_logo.png',
                label: L10n.signInWithGoogle,
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                buttonKey: 'google',
              ),
            ),
            if (isAppleSignInSupported) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: _socialButton(
                  onPressed: _isSocialLoading ? null : _signInWithApple,
                  label: L10n.signInWithApple,
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  buttonKey: 'apple',
                  icon: Icons.apple,
                ),
              ),
            ],
            const SizedBox(height: 24),
            Center(
              child: GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: Text(
                  L10n.goBack,
                  style: const TextStyle(color: AppColors.accent, fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _LoginHeader extends StatelessWidget {
  const _LoginHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 40),
        Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20.0),
              child: Image.asset(
                'assets/app_logo.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        Text(
          L10n.appTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50)),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(L10n.orDivider, style: const TextStyle(color: Colors.grey)),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
