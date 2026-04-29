# Cross-App Test Checklist + Report (van1 <-> van3)

Date: 2026-04-20
Scope: order-based chat/call/notification between van1 (shop) and van3 (rider)

## A) Changes Applied In This Round

1. van1 order screen now supports rider chat/call directly from each order card.
2. van1 now sends app notifications to van3 when shop updates order status:
   - shop accepted order
   - shop rejected order
   - shop ready for pickup
3. van3 now sends app notification to van1 when rider rejects order (in addition to existing accepted notification).

## B) Files Updated

1. van1/my-flutter/lib/order_management_screen_new.dart
2. van3/lib/home_screen.dart

## C) Checklist + Pass/Fail Report

| ID | Test Case | Method | Result | Notes/Evidence |
|---|---|---|---|---|
| V13-01 | van1 order card shows rider chat button | Code + analyzer | PASS | Added order contact actions with ChatRoomScreen open path in order card. |
| V13-02 | van1 order card shows rider call button (tel:) | Code + analyzer | PASS | Added tel launcher from resolved rider phone in order contact actions. |
| V13-03 | van1 -> van3 notification when shop accepts order | Code + analyzer | PASS | Added app_notifications publish targetApp=van3 action=shop_accepted_order. |
| V13-04 | van1 -> van3 notification when shop rejects order | Code + analyzer | PASS | Added app_notifications publish targetApp=van3 action=shop_rejected_order. |
| V13-05 | van1 -> van3 notification when shop marks ready | Code + analyzer | PASS | Added app_notifications publish targetApp=van3 action=shop_ready_for_pickup. |
| V13-06 | van3 -> van1 notification when rider accepts order | Code inspection | PASS | Existing flow in van3 home screen targetApp=van1 action=order_accepted. |
| V13-07 | van3 -> van1 notification when rider rejects order | Code + analyzer | PASS | Added targetApp=van1 action=order_rejected in rider reject flow. |
| V13-08 | End-to-end runtime chat van1 <-> van3 via real order | Runtime manual test | FAIL | Blocked in this session: required emulator mapping for van3 not available. |
| V13-09 | End-to-end runtime call van1 -> rider via order | Runtime manual test | FAIL | Blocked by same environment/device availability gap. |
| V13-10 | End-to-end push notification round-trip van1 <-> van3 | Runtime manual test | FAIL | Blocked by same environment/device availability gap. |

## D) Validation Commands Executed

```bash
# van1
flutter analyze lib/order_management_screen_new.dart

# van3
flutter analyze lib/home_screen.dart
```

## E) Runtime Completion Steps

1. Start van1 on its mapped emulator and van3 on its mapped emulator.
2. Create a real order linked to shopOwnerId (van1 uid) and driverId (van3 uid).
3. Execute V13-08 to V13-10 and update FAIL -> PASS after verification.
