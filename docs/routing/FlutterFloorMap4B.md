# Phase 4B: floor route visualization

## Data sources

- `POST /api/routes` (`RouteResponseDto`) supplies ordered node IDs, floor metadata,
  directed edges and total distance. It does **not** supply X/Y.
- The existing JWT protected `GET /api/Maps/floors/{floorId}/graph`
  (`FloorGraphDto`) supplies normalized X/Y for each node on that floor.
- `WayMarkApiService.getFloorGraph` uses the existing base URL, token and timeout.
  It validates the floor ID, node floor IDs, unique node IDs and response types.
- `FloorMapData` deliberately ignores graph edges. Some graph edges may be inactive
  or not part of the route; drawing uses only edges in the routing response.

No backend, database or migration changes are required.

## Map behavior

`FloorRouteMap` is inserted above the existing node/edge instructions in Preview's
scrollable content. Summary distance remains the value returned by the API.

- Floor selectors follow first appearance in the route, not numeric ID order.
  The text below the selectors shows consecutive floor visits, including repeats
  such as F1 → F2 → F1.
- One floor graph is requested when selected, then cached for this widget's lifetime.
  Map state is retained while scrolling down to the instructions. A new route
  clears the graph cache. A failed read has an explicit retry button and does not
  discard the route summary or instructions.
- `LayoutBuilder` sizes the canvas for the available width. Coordinates use a
  top-left origin, X increasing right and Y increasing down. A point is projected
  as `(X * contentWidth, Y * contentHeight)` after the canvas padding.
- `FloorRouteGeometry` associates coordinates by node ID and floor ID, preserving
  route index. It never sorts nodes by coordinate or floor to rebuild a path.
- Every same-floor route edge becomes a directed polyline segment. Separate
  subpaths prevent an invented connection across a missing node or return visit.
  Arrows show direction; numbers on markers match the instruction step numbers.
- Cross-floor edges are never drawn as lines. Their endpoint receives an orange
  ring and a caption indicating departure/arrival and the other floor. E/T labels
  mark elevator/stairs nodes; S/Đ mark the global start/destination. A same-node
  start/destination has one SĐ marker and no route line.
- Missing/out-of-range/non-finite coordinates cause warnings and omission of
  affected segments. Empty routes and invalid/missing floor information have
  explicit messages. No coordinate is invented or clamped into a valid range.

## Floor images and limits

`FloorPlanImageUrl` is nullable in both the floor graph and routing DTO. The checked
demo seed source sets it to NULL; the live database was not queried in this task.
When no absolute HTTP(S) image URL is provided, a clearly labeled plain node
diagram is shown. No fake walls, corridors or floor image is generated.

When an absolute HTTP(S) URL without userinfo is provided, the image is fitted to
the exact same content rectangle as the coordinates. Both are resized together;
this display has no physical scale. A failed image load falls back to the plain
diagram with a message. Relative URLs and protected images requiring a Bearer
header are not supported in this phase; JWT is never forwarded to image hosts.
Browser image loading remains subject to HTTPS/CORS and server availability.

Edges have endpoint coordinates but no intermediate corridor geometry. Straight
segments represent graph connections, not surveyed corridor shapes. The system
does not infer turns, GPS, live position, ETA or movement progress. Separate
route/graph requests do not provide an atomic map version; if graph data changes,
the user may need to request a new route. Missing nodes are shown explicitly.

## Local run and manual demo check

Keep the already configured backend running. If stopped, from repository root:

```powershell
dotnet run --project .\WayMark.Api\WayMark.Api.csproj --launch-profile http
```

Use its actual listening URL. The existing http launch profile uses port 5121.
In a separate terminal:

```powershell
cd D:\project\WayMark\waymark
flutter run -d chrome --dart-define=WAYMARK_API_BASE_URL=http://localhost:5121/api
```

1. Log in, scan `WM-DEMO-2A-START`, then select `WM-DEMO-2A-DEST`.
2. Confirm the expected 40 m from the previously verified demo route.
3. Confirm GET `/api/Maps/floors/{id}/graph` in DevTools has Bearer authentication.
4. Select each floor. Check that only same-floor edges are connected, the elevator
   has a transfer marker, and no line joins two separate floor canvases.
5. Check step numbers against the list below and resize the browser.
6. Check map-read failures by disabling the API temporarily; a cached graph will
   remain visible until a new floor/route is requested. No database edits are needed.

Unit/widget tests use MockClient and contract fixtures, including return visits,
missing coordinates and responsive widths. They do not verify a physical camera,
actual floor images, real API authentication or SQL data. Android device testing
and a visual check against the live demo remain manual.

## Verification in this workspace (2026-10-18)

- `flutter analyze --no-pub`: no issues.
- `flutter test --reporter expanded`: 56 passed, one existing browser-only test
  skipped on the VM test runner. Includes 13 floor-map unit/widget tests.
- `flutter build web --no-pub --dart-define=WAYMARK_API_BASE_URL=http://localhost:5121/api`:
  succeeded, output `waymark/build/web`.
- `git diff --check`: passed (Git also reports LF/CRLF normalization notices).
- No SQL, migrations, seed, real API requests or physical camera checks were run.
