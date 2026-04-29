# van3 Project Summary

## Project Overview

`van3` is the rider application in the van ecosystem. It is responsible for rider sign-in, online/offline availability, order intake, order acceptance, delivery workflow, rider-to-customer communication, and real-time location updates.

## Core Responsibilities

- Receive rider-assigned orders from Firestore.
- Show incoming order alerts and let the rider accept or decline.
- Display accepted jobs in the rider job list.
- Support rider-to-customer and rider-to-shop communication.
- Keep rider location updated while online.
- Sync FCM tokens so the rider can receive job, chat, and call notifications.

## Main Technical Stack

- Flutter
- Firebase Core
- Firebase Auth
- Cloud Firestore
- Cloud Functions
- Firebase Messaging
- Agora RTC Engine
- Geolocator
- Google Maps Flutter
- Shared Preferences
- Flutter Local Notifications
- Flutter Overlay Window

## Main App Areas

### App bootstrap

- `lib/main.dart`
- Initializes Firebase and background messaging.
- Starts overlay behavior for incoming order alerts.
- Maintains listener logic for new rider jobs.

### Rider home dashboard

- `lib/home_screen.dart`
- Controls rider online/offline mode.
- Starts location heartbeat while online.
- Provides entry points to new jobs, rider jobs, maps, scanning, and chat.
- Filters incoming rider-visible orders from `van2_customer` with confirmation guards.

### Incoming order handling

- `lib/incoming_order_screen.dart`
- Shows the full incoming order detail.
- Accept action writes Firestore status `accepted`.
- Decline action writes Firestore status `awaiting_rider`.
- Includes communication actions to call customer or shop.

### Accepted jobs list

- `lib/rider_jobs_screen.dart`
- Now shows only orders with status `accepted`.
- Does not show orders that are still `pending`.
- Does not show orders that were declined back to `awaiting_rider`.
- Used for the user requirement that an order must appear only after the rider presses accept.

### Chat and calling

- `lib/rider_chat_room_screen.dart`
- Rider chat interface.
- `lib/utils/order_call_launcher.dart`
- Shared rider call launcher used by order-related screens.
- Voice call flow is routed through the in-app call experience instead of relying only on raw phone dialing.

### Notifications and token sync

- `lib/services/fcm_token_sync_service.dart`
- Keeps rider FCM token in sync with the authenticated rider account.
- Supports push-driven order, chat, and call behavior.

## Current Verified Behavior

- The app runs on emulator targets from the workspace tasks.
- The rider app supports incoming order dialogs from Firestore-backed order changes.
- The accepted jobs page was updated so it only shows accepted orders.
- Orders that are not yet accepted, or are declined, should no longer appear in the rider "รับงานใหม่" page.

## Recent Project Work

- Rider/customer/store calling flow was aligned with the in-app calling flow.
- `rider_chat_room_screen.dart` was repaired after corruption issues.
- Android geolocator behavior was stabilized using Android-specific location settings.
- Incoming jobs visibility was tightened so only accepted jobs remain in the accepted-jobs screen.

## Deployment and Workspace Notes

- Firebase rules deployment scripts are included under `scripts/`.
- The workspace has dedicated VS Code tasks for deploy operations and emulator runs.
- The current workspace commonly runs `van3` on Android emulator `emulator-5554`.

## Current Request State

The latest completed functional change for `van3` is:

- Only show an order in the rider jobs page after the rider presses accept.
- Do not show the order there if it is still pending.
- Do not show the order there if the rider declined it.

## Suggested GitHub Project Record

Title:

`van3 rider app - full project status`

Suggested note body:

`van3` is the rider application for the van ecosystem. It handles rider availability, incoming orders, accepted jobs, chat, in-app calling, notifications, and live location updates. The project uses Flutter with Firebase Auth, Firestore, Functions, Messaging, Agora, Geolocator, Maps, and local notification/overlay support. Recent work includes rider call flow fixes, chat screen recovery, Android geolocation stabilization, and an update so the rider jobs page only shows orders after the rider has accepted them.