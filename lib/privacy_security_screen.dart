import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'data/legal_content.dart';
import 'legal_document_screen.dart';
import 'services/notification_service.dart';
import 'services/privacy_consent_service.dart';

class PrivacySecurityScreen extends StatefulWidget {
  const PrivacySecurityScreen({super.key});

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  bool _loading = true;
  bool _busy = false;
  bool _pushOptIn = false;
  bool _marketingOptIn = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final local = await PrivacyConsentService.instance.loadLocalSnapshot();
    if (!mounted) return;
    setState(() {
      _pushOptIn = local?.pushOptIn ?? false;
      _marketingOptIn = local?.marketingOptIn ?? false;
      _loading = false;
    });
  }

  Future<void> _openSystemSettings() async {
    final opened = await openAppSettings();
    if (!opened && mounted) {
      await Geolocator.openAppSettings();
    }
  }

  Future<void> _setPushOptIn(bool enabled) async {
    setState(() {
      _pushOptIn = enabled;
      _busy = true;
    });
    try {
      if (enabled) {
        await NotificationService().enablePushNotifications();
      }
      await PrivacyConsentService.instance.updatePreference(
        app: PrivacyAppKey.van3Rider,
        pushOptIn: enabled,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกการตั้งค่าแจ้งเตือนไม่สำเร็จ: $error')),
        );
      }
      await _loadPreferences();
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setMarketingOptIn(bool enabled) async {
    setState(() {
      _marketingOptIn = enabled;
      _busy = true;
    });
    try {
      await PrivacyConsentService.instance.updatePreference(
        app: PrivacyAppKey.van3Rider,
        marketingOptIn: enabled,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกการตั้งค่าการตลาดไม่สำเร็จ: $error')),
        );
      }
      await _loadPreferences();
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitPrivacyRequest(String type) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อนส่งคำขอ')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(switch (type) {
          'export' => 'ขอส่งออกข้อมูล',
          'delete' => 'ขอลบบัญชี',
          _ => 'ขอแก้ไขข้อมูล',
        }),
        content: const Text(
          'ระบบจะสร้างคำขอ PDPA และแจ้งแอดมิน ต้องการดำเนินการต่อหรือไม่?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ส่งคำขอ'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await PrivacyConsentService.instance.createPrivacyRequest(
        app: PrivacyAppKey.van3Rider,
        type: type,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ส่งคำขอแล้ว (${result.requestId})')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ส่งคำขอไม่สำเร็จ: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('ความเป็นส่วนตัวและความปลอดภัย')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ListTile(
                  leading: const Icon(Icons.policy_outlined),
                  title: const Text('นโยบายความเป็นส่วนตัว'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const LegalDocumentScreen(
                        document: LegalContent.privacyPolicy,
                      ),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('ข้อกำหนดการใช้งาน'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const LegalDocumentScreen(
                        document: LegalContent.termsOfService,
                      ),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('ข้อมูลที่เราเก็บ'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const LegalDocumentScreen(
                        document: LegalContent.dataSummary,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('แจ้งเตือนงาน'),
                  value: _pushOptIn,
                  onChanged: _busy ? null : _setPushOptIn,
                ),
                SwitchListTile(
                  title: const Text('ข่าวโปรโมชัน'),
                  value: _marketingOptIn,
                  onChanged: _busy ? null : _setMarketingOptIn,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('ขอส่งออกข้อมูล'),
                  onTap: _busy ? null : () => _submitPrivacyRequest('export'),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_note_outlined),
                  title: const Text('ขอแก้ไขข้อมูล'),
                  onTap: _busy ? null : () => _submitPrivacyRequest('correct'),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever_outlined),
                  title: const Text('ขอลบบัญชี'),
                  onTap: _busy ? null : () => _submitPrivacyRequest('delete'),
                ),
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: const Text('จัดการสิทธิ์แอป'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _openSystemSettings,
                ),
              ],
            ),
    );
  }
}
