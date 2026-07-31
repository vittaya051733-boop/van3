# van3 white screen — reproduction matrix

Use after installing a build that includes the startup deferral fix.

| Scenario | Steps | Expected after fix |
|----------|-------|-------------------|
| Cold start | Force-stop app, open from launcher (no notification tap) | Welcome or home within ~2s; log `[van3:startup] runApp` |
| Open from notification | Tap order/announcement push, then open app | No white hang; initial message handled after first frame |
| Clear app data | Settings → Apps → RIDER → Clear storage → open | Welcome screen |
| Logged-in approved rider | Sign in as approved rider | Home dashboard (orange gradient) |
| Release APK | Install release/sideload build | Same as debug unless App Check blocks Firestore |

## Logcat (when adb available)

```powershell
adb logcat -s flutter MainActivity
```

Look for:
- `[van3:startup] begin/done/skip` for each init step
- `[van3:startup] runApp` before UI appears
- `initial message handling skipped` if FCM path times out

## adb not on PATH

Install Android SDK platform-tools or run from `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`.
