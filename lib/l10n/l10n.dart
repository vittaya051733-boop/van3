import 'package:flutter/material.dart';

import '../services/locale_service.dart';

/// Centralized Thai/English strings for van3 rider app.
/// Migrate call sites incrementally — do not duplicate keys elsewhere.
class L10n {
  L10n._();

  static bool get en => LocaleService.instance.isEnglish;

  // ---------------------------------------------------------------------------
  // Locale
  // ---------------------------------------------------------------------------

  static String localeLabel(Locale value) =>
      value.languageCode == 'en' ? languageEnglish : languageThai;

  static String get languageEnglish => 'English';
  static String get languageThai => 'ไทย';

  // ---------------------------------------------------------------------------
  // Common
  // ---------------------------------------------------------------------------

  static String get cancel => en ? 'Cancel' : 'ยกเลิก';
  static String get close => en ? 'Close' : 'ปิด';
  static String get ok => en ? 'OK' : 'ตกลง';
  static String get retry => en ? 'Retry' : 'ลองอีกครั้ง';
  static String get reload => en ? 'Reload' : 'ลองโหลดใหม่';
  static String get reloadAgain => en ? 'Try loading again' : 'ลองโหลดอีกครั้ง';
  static String get later => en ? 'Later' : 'ภายหลัง';
  static String get now => en ? 'Enable now' : 'เปิดตอนนี้';
  static String get confirm => en ? 'Confirm' : 'ยืนยัน';
  static String get submit => en ? 'Submit' : 'ส่ง';
  static String get save => en ? 'Save' : 'บันทึก';
  static String get back => en ? 'Back' : 'ย้อนกลับ';
  static String get next => en ? 'Next' : 'ถัดไป';
  static String get all => en ? 'All' : 'ทั้งหมด';
  static String get optional => en ? 'Optional' : 'ไม่บังคับ';
  static String get loading => en ? 'Loading...' : 'กำลังโหลด...';
  static String get processing => en ? 'Processing...' : 'กำลังประมวลผล...';
  static String get opening => en ? 'Opening...' : 'กำลังเปิด...';
  static String get submitting => en ? 'Submitting...' : 'กำลังส่ง...';
  static String get saving => en ? 'Saving...' : 'กำลังบันทึก...';
  static String get signInRequired => en ? 'Please sign in' : 'กรุณาเข้าสู่ระบบ';
  static String get signInRequiredAgain =>
      en ? 'Please sign in again' : 'กรุณาเข้าสู่ระบบใหม่';
  static String get signInRequiredFirst =>
      en ? 'Please sign in first' : 'กรุณาเข้าสู่ระบบก่อน';
  static String get signInRequiredForHistory =>
      en ? 'Please sign in to view history' : 'กรุณาเข้าสู่ระบบเพื่อดูประวัติ';
  static String get userNotFound =>
      en ? 'User not found' : 'ไม่พบผู้ใช้';
  static String get defaultUser => en ? 'User' : 'ผู้ใช้';
  static String get newUser => en ? 'New user' : 'ผู้ใช้ใหม่';
  static String get you => en ? 'You' : 'คุณ';
  static String get done => en ? 'Done' : 'เสร็จสิ้น';
  static String get dismiss => en ? 'Dismiss' : 'ปิดก่อน';
  static String get viewAll => en ? 'View all' : 'ดูทั้งหมด';
  static String get continueAction => en ? 'Continue' : 'ดำเนินการต่อ';
  static String get notSelected => en ? 'Not selected' : 'ยังไม่ได้เลือก';
  static String get selected => en ? 'Selected' : 'เลือกแล้ว';
  static String get tapToChange => en ? 'Tap to change' : 'แตะเพื่อเปลี่ยน';
  static String get openingGallery => en ? 'Opening gallery...' : 'กำลังเปิดคลังรูป...';
  static String get statusLabel => en ? 'Status' : 'สถานะ';
  static String statusWithValue(String status) =>
      en ? 'Status: $status' : 'สถานะ: $status';
  static String get details => en ? 'Details' : 'รายละเอียด';
  static String get contact => en ? 'Contact' : 'ติดต่อ';
  static String get note => en ? 'Note' : 'หมายเหตุ';
  static String noteWithText(String text) => en ? 'Note: $text' : 'หมายเหตุ: $text';
  static String get quantity => en ? 'Qty' : 'จำนวน';
  static String quantityPieces(int count) =>
      en ? 'Qty $count' : 'จำนวน $count ชิ้น';
  static String get price => en ? 'Price' : 'ราคา';
  static String priceThb(double amount) =>
      en ? 'THB ${amount.toStringAsFixed(1)}' : 'ราคา THB ${amount.toStringAsFixed(1)}';
  static String get total => en ? 'Total' : 'ยอดรวม';
  static String totalThb(double amount) =>
      en ? 'Total: THB ${amount.toStringAsFixed(1)}' : 'ยอดรวม: THB ${amount.toStringAsFixed(1)}';
  static String get shippingFee => en ? 'Delivery fee' : 'ค่าส่ง';
  static String shippingFeeThb(double amount) =>
      en ? 'Delivery fee: THB ${amount.toStringAsFixed(1)}' : 'ค่าส่ง: THB ${amount.toStringAsFixed(1)}';
  static String get fare => en ? 'Fare' : 'ค่าโดยสาร';
  static String fareThb(double amount) =>
      en ? 'Fare: THB ${amount.toStringAsFixed(1)}' : 'ค่าโดยสาร: THB ${amount.toStringAsFixed(1)}';
  static String get paymentMethod => en ? 'Payment' : 'วิธีจ่าย';
  static String paymentMethodWithLabel(String? label) =>
      en ? 'Payment: ${label ?? '-'}' : 'วิธีจ่าย: ${label ?? '-'}';
  static String get orderId => en ? 'Order ID' : 'Order ID';
  static String orderIdWithValue(String id) => 'Order ID: $id';
  static String orderCodeWithValue(String code) =>
      en ? 'Order code: $code' : 'เลขออเดอร์: $code';
  static String orderIdAndCode(String id, String code) =>
      en ? 'Order ID: $id\nOrder code: $code' : 'Order ID: $id\nเลขออเดอร์: $code';
  static String orderLabel(String id) => en ? 'Order: $id' : 'ออเดอร์: $id';
  static String orderLabelWithCode(String code) =>
      en ? 'Order: $code' : 'ออเดอร์: $code';
  static String codeLabel(String code) => en ? 'Code: $code' : 'รหัส: $code';
  static String slipOkLabel(String id) => 'SlipOK: $id';
  static String get uidPrefix => 'UID: ';
  static String get copyFullUid => en ? 'Copy full UID' : 'คัดลอก UID เต็ม';
  static String get uidCopied => en ? 'UID copied' : 'คัดลอก UID เรียบร้อย';
  static String get sentFrom => en ? 'Sent from' : 'ส่งจาก';
  static String sentFromSource(String source) =>
      en ? 'Sent from: $source' : 'ส่งจาก: $source';
  static String amountBaht(double amount) => en
      ? '${amount.toStringAsFixed(2)} THB'
      : '${amount.toStringAsFixed(2)} บาท';
  static String amountBahtWhole(double amount) => en
      ? '${amount.toStringAsFixed(0)} THB'
      : '${amount.toStringAsFixed(0)} บาท';
  static String distanceKm(double km) => '${km.toStringAsFixed(2)} km';
  static String estimatedDistanceKm(double km) => en
      ? 'Estimated distance: ${km.toStringAsFixed(2)} km'
      : 'ระยะทางโดยประมาณ: ${km.toStringAsFixed(2)} km';
  static String get noItemsYet => en ? 'No transactions yet' : 'ยังไม่มีรายการ';
  static String get loadFailed => en ? 'Failed to load' : 'โหลดไม่สำเร็จ';
  static String loadFailedWithError(Object error) =>
      en ? 'Failed to load: $error' : 'โหลดไม่สำเร็จ: $error';
  static String get noDataYet => en ? 'No data yet' : 'ยังไม่มีข้อมูล';
  static String get signOut => en ? 'Sign out' : 'ออกจากระบบ';
  static String get preparing => en ? '(Coming soon)' : '(กำลังเตรียม)';
  static String get readOnly => en ? 'Read-only' : 'อ่านอย่างเดียว';
  static String get admin => en ? 'Admin' : 'แอดมิน';
  static String get customer => en ? 'Customer' : 'ลูกค้า';
  static String get shop => en ? 'Shop' : 'ร้านค้า';
  static String get rider => en ? 'Rider' : 'ไรเดอร์';
  static String get caller => en ? 'Caller' : 'ผู้โทร';
  static String get contactPerson => en ? 'Contact' : 'ผู้ติดต่อ';
  static String get chatPartner => en ? 'Chat partner' : 'คู่สนทนา';
  static String get newMessage => en ? 'New message' : 'ข้อความใหม่';
  static String get newNotification => en ? 'New notification' : 'แจ้งเตือนใหม่';
  static String get evLabel => 'EV';
  static String get gpDeductionNote =>
      en ? 'Based on completed deliveries, 15% GP deducted' : 'ใช้ข้อมูลที่บันทึกตอนส่งสำเร็จ หัก 15%';
  static String get gpDeductionNoteShort =>
      en ? 'Recorded at delivery completion' : 'ใช้ข้อมูลที่บันทึกตอนปิดงาน';
  static String get noPromptPayBadge => en ? 'No PP' : 'ไม่มี PP';
  static String get incompleteBadge => en ? 'Incomplete' : 'ไม่ครบ';
  static String get other => en ? 'Other' : 'อื่นๆ';

  // ---------------------------------------------------------------------------
  // App branding
  // ---------------------------------------------------------------------------

  static String get appTitle => 'Van3 Rider';
  static String get riderSystem => en ? 'Rider platform' : 'ระบบไรเดอร์';
  static String get dashboardTitle => en ? 'Van3 Rider Dashboard' : 'Van3 Rider Dashboard';
  static String get dashboardSubtitle =>
      en ? 'Ready for deliveries today' : 'พร้อมลุยงานจัดส่งวันนี้';
  static String get loggedInAccount => en ? 'Signed-in account' : 'บัญชีที่ล็อกอิน';
  static String get noLoggedInAccount =>
      en ? 'No signed-in account found' : 'ไม่พบบัญชีที่ล็อกอิน';

  // ---------------------------------------------------------------------------
  // Welcome / Auth
  // ---------------------------------------------------------------------------

  static String get signIn => en ? 'Sign in' : 'เข้าสู่ระบบ';
  static String get registerRider => en ? 'Register as rider' : 'สมัครไรเดอร์';
  static String get emailOrPhone => en ? 'Email or phone' : 'อีเมลหรือเบอร์โทร';
  static String get emailOrPhoneHint =>
      en ? 'user@example.com or 0812345678' : 'user@example.com หรือ 0812345678';
  static String get password => en ? 'Password' : 'รหัสผ่าน';
  static String get forgotPasswordQuestion => en ? 'Forgot password?' : 'ลืมรหัสผ่าน?';
  static String get signInWithGoogle => en ? 'Sign in with Google' : 'เข้าสู่ระบบด้วย Google';
  static String get goBack => en ? '← Back' : '← ย้อนกลับ';
  static String get orDivider => en ? 'or' : 'หรือ';
  static String get fillAllFields => en ? 'Please fill in all fields' : 'กรอกข้อมูลให้ครบถ้วน';
  static String get accountLinkedToEmail => en
      ? 'This account is linked to email. Please sign in with email instead of phone.'
      : 'บัญชีนี้ผูกกับอีเมล กรุณาเข้าสู่ระบบด้วยอีเมลแทนเบอร์โทร';
  static String get wrongPassword => en ? 'Incorrect password' : 'รหัสผ่านไม่ถูกต้อง';
  static String get accountDisabled =>
      en ? 'This account has been disabled' : 'บัญชีนี้ถูกปิดการใช้งาน';
  static String get phoneAccountNotFound => en
      ? 'No account found for this phone number'
      : 'ไม่พบบัญชีที่ผูกกับเบอร์โทรนี้';
  static String get signInFailed => en ? 'Unable to sign in' : 'ไม่สามารถเข้าสู่ระบบได้';
  static String phoneSignInError(Object error) => en
      ? 'Phone sign-in error: $error'
      : 'เกิดข้อผิดพลาดในการเข้าสู่ระบบด้วยเบอร์โทร: $error';
  static String get userNotFoundRegisterFirst => en
      ? 'User not found. Please register first.'
      : 'ไม่พบผู้ใช้นี้ในระบบ กรุณาลงทะเบียนก่อน';
  static String get invalidEmailFormat => en ? 'Invalid email format' : 'รูปแบบอีเมลไม่ถูกต้อง';
  static String get userMissingAfterSignIn => en
      ? 'User data not found after sign-in'
      : 'ไม่พบข้อมูลผู้ใช้หลังเข้าสู่ระบบ';
  static String get googleIdTokenMissing =>
      en ? 'Google ID token not found' : 'ไม่พบ Google ID token';
  static String get googleSignInNotSupported => en
      ? 'Google Sign-In is not supported on this platform'
      : 'แพลตฟอร์มนี้ไม่รองรับ Google Sign-In';
  static String get googleAndroidClientIdNotSet => en
      ? 'GOOGLE_ANDROID_SERVER_CLIENT_ID is not configured'
      : 'ยังไม่ได้ตั้งค่า GOOGLE_ANDROID_SERVER_CLIENT_ID';
  static String get googleIosClientIdNotSet => en
      ? 'GOOGLE_IOS_CLIENT_ID is not configured'
      : 'ยังไม่ได้ตั้งค่า GOOGLE_IOS_CLIENT_ID';
  static String googleSignInConfigIncomplete(String message) => en
      ? 'Google Sign-In is not fully configured: $message'
      : 'ตั้งค่า Google Sign-In ไม่ครบ: $message';
  static String googleSignInFailedWithCode(String code) => en
      ? 'Unable to sign in with Google ($code)'
      : 'ไม่สามารถเข้าสู่ระบบด้วย Google ได้ ($code)';
  static String get firebaseBlockedVan3 => en
      ? 'Firebase still blocks van3.rider.com — wait for SHA-1/App Check to propagate or rebuild the app'
      : 'Firebase ยังบล็อก van3.rider.com — รอ SHA-1/App Check propagate หรือ rebuild แอป';
  static String googleSignInFailedFirebaseCode(String code) => en
      ? 'Unable to sign in with Google ($code)'
      : 'ไม่สามารถเข้าสู่ระบบด้วย Google ได้ ($code)';
  static String get googleSignInFailed =>
      en ? 'Unable to sign in with Google' : 'ไม่สามารถเข้าสู่ระบบด้วย Google ได้';
  static String get forgotPassword => en ? 'Forgot password' : 'ลืมรหัสผ่าน';
  static String get email => en ? 'Email' : 'อีเมล';
  static String get emailReadOnly => en ? 'Email (read-only)' : 'อีเมล (อ่านอย่างเดียว)';
  static String get pleaseEnterEmail => en ? 'Please enter your email' : 'กรุณากรอกอีเมล';
  static String get resetLinkSent =>
      en ? 'Password reset link sent' : 'ส่งลิงก์รีเซ็ตรหัสผ่านแล้ว';
  static String get resetLinkFailed =>
      en ? 'Unable to send reset link' : 'ไม่สามารถส่งลิงก์รีเซ็ตได้';
  static String get sendResetLink => en ? 'Send reset link' : 'ส่งลิงก์รีเซ็ต';
  static String get userMissingSignInAgain =>
      en ? 'User not found. Please sign in again.' : 'ไม่พบผู้ใช้ กรุณาเข้าสู่ระบบใหม่';

  // ---------------------------------------------------------------------------
  // Registration / Profile
  // ---------------------------------------------------------------------------

  static String get registerRiderTitle => en ? 'Register as rider' : 'สมัครไรเดอร์';
  static String get pendingApprovalTitle => en ? 'Pending approval' : 'รอการอนุมัติ';
  static String get registrationSubmitted =>
      en ? 'Rider registration submitted' : 'ส่งคำขอสมัครไรเดอร์แล้ว';
  static String get registrationPendingBody => en
      ? 'Admin will review your documents and bank account.\nYou can start accepting jobs after approval.'
      : 'แอดมินจะตรวจสอบเอกสารและบัญชีธนาคาร\nเมื่ออนุมัติแล้วจึงเริ่มรับงานได้';
  static String registrationRejected(String reason) => en
      ? 'Application rejected: $reason'
      : 'คำขอถูกปฏิเสธ: $reason';
  static String get accountInfoSection => en ? 'Account info' : 'ข้อมูลบัญชี';
  static String get profileAndVehicleSection =>
      en ? 'Profile and vehicle' : 'โปรไฟล์และข้อมูลรถ';
  static String get profileVehicleCustomerHint => en
      ? 'This information is shown to customers after booking a ride'
      : 'ข้อมูลนี้จะแสดงให้ลูกค้าเห็นหลังจองการเดินทาง';
  static String get identityDocumentsSection =>
      en ? 'Identity documents' : 'เอกสารยืนยันตัวตน';
  static String get identityDocumentsHint => en
      ? 'Used for verification before rider partner approval'
      : 'ใช้ตรวจสอบก่อนอนุมัติเป็นพาร์ทเนอร์ไรเดอร์';
  static String get payoutAccountSection => en ? 'Payout account' : 'บัญชีรับเงิน';
  static String get privacyPdpaSection => en ? 'Privacy (PDPA)' : 'ความเป็นส่วนตัว (PDPA)';
  static String get fullName => en ? 'Full name' : 'ชื่อ-นามสกุล';
  static String get pleaseEnterName => en ? 'Please enter your name' : 'กรุณากรอกชื่อ';
  static String get phone => en ? 'Phone' : 'เบอร์โทร';
  static String get pleaseEnterPhone => en ? 'Please enter phone number' : 'กรุณากรอกเบอร์โทร';
  static String get passwordMinSix => en ? 'Password (min. 6 chars)' : 'รหัสผ่าน (อย่างน้อย 6 ตัว)';
  static String get passwordTooShort => en ? 'Password too short' : 'รหัสผ่านสั้นเกินไป';
  static String get vehicleType => en ? 'Vehicle type' : 'ประเภทรถ';
  static String get pleaseSelectVehicleType =>
      en ? 'Please select vehicle type' : 'กรุณาเลือกประเภทรถ';
  static String get licensePlate => en ? 'License plate' : 'ทะเบียนรถ';
  static String get vehicleColorHint => en ? 'Vehicle color (e.g. white)' : 'สีรถ (เช่น ขาว)';
  static String get vehicleBrandHint =>
      en ? 'Brand/model (e.g. AION Y)' : 'ยี่ห้อ/รุ่น (เช่น AION Y)';
  static String get electricVehicle => en ? 'Electric vehicle (EV)' : 'รถไฟฟ้า (EV)';
  static String get profilePhotoTitle =>
      en ? 'Profile photo (clear face)' : 'รูปโปรไฟล์ (ใบหน้าชัดเจน)';
  static String get driverLicense => en ? 'Driver license' : 'ใบขับขี่';
  static String get motorcyclePhoto => en ? 'Motorcycle photo' : 'รูปมอเตอร์ไซค์';
  static String get vehiclePhoto => en ? 'Vehicle photo' : 'รูปรถ';
  static String get bankBookPage => en ? 'Bank book page' : 'หน้าสมุดบัญชี';
  static String get bank => en ? 'Bank' : 'ธนาคาร';
  static String get selectBank => en ? 'Select bank' : 'เลือกธนาคาร';
  static String get pleaseSelectBank => en ? 'Please select a bank' : 'กรุณาเลือกธนาคาร';
  static String get accountNumber => en ? 'Account number' : 'เลขบัญชี';
  static String get pleaseEnterAccountNumber =>
      en ? 'Please enter account number' : 'กรุณากรอกเลขบัญชี';
  static String get accountName =>
      en ? 'Account name (must match bank)' : 'ชื่อบัญชี (ต้องตรงธนาคาร)';
  static String get pleaseEnterAccountName =>
      en ? 'Please enter account name' : 'กรุณากรอกชื่อบัญชี';
  static String get promptPayWithdrawRequired =>
      en ? 'PromptPay (withdrawals) *' : 'PromptPay (ถอนเงิน) *';
  static String get promptPayPhoneRequired =>
      en ? 'PromptPay phone *' : 'เบอร์ PromptPay *';
  static String get promptPayPhoneHint => en ? 'e.g. 0812345678' : 'เช่น 0812345678';
  static String get promptPayNationalIdOptional => en
      ? 'PromptPay national/tax ID (optional)'
      : 'เลขบัตร/นิติบุคคล PromptPay (ถ้ามี)';
  static String get promptPayNationalIdHint => en
      ? '13 digits — can replace phone'
      : '13 หลัก — กรอกแทนเบอร์ได้';
  static String get promptPayNationalIdLengthError => en
      ? 'National/tax ID must be 13 digits'
      : 'เลขบัตร/นิติบุคคลต้องมี 13 หลัก';
  static String get acceptPrivacyRequired => en
      ? 'Accept privacy policy and terms (required)'
      : 'ยอมรับนโยบายและข้อกำหนด (จำเป็น)';
  static String get jobNotificationsOptional =>
      en ? 'Receive job notifications (optional)' : 'รับแจ้งเตือนงาน (ไม่บังคับ)';
  static String get submitRegistration =>
      en ? 'Submit application' : 'ส่งคำขอสมัคร';
  static String get pleaseAcceptPrivacyPolicy => en
      ? 'Please accept the privacy policy'
      : 'กรุณายอมรับนโยบายความเป็นส่วนตัว';
  static String get pleaseUploadAllDocuments => en
      ? 'Please upload profile photo and all documents'
      : 'กรุณาอัปโหลดรูปโปรไฟล์และเอกสารให้ครบ';
  static String get pleaseCompleteVehicleInfo => en
      ? 'Please complete vehicle information'
      : 'กรุณากรอกข้อมูลรถให้ครบ';
  static String get pleaseSetPinSixDigits =>
      en ? 'Please set a 6-digit PIN' : 'กรุณาตั้งรหัส PIN 6 หลัก';
  static String get pinMismatch => en ? 'PINs do not match' : 'รหัส PIN ไม่ตรงกัน';
  static String get accountCreationFailed =>
      en ? 'Account creation failed' : 'สร้างบัญชีไม่สำเร็จ';
  static String get registrationFailed =>
      en ? 'Registration failed' : 'สมัครไม่สำเร็จ';
  static String registrationFailedWithError(Object error) =>
      en ? 'Registration failed: $error' : 'สมัครไม่สำเร็จ: $error';
  static String get pleaseCompleteVehicleAndPhotos => en
      ? 'Please complete vehicle info and upload all photos'
      : 'กรุณากรอกข้อมูลรถและอัปโหลดรูปให้ครบ';
  static String get waitForImagePickerClose => en
      ? 'Please wait for the image picker to close, then try again'
      : 'กรุณารอให้หน้าต่างเลือกรูปปิดก่อน แล้วลองใหม่';
  static String pickImageFailed(Object error) =>
      en ? 'Failed to pick image: $error' : 'เลือกรูปไม่สำเร็จ: $error';
  static String get signInBeforeUpload =>
      en ? 'Please sign in before uploading' : 'กรุณาเข้าสู่ระบบก่อนอัปโหลด';
  static String get pinSixDigits => en ? '6-digit PIN' : 'รหัส PIN 6 หลัก';
  static String get confirmPinSixDigits =>
      en ? 'Confirm 6-digit PIN' : 'ยืนยันรหัส PIN 6 หลัก';
  static String get pinUsageHint => en
      ? 'Used to unlock the app and confirm before withdrawals'
      : 'ใช้ปลดล็อกแอป และยืนยันก่อนถอนเงิน';

  static String get editRiderProfile =>
      en ? 'Edit rider profile' : 'แก้ไขโปรไฟล์ไรเดอร์';
  static String get profileIncompleteVan2Hint => en
      ? 'Profile and vehicle info incomplete — customers on van2 will not see you until complete'
      : 'ข้อมูลรถและรูปโปรไฟล์ยังไม่ครบ — ลูกค้า van2 จะไม่เห็นในหน้าเดินทางจนกว่าจะกรอกครบ';
  static String get personalInfoSection => en ? 'Personal info' : 'ข้อมูลส่วนตัว';
  static String get personalInfoCustomerHint => en
      ? 'Shown to customers when booking a ride'
      : 'แสดงให้ลูกค้าเห็นเมื่อจองงานเดินทาง';
  static String get profilePhotoVehicleSection =>
      en ? 'Profile photo and vehicle' : 'รูปโปรไฟล์และข้อมูลรถ';
  static String get profileVan2TravelHint =>
      en ? 'Used on van2 travel screen' : 'van2 ใช้แสดงในหน้าเดินทาง';
  static String get identityDocumentsEditableHint => en
      ? 'Editable anytime — admin may re-verify'
      : 'แก้ไขได้ทุกเมื่อ — แอดมินอาจตรวจสอบใหม่';
  static String get saveProfile => en ? 'Save profile' : 'บันทึกโปรไฟล์';
  static String get profileSavedVan2Visible => en
      ? 'Saved — customers on van2 will see your photo and vehicle info'
      : 'บันทึกแล้ว — ลูกค้า van2 จะเห็นรูปและข้อมูลรถของคุณ';
  static String get profileSavedIncomplete => en
      ? 'Saved — please add profile photo and complete vehicle info'
      : 'บันทึกแล้ว — กรุณาเติมรูปโปรไฟล์และข้อมูลรถให้ครบ';
  static String saveFailedWithError(Object error) =>
      en ? 'Save failed: $error' : 'บันทึกไม่สำเร็จ: $error';
  static String loadProfileFailed(Object error) =>
      en ? 'Failed to load profile: $error' : 'โหลดข้อมูลไม่สำเร็จ: $error';
  static String get noPromptPayForWithdraw => en
      ? 'No PromptPay for withdrawals — tap to add'
      : 'ยังไม่มี PromptPay สำหรับรับเงินถอน — แตะเพื่อกรอก';
  static String get profileCompleteHint => en
      ? 'Photo, vehicle, documents, bank account, and PromptPay'
      : 'รูป ข้อมูลรถ เอกสาร บัญชี และ PromptPay';
  static String get profileIncompleteVan2HintShort => en
      ? 'Missing info used on van2 travel screen — tap to complete'
      : 'ยังขาดข้อมูลที่ van2 ใช้ในหน้าเดินทาง — แตะเพื่อเติม';

  static List<String> get thaiBanks => en
      ? const [
          'Bangkok Bank (BBL)',
          'Kasikorn Bank (KBank)',
          'Siam Commercial Bank (SCB)',
          'Krung Thai Bank (KTB)',
          'Bank of Ayudhya (BAY)',
          'TTB Bank (TTB)',
          'Other',
        ]
      : const [
          'ธนาคารกรุงเทพ (BBL)',
          'ธนาคารกสิกรไทย (KBank)',
          'ธนาคารไทยพาณิชย์ (SCB)',
          'ธนาคารกรุงไทย (KTB)',
          'ธนาคารกรุงศรีอยุธยา (BAY)',
          'ทีเอ็มบีธนชาต (TTB)',
          'อื่นๆ',
        ];

  static String vehicleTypeLabel(String key) {
    switch (key) {
      case 'motorcycle':
        return paymentVehicleMotorcycle;
      case 'sedan':
        return paymentVehicleSedan;
      case 'pickup':
        return paymentVehiclePickup;
      default:
        return key;
    }
  }

  // ---------------------------------------------------------------------------
  // Home / Dashboard
  // ---------------------------------------------------------------------------

  static String get dashboardNewOrders => en ? 'New orders' : 'ออเดอร์ใหม่';
  static String get dashboardNewOrdersSubtitle =>
      en ? 'View pending jobs' : 'ดูงานที่รอรับ';
  static String get dashboardOrderHistory => en ? 'Order history' : 'ประวัติ ออเดอร์';
  static String get dashboardOrderHistorySubtitle =>
      en ? 'In delivery' : 'กำลังจัดส่ง';
  static String get dashboardWallet => en ? 'Wallet' : 'กระเป๋าเงิน';
  static String get dashboardWalletSubtitle =>
      en ? 'Balance' : 'ยอดคงเหลือ';
  static String get dashboardTodayIncome => en ? "Today's earnings" : 'รายได้วันนี้';
  static String get dashboardTodayIncomeSubtitle =>
      en ? 'Daily summary' : 'สรุปรายวัน';
  static String get dashboardNotifications => en ? 'Notifications' : 'การแจ้งเตือน';
  static String get dashboardNotificationsSubtitle =>
      en ? 'Latest job updates' : 'อัปเดตงานล่าสุด';
  static String get dashboardSettings => en ? 'Settings' : 'ตั้งค่า';
  static String get dashboardSettingsSubtitle =>
      en ? 'Profile and system' : 'โปรไฟล์และระบบ';
  static String get enableLocationTitle =>
      en ? 'Enable location' : 'เปิดการใช้งานตำแหน่ง';
  static String get locationPermissionAppSettings => en
      ? 'Please enable location permission in app settings so the system can update your rider coordinates.'
      : 'กรุณาเปิดสิทธิ์ตำแหน่งในตั้งค่าแอป เพื่อให้ระบบอัปเดตพิกัดไรเดอร์ได้';
  static String get locationPermissionEnableGps => en
      ? 'Please enable GPS/Location on your device so coordinates can be retrieved.'
      : 'กรุณาเปิด GPS/Location ของเครื่อง เพื่อให้ระบบดึงพิกัดได้';
  static String get locationPermissionRequest => en
      ? 'Please allow location permission so coordinates can be retrieved.'
      : 'กรุณาอนุญาตสิทธิ์ตำแหน่ง เพื่อให้ระบบดึงพิกัดได้';
  static String get deliveryReadyEnabled =>
      en ? 'Delivery jobs enabled' : 'เปิดรับงานส่งของแล้ว';
  static String get deliveryReadyDisabled =>
      en ? 'Delivery jobs disabled' : 'ปิดรับงานส่งของแล้ว';
  static String get deliveryReadyDisabledPassengerStillOn => en
      ? 'Delivery jobs disabled, but passenger rides are still enabled'
      : 'ปิดรับงานส่งของแล้ว แต่ยังเปิดรับผู้โดยสารอยู่';
  static String get passengerReadyEnabled =>
      en ? 'Passenger rides enabled' : 'เปิดรับงานผู้โดยสารแล้ว';
  static String get passengerReadyDisabled =>
      en ? 'Passenger rides disabled' : 'ปิดรับงานผู้โดยสารแล้ว';
  static String get passengerReadyDisabledDeliveryStillOn => en
      ? 'Passenger rides disabled, but delivery jobs are still enabled'
      : 'ปิดรับงานผู้โดยสารแล้ว แต่ยังเปิดรับส่งของอยู่';
  static String readyEnabledWithLocation(String message) => en
      ? '$message and location saved to the system'
      : '$message และบันทึกพิกัดลงระบบแล้ว';
  static String get enableGpsBeforeReady => en
      ? 'Please enable GPS and allow location permission before going online'
      : 'กรุณาเปิด GPS และอนุญาตสิทธิ์ตำแหน่งก่อนเปิดรับงาน';
  static String firestoreReadySaveFailed(Object error) => en
      ? 'Failed to save status to Firestore: $error'
      : 'บันทึกสถานะลง Firestore ไม่สำเร็จ: $error';
  static String get readyEnabledLocationStreamFailed => en
      ? 'Online status enabled, but real-time location updates failed to start'
      : 'เปิดสถานะรับงานแล้ว แต่เริ่มอัปเดตพิกัดเรียลไทม์ไม่สำเร็จ';
  static String setOnlineFailed(Object error) =>
      en ? 'Unable to set online status: $error' : 'ไม่สามารถตั้งค่าออนไลน์ได้: $error';
  static String get creditLoadFailed => en
      ? 'Unable to load credit (check internet/Firestore)'
      : 'ยังโหลดเครดิตไม่ได้ (ตรวจอินเทอร์เน็ต/Firestore)';
  static String menuReadyPlaceholder(String title) => en
      ? 'Menu "$title" is ready — awaiting system integration'
      : 'เมนู "$title" พร้อมแล้ว รอเชื่อมต่อระบบถัดไป';
  static String get creditMinimumRequired => en
      ? 'Credit must be at least 500 THB to go online — this prevents undelivered orders'
      : 'เครดิตต้องไม่ต่ำกว่า 500 บาท จึงจะเปิดรับงานได้ เพื่อป้องกันการส่งของให้ถึงมือลูกค้า';
  static String get creditNearMinimumTitle =>
      en ? 'Credit near minimum' : 'เครดิตใกล้ถึงขั้นต่ำ';
  static String get creditNearMinimumBody => en
      ? 'Your credit is close to falling below 500 THB. Below 500 THB you cannot go online — this prevents undelivered orders.'
      : 'เครดิตของคุณใกล้ต่ำกว่า 500 บาท หากต่ำกว่า 500 บาท จะไม่สามารถเปิดรับงานได้ เพื่อป้องกันการส่งของให้ถึงมือลูกค้า';
  static String get creditLevel4Ready =>
      en ? 'Level 4 — Ready for jobs' : 'ระดับ 4 พร้อมรับงาน';
  static String get creditLevel3 => en ? 'Level 3' : 'ระดับ 3';
  static String get creditLevel2 => en ? 'Level 2' : 'ระดับ 2';
  static String get creditLevel1NearMin =>
      en ? 'Level 1 — Near minimum' : 'ระดับ 1 ใกล้ขั้นต่ำ';
  static String get creditBelowMinimum =>
      en ? 'Below minimum' : 'ต่ำกว่าขั้นต่ำ';
  static String get todayIncomeTitle => en ? "Today's earnings" : 'รายได้วันนี้';
  static String get todayIncomeSubtitle => en
      ? 'Summary from jobs completed today using data recorded at delivery'
      : 'สรุปจากงานที่ส่งสำเร็จวันนี้และใช้ข้อมูลที่บันทึกตอนปิดงาน';
  static String get todayNetIncomeTotal =>
      en ? "Today's net earnings" : 'รายได้สุทธิรวมวันนี้';
  static String deliveredTodayCount(int count) => en
      ? '$count jobs delivered today'
      : 'ส่งสำเร็จวันนี้ $count งาน';
  static String get last7DaysSummary =>
      en ? 'Last 7 days summary' : 'สรุป 7 วันล่าสุด';
  static String get noIncomeLast7Days => en
      ? 'No earnings data for the last 7 days'
      : 'ยังไม่มีข้อมูลรายได้ย้อนหลัง 7 วันล่าสุด';
  static String deliveredCount(int count) =>
      en ? '$count jobs delivered' : 'ส่งสำเร็จ $count งาน';
  static String get riderNetIncomeToday =>
      en ? "Rider's net delivery earnings today" : 'รายได้ค่าส่งสุทธิของไรเดอร์วันนี้';
  static String get riderCreditRemaining =>
      en ? 'Remaining rider credit' : 'เครดิตไรเดอร์คงเหลือ';
  static String get topUpCredit => en ? 'Top up credit' : 'เติมเครดิต';
  static String get creditBelow500ToggleDisabled => en
      ? 'Credit below 500 THB — job toggle disabled'
      : 'เครดิตต่ำกว่า 500 บาท ปุ่มรับงานจะเปิดไม่ได้';
  static String get jobsAccepted => en ? 'Accepted' : 'งานที่รับแล้ว';
  static String get jobsDelivering => en ? 'Delivering' : 'กำลังส่ง';
  static String get jobsDelivered => en ? 'Delivered' : 'ส่งสำเร็จ';
  static String get acceptDelivery => en ? 'Accept delivery' : 'รับส่งของ';
  static String get disableDelivery => en ? 'Disable delivery' : 'ปิดส่งของ';
  static String get acceptPassenger => en ? 'Accept passengers' : 'รับผู้โดยสาร';
  static String get disablePassenger => en ? 'Disable passengers' : 'ปิดรับผู้โดยสาร';
  static String get locationStreamingActive => en
      ? 'Rider location is updating in real time for enabled job modes'
      : 'พิกัดไรเดอร์กำลังอัปเดตแบบเรียลไทม์สำหรับงานที่เปิดรับอยู่';
  static String get locationStreamingInactive => en
      ? 'Location updates start when you enable delivery or passenger rides'
      : 'พิกัดจะเริ่มอัปเดตเมื่อกดเปิดรับส่งของหรือรับผู้โดยสาร';
  static String get loadingCredit => en ? 'Loading credit...' : 'กำลังโหลดเครดิต...';
  static String get creditBelow500CannotGoOnline => en
      ? 'Credit below 500 THB — cannot go online'
      : 'เครดิตต่ำกว่า 500 บาท ไม่สามารถเปิดรับงานได้';
  static String readyModeSummary(bool deliveryOn, bool passengerOn) => en
      ? 'Delivery: ${deliveryOn ? 'ON' : 'OFF'} | Passengers: ${passengerOn ? 'ON' : 'OFF'}'
      : 'ส่งของ: ${deliveryOn ? 'เปิดรับ' : 'ปิดรับ'} | ผู้โดยสาร: ${passengerOn ? 'เปิดรับ' : 'ปิดรับ'}';

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  static String get settingsTitle => en ? 'Settings' : 'ตั้งค่า';
  static String get profileSection => en ? 'Profile' : 'โปรไฟล์';
  static String get reviewsSection => en ? 'Reviews' : 'รีวิว';
  static String get customerReviews => en ? 'Customer reviews' : 'รีวิวจากลูกค้า';
  static String get customerReviewsHint => en
      ? 'Read-only — customers rate and edit their own reviews'
      : 'อ่านอย่างเดียว — ลูกค้าเป็นผู้ให้คะแนนและแก้ไขรีวิวเอง';
  static String get privacySection => en ? 'Privacy' : 'ความเป็นส่วนตัว';
  static String get privacyAndSecurity =>
      en ? 'Privacy and security' : 'ความเป็นส่วนตัวและความปลอดภัย';
  static String get privacyAndSecuritySubtitle => en
      ? 'Consent, data rights, and notifications'
      : 'ความยินยอม สิทธิข้อมูล และการแจ้งเตือน';
  static String get securitySection => en ? 'Security' : 'ความปลอดภัย';
  static String get biometricUnlock => en ? 'Unlock with fingerprint' : 'ปลดล็อกด้วยลายนิ้วมือ';
  static String get checkingBiometric => en ? 'Checking...' : 'กำลังตรวจสอบ...';
  static String get biometricUnlockHint => en
      ? 'Use before entering the app (after login)'
      : 'ใช้ก่อนเข้าแอป (หลัง login แล้ว)';
  static String get biometricNotAvailable => en
      ? 'Fingerprint unlock is not available on this device'
      : 'เครื่องนี้ยังไม่พร้อมใช้ลายนิ้วมือ';
  static String get setPinBeforeBiometric =>
      en ? 'Please set a 6-digit PIN first' : 'กรุณาตั้งรหัส PIN 6 หลักก่อน';
  static String get biometricVerifyForUnlock => en
      ? 'Verify fingerprint to unlock the app'
      : 'ยืนยันลายนิ้วมือเพื่อปลดล็อกแอป';
  static String get biometricUnlockEnabled => en
      ? 'Fingerprint unlock before entering the app is enabled'
      : 'เปิดปลดล็อกด้วยลายนิ้วมือก่อนเข้าแอปแล้ว';
  static String get biometricUnlockDisabled => en
      ? 'Fingerprint unlock disabled'
      : 'ปิดปลดล็อกด้วยลายนิ้วมือแล้ว';
  static String get helpSection => en ? 'Help' : 'ช่วยเหลือ';
  static String get helpCenter => en ? 'Help center' : 'ศูนย์ช่วยเหลือ';
  static String get helpCenterPreparing =>
      en ? 'Help center (coming soon)' : 'ศูนย์ช่วยเหลือ (กำลังเตรียม)';
  static String get contactAdmin => en ? 'Contact admin' : 'ติดต่อแอดมิน';
  static String get adminMessages => en ? 'Messages to admin' : 'ข้อความถึงแอดมิน';
  static String get adminMessagesSubtitle => en
      ? 'View admin replies and respond'
      : 'ดูคำตอบจากแอดมินและตอบกลับ';
  static String get securityPreparing =>
      en ? 'Security (coming soon)' : 'ความปลอดภัย (กำลังเตรียม)';
  static String get languageSection => en ? 'Language' : 'ตั้งค่าภาษา';
  static String get language => en ? 'Language' : 'ภาษา';
  static String get languagePreparing =>
      en ? 'Language settings (coming soon)' : 'ตั้งค่าภาษา (กำลังเตรียม)';
  static String get chooseLanguage => en ? 'Choose language' : 'เลือกภาษา';

  // ---------------------------------------------------------------------------
  // Wallet
  // ---------------------------------------------------------------------------

  static String get walletTitle => en ? 'Wallet' : 'กระเป๋าเงิน';
  static String get creditBalanceRemaining =>
      en ? 'Remaining credit balance' : 'ยอดเครดิตคงเหลือ';
  static String withdrawableBalance(double amount) => en
      ? 'Withdrawable ${amount.toStringAsFixed(2)} THB'
      : 'ถอนได้ ${amount.toStringAsFixed(2)} บาท';
  static String get withdrawMoney => en ? 'Withdraw' : 'ถอนเงิน';
  static String get creditAndDeliveryHistory =>
      en ? 'Top-up and delivery history' : 'ประวัติเติมเครดิตและค่าส่ง';
  static String get loadHistoryFailed =>
      en ? 'Failed to load history' : 'โหลดประวัติไม่สำเร็จ';
  static String get loadDeliveryHistoryFailed => en
      ? 'Failed to load delivery earnings history'
      : 'โหลดประวัติค่าส่งไม่สำเร็จ';
  static String get creditTopUp => en ? 'Top up credit' : 'เติมเครดิต';
  static String get creditDeduct => en ? 'Credit deducted' : 'หักเครดิต';
  static String get creditDeductPayAtDestination => en
      ? 'Credit deducted (pay-on-delivery job)'
      : 'หักเครดิต (รับงานจ่ายปลายทาง)';
  static String get creditReleasePayAtDestination => en
      ? 'Credit returned (unused • pay on delivery)'
      : 'คืนเครดิต (เลิกใช้แล้ว • รับปลายทาง)';
  static String get riderIncomeAfterGp => en
      ? 'Delivery/ride earnings (after GP)'
      : 'รายได้ค่าส่ง/ค่าโดยสาร (หลังหัก GP)';
  static String get creditTopUpSlipVerified =>
      en ? 'Top up credit (slip verified)' : 'เติมเครดิต (ตรวจสลิป)';
  static String creditTitleWithProvider(String title, String provider) =>
      '$title ($provider)';
  static String get pendingCreditRelease =>
      en ? 'Pending credit release' : 'รอปล่อยเครดิต';
  static String pendingCreditReleaseCod(bool isCod) => en
      ? 'Pending credit release${isCod ? ' (pay on delivery)' : ''}'
      : 'รอปล่อยเครดิต${isCod ? ' (จ่ายปลายทาง)' : ''}';
  static String get netDeliveryIncomePayAtDestination => en
      ? 'Net delivery earnings (pay on delivery)'
      : 'รายได้ค่าส่งสุทธิ (รับปลายทาง)';
  static String cashCollectedThb(double amount) => en
      ? 'Cash collected THB ${amount.toStringAsFixed(1)}'
      : 'เก็บเงินสด THB ${amount.toStringAsFixed(1)}';
  static String orderCashCollected(String orderCode, double amount) => en
      ? 'Order: $orderCode • Cash collected THB ${amount.toStringAsFixed(1)}'
      : 'ออเดอร์: $orderCode • เก็บเงินสด THB ${amount.toStringAsFixed(1)}';
  static String get netDeliveryIncome =>
      en ? 'Net delivery earnings' : 'รายได้ค่าส่งสุทธิ';
  static String get jobDeliveredSuccess => en ? 'Job delivered' : 'งานส่งสำเร็จ';
  static String get todayNetIncome =>
      en ? "Today's net earnings" : 'รายได้สุทธิของวัน';
  static String get noPinOnDeviceForWithdraw => en
      ? 'No PIN on this device — set PIN in profile before withdrawing'
      : 'ยังไม่มีรหัส PIN บนเครื่องนี้ — ตั้ง PIN ในเมนูโปรไฟล์ก่อนถอนเงิน';
  static String get confirmBeforeWithdraw =>
      en ? 'Confirm before withdrawal' : 'ยืนยันก่อนถอนเงิน';
  static String withdrawRequestSubmitted(double amount) => en
      ? 'Withdrawal request for ${amount.toStringAsFixed(2)} THB submitted — transferring to account'
      : 'ส่งคำขอถอน ${amount.toStringAsFixed(2)} บาท — กำลังโอนเข้าบัญชี';
  static String get openWithdrawFailed => en
      ? 'Unable to open withdrawal screen — try again'
      : 'เปิดหน้าถอนเงินไม่สำเร็จ — ลองอีกครั้ง';
  static String get withdrawTitle => en ? 'Withdraw' : 'ถอนเงิน';
  static String get loadWithdrawBalanceFailed =>
      en ? 'Failed to load withdrawable balance' : 'โหลดยอดถอนไม่สำเร็จ';
  static String loadWithdrawBalanceFailedWithError(Object error) =>
      en ? 'Failed to load withdrawable balance: $error' : 'โหลดยอดถอนไม่สำเร็จ: $error';
  static String get pleaseSelectAmount =>
      en ? 'Please select an amount' : 'กรุณาเลือกจำนวนเงิน';
  static String get withdrawFailed => en ? 'Withdrawal failed' : 'ถอนเงินไม่สำเร็จ';
  static String withdrawFailedWithError(Object error) =>
      en ? 'Withdrawal failed: $error' : 'ถอนเงินไม่สำเร็จ: $error';
  static String get registeredPayoutChannels =>
      en ? 'Registered payout channels' : 'ช่องทางรับเงินที่ลงทะเบียน';
  static String promptPayChannel(String label) => 'PromptPay: $label';
  static String bankChannel(String label) => en ? 'Bank: $label' : 'ธนาคาร: $label';
  static String get withdrawAdminProcessHint => en
      ? 'Admin will choose transfer channel (PromptPay or bank) and confirm with slip within 1–2 business days'
      : 'แอดมินจะเลือกช่องทางโอน (PromptPay หรือบัญชีธนาคาร) และยืนยันด้วยสลิปภายใน 1–2 วันทำการ';
  static String get noPromptPayGoProfile => en
      ? 'No PromptPay — go to Settings > Edit rider profile to add a bank-linked number'
      : 'ยังไม่มี PromptPay — ไป ตั้งค่า > แก้ไขโปรไฟล์ไรเดอร์ เพื่อกรอกเบอร์ที่ผูกกับบัญชีธนาคาร';
  static String get addPromptPayOrBankInProfile => en
      ? 'Please add PromptPay or bank account in Settings > Edit rider profile'
      : 'กรุณาเพิ่ม PromptPay หรือบัญชีธนาคารใน ตั้งค่า > แก้ไขโปรไฟล์ไรเดอร์';
  static String withdrawFeePerTime(double fee) => en
      ? 'Withdrawal fee ${fee.toStringAsFixed(0)} THB/time (deducted from requested amount)'
      : 'ค่าบริการถอน ${fee.toStringAsFixed(0)} บาท/ครั้ง (หักจากยอดที่ขอถอน)';
  static String enterWithdrawAmountHint(double min) => en
      ? 'Enter amount from wallet (minimum ${min.toStringAsFixed(0)} THB)'
      : 'ระบุจำนวนเงินจากกระเป๋า (ขั้นต่ำ ${min.toStringAsFixed(0)} บาท)';
  static String netReceiveAfterFee(double net, double fee) => en
      ? 'You receive ${net.toStringAsFixed(2)} THB (after ${fee.toStringAsFixed(0)} THB fee)'
      : 'ได้รับ ${net.toStringAsFixed(2)} บาท (หลังหักค่าบริการ ${fee.toStringAsFixed(0)} บาท)';
  static String get noWithdrawableBalance =>
      en ? 'No withdrawable balance' : 'ไม่มียอดที่ถอนได้';
  static String withdrawMinimumHint(double min, double grossMin) => en
      ? 'Minimum withdrawal ${min.toStringAsFixed(0)} THB (after fee) — wallet must have at least ${grossMin.toStringAsFixed(0)} THB'
      : 'ยอดถอนขั้นต่ำ ${min.toStringAsFixed(0)} บาท (หลังหักค่าบริการ) — ต้องมีในกระเป๋าอย่างน้อย ${grossMin.toStringAsFixed(0)} บาท';
  static String get confirmWithdraw => en ? 'Confirm withdrawal' : 'ยืนยันถอน';

  static String get topUpTitle => en ? 'Top up credit' : 'เติมเครดิต';
  static String get selectAmount => en ? 'Select amount' : 'เลือกจำนวนเงิน';
  static String topUpMaxPerTime(double max) => en
      ? 'Max ${max.toStringAsFixed(0)} THB per top-up · up to 3 slip submissions per day'
      : 'สูงสุด ${max.toStringAsFixed(0)} บาทต่อครั้ง · ส่งสลิปได้ไม่เกิน 3 ครั้งต่อวัน';
  static String get customAmount => en ? 'Custom amount' : 'กำหนดเอง';
  static String customAmountHint(double max) => en
      ? 'e.g. 1500 (max ${max.toStringAsFixed(0)})'
      : 'เช่น 1500 (สูงสุด ${max.toStringAsFixed(0)})';
  static String get selectAmountForQr =>
      en ? 'Select an amount to generate QR' : 'กรุณาเลือกจำนวนเงินเพื่อสร้าง QR';
  static String transferToRecipient(String name) =>
      en ? 'Transfer to $name' : 'โอนให้ $name';
  static String get invalidPromptPayId =>
      en ? 'Invalid PromptPay ID' : 'PromptPay ID ไม่ถูกต้อง';
  static String get saveQrToDevice => en ? 'Save QR to device' : 'บันทึก QR ลงเครื่อง';
  static String get attachSlip => en ? 'Attach slip' : 'แนบสลิป';
  static String get submitSlipForReview =>
      en ? 'Submit slip for verification' : 'ส่งสลิปเพื่อตรวจสอบ';
  static String get slipReviewResult =>
      en ? 'Slip verification result' : 'ผลตรวจสลิป';
  static String get createRemainingQr =>
      en ? 'Create QR for remaining balance' : 'สร้าง QR ยอดคงเหลือ';
  static String get slipVerifyFailed =>
      en ? 'Slip verification failed' : 'ตรวจสลิปไม่สำเร็จ';
  static String slipVerifyFailedWithError(Object error) =>
      en ? 'Slip verification failed: $error' : 'ตรวจสลิปไม่สำเร็จ: $error';
  static String get remainingQrCreated =>
      en ? 'QR for remaining balance created' : 'สร้าง QR สำหรับยอดคงเหลือเรียบร้อย';
  static String topUpVerifiedAmount(double amount) => en
      ? 'Credit top-up ${amount.toStringAsFixed(2)} THB'
      : 'เติมเครดิต ${amount.toStringAsFixed(2)} บาท';
  static String remainingToPay(double amount) => en
      ? 'Remaining to pay ${amount.toStringAsFixed(2)} THB'
      : 'คงเหลือต้องจ่ายอีก ${amount.toStringAsFixed(2)} บาท';
  static String overpaidTopUp(double amount) => en
      ? 'Overpaid ${amount.toStringAsFixed(2)} THB (credited at paid amount)'
      : 'จ่ายเกิน ${amount.toStringAsFixed(2)} บาท (ระบบเติมตามยอดที่จ่าย)';
  static String get saveQrWebUnsupported =>
      en ? 'Saving QR on web is not supported' : 'บันทึก QR บน Web ยังไม่รองรับ';
  static String get noQrToSave => en ? 'No QR to save' : 'ยังไม่มี QR สำหรับบันทึก';
  static String get galleryPermissionDenied => en
      ? 'Photo/storage permission denied'
      : 'ไม่ได้รับสิทธิ์เข้าถึงรูปภาพ/พื้นที่จัดเก็บ';
  static String get galleryPermissionRequestFailed => en
      ? 'Unable to request photo permission'
      : 'ไม่สามารถขอสิทธิ์เข้าถึงรูปภาพได้';
  static String get saveQrFailed => en ? 'Failed to save QR' : 'บันทึก QR ไม่สำเร็จ';
  static String get saveQrSuccess =>
      en ? 'QR saved to device' : 'บันทึก QR ลงเครื่องเรียบร้อย';
  static String saveQrFailedWithError(Object error) =>
      en ? 'Failed to save QR: $error' : 'บันทึก QR ไม่สำเร็จ: $error';
  static String get attachSlipWebUnsupported =>
      en ? 'Attaching slips on web is not supported' : 'แนบสลิปบน Web ยังไม่รองรับ';
  static String get selectAmountBeforeSlip => en
      ? 'Please select an amount first'
      : 'กรุณาเลือกจำนวนเงินก่อน';
  static String selectSlipFailed(Object error) =>
      en ? 'Failed to select slip: $error' : 'เลือกสลิปไม่สำเร็จ: $error';
  static String get selectSlipImageFirst =>
      en ? 'Please select a slip image first' : 'กรุณาเลือกรูปสลิปก่อน';
  static String topUpMaxExceeded(double max) => en
      ? 'Maximum top-up ${max.toStringAsFixed(0)} THB per transaction'
      : 'ยอดเติมสูงสุด ${max.toStringAsFixed(0)} บาทต่อครั้ง';
  static String get pickSlipFromGallery =>
      en ? 'Choose from gallery' : 'เลือกจากแกลเลอรี';
  static String get changeSlipImage => en ? 'Change slip image' : 'เปลี่ยนรูปสลิป';
  static String attachPhotosCount(int count, int max) =>
      en ? 'Attach photos ($count/$max)' : 'แนบรูป ($count/$max)';

  static String get receiveMoney => en ? 'Receive money' : 'รับเงิน';
  static String get receiveMoneyHint => en
      ? 'Let customer scan QR or enter your UID'
      : 'ให้ลูกค้าสแกน QR หรือกรอก UID ของคุณ';
  static String get payMoney => en ? 'Pay' : 'จ่ายเงิน';
  static String get payMoneyHint => en
      ? 'Enter recipient UID and amount'
      : 'กรอก UID ปลายทางและจำนวนเงิน';
  static String get transferMoney => en ? 'Transfer' : 'โอนเงิน';
  static String get transferMoneyHint => en
      ? 'Enter recipient UID and amount'
      : 'กรอก UID ปลายทางและจำนวนเงิน';

  // ---------------------------------------------------------------------------
  // Orders — incoming, jobs, scanner, workflow
  // ---------------------------------------------------------------------------

  static String get confirmCreditDeduct =>
      en ? 'Confirm credit deduction' : 'ยืนยันหักเครดิต';
  static String confirmCreditDeductBody(
    String paymentLabel,
    double holdAmount,
    double currentCredit,
  ) =>
      en
          ? 'This order is "$paymentLabel"\n'
              'Your credit will be deducted by ${holdAmount.toStringAsFixed(2)} THB when you accept\n\n'
              'Current credit: ${currentCredit.toStringAsFixed(2)} THB'
          : 'ออเดอร์นี้เป็น "$paymentLabel"\n'
              'ระบบจะหักเครดิตของคุณ $holdAmount บาท เมื่อกดรับงาน\n\n'
              'เครดิตปัจจุบัน: ${currentCredit.toStringAsFixed(2)} บาท';
  static String get confirmAcceptJob =>
      en ? 'Confirm accept job' : 'ยืนยันรับงาน';
  static String get insufficientCredit =>
      en ? 'Insufficient credit' : 'เครดิตไม่พอ';
  static String insufficientCreditBody(
    String paymentLabel,
    double holdAmount,
    double currentCredit,
  ) =>
      en
          ? 'This order is "$paymentLabel"\n'
              'At least ${holdAmount.toStringAsFixed(2)} THB credit is required to accept\n\n'
              'Current credit: ${currentCredit.toStringAsFixed(2)} THB\n\n'
              'Please top up credit or reject this job'
          : 'ออเดอร์นี้เป็น "$paymentLabel"\n'
              'ต้องใช้เครดิตอย่างน้อย $holdAmount บาทเพื่อรับงาน\n\n'
              'เครดิตปัจจุบัน: ${currentCredit.toStringAsFixed(2)} บาท\n\n'
              'กรุณาเติมเครดิตกับไลด์เดอร์ก่อน หรือปฏิเสธงานนี้';
  static String get rejectJob => en ? 'Reject job' : 'ปฏิเสธงาน';
  static String get loadOrderDetailsFailed => en
      ? 'Failed to load order details'
      : 'โหลดรายละเอียดออเดอร์ไม่สำเร็จ';
  static String loadOrderDetailsFailedWithError(Object error) => en
      ? 'Failed to load order details\n$error'
      : 'โหลดรายละเอียดออเดอร์ไม่สำเร็จ\n$error';
  static String get pickupNotFound => en ? 'Pickup not found' : 'ไม่พบจุดรับ';
  static String get shopNameNotFound => en ? 'Shop name not found' : 'ไม่พบชื่อร้าน';
  static String get distanceToPickup => en ? 'Distance to pickup' : 'ระยะถึงจุดรับ';
  static String get distanceToShop => en ? 'Distance to shop' : 'ระยะถึงร้าน';
  static String get dropoffPoint => en ? 'Drop-off' : 'จุดส่ง';
  static String get destination => en ? 'Destination' : 'ปลายทาง';
  static String get pickupMap => en ? 'Pickup map' : 'แผนที่จุดรับ';
  static String get shopMap => en ? 'Shop map' : 'แผนที่ร้านค้า';
  static String get destinationMap => en ? 'Destination map' : 'แผนที่ปลายทาง';
  static String get customerMap => en ? 'Customer map' : 'แผนที่ลูกค้า';
  static String get travelDetailsSection =>
      en ? 'Trip details' : 'รายละเอียดการเดินทาง';
  static String get productListSection => en ? 'Items' : 'รายการสินค้า';
  static String get newTravelJob => en ? 'New ride job' : 'งานเดินทางใหม่';
  static String newTravelJobWithCode(String code) =>
      en ? 'New ride job $code' : 'งานเดินทางใหม่ $code';
  static String get newOrder => en ? 'New order' : 'ออเดอร์ใหม่';
  static String newOrderWithCode(String code) =>
      en ? 'New order $code' : 'ออเดอร์ใหม่ $code';
  static String pickupPoint(String label) => en ? 'Pickup: $label' : 'จุดรับ: $label';
  static String dropoffPointWithLabel(String label) =>
      en ? 'Drop-off: $label' : 'จุดส่ง: $label';
  static String destinationWithLabel(String label) =>
      en ? '$destination: $label' : '$destination: $label';
  static String vehicleTypeWithLabel(String label) =>
      en ? 'Vehicle: $label' : 'ประเภทรถ: $label';
  static String scheduleWithLabel(String label) =>
      en ? 'Trip time: $label' : 'เวลาเดินทาง: $label';
  static String get callCustomer => en ? 'Call customer' : 'โทรลูกค้า';
  static String get chatCustomer => en ? 'Chat customer' : 'แชตลูกค้า';
  static String get callShop => en ? 'Call shop' : 'โทรร้านค้า';
  static String get chatShop => en ? 'Chat shop' : 'แชตร้านค้า';
  static String get noProductDetails =>
      en ? 'No item details found' : 'ไม่พบรายละเอียดสินค้า';
  static String get declineJob => en ? 'Decline job' : 'ไม่รับงาน';
  static String get acceptJob => en ? 'Accept job' : 'รับงาน';
  static String get savingJob => en ? 'Saving...' : 'กำลังบันทึก...';
  static String get jobAccepted => en ? 'Job accepted' : 'รับงานเรียบร้อย';
  static String get acceptJobFailed => en ? 'Failed to accept job' : 'รับงานไม่สำเร็จ';
  static String acceptJobFailedWithError(Object error) =>
      en ? 'Failed to accept job: $error' : 'รับงานไม่สำเร็จ: $error';
  static String get orderTakenByOtherRider => en
      ? 'This order was already accepted by another rider'
      : 'ออเดอร์นี้ถูกรับโดยไรเดอร์คนอื่นแล้ว';
  static String get findingNewRiderTitle =>
      en ? 'Finding a new rider' : 'กำลังหาไรเดอร์ใหม่';
  static String get findingNewRiderBody => en
      ? 'Rider declined — searching for a new rider'
      : 'ไรเดอร์ปฏิเสธงาน ระบบกำลังค้นหาไรเดอร์ให้ใหม่';
  static String get riderDeclinedJobTitle =>
      en ? 'Rider declined job' : 'ไรเดอร์ปฏิเสธงาน';
  static String riderDeclinedJobBody(String suffix) => en
      ? 'Order$suffix — rider declined, searching for another rider'
      : 'ออเดอร์$suffix ไรเดอร์ปฏิเสธงาน ระบบกำลังหาไรเดอร์ใหม่';
  static String get cancelAcceptFindingOther => en
      ? 'Acceptance cancelled — finding another driver'
      : 'ยกเลิกการรับงานแล้ว ระบบจะหาคนขับคนอื่นต่อ';
  static String get declinedFindingOther => en
      ? 'Job declined — finding another driver'
      : 'ไม่รับงานแล้ว ระบบจะหาคนขับคนอื่นต่อ';
  static String get updateStatusFailed =>
      en ? 'Failed to update status' : 'อัปเดตสถานะไม่สำเร็จ';
  static String updateStatusFailedWithError(Object error) =>
      en ? 'Failed to update status: $error' : 'อัปเดตสถานะไม่สำเร็จ: $error';
  static String get cannotOpenMap =>
      en ? 'Unable to open map' : 'ไม่สามารถเปิดแผนที่ได้';
  static String get riderAcceptedJobTitle =>
      en ? 'Rider accepted job' : 'ไรเดอร์รับงานแล้ว';
  static String riderAcceptedJobBody(String suffix) => en
      ? 'Order$suffix has been accepted by a rider'
      : 'ออเดอร์$suffix มีไรเดอร์รับงานแล้ว';

  static String get newJobsTitle => en ? 'New jobs' : 'รับงานใหม่';
  static String get orderHistoryTitle => en ? 'Order history' : 'ประวัติ ออเดอร์';
  static String get noDeliveredHistory => en
      ? 'No completed order history yet'
      : 'ยังไม่มีประวัติออเดอร์ที่ส่งสำเร็จ';
  static String get noAcceptedJobsNow => en
      ? 'No accepted jobs right now'
      : 'ยังไม่มีงานที่รับแล้วในตอนนี้';
  static String get loadJobsFailedPermission => en
      ? 'Failed to load jobs: no permission to read orders from Firebase\n(permission-denied)\n\nDeploy Firestore rules from van2 and try again'
      : 'โหลดงานไม่สำเร็จ: ไม่มีสิทธิ์อ่านออเดอร์จาก Firebase\n(permission-denied)\n\nให้ deploy Firestore rules จาก van2 แล้วลองใหม่';
  static String loadJobsFailedWithError(String message) =>
      en ? 'Failed to load jobs: $message' : 'โหลดงานไม่สำเร็จ: $message';
  static String get scanQr => en ? 'Scan QR' : 'สแกนคิวอาร์';
  static String get captureDeliveryProof =>
      en ? 'Capture delivery proof photo' : 'ถ่ายรูปยืนยันส่งถึงมือลูกค้า';
  static String shopLabel(String name) => en ? 'Shop: $name' : 'ร้าน: $name';
  static String pickupLabel(String label) => en ? 'Pickup: $label' : 'จุดรับ: $label';
  static String orderStatus(String status) => en ? 'Status: $status' : 'สถานะ: $status';
  static String cashCollectedLabel(double amount) => en
      ? 'Cash collected: THB ${amount.toStringAsFixed(1)}'
      : 'เก็บเงินสด: THB ${amount.toStringAsFixed(1)}';
  static String riderNetIncomeLabel(double amount) => en
      ? 'Net delivery earnings: THB ${amount.toStringAsFixed(1)}'
      : 'รายได้ค่าส่งสุทธิ: THB ${amount.toStringAsFixed(1)}';
  static String get deliveredAt => en ? 'Delivered at' : 'ส่งสำเร็จเมื่อ';
  static String deliveredAtValue(String? text) =>
      en ? 'Delivered at: ${text ?? '-'}' : 'ส่งสำเร็จเมื่อ: ${text ?? '-'}';
  static String get riderNetIncomeShort =>
      en ? 'Rider net earnings' : 'รายได้สุทธิไรเดอร์';
  static String get distanceToPickupDash =>
      en ? 'Distance to pickup: -' : 'ระยะทางไรเดอร์ถึงจุดรับ: -';
  static String get distanceToShopDash =>
      en ? 'Distance to shop: -' : 'ระยะทางไรเดอร์ถึงร้าน: -';
  static String distanceToPickupKm(double km) => en
      ? 'Distance to pickup: ${km.toStringAsFixed(2)} km'
      : 'ระยะทางไรเดอร์ถึงจุดรับ: ${km.toStringAsFixed(2)} km';
  static String distanceToShopKm(double km) => en
      ? 'Distance to shop: ${km.toStringAsFixed(2)} km'
      : 'ระยะทางไรเดอร์ถึงร้าน: ${km.toStringAsFixed(2)} km';
  static String get passengerService =>
      en ? 'Passenger ride service' : 'บริการรับส่งผู้โดยสาร';
  static String get arrivedAtPickup => en ? 'Arrived at pickup' : 'ถึงจุดรับแล้ว';
  static String get startTrip => en ? 'Start trip' : 'เริ่มเดินทาง';
  static String get arrivedAtDestination =>
      en ? 'Arrived at destination' : 'ถึงจุดหมายปลายทาง';
  static String last7DaysNetIncome(double amount) => en
      ? 'Total net THB ${amount.toStringAsFixed(1)}'
      : 'รายได้สุทธิรวม THB ${amount.toStringAsFixed(1)}';
  static String get reviewService => en ? 'Service review' : 'รีวิวการให้บริการ';

  static String scanQrForOrder(String code) =>
      en ? 'Scan QR $code' : 'สแกนคิวอาร์ $code';
  static String get scanQrOrder => en ? 'Scan order QR' : 'สแกนคิวอาร์ออเดอร์';
  static String get scanQrTitle => en ? 'Scan QR code' : 'สแกนคิวอาร์โค้ด';
  static String get alignCameraWithQr =>
      en ? 'Align camera with QR code' : 'วางกล้องตรงกับ QR Code';
  static String get scanQrInstructions => en
      ? 'Scan order QR to pick up items\nScan the same QR again after delivery'
      : 'สแกน QR ออเดอร์เพื่อรับสินค้า\nและสแกน QR เดิมอีกครั้งเมื่อส่งสำเร็จ';
  static String get invalidQrCode => en ? 'Invalid QR code' : 'QR Code ไม่ถูกต้อง';
  static String errorOccurred(Object error) =>
      en ? 'An error occurred: $error' : 'เกิดข้อผิดพลาด: $error';
  static String get orderNotFound => en ? 'Order not found' : 'ไม่พบออเดอร์นี้';
  static String orderQrNotAvailableForStatus(String status) => en
      ? 'Single QR not available for this order yet (status: $status)'
      : 'ออเดอร์นี้ยังใช้ QR เดียวไม่ได้ (สถานะ: $status)';
  static String get orderNotAssignedToYou => en
      ? 'This order is not assigned to you'
      : 'ออเดอร์นี้ไม่ได้รับโดยคุณ';
  static String orderNotReadyToDeliver(String status) => en
      ? 'Order not ready to start delivery (status: $status)'
      : 'ออเดอร์นี้ยังไม่พร้อมเริ่มส่ง (สถานะ: $status)';
  static String get deliveryStarted => en ? 'Delivery started' : 'เริ่มจัดส่งแล้ว';
  static String get scanAgainToComplete => en
      ? 'When you reach the customer, scan the same order QR again to complete'
      : 'เมื่อถึงลูกค้าแล้ว ให้สแกน QR ออเดอร์เดิมอีกครั้งเพื่อปิดงาน';
  static String orderNotDelivering(String status) => en
      ? 'Order is not in delivery (status: $status)'
      : 'ออเดอร์นี้ยังไม่ได้อยู่ระหว่างจัดส่ง (สถานะ: $status)';
  static String get deliveryCompleted => en ? 'Delivery completed' : 'ส่งสำเร็จ';
  static String get deliveryJobClosed =>
      en ? 'Delivery job closed successfully' : 'ปิดงานจัดส่งเรียบร้อยแล้ว';
  static String get qrMismatchTitle =>
      en ? 'QR data mismatch' : 'ข้อมูล QR ไม่ตรงกัน';
  static String get qrOrderIdMismatch =>
      en ? 'Order ID mismatch' : 'ออเดอร์ไอดีไม่ตรงกัน';
  static String get qrOrderCodeMismatch =>
      en ? 'Order code mismatch' : 'หมายเลขออเดอร์ไม่ตรงกัน';
  static String get qrTotalMismatch =>
      en ? 'Total amount mismatch' : 'ยอดรวมไม่ตรงกัน';

  static String get workflowShopReady =>
      en ? 'Shop is ready' : 'ร้านพร้อมส่งแล้ว';
  static String get workflowArrivedShop =>
      en ? 'Arrived at shop' : 'ถึงร้านแล้ว';
  static String get workflowDeliveryStarted =>
      en ? 'Delivery started' : 'เริ่มจัดส่งแล้ว';
  static String get workflowArrivedCustomer =>
      en ? 'Arrived at customer' : 'ถึงลูกค้าแล้ว';
  static String get workflowGoPickupShop =>
      en ? 'You can pick up at the shop now' : 'ไปรับสินค้าที่ร้านได้แล้ว';
  static String get workflowScanQrPickup => en
      ? 'Scan order QR to confirm pickup from shop'
      : 'สแกน QR ออเดอร์เพื่อยืนยันรับสินค้าจากร้าน';
  static String get workflowDeliverToCustomer => en
      ? 'Deliver items to customer using the map'
      : 'นำสินค้าไปส่งลูกค้าตามแผนที่';
  static String get workflowPhotoProof => en
      ? 'Take a photo to confirm handoff to customer'
      : 'ถ่ายรูปยืนยันการส่งถึงมือลูกค้า';
  static String get laterAction => en ? 'Later' : 'ทีหลัง';
  static String get goPickupNow => en ? 'Pick up now' : 'ไปรับเลย';
  static String get photoOnArrival => en ? 'Photo on arrival' : 'ถ่ายรูปเมื่อถึง';

  static String get mustBeDeliveringForPhoto => en
      ? 'Order must be delivering before you can capture delivery proof'
      : 'ต้องเป็นสถานะกำลังส่งก่อน จึงจะถ่ายรูปยืนยันการส่งได้';
  static String get confirmDeliveryPhotoTitle =>
      en ? 'Confirm delivery photo' : 'ยืนยันรูปส่งสำเร็จ';
  static String get confirmDeliveryPhotoBody => en
      ? 'Review the photo before confirming — the order will be marked delivered immediately'
      : 'ตรวจสอบรูปก่อนยืนยัน ระบบจะอัปเดตออเดอร์เป็นส่งสำเร็จทันที';
  static String get confirmDelivered => en ? 'Confirm delivered' : 'ยืนยันส่งสำเร็จ';
  static String get photoProofSavedPendingRelease => en
      ? 'Delivery proof saved — credit release pending admin schedule'
      : 'บันทึกรูปยืนยันแล้ว — รอปล่อยเครดิตตามเวลาที่แอดมินกำหนด';
  static String get photoProofSavedDelivered => en
      ? 'Delivery proof saved and order marked delivered'
      : 'บันทึกรูปยืนยันและอัปเดตสถานะส่งสำเร็จแล้ว';
  static String get uploadBlockedRetry => en
      ? 'Firebase blocked photo upload — please try again'
      : 'Firebase บล็อกการอัปโหลดรูป กรุณาลองใหม่อีกครั้ง';
  static String saveDeliveryProofFailed(Object error) => en
      ? 'Failed to save delivery proof: $error'
      : 'บันทึกรูปยืนยันไม่สำเร็จ: $error';
  static String get arrivedPickupStartTripHint => en
      ? 'Marked arrived at pickup — tap "Start trip" when passenger boards'
      : 'บันทึกถึงจุดรับแล้ว — กด "เริ่มเดินทาง" เมื่อผู้โดยสารขึ้นรถ';
  static String get tripStartedArriveHint => en
      ? 'Trip started — tap "Arrived at destination" when passenger is dropped off'
      : 'เริ่มเดินทางแล้ว — กด "ถึงจุดหมายปลายทาง" เมื่อส่งผู้โดยสารถึงที่หมาย';
  static String get orderNotYours => en ? 'This order is not yours' : 'ออเดอร์นี้ไม่ได้รับโดยคุณ';
  static String cannotCompleteInStatus(String status) =>
      en ? 'Cannot complete in status $status' : 'ไม่สามารถปิดงานได้ในสถานะ $status';
  static String get passengerArrivedPendingRelease => en
      ? 'Passenger dropped off — credit release pending admin schedule'
      : 'ส่งผู้โดยสารถึงจุดหมายแล้ว — รอปล่อยเครดิตตามเวลาที่แอดมินกำหนด';
  static String get passengerArrivedPendingPayout => en
      ? 'Passenger dropped off — fare payout after GP per admin schedule'
      : 'ส่งผู้โดยสารถึงจุดหมายแล้ว — รอระบบโอนค่าโดยสารหลังหัก GP ตามที่แอดมินกำหนด';
  static String completeJobFailed(Object error) =>
      en ? 'Failed to complete job: $error' : 'ปิดงานไม่สำเร็จ: $error';
  static String cannotUpdateInStatus(String status) =>
      en ? 'Cannot update in status $status' : 'ไม่สามารถอัปเดตได้ในสถานะ $status';
  static String get confirmDestinationArrivalTitle => en
      ? 'Confirm destination arrival'
      : 'ยืนยันถึงจุดหมายปลายทาง';
  static String confirmDestinationArrivalCod(String fareLabel) => en
      ? 'Confirm passenger dropped off\n'
          'Payment: pay on delivery (collect $fareLabel THB cash from customer)\n'
          'Net fare (after GP) will be credited after admin release schedule'
      : 'ยืนยันว่าส่งผู้โดยสารถึงปลายทางแล้ว\n'
          'การชำระ: จ่ายปลายทาง (รับเงินสด $fareLabel บาทจากลูกค้า)\n'
          'ค่าโดยสารสุทธิ (หลังหัก GP) จะเข้าเครดิตหลังครบเวลาที่แอดมินกำหนด';
  static String confirmDestinationArrival(String fareLabel) => en
      ? 'Confirm passenger dropped off\n'
          'Fare $fareLabel THB will be transferred after GP per admin schedule'
      : 'ยืนยันว่าส่งผู้โดยสารถึงปลายทางแล้ว\n'
          'ค่าโดยสาร $fareLabel บาท จะรอโอนให้หลังหัก GP ตามที่แอดมินกำหนด';
  static String get confirmArrivedDestination =>
      en ? 'Confirm arrival' : 'ยืนยันถึงปลายทาง';

  static String get pickupPointShort => en ? 'Pickup' : 'จุดรับ';
  static String get yourLocation => en ? 'Your location' : 'ตำแหน่งของคุณ';
  static String get routeToPickupPassenger => en
      ? 'Route to passenger pickup'
      : 'เส้นทางไปจุดรับผู้โดยสาร';
  static String get routePickupToDestination => en
      ? 'Route from pickup to destination'
      : 'เส้นทางจากจุดรับไปปลายทาง';
  static String etaArrivalEstimate(String target, int minutes, String time) =>
      en
          ? 'About $minutes min to $target (approx. $time)'
          : 'ถึง$targetประมาณ $minutes นาที (โดยประมาณ $time น.)';
  static String get updatingRoute =>
      en ? 'Updating route...' : 'กำลังอัปเดตเส้นทาง...';
  static String get shopReadyChannelName =>
      en ? 'Shop ready' : 'ร้านพร้อมส่ง';
  static String get shopReadyChannelDesc => en
      ? 'Notifies when the shop finished preparing the order'
      : 'แจ้งเตือนเมื่อร้านค้าเตรียมสินค้าเสร็จแล้ว';
  static String get shopPreparedTitle =>
      en ? 'Shop finished preparing' : 'ร้านเตรียมสินค้าเสร็จแล้ว';
  static String get shopReadyForPickupBody =>
      en ? 'Ready for rider pickup' : 'พร้อมให้ไรเดอร์รับสินค้า';
  static String orderHashLabel(String code) =>
      en ? 'Order #$code' : 'ออเดอร์ #$code';

  // ---------------------------------------------------------------------------
  // Chat / Call
  // ---------------------------------------------------------------------------

  static String chatWith(String peer, {String? orderSuffix}) =>
      en ? 'Chat with $peer$orderSuffix' : 'แชตกับ $peer$orderSuffix';
  static String get voiceCallTooltip => en ? 'Voice call' : 'โทรด้วยเสียง';
  static String get videoCallTooltip => en ? 'Video call' : 'วิดีโอคอล';
  static String get regularCallTooltip => en ? 'Phone call' : 'โทรปกติ';
  static String get peerPhoneNotFound =>
      en ? 'Chat partner phone not found' : 'ไม่พบเบอร์โทรของคู่แชท';
  static String get cannotPlaceCall =>
      en ? 'Unable to place call' : 'ไม่สามารถโทรออกได้';
  static String startCallFailed(Object error) =>
      en ? 'Failed to start call: $error' : 'เริ่มการโทรไม่สำเร็จ: $error';
  static String sendMessageFailed(Object error) =>
      en ? 'Failed to send message: $error' : 'ส่งข้อความไม่สำเร็จ: $error';
  static String uploadFileFailed(Object error) =>
      en ? 'Failed to upload file: $error' : 'อัปโหลดไฟล์ไม่สำเร็จ: $error';
  static String get pickFromGallery =>
      en ? 'Choose from gallery' : 'เลือกรูปจากคลังภาพ';
  static String get takePhoto => en ? 'Take photo' : 'ถ่ายรูป';
  static String get pickVideo => en ? 'Choose video' : 'เลือกวิดีโอ';
  static String get pickDocument => en ? 'Choose document' : 'เลือกไฟล์เอกสาร';
  static String get sentImage => en ? 'Sent an image' : 'ส่งรูปภาพ';
  static String get sentVideo => en ? 'Sent a video' : 'ส่งวิดีโอ';
  static String sentFile(String fileName) =>
      en ? 'Sent file $fileName' : 'ส่งไฟล์ $fileName';
  static String get videoFile => en ? 'Video file' : 'ไฟล์วิดีโอ';
  static String get attachmentFile => en ? 'Attachment' : 'ไฟล์แนบ';
  static String get startConversation =>
      en ? 'Start the conversation' : 'เริ่มสนทนาได้เลย';
  static String loadChatFailed(Object error) =>
      en ? 'Failed to load chat: $error' : 'โหลดแชตไม่สำเร็จ: $error';
  static String get typeMessageHint => en ? 'Type a message...' : 'พิมพ์ข้อความ...';
  static String get cannotStartChatWithSelf => en
      ? 'Cannot start chat with your own account'
      : 'ไม่สามารถเริ่มแชทกับบัญชีตัวเองได้';
  static String startChatRoomFailed(Object error) => en
      ? 'Unable to start chat room: $error'
      : 'ไม่สามารถเริ่มห้องแชทได้: $error';
  static String get noCallPeerAccount => en
      ? 'No destination account found to start call'
      : 'ไม่พบบัญชีปลายทางสำหรับเริ่มการโทร';
  static String get cannotCallSelf =>
      en ? 'Cannot call your own account' : 'ไม่สามารถเริ่มการโทรหาบัญชีตัวเองได้';
  static String inAppCallFailed(Object error) => en
      ? 'In-app call failed: $error'
      : 'เริ่มการโทรในแอปไม่สำเร็จ: $error';
  static String get signInBeforeCall =>
      en ? 'Please sign in before calling' : 'กรุณาเข้าสู่ระบบก่อนโทร';
  static String get adminCallWaitingReply => en
      ? 'No admin assigned yet — wait for admin reply first'
      : 'ยังไม่มีแอดมินรับเรื่อง — รอแอดมินตอบกลับก่อน';

  static String get callServerDataMissing => en
      ? 'Call data not found from server — please try again'
      : 'ไม่พบข้อมูลการโทรจากเซิร์ฟเวอร์ กรุณาลองใหม่อีกครั้ง';
  static String get callPermissionMicrophone => en ? 'Microphone' : 'ไมโครโฟน';
  static String get callPermissionCamera => en ? 'Camera' : 'กล้อง';
  static String callPermissionRequired(String permission) => en
      ? 'Allow $permission before using calls'
      : 'ต้องอนุญาต$permissionก่อนจึงจะใช้การโทรได้';
  static String get callAgoraTokenInvalid => en
      ? 'Agora token invalid or expired'
      : 'Agora token ไม่ถูกต้องหรือหมดอายุ';
  static String callServiceConnectFailed(Object error) => en
      ? 'Unable to connect call service ($error)'
      : 'ไม่สามารถเชื่อมต่อบริการโทรได้ ($error)';
  static String get callServiceConnectFailedRetry => en
      ? 'Call service connection failed — please try again'
      : 'เชื่อมต่อบริการโทรไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  static String get callPeerUnreachable => en
      ? 'Unable to reach caller'
      : 'ไม่สามารถเชื่อมต่อกับผู้โทรได้';
  static String get callPeerNoAnswer => en
      ? 'Recipient did not answer'
      : 'ปลายทางไม่ตอบรับการโทร';
  static String get reconnectingCall =>
      en ? 'Reconnecting...' : 'กำลังเชื่อมต่อใหม่...';
  static String get callConnectionFailed => en
      ? 'Connection failed — please try again'
      : 'การเชื่อมต่อล้มเหลว กรุณาลองใหม่อีกครั้ง';
  static String get connectingCall => en ? 'Connecting...' : 'กำลังเชื่อมต่อ...';
  static String get callingVideo => en ? 'Calling (video)...' : 'กำลังโทรหา (วิดีโอ)';
  static String get callingVoice => en ? 'Calling...' : 'กำลังโทรหา';
  static String get talkingWith => en ? 'Talking with' : 'กำลังสนทนากับ';
  static String get incomingCall => en ? 'Incoming call' : 'มีสายเข้า';
  static String get answerCall => en ? 'Answer' : 'รับสาย';
  static String get declineCall => en ? 'Decline' : 'ไม่รับ';
  static String get cameraOffByYou =>
      en ? 'You turned off camera' : 'คุณปิดกล้อง';
  static String get waitingForPeer =>
      en ? 'Waiting for other party...' : 'กำลังรอคู่สนทนา...';
  static String get turnCameraOn => en ? 'Turn camera on' : 'เปิดกล้อง';
  static String get turnCameraOff => en ? 'Turn camera off' : 'ปิดกล้อง';
  static String get speaker => en ? 'Speaker' : 'ลำโพง';
  static String get hangUp => en ? 'Hang up' : 'วางสาย';
  static String get unmuteMic => en ? 'Unmute mic' : 'เปิดไมค์';
  static String get muteMic => en ? 'Mute mic' : 'ปิดไมค์';
  static String get chatNotificationChannelName =>
      en ? 'van3 chat notifications' : 'การแจ้งเตือนแชท van3';
  static String get chatNotificationChannelDesc => en
      ? 'Rider chat message notifications'
      : 'ใช้สำหรับแจ้งเตือนข้อความแชทของไรเดอร์';

  // ---------------------------------------------------------------------------
  // Notifications / job alerts
  // ---------------------------------------------------------------------------

  static String get notificationsTitle => en ? 'Notifications' : 'การแจ้งเตือน';
  static String get notificationsLoadFailed =>
      en ? 'Failed to load notifications' : 'โหลดแจ้งเตือนไม่สำเร็จ';
  static String get notificationsEmpty =>
      en ? 'No notifications yet' : 'ยังไม่มีแจ้งเตือน';
  static String notificationsUnreadCount(int count) => en
      ? '$count new notifications'
      : 'มีแจ้งเตือนใหม่ $count รายการ';
  static String get notificationsMarkAllRead =>
      en ? 'Mark all read' : 'อ่านทั้งหมด';
  static String get notificationsNoLinkedScreen => en
      ? 'This notification has no linked screen'
      : 'แจ้งเตือนนี้ไม่มีหน้าที่เชื่อมต่อ';
  static String get adminAnnouncementTitle =>
      en ? 'Admin announcement' : 'ประกาศจากแอดมิน';
  static String get adminAnnouncementChannelDesc => en
      ? 'Platform announcements and general alerts'
      : 'ประกาศและแจ้งเตือนทั่วไปจากแพลตฟอร์ม';
  static String get newJobDefaultTitle =>
      en ? 'New job available' : 'มีงานใหม่';
  static String get newJobDefaultBody => en
      ? 'New ride request — check immediately'
      : 'มีคำขอเรียกรถใหม่ กรุณาตรวจสอบทันที';
  static String get newOrderArrived =>
      en ? 'A new order has arrived' : 'มีออเดอร์ใหม่เข้ามาแล้ว';
  static String get newOrderConfirmedHint => en
      ? 'This order is confirmed — open the jobs screen now'
      : 'ออเดอร์นี้ถูกยืนยันแล้ว คุณสามารถเปิดหน้ารับงานได้ทันที';
  static String get openJobsScreen =>
      en ? 'Open jobs screen' : 'เปิดหน้ารับงาน';
  static String get urgentJobsChannelName => 'Rider Jobs Urgent';
  static String get urgentJobsChannelDesc => en
      ? 'Urgent rider job alerts with sound'
      : 'แจ้งเตือนงานด่วนพร้อมเสียง';
  static String get orderAlertSettingsTitle =>
      en ? 'Order alert settings' : 'ตั้งค่าแจ้งเตือนออเดอร์';
  static String get alertFullScreenNeeded => en
      ? 'Enable full-screen alerts so jobs appear on the lock screen'
      : 'เปิด "แจ้งเตือนเต็มจอ" เพื่อให้ออเดอร์เด้งบนหน้าจอล็อก';
  static String get alertOverlayNeeded => en
      ? 'Enable display over other apps to see jobs on any screen'
      : 'เปิด "แสดงทับแอปอื่น" เพื่อให้เห็นออเดอร์ทุกหน้าจอ';
  static String get alertEnableFullScreen =>
      en ? 'Enable full-screen alerts' : 'เปิดแจ้งเตือนเต็มจอ';
  static String get alertEnableOverlay =>
      en ? 'Enable overlay display' : 'เปิดแสดงทับแอป';
  static String get alertRecheck => en ? 'Check again' : 'ตรวจสอบอีกครั้ง';

  // ---------------------------------------------------------------------------
  // Admin support
  // ---------------------------------------------------------------------------

  static String get adminSupportInboxTitle =>
      en ? 'Messages to admin' : 'ข้อความถึงแอดมิน';
  static String get adminSupportNewMessageTooltip =>
      en ? 'Send new message' : 'ส่งข้อความใหม่';
  static String get adminSupportContactNew => en ? 'New contact' : 'ติดต่อใหม่';
  static String get adminSupportEmpty =>
      en ? 'No messages yet' : 'ยังไม่มีข้อความ';
  static String get adminSupportEmptyHint => en
      ? 'Tap below to ask admin a question'
      : 'กดปุ่มด้านล่างเพื่อส่งคำถามถึงแอดมิน';
  static String get adminSupportThreadTitle =>
      en ? 'Chat with admin' : 'สนทนากับแอดมิน';
  static String get adminSupportCallAdminTooltip =>
      en ? 'Call admin (in-app)' : 'โทรแอดมิน (ในแอป)';
  static String get adminSupportNoMessages =>
      en ? 'No messages found' : 'ไม่พบข้อความ';
  static String get adminSupportTicketClosedReadOnly => en
      ? 'This ticket is closed — read-only history'
      : 'เรื่องนี้ปิดแล้ว — ดูประวัติการสนทนาได้อย่างเดียว';
  static String get adminSupportMessageHint =>
      en ? 'Message admin...' : 'พิมพ์ข้อความถึงแอดมิน...';
  static String get adminSupportStatusOpen =>
      en ? 'Waiting for admin reply' : 'รอแอดมินตอบ';
  static String get adminSupportStatusInProgress =>
      en ? 'In progress' : 'กำลังติดตาม';
  static String get adminSupportStatusResolved =>
      en ? 'Resolved' : 'แก้ไขแล้ว';
  static String get adminSupportStatusClosed =>
      en ? 'Closed' : 'ปิดเรื่อง';
  static String adminSupportStatusLabel(String status) {
    switch (status) {
      case 'open':
        return adminSupportStatusOpen;
      case 'in_progress':
        return adminSupportStatusInProgress;
      case 'resolved':
        return adminSupportStatusResolved;
      case 'closed':
        return adminSupportStatusClosed;
      default:
        return status;
    }
  }

  static String adminSupportMaxImages(int max) => en
      ? 'Up to $max images allowed'
      : 'แนบรูปได้สูงสุด $max รูป';
  static String get adminContactTitle => en ? 'Contact admin' : 'ติดต่อแอดมิน';
  static String get adminContactInstructions => en
      ? 'Choose a topic, describe the issue, and attach photos (auto-compressed)'
      : 'เลือกหัวข้อที่ตรงกับปัญหา อธิบายรายละเอียด และแนบรูปประกอบได้ (บีบอัดอัตโนมัติ)';
  static String get adminContactTopicSection =>
      en ? 'Topic to ask about' : 'หัวข้อที่ต้องการสอบถาม';
  static String get adminContactCustomTopicLabel =>
      en ? 'Enter custom topic' : 'พิมพ์หัวข้อเอง';
  static String get adminContactDetailsLabel => en ? 'Details' : 'รายละเอียด';
  static String get adminContactDetailsHint => en
      ? 'Describe the issue, date, or order ID (if any)'
      : 'อธิบายปัญหา วันที่เกิดขึ้น หรือเลขออเดอร์ (ถ้ามี)';
  static String get adminContactSubmit => en ? 'Send to admin' : 'ส่งถึงแอดมิน';
  static String get adminContactSelectTopic =>
      en ? 'Please select a topic' : 'กรุณาเลือกหัวข้อ';
  static String get adminContactEnterCustomTopic => en
      ? 'Enter the topic you want to ask'
      : 'กรุณาพิมพ์หัวข้อที่ต้องการสอบถาม';
  static String get adminContactTopicTooLong =>
      en ? 'Topic too long' : 'หัวข้อยาวเกินไป';
  static String get adminContactSentSuccess => en
      ? 'Message sent to admin — awaiting reply'
      : 'ส่งข้อความถึงแอดมินแล้ว รอการติดต่อกลับ';
  static String get adminSupportSourceRider => en ? 'Rider' : 'ไรเดอร์';
  static String get adminTopicJobAssignment => en
      ? 'Job assignment issues'
      : 'ปัญหารับงาน / มอบหมายออเดอร์';
  static String get adminTopicWalletCredit => en
      ? 'Wallet / credit / earnings'
      : 'กระเป๋าเงิน / เครดิต / รายได้';
  static String get adminTopicGps => en
      ? 'GPS / location / maps'
      : 'GPS / พิกัด / แผนที่';
  static String get adminTopicDeliveryIssue => en
      ? 'Customer/shop issues during delivery'
      : 'ปัญหาลูกค้า / ร้านขณะส่งของ';
  static String get adminTopicAccountVerification => en
      ? 'Rider account / verification docs'
      : 'บัญชีไรเดอร์ / เอกสารยืนยัน';
  static String get adminTopicAppBug => en
      ? 'Report app bug'
      : 'แจ้งข้อผิดพลาดแอป';
  static String get adminTopicCustom => en
      ? 'Other (custom topic)'
      : 'อื่นๆ (พิมพ์หัวข้อเอง)';
  static String get adminSupportSignInRequired => en
      ? 'Sign in before contacting admin'
      : 'กรุณาเข้าสู่ระบบก่อนติดต่อแอดมิน';
  static String get adminSupportDetailsRequired =>
      en ? 'Please enter details' : 'กรุณาระบุรายละเอียด';
  static String get adminSupportDetailsTooLong =>
      en ? 'Details too long' : 'รายละเอียดยาวเกินไป';
  static String get adminSupportMessageRequired =>
      en ? 'Please enter a message' : 'กรุณาระบุข้อความ';
  static String get adminSupportMessageTooLong =>
      en ? 'Message too long' : 'ข้อความยาวเกินไป';
  static String get adminSupportTicketNotFound =>
      en ? 'Ticket not found' : 'ไม่พบข้อความ';
  static String get adminSupportNoReplyPermission => en
      ? 'No permission to reply to this ticket'
      : 'ไม่มีสิทธิ์ตอบข้อความนี้';
  static String get adminSupportTicketClosedNoSend => en
      ? 'Ticket closed — cannot send more messages'
      : 'เรื่องนี้ปิดแล้ว — ไม่สามารถส่งข้อความเพิ่มได้';
  static String get adminSupportSendFailed =>
      en ? 'Send failed' : 'ส่งไม่สำเร็จ';
  static String adminSupportSendFailedWithError(Object error) =>
      en ? 'Send failed: $error' : 'ส่งไม่สำเร็จ: $error';

  // ---------------------------------------------------------------------------
  // Privacy / Legal
  // ---------------------------------------------------------------------------

  static String get privacyOnboardingTitle =>
      en ? 'Privacy and terms' : 'ความเป็นส่วนตัวและข้อกำหนด';
  static String get privacyOnboardingIntro => en
      ? 'Please read VANTALAD personal data use before continuing'
      : 'โปรดอ่านการใช้ข้อมูลส่วนบุคคลของ VANTALAD ก่อนใช้งานต่อ';
  static String get privacyPolicyTitle =>
      en ? 'Privacy Policy' : 'นโยบายความเป็นส่วนตัว';
  static String get termsTitle => en ? 'Terms of Service' : 'ข้อกำหนดการใช้งาน';
  static String get dataWeCollectTitle =>
      en ? 'Data we collect' : 'ข้อมูลที่เราเก็บ';
  static String legalUpdatedAt(String date) =>
      en ? 'Last updated: $date' : 'อัปเดตล่าสุด: $date';
  static String get legalUpdatedAtJun2026 => en ? '1 Jun 2026' : '1 มิ.ย. 2026';
  static String get privacyAcceptRequired => en
      ? 'Accept terms and privacy policy (required)'
      : 'ยอมรับข้อกำหนดและนโยบายความเป็นส่วนตัว (จำเป็น)';
  static String get privacyJobNotificationsOptional => en
      ? 'Receive job and order notifications'
      : 'รับการแจ้งเตือนงานและออเดอร์';
  static String get privacyPromotionsOptional =>
      en ? 'Receive promotions' : 'รับข่าวโปรโมชัน';
  static String get privacyMustAcceptGate => en
      ? 'You must accept terms and privacy policy before use'
      : 'ต้องยอมรับข้อกำหนดและนโยบายความเป็นส่วนตัวก่อนใช้งาน';
  static String get privacyReviewTermsAgain =>
      en ? 'Review terms again' : 'ดูข้อกำหนดอีกครั้ง';
  static String get privacySecurityTitle =>
      en ? 'Privacy and security' : 'ความเป็นส่วนตัวและความปลอดภัย';
  static String get privacyJobNotificationsToggle =>
      en ? 'Job notifications' : 'แจ้งเตือนงาน';
  static String get privacyPromotionsToggle =>
      en ? 'Promotions' : 'ข่าวโปรโมชัน';
  static String get privacyExportData =>
      en ? 'Request data export' : 'ขอส่งออกข้อมูล';
  static String get privacyCorrectData =>
      en ? 'Request data correction' : 'ขอแก้ไขข้อมูล';
  static String get privacyDeleteAccount =>
      en ? 'Request account deletion' : 'ขอลบบัญชี';
  static String get privacyManageAppPermissions =>
      en ? 'Manage app permissions' : 'จัดการสิทธิ์แอป';
  static String saveNotificationSettingsFailed(Object error) => en
      ? 'Failed to save notification settings: $error'
      : 'บันทึกการตั้งค่าแจ้งเตือนไม่สำเร็จ: $error';
  static String saveMarketingSettingsFailed(Object error) => en
      ? 'Failed to save marketing settings: $error'
      : 'บันทึกการตั้งค่าการตลาดไม่สำเร็จ: $error';
  static String get privacyRequestSignInRequired => en
      ? 'Sign in before submitting request'
      : 'กรุณาเข้าสู่ระบบก่อนส่งคำขอ';
  static String get privacyRequestConfirmBody => en
      ? 'System will create a PDPA request and notify admin. Continue?'
      : 'ระบบจะสร้างคำขอ PDPA และแจ้งแอดมิน ต้องการดำเนินการต่อหรือไม่?';
  static String get privacyRequestSubmit =>
      en ? 'Submit request' : 'ส่งคำขอ';
  static String privacyRequestSubmitted(String requestId) => en
      ? 'Request submitted ($requestId)'
      : 'ส่งคำขอแล้ว ($requestId)';
  static String privacyRequestFailed(Object error) =>
      en ? 'Request failed: $error' : 'ส่งคำขอไม่สำเร็จ: $error';
  static String get pdpaRequestFailed =>
      en ? 'PDPA request failed' : 'คำขอ PDPA ไม่สำเร็จ';

  // ---------------------------------------------------------------------------
  // Security — PIN, biometric, app unlock
  // ---------------------------------------------------------------------------

  static String get pinLabel => en ? '6-digit PIN' : 'รหัส PIN 6 หลัก';
  static String get pinVerifyDefaultSubtitle => en
      ? 'Enter the 6-digit PIN you set during registration'
      : 'กรุณาใส่รหัส PIN 6 หลักที่ตั้งไว้ตอนลงทะเบียน';
  static String get pinEnterRequired =>
      en ? 'Enter 6-digit PIN' : 'กรุณากรอกรหัส PIN 6 หลัก';
  static String get pinIncorrect => en ? 'Incorrect PIN' : 'รหัส PIN ไม่ถูกต้อง';
  static String get pinVerifyFailedRetry => en
      ? 'PIN verification failed — try again'
      : 'ตรวจ PIN ไม่สำเร็จ — ลองอีกครั้ง';
  static String get pinSetTitle => en ? 'Set 6-digit PIN' : 'ตั้งรหัส PIN 6 หลัก';
  static String get pinConfirmTitle =>
      en ? 'Confirm PIN again' : 'ยืนยันรหัส PIN อีกครั้ง';
  static String get pinSetRequired =>
      en ? 'Set a 6-digit PIN' : 'กรุณาตั้งรหัส PIN 6 หลัก';
  static String get pinMismatchRetry =>
      en ? 'PINs do not match — try again' : 'รหัส PIN ไม่ตรงกัน ลองใหม่';
  static String get pinChangeExisting =>
      en ? 'Change existing PIN' : 'เปลี่ยนรหัสที่ตั้งไว้';
  static String get unlockTitle =>
      en ? 'Unlock to continue' : 'ปลดล็อกเพื่อเข้าใช้งาน';
  static String get unlockMethodHint => en
      ? 'Use fingerprint or 6-digit PIN'
      : 'ใช้ลายนิ้วมือหรือรหัส PIN 6 หลัก';
  static String get unlockWithBiometric =>
      en ? 'Unlock with fingerprint' : 'เข้าใช้งานด้วยลายนิ้วมือ';
  static String get unlockOrEnterPin =>
      en ? 'Or enter PIN' : 'หรือใส่รหัส PIN';
  static String get biometricUnlockReason => en
      ? 'Verify fingerprint to enter app'
      : 'ยืนยันลายนิ้วมือเพื่อเข้าใช้งาน';
  static String get biometricVerifyFailed => en
      ? 'Fingerprint verification failed'
      : 'ยืนยันลายนิ้วมือไม่สำเร็จ';
  static String get biometricDefaultReason => en
      ? 'Verify identity with fingerprint'
      : 'ยืนยันตัวตนด้วยลายนิ้วมือ';

  static String get appCheckDeviceSecurityFailed => en
      ? 'Unable to verify device security — please update the app and try again'
      : 'ไม่สามารถยืนยันความปลอดภัยของอุปกรณ์ได้ กรุณาอัปเดตแอปแล้วลองใหม่';
  static String appCheckDebugNotReady(String hint) => en
      ? 'App Check not ready — register debug token in Firebase Console → van3: $hint'
      : 'App Check ยังไม่พร้อม — ลงทะเบียน debug token ใน Firebase Console → van3: $hint';
  static String get serverSlowRetryColdStart => en
      ? 'Server is slow — try again in 10–20 seconds (first call may wait for cold start)'
      : 'เซิร์ฟเวอร์ตอบช้า — ลองอีกครั้งใน 10–20 วินาที (ครั้งแรกอาจรอ cold start)';
  static String get privacyPolicyRequired => en
      ? 'Must accept privacy policy'
      : 'ต้องยอมรับนโยบายความเป็นส่วนตัว';
  static String get currentUserNotFound =>
      en ? 'Current user not found' : 'ไม่พบผู้ใช้ปัจจุบัน';

  // ---------------------------------------------------------------------------
  // Location permission / onboarding
  // ---------------------------------------------------------------------------

  static String get locationPermissionTitle =>
      en ? 'Location access' : 'สิทธิ์การเข้าถึงพิกัด';
  static String get locationPermissionBeforeReady =>
      en ? 'Before going online' : 'ก่อนเปิดพร้อมรับงาน';
  static String get locationPermissionBody => en
      ? 'The system needs your current location to match jobs correctly'
      : 'ระบบต้องใช้พิกัดปัจจุบันของไรเดอร์ เพื่อจับคู่งานได้ถูกต้อง';
  static String get locationEmulatorHint => en
      ? 'On emulator, set mock location to your test area first'
      : 'หากใช้ Emulator ให้ตั้ง Mock Location เป็นพิกัดจริงของพื้นที่ทดสอบก่อน';
  static String get enableGps => en ? 'Enable GPS' : 'เปิด GPS';
  static String get openAppSettings =>
      en ? 'App settings' : 'ตั้งค่าแอป';
  static String get allowAndContinue =>
      en ? 'Allow and continue' : 'อนุญาตและไปต่อ';
  static String get enableGpsFirst => en
      ? 'Please enable GPS/Location on your device first'
      : 'กรุณาเปิด GPS/Location ของเครื่องก่อน';
  static String get locationPermissionDenied =>
      en ? 'Location permission not granted' : 'ยังไม่ได้อนุญาตสิทธิ์ตำแหน่ง';
  static String get locationPermissionDeniedForever => en
      ? 'Location permission permanently denied — enable in app settings'
      : 'สิทธิ์ตำแหน่งถูกปิดถาวร กรุณาเปิดในตั้งค่าแอป';
  static String get riderStatusLoadTimeout => en
      ? 'Loading rider status timed out — check internet and try again'
      : 'โหลดสถานะไรเดอร์ใช้เวลานานเกินไป กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ตแล้วลองใหม่';
  static String get riderStatusPermissionDenied => en
      ? 'Unable to read rider status (permission-denied) — contact admin'
      : 'ไม่สามารถอ่านสถานะไรเดอร์ได้ (permission-denied) กรุณาติดต่อแอดมิน';
  static String riderStatusLoadFailed(String code) => en
      ? 'Failed to load rider status ($code)'
      : 'โหลดสถานะไรเดอร์ไม่สำเร็จ ($code)';
  static String get riderStatusLoadFailedTitle =>
      en ? 'Failed to load rider status' : 'โหลดสถานะไรเดอร์ไม่สำเร็จ';

  // ---------------------------------------------------------------------------
  // Reviews
  // ---------------------------------------------------------------------------

  static String get reviewsLoadFailed =>
      en ? 'Failed to load reviews' : 'โหลดรีวิวไม่สำเร็จ';
  static String reviewsLoadFailedWithError(Object error) => en
      ? 'Failed to load reviews\n$error'
      : 'โหลดรีวิวไม่สำเร็จ\n$error';
  static String get noCustomerReviewsYet => en
      ? 'No customer reviews yet'
      : 'ยังไม่มีรีวิวจากลูกค้า';
  static String reviewForOrder(String orderId) =>
      en ? 'Order $orderId' : 'ออเดอร์ $orderId';
  static String get reviewsReadOnlyCustomer => en
      ? 'Read-only — only customers can edit reviews'
      : 'อ่านอย่างเดียว — แก้ไขได้เฉพาะลูกค้า';

  // ---------------------------------------------------------------------------
  // Payment labels / vehicles / settlement / PromptPay
  // ---------------------------------------------------------------------------

  static String get paymentPayAtDestination =>
      en ? 'Pay on delivery' : 'จ่ายปลายทาง';
  static String get paymentTransferAtDestination =>
      en ? 'Transfer on delivery' : 'โอนปลายทาง';
  static String get paymentScanPay => en ? 'Scan to pay' : 'สแกนจ่าย';
  static String get paymentCash => en ? 'Cash' : 'เงินสด';
  static String get paymentBankTransfer => en ? 'Bank transfer' : 'โอนเงิน';
  static String get paymentVehicleMotorcycle =>
      en ? 'Motorcycle' : 'มอเตอร์ไซค์';
  static String get paymentVehicleSedan => en ? 'Sedan' : 'รถเก๋ง';
  static String get paymentVehiclePickup =>
      en ? 'Pickup truck' : 'รถกระบะ';
  static String get creditReleaseScheduled =>
      en ? 'Pending credit release' : 'รอปล่อยเครดิต';
  static String get creditReleaseHeld =>
      en ? 'Held by admin' : 'ถูกระงับโดยแอดมิน';
  static String get creditReleaseReleased =>
      en ? 'Released' : 'ปล่อยแล้ว';
  static String get creditReleaseBlocked =>
      en ? 'Blocked' : 'ถูกบล็อก';
  static String get payoutPaid => en ? 'Paid' : 'จ่ายแล้ว';
  static String get payoutFailed =>
      en ? 'Transfer failed' : 'โอนไม่สำเร็จ';
  static String get payoutPending =>
      en ? 'Pending payment' : 'รอชำระ';
  static String get payoutIncomingTitle =>
      en ? 'Payment incoming' : 'มียอดเงินเข้า';
  static String payoutIncomingBody(String order, double amount) => en
      ? 'Order $order ${amount.toStringAsFixed(2)} THB • pending'
      : 'ออเดอร์ $order ${amount.toStringAsFixed(2)} บาท • รอชำระ';
  static String payoutPaidBody(String order, double amount) => en
      ? 'Order $order ${amount.toStringAsFixed(2)} THB • paid'
      : 'ออเดอร์ $order ${amount.toStringAsFixed(2)} บาท • จ่ายแล้ว';
  static String get payoutSuccessTitle =>
      en ? 'Transfer successful' : 'โอนเงินสำเร็จ';
  static String get promptPayRequired => en
      ? 'Enter PromptPay phone or national/tax ID'
      : 'กรุณากรอกเบอร์ PromptPay หรือเลขบัตร/นิติบุคคล';
  static String get promptPayNationalIdLength => en
      ? 'PromptPay national/tax ID must be 13 digits'
      : 'เลขบัตร/นิติบุคคล PromptPay ต้องมี 13 หลัก';
  static String get promptPayPhoneInvalid => en
      ? 'Invalid PromptPay phone (e.g. 0812345678)'
      : 'เบอร์ PromptPay ไม่ถูกต้อง (เช่น 0812345678)';
  static String get promptPayInvalid => en
      ? 'Invalid PromptPay phone or ID'
      : 'เบอร์หรือเลข PromptPay ไม่ถูกต้อง';
  static String get promptPayBankLinkHint => en
      ? 'Must be PromptPay linked to registered bank account (for withdrawals)'
      : 'ต้องเป็นเบอร์หรือเลข PromptPay ที่ผูกกับบัญชีธนาคารที่ลงทะเบียนไว้ (ใช้รับเงินถอน)';
  static String get promptPayDisplay => 'PromptPay';
  static String promptPayMaskedDisplay(String suffix) =>
      'PromptPay ••••$suffix';

  /// Resolve credit release display status from raw backend code.
  static String creditReleaseDisplayStatus(String? rawStatus) {
    final status = rawStatus?.trim().toLowerCase() ?? '';
    switch (status) {
      case 'scheduled':
        return creditReleaseScheduled;
      case 'held':
        return creditReleaseHeld;
      case 'released':
        return creditReleaseReleased;
      case 'blocked':
        return creditReleaseBlocked;
      default:
        return creditReleaseScheduled;
    }
  }

  /// Resolve settlement payout display status from raw backend code.
  static String settlementPayoutDisplayStatus(String? rawStatus) {
    final status = rawStatus?.trim().toLowerCase() ?? '';
    switch (status) {
      case 'paid':
        return payoutPaid;
      case 'failed':
        return payoutFailed;
      case 'scheduled':
        return creditReleaseScheduled;
      case 'held':
        return creditReleaseHeld;
      case 'pending':
      case 'exported':
      case '':
        return payoutPending;
      default:
        return payoutPending;
    }
  }

  /// Resolve order payment label from normalized payment key.
  static String? orderPaymentLabelFromKey(String? key) {
    if (key == null || key.isEmpty) return null;
    if (key.contains('cash_on_delivery') ||
        key.contains('cod') ||
        key.contains('pay_at_destination') ||
        key.contains('destination')) {
      return paymentPayAtDestination;
    }
    if (key.contains('promptpay') ||
        key.contains('qr') ||
        key.contains('scan') ||
        key.contains('qrcode') ||
        key.contains('true_money') ||
        key.contains('truemoney')) {
      return paymentScanPay;
    }
    if (key.contains('cash')) return paymentCash;
    if (key.contains('transfer') || key.contains('bank')) {
      return paymentBankTransfer;
    }
    return null;
  }
}
