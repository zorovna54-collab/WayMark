# Android Scanner and Settings navigation

## Findings

- `AndroidManifest.xml` already declares CAMERA and INTERNET. No manifest,
  Gradle, package, API or authentication changes are required for these fixes.
- The only Settings screen is `AdminSettingsPage`. Home opens it with
  `Navigator.push`; admin drawer destinations use `pushReplacement`.
  Its shared `AdminPageShell` had a Drawer, so the default AppBar leading widget
  was the menu rather than an explicit Back button. No separate user Settings
  screen exists in the current source.
- The local AVD configuration for **Medium Phone API 37.0** was read without
  modification: `hw.camera.back=virtualscene`, `hw.camera.front=emulated`.
  These settings provide simulated images. Runtime flags can override AVD
  configuration; the actual preview and the previously seen camera notice were
  not observed during this task.

## Scanner changes

- Explicit rear-facing camera, QR only. Manual startup after MobileScanner is
  attached replaces mixed automatic/manual startup. Existing duplicate detection
  protection and map-location → Search flow remain in place.
- Stops on inactive/paused states; resumes a previously permitted healthy camera.
  Does not automatically re-prompt after a permission denial. Startup completing
  while the app is inactive stops its camera session.
- Permission denial, unavailable/unsupported camera and initialization failure
  have Vietnamese messages. Plugin errors also display the error code so an
  exact screenshot can be reported. Frame decode failures show a single notice.
- Error UI is no longer covered by the scan frame. Retry and Close are usable.
  Unexpected startup exceptions that leave the controller starting are handled
  by disposing that controller and creating a fresh one on explicit retry.
- Front/back switch appears only when the plugin confirms more than one camera,
  a front/back direction and a running camera. Unknown camera counts, external
  cameras, a single camera or an error do not advertise switching. Switching is
  serialized; it changes the Android/Web camera facing, not the host webcam.

## Settings behavior

- Explicit Back in the AppBar; the drawer remains accessible from a menu button
  on the opposite side.
- If there is a previous route, Back pops it. If Settings is the root route,
  Back replaces it with Home, without stacking another Home above Settings.
- Android/framework Back uses the same fallback. With the drawer open, Back
  closes the drawer first. AuthSession is neither cleared nor recreated.
- Other admin pages retain their existing shell behavior.

## Configure the Emulator yourself

1. Stop the AVD in Android Studio Device Manager.
2. Edit **Medium Phone API 37.0**, find Camera in advanced/additional settings,
   and choose the desired **Webcam** for the back-facing camera (the app's default)
   or front-facing camera. Names depend on the webcams detected on this computer.
3. Save and restart the AVD; use Cold Boot if a saved session retains old settings.
4. Confirm the source image in the Emulator's own Camera app before testing WayMark.
   If necessary, check host camera permission and close software occupying it.
5. In Android Settings → Apps → WayMark → Permissions → Camera, grant camera
   access, then return and use **Thử lại**. The app does not change AVD config.

Official references:
[AVD camera settings](https://developer.android.com/studio/run/managing-avds),
[emulator camera command-line options](https://developer.android.com/studio/run/emulator-commandline).

## Manual verification

From `waymark/`, use the actual device ID printed by `flutter devices`:

```powershell
flutter run -d <android-device-id> --dart-define=WAYMARK_API_BASE_URL=http://10.0.2.2:5121/api
```

Use the backend's actual listening port if different. For Chrome on this host:

```powershell
flutter run -d chrome --dart-define=WAYMARK_API_BASE_URL=http://localhost:5121/api
```

- Deny camera permission and verify the specific message and tappable retry.
  Then grant permission in Android/browser settings and retry.
- With camera permission and a working source, switch front/back if offered,
  background/resume the app, then scan a real WayMark QR. Confirm map-location
  and Search still use the scanned code as the starting point.
- Capture the full message/error code if initialization fails. Seeing a preview
  does not establish that QR recognition or API lookup succeeded.
- Open Settings from Home: verify both visible Back and Android Back return to
  the same Home and preserve login. Open/close the admin drawer before repeating.
- On Flutter Web verify the in-app Back button; browser toolbar Back should also
  be checked manually because the app uses imperative Navigator routes.

Unit/widget tests use camera fakes, not real camera devices or permissions.
`settings_navigation_test.dart` covers pushed/root routes, AppBar/system Back,
drawer closing and AuthSession preservation. `scanner_camera_test.dart` covers
denied/unsupported/generic and unexpected startup failures, retry, switching,
lifecycle, frame errors and disposal. Actual emulator webcam/QR capture is not
claimed by these tests.

## Verification results (2026-10-18)

- `flutter analyze --no-pub`: no issues.
- `flutter test --reporter expanded`: 71 passed, one existing browser-only test
  skipped on the VM runner. Camera errors and permissions use fakes.
- `flutter build apk --debug --no-pub`: succeeded; APK at
  `waymark/build/app/outputs/flutter-apk/app-debug.apk`. Java native-access warnings
  were printed, but no Kotlin/Gradle failure prevented the build.
- `flutter build web --no-pub --dart-define=WAYMARK_API_BASE_URL=http://localhost:5121/api`:
  succeeded.
- `git diff --check`: passed, with existing Git LF/CRLF normalization notices.
- The pre-existing `android/gradle.properties` edit was preserved; its SHA-256
  before and after building matched. Prior Phase 4B edits and Windows generated
  plugin files were not modified by this task.
- Neither the updated app's physical camera preview nor actual QR scanning on
  the Emulator was exercised. The original camera notice remains unidentified.
