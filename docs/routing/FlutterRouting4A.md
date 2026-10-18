# Flutter routing integration — Phase 4A

## Flow

1. Log in using the existing login screen. Requests read the Bearer token from
   `AuthSession` at request time; no second authentication mechanism is added.
2. Scanner normalizes the QR, calls
   `GET /api/WayMarks/code/{code}/map-location`, and accepts the starting point
   only when its linked node is non-null. Repeated camera detections remain blocked
   until the user explicitly scans again.
3. Select **Chọn điểm đến** to open Search with the verified starting point.
   Search loads the existing WayMarks endpoint and filters name/location/code.
4. Selecting a destination opens Preview, which calls
   `POST /api/routes?accessibleOnly=false` (or `true` when selected in Search).
   The JSON body contains only `startWayMarkCode` and `destinationWayMarkCode`.
5. Preview displays the returned distance and ordered nodes/edges, including
   floor names and elevator transitions. It does not infer left/right turns,
   physical coordinates, travel time, or current position.

Home destination shortcuts open Search filtered by code. If Search has no starting
point, selecting a destination opens Scanner and resumes that selection after a
successful lookup. Cancelling Scanner does not submit a route. The old History
shortcut opens Search to choose a fresh route; its static entries are not treated
as saved backend routes.

## Run locally

Keep the configured backend running. If it is stopped, from repository root:

```powershell
dotnet run --project .\WayMark.Api\WayMark.Api.csproj --launch-profile http
```

The existing `http` launch profile declares `http://localhost:5121`. Check the
actual `Now listening on` log if environment settings override it. In another terminal:

```powershell
cd D:\project\WayMark\waymark
flutter run -d chrome --dart-define=WAYMARK_API_BASE_URL=http://localhost:5121/api
```

Use the actual API URL when different. Include `/api` once. Trailing slashes are
removed; routing endpoints share the existing `WayMarkApiService.baseUrl`.
Do not restart an already running backend or change database/JWT configuration.

Android emulator uses the existing `10.0.2.2` fallback. A physical Android device
needs a reachable API address via the same dart-define and the existing camera
permission. Web uses `kIsWeb` before native platform decisions; localhost browser
camera still requires user permission. HTTPS pages need a compatible HTTPS API.

## Manual check against the existing database

- Log in, scan `WM-DEMO-2A-START`, verify that the starting point appears in Search.
- Choose `WM-DEMO-2A-DEST` with the accessible filter off. With the unchanged demo
  data, the expected route is 40 m, as previously checked by the user in Swagger.
  Confirm the floor transition and server-returned node/edge sequence.
- Toggle the accessible filter and check the server result without assuming that
  it certifies wheelchair suitability.
- Verify invalid QR, unknown QR, a WayMark without a node, expired/missing JWT,
  unavailable API and a destination with no route. These need suitable existing
  data; do not insert records solely for this check without approval.
- Inspect DevTools for one map-location request per scan and one POST per selection.
- Refreshing the browser clears the existing in-memory AuthSession; log in again.

## Tests and boundaries

`routing_api_test.dart` checks DTO parsing, ordered edges, decimal display,
request/JWT/query contract, HTTP errors, invalid JSON, network failure and timeout.
`routing_flow_test.dart` uses an in-memory camera adapter and MockClient to test
Scanner → Search → Preview, repeated scans, retry and error states. These tests
do not exercise a physical camera, real JWT validation, SQL Server or real API I/O.

Preview no longer draws the old fabricated map, displays fake ETA, or opens the
legacy Navigation page. Live navigation is disabled explicitly. The legacy
`navigation_page.dart` still contains its old mock UI/timer but has no callers in
the application; it is not instantiated by this flow. History synchronization,
spatial map rendering and live movement tracking remain outside this phase.

No backend, database, migration, seed, authentication configuration, dependency,
or Windows generated plugin file is changed by this integration.

## Verification in this workspace (2026-10-18)

- `flutter analyze --no-pub`: passed with no issues.
- `flutter test --reporter expanded`: 43 passed, one browser-only test skipped
  on VM. Camera and HTTP are test adapters, not real devices/services.
- `flutter test --platform chrome test/routing_api_test.dart test/routing_flow_test.dart --reporter expanded`:
  failed to load both suites with `Connection closed before test suite loaded`.
  No browser test assertions ran; the cause of the browser connection closing
  has not been established.
- `flutter build web --no-pub --dart-define=WAYMARK_API_BASE_URL=http://localhost:5121/api`:
  succeeded, output `waymark/build/web` (ignored build artifacts).
- `git diff --check`: passed.
- Real login → physical QR scan → authenticated routing against SQL Server and
  Android device testing were not performed in this implementation session.
