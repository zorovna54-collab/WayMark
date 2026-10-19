# Phase 4C — manual step navigation

## Flow and state

Preview enables **Bắt đầu dẫn đường** when `ManualNavigation.validate` accepts
the loaded route. The exact `WayMarkRoute` instance and existing API service are
passed to `NavigationPage`; starting/finishing navigation does not call POST
`/api/routes` again. Repeated presses cannot stack multiple Navigation pages.

`ManualNavigation` is a local state object with a node index and completion flag.
It validates ordered directed edges, finite positive edge distances, required
point/floor metadata and floor-change information before allowing confirmation.
It has no timer, sensor, GPS dependency, backend session or persistence.

- Initially the selected node is the first route node; no edges are confirmed.
- **Đã đến điểm tiếp theo** confirms the next node and increments the selected
  node index once. Current/next edge cards show API distances, edge type, floor
  and transfer endpoints. These are graph directions, not inferred left/right turns.
- Progress is confirmed edges / total edges, explicitly labeled manual. It is
  not a measured percentage of physical travel or a distance estimate.
- Confirmation of the last node shows **Đã xác nhận hoàn tất tuyến** with a
  reminder that physical position has not been verified.
- **Bước trước** undoes a confirmation, including the last one after completion.
- A one-node route starts unconfirmed and requires **Xác nhận hoàn tất tại điểm
  này**. It has no fabricated edge or distance.
- Empty/incomplete routes display an error and no confirmation control. Missing
  graph coordinates continue to use the existing map warnings; route instructions
  do not depend on invented coordinates.
- **Kết thúc** or normal Back returns to the previous Preview. Re-entering creates
  a fresh local checklist starting at the first node. No History record is created.

The old Navigation timer, default destination, fake 60% progress, fake AR/camera
background and hardcoded route painter have been removed.

## Floor map synchronization

`FloorRouteMap.activeNodeIndex` is optional; ordinary Preview retains its existing
floor selector behavior. Navigation supplies its selected node index:

- A blue ring identifies the selected node; its outgoing same-floor edge is
  emphasized. The ring is a manual selection, not a physical position marker.
- Confirming/undoing a node automatically selects that node's floor.
- Floor graphs still come from the existing authenticated endpoint and are cached
  by the map widget. Switching steps does not clear graphs for already read floors.
- Users may inspect another floor and select **Về tầng của bước hiện tại** to
  return. Inspecting a floor does not change navigation progress.
- Cross-floor edges remain transfer markers rather than lines between canvases.
  The original route sequence and repeated visits to a floor are preserved.

## Run and manually verify on the Emulator

Keep the already configured API running. From `waymark/`, select the real device
ID reported by `flutter devices`:

```powershell
flutter run -d <android-device-id> --dart-define=WAYMARK_API_BASE_URL=http://10.0.2.2:5121/api
```

For Web use `-d chrome` and the existing host API URL
`http://localhost:5121/api`, adjusting the port to the actual backend if needed.

1. Log in, scan `WM-DEMO-2A-START`, choose `WM-DEMO-2A-DEST`, verify the previously
   tested API distance of 40 m, and press **Bắt đầu dẫn đường**.
2. Wait without pressing confirmation: the selected node/progress must remain unchanged.
3. Compare each current/next leg with the Preview route. Confirm one step at a time.
4. At the elevator transition, check floor names, transfer endpoints and distance;
   confirm arrival and verify the map changes to the destination floor.
5. Press **Bước trước** and verify the previous node/floor/progress are restored.
6. Complete the route; verify that the UI explicitly calls this manual confirmation.
   Undo once, confirm again, then press **Kết thúc** to return to Preview.
7. Select the same start/destination WayMark to check the one-node confirmation.

No schema, API, Dijkstra, JWT or SQL data changes are needed. Test fixtures are not
inserted into the database. Unit/widget tests use MockClient and do not establish
that a user has physically traveled the route.

## Verification in this workspace (2026-10-18)

- `flutter analyze --no-pub`: no issues.
- `flutter test --reporter expanded`: 83 passed, one existing browser-only test
  skipped on the VM runner. New tests cover manual next/previous, transfer floor
  selection, completion/undo, one node, empty/incomplete data, floor browsing,
  narrow/wide layouts, no progress after five minutes, Preview entry/exit without
  route recalculation and disabling entry when node metadata is missing.
- `flutter build apk --debug --no-pub`: succeeded; output
  `waymark/build/app/outputs/flutter-apk/app-debug.apk`.
- `flutter build web --no-pub --dart-define=WAYMARK_API_BASE_URL=http://localhost:5121/api`:
  succeeded.
- `git diff --check`: passed (existing LF/CRLF normalization notices remain).
- No new live API, physical movement or Emulator visual navigation check was run
  in this phase. The new Navigation flow still needs the manual walkthrough above.
