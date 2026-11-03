# AI Map Assistant Phase 2 — Node / Edge proposals

Date: 27/10/2026 (Asia/Ho_Chi_Minh). Scope: Flutter only; no SQL, API, migration, JWT, roles or published graph changes. Existing workspace changes were preserved. No commit/push.

## Implementation

The existing `AiMapProvider` and node-only Phase 1 remain available. `AiGraphProvider` adds a detached, floor-scoped analysis request. `OpenAiMapProvider` reuses the existing image transport and OpenAI-compatible `/v1/models` and `/v1/chat/completions` calls. It sends an image, not just text; transport copies are limited to 768 px on the longest side without cropping or changing the source. Input limits remain 4 MB / 8 MP. Phase 2 defaults to a bounded 300-second timeout; Phase 1 retains 120 seconds. An app JWT is never forwarded to the AI provider. Optional AI tokens stay in the configuration screen's memory.

Proposal schema version 2 is independent of persisted Draft JSON v2/v3. Nodes contain temporary ID, floor, normalized coordinates, type, name, destination flag, optional evidenced landmark, confidence, evidence and uncertainty. Edges contain temporary ID, exact endpoint references, floor, type, evidence, uncertainty and an unverified direction hint. AI `distanceMeters` must be null. Uncertain areas are visible separately. Existing endpoints use `existing:<stable GUID>`, never a QR code, display order or WayMarkCode. Corridor points use the existing `Junction` node type; no schema enum was added.

The parser bounds payload/list/text sizes, checks coordinates/enums/IDs/floor and rejects invalid items, including cross-floor edges, unknown endpoints, self-loops, duplicate directed pairs, invented metres and accessibility claims. A wholly malformed result fails closed. Pending/Accepted/Rejected status belongs to the review queue, not the graph.

Review overlays use the existing image canvas and transform: node centers and edge endpoints follow the image, while marker/label/stroke sizes remain in screen pixels. Gray is existing graph, orange/purple is pending AI, green is queued acceptance. Tap a proposal for evidence; use Accept/Edit/Reject in the list. Node edits/rejections invalidate accepted dependent edges. Each Edge requires approved/existing endpoints, a human-selected direction, positive finite metres, and explicit confirmation. Two-way acceptance creates two directed edges. Accessibility remains Unknown through the existing server mapper, not verified wheelchair access.

Final confirmation revalidates project ID, floor ID, source image identity and the original graph stamp, validates the entire candidate batch, then appends fresh stable node/edge IDs using the existing Draft methods. No overwrites, automatic Save, Publish or QR changes. Save/Load remains the existing explicit workflow. The snackbar offers guarded batch undo; it refuses to undo across subsequent graph/image/project changes. Closing/cancelling, stale asynchronous results and provider failures do not apply changes.

## Files in this change

Added:
- `waymark/lib/models/ai_graph_proposal.dart`
- `waymark/lib/features/admin/ai_graph_review.dart`
- `waymark/lib/features/admin/ai_graph_review_panel.dart`
- `waymark/test/ai_graph_assistant_test.dart`
- This report.

Updated existing working-tree sources:
- `waymark/lib/services/ai_map_provider.dart`
- `waymark/lib/features/admin/ai_map_assistant_page.dart`
- `waymark/lib/features/admin/draft_map_editor.dart`
- `waymark/lib/features/admin/draft_map_editor_mobile.dart`

Some pre-existing sources are still Git-untracked from earlier sprints; “added/updated” above describes this task's baseline, not a claim about repository staging.

## Verification

- AI Phase 1 + Phase 2 targeted tests: **50 passed, 1 opt-in live test skipped**.
- Full Flutter regression: **340 passed, 4 skipped** (Web-only test, two explicit SQL-live tests without fixture paths, and the opt-in Vision smoke). No SQL tests were enabled.
- Analyzer: no issues.
- Android main debug APK build: PASS, explicit Flutter exit code 0. Existing Gradle/JDK native-access warnings remain; Gradle was not modified.
- `git diff --check`: PASS; Git emits existing LF/CRLF conversion notices.
- Backend tests not rerun: no backend source changed in this task.

### Real LM Studio evidence

`GET /v1/models` succeeded at Windows `http://127.0.0.1:1234/v1` and the user-provided LAN address `http://192.168.1.21:1234/v1`. The model ID actually returned is `qwen/qwen3-vl-8b` (plus an embedding model). LAN addresses are configuration examples and may change.

A real provider smoke sent a 900×598 synthetic clinic fixture image as `image_url` to `POST /v1/chat/completions`. It completed in approximately **4m50s**, returning **4 nodes, 3 edges, 1 uncertain area, 0 invalid items**. Names included EXAM (TEST), TRIAGE, WAITING and P0 FIXTURE CORRIDOR. This proves image transport, inference and typed parsing; it does **not** establish room entrances or walkability. In particular, edges ending at room labels must be checked and may need rejection or manual relocation to doors. No proposals from this smoke were applied.

Evidence (ignored build directory):
- `waymark/build/ai-phase2-evidence/live-proposal.json`: typed real response, without image bytes or credentials.
- `waymark/build/qr-publish-hotfix/ai-phase2-live.log`.
- Analyze/test/build logs: `waymark/build/qr-publish-hotfix/ai-phase2-*.log`.

### Android Emulator: real Vision and review

The main debug APK was installed and exercised on `emulator-5554`. Using the existing local Builder and real Android file picker, a new local floor loaded the synthetic 900×598 clinic image. The UI connected to `http://10.0.2.2:1234/v1`, selected the actual `qwen/qwen3-vl-8b` ID and submitted another real image request with a 300-second timeout. The review UI displayed **4 nodes / 3 edges / 0 discarded** on the image. This was a real model response, not the fake provider.

Observed model error: the proposed segments ran toward room-label centers and crossed drawn room boundaries. **Those edges were rejected, not confirmed as corridors.** Confidence/valid JSON do not establish a walkable connection. One node label was edited, all other proposals rejected, the remaining node accepted, and final confirmation added **exactly 1 Node / 0 Edge** to the local Draft. An attempt to accept an edge without approved endpoints/direction/metres displayed the validation error and did not add it. Cancelling the final dialog retained the review queue; only the subsequent explicit confirmation appended the node.

The real Android Save dialog exported a new JSON v2 file; reopening it in Builder restored the image and edited node. Its image SHA-256 matched the original fixture, `verifiedForPatientUse` remained false and the landmark field retained the unverified AI notice. Existing routing validation correctly refused routing because there was no directed edge. This validates the safe refusal path, **not a new AI-generated navigable route**. JSON v3 multi-floor roundtrip and valid human-confirmed edge routing are covered by isolated tests, not a new SQL/physical-hospital test.

Additional evidence:
- `waymark/build/ai-phase2-evidence/android-real-review.png`
- `waymark/build/ai-phase2-evidence/android-edge-gate.png`
- `waymark/build/ai-phase2-evidence/android-applied-node.png`
- `waymark/build/ai-phase2-evidence/android-loaded-draft.png`
- `waymark/build/ai-phase2-evidence/android-routing-validation.png`
- `waymark/build/ai-phase2-evidence/android-saved-draft.json` (local fixture only; not staged).

No SQL/API Save or Publish was executed. Final minor UI changes (P-number disambiguation in edge selectors, confidence text, and the 300-second graph default) were rebuilt and covered by targeted tests; the real Android request above explicitly selected 300 seconds before those presentation/default changes.

The live test is deliberately disabled in normal regression runs. To run manually from `waymark` with a trusted local image:

```powershell
flutter test test/ai_graph_assistant_test.dart --plain-name 'LM Studio REAL image graph proposal (opt-in, never SQL)' --dart-define=WAYMARK_AI_PHASE2_LIVE=true --dart-define=WAYMARK_AI_BASE_URL=http://127.0.0.1:1234/v1 --dart-define=WAYMARK_AI_PHASE2_IMAGE=C:/path/to/verified-plan.png --reporter expanded
```

The real smoke explicitly uses a real HTTP client only when opted in; normal widget tests retain Flutter's isolated networking/fake providers. Its output stays in ignored build folders.

## Android check

```powershell
cd D:\project\WayMark\waymark
flutter run -d emulator-5554 --dart-define=WAYMARK_API_BASE_URL=http://10.0.2.2:5121/api --dart-define=WAYMARK_AI_BASE_URL=http://10.0.2.2:1234/v1
```

1. Open the existing local Map Builder, create/import a map and select the correct floor image.
2. Open **AI đề xuất Node / Edge**. Check the configured `/v1` URL, connect and select the actual Vision model. `10.0.2.2` reaches the Windows host from Android Emulator. Real phones use the configured LAN URL and require suitable firewall/network access. HTTP remains debug-only; release requires HTTPS.
3. Analyze. Review node positions, evidence and uncertainty on the image. Edit and accept/reject nodes; acceptance alone does not modify the Draft.
4. For an Edge, review endpoints/type, enter independently checked metres, choose direction, then confirm. Reject connections through walls or unverified room centers.
5. Confirm the final batch. Export JSON and reopen it, validate/routetest through existing tools. Server Save/Publish still requires the existing validation and authorization.

## Limits

- Same-floor proposals only. No automatic metre measurement, cross-floor connection, accessibility verification or AI publication.
- Existing-node prompt context is capped at 80 nodes; large floors may need manual editing. Parser limits are 40 nodes / 80 edges / 20 uncertain areas; prompt asks for at most 8 / 12 / 6 respectively.
- Pending proposals are ephemeral, not persisted into Draft JSON. Accepted final nodes/edges use unchanged JSON v2/v3 structures.
- AI may misread text, place nodes in room centers or hallucinate connections. Human graph validation and on-site verification are still required. Structured JSON and successful Vision are not safety certification.
- Local inference was slow and came close to the 300-second limit. Timeouts keep the draft intact and allow retry/cancel.
- Android hardware/LAN phone testing and new SQL persistence E2E are not claimed by these automated/local-fixture checks.
