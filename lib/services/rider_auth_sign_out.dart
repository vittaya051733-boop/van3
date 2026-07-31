import 'package:firebase_auth/firebase_auth.dart';

import 'fcm_token_sync_service.dart';

class RiderAuthSignOut {
  RiderAuthSignOut._();

  static Future<void> signOut() async {
    await FcmTokenSyncService.instance.clearTokenBeforeLogout();
    await FirebaseAuth.instance.signOut();
  }
}
