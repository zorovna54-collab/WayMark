# WayMark — Sprint 7: Published Pilot Handoff & Field Evidence Toolkit

Ngày bàn giao: **28/10/2026 — Asia/Saigon**  
Workspace: `D:\project\WayMark`; branch giữ nguyên: `auth-jwt-assignment`

## A. Executive Summary

**Sprint 7 đạt CODE COMPLETE** trong phạm vi code/tooling/documentation, có APK riêng tương thích Sprint 6.

| Mức bằng chứng độc lập | Kết luận |
|---|---|
| **CODE IMPLEMENTED** | Checklist, structured bug report, cửa sổ ghi nhận, field measurement form/template, runbook và benchmark runner đã có |
| **AUTOMATED TESTED** | Targeted **85 PASS**; full suite **532 PASS / 4 SKIP**; analyzer/format/diff, Android builds và APK verification đạt |
| **DESKTOP BENCHMARKED** | Đã đo fixture nhỏ/vừa/lớn trên Windows Flutter test, 1 warmup + 3 measured loads mỗi cỡ, trước/sau tối ưu lookup |
| **PHONE SMOKE TESTED** | Có user smoke Local Pilot bản trước; **APK Sprint 7 chưa được agent chạy/cập nhật trên điện thoại** |
| **PUBLISHED SERVER/CAMERA E2E VERIFIED** | **NOT VERIFIED** — chỉ audit source/môi trường và mocked regression |
| **REAL-WORLD POSITIONING ACCURACY VERIFIED** | **NOT VERIFIED** — không có số đo bước/mét/error thật được tạo trong lượt này |

Bàn giao:
- [Runbook Published Pilot không USB](PublishedPilotRunbook20261028.md).
- [Mẫu một lượt đo thực địa, để trống](PublishedPilotFieldTrialTemplate20261028.md).
- Live Test Home có trang checklist; Diagnostics của Live có cùng toolkit nối với controller hiện có.
- Export JSON chủ động, bounded, phân biệt detector events và accepted displacement observations, không kèm token/endpoint/raw IDs/coordinate trace.
- Sau manual fallback có thể mở **Pilot report • phiên Live vừa đóng** để hoàn tất checklist và copy snapshot đã chốt.
- Tối ưu index identity/route adjacency từ kết quả benchmark, không đổi GUID, topology, Published semantics hoặc sensor algorithms.

Không viết lại PDR/Map Matching/Published validator. Rule readiness giữ nguyên; chỉ thay lượt quét route cạnh bằng Set lookup. Không tăng budget 40 hoặc thêm heuristic chống lắc.

## B. Current Published Pilot Prerequisites

Checklist có **11 gates**, mặc định NOT TESTED:
APK installation, API reachable, QR resolver, map/version, floor images, preflight, guided setup, real Detector, blue dot, QR correction, manual fallback.

Người thử chọn PASS/FAIL sau quan sát. App **không tự đánh PASS** khi mở trang, khi test fake đạt hoặc khi tạo snapshot. Không có auto HTTP probe mới. Một HTTP response chỉ chứng minh mức kết nối tương ứng, không chứng minh QR/SQL/images/accuracy.

**Điểm vào:**
1. Live Test Home → **Published Pilot • checklist & báo cáo (không USB)**: checklist/field form độc lập; sensor/position data để null vì chưa nối phiên.
2. Navigation → Live → Diagnostics → toolkit: dùng sensor counters/readiness/timeline hiện có, không tạo provider hoặc hệ thống log thứ hai.
3. Chọn phase, **Bắt đầu ghi nhận**, thực hiện ca, **Chốt số liệu**, nhập số đo rồi copy. Hai nút này chỉ điều khiển báo cáo, không tự bật/tắt sensor. Pause/Resume của Live vẫn là thao tác riêng.
4. Manual fallback đóng provider theo luồng cũ và đóng băng report trong bộ nhớ; không tự ghi PASS cho fallback. Người dùng có thể đánh dấu sau quan sát rồi copy.
5. Report/checklist ở RAM, không SQL/History/filesystem persistence. Copy trước khi rời Navigation/đóng app hoặc mở Live session mới.

Local Pilot vẫn dùng cảm biến điện thoại thật nhưng sơ đồ synthetic; không dùng mét fixture làm ground truth. Published cần endpoint/QR/map đúng phiên thực tế. Không yêu cầu ADB để bắt đầu hoặc hoàn tất phần code này.

## C. Network/API Readiness Audit — read-only

| Hạng mục/source | Bằng chứng |
|---|---|
| `WayMark.Api/Properties/launchSettings.json` | Profile http: localhost:5121; https: localhost:7199 + localhost:5121 |
| `Program.cs` | AddMapDraftFoundation, AddWayMarkDatabases, UseHttpsRedirection, Authentication/RateLimiter/Authorization, MapControllers |
| `Controllers/MapProjectsController.cs` | PublicMapsController AllowAnonymous dưới `/api/public`; quản lý/publish vẫn Authorize(MapAuthorPolicy) |
| Public QR/map/images | GET qr/{token}; maps/{id}/versions/{version}; images/{assetId} đúng version |
| `MapProjectService.ResolveAsync` | SQL read MapNodeQrs; check active/published version; đọc publication và membership node/floor; 410 revoke/missing |
| `PublicImageAsync` | Check MapPublicationImages binding và FloorMapImageAssets; mở ảnh đã verify qua storage |
| `MapDraftRegistration` | MapProjectService/MapDraftService scoped, MapImageCodec, IMapImageStorage → ManagedFileMapImageStorage |
| `WayMarkDatabaseRegistration` | WayMarkDbContext và AuthDbContext cùng cấu hình SQL Server tên WayMarkDatabase, history tables khác nhau; không đọc giá trị connection string |
| `ManagedMapImageOptions`/`ManagedStoragePaths` | Kho ảnh phải được enable, root tuyệt đối ngoài Git/content/web root; runtime filesystem permissions và object/manifest hợp lệ |
| `waymark/lib/services/waymark_api_service.dart` | WAYMARK_API_BASE_URL build define; Android mặc định 10.0.2.2:5121/api, desktop/web localhost |
| Live Test Home | Runtime endpoint riêng cho PublishedMapApiService; không có credentials/query/fragment; không thay config server |
| Public reader | Không gắn Authorization cho public request; followRedirects=false; không đi theo host trên QR |
| CORS | Development chỉ cho browser origin loopback; E2E dùng allowed origin riêng; không sửa policy |
| Read-only port inventory | Không thấy listener tại **5121/7199** lúc kiểm tra; không suy ra mọi port/host khác đều dừng |
| Runtime SQL/storage/API/TLS | **NOT VERIFIED** — không khởi động process, không kết nối SQL, không request QR/map thật |

**Điều kiện thực địa:** API reachable từ điện thoại qua interface/DNS được duyệt, endpoint HTTPS cuối cùng với certificate được Android tin cậy, Published rows/image objects đã provision và quyền runtime phù hợp. AllowAnonymous không thay thế SQL/file permissions, không bỏ TLS hoặc admin authorization.

CORS do browser thực thi; đổi CORS không sửa TLS/network của native Android. HTTPS binding cũng cần certificate phù hợp, `--urls` không tự tạo trust cho điện thoại. Xem [Microsoft CORS](https://learn.microsoft.com/en-us/aspnet/core/security/cors?view=aspnetcore-10.0) và [Kestrel](https://learn.microsoft.com/en-gb/aspnet/core/fundamentals/servers/kestrel?view=aspnetcore-10.0).

Runbook có kế hoạch chạy một process LAN test riêng, giới hạn interface/cổng/remote client và bước hoàn nguyên. **Mọi mở binding/firewall/network thực tế cần người dùng phê duyệt riêng; Sprint 7 không thực thi.** Không dùng bypass TLS/accept-all cert, allow-all CORS, tắt auth hoặc public tunnel. Không chép secrets vào log/report.

Evidence inventory: `waymark/build/sprint7-evidence-20261028-v2/read-only-environment-audit.json`.

## D. Bug Report / Diagnostics Enhancements

### D1. Nguồn và cấu trúc

`PilotEvidenceSession` chỉ quản lý thời điểm/cửa sổ/checklist/nhãn ghi chú/số đo. Tracking snapshot đọc **IndoorTrackingController + SensorSessionController + readiness report + TrackingTimeline hiện có**. Không đăng ký sensor subscription mới, không thêm raw event log.

Export `WayMarkPilotEvidence1`:
- App package/version 1.0.0+1, debug/release, toolkit Sprint 7 và Live Test define; khớp artifact hiện tại.
- Mode Local/Published; phase preparation/walk/still/rotation/reverse/correction/lifecycle/fallback.
- Device manufacturer/model và Android API từ capability probe đã hỗ trợ; không thu serial/user account. Metadata device có scrub và giới hạn 80 ký tự; chưa probe → notProbed/null.
- Sensor kind/availability/registration/permission.
- Detector accepted events, accepted displacement observations, rejected movement observations; tổng phiên và delta của cửa sổ tách riêng.
- Stride, estimated integrated distance, tracking state/confidence/hold/pause/error/recovery action, budget và overflow.
- Readiness summary: level, readyByData, eligibleRouteSegments, routeSegments, blocker count, tối đa 24 reason codes; không export affected IDs.
- QR correction result/count, last state transition và tối đa **32 events lấy từ timeline 96-event hiện có**.
- Start/end UTC do người dùng bắt đầu/chốt, fixed-note tags, số đo do người dùng nhập.
- `physicalAccuracy=NOT_VERIFIED` và `publishedServerCameraE2e=NOT_INDEPENDENTLY_VERIFIED` kể cả checklist được chọn toàn bộ PASS.

`stepAccepted` là sensor event đã qua gate, **không chứng minh một bước thật đúng**. `acceptedDisplacementObservations` chỉ là observation matcher đã cho dịch chuyển >0. Ví dụ detector false positives có thể làm estimate tiến; Sprint 7 chưa lọc chúng bằng ngưỡng thiếu bằng chứng.

### D2. Boundaries và privacy

- Checklist 11 mục, notes tối đa 10 enum tags, window 2 snapshots, timeline export 32 events. Không lưu lịch sử tọa độ hoặc toàn bộ raw samples.
- Code/event export qua **allowlist**. Code lạ → unrecognized; không tin raw exception text hoặc nguyên chuỗi timeline.sanitized. Transition chỉ giữ enum states.
- Không serialize QR payload/opaque token, JWT/password, API URL, tên người/địa điểm, raw map/node/edge GUID hoặc coordinate trace.
- Nhãn ghi chú cố định thay free text để tránh vô tình đưa PII/secrets vào export. Điều kiện tự do có thể ghi trong mẫu Markdown sau khi người dùng tự loại thông tin riêng tư.
- Không ghi âm/quay màn hình, không telemetry/upload. Clipboard chỉ ghi khi người dùng bấm; lỗi clipboard có message cố định và có thể thử lại.
- JSON được test dưới 24.000 ký tự với timeline đầy; đây là guard automated trên schema hiện tại, không phải kích thước mọi screenshot.
- Window chỉ dùng delta khi cùng controller, cùng pinned map/version, counters không giảm và pin còn khớp. Đổi session/version → deltas null, sessionOrVersionChanged; không ghép số liệu.
- Chốt report đóng băng tracking data; các bước sau không làm report đã chốt tự thay đổi. Manual fallback giữ snapshot closed/disposed trong Navigation để copy, không tự gán PASS.
- Toolkit chỉ được đưa vào entrypoint Live Test debug/Diagnostics có Live Test define; main product route không có màn checklist này. UI tests có thể mount debug component riêng.

## E. Field Measurement Toolkit

[Mẫu lượt đo](PublishedPilotFieldTrialTemplate20261028.md) để trống toàn bộ dữ liệu thực tế. App debug form có cùng các trường số:
- Ground-truth distance đo bằng thước, bước đếm tay, detector count trong cùng cửa sổ.
- Stride đã cấu hình, WayMark estimated distance.
- Endpoint error trước/sau QR do người dùng tự đo, false steps khi đứng yên.
- Cách cầm, uncertain/budget/edge re-selection với trạng thái chưa ghi nhận/có/không.
- Fixed tags cho missed/false steps, heading stale, đổi tay, network/QR/lifecycle issues.

Chỉ tính arithmetic xác định từ số nhập:
- detector bias = detector − manual steps;
- distance bias = estimated distance − ground truth;
- relative errors chỉ khi mẫu số dương và kết quả hữu hạn; zero/overflow → null/N/A.
- Distance bias **khác** endpoint position error. After-QR endpoint error để null nếu chưa đo, không tự điền 0.
- Kiểm finite/nonnegative/range, số bước nguyên; stride 0,2–1,5 m. Form chỉ ghi báo cáo, không đổi cấu hình PDR.

Gợi ý campaign: hành lang thẳng 10–20 m đo thật, nhiều lượt mỗi chiều, ca đứng/quay riêng, nhóm theo máy/người/cách cầm. Giữ cả lượt lỗi/incomplete. Không tính mean/p95 hoặc công bố mét accuracy khi chưa có số liệu; không dùng graph meters synthetic làm ground truth.

## F. Map Loading Performance Results

### F1. Phương pháp và fixture

Runner: `waymark/tool/published_pilot_benchmark_test.dart`. Fixture chỉ trong `test/fixtures/published_benchmark_fixture.dart`: fixed GUIDs, node/edge order, geometry và pixel grid arithmetic; không random fixture, không dữ liệu cá nhân. Native private routing vẫn tạo các ID phiên theo thiết kế hiện có; stable IDs trong snapshot được kiểm giữ nguyên.

Mỗi cỡ chạy theo thứ tự cố định: **1 warmup + 3 measured loads**, median từng phase. HTTP MockClient chỉ trả fixture và PNG RAM, không real server/SQL/network latency. Route calculation phục vụ tạo input nằm ngoài các phase được đo; không cộng median các phase thành một “total latency” giả.

| Fixture | Floor | Node | Directed Edge/link | Ảnh | Tổng encoded image bytes | Snapshot JSON bytes |
|---|---:|---:|---:|---|---:|---:|
| small | 1 | 20 | 38 | 1 × 256×128 | 551 | 15.549 |
| medium | 4 | 400 | 798 | 4 × 1024×512 | 15.332 | 313.381 |
| large | 8 | 1.600 | 3.198 | 8 × 2048×1024 | 101.240 | 1.255.209 |

Ảnh grid nén rất tốt, không đại diện dung lượng JPEG/PNG bản đồ cá nhân hoặc latency download thật. Kích thước decode vẫn lớn hơn encoded bytes đáng kể.

### F2. Median desktop sau tối ưu — milliseconds

| Phase | small | medium | large |
|---|---:|---:|---:|
| JSON decode snapshot | 0,128 | 1,250 | 7,219 |
| project DTO + image requests/validation + project decode | 4,382 | 46,396 | 560,619 |
| Navigation copy/build | 3,850 | 47,490 | 821,966 |
| TrackingGraph clone/build | 2,115 | 29,314 | 352,373 |
| Readiness input snapshot/mapping | 0,726 | 7,140 | 97,435 |
| Readiness validator | 0,306 | 2,747 | 15,159 |

**Windows Flutter test desktop**, không phải Android. n=3 nhỏ, JIT/scheduling/native codec/GC có biến thiên; không có p95 đáng tin cậy hoặc throughput/phone guarantee.

### F3. Tối ưu nhỏ từ bằng chứng

Trước tối ưu, large readiness input median **203,596 ms**, validator **57,057 ms**, TrackingGraph **473,194 ms**.

- `LocalMapNavigation`: tạo private indexes UI(nodeId,floorId)→stable identity và stable(floor,node)→route key khi load. Thay scan tuyến tính lặp bằng lookup, giữ original stable ID values, case-insensitive lookup và lỗi membership cũ. Không thêm cache xuyên map/version.
- `MapReadinessValidator`: dùng active directed-pair Set cho route adjacency thay quét toàn edges ở từng cặp route nodes. Rule/issue semantics không đổi.
- Sau tối ưu large: readiness input **97,435 ms**, validator **15,159 ms**, TrackingGraph **352,373 ms**. Đây là kết quả hai run desktop trước/sau, không quy mọi thay đổi phase không được sửa thành công lao tối ưu.
- Identity/snapshot ownership/unknown floor-node/case folding/reverse/multifloor được regression kiểm tra; không sửa PDR, matching candidate policy hoặc controller lifecycle.

### F4. Cache, duplicate decode và memory

- Một load project request từng floor image. Qua 4 loads, imageRequests small/medium/large lần lượt **4/16/32**: không có persistent download cache của loader.
- Source có validate/decode ảnh tại request→FloorPlanAsset, rồi decode project; Navigation clone và TrackingGraph clone lại decode ảnh. Đây là **quan sát đường gọi source**, không phải counter đo trực tiếp decoder/HAL.
- Rendering vẫn reuse MemoryImage/provider; test xác nhận `LiveTrackingPanel.readiness` giữ cùng object qua step events. Validator không bị chạy lại theo từng bước.
- Navigation/project clone vẫn là phase đáng chú ý với map lớn. Không bỏ validation ảnh hay đổi snapshot/identity để “tăng tốc”; cần profile Android và thiết kế cache có invalidation riêng trước tối ưu sâu.
- **Memory NOT MEASURED**: RSS process chứa Flutter engine/native pixels/JIT/GC, không tách allocation/peak của từng map đáng tin trong môi trường này. Không gọi encoded bytes là heap/RSS hoặc invent memory savings.

Artifacts tại `waymark/build/sprint7-evidence-20261028-v2/`:
- `published-loading-benchmark.json` + `benchmark.log` — trước tối ưu.
- `published-loading-benchmark-after.json` + `benchmark-after.log` — sau tối ưu.

Để tái lập, dùng cùng toolchain và chọn output mới để giữ evidence cũ:

~~~powershell
flutter test --no-pub tool/published_pilot_benchmark_test.dart --concurrency=1 --reporter expanded --dart-define=PUBLISHED_BENCHMARK_OUTPUT=build/<new-benchmark-output>.json
~~~

Runner không ghi đè output đã tồn tại. Nội dung fixture tái lập; wall time không được kỳ vọng giống tuyệt đối.

## G. Source Files Created / Modified

Đường dẫn dưới có tiền tố `waymark/` trừ các docs.

| Tạo mới | Vai trò |
|---|---|
| `lib/features/indoor_tracking/debug/pilot_evidence.dart` | Checklist/window/report capture/sanitization; dùng timeline/controller hiện có |
| `lib/features/indoor_tracking/debug/field_trial_measurement.dart` | Kiểm số đo, bias/relative arithmetic an toàn |
| `lib/features/indoor_tracking/debug/pilot_evidence_panel.dart` | Debug checklist/form/copy, standalone handoff page |
| `test/fixtures/published_benchmark_fixture.dart` | Synthetic Published data cố định |
| `tool/published_pilot_benchmark_test.dart` | Benchmark stage timings/output guard |
| `test/pilot_evidence_test.dart` | 6 tests model/privacy/counters/context/measurement |
| `test/pilot_evidence_panel_test.dart` | 3 widget tests explicit export/fallback/retention |
| `test/published_loading_benchmark_test.dart` | 1 fixture/load/index determinism test |
| `docs/PublishedPilotRunbook20261028.md` | Prerequisites/checklist/network plan/rollback/update workflow |
| `docs/PublishedPilotFieldTrialTemplate20261028.md` | Mẫu đo trống |
| `docs/LiveNavigationSprint7PilotHandoff20261028.md` | Báo cáo này |

| Sửa 5 file đã có so với baseline | Lý do |
|---|---|
| `lib/features/indoor_tracking/live_tracking_panel.dart` | Hook toolkit vào Diagnostics chỉ Live Test debug |
| `lib/features/navigation/navigation_page.dart` | Own evidence session và giữ frozen report sau manual fallback |
| `tool/live_test_main.dart` | Entry checklist độc lập từ Home |
| `lib/features/navigation/local_map_navigation.dart` | Private identity indexes, không đổi routing/IDs |
| `lib/features/indoor_tracking/map_readiness.dart` | Set lookup adjacency, không thay rules |

Không sửa backend, launch profiles, CORS/TLS/firewall/SQL config, auth/roles/QR/Published DTO, maps/assets/Builder/AI/History, dependencies/toolchain/signing hoặc existing test source. SensorProvider/Session/Bridge, PDR, matcher, IndoorTrackingController và budget giữ nguyên hash.

## H. Automated Tests and Regression

Kết quả **lần chạy cuối**, không cộng số targeted vào full hoặc cộng các run benchmark:

| Gate | Kết quả | Evidence dưới sprint7-evidence-20261028-v2 |
|---|---|---|
| Targeted 9 files | **85 PASS / 0 FAIL** | targeted-tests.log |
| Full Flutter suite | **532 PASS / 4 SKIP / 0 FAIL** | full-tests.log |
| Live Test define UI run | **3 PASS** (run riêng, không cộng vào full) | livetest-gated-ui.log |
| Desktop benchmark trước/sau | Mỗi run **1 PASS**; 3 cỡ fixture | benchmark.log / benchmark-after.log |
| Analyzer | **No issues found** | analyze.log |
| Format 13 file Dart sửa/tạo | **0 changed** | format.log |
| git diff --check | **PASS** | kiểm trong phiên |
| Android main debug | **PASS** | android-main-build.log |
| Android Live Test debug | **PASS** | android-livetest-build.log |
| Package/SDK/permissions/signature | **PASS**, certificate khớp Sprint 6 | *apk-badging.txt / *apk-signing.txt |
| Backend runtime/SQL/server-camera E2E/phone test mới | **NOT VERIFIED / không chạy** | read-only-environment-audit.json |

Bốn skip giữ điều kiện live SQL/Vision/platform cũ, không bật SQL write hoặc tắt existing tests. Regressions Published QR/preflight/guided/manual/multifloor/rendering/Builder/AI preferences/SAF/history được giữ theo suite có sẵn.

Coverage mới tập trung vào:
- Mọi checklist NT ban đầu, PASS/FAIL chỉ từ thao tác, không nâng thành accuracy/E2E verification.
- Counts detector ≠ displacement, chốt window không đổi theo steps sau đó.
- Allowlist loại QR/JWT/endpoint/raw IDs, metadata device redaction, bounded timeline từ nguồn cũ.
- Summary readiness, pin/version và same-map/different-controller mismatch.
- Measurement zero/invalid/tiny finite arithmetic, không tự tạo endpoint error.
- Clipboard chỉ explicit tap; field invalid không được export.
- Manual fallback/disposal vẫn giữ report; LiveTest-gated Nav UI path được kiểm riêng.
- Deterministic Published bytes/IDs, case-insensitive index/membership errors, repeated image requests, report reuse qua steps.

Lệnh chính:

~~~powershell
flutter analyze --no-pub
flutter test --no-pub test/pilot_evidence_test.dart test/pilot_evidence_panel_test.dart test/published_loading_benchmark_test.dart test/local_map_navigation_test.dart test/multifloor_navigation_test.dart test/live_tracking_graph_test.dart test/published_map_readiness_test.dart test/published_live_integration_test.dart test/live_navigation_ui_test.dart --reporter expanded
flutter test --no-pub --reporter expanded
flutter test --no-pub test/pilot_evidence_panel_test.dart --dart-define=WAYMARK_LIVE_TEST=true --reporter expanded
flutter build apk --debug --no-pub
flutter build apk --debug --no-pub --flavor liveTest --target tool/live_test_main.dart --dart-define=WAYMARK_LIVE_TEST=true
~~~

Các mock/fake đều phục vụ tests; không đưa deterministic sensor/replay vào APK để tạo chuyển động giả.

## I. APK Path, Signing, SHA256 and Update Guide

| Metadata kiểm từ APK | Giá trị |
|---|---|
| Exact artifact | `D:\project\WayMark\waymark\build\live-navigation-artifacts\WayMark-Live-Test-Sprint7-20261028-debug.apk` |
| Package / label | `com.example.waymark.livetest` / **WayMark Live Test** |
| Version / variant / entrypoint | 1.0.0 / code 1; liveTestDebug; tool/live_test_main.dart |
| Size | **187.745.970 bytes** (~187,75 MB, universal debug APK) |
| SHA256 file | `87ADD1157E7115F9A86C678659DF666356B5FFE3F5555302B62D27DBE115663D` |
| Signing certificate SHA256 | `8c15d5eb313223a87d82ef435a13307e74f8abf1a9da2e9dd8de9c21b0cf4df2` — **khớp Sprint 6** |
| min/target/compile SDK | **24 / 36 / 36** — tối thiểu Android 7.0 |
| ABIs | arm64-v8a, armeabi-v7a, x86_64 |
| Permissions | INTERNET, CAMERA, ACTIVITY_RECOGNITION, ACCESS_NETWORK_STATE, permission nội bộ DYNAMIC_RECEIVER_NOT_EXPORTED của package test |

Main APK vẫn `com.example.waymark`, label waymark. APK Sprint 6 giữ nguyên SHA256 `0C4411CA5597B85E35B71795580D5CC4B22ADA4247D9A24570D640EA3A474CF9`. Không đổi signing hoặc upload.

**Cập nhật Drive không USB:** người dùng tự chuyển file artifact tới Drive cá nhân/phương thức tin cậy, tải về Android, mở bằng Files và chọn **Cập nhật WayMark Live Test**. Chỉ cấp quyền cài cho nguồn tin cậy nếu OS yêu cầu, có thể tắt lại sau. Same package/certificate của hai artifact local hỗ trợ update giữ sandbox; **chưa thực hiện update trên điện thoại trong phiên này**. Không nhắm vào app WayMark chính.

Nếu installer báo không tương thích/chữ ký/version, giữ app/data hiện có và gửi lỗi để kiểm artifact đã cài; không uninstall/reinstall hoặc xóa data để vượt. Checklist/report trong RAM không phải dữ liệu persist được bảo đảm qua app restart, nên copy trước.

## J. Unresolved Real-Device / Published E2E Gates

- Chưa kiểm APK Sprint 7 install/update/sensor/Published QR bằng camera thật.
- Chưa có endpoint test reachable/TLS đã được xác minh, SQL/image storage runtime hoặc real server response trong phiên.
- User smoke bản trước chỉ là evidence sơ bộ sensor→PDR→dot trên Android; chưa có ground-truth/error/heading/battery campaign.
- False steps khi lắc vẫn có thể làm estimate tiến. Không có anti-shake filter mới hoặc accuracy radius giả.
- Geometry vẫn là cạnh thẳng cần đối chiếu; không wall mask/polyline hoặc floor inference.
- Desktop clone/decode lớn còn đáng profile trên thiết bị. Không suy memory/latency điện thoại từ bảng F.
- Report/checklist là user-reported, số đo app form có thể nhập sai; validation chỉ kiểm kiểu/phạm vi/arithmetics.
- Report được giữ sau **manual fallback trong cùng Navigation**; rời màn hình/đóng app/new Live session sẽ mất dữ liệu RAM. Không hứa lưu qua mọi map replacement/unmount hoặc crash.
- Ghi chú chỉ fixed tags, không free text; điều kiện chi tiết ghi trong template đã loại PII. Không tự quay màn hình hoặc upload.
- Header build version phản ánh pubspec/artifact 1.0.0+1 hiện tại; cần cập nhật cùng release metadata khi thay version về sau.

## K. Next Recommendation

Có thể tiếp tục code/tooling mà không bắt buộc ADB ngay: chuẩn hóa cách nhận/so sánh sanitized reports từ nhiều lượt, bổ sung fixture ảnh có độ nén gần thực tế, và profile tách chi phí project/navigation/image decode trước thiết kế cache. Bất kỳ cache ảnh/snapshot mới phải có invalidation theo map/version và không bỏ validation để đổi lấy số benchmark đẹp.

Khi người dùng thuận tiện, chọn một Published map đã được phép dùng với corridor đo 10–20 m và endpoint HTTPS hợp lệ, thực hiện runbook, gửi JSON + template trước/after QR. Dữ liệu đó là căn cứ cho stride/heading/false-positive work sau này; không tự tăng budget hoặc thay thuật toán cảm biến.

## L. Change Safety

Baseline Sprint 7: **366 Git status entries = 43 modified + 323 untracked**, SHA256 **509 file** tracked/untracked không bị ignore.

Sau bàn giao: **377 entries = 43 modified + 334 untracked**, **520 file** trong tập hash. **504/509 file cũ giữ nguyên hash**; đúng **5 file** ở G thay đổi, không mất file cũ; thêm **8 Dart/tool/test + 3 docs**. Không nhận các thay đổi dirty từ Sprint trước làm công việc mới.

Evidence mới dùng `waymark/build/sprint7-evidence-20261028-v2/` vì `build/sprint7-evidence/` đã chứa log cũ từ công việc trước; không ghi đè/xóa chúng. Các docs/APK cũ giữ nguyên. Build/evidence/artifacts nằm dưới build bị ignore, không tính vào Git hash manifest.

Không reset/clean/đổi branch/stage/commit/push, không SQL write/migration/E2E, không mở public/LAN listeners/firewall, không đổi TLS/auth/CORS/secrets/Windows security, không upgrade toolchain. Không install/uninstall/upload hoặc đọc/xuất secret values.
