# WayMark Full Product Completion — Cycle 2

**Thực hiện: 31/10/2026 — Asia/Saigon.** Tên file giữ suffix `20261030` theo yêu cầu, không ghi đè báo cáo cũ.
Workspace: `D:\project\WayMark`. Chiến lược: continuous code completion, deferred physical acceptance.

## A. Executive Summary

Cycle 2 tập trung vào retained Creator workflows, session recovery và responsive UX. Đã triển khai owner/session guards, vô hiệu hóa dialog cũ, giữ Builder draft trong RAM khi phiên hết hạn và không tự retry mutation.

**CODE COMPLETE cho phạm vi Cycle2 đã kiểm thử:**590 Flutter PASS /4 SKIP; analyzer/format/diff-check sạch;171 selected backend tests PASS; Main và LiveTest build/signature PASS. **EMULATOR SMOKE: NOT VERIFIED trong Cycle2** sau các lần thử runtime và cleanup; không dùng smoke Cycle1 thay bằng chứng mới.

Bằng chứng backend đã thay đổi so với Cycle 1: chạy thông thường hiện thực thi được combined HTTP/Identity/SQLite scenario và nhóm regression cô lập **171 PASS**. Không thay Windows policy hoặc dùng kỹ thuật bypass. Đây không phải SQL Server thật hoặc Published phone E2E.

Kết quả kiểm thử, build, APK metadata và emulator chốt tại H1/J1. **INTERNAL DEBUG RELEASE CANDIDATE**, chưa PRODUCTION READY. ANDROID PHONE PHYSICAL, PUBLISHED SERVER/CAMERA E2E và PRODUCTION SIGNING vẫn PENDING.

Không sửa thuật toán PDR/heading/stride/matching, budget40, schema/Published contract, JWT policy/secrets hoặc cấu hình hạ tầng.

## B. Cycle 1 Carryover Backlog

| Carryover | Kết quả Cycle 2 |
|---|---|
| Retained cloud action có thể tiếp tục dưới tài khoản mới | FIXED trong các đường đi chính được audit/test; scope theo token + revision, guards trước request và sau await |
| Session expiry routing còn PARTIAL | IMPLEMENTED recovery tại chỗ, không pop Builder; private 401/403/network/stale/public được xử lý khác nhau |
| Chưa có layout coverage ngoài Login | AUTOMATED TESTED 24 ca Home/MyMaps/onboarding/cloud/Search/Preview/Navigation/Live; sửa lỗi tái hiện |
| Chưa có performance evidence mới | Có baseline desktop và decode/cleanup timings; **MEMORY NOT MEASURED** |
| Windows policy chặn test DLL | Lần chạy hiện tại không còn chặn; 171 selected backend tests thực thi PASS, không suy đã thay policy |
| Real Published QR / phone trusted endpoint / field accuracy | Vẫn PENDING; không tự tạo token, mở mạng hoặc yêu cầu điện thoại ở checkpoint |
| Production signing | Vẫn PENDING; giữ debug key để cài cập nhật nội bộ |

## C. Retained Creator Workflow Audit

Đọc báo cáo Cycle 1 và source hiện tại: AuthSession/AuthApiService, PublishedMapApiService, MapDraftApiService, WayMarkApiService, onboarding, MyMaps, Builder core/mobile/project parts, DraftServerSession, cloud Publish/QR, Profile/Settings, AccountSecurity và History. Không có AGENTS.md áp dụng ở workspace/ancestors; AGENTS trong Figma design-reference không thuộc phạm vi.

| Workflow / source dưới waymark/lib | Await / rủi ro đã kiểm | Hành vi sau hardening |
|---|---|---|
| features/admin/create_map_page.dart | create → private image/project decode → profile → mở Builder; callback còn giữ profile A | Scope giữ nguyên từ lúc mở; kiểm sau từng phase. Đổi account thì ẩn form A và không mở Builder từ kết quả cũ |
| features/admin/my_maps_page.dart | list/get → project multi-image decode → navigation | Giữ generation guards Cycle 1; service project bổ sung identity pin xuyên các ảnh, tránh request ảnh tiếp theo bằng B |
| features/admin/draft_map_editor.dart | Save-before-leave, load/save/history/restore/recover image, mở Cloud, decode | Dialog thuộc session gốc; async result không áp dụng sau invalidate/dispose; local graph giữ trong State |
| features/admin/draft_map_editor_mobile.dart | validation/new/import/action dialogs và retained bottom sheet | Modal đổi thành thông báo chung khi session đổi; ẩn private content và confirmation; đóng sheet không chuyển dữ liệu sang B |
| features/admin/draft_map_editor_project.dart | floor/link dialogs, rename decode, delete confirmations | Scoped dialog và post-await guard; không tiếp tục thao tác local thuộc A dưới B |
| features/admin/map_project_cloud_page.dart | image upload/create → project save → readback; load/reconcile; publish/revoke confirmations; QR label/PNG/Visitor load | Workflow owner cố định; kiểm trước API qua scope và sau async; confirmation cũ mất hiệu lực; callbacks onLinked/onSaved không thay Builder mới |
| features/admin/draft_server_session.dart | multi-request metadata/create/upload/save/restore | Không viết lại implementation; gọi trong scoped Builder task; private API kiểm scope trước mỗi request. Optimistic version và uncertainty semantics giữ nguyên |
| features/profile/profile_page.dart / admin/settings_page.dart | profile load/save + cached metadata | Giữ guards Cycle 1; thêm hành động đăng nhập lại khi credential bị 401 |
| features/auth/account_security_page.dart | retained password/email inputs, late account action và completed screen | Ẩn input khi owner đổi; result cũ không clear B; completed screen cũng không được dùng nút login cũ để logout session mới |
| features/history/history_page.dart | detail/confirm dialogs | Giữ action owner guards Cycle 1; nội dung modal cũ được ẩn khi owner đổi; public/manual navigation không phụ thuộc login |

Ba phase được phân biệt:

1. **Chưa gửi request:** scope invalid → không gửi bằng session mới; dialog chỉ còn thông báo chung/Close.
2. **Request đang xử lý:** response cũ bị loại; không áp dụng UI/link/metadata hoặc khởi động request nối tiếp dưới B.
3. **Server có thể đã commit:** client cancellation không rollback. Timeout/network/stale mutation response vẫn uncertain. Cloud yêu cầu readback/reconcile; không tự Save/Publish/revoke lại.

Một file được formatter đổi whitespace trong lượt format thư mục ban đầu: `features/admin/draft_files_native.dart`. Không đổi logic SAF hay channel; liệt kê riêng để không nhận là functional fix.

## D. Owner-Scoped Workflow Fixes

### D1. Session / workflow boundary

`services/auth_session.dart` bổ sung:

- `OwnerWorkflow` capture token, revision và local owner equality key. Revision chống ABA dù token string giống nhau.
- `run()` giữ guard xuyên chuỗi async trước private request; `wait()` kiểm result và generation của workflow sau await. Rebind cùng owner không làm continuation của generation cũ sống lại.
- Listener được gỡ khi dispose. Workflow đã đóng không được phát request deferred.
- Owner equality dùng issuer/subject JWT nếu có, fallback server username. Đây chỉ là khóa so sánh recovery, **không xác minh chữ ký hoặc cấp quyền client**; server tiếp tục quyết định authorization.

`features/auth/workflow_recovery.dart` chứa recovery screen và scoped dialog. Không thêm state-management framework/dependency.

### D2. Cloud / Builder / dialogs

Regression trước sửa xác nhận Publish và revoke counters tăng từ0 lên1 sau account switch. Sau sửa, confirmation cũ không còn action; private content bị ẩn. Test Save-before-leave dùng Builder thực tế cũng xác nhận không lưu server/file sau switch.

Cloud giữ detached draft. QR label lookup public, PNG render hoặc Visitor load từ trang quản lý vẫn thuộc workflow quản lý ban đầu; guest public reader độc lập không bị ép vào owner này.

Request cũ đã rời app/native file picker có thể hoàn tất theo hệ thống; guard client không thể thu hồi transaction/file operation đã được chấp nhận. Không công bố cancellation là bằng chứng không có ghi.

### D3. File changes của Cycle 2

Các file đã có trước, thay đổi so với hash baseline (không quy toàn bộ Git diff dirty cũ cho Cycle 2):

| Nhóm | File dưới waymark/ | Thay đổi |
|---|---|---|
| Session | lib/services/auth_session.dart | expiry state, owner workflow, scoped continuation |
| Private services | lib/services/auth_api_service.dart; map_draft_api_service.dart; published_map_api_service.dart; waymark_api_service.dart | current private401 → expiry; stale session không expire B; private project multi-image pin; scope gate trước send |
| Creator | lib/features/admin/create_map_page.dart; my_maps_page.dart; map_project_cloud_page.dart | onboarding/cloud owner, recovery, reconciliation, retained QR/dialog, responsive fields/status |
| Builder | lib/features/admin/draft_map_editor.dart; draft_map_editor_mobile.dart; draft_map_editor_project.dart | retain RAM + hide old owner, scoped dialogs/sheets/results, explicit leave confirmation |
| Private UI | lib/features/admin/settings_page.dart; lib/features/profile/profile_page.dart; lib/features/history/history_page.dart | expired login action; History detail/confirm privacy |
| Authentication UI | lib/features/auth/login/login_page.dart; account_security_page.dart | login có return-to-workflow; retained sensitive forms/completed action owner guard |
| Responsive | lib/features/home/home_page.dart; lib/features/navigation/navigation_page.dart; lib/features/route/route_preview_page.dart | flexible nav labels, bounded scroll action area, scroll header/banner |
| Existing tests | test/profile_settings_smoke_test.dart | expired Retry không tái dùng credential; renewed session mới hồi phục Profile, giữ assertion thành công |
| Existing tests | test/map_draft_editor_server_test.dart | bổ sung retained Save-before-leave account switch regression; không bỏ assertion cũ |
| Format only | lib/features/admin/draft_files_native.dart | whitespace formatter; không semantic change |

File mới:

- `waymark/lib/features/auth/workflow_recovery.dart`.
- `waymark/test/cycle2_workflow_test.dart`.
- `waymark/test/cycle2_recovery_test.dart`.
- `waymark/test/cycle2_responsive_test.dart`.
- `waymark/tool/cycle2_image_lifecycle_test.dart` (test-only benchmark entry, không import vào app).
- Báo cáo này.

## E. Session Expiry & Unsaved Draft Recovery

| Response / sự kiện | Xử lý |
|---|---|
| Current private HTTP401 | Đánh dấu expired, tăng revision để invalidate workflows, clear cached profile; giữ owner identity và RAM draft. Credential cũ bị chặn gửi tiếp ở private adapters |
| Private HTTP403 | Báo thiếu quyền; không auto logout hoặc expire |
| HTTP401/403 của request cũ | Không thay session mới; stale result bị loại trước xử lý status |
| Timeout/disconnect | Không expire session; mutation có thể đã commit, giữ uncertain |
| Public anonymous401 | Public endpoint/config failure; không expire private session, không thêm Authorization |
| Probe kết nối không JWT | HTTP401 vẫn là transport reachability, không phải expiry của người đang đăng nhập |

Recovery hoạt động **tại chỗ**, không tự navigate/pop Builder khi401:

1. Ẩn nội dung owner cũ; giữ graph/GUID/image và dirty state trong State.
2. Mở Login ở chế độ quay lại workflow, không thay toàn bộ stack bằng Home.
3. Xác minh profile qua private API và đối chiếu owner key; chỉ explicit recovery mới rebind cùng owner.
4. Owner B không được nhận draft/cache A. Không có sync hoặc chuyển workspace tự động.
5. Không tự retry Save/Publish sau login. Cloud phải GET/readback; chỉ khi server khớp graph/ảnh/name local mới mở khóa uncertainty. Nếu không khớp, giữ local và không auto overwrite.
6. Builder cảnh báo đối chiếu server trước ghi; optimistic version tiếp tục bảo vệ server. Recovery không giải quyết conflict bằng cách bỏ version check.
7. Rời recovery screen của Builder cần xác nhận rõ việc bỏ bản đang giữ trong RAM.

**Giới hạn:** không thêm encrypted storage/secure persistent login/refresh token; không bảo đảm recovery qua app restart. Native draft recovery hiện có giữ nguyên owner scope, không tự đổi sang B. Workflow bắt đầu không xác định được owner key không được tự nhận là cùng owner sau login; cần exit/reopen theo policy rõ ràng.

## F. Responsive / Accessibility Results

24 ca: 8 trang × 3 viewport, text scale2:

- 320×640 với bottom keyboard inset240.
- 390×844 portrait.
- 640×360 landscape/viewport thấp.

Trang: Home, MyMaps, onboarding, linked Cloud, Search, Preview, Navigation, guided Live panel. Cloud dùng fixture project/link/QR có readiness, mở và Cancel dialog Publish thật. Navigation thử anonymous/manual.

Lỗi tái hiện và sửa:

| Source | Red evidence | Fix |
|---|---|---|
| Home bottom navigation | overflow ngang380/310/60px ở ba viewport | Chia chiều rộng từng item bằng Expanded, label có thể wrap |
| Preview header/banner | overflow dưới76px khi keyboard và26px ở landscape | Header/banner trong vùng Flexible có scroll, giữ route viewport |
| Navigation | action area tràn dưới, Row tràn ngang29px tại320 | Bounded action area có scroll; hai nút xếp dọc và vẫn giữ xác nhận explicit |
| Linked cloud floor dropdown | overflow ngang29px tại320/text2 | isExpanded cho selectors |
| Cloud status / confirmation | Nội dung dài cần không chiếm hết body, button phải tiếp cận được | Status có chiều cao giới hạn + scroll; confirmation scrollable |

Không xóa cảnh báo safety/manual/estimated. Không đổi arrival/QR semantics. Đây là targeted coverage, không chứng nhận mọi màn hình, mọi ngôn ngữ hoặc mọi OEM accessibility setting. Builder dialogs ở320 đã có regression trước và được chạy lại trong full suite.

Một số lần thử ban đầu sai harness (lazy finder chưa scroll/pump; Live cleanup chờ fake event loop) đã được sửa. Không coi những lỗi harness đó là lỗi sản phẩm. Red overflow và retained action counters được ghi riêng trong evidence.

## G. Performance / Memory Findings

Tái sử dụng `tool/published_pilot_benchmark_test.dart` và synthetic Published fixtures Sprint7. Windows Flutter test desktop, MockClient, không HTTP/SQL thật. Mỗi fixture1 warmup +3 lần đo; median ms:

| Fixture | Floors /nodes /edges | JSON parse | Project + image validation | Navigation clone | Tracking graph clone | Readiness input | Validator |
|---|---|---:|---:|---:|---:|---:|---:|
| Small | 1 /20 /38 | 0.193 | 5.017 | 6.139 | 3.529 | 0.917 | 0.537 |
| Medium | 4 /400 /798 | 3.092 | 63.603 | 67.964 | 48.777 | 11.264 | 4.241 |
| Large | 8 /1600 /3198 | 5.388 | 273.111 | 338.597 | 167.610 | 44.353 | 8.389 |

Ảnh theo fixture: 256×128, 1024×512, 2048×1024. Snapshot bytes lần lượt15,549 /313,381 /1,255,209; đây là kích thước tài liệu, **không phải RAM**. Mỗi fresh project load tải mọi ảnh; số GET ảnh qua4 lần =4 /16 /32, không có persistent download cache.

Benchmark bổ sung image/lifecycle, 1 warmup +10 measured/controller cycles mỗi size:

| Ảnh | Validate/decode median ms | Controller close/dispose median ms |
|---|---:|---:|
| 256×128 | 0.499 | 0.139 |
| 1024×512 | 3.341 | 0.258 |
| 2048×1024 | 8.606 | 0.163 |

Controller cleanup benchmark dùng UnsupportedSensorProvider, không phải native Android unregister latency. Controller không nhận movement; close/dispose được await trong từng iteration. Source image validator dispose codec/decoded frame trong finally; overlay/cache giữ phạm vi scene/session theo source audit.

**MEMORY NOT MEASURED:** không có đo baseline/peak/retained heap/native pixels đáng tin cậy hoặc ép GC kiểm soát. Không dùng encoded bytes hoặc RSS tổng của test process thay RAM map. Không chứng minh “không leak” chỉ bằng controller close thành công.

Đây là baseline, không có optimization claim hoặc before/after improvement. Không loại image validation, immutable snapshot hoặc version pin để giảm số đo. Phone performance còn PENDING.

## H. Automated Integration / Regression Results

Evidence local, ignored: `waymark/build/full-product-cycle2-20261031/`.

- Trước sửa: `workflow-before-valid.log` xác nhận current private401 chưa invalidate revision; Publish/revoke thực thi1 lần dưới replacement session.
- `integrated-regression.log`: **109 PASS** trước bổ sung case cuối.
- `responsive-final.log`: **24 PASS**, không cộng vào full suite.
- `profile-recovery-regression.log`: **9 PASS**.
- `builder-dialog-final.log`: **6 PASS**, có Builder Save-before-leave thực tế.
- `account-done-regression.log`: **15 PASS**, gồm case completed account screen và History/manual semantics.
- Full run đầu: **587 PASS /4 SKIP /1 FAIL** do test Profile mong Retry tái dùng credential sau401. Đã đổi expected flow sang explicit renewed session và thêm assertion không hiện profile trước login; không bỏ kiểm recovery.
- Các full run tiếp theo588 rồi589 PASS là checkpoint trước case cuối. H1 ghi gate cuối; không cộng targeted counts.

Coverage yêu cầu:

| Case | Evidence / cấp kiểm |
|---|---|
| A mở Save dialog → B trước confirm | Builder widget regression + scoped Save confirmation widget |
| A gửi Save → B → late response | private service delayed response tests Cycle1/2 |
| Save có thể commit nhưng mất response | timeout fixture, uncertain=true, đúng1 request, không auto retry |
| Publish dialog logout/switch | retained Publish widget + revision invalidation |
| QR management/revoke cũ | retained revoke widget và guarded QR/readback source |
| Old A401 sau B / same-token new revision | deterministic service test; B revision giữ nguyên |
| Current401 | Published/Draft/legacy adapters và Profile regression |
| 403 /network /public401 | session revision không bị expire sai |
| Unsaved Builder khi expired | giữ encoded graph/GUID trong RAM, recovery gate không pop |
| Cùng owner recovery | profile verification GET, graph giữ nguyên, không POST/PUT |
| Owner khác | nội dung A bị ẩn, rebind bị từ chối |
| Disposed widget /workflow | pending list hoặc deferred request không phát side effect |
| Public QR/manual khi anonymous | full Published/Navigation suite và responsive Navigation |

Không gọi các widget/MockClient test là SQL Server E2E hoặc camera APK E2E.

### H1. Quality gates cuối

| Gate | Kết quả | Evidence |
|---|---|---|
| Dart format | PASS,27 Dart files /0 changed | format-final.log |
| Analyzer | PASS,No issues found | analyze-handoff.log |
| Full Flutter suite cuối | **590 PASS /4 SKIP /0 FAIL**, exit0,1m13s | full-tests-complete.log |
| Backend build | PASS,0 warnings /0 errors | backend-build.log |
| Backend execution | **171 PASS /0 FAIL /0 SKIP**, fixture cô lập | backend-regression.log |
| git diff --check | PASS,exit0 | diff-check-final.log |
| Main build cuối | PASS,assembleDebug46.6s | android-main-final.log |
| Live Test build cuối | PASS,assembleLiveTestDebug15.5s | android-livetest-final.log |
| APK metadata/signature | PASS,aapt +apksigner exit0 | apk-metadata-final.json |

4 SKIP vẫn là opt-in live Vision, live SQL public navigation, P0 live SQL navigation và web-only routing branch trên VM. Không chuyển skip thành PASS. Benchmark tool tests nằm ngoài full test/ suite và không cộng vào590.

## I. Backend Windows Policy Gate

Chạy thông thường:

~~~powershell
dotnet build WayMark.Api.Tests/WayMark.Api.Tests.csproj --no-restore
dotnet test WayMark.Api.Tests/WayMark.Api.Tests.csproj --no-build --no-restore --filter FullyQualifiedName~ProductCompletionCycle1Tests
~~~

- **BACKEND BUILD PASS:**0 warning /0 error.
- Combined backend HTTP/Identity/relational SQLite/managed image/restart test: **1 executed PASS**.
- Selected regression: **171 executed PASS /0 FAIL /0 SKIP**, gồm ProductCompletionCycle1, PersonalMapOnboarding, PersonalQrPublishHotfix, PublishedMap, NavigationHistory, AdminAuthorization, AccountSecuritySprint9, MapDraftApi, MapDraftImageBoundary và ManagedImageStorage.
- 1-test run nằm trong selected171; không cộng thành172.
- Không chạy toàn bộ backend suite hoặc opt-in SQL Server E2E. Test state thuộc fixture cô lập, không dùng database thật làm thay thế.
- Cycle1 policy block là bằng chứng lịch sử. Lần này DLL load/test thực thi được; chưa xác định nguyên nhân chính sách/môi trường thay đổi ngoài phiên, không suy enforcement bị tắt.
- Không dùng Unblock-File, rename/path/runner/signing trick hoặc chỉnh Windows policy. Nếu block tái xuất hiện, policy remediation vẫn APPROVAL REQUIRED theo quy trình chủ máy; không tự làm.

## J. Main / Live Test APKs

Artifact directory: `D:\project\WayMark\waymark\build\product-completion-artifacts`.

- `WayMark-Main-Cycle2-20261031-internal-debug.apk`.
- `WayMark-Live-Test-Cycle2-20261031-internal-debug.apk`.

Tên dùng ngày thực hiện31/10; báo cáo vẫn dùng suffix30/10 theo yêu cầu.

~~~powershell
# tại waymark/
flutter build apk --debug --no-pub
flutter build apk --debug --no-pub --flavor liveTest --target tool/live_test_main.dart --dart-define=WAYMARK_LIVE_TEST=true
~~~

Metadata/hash/size/signature cuối và emulator ở J1. Giữ package `com.example.waymark` và `com.example.waymark.livetest`, version1.0.0/code1, min24/target36/compile36; ABI arm64-v8a, armeabi-v7a, x86_64.

Giữ Android Debug signer SHA256:
`8c15d5eb313223a87d82ef435a13307e74f8abf1a9da2e9dd8de9c21b0cf4df2`.

Cùng package/key hỗ trợ cập nhật nội bộ bằng `adb install -r` khi có app cùng signer; không uninstall/reset data để vượt mismatch. Không bảo đảm tương thích app được ký bằng key khác. Không tạo production key, upload APK hoặc phát hành. APK Cycle1 được giữ nguyên.

### J1. Artifact chốt

| Thuộc tính | Main | Live Test |
|---|---|---|
| Exact file dưới artifact directory | WayMark-Main-Cycle2-20261031-internal-debug.apk | WayMark-Live-Test-Cycle2-20261031-internal-debug.apk |
| Package /label | com.example.waymark /waymark | com.example.waymark.livetest /WayMark Live Test |
| Version /code | 1.0.0 /1 | 1.0.0 /1 |
| Size bytes | 211,008,572 | 187,769,365 |
| SHA256 | A6EC3CC94F5F1480319CAA96B7CDB094CB6D2293A4853130136D11B9B078B0FE | 9A99AE5BD7A16798426BBFC8284EB191F62A94614ECDDE13AD3877BFFDFCF2FE |
| Signer SHA256 | 8c15d5eb313223a87d82ef435a13307e74f8abf1a9da2e9dd8de9c21b0cf4df2 | Cùng signer Main |

`apk-metadata-final.json` xác nhận min24/target36/compile36 và cả ba ABI đã nêu. Signature verify thành công, debug signer giữ nguyên Cycle1.

### J2. Emulator execution / cleanup

Đã thử AVD có sẵn `Medium_Phone_API_37.0` /API37 tại emulator-5580, headless/hidden, software renderer, `-read-only -no-snapshot-load -no-snapshot-save`. Không sửa AVD config, wipe userdata hoặc uninstall app. Lần chạy trong lúc test/build và sau gián đoạn bị offline/khởi động chậm; đã dừng đúng emulator thuộc nhiệm vụ trước retry. Lần cuối dùng override RAM2048 trên command line, không đổi cấu hình lưu.

Lần cuối `getprop sys.boot_completed` trả1. Main APK push211,008,572 bytes hoàn tất nhưng install chưa trả Success; client chờ thiết bị khi cleanup. **INSTALL/UPDATE và UI SMOKE CYCLE2: NOT VERIFIED**, LiveTest install/UI chưa xác minh. Metadata/signature/build PASS không thay kết quả này. Không dùng emulator để chứng nhận native sensor hoặc field accuracy.

Đã `adb -s emulator-5580 emu kill`, hủy đúng pending install client. Sau đó `adb devices -l` rỗng, không còn process QEMU của AVD ở port5580, không còn listener5580/5581. ADB server chung được giữ, không kill tiến trình .NET/ADB khác. Với một lần emulator offline trước đó, chỉ Stop-Process đúng QEMU có command line AVD/port/read-only của nhiệm vụ.

Log emulator nằm trong evidence directory. Chỉ xác nhận các flags/thao tác đã dùng; không tuyên bố hash toàn bộ ignored AVD/cache giữ nguyên. Không có APK install hoặc dữ liệu điện thoại thật bị tác động.

## K. Security & Data Preservation

Baseline trước code: **527 hashed files;384 Git entries =43 modified +341 untracked**, branch `auth-jwt-assignment`,0 staged. Baseline lưu trên disk, gồm full status/hash và hash hai APK Cycle1.

Không reset/clean/stage/commit/push/đổi branch; không real SQL migration/DML/grant, không sửa JWT secret/auth policy/Published DTO/QR format, không đổi certificate store/TLS validation, firewall/LAN/DNS/public tunnel/CORS, toolchain/dependency/signing key.

Không đọc QR thật từ SQL/log/source, không publish/revoke dữ liệu thật. Fixture QR được tạo trong backend test host cô lập theo test authorization. Không khởi động production API, không cài APK lên điện thoại.

Các lần build/test có thể thay ignored caches/generated output; chúng không thuộc source hash baseline. Không dùng source hashes để khẳng định mọi byte ignored storage đã được audit. Không có thao tác với storage/map/History thật.

Một lượt tool bị ngắt khi build LiveTest đang chạy; đã kiểm tra process/artifact/log trước retry, không coi APK cũ là build mới. Named artifacts trong task được cập nhật sau final code fix; hash Cycle1 không đổi.

Integrity summary cuối ở K1.

### K1. Final source / Git invariants

**533 files /391 status entries =44 modified +347 untracked**,0 staged, branch vẫn `auth-jwt-assignment`. Baseline527 files: **505 giữ nguyên hash,22 file cũ đổi hash đúng D3,0 file mất**, cộng6 file mới đúng D3. Status tăng thêm1 modified vì `waymark_api_service.dart` trước đó clean; không nhầm với các file untracked có sẵn.

Hai named APK Cycle1 đều giữ nguyên SHA256 baseline. Tracking/PDR/matching/sensor bridge/config/backend source không đổi hash. Evidence `final-invariants.json`; ignored build/cache/APK outputs chỉ được ghi trong công việc được giao. Không stage/commit/push.

## L. Remaining P0/P1/P2

| Mức | Trạng thái / việc còn lại |
|---|---|
| P0 | Không còn lỗi tái hiện trong các regression owner/session đã sửa; không phải security certification toàn sản phẩm |
| P1 | Physical Android sensor/permission/lifecycle, corridor accuracy/false steps/heading/stride, real QR correction còn PENDING |
| P1 | Published endpoint HTTPS được Android tin cậy + authorized QR + runtime SQL/image storage/camera E2E còn PENDING |
| P1 | Production signing/deployment configuration chưa được phê duyệt |
| P1 | Cần real SMTP/AI provider delivery/config evidence nếu nghiệm thu các chức năng đó |
| P2 | Accessibility sweep ngoài targeted matrix (nhiều ngôn ngữ, OEM, screen reader); cache/heap profiling trên phone |
| P2 | Workflow bắt đầu guest/owner key unknown cần policy explicit export/reopen; không tự chuyển draft sang tài khoản mới |
| P2 | Recovery xuyên restart/secure persistence/refresh token cần thiết kế riêng; chưa triển khai |
| OUT_OF_SCOPE | Background tracking, BLE/UWB/GPS, auto floor/arrival, new heading filters hoặc tăng budget40 |

Source tracking/PDR/map matching/sensor bridge giữ nguyên hash baseline. UI Navigation thay layout, không đổi progress/arrival/position semantics.

## M. Cycle 3 Recommendation

1. Khép các lỗi có deterministic evidence mới ở account recovery và retained routes nếu phát hiện; không viết lại module đang pass.
2. Bổ sung screen-reader/focus/keyboard reachability và responsive coverage các modal còn lại theo lỗi đo được.
3. Đo retained heap/native image memory trên môi trường profiling phù hợp; chỉ tối ưu cache/clone sau before/after measurements.
4. Giữ selected backend regressions làm gate; thêm opt-in môi trường thật khi có authorization, không thay fixture bằng SQL dữ liệu thật.
5. Chuẩn bị một đợt nghiệm thu tổng thể phone/Published/sensors sau completion. Không yêu cầu người dùng thử ở checkpoint này.
6. Endpoint/signing/real data/security changes cần phê duyệt riêng; giữ nguyên PDR invariants khi chưa có field evidence.
