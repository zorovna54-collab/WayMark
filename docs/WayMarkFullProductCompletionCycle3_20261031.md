# WayMark Full Product Completion — Cycle 3

Ngày: **31/10/2026 — Asia/Saigon**. Workspace: `D:\project\WayMark`.
Chiến lược: continuous code completion, deferred physical acceptance. Đây là code-level/internal debug RC, không phải production release hoặc chứng nhận định vị thực địa.

## A. Executive Summary

Cycle3 hoàn tất residual triage và sửa các lỗi có bằng chứng: stale logout confirmation, stale Studio navigation/capabilities, Home keyboard/semantics và Drawer overflow ở320px/text2. Không thêm feature hoặc thuật toán positioning.

**CODE-LEVEL FINAL RC READY — PHYSICAL ACCEPTANCE PENDING.** Full Flutter597 PASS /4 SKIP; full backend non-opt-in386 PASS; analyzer/format/build/signature đạt; emulator install/UI smoke PASS trong phạm vi H1. Không mở thêm cycle phát triển chỉ để polish hoặc tăng test count.

Full backend non-opt-in suite đã thực thi **386 PASS**, selected regression **171 PASS**. Một assertion metadata migration cũ được cập nhật theo các migration đã tồn tại; không chạy migration/SQL thật. Kết quả Flutter/build/APK/emulator chốt ở phần Quality Gates và H/K.

Final decision tại N áp dụng cho code-level MVP. Production signing, real Published endpoint/camera E2E, sensor/OEM và field accuracy vẫn tách riêng ở O.

## B. Residual P0/P1/P2 Triage

| Hạng mục | Phân loại cuối | Bằng chứng / xử lý |
|---|---|---|
| Confirmation Logout A có thể clear session B | FIXED AND REGRESSION TESTED /P1 | Red test thấy B bị clear; capture token+revision, reactive confirmation và guard trước clear |
| Drawer go() chờ beforeNavigate rồi mở onboarding profile A dưới B | FIXED AND REGRESSION TESTED /P1 | Deterministic Completer test; guard build revision trước/sau await |
| Drawer không phản ánh capability khi account đổi | FIXED AND REGRESSION TESTED /P1 | Red test vẫn thấy Creator action; ValueListenableBuilder cập nhật menu |
| Home avatar không có named/focusable control, search/nav dùng gesture-only | FIXED AND REGRESSION TESTED /P1 accessibility | Named IconButton + keyboard activation test; search InkWell, bottom nav TextButton |
| DrawerHeader tràn254px ở320×480/text2 | FIXED AND REGRESSION TESTED /P1 usability | Header theo intrinsic height trong ListView, không bỏ nhãn/cảnh báo |
| Explicit logout của chính phiên expired | FIXED AND REGRESSION TESTED | Không dùng active-private workflow gate cho local logout; vẫn cho xác nhận current expired session, không clear replacement |
| Full backend suite stale expected last migration | FIXED AND REGRESSION TESTED /test maintenance |385 PASS /1 FAIL trước sửa; giữ assert Publish tồn tại, thêm History và latest lifecycle metadata; full386 PASS sau sửa |
| Creator save/load/publish/QR owners, uncertainty/reconcile | IMPLEMENTATION COMPLETE trong phạm vi hiện tại | Cycle1/2 guards + regression; không viết lại |
| Published loader/image validation/version pin | IMPLEMENTATION COMPLETE | Existing malformed/image failure/immutable GUID/version tests chạy lại |
| Live fallback/lifecycle/arrival | IMPLEMENTATION COMPLETE cho MVP giới hạn | Replay/controller/UI regressions; no algorithm change |
| Emulator installation/UI gate Cycle2 | Xem H | Thử bounded với AVD read-only; không thay app để né lỗi môi trường |
| Heap/native memory profile | OPTIONAL /POST-RC | NOT MEASURED; không suy RAM từ PNG/RSS |
| Secure persistence/refresh/cross-restart recovery | OPTIONAL /POST-RC | Ngoài phạm vi; giữ recovery RAM và owner identity hiện tại |
| Trusted phone endpoint, production signing/deployment | EXTERNAL APPROVAL REQUIRED | Không tự cấu hình network/cert/key |
| Sensor accuracy/OEM/real camera Published | PHYSICAL ACCEPTANCE PENDING | Một campaign tổng thể theo checklist riêng |
| Background live/BLE/UWB/GPS/auto floor/auto arrival/new heading filters | OUT OF SCOPE | Không thêm để kéo dài completion |

Không còn P0/P1 nội bộ tái hiện được trong các case đã audit sau sửa. Đây không phải bảo đảm không còn bug ngoài phạm vi kiểm thử.

## C. Actual Code Changes

Chỉ tính delta so với **baseline Cycle3**, không coi toàn bộ dirty Git diff từ Sprint trước là đóng góp mới.

| File | Trước → Sau |
|---|---|
| waymark/lib/features/auth/logout.dart | Confirmation không pin session → token/revision guard và reactive dialog; replacement session không bị logout. Current expired session vẫn được explicit logout. Dialog scrollable, Escape/Cancel hoạt động |
| waymark/lib/features/admin/admin_page_shell.dart | Menu đọc profile một lần, go() không recheck sau await → lắng nghe AuthSession.changes, pin revision ở build, chặn stale navigation/Back; DrawerHeader fixed height → scroll cùng menu theo nội dung |
| waymark/lib/features/home/home_page.dart | Avatar/search/bottom nav gesture-only → named IconButton/InkWell/TextButton có keyboard focus/activation; giữ route và style chính |
| WayMark.Api.Tests/E2ESafetyTests.cs | Last migration expected ở Publish cũ → assert Publish + AddNavigationHistory có mặt, latest là ExtendNavigationHistoryLifecycle; giữ các assertion guard/history/model cũ |
| waymark/test/cycle3_stabilization_test.dart — mới |7 regression cases: expired logout, old logout replacement, pending drawer navigation, reactive capability, named keyboard avatar, narrow Drawer, Escape cancel |
| docs/WayMarkFinalAcceptanceChecklist20261031.md — mới | Bộ nghiệm thu A–J, tất cả human cases NOT TESTED |
| Báo cáo này — mới | Readiness matrix, release manifest, evidence và exit decision |

Không sửa AuthSession/service security contract, backend application source, DTO/QR/schema/migration, native sensor, dependencies/toolchain hoặc thuật toán tracking.

Red/green evidence: `residual-before.log` (4 failures thực tế), `accessibility-before.log` (Drawer overflow), `expired-logout-before.log` (regression phát hiện trong lượt hardening), `stabilization-final.log`, `auth-final-regression.log`.

Một lần semantics test lỗi do SemanticsHandle cần dispose trong test body; đã sửa harness bằng try/finally. Không đổi production chỉ để che lỗi harness.

## D. Core Product Integration Evidence

| Đường đi / invariant | Evidence tự động |
|---|---|
| Creator auth → personal workspace → image → directed GUID graph → Save/Reload | ProductCompletionCycle1Tests, PersonalMapOnboarding, MapDraftApi/Image suites; actual controllers/Identity/relational SQLite/temp managed files |
| QR tạo trên saved version → Publish → draft edit tách riêng → public resolver/image read | PublishedMap/PersonalQrPublishHotfix + combined scenario; QR được phép trong fixture riêng |
| Visitor → Search → Preview → Navigation → explicit Finish | published_map_test, qr_publish_hotfix, navigation_qr_flow và UI integration fixtures |
| History idempotency/terminal semantics/identity/restart/owner | NavigationHistory backend + sprint9/sprint10/history/cycle1-2 client regressions |
| Stable node/edge/floor GUID, directed edges, immutable Published pin | local_map_navigation, multifloor, published/live graph/readiness tests |
| Revoked/mismatched QR, failed/corrupt image, timeout/retry | loader/QR/error regressions; không thay bằng ảnh demo hoặc tự replay mutation |
| Owner switch /same-token new revision /late result /disposed UI | cycle1/cycle2/cycle3 suites; retained logout/menu được bổ sung trong Cycle3 |
| Public/manual fallback không cần login | anonymous Published + Navigation tests; không attach JWT vào public reader |

Đây là các tầng evidence phối hợp: unit/service/widget + backend HTTP/TestServer/SQLite. Không tuyên bố một Android camera app chạy xuyên real SQL Server chỉ vì fixtures cùng PASS. Không dùng QR/SQL/data người dùng.

## E. Live Tracking Final Integration

Không sửa PDR/stride/heading/matching/provider. Giữ movement budget40, chỉ step observations hợp lệ mới tạo displacement, confidence/source riêng với QR, không ép route, tự chọn tầng hoặc tự arrival.

| Case cần giữ | Regression có sẵn được chạy lại |
|---|---|
| Route replacement /late QR reply | live_guided_replay: atomic correction và fence sau replaceRoute |
| Background/resume /generation | live_tracking_controller, replay10 pause/resume cycles, sensor_session/controller lifecycle |
| Published version thay đổi | replay changed published version fences samples/alignment/anchors |
| Floor transition | explicit new-floor anchor; không nội suy hai ảnh |
| Detector unavailable /permission denied | native-provider codec/session fakes và guided/manual fallback UI |
| Heading stale | stop/no orientation → uncertain/hold, arrow stale checks |
| Budget32/40/41 | warning32, allow40, hold41, reset chỉ explicit anchor |
| Junction ambiguity | full graph ambiguity holds; destination route không quyết định vị trí |
| Return Manual | live_navigation_ui/published_live_integration/manual navigation semantics |
| Dispose giữa QR/request | late reply cannot overwrite pause/replacement/disposed session |
| Dot estimated chạm destination | replay estimatedRouteRemaining0 nhưng status không finished; History không auto completed |
| Diagnostics/export | bounded sanitized timeline/pilot tests; export chủ động, không upload |

Native StepDetector callback/phần cứng thật vẫn PHYSICAL ACCEPTANCE PENDING. Android bridge build/emulator capability không thay các phép đo thực địa.

## F. Accessibility Results

- Home avatar có semantic label/tooltip và button role, focusable; Tab rồi Enter mở Login khi guest.
- Home search surface có keyboard handling qua InkWell; bottom navigation dùng TextButton thay GestureDetector. Không thêm route mới.
- Logout modal có Cancel/Escape và không giữ action của session cũ. Expired current owner vẫn được chủ động logout.
- Studio drawer cập nhật capability, tên action cũ biến mất;320×480/text scale2 không overflow sau sửa.
- Chạy lại matrix Cycle2:8 trang ×3 viewport (320×640+keyboard240,390×844,640×360), text scale2; linked Publish dialog, Search/Preview/Navigation/guided Live.
- Icon Back/menu/options dùng tooltip hiện có; form fields dùng labels, confirmation/cancel và warnings vẫn giữ.

Không công bố TalkBack/OEM/screen-reader physical acceptance từ widget semantics. Không redesign hoặc bỏ các cảnh báo safety/estimated/manual. Những vấn đề cosmetics không tái hiện được không mở thành cycle mới.

## G. Backend Full / Selected Test Status

| Gate | Kết quả |
|---|---|
| Compile trước/sau test maintenance | PASS,0 warnings /0 errors |
| Selected gate giữ từ Cycle2 |171 PASS /0 FAIL /0 SKIP |
| Full non-opt-in lần đầu |385 PASS /1 FAIL: stale migration metadata assertion |
| Full non-opt-in sau sửa |**386 PASS /0 FAIL /0 SKIP** |
| SQL Server E2E opt-in thật | NOT RUN /EXTERNAL DEPENDENCY PENDING |
| SMTP/AI/external services thật | NOT RUN; suite dùng fakes/counters/isolated hosts |
| Windows Code Integrity | Không chặn các lần chạy hiện tại; không thay/bypass policy |

171 tests nằm trong386, không cộng thành557. No policy tricks/Unblock-File/rename/path changes.

Trước chạy full suite đã rà test host/config: SQLite `:memory:` hoặc file temp fixture, Identity InMemory/SQLite, fake SQL metadata connections cho safety checks, no real SqlConnection.Open/network SMTP/AI. Các test model `UseSqlServer()` chỉ kiểm EF metadata/scripts, không apply migration. Không dùng database thật thay fixture.

Lệnh:

~~~powershell
dotnet build WayMark.Api.Tests/WayMark.Api.Tests.csproj --no-restore
$cycle3SelectedFilter = 'FullyQualifiedName~ProductCompletionCycle1Tests|FullyQualifiedName~PersonalMapOnboardingTests|FullyQualifiedName~PersonalQrPublishHotfixTests|FullyQualifiedName~PublishedMapTests|FullyQualifiedName~NavigationHistoryTests|FullyQualifiedName~AdminAuthorizationTests|FullyQualifiedName~AccountSecuritySprint9Tests|FullyQualifiedName~MapDraftApiTests|FullyQualifiedName~MapDraftImageBoundaryTests|FullyQualifiedName~ManagedImageStorageTests'
dotnet test WayMark.Api.Tests/WayMark.Api.Tests.csproj --no-build --no-restore --filter $cycle3SelectedFilter
dotnet test WayMark.Api.Tests/WayMark.Api.Tests.csproj --no-build --no-restore
~~~

Lệnh trên giữ đúng selected filter của Cycle2; không có credential trong lệnh.

### Quality gates chốt

| Gate | Kết quả | Evidence trong full-product-cycle3-20261031 |
|---|---|---|
| Dart format |4 Dart files /0 changed,exit0 | format.log |
| Flutter analyze |No issues found,exit0 | analyze-final.log |
| Targeted integration checkpoint |138 PASS; các subset khác chồng lặp,không cộng | targeted-regression.log |
| Auth/stabilization cuối |23 PASS gồm7 regression mới | auth-final-regression.log |
| Full Flutter cuối |**597 PASS /4 SKIP /0 FAIL**,56s,exit0 | full-flutter-final.log |
| Backend build |0 warning /0 error,exit0 | backend-build-final.log |
| Selected backend |171 PASS /0 FAIL | backend-selected.log |
| Full backend non-opt-in |**386 PASS /0 FAIL /0 SKIP** | backend-full-final.log |
| git diff --check |PASS,exit0 | diff-check.log |
| Main build |PASS,assembleDebug11.9s,exit0 | android-main.log |
| Live Test build |PASS,assembleLiveTestDebug10.6s,exit0 | android-livetest.log |
| APK/signature |aapt/apksigner PASS,giữ signer cũ | release-manifest.json |

4 Flutter SKIP: live Vision opt-in, live SQL public navigation, P0 live SQL navigation và web-only routing branch trên VM. Benchmark tool1 PASS nằm ngoài full suite, không cộng vào597. Full run596 PASS trước bổ sung expired-logout regression là checkpoint lịch sử, không dùng thay kết quả cuối.

## H. Emulator Install / UI Smoke

Kết quả bounded emulator cuối được ghi ở H1. Bắt buộc phân biệt boot, Package Manager install Success và UI launch, không suy một gate từ gate khác.

Chỉ dùng AVD có sẵn, process overrides/read-only/software renderer; không wipe userdata, uninstall app hay sửa config AVD để vượt lỗi. Không chạy CPU-heavy test/build đồng thời trong phase smoke cuối.

### H1. Actual emulator acceptance

AVD có sẵn `Medium_Phone_API_37.0`, Google sdk_gphone64_x86_64 /API37, emulator-5580. Process flags: `-read-only -no-window -no-snapshot -gpu swiftshader -memory 3072 -cores 2 -no-audio -no-boot-anim`, camera emulated. Launcher chạy Hidden; không đổi file config AVD. Baseline không có device/listener5580/5581.

- **BOOT PASS:** ADB online, `sys.boot_completed=1`; emulator log ghi boot38,742ms, trong deadline240s. Host có khoảng10.3GiB RAM free trước boot; C còn khoảng74GiB và D khoảng167GiB. Guest trước install: `/data` available7,614,124KiB, MemAvailable2,905,340KiB. Đây là resource checks, không phải memory profile ứng dụng.
- **MAIN INSTALL PASS:** `adb install --no-streaming -r <Main Cycle3 APK>` exit0, Package Manager `Success`. File push đúng211,010,342 bytes.
- **LIVE TEST INSTALL PASS:** cùng lệnh cho LiveTest, exit0 và `Success`. Hai package khác nhau cùng tồn tại, không uninstall/wipe.
- **MAIN UI SMOKE PASS:** Login render; chọn Visitor theo bounds từ UI hierarchy, mở public QR entry không login; Back quay Login được xác minh qua XML. Không nhập QR hoặc gọi real backend.
- **LIVE TEST UI SMOKE PASS:** cold launch `Status: ok`; home có Sensor Probe/Local Pilot. Probe idle report permission denied, StepDetector unavailable, RotationVector available. Start → running, rotation registration=registered, buffer128/128, Detector events0. Stop → idle, registration=stopped. Back về LiveTest home và mở Local Pilot có nhãn sơ đồ tổng hợp; Back hoạt động.
- **LIMITATION /không che lỗi ban đầu:** Main cold `am start -W` lần đầu báo timeout, đồng thời Android hiện **System UI isn't responding**, không phải dialog ANR mang tên WayMark. Screenshot vẫn có Login phía sau. Chọn Wait đúng1 lần; sau đó UI dump/tap hoạt động. Main hot relaunch `Status: ok`,819ms. Sensor Probe có1 lần UI dump null root trong transition, retry1 lần thành công. Không đổi source để che lỗi máy ảo, không gọi cold-start latency PASS.
- **NOT VERIFIED:** camera→real Published endpoint, Creator native file flow đầy đủ, real StepDetector/phone accuracy, TalkBack/OEM. Emulator sensor không thay hardware acceptance.

Evidence: `main-install.log`, `livetest-install.log`, `main-launch.log`, `main-relaunch.log`, `livetest-launch.log`, `main-ready.xml/png`, `main-public.xml`, `main-back.xml`, `livetest-home.xml`, `probe-idle.xml`, `probe-running.xml`, `probe-stopped.xml`, `livetest-back.xml`, `local-pilot.xml/png`, emulator resource/start logs.

PowerShell có ghi NativeCommandError cho progress stderr của adb push; kết quả install dựa trên **exit0 +Package Manager Success**, không dựa vào loại hiển thị stderr đó.

**Cleanup PASS:** Stop sensors trước Back; force-stop đúng hai package trên emulator thuộc nhiệm vụ rồi `adb -s emulator-5580 emu kill`. Kiểm sau:0 devices,0 process QEMU đúng AVD/port của nhiệm vụ,0 listener5580/5581. Giữ ADB server chung, không kill .NET/process khác. Không cài app trên điện thoại. Không tuyên bố toàn bộ ignored AVD/cache giữ nguyên hash.

## I. Performance / Memory Results

Rerun `tool/published_pilot_benchmark_test.dart`, synthetic Sprint7 fixtures. Windows Flutter test desktop, MockClient,1 warmup +3 measured iterations; median ms:

| Fixture | Floors /nodes /edges | JSON | Project +image validation | Navigation clone | Tracking graph clone | Readiness input | Validator |
|---|---|---:|---:|---:|---:|---:|---:|
| Small |1 /20 /38 |0.105 |5.147 |5.359 |3.663 |0.677 |0.308 |
| Medium |4 /400 /798 |1.252 |69.154 |76.065 |42.044 |9.665 |4.341 |
| Large |8 /1600 /3198 |8.267 |293.629 |386.800 |199.216 |46.835 |8.623 |

Ảnh256×128 /1024×512 /2048×1024, snapshot15,549 /313,381 /1,255,209 bytes. Số image GET qua4 fresh loads =4 /16 /32; encoded byte counts là kích thước fixture, không phải RAM.

Source audit: FloorPlanAsset.validate kiểm dimensions trước decode, dispose frame/codec trong finally; FloorPlanCanvas release ImageInfo/transform/listeners theo lifecycle; FloorRouteMap cache graph futures theo route/API/map; controller close cancels freshness timer/subscription, closes sensor session, disposes notifier. Existing dispose/pan/zoom/cache regression chạy lại.

**Heap/native image RAM: NOT MEASURED.** Chưa có profiler/GC-isolated peak hoặc retained heap đáng tin cậy. Host free memory dùng quyết định resource emulator, không dùng làm RAM map. C2 image/decode/controller timing là historical reference, không đổi thành phép đo mới của Cycle3.

Không tối ưu clone/cache khi chưa có bottleneck đáng tin cậy; timing khác Cycle2 không được gọi là improvement/regression có nguyên nhân vì môi trường/JIT/load chưa kiểm soát đồng nhất. Không thay validation/version pin hoặc scene transform để tăng benchmark.

## J. Final Release Readiness Matrix

F = full Flutter gate hiện tại; B = full386 non-opt-in backend; E = emulator evidence H1. CODE COMPLETE chỉ cho MVP đã thống nhất, không phải mọi feature tưởng tượng.

| Tính năng | Code /automated evidence | Integration /runtime evidence | Gate còn lại |
|---|---|---|---|
| Authentication /logout /recovery | CODE COMPLETE; F incl stale/current-expired logout | B Identity/policy; E startup theo H1 | real phone session UX PENDING |
| Creator workspace | CODE COMPLETE; F onboarding/owner | ISOLATED INTEGRATION PASS B | real API/SQL accepted workspace |
| Builder Node/Edge | CODE COMPLETE; F GUID/directed/metres/edit | isolated save/reload B | phone native/edit acceptance |
| Save/Reload | CODE COMPLETE; F uncertainty/version conflict | B persistence/restart | real runtime identity/storage |
| Import/Export/recovery | CODE COMPLETE trong scope RAM/local hiện có; F SAF mocks | E không thay native file acceptance | physical SAF/persistence PENDING |
| Publish/QR | CODE COMPLETE; F revoke/mismatch/pin | B fixture publish/resolver | authorized real QR/Pub read |
| Published images | CODE COMPLETE; F validate/failure | B image integrity/hash | real SQL/storage/TLS GET |
| Visitor public entry | CODE COMPLETE; F anonymous/no JWT | E Guest theo H1; B public fixture | camera real endpoint PENDING |
| Search/Preview | CODE COMPLETE; F route/zoom | widget fixture integration | physical map correctness |
| Navigation /History | CODE COMPLETE; F explicit finish/identity | B completed history/pin restart | phone whole journey PENDING |
| Multifloor | CODE COMPLETE explicit links/confirmation; F | B graph fixtures | actual floor transitions PENDING |
| Live Tracking | CODE COMPLETE limited MVP; F replay/controller | E probe/entry theo H1, không real sensors | PHYSICAL ACCEPTANCE PENDING |
| QR correction | CODE COMPLETE; F atomic/fencing | fixture integration PASS | real QR timing/accuracy PENDING |
| Manual fallback | CODE COMPLETE; F unavailable/uncertain/guest | widget integration PASS | physical usability PENDING |
| AI Assistant | CODE COMPLETE review/apply flow; F mock/timeout/cancel | external provider NOT TESTED | EXTERNAL DEPENDENCY PENDING |
| Settings/Profile | CODE COMPLETE; F API/errors/owner | B account/profile fixture | physical/SMTP delivery PENDING |
| Security/Authorization | scoped session/roles CODE COMPLETE; F/B | ISOLATED INTEGRATION PASS | không security certification toàn sản phẩm |
| Performance | baseline đo desktop; no unsupported optimization | memory NOT MEASURED | phone profiling OPTIONAL/POST-RC |
| Accessibility | targeted keyboard/semantics/layout AUTOMATED PASS | E không TalkBack certification | phone reader sweep PENDING |
| Android Main/Live packages | build +metadata +signer gate K | E install/UI H1 | PRODUCTION SIGNING PENDING |
| Physical positioning /real E2E | Không nghiệm thu từ test code | NOT VERIFIED | PHYSICAL ACCEPTANCE PENDING |

## K. Main / Live APK Metadata

Hai artifacts mới tại `D:\project\WayMark\waymark\build\product-completion-artifacts`, không ghi đè Cycle1/2:

- `WayMark-Main-Cycle3-20261031-internal-debug.apk`.
- `WayMark-Live-Test-Cycle3-20261031-internal-debug.apk`.

Exact metadata/hash/signature/size ở K1, manifest JSON trong evidence directory. Giữ `com.example.waymark`, `com.example.waymark.livetest`, existing Android Debug signer, version1.0.0/code1. Không production signing/upload/store release.

Build commands (tại waymark):

~~~powershell
flutter build apk --debug --no-pub
flutter build apk --debug --no-pub --flavor liveTest --target tool/live_test_main.dart --dart-define=WAYMARK_LIVE_TEST=true
~~~

Cùng package/key/version cho phép internal update bằng `adb install -r` khi Android cho phép; không uninstall/data wipe để né signature mismatch. App ký bằng key khác không được bảo đảm tương thích.

### K1. Release manifest

| Thuộc tính | Main | Live Test |
|---|---|---|
| File |WayMark-Main-Cycle3-20261031-internal-debug.apk |WayMark-Live-Test-Cycle3-20261031-internal-debug.apk |
| Package |com.example.waymark |com.example.waymark.livetest |
| Label |waymark |WayMark Live Test |
| Version /code |1.0.0 /1 |1.0.0 /1 |
| Min /target /compile SDK |24 /36 /36 |24 /36 /36 |
| ABI |arm64-v8a,armeabi-v7a,x86_64 |arm64-v8a,armeabi-v7a,x86_64 |
| Size bytes |211,010,342 |187,770,181 |
| SHA256 |CADA53AF3B82F586C31B115FF6714CCF03F46D706B4C18C6F0FA3D71376031AB |2A7E8B75F461D2888974420C5A473D96ACAF31DC3B2B863538D6C42ED9389CB4 |

Cả hai `apksigner verify --print-certs` exit0, signer Android Debug SHA256 `8c15d5eb313223a87d82ef435a13307e74f8abf1a9da2e9dd8de9c21b0cf4df2`, khớp các internal build cũ. Không gọi production-signed. Exact absolute paths/metadata trong `waymark/build/full-product-cycle3-20261031/release-manifest.json`.

## L. Security / Data Preservation

Baseline Cycle3: **533 files /391 Git entries =44 modified +347 untracked**, branch `auth-jwt-assignment`,0 staged. Hash cả4 named APK Cycle1/2. Baseline lưu disk trong `waymark/build/full-product-cycle3-20261031/baseline.json`.

Không reset/clean/stage/commit/push/đổi branch; không real SQL write/migration/seed/grant/DDL, không lấy QR token thật từ source/log/SQL, không sửa auth policy/JWT/certificate trust/TLS/network/firewall/DNS/CORS/tunnel/dependency/signing key. Backend tests chỉ ghi isolated fixtures được phép. Không khởi động API thật hoặc publish/revoke data người dùng.

Ignored build/cache/AVD process outputs có thể đổi theo test/build; không dùng source hashes để chứng nhận mọi byte ignored user storage. Không có thao tác cài app/xóa dữ liệu trên điện thoại.

Final invariant count và artifact preservation ở L1. Không quy file dirty có sẵn thành thay đổi mới.

### L1. Source/Git integrity cuối

**536 files /394 entries =44 modified +350 untracked**,0 staged,branch vẫn `auth-jwt-assignment`. So baseline533 files: **529 giữ nguyên SHA256,4 file cũ đổi hash đúng C,0 file mất**, thêm3 file mới đúng C. Bốn APK named Cycle1/2 đều giữ nguyên hash. Tracking/PDR/provider/graph/Published schema/auth policies/cấu hình nhạy cảm không đổi hash. Không claim ignored caches không đổi; build và test có generated outputs hợp lệ.

## M. Final Acceptance Checklist

Tài liệu riêng: `docs/WayMarkFinalAcceptanceChecklist20261031.md`, các nhóm độc lập A–J:

A cài Main/Live; B Creator/Builder/save; C Publish/QR; D Guest/camera/Navigation; E Sensor Probe/Local Pilot/live; F QR correction/floor/budget; G History/account/recovery; H AI/Settings/network/accessibility; I ground truth steps/distance/error; J bug/screenshot/diagnostics.

Mỗi nhóm có Preconditions/Steps/Expected/Result/Evidence, tất cả human cases **NOT TESTED**. Phân biệt Local Pilot không cần API với Published cần API/SQL/ảnh/authorized QR và Android-trusted HTTPS. Hạ tầng cần phê duyệt riêng; không bypass TLS.

Không yêu cầu thử điện thoại trong Cycle3. Chuyển checklist cho **một Final Acceptance Campaign tổng thể**, không tạo cycle mới chỉ để polish/test count.

## N. Go / No-Go for Code-Level Final RC

Quyết định chốt sau gate cuối ở N1. Scope là code-level/internal debug MVP. Không dùng quyết định này làm production, hospital safety/accessibility hoặc positioning accuracy claim.

### N1. Final decision

**CODE-LEVEL FINAL RC READY — PHYSICAL ACCEPTANCE PENDING.**

| Exit criterion | Kết quả |
|---|---|
| Không còn P0/P1 nội bộ đã biết/tái hiện trong scope chưa sửa | PASS: các lỗi triage đã sửa và có regression; không khẳng định hết mọi bug |
| Full Flutter/analyzer/format | PASS:597 /4 skip; analyzer sạch,format0 change |
| Backend regression/full non-opt-in | PASS:171 selected nằm trong386 full |
| Main/Live builds +identity/signature | PASS,K1 |
| Identity/QR/History/live fallback | AUTOMATED /ISOLATED INTEGRATION PASS,D/E |
| Emulator smoke khả dụng | PASS trong phạm vi H1; transient System UI/cold timeout được giữ evidence |
| Bảo toàn dữ liệu/source/APK cũ | PASS trong phạm vi hash/operations,L1 |
| Manifest/checklist và external gates | Có K1 +release-manifest.json +checklist A–J; human cases NOT TESTED |

Đề xuất kết thúc code-level completion và chuyển sang **Final Acceptance Campaign tổng thể** bằng checklist đã tạo. Không đề xuất Cycle4 chỉ để polish/test count. Nếu campaign phát hiện bug mới, mở nhiệm vụ sửa giới hạn theo evidence.

Đây **không phải PRODUCTION READY**: production signing/deployment, real backend/phone/camera và field accuracy phải đóng riêng theo O. Không yêu cầu người dùng thử thiết bị ngay trong phiên này.

## O. Remaining External / Physical Gates

| Gate | Trạng thái /cách đóng sau này |
|---|---|
| Real Published resolver/snapshot/image | Authorized QR + đúng runtime SQL/storage identity; TLS mặc định. Không tự lấy token |
| Android endpoint trust/network | EXTERNAL APPROVAL REQUIRED trước cấu hình; localhost trust PC không tự sang phone |
| Production signing/deployment | PRODUCTION SIGNING PENDING; key/config do owner phê duyệt |
| Sensor/OEM lifecycle | Physical model/API/capability, permission/deny/revoke,10 lifecycle cycles, real events |
| Positioning accuracy | Corridor đo thật, truth steps, bias/false steps/heading/stride/correction, giữ lượt lỗi |
| Real camera Published E2E | Phone camera→reachable approved endpoint→same pinned map/images→explicit finish/history |
| Real SMTP/AI provider | Được phép cấu hình/delivery/budget; không giả fixture thành runtime PASS |
| Phone memory/battery/TalkBack | PHYSICAL ACCEPTANCE PENDING hoặc OPTIONAL/POST-RC theo phạm vi nghiệm thu |
| Cross-restart secure persistence/refresh, unknown guest draft transfer | OPTIONAL/POST-RC; không tự thêm contract/storage |
| Emulator cold-start/System UI stability | Smoke chức năng đã PASS sau bounded recovery; transient System UI ANR/cold timeout không được dùng làm phone latency benchmark |

Không mở thêm chu kỳ phát triển nếu N1 đạt và chỉ còn các gate external/physical/optional này.
