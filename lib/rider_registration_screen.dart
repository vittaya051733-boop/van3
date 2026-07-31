import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import 'data/legal_content.dart';
import 'legal_document_screen.dart';
import 'services/rider_auth_sign_out.dart';
import 'services/rider_registration_service.dart';
import 'utils/app_colors.dart';

class RiderRegistrationScreen extends StatefulWidget {
  const RiderRegistrationScreen({super.key, this.rejectedReason});

  final String? rejectedReason;

  @override
  State<RiderRegistrationScreen> createState() =>
      _RiderRegistrationScreenState();
}

class _RiderRegistrationScreenState extends State<RiderRegistrationScreen> {
  static const List<String> _thaiBanks = <String>[
    'ธนาคารกรุงเทพ (BBL)',
    'ธนาคารกสิกรไทย (KBank)',
    'ธนาคารไทยพาณิชย์ (SCB)',
    'ธนาคารกรุงไทย (KTB)',
    'ธนาคารกรุงศรีอยุธยา (BAY)',
    'ทีเอ็มบีธนชาต (TTB)',
    'อื่นๆ',
  ];

  final _pageController = PageController();
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _accountOwnerController = TextEditingController();
  final _imagePicker = ImagePicker();

  int _step = 0;
  bool _submitting = false;
  bool _pickingImage = false;
  bool _acceptedPrivacy = false;
  bool _pushOptIn = false;
  String? _selectedBank;
  File? _licenseImage;
  File? _motorcycleImage;
  File? _bookBankImage;
  File? _profilePhotoImage;
  String? _vehicleType;
  final _licensePlateController = TextEditingController();
  final _vehicleColorController = TextEditingController();
  final _vehicleBrandModelController = TextEditingController();
  bool _isElectricVehicle = false;

  static const List<MapEntry<String, String>> _vehicleTypes =
      <MapEntry<String, String>>[
    MapEntry('motorcycle', 'มอเตอร์ไซค์'),
    MapEntry('sedan', 'รถเก๋ง'),
    MapEntry('pickup', 'รถกระบะ'),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _nameController.dispose();
    _accountNumberController.dispose();
    _accountOwnerController.dispose();
    _licensePlateController.dispose();
    _vehicleColorController.dispose();
    _vehicleBrandModelController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(void Function(File file) assign) async {
    if (_pickingImage) {
      return;
    }
    setState(() => _pickingImage = true);
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null || !mounted) {
        return;
      }
      setState(() => assign(File(picked.path)));
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      if (error.code == 'already_active') {
        _showSnack('กรุณารอให้หน้าต่างเลือกรูปปิดก่อน แล้วลองใหม่');
      } else {
        _showSnack('เลือกรูปไม่สำเร็จ: ${error.message ?? error.code}');
      }
    } finally {
      if (mounted) {
        setState(() => _pickingImage = false);
      }
    }
  }

  Future<String> _uploadImage(File file, String label) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('กรุณาเข้าสู่ระบบก่อนอัปโหลด');
    }
    final compressed = await FlutterImageCompress.compressWithFile(
      file.absolute.path,
      quality: 82,
    );
    final bytes = compressed ?? await file.readAsBytes();
    final path =
        'rider_registrations/${user.uid}/${label}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = FirebaseStorage.instance.ref().child(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (!_acceptedPrivacy) {
      _showSnack('กรุณายอมรับนโยบายความเป็นส่วนตัว');
      return;
    }
    if (_licenseImage == null ||
        _motorcycleImage == null ||
        _bookBankImage == null ||
        _profilePhotoImage == null) {
      _showSnack('กรุณาอัปโหลดรูปโปรไฟล์และเอกสารให้ครบ');
      return;
    }
    if (_vehicleType == null || _vehicleType!.isEmpty) {
      _showSnack('กรุณาเลือกประเภทรถ');
      return;
    }
    if (_licensePlateController.text.trim().isEmpty ||
        _vehicleColorController.text.trim().isEmpty ||
        _vehicleBrandModelController.text.trim().isEmpty) {
      _showSnack('กรุณากรอกข้อมูลรถให้ครบ');
      return;
    }
    if (_selectedBank == null || _selectedBank!.isEmpty) {
      _showSnack('กรุณาเลือกธนาคาร');
      return;
    }

    setState(() => _submitting = true);
    try {
      User? user = FirebaseAuth.instance.currentUser;
      user ??= (await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      )).user;

      if (user == null) {
        throw StateError('สร้างบัญชีไม่สำเร็จ');
      }

      final licenseUrl = await _uploadImage(_licenseImage!, 'license');
      final bikeUrl = await _uploadImage(_motorcycleImage!, 'motorcycle');
      final bankUrl = await _uploadImage(_bookBankImage!, 'book_bank');
      final profileUrl = await _uploadImage(_profilePhotoImage!, 'profile');

      await RiderRegistrationService.submitRegistration(
        user: user,
        contactEmail: _emailController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        displayName: _nameController.text.trim(),
        bankName: _selectedBank!,
        accountNumber: _accountNumberController.text.trim(),
        accountOwner: _accountOwnerController.text.trim(),
        driverLicenseImageUrl: licenseUrl,
        motorcycleImageUrl: bikeUrl,
        bookBankImageUrl: bankUrl,
        profilePhotoUrl: profileUrl,
        vehicleType: _vehicleType!,
        licensePlate: _licensePlateController.text.trim(),
        vehicleColor: _vehicleColorController.text.trim(),
        vehicleBrandModel: _vehicleBrandModelController.text.trim(),
        isElectricVehicle: _isElectricVehicle,
        acceptedPrivacy: _acceptedPrivacy,
        pushOptIn: _pushOptIn,
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacementNamed('/registration-pending');
    } on FirebaseAuthException catch (error) {
      _showSnack(error.message ?? 'สมัครไม่สำเร็จ');
    } catch (error) {
      _showSnack('สมัครไม่สำเร็จ: $error');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _openDocument(LegalDocument document) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentScreen(document: document),
      ),
    );
  }

  Widget _imageTile({
    required String title,
    required File? file,
    required VoidCallback onPick,
  }) {
    return Card(
      child: ListTile(
        leading: file == null
            ? const Icon(Icons.add_a_photo_outlined)
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(file, width: 48, height: 48, fit: BoxFit.cover),
              ),
        title: Text(title),
        subtitle: Text(
          _pickingImage
              ? 'กำลังเปิดคลังรูป...'
              : file == null
              ? 'ยังไม่ได้เลือกรูป'
              : 'เลือกแล้ว',
        ),
        trailing: _pickingImage
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right_rounded),
        onTap: _pickingImage ? null : onPick,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = FirebaseAuth.instance.currentUser != null;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('สมัครไรเดอร์'),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: <Widget>[
            if (widget.rejectedReason != null)
              Container(
                width: double.infinity,
                color: const Color(0xFFFEF2F2),
                padding: const EdgeInsets.all(12),
                child: Text(
                  'คำขอถูกปฏิเสธ: ${widget.rejectedReason}',
                  style: const TextStyle(color: Color(0xFFB91C1C)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: List<Widget>.generate(4, (index) {
                  final active = index <= _step;
                  return Expanded(
                    child: Container(
                      margin: EdgeInsets.only(right: index == 3 ? 0 : 6),
                      height: 4,
                      decoration: BoxDecoration(
                        color: active ? AppColors.accent : const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  );
                }),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (value) => setState(() => _step = value),
                children: <Widget>[
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      const Text(
                        'ข้อมูลบัญชี',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      if (!loggedIn) ...<Widget>[
                        TextFormField(
                          controller: _emailController,
                          decoration: const InputDecoration(
                            labelText: 'อีเมล',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) =>
                              value?.trim().isEmpty == true ? 'กรุณากรอกอีเมล' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'รหัสผ่าน (อย่างน้อย 6 ตัว)',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              (value ?? '').length < 6 ? 'รหัสผ่านสั้นเกินไป' : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'ชื่อ-นามสกุล',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value?.trim().isEmpty == true ? 'กรุณากรอกชื่อ' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneController,
                        decoration: const InputDecoration(
                          labelText: 'เบอร์โทร',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.phone,
                        validator: (value) =>
                            value?.trim().isEmpty == true ? 'กรุณากรอกเบอร์โทร' : null,
                      ),
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      const Text(
                        'โปรไฟล์และข้อมูลรถ',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'ข้อมูลนี้จะแสดงให้ลูกค้าเห็นหลังจองการเดินทาง',
                        style: TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      _imageTile(
                        title: 'รูปโปรไฟล์ (ใบหน้าชัดเจน)',
                        file: _profilePhotoImage,
                        onPick: () => _pickImage(
                          (file) => setState(() => _profilePhotoImage = file),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _vehicleType,
                        items: _vehicleTypes
                            .map(
                              (entry) => DropdownMenuItem<String>(
                                value: entry.key,
                                child: Text(entry.value),
                              ),
                            )
                            .toList(),
                        decoration: const InputDecoration(
                          labelText: 'ประเภทรถ',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) =>
                            setState(() => _vehicleType = value),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _licensePlateController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'ทะเบียนรถ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _vehicleColorController,
                        decoration: const InputDecoration(
                          labelText: 'สีรถ (เช่น ขาว)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _vehicleBrandModelController,
                        decoration: const InputDecoration(
                          labelText: 'ยี่ห้อ/รุ่น (เช่น AION Y)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _isElectricVehicle,
                        onChanged: (value) =>
                            setState(() => _isElectricVehicle = value),
                        title: const Text('รถไฟฟ้า (EV)'),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'เอกสารยืนยันตัวตน',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'ใช้ตรวจสอบก่อนอนุมัติเป็นพาร์ทเนอร์ไรเดอร์',
                        style: TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      _imageTile(
                        title: 'ใบขับขี่',
                        file: _licenseImage,
                        onPick: () => _pickImage(
                          (file) => setState(() => _licenseImage = file),
                        ),
                      ),
                      _imageTile(
                        title: 'รูปมอเตอร์ไซค์',
                        file: _motorcycleImage,
                        onPick: () => _pickImage(
                          (file) => setState(() => _motorcycleImage = file),
                        ),
                      ),
                      _imageTile(
                        title: 'หน้าสมุดบัญชี',
                        file: _bookBankImage,
                        onPick: () => _pickImage(
                          (file) => setState(() => _bookBankImage = file),
                        ),
                      ),
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      const Text(
                        'บัญชีรับเงิน',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _selectedBank,
                        items: _thaiBanks
                            .map(
                              (bank) => DropdownMenuItem<String>(
                                value: bank,
                                child: Text(bank),
                              ),
                            )
                            .toList(),
                        decoration: const InputDecoration(
                          labelText: 'ธนาคาร',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => setState(() => _selectedBank = value),
                        validator: (value) =>
                            value == null || value.isEmpty ? 'เลือกธนาคาร' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _accountNumberController,
                        decoration: const InputDecoration(
                          labelText: 'เลขบัญชี',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) =>
                            value?.trim().isEmpty == true ? 'กรุณากรอกเลขบัญชี' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _accountOwnerController,
                        decoration: const InputDecoration(
                          labelText: 'ชื่อบัญชี (ต้องตรงธนาคาร)',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value?.trim().isEmpty == true ? 'กรุณากรอกชื่อบัญชี' : null,
                      ),
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      const Text(
                        'ความเป็นส่วนตัว (PDPA)',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      _LinkCard(
                        title: 'นโยบายความเป็นส่วนตัว',
                        onTap: () => _openDocument(LegalContent.privacyPolicy),
                      ),
                      const SizedBox(height: 8),
                      _LinkCard(
                        title: 'ข้อกำหนดการใช้งาน',
                        onTap: () => _openDocument(LegalContent.termsOfService),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _acceptedPrivacy,
                        onChanged: (value) =>
                            setState(() => _acceptedPrivacy = value == true),
                        title: const Text(
                          'ยอมรับนโยบายและข้อกำหนด (จำเป็น)',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _pushOptIn,
                        onChanged: (value) => setState(() => _pushOptIn = value),
                        title: const Text('รับแจ้งเตือนงาน (ไม่บังคับ)'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  if (_step > 0)
                    OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () {
                              final next = _step - 1;
                              _pageController.animateToPage(
                                next,
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                              );
                              setState(() => _step = next);
                            },
                      child: const Text('ย้อนกลับ'),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submitting
                          ? null
                          : () async {
                              if (_step < 3) {
                                if (!_formKey.currentState!.validate()) {
                                  return;
                                }
                                if (_step == 1 &&
                                    (_licenseImage == null ||
                                        _motorcycleImage == null ||
                                        _bookBankImage == null ||
                                        _profilePhotoImage == null ||
                                        _vehicleType == null ||
                                        _licensePlateController.text
                                            .trim()
                                            .isEmpty ||
                                        _vehicleColorController.text
                                            .trim()
                                            .isEmpty ||
                                        _vehicleBrandModelController.text
                                            .trim()
                                            .isEmpty)) {
                                  _showSnack(
                                    'กรุณากรอกข้อมูลรถและอัปโหลดรูปให้ครบ',
                                  );
                                  return;
                                }
                                final next = _step + 1;
                                await _pageController.animateToPage(
                                  next,
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOut,
                                );
                                setState(() => _step = next);
                                return;
                              }
                              await _submit();
                            },
                      child: Text(
                        _submitting
                            ? 'กำลังส่ง...'
                            : _step < 3
                            ? 'ถัดไป'
                            : 'ส่งคำขอสมัคร',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RiderRegistrationPendingScreen extends StatefulWidget {
  const RiderRegistrationPendingScreen({super.key});

  @override
  State<RiderRegistrationPendingScreen> createState() =>
      _RiderRegistrationPendingScreenState();
}

class _RiderRegistrationPendingScreenState
    extends State<RiderRegistrationPendingScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('รอการอนุมัติ')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.hourglass_top_rounded, size: 72, color: AppColors.accent),
            const SizedBox(height: 16),
            const Text(
              'ส่งคำขอสมัครไรเดอร์แล้ว',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'แอดมินจะตรวจสอบเอกสารและบัญชีธนาคาร\nเมื่ออนุมัติแล้วจึงเริ่มรับงานได้',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.5, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () async {
                await RiderAuthSignOut.signOut();
                if (context.mounted) {
                  Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (_) => false);
                }
              },
              child: const Text('ออกจากระบบ'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
