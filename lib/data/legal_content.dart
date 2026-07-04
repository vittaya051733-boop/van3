class LegalDocument {
  const LegalDocument({
    required this.titleTh,
    required this.titleEn,
    required this.bodyTh,
    required this.bodyEn,
    required this.updatedAtLabel,
  });

  final String titleTh;
  final String titleEn;
  final String bodyTh;
  final String bodyEn;
  final String updatedAtLabel;

  String title(bool english) => english ? titleEn : titleTh;
  String body(bool english) => english ? bodyEn : bodyTh;
}

class LegalContent {
  LegalContent._();

  static const privacyPolicy = LegalDocument(
    titleTh: 'นโยบายความเป็นส่วนตัว',
    titleEn: 'Privacy Policy',
    updatedAtLabel: '1 มิ.ย. 2026',
    bodyTh: '''แอป Van Rider (van3) สำหรับไรเดอร์ เป็นส่วนหนึ่งของแพลตฟอร์ม VANTALAD

ผู้ควบคุมข้อมูล
• ผู้ให้บริการแพลตฟอร์ม VANTALAD (Van Market)

ข้อมูลที่เราเก็บ
• บัญชีไรเดอร์ (อีเมล, เบอร์โทร, ชื่อ, รูปโปรไฟล์)
• ตำแหน่ง GPS แบบเรียลไทม์ขณะรับงานและจัดส่ง
• ออเดอร์ที่รับ ประวัติงาน รายได้ และกระเป๋าเงิน
• การโทร/แชทกับลูกค้าและแอดมิน
• โทเคนแจ้งเตือน (FCM) เมื่อคุณ opt-in

ฐานทางกฎหมาย (PDPA)
• สัญญา — ให้บริการรับส่งและจัดการงาน
• ความยินยอม — การตลาดและการแจ้งเตือน (ถ้าเลือกเปิด)
• ประโยชน์โดยชอบด้วยกฎหมาย — ความปลอดภัยและติดตามงาน

ผู้ประมวลผลภายนอก
• Google Firebase (Auth, Firestore, Storage, Functions, FCM)
• Agora — โทร/วิดีโอคอลผ่านแอป

การโอนข้อมูลต่างประเทศ
• ข้อมูลอาจถูกประมวลผลบนเซิร์ฟเวอร์ของ Google/Firebase ในต่างประเทศ

สิทธิของคุณ (PDPA)
• เข้าถึง ส่งออก แก้ไข ลบ หรือถอนความยินยอม
• ตั้งค่า → ความเป็นส่วนตัวและความปลอดภัย

ติดต่อ
• ตั้งค่า → ติดต่อแอดมิน''',
    bodyEn: '''Van Rider app (van3) is part of the VANTALAD platform.

Data controller
• VANTALAD platform operator

Data we collect
• Rider account (email, phone, name, profile photo)
• Real-time GPS while accepting and delivering orders
• Jobs, earnings, and wallet
• Calls/chats with customers and admin
• FCM token when you opt in

Legal bases (PDPA)
• Contract — delivery services
• Consent — marketing and push (if enabled)
• Legitimate interest — safety and job tracking

Processors
• Google Firebase
• Agora for in-app calls

Cross-border transfer
• Data may be processed on Google/Firebase servers abroad

Your rights (PDPA)
• Access, export, correct, delete, or withdraw consent
• Settings → Privacy & security

Contact
• Settings → Contact admin''',
  );

  static const termsOfService = LegalDocument(
    titleTh: 'ข้อกำหนดการใช้งาน',
    titleEn: 'Terms of Service',
    updatedAtLabel: '1 มิ.ย. 2026',
    bodyTh: '''การใช้แอป Van Rider ถือว่าคุณยอมรับข้อกำหนดนี้และนโยบายความเป็นส่วนตัว

บัญชีไรเดอร์
• ให้ข้อมูลที่ถูกต้องและรักษาความปลอดภัยบัญชี

การรับงาน
• ต้องปฏิบัติตามกฎหมายจราจรและนโยบายแพลตฟอร์ม
• อัปเดตสถานะงานและตำแหน่งให้ถูกต้อง

รายได้
• คำนวณตามนโยบายที่แอดมินกำหนด

การระงับบริการ
• บัญชีที่ละเมิดข้อกำหนดอาจถูกระงับ''',
    bodyEn: '''By using Van Rider you agree to these terms and the Privacy Policy.

Rider account
• Provide accurate information and keep your account secure

Jobs
• Follow traffic laws and platform policy
• Keep job status and location accurate

Earnings
• Calculated per admin policy

Suspension
• Accounts violating terms may be suspended''',
  );

  static const dataSummary = LegalDocument(
    titleTh: 'ข้อมูลที่เราเก็บ',
    titleEn: 'Data we collect',
    updatedAtLabel: '1 มิ.ย. 2026',
    bodyTh: '''สรุปข้อมูลหลัก (ไรเดอร์)
• บัญชีและโปรไฟล์
• ตำแหน่ง GPS ขณะทำงาน
• ออเดอร์และรายได้
• การสื่อสารกับลูกค้า/แอดมิน
• การตั้งค่าและความยินยอม

ดูรายละเอียดในนโยบายความเป็นส่วนตัว''',
    bodyEn: '''Rider summary
• Account and profile
• GPS while on duty
• Orders and earnings
• Customer/admin communications
• Preferences and consents

See Privacy Policy for details.''',
  );
}
