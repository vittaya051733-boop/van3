# Cross-App Test Checklist + Report (van2 <-> van3)

Date: 2026-04-20
Scope: chat, call, notify between van2 customer app and van3 rider app

## A) Changes Applied In This Round

- Added `customer_users` lookup for rider-side chat call button phone resolution.
- File: `van3/lib/rider_chat_room_screen.dart`

## B) Test Environment Snapshot

- `adb devices` result:
  - `emulator-5554` = `device`
  - `emulator-5556` = `device`
- Required rider emulator mapping (`van3 -> emulator-5558`) is currently unavailable in this session.

## C) Checklist + Pass/Fail Report

| ID | Test Case | Method | Result | Notes/Evidence |
|---|---|---|---|---|
| C01 | van3 rider chat resolves customer phone from `customer_users` | Code change + analyzer | PASS | Added lookup before riders/registrations in `rider_chat_room_screen.dart`; `flutter analyze lib/rider_chat_room_screen.dart` passed. |
| C02 | Chat ID format compatibility (`chat_<uidA>_<uidB>` sorted) between van2 and van3 | Code inspection | PASS | van2 `ChatService.chatIdFor` and van3 `_chatId` both sort UIDs and use same prefix. |
| C03 | Backend notification token routing (`van2 -> customer_users`, `van3 -> riders`) | Syntax check + code inspection | PASS | `node --check van2/functions/index.js` passed; routing logic matches target app in `resolveRecipientFcmToken`. |
| C04 | van3 can publish cross-app app notifications to Firestore | Code inspection | PASS | `_sendOrderAppNotification` writes `app_notifications` with `targetApp`, `recipientUid`, `title`, `body`, `action`. |
| C05 | van2 reads unread app notifications for target app `van2` | Code inspection + analyzer | PASS | `notifications_screen.dart` query filters `targetApp == 'van2'`, `recipientUid`, `read == false`; analyzer only info-level hints. |
| C06 | End-to-end chat van2 -> van3 runtime send/receive | Runtime manual test | FAIL | Blocked: van3 mapped emulator `5558` not available now, cannot complete paired runtime check in this round. |
| C07 | End-to-end call van3 -> van2 with customer phone resolution | Runtime manual test | FAIL | Blocked by same environment gap as C06; runtime call path not executed in this round. |
| C08 | End-to-end notification van3 -> van2 push delivery | Runtime manual test | FAIL | Blocked by same environment gap as C06; delivery/foreground receipt not executed in this round. |

## D) Commands Executed This Round

```bash
# van3
flutter analyze lib/rider_chat_room_screen.dart

# van2
flutter analyze lib/chat_room_screen.dart lib/notifications_screen.dart

# van2/functions
node --check index.js

# device state
adb devices
```

## E) Remaining Steps To Reach 100% Runtime Confirmation

1. Bring up `emulator-5558` (van3 mapped device) and ensure `adb devices` shows it as `device`.
2. Run van2 on `emulator-5554` and van3 on `emulator-5558`.
3. Execute C06, C07, C08 in sequence and update results from FAIL -> PASS when verified.
