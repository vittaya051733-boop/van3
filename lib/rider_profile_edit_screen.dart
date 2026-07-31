import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import 'services/rider_registration_service.dart';
import 'utils/app_colors.dart';

class RiderProfileEditScreen extends StatefulWidget {
  const RiderProfileEditScreen({super.key});

  @override
  State<RiderProfileEditScreen> createState() => _RiderProfileEditScreenState();
}

class _RiderProfileEditScreenState extends State<RiderProfileEditScreen> {
  static const List<String> _thaiBanks = <String>[
    'ธนาคารกรุงเทพ (BBL)',
    'ธนาคารกสิกรไทย (KBank)',
    'ธนาคารไทยพาณิชย์ (SCB)',
    'ธนาคารกรุงไทย (KTB)',
    'ธนาคารกรุงศรีอยุธยา (BAY)',
    'ทีเอ็มบีธนชาต (TTB)',
    'อื่นๆ',
  ];

  List<String> get _bankOptions {
    final bank = _selectedBank?.trim();
    if (bank != null && bank.isNotEmpty && !_thaiBanks.contains(bank)) {
      return <String>[bank, ..._thaiBanks];
    }
    return _thaiBanks;
  }

  static const List<MapEntry<String, String>> _vehicleTypes =
      <MapEntry<String, String>>[
    MapEntry('motorcycle', 'มอเตอร์ไซค์'),
    MapEntry('sedan', 'รถเก๋ง'),
    MapEntry('pickup', 'รถกระบะ'),
  ];

  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _accountOwnerController = TextEditingController();
  final _licensePlateController = TextEditingController();
  final _vehicleColorController = TextEditingController();
  final _vehicleBrandModelController = TextEditingController();
  final _imagePicker = ImagePicker();

  bool _loading = true;
  bool _saving = false;
  bool _pickingImage = false;
  bool _isElectricVehicle = false;
  bool _pushOptIn = false;
  String? _selectedBank;
  String? _vehicleType;
  String? _existingProfilePhotoUrl;
  String? _existingLicenseUrl;
  String? _existingMotorcycleUrl;
  String? _existingBookBankUrl;
  File? _profilePhotoImage;
  File? _licenseImage;
  File? _motorcycleImage;
  File? _bookBankImage;
  RiderProfileData? _loadedProfile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    _accountNumberController.dispose();
    _accountOwnerController.dispose();
    _licensePlateController.dispose();
    _vehicleColorController.dispose();
    _vehicleBrandModelController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    try {
      final profile = await RiderRegistrationService.fetchProfile(user.uid);
      if (!mounted) {
        return;
      }
      setState(() {
        _loadedProfile = profile;
        _nameController.text = profile.displayName ?? user.displayName ?? '';
        _phoneController.text = profile.phoneNumber ?? '';
        _accountNumberController.text = profile.accountNumber ?? '';
        _accountOwnerController.text = profile.accountOwner ?? '';
        _licensePlateController.text = profile.licensePlate ?? '';
        _vehicleColorController.text = profile.vehicleColor ?? '';
        _vehicleBrandModelController.text = profile.vehicleBrandModel ?? '';
        _selectedBank = profile.bankName;
        _vehicleType = profile.vehicleType;
        _isElectricVehicle = profile.isElectricVehicle;
        _pushOptIn = profile.pushOptIn;
        _existingProfilePhotoUrl = profile.profilePhotoUrl;
        _existingLicenseUrl = profile.driverLicenseImageUrl;
        _existingMotorcycleUrl = profile.motorcycleImageUrl;
        _existingBookBankUrl = profile.bookBankImageUrl;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
      _showSnack('โหลดข้อมูลไม่สำเร็จ: $error');
    }
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

  Future<String?> _resolveImageUrl({
    required File? picked,
    required String? existing,
    required String label,
  }) async {
    if (picked != null) {
      return _uploadImage(picked, label);
    }
    return existing?.trim().isNotEmpty == true ? existing!.trim() : null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack('กรุณาเข้าสู่ระบบก่อน');
      return;
    }

    setState(() => _saving = true);
    try {
      final profilePhotoUrl = await _resolveImageUrl(
        picked: _profilePhotoImage,
        existing: _existingProfilePhotoUrl,
        label: 'profile',
      );
      final licenseUrl = await _resolveImageUrl(
        picked: _licenseImage,
        existing: _existingLicenseUrl,
        label: 'license',
      );
      final motorcycleUrl = await _resolveImageUrl(
        picked: _motorcycleImage,
        existing: _existingMotorcycleUrl,
        label: 'motorcycle',
      );
      final bookBankUrl = await _resolveImageUrl(
        picked: _bookBankImage,
        existing: _existingBookBankUrl,
        label: 'book_bank',
      );

      await RiderRegistrationService.updateProfile(
        uid: user.uid,
        displayName: _nameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        bankName: _selectedBank,
        accountNumber: _accountNumberController.text.trim(),
        accountOwner: _accountOwnerController.text.trim(),
        driverLicenseImageUrl: licenseUrl,
        motorcycleImageUrl: motorcycleUrl,
        bookBankImageUrl: bookBankUrl,
        profilePhotoUrl: profilePhotoUrl,
        vehicleType: _vehicleType,
        licensePlate: _licensePlateController.text.trim(),
        vehicleColor: _vehicleColorController.text.trim(),
        vehicleBrandModel: _vehicleBrandModelController.text.trim(),
        isElectricVehicle: _isElectricVehicle,
        pushOptIn: _pushOptIn,
      );

      final displayName = _nameController.text.trim();
      if (displayName.isNotEmpty && displayName != user.displayName) {
        await user.updateDisplayName(displayName);
      }
      if (profilePhotoUrl != null && profilePhotoUrl != user.photoURL) {
        await user.updatePhotoURL(profilePhotoUrl);
      }

      if (!mounted) {
        return;
      }

      final updated = RiderProfileData.fromMap(<String, dynamic>{
        'displayName': displayName,
        'phoneNumber': _phoneController.text.trim(),
        'bankName': _selectedBank,
        'accountNumber': _accountNumberController.text.trim(),
        'accountOwner': _accountOwnerController.text.trim(),
        'driverLicenseImageUrl': licenseUrl,
        'motorcycleImageUrl': motorcycleUrl,
        'bookBankImageUrl': bookBankUrl,
        'profilePhotoUrl': profilePhotoUrl,
        'photoUrl': profilePhotoUrl,
        'vehicleType': _vehicleType,
        'licensePlate': _licensePlateController.text.trim(),
        'vehicleColor': _vehicleColorController.text.trim(),
        'vehicleBrandModel': _vehicleBrandModelController.text.trim(),
        'isElectricVehicle': _isElectricVehicle,
      });

      if (updated.isCompleteForCustomerTravel) {
        _showSnack('บันทึกแล้ว — ลูกค้า van2 จะเห็นรูปและข้อมูลรถของคุณ');
      } else {
        _showSnack('บันทึกแล้ว — กรุณาเติมรูปโปรไฟล์และข้อมูลรถให้ครบ');
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      _showSnack('บันทึกไม่สำเร็จ: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Widget _sectionHeader(String title, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Colors.black54)),
          ],
        ],
      ),
    );
  }

  Widget _imageTile({
    required String title,
    File? file,
    String? existingUrl,
    required VoidCallback onPick,
  }) {
    Widget? leading;
    if (file != null) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(file, width: 48, height: 48, fit: BoxFit.cover),
      );
    } else if (existingUrl != null && existingUrl.isNotEmpty) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          existingUrl,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
        ),
      );
    } else {
      leading = const Icon(Icons.add_a_photo_outlined);
    }

    final hasImage = file != null || (existingUrl?.isNotEmpty == true);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: leading,
        title: Text(title),
        subtitle: Text(
          _pickingImage
              ? 'กำลังเปิดคลังรูป...'
              : hasImage
              ? 'แตะเพื่อเปลี่ยนรูป'
              : 'ยังไม่ได้เลือกรูป',
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
    final user = FirebaseAuth.instance.currentUser;
    final travelReady = _loadedProfile?.isCompleteForCustomerTravel == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('แก้ไขโปรไฟล์ไรเดอร์'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: <Widget>[
                  if (!travelReady)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDBA74)),
                      ),
                      child: const Text(
                        'ข้อมูลรถและรูปโปรไฟล์ยังไม่ครบ — ลูกค้า van2 จะไม่เห็นในหน้าเดินทางจนกว่าจะกรอกครบ',
                        style: TextStyle(
                          color: Color(0xFF9A3412),
                          height: 1.4,
                        ),
                      ),
                    ),
                  _sectionHeader(
                    'ข้อมูลส่วนตัว',
                    subtitle: 'แสดงให้ลูกค้าเห็นเมื่อจองงานเดินทาง',
                  ),
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
                  if (user?.email?.trim().isNotEmpty == true) ...<Widget>[
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: user!.email,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'อีเมล (อ่านอย่างเดียว)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _sectionHeader(
                    'รูปโปรไฟล์และข้อมูลรถ',
                    subtitle: 'van2 ใช้แสดงในหน้าเดินทาง',
                  ),
                  _imageTile(
                    title: 'รูปโปรไฟล์ (ใบหน้าชัดเจน)',
                    file: _profilePhotoImage,
                    existingUrl: _existingProfilePhotoUrl,
                    onPick: () => _pickImage(
                      (file) => setState(() => _profilePhotoImage = file),
                    ),
                  ),
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
                    onChanged: (value) => setState(() => _vehicleType = value),
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
                  const SizedBox(height: 20),
                  _sectionHeader(
                    'เอกสารยืนยันตัวตน',
                    subtitle: 'แก้ไขได้ทุกเมื่อ — แอดมินอาจตรวจสอบใหม่',
                  ),
                  _imageTile(
                    title: 'ใบขับขี่',
                    file: _licenseImage,
                    existingUrl: _existingLicenseUrl,
                    onPick: () => _pickImage(
                      (file) => setState(() => _licenseImage = file),
                    ),
                  ),
                  _imageTile(
                    title: 'รูปรถ',
                    file: _motorcycleImage,
                    existingUrl: _existingMotorcycleUrl,
                    onPick: () => _pickImage(
                      (file) => setState(() => _motorcycleImage = file),
                    ),
                  ),
                  _imageTile(
                    title: 'หน้าสมุดบัญชี',
                    file: _bookBankImage,
                    existingUrl: _existingBookBankUrl,
                    onPick: () => _pickImage(
                      (file) => setState(() => _bookBankImage = file),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionHeader('บัญชีรับเงิน'),
                  DropdownButtonFormField<String>(
                    value: _selectedBank,
                    items: _bankOptions
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
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _accountNumberController,
                    decoration: const InputDecoration(
                      labelText: 'เลขบัญชี',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _accountOwnerController,
                    decoration: const InputDecoration(
                      labelText: 'ชื่อบัญชี (ต้องตรงธนาคาร)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _pushOptIn,
                    onChanged: (value) => setState(() => _pushOptIn = value),
                    title: const Text('รับแจ้งเตือนงาน'),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(
                      _saving ? 'กำลังบันทึก...' : 'บันทึกโปรไฟล์',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
