import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum RiderAccessStatus {
  approved,
  pending,
  rejected,
  needsRegistration,
}

class RiderRegistrationService {
  RiderRegistrationService._();

  static const String collection = 'rider_registrations';
  static const String privacyPolicyVersion = '2026-06-01';

  static Future<RiderAccessStatus> resolveAccessStatus(String uid) async {
    DocumentSnapshot<Map<String, dynamic>>? registration;
    try {
      registration = await FirebaseFirestore.instance
          .collection(collection)
          .doc(uid)
          .get();
    } catch (_) {
      // Missing Firestore rules or transient read errors — fall back to riders doc.
      registration = null;
    }

    DocumentSnapshot<Map<String, dynamic>>? rider;
    try {
      rider = await FirebaseFirestore.instance.collection('riders').doc(uid).get();
    } catch (_) {
      rider = null;
    }

    return statusFromSnapshots(
      registration: registration,
      rider: rider,
    );
  }

  static RiderAccessStatus statusFromSnapshots({
    DocumentSnapshot<Map<String, dynamic>>? registration,
    DocumentSnapshot<Map<String, dynamic>>? rider,
  }) {
    if (registration != null && registration.exists) {
      final status =
          registration.data()?['registrationStatus']?.toString() ?? 'pending';
      return switch (status) {
        'approved' => RiderAccessStatus.approved,
        'rejected' => RiderAccessStatus.rejected,
        _ => RiderAccessStatus.pending,
      };
    }

    final riderData = rider?.data();
    final riderStatus = riderData?['registrationStatus']?.toString();
    if (riderStatus == 'approved') {
      return RiderAccessStatus.approved;
    }
    if (riderStatus == 'pending') {
      return RiderAccessStatus.pending;
    }
    if (riderStatus == 'rejected') {
      return RiderAccessStatus.rejected;
    }

    final hasBank = _hasBankProfile(riderData);
    if (rider != null && rider.exists && hasBank && riderStatus == null) {
      return RiderAccessStatus.approved;
    }
    return RiderAccessStatus.needsRegistration;
  }

  static Stream<RiderAccessStatus> watchAccessStatus(String uid) {
    DocumentSnapshot<Map<String, dynamic>>? registration;
    DocumentSnapshot<Map<String, dynamic>>? rider;
    late final StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>
        registrationSub;
    late final StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>
        riderSub;

    late final StreamController<RiderAccessStatus> controller;
    controller = StreamController<RiderAccessStatus>(
      onListen: () {
        void emit() {
          if (!controller.isClosed) {
            controller.add(
              statusFromSnapshots(registration: registration, rider: rider),
            );
          }
        }

        registrationSub = FirebaseFirestore.instance
            .collection(collection)
            .doc(uid)
            .snapshots()
            .listen(
              (snapshot) {
                registration = snapshot;
                emit();
              },
              onError: (_) {
                registration = null;
                emit();
              },
            );

        riderSub = FirebaseFirestore.instance
            .collection('riders')
            .doc(uid)
            .snapshots()
            .listen(
              (snapshot) {
                rider = snapshot;
                emit();
              },
              onError: (_) {
                rider = null;
                emit();
              },
            );
      },
      onCancel: () async {
        await registrationSub.cancel();
        await riderSub.cancel();
      },
    );

    return controller.stream;
  }

  static bool _hasBankProfile(Map<String, dynamic>? data) {
    if (data == null) {
      return false;
    }
    return data['bankName']?.toString().trim().isNotEmpty == true &&
        data['accountNumber']?.toString().trim().isNotEmpty == true &&
        (data['accountOwner']?.toString().trim().isNotEmpty == true ||
            data['accountName']?.toString().trim().isNotEmpty == true);
  }

  static Future<void> submitRegistration({
    required User user,
    required String phoneNumber,
    required String displayName,
    required String bankName,
    required String accountNumber,
    required String accountOwner,
    required String contactEmail,
    required String driverLicenseImageUrl,
    required String motorcycleImageUrl,
    required String bookBankImageUrl,
    required bool acceptedPrivacy,
    bool marketingOptIn = false,
    bool pushOptIn = false,
  }) async {
    if (!acceptedPrivacy) {
      throw StateError('ต้องยอมรับนโยบายความเป็นส่วนตัว');
    }

    final now = FieldValue.serverTimestamp();
    final normalizedContactEmail = contactEmail.trim();
    final resolvedEmail = normalizedContactEmail.isNotEmpty
        ? normalizedContactEmail
        : (user.email?.trim() ?? '');
    final payload = <String, dynamic>{
      'uid': user.uid,
      'email': resolvedEmail,
      if (normalizedContactEmail.isNotEmpty) 'contactEmail': normalizedContactEmail,
      'phoneNumber': phoneNumber,
      'displayName': displayName,
      'bankName': bankName,
      'accountNumber': accountNumber,
      'accountOwner': accountOwner,
      'accountName': accountOwner,
      'driverLicenseImageUrl': driverLicenseImageUrl,
      'motorcycleImageUrl': motorcycleImageUrl,
      'bookBankImageUrl': bookBankImageUrl,
      'registrationStatus': 'pending',
      'privacyPolicyVersion': privacyPolicyVersion,
      'privacyAcceptedAt': now,
      'marketingOptIn': marketingOptIn,
      'pushOptIn': pushOptIn,
      'role': 'rider',
      'userType': 'rider',
      'updatedAt': now,
      'createdAt': now,
      'submittedAt': now,
    };

    final batch = FirebaseFirestore.instance.batch();
    final registrationRef =
        FirebaseFirestore.instance.collection(collection).doc(user.uid);
    final riderRef = FirebaseFirestore.instance.collection('riders').doc(user.uid);
    batch.set(registrationRef, payload, SetOptions(merge: true));
    batch.set(riderRef, payload, SetOptions(merge: true));
    await batch.commit();
  }
}
