# WayMark — Git finalization audit, 2026-10-19

## Follow-up: Phase 7A security fix

The NO-GO below records the **initial audit before Phase 7A**. Its two security
blockers have since been addressed in the working tree: Admin-only server policies
and the Pkcs 10.0.13 patch. See [Phase7ASecurityReview.md](Phase7ASecurityReview.md)
for the endpoint matrix, 108 backend / 147 Flutter test results, clean NuGet audit,
Admin provisioning requirements, and the eight additions to the 71-path manifest.
Current decision: **GO to rerun SAFE GIT FINALIZATION**, not production approval.
No staging, commit/push or production role/data changes occurred in Phase 7A.

## Historical decision at initial audit: NO-GO for commit/push

The user authorized commit/push only if the safety checks pass, and explicitly
required a stop for a public repository with unresolved Admin authorization risk.
That condition is present. **No staging, commit or push was performed.** The index
was empty at entry and remains empty. No PR, merge, reset, restore, clean, stash,
history rewrite, package upgrade, authorization change or SQL operation was run.

### Repository checks

- Workspace: `D:\project\WayMark`.
- Branch: `auth-jwt-assignment`; upstream: `origin/auth-jwt-assignment`.
- Fetch/push remote: `https://github.com/zorovna54-collab/WayMark.git`.
- GitHub repository API returned `private=false`, `visibility=public`.
- Local HEAD and remote branch both reported
  `2d5e7d61af68251070039f41ea0048fdf852881b` at the audit check.
- Existing HEAD message: `feat: integrate Flutter QR routing with backend API`.
- No deleted files or unmerged index entries. No pending migration/snapshot changes.
- No new commit hash/message exists. The proposed sprint message remains unused:
  `feat(waymark): implement QR rerouting and visual floor plan editor`.

## Blocking findings

| Severity | Evidence | Decision |
| --- | --- | --- |
| High — existing authorization gap | `WayMark.Api/Controllers/WayMarksController.cs:13` applies plain `[Authorize]`; POST at line 79, PUT at 102 and DELETE at 133 have no Admin role/policy. `Program.cs:77` registers default authorization without an Admin write policy. Registration/login issue ordinary user JWTs without an Admin role requirement. | Phase 7A is unresolved. Source permits ordinary authenticated users to reach business-data writes. This is already present in HEAD, not introduced by the pending sprint. No real database exploit was attempted. Stop commit/push under the user's rule; handle authorization in a separate task. |
| High — vulnerable dependency | A fresh restore/build reports NU1903 for resolved `System.Security.Cryptography.Pkcs 10.0.0`, [GHSA-846f-f764-76mx](https://github.com/advisories/GHSA-846f-f764-76mx), CVE-2026-84008. | The advisory lists 10.0.13 as a patched 10.x version. Dependency graph includes MimeKit 4.18.1 → Pkcs >=10.0.0 and Microsoft.Data.SqlClient 6.1.6 → Pkcs >=9.0.11. Review a compatible targeted update separately; no upgrade was made here. Vulnerable package presence is verified; application exploitability/reachability was not demonstrated. |
| Medium — vulnerable dependency | Same restore reports NU1902 for the package, [GHSA-2fmv-rv2c-59x7](https://github.com/advisories/GHSA-2fmv-rv2c-59x7). | Include this advisory in the separate dependency remediation and rerun the audit. |
| Low — local environment metadata | Development docs include example workspace/SDK paths and localhost URLs. Legacy SQL already tracked in HEAD contains local database-file paths. | These are documentation/schema-export metadata, not runtime credentials. No legacy SQL or local config is added by this sprint. Keep actual machine configuration and original private floor plans out of commits. |

Stopping this push does not remediate the authorization gap already in the public
branch. The audit did not change repository visibility or any deployed service.

## Secret, data and scope review

- Pattern scans covered tracked/proposed text and all 45 excluded Figma reference
  files, plus 187 unique text blobs reachable through the 11 local-ref commits
  (including Codex snapshot refs). Historical blobs were decoded with BOM detection
  so UTF-16 SQL exports were not silently skipped as binary.
- No confirmed production JWT secret, private key, API token or password was found
  by these scans. Candidate matches were controller `.text` reads and non-JWT test
  session markers. TestServer signing keys are generated randomly per test.
- This is a bounded pattern/source review, not a guarantee that every possible
  secret format or every remote/unreachable historical object has been covered.
  No credential values were printed or added to this report.
- Tracked `WayMark.Api/appsettings.json` contains no JWT secret or credential-bearing
  connection string. Development/local settings, User Secrets paths, `bin`, `obj`,
  `.dart_tool`, `build` and Android `local.properties` are outside the candidate set.
  No local secrets/config files were copied or modified.
- Current legacy SQL files have no AspNetUsers INSERT/password-hash rows detected.
  They are unchanged and are not part of the sprint candidate set.
- Fixtures/golden use synthetic clinic rooms/demo codes. The evidence screenshot
  shows the isolated visual harness and localhost, with no visible JWT/credentials
  or patient data. The four image files have no GPS metadata. Original user clinic
  images were not copied into the repository.
- Six Inter font/license files are runtime assets declared by pubspec, not build
  outputs; SIL OFL license and attribution accompany them.
- Draft import/export is local-only, with size/type/decode/hierarchy/graph validation.
  There is no new server upload/publish endpoint in the pending changes. Any
  future write/publication flow must wait for Phase 7A.

## Quality checks actually run

| Command | Result |
| --- | --- |
| `flutter analyze` from `waymark/` | Passed, no issues |
| `flutter test --reporter expanded` | 147 passed; 1 existing Web-only test skipped on VM |
| `flutter build web` | Passed; 27.2 s, Wasm dry run succeeded |
| `dotnet build WayMark.Api/WayMark.Api.csproj --artifacts-path <ignored-local-artifacts>` | Build passed, 0 errors; NU1902/NU1903 warnings remain |
| `dotnet test WayMark.Api.Tests/WayMark.Api.Tests.csproj --artifacts-path <ignored-local-artifacts> --logger trx ...` | 60 passed, 0 failed, 0 skipped; same dependency warnings |
| `git diff --check` | Passed; existing LF/CRLF conversion notices only |

The artifacts path was `waymark/.dart_tool/git-finalization/dotnet`, avoiding the
normal backend executable output location. Tests use EF InMemory/TestServer and
synthetic JWTs; the production API was not started, and SQL Server was not used.
Flutter test log and backend TRX are ignored local artifacts, not commit candidates.
Build/test success does not override the security stop condition.

## Phase 7B-1 finalization

Updated `VisualFloorPlan7B1.md` and `FloorPlanCanvasRenderingFix.md` to record the
user's **6/6 manual Chrome acceptance**: PNG/JPG on canvas, undistorted Fit Image,
hide/show, synchronized zoom/pan, dragging nodes with route preview, and JSON v2
image/graph restoration. **GO for local drafts; not production-ready.** These are
user-reported manual results, distinct from the automated checks above.

## Candidate manifest — not staged or committed

At entry: 18 modified + 98 untracked paths (116 total). This audit adds one report,
making 18 modified + 99 untracked paths. Excluding 45 Figma files and the existing
Gradle change leaves **71 candidate paths** below. This manifest is for a later
finalization after blockers are resolved; it is not a claim that a commit exists.

### Backend source — 5

- `WayMark.Api/Contracts/RouteDtos.cs`
- `WayMark.Api/Controllers/RoutesController.cs`
- `WayMark.Api/Services/Routing/DijkstraRouter.cs`
- `WayMark.Api/Services/Routing/RoutePlanner.cs`
- `WayMark.Api/Services/Routing/RoutingOptions.cs`

### Backend tests — 2

- `WayMark.Api.Tests/RouteApiTests.cs`
- `WayMark.Api.Tests/RoutingOptionsTests.cs`

### Flutter application source — 22

- `waymark/lib/core/theme/map_ui_theme.dart`
- `waymark/lib/features/admin/admin_page_shell.dart`
- `waymark/lib/features/admin/draft_file_gateway.dart`
- `waymark/lib/features/admin/draft_files.dart`
- `waymark/lib/features/admin/draft_files_stub.dart`
- `waymark/lib/features/admin/draft_files_web.dart`
- `waymark/lib/features/admin/draft_map.dart`
- `waymark/lib/features/admin/draft_map_editor.dart`
- `waymark/lib/features/admin/floor_plan_asset.dart`
- `waymark/lib/features/admin/map_builder_page.dart`
- `waymark/lib/features/admin/settings_page.dart`
- `waymark/lib/features/navigation/manual_navigation.dart`
- `waymark/lib/features/navigation/navigation_page.dart`
- `waymark/lib/features/navigation/reroute_navigation.dart`
- `waymark/lib/features/route/floor_plan_canvas.dart`
- `waymark/lib/features/route/floor_route_geometry.dart`
- `waymark/lib/features/route/floor_route_map.dart`
- `waymark/lib/features/route/route_preferences.dart`
- `waymark/lib/features/route/route_preview_page.dart`
- `waymark/lib/features/scanner/scanner_page.dart`
- `waymark/lib/models/route_models.dart`
- `waymark/lib/services/waymark_api_service.dart`

### Flutter package metadata — 2

- `waymark/pubspec.yaml`
- `waymark/pubspec.lock`

### Flutter tests, fixtures and visual harness — 21

- `waymark/test/draft_floor_workflow_test.dart`
- `waymark/test/draft_map_test.dart`
- `waymark/test/fixtures/floor_plan_render_probe.jpg`
- `waymark/test/fixtures/floor_plan_render_probe.png`
- `waymark/test/fixtures/qr_navigation_fixture.dart`
- `waymark/test/fixtures/routing_fixture.dart`
- `waymark/test/floor_plan_canvas_test.dart`
- `waymark/test/floor_plan_pixels_test.dart`
- `waymark/test/floor_route_map_test.dart`
- `waymark/test/goldens/floor_plan_clinic_canvas.png`
- `waymark/test/manual_navigation_test.dart`
- `waymark/test/map_layout_test.dart`
- `waymark/test/navigation_page_test.dart`
- `waymark/test/navigation_qr_flow_test.dart`
- `waymark/test/navigation_qr_match_test.dart`
- `waymark/test/route_preferences_test.dart`
- `waymark/test/routing_flow_test.dart`
- `waymark/test/routing_options_test.dart`
- `waymark/test/scanner_camera_test.dart`
- `waymark/test/settings_navigation_test.dart`
- `waymark/test/support/map_builder_visual_main.dart`

### Runtime fonts and license — 6

- `waymark/assets/fonts/Inter-Bold.ttf`
- `waymark/assets/fonts/Inter-Medium.ttf`
- `waymark/assets/fonts/Inter-Regular.ttf`
- `waymark/assets/fonts/Inter-SemiBold.ttf`
- `waymark/assets/fonts/OFL.txt`
- `waymark/assets/fonts/README.md`

### Documentation, contract and evidence — 13

- `docs/ScannerSettingsAndroid.md`
- `docs/ai/FloorPlanProposalV1.md`
- `docs/ai/FloorPlanProposalV1.schema.json`
- `docs/development/AutonomousSprint.md`
- `docs/development/FinalRegressionReview.md`
- `docs/development/FloorPlanCanvasRenderingFix.md`
- `docs/development/GitFinalizationAudit20261019.md`
- `docs/development/MapNavigationSprint.md`
- `docs/development/VisualFloorPlan7B1.md`
- `docs/development/evidence/floor-plan-canvas-chrome.jpg`
- `docs/routing/FlutterFloorMap4B.md`
- `docs/routing/FlutterNavigation4C.md`
- `docs/routing/FlutterQrNavigation4D.md`

### Exclusions and preserved files

- All 45 files in `waymark/design-reference/figma-make/`: reference only, never staged.
- `waymark/android/gradle.properties`: existing `kotlin.incremental=false` change,
  excluded because it is not established as part of this sprint; not modified here.
- `generated_plugin_registrant.cc`, `generated_plugin_registrant.h`, and
  `generated_plugins.cmake`: excluded, no pending diff, SHA-256 unchanged.
- `bin/`, `obj/`, `build/`, `.dart_tool/`, caches and local configuration: ignored,
  not staged. No build outputs were already tracked among the audited candidates.
- Migrations/model snapshots/legacy SQL: no pending changes; no staging or execution.

## Required next steps before retrying Git finalization

1. Resolve Phase 7A server-side write authorization in a separately scoped task:
   define/provision Admin permissions safely, protect the relevant write endpoints,
   and verify ordinary users receive 403 while authorized admins succeed. Do not
   treat hiding the Flutter Admin menu as API authorization.
2. Review a compatible targeted fix for the vulnerable Pkcs dependency, including
   transitive dependencies, then restore/build/test and rerun vulnerability checks.
   No SDK target-framework change or bulk package upgrade is implied.
3. Repeat remote/secret/quality checks. Only then stage explicit reviewed paths,
   inspect the complete cached diff, create the sprint commit and perform the
   non-force push to `origin auth-jwt-assignment`.

No commit/push command was attempted, so there is no new remote commit to verify.
