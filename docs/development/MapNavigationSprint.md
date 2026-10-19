# Map/navigation sprint implementation and review

Date: 2026-10-18. Branch: `auth-jwt-assignment`.

## Implemented slices

### 4E: QR rerouting

Navigation reuses `ScannerPage.verifyLocation` and the authenticated map-location
lookup. An off-route result is identified by database node ID **and floor ID**,
never by comparing WayMarkCode to NodeCode. The user must confirm rerouting.

`reroute_navigation.dart` creates a separate navigation state. The old state is
retained while loading and on cancellation, network/HTTP errors or invalid routes.
Before replacement it verifies route structure, first node/floor, unchanged
destination code and final node/floor, accessibleOnly, and all routing options.
Successful replacement starts at index zero with QR evidence and updates Preview
through a callback. No second request occurs merely when returning to Preview.
Failed/canceled camera or map-location operations cannot initiate rerouting.

### 5A: floor plan foundation

`FloorPlanCanvas` uses the decoded image dimensions with BoxFit.contain. Image and
graph are siblings in the same fitted rectangle and the same InteractiveViewer;
zoom, pan and resize therefore apply the same transform. Pointer coordinates for
draft edits are local to that transformed rectangle, normalized to 0–1. Reset zoom
is available. Graph-only/error fallback is explicitly labeled and has a neutral
grid, without fabricated rooms, scale or meter estimates.

Draft PNG/JPG input checks a 10 MB limit, matching extension/MIME/signature,
successful image header decoding, maximum 8192 pixels per side and 32 million
pixels. Selection uses browser file bytes, never arbitrary server filesystem paths.
JPEG/PNG corruption, unsupported formats and decoder errors are rejected. These
are local draft checks, not a replacement for future server-side upload validation.

Each draft carries actual SiteId/BuildingId/FloorId. Floor and parent API responses
are checked. Uploaded images never update FloorPlanImageUrl or patient routing.

### 5B: Figma source adaptation

Read `waymark/design-reference/figma-make/src/components/{HospitalMap,RoutePreferences,WaymarkUI}.tsx`,
mobile RoutePreview/Navigation/Scanner, admin MapBuilder, App.tsx, index.css and
WAYMARK-PROTOTYPE.md. The Make MCP returned resource links but resource reading
failed; the later local export resolved source access. The export was not changed.

- Navy/cyan/background/secondary tokens reuse AppColors; a scoped map theme adds
  locally bundled Inter 400/500/600/700 with SIL OFL license.
- Preview prioritizes the floor map with a draggable/click-expandable instruction
  sheet, actual distance, destination summary and a persistent Start button.
- Floor selection is vertical; repeated floor visits retain route order. Only
  route-response edges are drawn. Cross-floor transitions are marked, not bridged.
- Routes use cyan lines with white halo/arrows. QR evidence has a dashed navy ring;
  manual selected progress has an amber square. Unknown progress uses cyan outline.
- Navigation retains current/next edge cards and manual/QR controls. No time-driven
  progress, assumed indoor GPS, fake left/right instructions or ETA was introduced.
- Draft builder uses hierarchy selectors and a responsive node-list/canvas/property
  layout; property editing uses validated dialogs.

Differences intentionally retained: no hospital rooms, fixed 120 m, ETA, simulated
scanner cases, synthetic verified QR, fake publish or AI proposals from React.
Route DTOs supply BuildingId but not building name, so the map labels the actual
building ID rather than inventing a hospital/building name. No Make screenshot was
available for exact visual comparison. Flutter widget renderings were inspected
at 390×844 and tested at 1200×800; those use HTTP fixtures, not a live hospital map.

### 5C: usable local draft builder

Open **Map Builder** in the existing Admin drawer. API calls are GET only and use
the existing bearer token. Select Site → Building → Floor, copy the current floor
nodes/active same-floor edges into a detached draft, select/add/move nodes, enter
directed edges and measured meter distances, and propose WayMark links.

Node coordinates/types/codes, case-insensitive local duplicates, duplicate edges,
self-loops, missing references and nonpositive/nonfinite distances are checked.
A WayMark link is looked up through the existing API; an already linked different
published node/floor is not overwritten. Imported link proposals require rechecking
before any future publication. Global NodeCode uniqueness across all SQL floors
cannot be guaranteed by local draft validation; future publication must check it
server-side and rely on the existing database unique index.

On Web, choose PNG/JPG and **Xuất bản nháp JSON** to download a versioned draft with
image bytes. Confirm the download exists. **Nhập bản nháp JSON** validates version,
draft state, hierarchy, limits (18 MB file, 2000 nodes, 10000 edges), graph and image
before replacing state. Current local drafts are volatile until exported. Guards
cover changing hierarchy, system Back and the Admin drawer. Browser reload/closing
the tab can still lose unsaved state; export first.

Android can display/edit an in-memory draft, but file selection/export is currently
Web only and says so. No schema or production admin CRUD/publish endpoint was added.
Cross-floor draft editing, calibration, deletion tools and persistent server draft
storage remain future work. Published routing never reads these files or objects.

### 6A: restrictions versus preferences

Existing `POST /api/routes?accessibleOnly=true|false` remains JWT protected. Existing
two-code clients remain compatible. Optional request body:

```json
{
  "startWayMarkCode": "WM-DEMO-2A-START",
  "destinationWayMarkCode": "WM-DEMO-2A-DEST",
  "options": {
    "avoidStairs": true,
    "wheelchair": false,
    "preference": "PreferElevators"
  }
}
```

Successful responses echo `options` alongside existing nodes, edges and actual
`totalDistanceMeters`. Flutter checks the echo; an old backend ignoring new options
is rejected rather than silently displaying an unrestricted route.

| Option | Rule |
| --- | --- |
| accessibleOnly | Legacy hard filter on IsAccessible; does not certify wheelchair safety |
| avoidStairs | Hard filter excluding Stairs; never dropped automatically |
| ShortestDistance | Minimize stored physical meters, preserving existing default behavior |
| PreferElevators | Minimize Stairs/Ramp edge count, then physical meters; preference permits alternatives |
| LessWalking | Minimize non-Elevator meters, then physical meters; walking proxy only, no wait-time model |
| wheelchair | Fail closed with HTTP 422 `accessibility_not_verified`; no verified metadata is available |

The same Dijkstra uses nonnegative lexicographic decimal costs for preferences.
It still reports **physical distance**, not the preference score. Active/directed
edges, cross-floor transitions, deterministic ties, cancellation and overflow
handling are retained. X/Y are never used for distance. Unknown preference/null
options fail request validation with 400. Existing 401/404/409/422/503 behavior stays.
All options and accessibleOnly survive QR rerouting.

Wheelchair routing needs surveyed dimensions, restrictions and verification
evidence/status. No boolean, elevator label or demo flag is treated as sufficient.
That metadata and its publication workflow need approval before a schema change.

## Source inventory for this sprint

Backend changed: RouteDtos.cs, RoutesController.cs, RoutePlanner.cs, DijkstraRouter.cs,
RouteApiTests.cs. Added RoutingOptions.cs and RoutingOptionsTests.cs. No entity,
DbContext, auth, configuration or migration changes.

Flutter changed: route_models.dart, waymark_api_service.dart, navigation_page.dart,
manual_navigation.dart (existing untracked 4C/4D source), route_preview_page.dart,
floor_route_map.dart, admin_page_shell.dart, map_builder_page.dart, pubspec.yaml/lock,
navigation_qr_flow_test.dart and routing_flow_test.dart.

Added: map_ui_theme.dart; reroute_navigation.dart; floor_plan_canvas.dart;
route_preferences.dart; draft_map_editor.dart, draft_map.dart, floor_plan_asset.dart,
draft_files.dart/stub/web adapters; Inter fonts/license/provenance; draft_map_test.dart,
floor_plan_canvas_test.dart, routing_options_test.dart, route_preferences_test.dart,
map_layout_test.dart; this document and AutonomousSprint.md.

Pre-existing Scanner, Settings, Android Gradle and other uncommitted 4B–4D work is
retained. The three protected Windows generated files match their baseline hashes.

## Verification and remaining manual work

Final results: analyzer clean; 134 Flutter tests passed with one VM browser-only
skip; Web and Android debug builds passed; backend build passed and all 55 backend
tests passed; diff check passed. Full commands/warnings are in AutonomousSprint.md.
Tests use camera/HTTP
fakes and EF InMemory/TestServer with generated test JWT keys; no real SQL write or
seed was performed. They do not prove physical QR placement, Android camera behavior
after this sprint, wheelchair safety or operation on a real hospital map.

An optional fixture-only render check writes ignored PNGs under
`waymark/.dart_tool/sprint-previews`:

```powershell
flutter test --no-pub --dart-define=WAYMARK_CAPTURE_PREVIEWS=true test/map_layout_test.dart
```

The first capture attempt stalled awaiting image encoding in the widget fake async
zone; that exact test was interrupted. Capture now runs in tester.runAsync with
15-second image/encoding timeouts and has completed successfully. No SDK lock was
removed or unrelated Flutter/Dart process stopped.

### Run manually

The old API process was left running. Restart it deliberately in its own terminal
to load the new routing options (do not start a conflicting second listener):

```powershell
cd D:\project\WayMark
& 'C:\Program Files\dotnet\dotnet.exe' run --project WayMark.Api
```

Use the actual listener URL/port from that terminal. In a second terminal:

```powershell
cd D:\project\WayMark\waymark
flutter devices
flutter run -d chrome --dart-define=WAYMARK_API_BASE_URL=http://localhost:5121/api
# Android Emulator: replace DEVICE_ID with flutter devices output
flutter run -d DEVICE_ID --dart-define=WAYMARK_API_BASE_URL=http://10.0.2.2:5121/api
```

Replace port/address if the actual backend differs. Login through the existing flow.
Scan START, choose DEST, review the real route response (40 m only if the unchanged
demo graph still produces it), switch floors and expand/collapse instructions.
Check QR/manual markers and manual previous/next. For rerouting use an **existing**
linked WayMark outside the route; cancel first, then accept, and verify destination
and options remain. If no such WayMark exists, that live case needs separately
approved test data; no record was added during this sprint. Stop/unavailable API,
expired JWT and no-path cases must retain Navigation's previous state.

In Preview test avoid-stairs/preference options; wheelchair must return the explicit
unverified-data error without fallback. In Web MapBuilder test local image input,
node movement under zoom, edge meters, export/re-import for the same floor, wrong
floor rejection, and canceling a dirty draft navigation. These file-dialog behaviors
still need browser interaction beyond compile/unit coverage.

Before production: supply verified floor assets/graph measurements; approve role
provisioning, server draft storage, validation and publish design; survey accessibility;
review the baseline NuGet dependency advisories and restore access to vulnerability
feeds. No migration or SQL command is required for the source changes in this sprint.
