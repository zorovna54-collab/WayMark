# Mobile Navigation MVP — 2026-10-21

## Delivered

- Existing API route lacks coordinates; `GET /Maps/floors/{id}/graph` remains the coordinate source. No backend change.
- Missing floor image previously meant a dotted grid. Added explicitly synthetic Demo Map PNGs for G/L1, generated from `SeedDemoMap2A.sql` coordinates, not an arbitrary clinic photograph.
- Image is attached only when floor code, unique node codes/IDs, types, coordinates, active directed edges and route segments match the fixture. API IDs are resolved dynamically. A mismatching graph retains the regular graph-only display. A configured floor image takes precedence.
- Image and route reuse the same contained canvas and transform. Floor transitions have markers, never a line across diagrams. Fit Image, image toggle and touch zoom/pan remain available.
- Compact Preview/Navigation expose more map area; current-leg type, next node and distance are visible at the top. Arrival confirmation is visible without scrolling. Manual progress, QR confirmation and backend rerouting are preserved.
- Search recognizes **001 / Phòng 001 / Tiếp nhận** only after validating the API WayMark → actual Entrance node → matching graph. The demo room ends at G-ENTRY, not its centre. L1-DEST is a Destination, so it has no invented room entrance.

## Files in this sprint

Modified (all under `waymark/`): `pubspec.yaml`, `lib/features/search/search_page.dart`, `lib/features/route/route_preview_page.dart`, `lib/features/route/floor_route_map.dart`, `lib/features/navigation/navigation_page.dart`.

Added (under `waymark/`): `lib/features/route/demo_floor_plan.dart`; `assets/demo_maps/hospital_2a.json`, `ground.png`, `level1.png`; `tool/generate_demo_floor_plans_test.dart`, `tool/mobile_demo_data.dart`, `tool/mobile_map_demo.dart`; `test/mobile_demo_map_test.dart`. Documentation: `docs/MobileNavigationMvp.md`.

## Run the real app

```powershell
cd D:\project\WayMark\waymark
flutter run -d emulator-5554 --dart-define=WAYMARK_API_BASE_URL=http://10.0.2.2:5121/api
```

Use the port where your existing API actually listens; 5121 is the current client default. The emulator uses `10.0.2.2` to reach the Windows host. This sprint did not start or change SQL Server/backend configuration.

1. Log in normally; scan START → select DEST to inspect the original 40 m route and both floor images.
2. For the room flow, scan **WM-DEMO-2A-DEST**, search **001**, choose the Demo room. The backend should return the reverse route to **WM-DEMO-2A-START / G-ENTRY** if the seeded graph remains unchanged.
3. Preview both floors; pinch/pan and Fit Image; image and line must remain aligned.
4. Start Navigation; confirm steps manually; at the lift verify the floor changes and no cross-floor line appears.
5. Test QR current/next/later/repeated/off-route, cancel reroute, API offline and expired JWT. Failed/cancelled operations must preserve progress, destination and session. A confirmed late jump must still show unconfirmed intermediate steps.
6. Complete, step back and finish to Preview. Neither elapsed time nor reopening a floor should advance progress.

## Explicit offline visual rehearsal

```powershell
flutter run -d emulator-5554 -t tool/mobile_map_demo.dart
```

This separate target has a persistent **DEMO OFFLINE** banner. It reuses Search/Preview/Navigation with a fixed fixture service and makes no HTTP/SQL calls or AuthSession changes. It is not imported by production `main.dart`, does not provide a local production routing fallback, and rejects accessibility/options it cannot verify. Run the normal command above afterwards to return to the real app.

## Verification

- `flutter analyze --no-pub`: passed.
- `flutter test --no-pub --reporter expanded`: 181 passed, 1 Web-only skipped (six new tests).
- New tests cover graph mismatch rejection, room Entrance validation/search, the ordered two-floor route, actual PNG corridor pixels, image rendering/floor selection/zoom/Fit/resize, Search → Preview → Navigation and manual arrival without a timer.
- `flutter build apk --debug --no-pub`: passed for normal `lib/main.dart`.
- `flutter build web --no-pub`: passed for normal `lib/main.dart`.
- Emulator-5554: offline room search, Preview G/L1, manual Navigation L1 → G → arrival were exercised. Screenshots: `waymark/build/mobile-evidence/01-search.png` through `06-arrival.png` (ignored build artifacts). Main APK copy: `waymark/build/mobile-evidence/waymark-main-debug.apk`.
- `git diff --check`: passed. Preexisting-file hash comparison confirms only the five intended Flutter files changed in this sprint; backend, SQL plans, Gradle, Windows generated and Figma files were preserved.

## Limits

- No real hospital spatial survey, published map or production Room API integration. This is a schematic aligned with a demo graph, not a verified hospital plan; pixels do not determine metres.
- Home's existing “Gần đây” section is the first three API WayMarks, not personal navigation history. It was left unchanged; this sprint does not implement History.
- Real camera scanning, real JWT/API/SQL and two-finger emulator gestures were not re-tested manually in this sprint. Automated QR/rerouting/session/transform regression passed; perform the checklist above with the existing backend.
- Wheelchair safety is unknown. No new accessibility claims, automatic positioning, timers, Admin APIs, SQL writes, migrations or publishing.
