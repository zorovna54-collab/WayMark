# WayMark UI/UX polish and AI timeout

Date: 27/10/2026 (Asia/Ho_Chi_Minh). Branch: `auth-jwt-assignment`.

## Initial audit and decisions

Read the AI provider, Phase 1/2 page/review, Builder/mobile/project controls, Draft validation, theme, Home, Profile, Settings, My Maps and cloud Save/QR/Publish controls, together with their tests. The working tree contains extensive existing backend/Flutter work; it was retained. No applicable AGENTS.md was found outside the untouched Figma reference tree.

| Priority | Evidence | Resolution |
|---|---|---|
| P1 | AI page only offered 60/120/300 seconds; state reset on reopening. No explicit retry button. | Presets 30/60/120/180/300, custom integer 10–600, scoped persistence, visible retry/error/cancel and bounded settings I/O. |
| P1 | Edge dialog popped before graph validation, so missing endpoints, invalid metres or duplicate edges discarded the input form. | Validate in the dialog using the same Draft constraints; retain fields and show inline errors. Revalidate the complete operation before mutation. |
| P1 | Two-way connections required reentering a separate reverse edge. | Optional, unchecked-by-default two-way choice for a new manual edge. Validate both directions before adding either; reject reverse conflicts without a partial insert. |
| P1 | Five floor-management actions and legacy/property buttons preceded the phone canvas. | Keep current-floor selector and primary image/graph tools above the canvas; move floor management and legacy/property tools below. Keep all functionality and the existing renderer. |
| P2 | AI connection/transport explanation stayed expanded while reviewing; proposal cards mixed technical coordinates with the decision. | Collapse connection settings on successful analysis, move transport guidance and proposal coordinates/evidence into expandable details; keep uncertainty and unverified warnings visible. |
| P2 | Settings API check called a protected endpoint without JWT and reported a generic HTTP 401 response. Some Settings copy was developer-facing. | Explain that 401 proves API response but private data requires login; retain the unauthenticated GET probe and AuthSession. Shorten copy; leave unavailable admin functions disabled. |

No confirmed P0 data-loss or authorization fault was found in the covered source/isolated regression checks. This is not a new live SQL acceptance result.

## Timeout behavior and persistence

Open **Builder → AI đề xuất Node / Edge → Kết nối và thời gian chờ**. Choose a preset or **Tùy chỉnh…**. Invalid custom input disables Analyze; the last valid stored preference remains intact. Graph analysis defaults to 300 seconds, node-only Phase 1 to 120 seconds unless a valid preference exists.

Only the timeout integer is persisted, separately under `openai-compatible-graph-v2` and `openai-compatible-nodes-v1`. This avoids crossing the two analysis scopes; a future provider must define its own scope. URLs, selected model, AI tokens and application JWTs are not written by this store. Changing timeout does not reset the currently entered URL/model/token.

- Android: app-private SharedPreferences via a dedicated `waymark/ai_preferences` MethodChannel; native scope and 10–600 validation; writes report success only after commit.
- Web: localStorage using the already-present `web` package. No new dependency or plugin registrant changes.
- Other native platforms without this channel: the selected timeout remains usable for the current screen; storage failures are explicitly reported. Persistent desktop/iOS settings are not claimed.
- Preference reads/writes are bounded at two seconds. Reads fall back to a bounded default; writes are serialized so an earlier selection cannot overwrite a later one. Storage failure does not block manual Builder/Navigation.
- Only the AI provider receives this request timeout. `/models` retains its existing ten-second connection limit; ordinary API clients are untouched.

While analyzing, controls block duplicate sends and show a spinner/text rather than invented percentage progress. Cancel closes the active provider; operation generations discard late replies. A failure offers retry and preserves the existing review/draft. All prior stale project/floor/image/graph checks, final confirmation and edge direction/metres gates remain in place. AI does not Save or Publish.

## Builder and data preservation

`DraftMap.checkEdge` is read-only validation; it allocates no IDs. The dialog uses it before dismissal and before applying. Editing an existing edge retains the existing update method/ID behavior. Two-way creation adds two explicitly directed edges with the entered metres. Empty metres retain the existing unmeasured-draft behavior and do not become routable; no pixel-to-metre conversion or accessibility approval was added.

Stable node/edge IDs, JSON v2/v3, room/entrance references, floor links and renderer transforms were preserved in tests. Node deletion already had a confirmation with affected-edge count and reference checks, so that behavior was retained. Save → GET verification, cloud ownership, QR eligibility, snapshot immutability and unsaved-change guards were not relaxed.

Legitimate Demo Map/personal-map safety labels were retained. They identify real fixture/unverified use; hiding them would misrepresent the data. No fixtures, legacy Room models or offline functionality were removed. Home, History, Profile and Navigation were covered by regression instead of speculative redesign.

## Changed files in this sprint

New:
- `waymark/lib/services/ai_timeout_preferences.dart`
- `waymark/lib/services/ai_timeout_store.dart`
- `waymark/lib/services/ai_timeout_store_native.dart`
- `waymark/lib/services/ai_timeout_store_web.dart`
- `waymark/lib/features/admin/ai_timeout_control.dart`
- `waymark/test/ai_timeout_preferences_test.dart`
- `waymark/test/ui_polish_builder_test.dart`
- This report.

Updated existing working-tree files:
- `waymark/android/app/src/main/kotlin/com/example/waymark/MainActivity.kt` (isolated preferences channel only).
- `waymark/lib/features/admin/ai_map_assistant_page.dart`
- `waymark/lib/features/admin/ai_graph_review_panel.dart`
- `waymark/lib/features/admin/draft_map.dart`
- `waymark/lib/features/admin/draft_map_editor.dart`
- `waymark/lib/features/admin/draft_map_editor_mobile.dart`
- `waymark/lib/features/admin/draft_map_editor_project.dart`
- `waymark/lib/features/admin/settings_page.dart`
- `waymark/lib/services/auth_api_service.dart`
- `waymark/test/multifloor_navigation_test.dart` (scroll to relocated management controls before interacting).

“New/updated” refers to this task's baseline; several earlier sources are still Git-untracked. No staging/commit/push occurred.

## Verification

Commands run from `waymark`:

```powershell
flutter analyze --no-pub
flutter test --reporter expanded
flutter test test/ai_timeout_preferences_test.dart --reporter expanded
flutter test test/ui_polish_builder_test.dart test/android_map_builder_test.dart test/ai_graph_assistant_test.dart --reporter expanded
flutter build apk --debug --dart-define=WAYMARK_API_BASE_URL=http://10.0.2.2:5121/api --dart-define=WAYMARK_AI_BASE_URL=http://10.0.2.2:1234/v1
flutter build web --no-pub --dart-define=WAYMARK_API_BASE_URL=http://localhost:5121/api
git diff --check
```

- Analyzer: clean.
- Full suite: **357 passed / 4 skipped / 0 failed**, a single suite result, not a sum of separate runs. Skips are the Web-only case, two explicit SQL-live tests and the opt-in live Vision test.
- New coverage includes all presets/custom limits, persistence scopes/corruption, cancel/retry/late replies, invalid timeout disabling Analyze, AI-only timeout/AuthSession preservation; Edge errors retaining input, explicit two-way insertion, reverse conflict atomicity, stable IDs and JSON v3 roundtrip. Responsive widget checks cover 320/360/393/430 logical pixels.
- Final Builder/Phase 2 targeted run: **42 passed / 1 live skip** after the last imported-file copy refinement. Timeout tests are reported separately, not added to the full-suite total.
- Final timeout-only run: **8 passed**, including the additional connected-page invalid-input assertion. No counts from different runs are combined.
- Android main debug build: PASS. Existing JDK/Gradle native-access notices remain; Gradle unchanged.
- Web JS build: PASS; Wasm dry-run also reported success (an informational message appears as a PowerShell stderr notice). A real Wasm deployment was not tested.
- Backend build/tests not rerun: no backend file changed in this task.
- Hash comparison confirms protected Gradle files and all three Windows generated files unchanged.

## Runtime boundaries and manual acceptance

Android Emulator initially stayed ADB-offline. Reconnecting did not recover it; the task-launched emulator was gracefully stopped and cold-booted without wiping user data or changing Windows policy. System UI briefly reported an ANR during boot; selecting Wait allowed startup. The app and existing Downloads remained available. A new, clearly named local fixture JSON was copied to Downloads; existing personal maps were not used or overwritten.

Actual Android checks use the existing synthetic clinic image and a local draft. They do not write SQL or publish anything. Screenshots/logs/source baselines are in the ignored folder `waymark/build/ui-polish-evidence/`:
- `before-builder.png` and `after-builder.png` (same fixture).
- `before-ai-review.png` (copied from the previous real Phase 2 evidence).
- `after-ai-invalid.png` and `after-ai-timeout.png` (actual timeout UI).
- `after-ai-reopened.png` confirms the custom value reloaded on a new screen.
- `after-edge-validation.png`, `after-two-way-edge.png`, `after-canvas.png`, `after-unsaved-guard.png`.
- `full-tests.log`, `timeout-tests.log`, `final-targeted.log`, `analyze.log`, `android-build.log`, `web-build.log`.
- `protected-before.json` and `before-source/` are local verification artifacts, not staged content.

Actual native preferences were read back as a bounded integer 417 in the app's private timeout file. Only that settings file was inspected; no authentication/SMTP/JWT secrets were read.

Actual Android acceptance: invalid custom text showed the range error; correcting it to 417 committed the preference, and closing/reopening AI restored **417**. On the fixture only, a second manual node `Test-waypoint` was added. Trying to save an edge without a target kept the dialog and source selection open with an inline error. Selecting the target, entering `2,5` and explicitly choosing two-way produced **2 Node / 2 Edge / 1 destination**. The entered 2.5 metres are a controlled test value, not a surveyed hospital distance; no physical passage/route safety was claimed. Android Back showed the unsaved-draft guard; **Giữ lại** retained the editing screen. These local edits were not exported over the original file, saved to a server or published.

The Development API read-only probe at `http://localhost:5121/api/WayMarks` was unavailable during this task. Therefore live SQL Creator Save/QR/Publish, live Visitor/History and a new real Vision inference are **not re-accepted** here. Isolated HTTP/widget regressions cover them; previous live evidence remains previous evidence. No SQL writes, migrations, accounts, permissions, secrets, Master Plan or production graph were changed.

Recommended manual check:
1. Open the local fixture/import your own copy; confirm current floor/image and that management tools are below the canvas.
2. Create two nodes; enter an invalid edge, correct it without reopening the form, then explicitly choose one/two-way metres and verify direction.
3. Open AI settings; try 601 (error), then 417; reopen and verify persistence. Change URL/model only intentionally.
4. With a trusted configured Vision server, analyze/cancel/retry and review proposals. No AI edge enters routing until direction/metres/final confirmation.
5. Export/reopen JSON; then use the existing server workflow only when the API and appropriate account are available. Confirm server Save → GET, QR and Publish prerequisites without bypassing guards.

Remaining backlog: further compact phone toolbars, persistent settings adapters for other native platforms, physical-phone testing, live API/SQL acceptance when the backend is running, and on-site verification of AI geometry. These were not replaced with fake success or a redesign.
