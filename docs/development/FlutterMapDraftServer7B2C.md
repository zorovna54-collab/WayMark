# Phase 7B-2C — Flutter Map Builder server drafts

Date: 2026-10-20. Branch: `auth-jwt-assignment`.
Phase-start HEAD: `631a76cd196460318429ebff8da394818ccbdd2d`.
The uncommitted 7B-2A/2B backend and existing Gradle/Figma work are preserved.

## Contract audit and boundary

Read the 7B-2A/2B reports, `MapDraftsController`, `MapDraftDtos`,
`MapDraftService`, `MapDraftValidator` and exception filter; reviewed the Flutter
editor, local model/image/file gateway, AuthSession, base URL and canvas.
No backend changes were needed. This client only writes private draft revisions
and image assets. It never calls a production graph writer, `/api/routes`,
membership administration, publish, migration, seed or LM Studio.

Every private endpoint requires the existing JWT, server AdminOnly policy and
active CanEditDrafts membership for Floor → Building → Site. Flutter reads the
current AuthSession for each request; it neither grants permissions nor clears
the login session on a failed draft request. Authorization remains on the server.

`MapDraftApiService` reuses `WayMarkApiService.baseUrl`, including the existing
`WAYMARK_API_BASE_URL` define and platform defaults. No new localhost setting.
Prefix: `/api/admin/floors/{floorId}/map-drafts`.

| Method | Suffix | Client behavior |
| --- | --- | --- |
| GET | base | Read typed metadata; verify Site/Building/Floor and draft identity. |
| POST | base | Create v1 content without embedded image; expect revision 1. |
| PUT | `/{draftId}` | Send `{expectedVersion,content}`; require next revision. |
| GET | `/{draftId}/graph?version=N` | Pin metadata version; verify draft/floor/version/status. |
| POST | `/images` | Raw PNG/JPEG bytes, exact MIME, authenticated. No multipart or Base64. |
| GET | `/images/{assetId}` | Authenticated bytes → actual decode → MemoryImage canvas. No public URL. |
| GET | `/images?page=N&take=100` | Scoped metadata recovery list with pagination. |
| GET | `/{draftId}/versions?take=50&beforeVersion=N` | Descending history with exclusive pagination. |
| POST | `/{draftId}/restore` | `{expectedVersion,sourceVersion}`; new revision, then pinned reload. |

## Local JSON v2 ↔ server draft v1

| Local v2 / editor | Server v1 | Rule |
| --- | --- | --- |
| `version:2,status:draft,verifiedForPatientUse:false` | `schemaVersion:1` | Separate formats; no local safety assertion sent to server. |
| Site/Building/Floor metadata | Floor in URL; ownership from response | Never send client ownership fields in content. |
| NodeCode and `draftNodeIds` | GUID `id`, `nodeCode` | Stable local GUIDs, persisted in JSON v2. Published int ID stays provenance only. |
| Node X/Y | Decimal X/Y | Normalized 0–1 coordinates; never derive meter distance from pixels. |
| `sourceNodeId,wayMarkCode` | `sourceNodeId,existingWayMarkCode` | Existing QR provenance only. Server validates actual same-floor mapping. |
| Edge code pair + `draftEdgeIds` | GUID edge and endpoint IDs | Directed; editing retains edge ID; deleting/recreating allocates a new ID. |
| Meters + `isMeasured` | `distanceMeters` number or null | Unknown is null, never a fake measured zero. Preview excludes unmeasured edges. |
| `isActive` | `isActive` | Retained through load, edit, export/import and save; inactive edges excluded from preview. |
| Legacy `isAccessible:false` | `accessibility:Unknown`, `passageVerification:Unknown` | Legacy flag is unverified, not a verified accessibility claim. |
| `places` | `places` | Code/name, label, polygon, one/many Entrance GUIDs and Unknown retained. Label is not route target. |
| `transitions` | `transitions` | From-node GUID and target draft/version/node pinned exactly, with type/distance/Unknown flags. |
| Embedded `image.dataBase64` | `imageAssetId` | Only local backup embeds bytes. Upload separately; SQL receives a GUID reference. |

Old local JSON v1/v2 remains importable. New optional GUID/Place/transition fields
extend v2 without removing embedded-image backup. Unknown server graph fields or
schema versions are refused instead of silently discarded. Room/transition data
is displayed read-only and preserved; this phase does not add a Place editor.
Removing referenced nodes or changing their type is blocked. Unmeasured/inactive
edges remain visible for editing and cannot create a local preview route.

## Save, load and failure behavior

1. Select Site → Building → Floor. Initial graph is a **local copy** of the
   existing floor graph; selecting a floor does not issue a draft write.
2. Load/Reload explicitly to edit an existing server head. Graph and image are
   decoded into a replacement map before the editor/session is changed.
3. Save with no known head first reads metadata. Only the exact authorized
   `404 draft_resource_not_found` allows creation. An existing head requires
   explicit reload/conflict choice; its version is never silently adopted.
4. With an image, create the owning draft without an image first, upload raw
   bytes, then save a new revision with the returned asset GUID. This may leave
   an initial image-less revision if a later step fails; UI remains unsaved.
5. Successful acknowledged metadata alone advances the session version. UI
   clears dirty only after the complete save; shows revision and last confirmed
   server UpdatedAt. Save/Load busy state blocks editing/floor switches/navigation.
6. Acknowledged upload + failed save retains the pending asset and local bytes.
   Retry reuses it, including an import of identical image bytes in this session.
   After a page restart, load the draft or explicitly recover an existing asset;
   pending in-memory bindings are not stored in a hidden browser database.
7. Upload timeout/network/503/malformed response has an uncertain result. The
   session blocks blind re-upload. “Ảnh đã upload” lists same-floor metadata,
   downloads privately for visual comparison and asks before binding a chosen
   asset to local state. Save is still required. No automatic delete/purge.
   If no asset is visible, wait/reload the list and ask the operator to reconcile;
   do not assume a 503 means nothing committed.
8. Restore requires an explicit confirmation and the last loaded expectedVersion.
   If restore is acknowledged but loading its image/graph fails, the message
   explicitly says the server revision exists and requires Reload. Local content
   stays unchanged; the stale expectedVersion prevents a silent retry overwrite.

401/403/404/413 have separate messages. 409 `draft_version_conflict` offers
keep-local, export backup or reload-latest; other 409 codes (revision/image quota,
storage quota/key conflict) do not offer a forced overwrite. 400, 503, network,
timeout and invalid JSON preserve the current map and login. No internal response
title, stack trace or physical storage path is shown.

Floor/Site/Building change, reload, local import and Flutter page exit ask before
discarding dirty content. Export does not falsely mark the server copy saved.
Web beforeunload installs/removes a scoped listener for dirty/busy state; prompt
display and wording remain browser-controlled. Always export before closing a
tab or killing a process; this is not crash recovery or automatic local persistence.

## Verification

- 28 new mock-HTTP/unit/widget tests; full Flutter suite: **175 passed, 1 skipped**
  (the existing Web-only skip). Tests exercise actual local image codec for small
  generated PNGs, but do not exercise real server image storage or SQL Server.
- Coverage: create/save, raw upload then binding, private image reload, GUID/JSON
  roundtrip, Room entrances and pinned transitions, inactive/unmeasured edges,
  pending asset retry, ambiguous-upload recovery, restore/history, 409 categories,
  all requested HTTP errors, malformed responses, missing/changed JWT, timeout,
  offline export, dirty reload/back/floor guards and floor isolation.
- Existing responsive canvas test now scrolls to the canvas after narrowing the
  screen: the new toolbar can put that ListView child outside the cached viewport.
  Its route/pixel/image assertions were retained.
- Flutter analyzer: no issues. Web release build: passed, including Wasm dry run.
- `git diff --check`: passed. New/untracked text paths also checked separately.
- Backend build/tests **not rerun**: no backend source or dependencies changed in
  this phase. The previous 212/212 result is historical, not a new result here.
- No browser Save/Load against a live API, real JWT/membership enforcement,
  SQL Server persistence, restart/storage or camera acceptance is claimed here.

The sandbox initially blocked SDK cache, temporary compiler files and loopback.
Granted the SDK cache write scope and test-runner network access; used an ignored
task temp directory and suppressed analytics. Final verification invokes the
installed Flutter tools snapshot directly through its bundled Dart executable
because the batch launcher also hit an SDK Git-directory permission failure:

```powershell
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:TEMP = (Resolve-Path .dart_tool/phase7b2c/tmp).Path
$env:TMP = $env:TEMP
# Working directory: waymark
& C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe C:\src\flutter\bin\cache\flutter_tools.snapshot --suppress-analytics analyze --no-pub
& C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe C:\src\flutter\bin\cache\flutter_tools.snapshot --suppress-analytics test --no-pub --reporter expanded
& C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe C:\src\flutter\bin\cache\flutter_tools.snapshot --suppress-analytics build web --no-pub
```

These are the installed Flutter analyzer/test/build commands, with unchanged SDK
source. Logs are ignored under `waymark/.dart_tool/phase7b2c/`.

## Manual acceptance in an isolated environment

Prerequisites require a separate operator approval: verify backup/schema/history,
apply the two reviewed pending migrations **only to the approved isolated DB**,
provision an approved existing Admin's Site membership, configure private managed
storage/root quotas and the API's allowed Web origin. Reuse existing secrets
outside Git. This phase performed none of those operations.

1. Run that isolated backend and sign in with the approved account in Flutter Web.
   Set `WAYMARK_API_BASE_URL` to that backend's actual origin plus `/api`, using
   the normal `flutter run -d chrome --dart-define=WAYMARK_API_BASE_URL=...` flow.
2. Open Map Builder and select the approved Site/Building/Floor. If a draft exists,
   Load first; optionally import a same-floor JSON backup **after** Load.
3. Select PNG/JPG; inspect canvas, Fit Image, zoom/pan, nodes and directed edges.
   Save Draft. Confirm revision/timestamp only after success in Network/response.
4. Reload the tab, sign in if needed (AuthSession remains its existing in-memory
   behavior), reselect floor, Load: inspect pixels, node geometry, edge direction,
   Room labels/entrances and transitions against the saved draft/JSON backup.
5. Open two tabs at the same revision. Save A then B; B must show version conflict
   and retain its edits. Export B, reload latest, compare deliberately.
6. Edit without saving; try floor change, Reload, Back, browser reload and close.
   Cancel the prompt and verify local content. Export backup and import it again.
7. Disconnect the isolated backend during save; verify no false Saved, local
   editing/export still works. Test upload-ack/save-fail retry does not re-upload.
   For ambiguous upload, use the scoped recovery list and visually confirm asset.
8. Restore an older revision; verify NEW version with the original image/content.
   Restart the isolated API; Load again. Test unavailable/corrupt storage safely
   in the isolated environment, never by modifying production files.
9. Verify real 401/403 with ordinary user, Admin without membership and other-Site
   Admin; confirm JWT/production QR/routes remain unchanged. Inspect requests to
   ensure there are no production graph writes or public image URLs.

## This phase's file manifest (12)

Modified: `waymark/lib/features/admin/draft_map.dart`,
`waymark/lib/features/admin/draft_map_editor.dart`,
`waymark/test/draft_floor_workflow_test.dart`.

New:

- `waymark/lib/services/map_draft_api_service.dart`
- `waymark/lib/features/admin/draft_server_session.dart`
- `waymark/lib/features/admin/draft_exit_guard.dart`
- `waymark/lib/features/admin/draft_exit_guard_stub.dart`
- `waymark/lib/features/admin/draft_exit_guard_web.dart`
- `waymark/test/fixtures/map_draft_fixture.dart`
- `waymark/test/map_draft_server_test.dart`
- `waymark/test/map_draft_editor_server_test.dart`
- `docs/development/FlutterMapDraftServer7B2C.md`

Phase-start file hashes confirm that only the three listed pre-existing files
changed; all pre-existing backend/migrations/docs/Gradle/Windows-generated/Figma
files remain byte-for-byte unchanged. Nothing staged, committed or pushed.

## Decision

**GO for the next isolated 7B-2D integration/acceptance step, conditional on the
operator prerequisites above. NO-GO for production use or claiming real server
Save/Load acceptance until the manual checklist passes.** No publish workflow,
production Place routing, Room editing, membership administration or automatic
asset/revision cleanup is included. Back up private image storage together with
the matching database as specified in the 7B-2B report.
