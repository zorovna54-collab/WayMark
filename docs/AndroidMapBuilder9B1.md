# Phase 9B-1 — Android local Map Builder

## Root cause and scope

`draft_file_gateway.dart` returned only `kIsWeb`; native builds selected `draft_files_stub.dart`, which threw UnsupportedError. `pick-floor-image` was disabled by `_busy || !_files.supported`. This was not a camera permission or JWT role failure. The previous editor also required an API Site/Building/Floor and only preserved imported Room references without offering Room editing.

Android now offers an empty local workspace without API/SQL/demo data. This is not a server publication or an Admin permission grant. The existing server APIs retain their authorization. In the normal app use Home → Cài đặt → menu quản trị → Map Builder.

## Implemented

- Android Storage Access Framework open/create document intents, bounded background stream reads, explicit cancellation/errors, PNG/JPG codec validation and existing 10 MB/8192 px/32 MP limits. No new package, Gradle change or broad storage permission. Native file access follows [Android SAF](https://developer.android.com/training/data-storage/shared/documents-files).
- Local workspace GUID + Site/Building/Floor labels; integer IDs are local placeholders. Server-bound import and `DraftServerSession.save` reject local workspaces before HTTP calls.
- Phone-first canvas, horizontal tool strip, object/property sheets, larger touch hit areas, node drag and the shared aspect-preserving image/graph transform with Fit/zoom/pan.
- Add/edit/delete nodes and directed edges. Distance is entered in metres or remains unmeasured; dragging never recalculates metres. Reverse direction requires a separate edge.
- Add/edit/delete Room/Place labels, names/codes, normalized label coordinates and one or more valid Entrance GUID references. Existing polygons survive edits. Referenced Entrance nodes cannot be deleted or changed to another type. Accessibility/passage verification remain Unknown; labels are not route endpoints.
- JSON v2 embeds the image and preserves stable node/edge/Room GUIDs. Optional `localWorkspace` metadata distinguishes custom maps from server floors. Android and Web share this format/local-open flow. Picker cancellation/tool changes preserve the current draft. Save success is reported only after Android finishes writing the selected document.
- Unsaved drafts remain in memory: save JSON before terminating the app. Opening a saved file after app restart is supported. No auto-publish, production navigation import, AI or server persistence was added.

## Files in this sprint

Under `waymark/`, modified: `android/app/src/main/kotlin/com/example/waymark/MainActivity.kt`; `lib/features/admin/draft_file_gateway.dart`, `draft_files.dart`, `draft_map.dart`, `draft_map_editor.dart`, `draft_server_session.dart`.

Added: `lib/features/admin/draft_files_native.dart`, `draft_map_editor_mobile.dart`; `test/android_map_builder_test.dart`; `tool/android_map_builder.dart`, `generate_custom_plan_test.dart`; this document. Existing Codex/Kilo changes were retained. No backend, migrations, secrets, Gradle, Windows generated or Figma files changed in this sprint.

## Verification

- `flutter analyze --no-pub`: passed.
- `flutter test --no-pub --reporter expanded`: 184 passed, 1 Web-only skipped. New tests include native channel cancellation/limits/save outcomes, custom v2 round-trip, blocked server binding, offline blank creation, actual image painting, cancelled image selection, Room create/edit/delete and AuthSession preservation. Existing QR/rerouting/navigation and server-draft regression passed.
- Android debug build and Web build: passed. Backend tests not rerun because backend was unchanged.
- Emulator-5554, real native file dialogs: created empty map, selected PNG 900×598, imported a custom test JSON, dragged a node, edited Room name, saved via Android CREATE_DOCUMENT, stopped/restarted app and reopened the saved JSON. Also selected JPG 900×598, then cancelled another image selection: JPG and 2 nodes/1 edge/1 Room remained.
- Pulled the saved device JSON for comparison: image Base64 identical; workspace GUID and Entrance reference preserved; dragged X changed from `0.18` to `0.2948717948717948`; edge distance remained `5.25 m`.
- Inputs/evidence are synthetic test-only files in ignored `waymark/build/android-builder-evidence/`, not app assets or production maps. Screenshots: `05-real-image.png`, `07-edited-room.png`, `09-restored-after-restart.png`, `10-jpg.png`. The emulator test used the real editor/picker, not a fake file service.
- `git diff --check`: passed. Baseline hashes confirm unrelated existing files were preserved.

## Run

```powershell
cd D:\project\WayMark\waymark
flutter run -d emulator-5554
# Direct local editor for testing without login/API:
flutter run -d emulator-5554 -t tool/android_map_builder.dart
```

## Acceptance checklist (6 steps)

1. Map Builder → Bản đồ mới: enter your area/building/floor; confirm an empty graph.
2. Choose your PNG/JPG; inspect the canvas, Fit Image, Pan/pinch; cancel a replacement and verify the current image stays.
3. Thêm node: place corridor/Entrance nodes; select and drag. Use Đối tượng / Sửa to edit/delete selected nodes.
4. Thêm phòng: enter room name/number, link valid Entrance(s); edit/delete via the object sheet. Labels must not become entrance coordinates.
5. Scroll the tool strip → Thêm cạnh có hướng: choose endpoints, enter measured metres. Edit/delete an edge; add a reverse edge explicitly if needed. Preview remains local and requires alignment review.
6. Lưu JSON + ảnh → choose a device location. Restart/open JSON; verify image, rooms, entrances, coordinates and edges. Nothing should appear automatically in production Navigation.

Phase 9B-2 still needs an explicit reviewed conversion/binding of this local workspace into a navigation dataset, cross-floor mapping and physical passage/accessibility verification. This phase does not claim the map is safe for patient navigation.
