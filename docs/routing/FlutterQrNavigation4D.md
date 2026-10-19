# Phase 4D — QR checks during Navigation

## Existing contracts and reuse

`POST /api/routes` provides ordered `RouteNodeDto.Id` and `Floor.Id`. It does not
provide WayMarkCode for every route node. `GET /api/WayMarks/code/{code}/map-location`
returns a WayMark and its nullable node, including `Id` and `FloorId`.

Navigation opens `ScannerPage.verifyLocation` and receives `WayMarkMapLocation`
only after a successful authenticated lookup and the user's **Sử dụng QR này**.
The existing camera controller, permissions/errors, lifecycle, switching and
duplicate-detection gate are reused. This mode returns the result to Navigation;
it never opens Search or treats the QR as a new starting point.

The ordinary Scanner → map-location → Search flow is unchanged. Scanner now also
rejects non-positive node/floor IDs. Lookup errors retain the scanner error state;
404 has a QR-specific message. No backend/authentication/SQL changes are needed.

## Matching rules

`ManualNavigation.inspectQr` is read-only. It compares **node ID AND floor ID**.
WayMarkCode is sent to the lookup API; neither WayMarkCode nor NodeCode is used
as a substitute for node ID. `acceptQr` separately applies the result:

| Match | Behavior |
| --- | --- |
| Unique current occurrence | Record QR evidence; keep index, progress and completion unchanged. |
| Unique next occurrence | Advance one node after accepting the scanned QR. |
| Unique later occurrence | Show a confirmation dialog; cancellation makes no change. |
| Repeated node | Require an explicit occurrence choice, with no default. Current/forward choices are available; passed choices are disabled. A distant choice then requires jump confirmation too. |
| Unique passed occurrence | Warn and do not move backward automatically; use Bước trước. |
| Wrong node/floor or not on route | Warn and keep progress. |
| Missing/invalid link, 401, unavailable API, camera error or cancelled scan | No progress change. |

Application is guarded by navigation object identity and a revision counter, so
results from another session or an older state cannot be applied. The scan action
is serialized and manual Next/Previous are disabled until it returns.

## Evidence and progress

- UI distinguishes the current step's manual confirmation, QR match and no QR
  evidence. The map legend follows the source; its active node/floor still follow
  the route index.
- QR evidence is a code-to-node check at scan time. It is not continuous positioning,
  proof of traversing intermediate edges, or proof that a printed QR is installed
  in its intended physical place.
- Jumping to a later node records only the scanned target. Unconfirmed intermediate
  steps remain visibly marked, including after manual undo/advance. Progress is
  labeled as selected-route-step progress; reaching the endpoint this way does not
  claim all edges were traveled.
- Manual Next remains available. Moving manually clears current QR evidence; Undo
  clears evidence for steps being undone. No position sensor or timer is used.
- On a one-node route, a QR check does not auto-complete the route; explicit finish
  confirmation is still required.
- Checks are in memory only. Exiting/restarting Navigation creates a fresh session.

## Android Emulator walkthrough

Run the existing backend, then from `waymark/` use the actual ID from `flutter devices`:

```powershell
flutter run -d DEVICE_ID --dart-define=WAYMARK_API_BASE_URL=http://10.0.2.2:5121/api
```

Replace `DEVICE_ID` and the port as needed. For Chrome use `-d chrome` and the
existing host API address `http://localhost:5121/api`.

1. Log in, scan `WM-DEMO-2A-START`, choose `WM-DEMO-2A-DEST`, open the route and
   start Navigation as in Phase 4C.
2. Press **Quét QR xác nhận vị trí**, scan START again, choose **Sử dụng QR này**.
   Verify current-step QR evidence appears and progress stays unchanged.
3. Scan DEST while still at the beginning: verify jump confirmation appears.
   Cancel and check the unchanged state. Repeat and accept to check the endpoint,
   correct floor, QR source and unconfirmed-intermediate-step warning.
4. Exit to Preview and restart Navigation. Manually advance to the node immediately
   before DEST, then scan DEST: it should advance exactly one step without a jump
   dialog. Confirm the source reads QR rather than manual.
5. Test an existing linked QR outside the route, an unknown code, denied camera
   permission and unavailable API. On returning to Navigation, progress must remain.
6. Intermediate nodes need existing linked WayMarks to have usable QR codes. If
   only the two demo endpoint QR codes exist, use manual steps for intermediate
   nodes. Do not insert/update SQL records merely for this walkthrough.

Repeated occurrences and missing-node links are also covered by test fixtures;
they are not seeded into the real database. A route with a repeated node is not
assumed to exist in the current demo dataset.

Tests reuse the Scanner widget with camera and HTTP fakes, checking Bearer headers,
real navigation return flow, ambiguity/cancellation, cross-floor matches, stale
results and failure invariants. They do not constitute a new live camera/API/SQL
verification of Phase 4D; that requires the walkthrough above.

## Verification results (2026-10-18)

- `flutter analyze --no-pub`: no issues.
- `flutter test --reporter expanded`: 107 passed, one existing browser-only test
  skipped on the VM runner. Includes matching and Scanner-return widget tests for
  current/next/later nodes, explicit repeated occurrences, wrong floor, stale
  results, one-node completion, cancellation, 401/404/503, missing links, network
  failures and denied/unavailable/failed camera initialization.
- `flutter build apk --debug --no-pub`: succeeded; output
  `waymark/build/app/outputs/flutter-apk/app-debug.apk`.
- `git diff --check`: passed, with existing LF/CRLF normalization notices.
- Backend, SQL/migrations/seed, Windows generated plugin files and the user's
  existing Android Gradle configuration were preserved. No commit/push was made.
- New physical QR/API/SQL verification on the Emulator has not been performed
  during this implementation session. No test data was inserted into SQL Server.
