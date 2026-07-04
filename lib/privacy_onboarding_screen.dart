import 'package:flutter/material.dart';

import 'data/legal_content.dart';
import 'legal_document_screen.dart';

class PrivacyOnboardingResult {
  const PrivacyOnboardingResult({
    required this.acceptedTerms,
    required this.pushOptIn,
    required this.marketingOptIn,
  });

  final bool acceptedTerms;
  final bool pushOptIn;
  final bool marketingOptIn;
}

class PrivacyOnboardingScreen extends StatefulWidget {
  const PrivacyOnboardingScreen({
    super.key,
    required this.app,
    this.canDismiss = false,
  });

  final String app;
  final bool canDismiss;

  @override
  State<PrivacyOnboardingScreen> createState() =>
      _PrivacyOnboardingScreenState();
}

class _PrivacyOnboardingScreenState extends State<PrivacyOnboardingScreen> {
  bool _acceptedTerms = false;
  bool _pushOptIn = false;
  bool _marketingOptIn = false;

  void _openDocument(LegalDocument document) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentScreen(document: document),
      ),
    );
  }

  void _continue() {
    if (!_acceptedTerms) return;
    Navigator.of(context).pop(
      PrivacyOnboardingResult(
        acceptedTerms: true,
        pushOptIn: _pushOptIn,
        marketingOptIn: _marketingOptIn,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('ความเป็นส่วนตัวและข้อกำหนด'),
        automaticallyImplyLeading: widget.canDismiss,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                children: [
                  const Text(
                    'โปรดอ่านการใช้ข้อมูลส่วนบุคคลของ VANTALAD ก่อนใช้งานต่อ',
                    style: TextStyle(fontSize: 15, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  _LinkCard(
                    title: 'นโยบายความเป็นส่วนตัว',
                    subtitle:
                        'อัปเดตล่าสุด: ${LegalContent.privacyPolicy.updatedAtLabel}',
                    onTap: () => _openDocument(LegalContent.privacyPolicy),
                  ),
                  const SizedBox(height: 10),
                  _LinkCard(
                    title: 'ข้อกำหนดการใช้งาน',
                    subtitle:
                        'อัปเดตล่าสุด: ${LegalContent.termsOfService.updatedAtLabel}',
                    onTap: () => _openDocument(LegalContent.termsOfService),
                  ),
                  const SizedBox(height: 10),
                  _LinkCard(
                    title: 'ข้อมูลที่เราเก็บ',
                    subtitle:
                        'อัปเดตล่าสุด: ${LegalContent.dataSummary.updatedAtLabel}',
                    onTap: () => _openDocument(LegalContent.dataSummary),
                  ),
                  const SizedBox(height: 20),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _acceptedTerms,
                    onChanged: (value) {
                      setState(() => _acceptedTerms = value == true);
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'ยอมรับข้อกำหนดและนโยบายความเป็นส่วนตัว (จำเป็น)',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _pushOptIn,
                    onChanged: (value) => setState(() => _pushOptIn = value),
                    title: const Text('รับการแจ้งเตือนงานและออเดอร์'),
                    subtitle: const Text('ไม่บังคับ'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _marketingOptIn,
                    onChanged: (value) =>
                        setState(() => _marketingOptIn = value),
                    title: const Text('รับข่าวโปรโมชัน'),
                    subtitle: const Text('ไม่บังคับ'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _acceptedTerms ? _continue : null,
                  child: const Text('ดำเนินการต่อ'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.policy_outlined, color: Color(0xFFFF8A1E)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
