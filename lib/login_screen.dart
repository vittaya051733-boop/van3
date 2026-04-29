import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/fcm_token_sync_service.dart';
import 'utils/app_colors.dart';
import 'utils/phone_login_helper.dart';

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
  bool _isPasswordSaved = false;
  String? _socialLoadingKey;

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
          : 'ไรเดอร์',
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
      _showSnack('กรอกข้อมูลให้ครบถ้วน');
      return;
    }

    final isPhone = RegExp(r'^\+?[0-9]{9,}$').hasMatch(input);
    if (isPhone) {
      setState(() => _isLoading = true);
      try {
        final normalizedPhone = PhoneLoginHelper.normalize(input);
        final existingRider = await FirebaseFirestore.instance
            .collection('riders')
            .where('phoneNumber', isEqualTo: normalizedPhone)
            .limit(1)
            .get();

        final loginEmail = existingRider.docs.isNotEmpty
            ? (existingRider.docs.first.data()['loginEmail'] as String?)
          : null;

        if (loginEmail != null && loginEmail.isNotEmpty) {
          final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: loginEmail,
            password: password,
          );
          if (credential.user == null) {
            throw Exception('ไม่พบข้อมูลผู้ใช้หลังเข้าสู่ระบบ');
          }
          await _upsertRiderLoginUser(
            credential.user!,
            phoneInput: normalizedPhone,
          );
          await FcmTokenSyncService.instance.syncNow();
          if (!mounted) return;
          setState(() => _isLoading = false);
          Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
          return;
        }

        if (!mounted) return;
        setState(() => _isLoading = false);
        _showSnack('ไม่พบบัญชีที่ผูกกับเบอร์โทรนี้');
        return;
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _showSnack('เกิดข้อผิดพลาดในการเข้าสู่ระบบด้วยเบอร์โทร: $e');
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
        throw Exception('ไม่พบข้อมูลผู้ใช้หลังเข้าสู่ระบบ');
      }

      await _upsertRiderLoginUser(userCredential.user!);
      await FcmTokenSyncService.instance.syncNow();

      if (!mounted) return;
      setState(() => _isLoading = false);
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message = 'ไม่สามารถเข้าสู่ระบบได้';
      if (e.code == 'user-not-found') {
        message = 'ไม่พบผู้ใช้นี้ในระบบ กรุณาลงทะเบียนก่อน';
      } else if (e.code == 'wrong-password') {
        message = 'รหัสผ่านไม่ถูกต้อง';
      } else if (e.code == 'invalid-email') {
        message = 'รูปแบบอีเมลไม่ถูกต้อง';
      } else if (e.code == 'user-disabled') {
        message = 'บัญชีนี้ถูกปิดการใช้งาน';
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
        throw StateError('ยังไม่ได้ตั้งค่า GOOGLE_ANDROID_SERVER_CLIENT_ID');
      }
      if (Platform.isIOS && _iosClientId.isEmpty) {
        throw StateError('ยังไม่ได้ตั้งค่า GOOGLE_IOS_CLIENT_ID');
      }

      final googleSignIn = GoogleSignIn.instance;
      await googleSignIn.initialize(
        serverClientId: Platform.isAndroid ? _androidServerClientId : null,
        clientId: Platform.isIOS ? _iosClientId : null,
      );
      if (!googleSignIn.supportsAuthenticate()) {
        throw Exception('แพลตฟอร์มนี้ไม่รองรับ Google Sign-In');
      }

      final googleUser = await googleSignIn.authenticate();
      final googleAuth = googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw FirebaseAuthException(code: 'missing-id-token', message: 'ไม่พบ Google ID token');
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      if (userCredential.user == null) {
        throw FirebaseAuthException(code: 'user-not-found', message: 'ไม่พบข้อมูลผู้ใช้หลังเข้าสู่ระบบ');
      }
      await _upsertRiderLoginUser(userCredential.user!);
      await FcmTokenSyncService.instance.syncNow();

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        _showSnack('ไม่สามารถเข้าสู่ระบบด้วย Google ได้ (${e.code.name})');
      }
    } on StateError catch (e) {
      _showSnack('ตั้งค่า Google Sign-In ไม่ครบ: ${e.message}');
    } on FirebaseAuthException catch (e) {
      _showSnack('ไม่สามารถเข้าสู่ระบบด้วย Google ได้ (${e.code})');
    } catch (_) {
      _showSnack('ไม่สามารถเข้าสู่ระบบด้วย Google ได้');
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
        title: const Text('เข้าสู่ระบบ'),
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
                labelText: 'อีเมลหรือเบอร์โทร',
                hintText: 'user@example.com หรือ 0812345678',
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
                labelText: 'รหัสผ่าน',
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pushNamed('/forgot'),
                  child: const Text(
                    'ลืมรหัสผ่าน?',
                    style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w500),
                  ),
                ),
                Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _isPasswordSaved,
                        onChanged: (bool? value) async {
                          if (value == true) {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString(
                              'saved_password_${_emailController.text}',
                              _passwordController.text,
                            );
                          }
                          setState(() => _isPasswordSaved = value ?? false);
                        },
                        activeColor: AppColors.accent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'บันทึกรหัสผ่าน',
                      style: TextStyle(fontSize: 14, color: Color(0xFF718096)),
                    ),
                  ],
                ),
              ],
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
                  : const Text('เข้าสู่ระบบ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 24),
            const _OrDivider(),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: _socialButton(
                onPressed: _isSocialLoading ? null : _signInWithGoogle,
                assetImage: 'assets/file_0000000075b0720680f74d4375d75c25.png',
                label: 'เข้าสู่ระบบด้วย Google',
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                buttonKey: 'google',
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: const Text(
                  '← ย้อนกลับ',
                  style: TextStyle(color: AppColors.accent, fontSize: 16, fontWeight: FontWeight.w500),
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
              child: const Image(
                image: AssetImage('assets/file_000000008fc872089268acc9b04e5bcf.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        const Text(
          'Van3 Rider',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50)),
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
    return const Row(
      children: [
        Expanded(child: Divider()),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('หรือ', style: TextStyle(color: Colors.grey)),
        ),
        Expanded(child: Divider()),
      ],
    );
  }
}
