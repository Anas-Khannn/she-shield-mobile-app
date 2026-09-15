# Phase 7 — Android/iOS Permissions & Native Configuration Audit Report

She Shield · Flutter client + native configuration
Date: 2026-09-16
Scope: Runtime permission handling, SOS capability isolation, Android/iOS
native configuration, and platform limitation documentation.

---

## 1. Executive summary

The audit found the app's permission posture was already largely correct and
least-privilege focused: no `CALL_PHONE`, no `SEND_SMS`, no
`ACCESS_BACKGROUND_LOCATION`, no `POST_NOTIFICATIONS`, no iOS background modes.
SOS already used the honest platform mechanisms (dialer via `tel:`, SMS
composer via `sms:`) and kept every action fault-isolated. Two real gaps were
closed:

1. A centralized permission abstraction existed but was **dead code** — nothing
   wired into it, and its *phone* method would have requested `CALL_PHONE`,
   which the app must never ask for.
2. **Microphone access was never requested** — `MediaService` only *checked*
   the permission and failed silently, so a fresh install could never record
   SOS evidence.

**Test status**
- Flutter: 186 tests passing (controllers, services, widgets) after adding
  permission-service, location-service, and SOS permission-isolation tests.
- `flutter analyze`: 0 errors, 0 warnings (1 pre-existing deprecation info in
  `supabase_initializer.dart`, intentionally left).

---

## 2. Permission architecture

`lib/services/permission_service.dart` is now the single permission abstraction.
UI code never touches platform enums or catches `PlatformException` — everyone
talks to:

```
Feature  →  PermissionService (request/check)  →  PermissionResult  →  action
```

`PermissionResult` distinguishes all the states the OS can express:

| Status | Meaning |
|---|---|
| `granted` | Full access |
| `limited` | iOS partial/provisional grants — feature may proceed |
| `denied` | Refused; a prompt can still be shown later |
| `permanentlyDenied` | OS will never prompt again → route to settings |
| `restricted` | Device policy (managed device / parent controls) |
| `unavailable` | Permission not defined on this platform |
| `error` | Platform channel failure (never leaks raw exceptions) |

The raw-to-typed mapping (`PermissionResult.fromStatus`) is public so it is
unit-tested without a device.

### Phone capability — deliberately NOT `CALL_PHONE`
`canOpenPhoneDialer()` is a **capability** check via `canLaunchUrl('tel:')`.
Launching the dialer (`ACTION_DIAL`, iOS `tel:`) needs no permission. The old
`requestPhone()`/`checkPhone()` methods were removed — requesting
`Permission.phone` on Android would have surfaced `CALL_PHONE`/`READ_PHONE_STATE`
for no benefit.

---

## 3. Feature-by-feature review

### Location (while-in-use only)
- `LocationService` checks service-enabled → permission → requests once →
  obtains a fix with a 15s timeout; maps every outcome to a structured
  `LocationFailure` (`serviceDisabled`, `permissionDenied`,
  `permissionPermanentlyDenied`, `timeout`, `unavailable`, `unknown`).
- On failure it returns `null` — the SOS coordinator records `location = failure`
  and **no other action is skipped**. No coordinates are ever fabricated.
- **No background location requested.** SOS location is read while the user is
  holding the app in the foreground.

### Microphone / audio
- **Fixed:** the SOS recording action now requests microphone permission
  *contextually* (right before recording) via `PermissionService`. A denial,
  permanent denial, or platform error becomes an isolated `recording` failure
  with a clear message; every other action still runs.
- Recording is **foreground-only**. No iOS `audio` background mode, no Android
  foreground service. Documented in `MediaService` — background capture is not
  guaranteed (iOS suspends the audio session; Android may kill the process).

### Vibration
- `VIBRATE` manifest permission present (Android). No runtime permission.
- Independent action: a vibrator absence or failure never stops location, call,
  contacts, or audio.

### Phone calling (dialer)
- Uses `tel:` + `url_launcher` (`LaunchMode.externalApplication`) → platform
  dialer. No `CALL_PHONE`.
- Handled outcomes: missing primary contact, invalid number, dialer
  unavailable (`canLaunchUrl` false), launch failure, user cancellation (the OS
  owns the dialer UI). All become a structured `call` failure only.

### SMS / contact notification (composer)
- Uses `sms:` + `url_launcher` → platform SMS composer. No `SEND_SMS`, no
  silent background SMS claims.
- Handled: no contacts, invalid numbers (skipped), unavailable composer,
  launch failure, user cancellation.
- With a location fix a real Google Maps link is included; without one a
  location-unavailable fallback message is used. Fake coordinates are never
  generated or claimed.

### Notifications
- Not used anywhere. No `POST_NOTIFICATIONS`, no notification channel/iOS
  authorization code, no `flutter_local_notifications`. None added — there is
  no feature that needs them.

### Background execution
- Nothing runs in the background. Safety Timer only *reconciles on resume*;
  it does not run SOS while terminated (OS may kill the app). No
  `ACCESS_BACKGROUND_LOCATION`, no UIBackgroundModes, no background service.

---

## 4. Android changes

| File | Change | Why |
|---|---|---|
| `AndroidManifest.xml` | **Removed** `WRITE_EXTERNAL_STORAGE` | Audio is written to app-private storage (`path_provider` documents dir) — no storage permission needed on any API level |
| `AndroidManifest.xml` | Documented each remaining permission + the deliberately-absent list | Least-privilege review artifact |

Final Android permission set (all with a real consumer):

- `ACCESS_FINE_LOCATION` + `ACCESS_COARSE_LOCATION` — SOS GPS (while-in-use)
- `RECORD_AUDIO` — SOS audio evidence
- `VIBRATE` — SOS distress vibration
- `<queries>`: `PROCESS_TEXT` (Flutter engine), `SENDTO sms:`, `ACTION_DIAL`

No changes to MainActivity, Gradle, SDK versions, or R8: `compileSdk`/`minSdk`/
`targetSdk` use Flutter defaults, AGP 8.11.1 / Kotlin 2.2.20 / Java 17 match the
project's Flutter version — nothing to upgrade. Flutter's Android migrator, run
during the validated debug build, appended the two compatibility flags now
committed in `android/gradle.properties` (`android.builtInKotlin=false`,
`android.newDsl=false`).

## 5. iOS changes

`Info.plist` required no edits — it already contains accurate usage strings for
the only protected resources the app touches:

- `NSLocationWhenInUseUsageDescription` (SOS location sharing)
- `NSMicrophoneUsageDescription` (SOS audio evidence)
- `LSApplicationQueriesSchemes`: `tel`, `sms` (needed by `canLaunchUrl`)

No `NSCameraUsageDescription` is required: the unused `camera` dependency was
removed (see §6), so no camera access exists to describe. No `Runner.entitlements`
exists and none is needed: no push, no background audio/location, no App Groups.
Deployment target stays `13.0`.

## 6. Dependency change

- **Removed the unused `camera` dependency** from `pubspec.yaml`. Nothing in
  `lib/` or `test/` referenced it. Removing it eliminates a plugin family from
  the build (smaller surface), the iOS `NSCameraUsageDescription` obligation,
  and Android camera framework overhead. No feature used it.
- **Added a test-only dev dependency** `geolocator_platform_interface` so
  `location_service_test.dart` can inject a fake `GeolocatorPlatform`.
- No transitive production dependencies changed (verified by `flutter pub get`).

## 7. Safety Timer integration

Unchanged by design. The timer stays a pure deadlines/restore coordinator:

```
Safety Timer expires  →  SOSCoordinator (duplicate-guarded)  →  SOSController
```

Permission handling and emergency actions remain owned by the SOS layer, not
the timer. Lifecycle (resume/pause) continues to reconcile the timer without
double-triggering SOS.

## 8. Auth integration

Permissions remain fully device-local. An expired backend session clears the
auth state and routes to login; it has **no effect** on `PermissionService`,
`LocationService`, or the SOS flow. Verified by the existing
"SOS independence from authentication" test and unchanged by this phase.

## 9. Lifecycle

- Safety Timer: `handleAppLifecycleState` stops/starts the ticker and
  reconciles on resume (no duplicate SOS — two-layer guard).
- Recording: intentionally **no** resume/stop hooked to lifecycle. The app does
  not claim background capture; documented in `MediaService`.
- Permission requests are contextual and single-instance; the coordinator's
  duplicate trigger guard prevents overlapping SOS sessions.

## 10. Permission UX

Requests happen when the feature runs (SOS trigger), not at startup:
- Location card on Home refreshes the fix (and this is when permission is
  requested) instead of a launch-time prompt.
- Microphone is requested immediately before recording within the SOS flow.
- Never re-prompt after permanent denial; the result routes the user to
  settings via the message text.

## 11. Security / privacy review

- No secrets in any native configuration; no service-role key in mobile code
  (actively rejected at init); only `.env.example` files are tracked.
- No token/password logging; the only `debugPrint`s are SOS/timer error labels.
- Emergency records store only timer fields; contacts are phone numbers stored
  in `SharedPreferences` (no `READ_CONTACTS` permission used).
- Least-privilege: this phase **removed** permissions/dependencies, added none.

## 12. Platform limitations (documented, not "marketing")

- **SMS**: opens the platform SMS composer, pre-filled. The user must press
  send; silent background SMS is not performed (and is not permitted on the
  major platforms used here).
- **Calls**: opens the dialer. Flutter cannot silently place calls on iOS, and
  on Android auto-dialing would require `CALL_PHONE` + the user still sees the
  dialer.
- **Background execution**: the OS may suspend or terminate the app at any
  time; nothing is guaranteed in the background.
- **Background recording**: not guaranteed — no background audio capability is
  configured.
- **Location**: depends on device GPS hardware, user settings, and permission
  state; a granted permission does not guarantee a fix.
- **Permission granted ≠ capability guaranteed** (microphone busy, GPS
  unavailable, dialer absent).

## 13. Validation

- `flutter pub get` — OK (camera fully removed from the lockfile; no transitive
  production dependencies changed).
- `flutter analyze` — 0 errors, 0 warnings (1 pre-existing deprecation info in
  `supabase_initializer.dart`).
- `flutter test` — 186/186 passing (167 pre-existing + 19 new for permissions,
  location, and SOS mic-isolation).
- **Android debug build — SUCCESS.** `gradlew assembleDebug` completed with the
  Flutter migrator flags committed in `android/gradle.properties`; the packaged
  manifest was inspected and confirms the final permission set.
- Two environmental notes (host-specific, not project defects, not committed):
  1. The default JDK on this machine (Android Studio JBR 25) is incompatible
     with Gradle 8.14; the validated build used `JAVA_HOME
     = C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot`. The project's
     `compileOptions`/`jvmTarget` remain Java 17.
  2. The pub cache (`C:\Users\...\Pub\Cache`) and the project build dir (D:)
     are on different volumes, which triggers a known Kotlin incremental-cache
     bug; the build was run with `-Pkotlin.incremental=false`. Newer Kotlin
     (2.3.x) solves this, or the Gradle/AGP version can be raised when
     supported by the Flutter release used.
- **iOS build**: not executable on this Windows host — reported honestly, not
  claimed. `Info.plist` needs no changes (verified by inspection, §5).

## 14. Remaining risks / recommendations (non-blocking)

1. Persistent run-time prompts can still be double-invoked if SOS is retried
   quickly; consider a short in-memory debounce in `PermissionService`.
2. Recording file cleanup: past SOS recordings accumulate in app documents;
   a retention policy would avoid disk growth and stale sensitive audio.
3. Contacts and audio evidence live in plaintext on-device storage;
   `flutter_secure_storage` / on-disk encryption is the recommended follow-up.
4. Full Android/iOS capability validation requires physical-device testing on
   real hardware (permissions, dialer, composer, GPS).
