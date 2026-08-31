/// In-memory unlock flag for the current app process.
class AppUnlockSession {
  AppUnlockSession._();

  static bool _unlocked = false;

  static bool get isUnlocked => _unlocked;

  static void unlock() {
    _unlocked = true;
  }

  static void lock() {
    _unlocked = false;
  }
}
