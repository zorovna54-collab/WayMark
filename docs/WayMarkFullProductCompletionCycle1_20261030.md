# WayMark Full Product Completion — Cycle 1

Ngày: **30/10/2026 — Asia/Saigon**. Workspace: `D:\project\WayMark`.
Phạm vi: integration audit, sửa lỗi core có bằng chứng, kiểm thử và hai APK nội bộ. Không phải nghiệm thu production hoặc định vị thực địa.

## A. Executive Summary

**Cycle 1 đã hoàn tất phần code hardening và đóng gói INTERNAL RELEASE CANDIDATE. CONDITIONAL GO cho Cycle 2; chưa PRODUCTION READY.**

- Full Flutter: **549 PASS / 4 SKIP / 0 FAIL**; analyzer không có issue.
- Backend API/test project **build PASS, 0 warning / 0 error**. Backend HTTP/SQLite integration mới **BLOCKED khi nạp assembly bởi Windows Application Control; 0 test được thực thi**.
- Hai APK Main và Live Test build PASS, metadata/package/chữ ký đã kiểm tra. Cả hai dùng **Android Debug** key hiện có, không phải production signing.
- Đã sửa account/session races, History resume ghi nhầm owner, private response stale, cached profile/map rows và Login overflow. Không thay thuật toán PDR hoặc budget 40 observations.
- Published QR thật, SQL Server E2E, endpoint HTTPS tin cậy trên Android và physical positioning accuracy vẫn chưa có bằng chứng mới. Không yêu cầu người dùng kiểm thử điện thoại giữa checkpoint.

Quy ước: COMPLETE là đã có implementation cho phạm vi mô tả; PARTIAL còn thiếu tích hợp/chính sách; BUG là lỗi tái hiện; UNVERIFIED là chưa có runtime evidence cần thiết; MISSING là chưa có code; OUT_OF_SCOPE là hoãn rõ ràng. COMPLETE không tự đồng nghĩa PRODUCTION READY.

## B. Full Product Feature Inventory / Release Readiness Matrix

Audit đối chiếu source hiện tại, không chỉ báo cáo cũ: index 159 file source (99 Flutter lib, 60 API; không tính migrations/generated/config secrets). Đọc trực tiếp các đường đi auth, personal workspace, Builder, services, public snapshot, navigation, tracking, AI và tests liên quan. Không tìm thấy TODO/UnimplementedError hoặc callback nút rỗng trong lib qua tìm kiếm; đây không phải bằng chứng mọi tương tác đều runtime PASS.

Trong bảng: **F** = Flutter automated suite hiện tại; **B** = backend fixture đã compile nhưng execution BLOCKED. Runtime PC HTTPS là bằng chứng lịch sử trong báo cáo HTTPS, không phải Published data PASS của Cycle 1.

| Tính năng | Implementation | Automated / integration evidence | Runtime / physical | Remaining / severity / recommendation |
|---|---|---|---|---|
| Authentication register/login/logout | COMPLETE; races BUG→fixed | F session/latest intent/dispose tests; B Identity flow | APK build; real auth server mới chưa thử | P1 expiry UX liên màn hình còn PARTIAL; AUTOMATED PASS trong phạm vi F |
| JWT/session expiration | PARTIAL; session trong RAM, không refresh/persist token | F owner revision và same-token ABA rejection | Không có phiên expired trên Android thật | P1 thống nhất expired-session routing; secure persistence chỉ khi chốt scope |
| Forgot Password | COMPLETE về request/UI; delivery UNVERIFIED | F password reset smoke; backend source | SMTP thực chưa thử | P1 external SMTP/delivery gate |
| Creator Workspace | COMPLETE | F self-service/owner UI; B create owned workspace | Không tạo dữ liệu thật | EXTERNAL DEPENDENCY BLOCKED ở backend runtime |
| Map Builder Node/Edge | COMPLETE | F directed/metres/GUID/editor tests | APK compile; thao tác toàn bộ trên thiết bị chưa nghiệm thu | P2 full accessibility sweep |
| Multiple floors / links | COMPLETE topology + manual transitions | F multifloor/navigation/geometry | Không kiểm chuyển tầng vật lý | P1 PHYSICAL ACCEPTANCE PENDING; không auto floor inference |
| Save/Reload | COMPLETE; stale save BUG→fixed | F version/conflict/uncertain session response; B reload GUID | SQL Server runtime chưa thử | P1 request cũ có thể đã commit; giữ uncertain, không retry mù |
| Import/Export/recovery | COMPLETE | F draft/SAF mocks, recovery owner identity regression | SAF phone smoke mới chưa thử | P1 native I/O acceptance pending |
| Draft/Published separation | COMPLETE | F immutable copy/version pin; B edit after publish/restart | Chưa đọc Published thật trong cycle | P1 external persistence gate |
| Publish/QR/revoke | COMPLETE contract | F parser/revoke/mismatch; B fixture QR/publish | AUTHORIZED_QR_NOT_AVAILABLE | P1 thực thi fixture khi policy cho phép; không lấy QR từ SQL |
| Visitor Public Map/images | COMPLETE | F anonymous/pinned image/malformed/error cases; B image hash | PC weatherforecast cũ PASS không chứng minh dữ liệu | P1 real SQL/image identity + QR read pending |
| Search destination | COMPLETE | F room/node/start pin | Backend Published camera flow chưa thử | CODE COMPLETE / AUTOMATED PASS |
| Route Preview | COMPLETE | F directed local route/preview | Không đo correctness geometry hiện trường | P1 map-authoring geometry verification |
| Navigation / Finish | COMPLETE checklist semantics | F Published/QR/manual/reroute/explicit finish | Không có phone Published E2E | AUTOMATED PASS; completion không phải sensor verified arrival |
| History | COMPLETE; owner race BUG→fixed | F history persistence client/session tests; B completed history restart | SQL persistence fixture chưa chạy | P0 fixed regression; P1 actual backend execution blocked |
| Live Tracking / PDR | COMPLETE cho MVP giới hạn | F deterministic replay/budget/uncertainty/lifecycle | APK build; physical accuracy UNVERIFIED | PHYSICAL ACCEPTANCE PENDING; không production navigation claim |
| Calibration / junction / guided setup | COMPLETE cho điều kiện v1 | F setup/calibration/junction gates | Phone travel direction/stride chưa nghiệm thu | P1 điều kiện cầm máy và heading cần campaign thực địa |
| QR correction | COMPLETE same pinned context | F stale correction/reset/pause/version/floor tests | QR thật chưa thử | P1 Published phone integration pending |
| BlueDot / zoom/pan | COMPLETE constrained overlay | F floor geometry/zoom/render tests | Chưa đo phone frame/memory | P2 profile trước tối ưu |
| Manual / QR fallback | COMPLETE | F tracking unavailable/uncertain/manual semantics | Không cần live để dùng checklist; phone mới pending | AUTOMATED PASS; không ép estimate thành verified |
| Readiness / diagnostics / pilot toolkit | COMPLETE cho toolkit | F blocked graph/endpoint/redaction/export/handoff | Live Test APK build | P1 field evidence pending; diagnostic export opt-in |
| AI Assistant | COMPLETE review flow; provider runtime UNVERIFIED | F timeout/cancel/review/edit/apply/failure; live Vision skipped | Không gọi API trả phí/thật | P1 external config/provider gate; không auto publish |
| Settings/Profile | COMPLETE; private cache BUG→fixed | F account switch/profile/settings/layout cases | APK build | P2 màn hình khác cần accessibility sweep |
| Loading/Error/Cancel/Retry | PARTIAL toàn sản phẩm, core đã harden | F stale response + cancel + error regressions | Không chứng minh mọi network/OEM condition | P1 retained cloud workflow owner policy ở Cycle 2 |
| Security/Authorization | COMPLETE server checks được đọc; không security certification | F private response isolation/public no auth; B cross-owner HTTP | B runtime BLOCKED | P1 backend execution + expiry policy gate |
| Performance | PARTIAL đo lường | Existing graph budget/repaint tests; benchmark Sprint 7 là lịch sử | Chưa có phone benchmark mới | P2 image decode/cache/clone profiling; không tuyên bố nhanh hơn |
| Android installation | Build/signature COMPLETE; UI smoke xem H | Hai APK metadata + signer verified | Emulator không thay phone acceptance | P1 production signing/config chưa có |
| Device Sensors | Native implementation COMPLETE | F channel/fake/controller/lifecycle | Emulator không chứng minh sensor điện thoại | PHYSICAL ACCEPTANCE PENDING |
| Physical positioning accuracy | UNVERIFIED | Replay là correctness test, không metric accuracy | Chưa có ground truth campaign | P1 field gate; không công bố sai số mét |
| Secure persistent login/refresh | MISSING | Không thêm trong cycle | Không có runtime claim | P2 tùy chốt yêu cầu sản phẩm |
| Background live, BLE/UWB, auto floor/polyline migration | OUT_OF_SCOPE | Không triển khai | Không claim | Công việc riêng, cần thiết kế/evidence |

## C. P0/P1/P2 Backlog

| ID | Mức / trạng thái | Bằng chứng và xử lý |
|---|---|---|
| C1-01 | P0 FIXED | History resume account A nhận public map sau khi chuyển B có thể gọi record bằng B. Deterministic red test xác nhận 1 write thay vì 0; nay owner/revision được giữ xuyên confirmation→load→record/navigation. |
| C1-02 | P0 FIXED | Response private cũ có thể được áp dụng sau logout/switch hoặc cùng token được tái dùng. Guard token + revision ở private services; clear cached identity khi token thay. |
| C1-03 | P1 FIXED | Login response cũ/sau dispose có thể đăng nhập lại. Latest intent + owned cancellation + session revision; atomic establish. |
| C1-04 | P1 FIXED | MyMaps/Profile/Settings còn hiển thị metadata owner cũ. Listen auth changes, clear và generation guard reload. |
| C1-05 | P1 FIXED | Save đã gửi trước account change không được xem như chắc chắn chưa ghi. auth_session_changed được phân loại uncertain; không tự gửi lại. |
| C1-06 | P1 FIXED | Login 320px/text scale 2/keyboard overflow: Row tràn ngang 604px, Column tràn dưới 228px trong red tests. Scroll toàn nội dung + Wrap; nút Guest vẫn truy cập được. |
| C1-07 | P1 BLOCKED | Windows Code Integrity chặn WayMark.Api.Tests.dll. Cần chủ môi trường xử lý theo chính sách được duyệt trước backend test execution; không bypass. |
| C1-08 | P1 OPEN | Thống nhất owner pinning cho retained Creator cloud dialogs và route/session-expiry UX mà không làm mất draft. Không coi guard service hiện tại là chứng minh toàn bộ workflow an toàn. Cycle 2 kiểm bằng regression trước sửa. |
| C1-09 | P1 EXTERNAL | Real SQL/image storage read, authorized Published QR, Android trusted endpoint, SMTP delivery còn chưa verified. Không tự tạo dữ liệu/network/trust mới. |
| C1-10 | P1 EXTERNAL | Production signing và deployment config chưa có; APK hiện tại chỉ internal debug RC. |
| C1-11 | P1 PHYSICAL PENDING | Sensor/OEM lifecycle, travel heading, stride, false steps, geometry và accuracy. Hoãn đến đợt acceptance tổng thể; không chặn code độc lập. |
| C1-12 | P2 OPEN | Accessibility toàn màn hình, secure session persistence nếu cần, profile image memory/cache theo đo lường. Không tối ưu khi chưa có benchmark. |

Không phát hiện P0 còn tái hiện trong phạm vi regression đã sửa. Đây không phải tuyên bố không còn P0 toàn sản phẩm.

## D. Các phần code đã hoàn thiện

### File đã tồn tại, đổi hash so với baseline Cycle 1

| File dưới waymark/ | Trước → Sau |
|---|---|
| lib/services/auth_session.dart | Token/name cập nhật rời rạc → atomic establish, revision, token đổi xóa profile/name; clear luôn invalidates pending work. |
| lib/services/auth_api_service.dart | Login/profile response có thể stale → latest login intent, dispose cancellation, owner revision validation. |
| lib/services/published_map_api_service.dart | Private response không gắn session generation → reject stale private response; public guest read vẫn anonymous. |
| lib/services/map_draft_api_service.dart | Stale private result có thể accepted → session guard; stale mutation response giữ uncertain. |
| lib/services/navigation_history_service.dart | Owner chỉ token → token + revision ở request/delete/history session. |
| lib/features/admin/my_maps_page.dart | Cached private rows qua account switch → clear/reload + operation generation và decode guards. |
| lib/features/admin/settings_page.dart | Profile/connection cũ có thể giữ → auth listener/reset/async owner guards/cleanup. |
| lib/features/profile/profile_page.dart | Profile/name cũ có thể giữ → owner-scoped load/save và cleanup. |
| lib/features/history/history_page.dart | Resume qua account switch có thể ghi/navigate sai owner → capture owner trước dialog, guard mọi await và record sau validate. |
| lib/features/auth/login/login_page.dart | Late login/dispose, overflow → injected owned API cancellation, scroll/Wrap và busy guards. |
| test/p0_builder_state_test.dart | Fixture gán name trước token → dùng atomic establish; assertions recovery giữ nguyên. |
| test/published_live_integration_test.dart | Native decode polling 15×Duration.zero dễ timeout khi chạy suite → bounded wait 40×10ms dừng khi blocked UI xuất hiện; giữ assertions không tạo sensor. |

### File mới

- `waymark/test/cycle1_session_isolation_test.dart`: 15 regression tests về stale login/private response/UI/history/recovery identity.
- `waymark/test/cycle1_accessibility_layout_test.dart`: 2 tests Login 320×640, text scale 2, có/không keyboard; Guest action vẫn hoạt động.
- `WayMark.Api.Tests/ProductCompletionCycle1Tests.cs`: isolated HTTP/Identity/SQLite/image/restart scenario, đã compile nhưng chưa thực thi.
- Báo cáo này.

Không sửa backend application source, schema/contracts, Gradle, Manifest, dependency, native sensor, navigation algorithm hoặc APK cũ trong cycle này.

## E. Các luồng nghiệp vụ đã kiểm thử

1. **Flutter unit/service/widget integration — PASS:** account A→logout/B→late responses bị loại; same token với revision khác cũng bị loại; public load không mang Authorization và không bị ép thành private.
2. **History resume race — PASS:** trong lúc A resume, đổi B rồi public map response về; không ghi History dưới B, không mở hành trình cũ.
3. **Login UX — PASS:** keyboard/text scaling không overflow; cuộn đến Guest và mở public entry. Login disposal không âm thầm đăng nhập.
4. **Existing fixture integration — PASS trong F suite:** QR parser/resolve bằng fake HTTP→pinned map/image→Search→Preview→Navigation→manual/QR confirmation→Finish; multifloor, history client, graph/readiness/live fallback giữ semantics. Widget camera/HTTP fixtures không phải camera APK E2E.
5. **New backend HTTP/SQLite scenario — COMPILED, BLOCKED:** register/login→personal workspace→upload fixture image→save/reload GUID graph→tạo fixture QR trước Publish theo contract thực tế→publish v2→private edit v3→anonymous resolve đúng v2/image SHA→visitor history Completed→restart same isolated database→history/pin tồn tại→other owner bị từ chối. Không có assertion nào được chạy vì assembly load bị chặn.
6. **SQL Server E2E / real Published / phone camera E2E — NOT VERIFIED.** Không lấy token thật từ repository/SQL/log, không seed/publish/revoke dữ liệu người dùng.

## F. Architecture / Integration Issues

State hiện tại chủ yếu StatefulWidget/setState, Navigator và ValueNotifier. Cycle này thêm revision tại AuthSession để xử lý ABA (logout rồi cùng token trở lại), không thêm state framework/dependency.

Private network response được kiểm lại trước parse/accept. Guard client không hủy hoặc rollback transaction đã được server nhận: save cũ có thể đã ghi thành công, vì vậy trạng thái uncertain bắt buộc reload/reconcile trước retry. Server vẫn chịu trách nhiệm authorization.

History không được dùng public loading thành công làm bằng chứng owner còn hợp lệ. Các side effect và navigation phải kiểm cùng owner/revision với lúc người dùng bắt đầu thao tác.

Live pipeline và các invariant giữ nguyên: stable map/version/floor/node/edge; không timer movement, không ép route, không auto floor, không auto arrival, không đổi budget40 hoặc heading heuristic. Production không được thay bằng FakeProvider; fake chỉ cho test/debug có nhãn, Local Pilot vẫn là synthetic map có chủ đích.

Còn PARTIAL: central session expiry routing và retained cloud workflow ownership. Cần policy đóng/giữ màn hình nháp rõ ràng thay vì tự pop và mất draft. Cần kiểm memory/latency bằng đo lường trước đổi cache/clone; không có performance claim mới ở Cycle 1.

## G. Flutter / Backend Test Results

Evidence local (ignored): `waymark/build/full-product-cycle1-20261030/`.

| Gate | Kết quả thực tế | Evidence |
|---|---|---|
| Flutter targeted đầu | 79 PASS | targeted-tests.log |
| Integrated regression | 120 PASS | integrated-regression.log |
| Recovery/preflight follow-up | 34 PASS | recovery-and-preflight-regression.log |
| Analyzer cuối | No issues found | analyze.log |
| Full Flutter cuối | **549 PASS /4 SKIP /0 FAIL**, exit0, khoảng2 phút | full-flutter-tests-final.log |
| Backend build | **PASS /0 warning /0 error** | backend-build.log |
| Backend new integration execution | **BLOCKED /0 executed** | backend-core-integration.log, TRX |
| Main Android build | PASS | android-main-build-v2.log |
| Live Test Android build | PASS | android-livetest-build.log |

Các targeted counts chồng lặp, không cộng thành tổng test độc lập.

Full suite đầu có 3 fail: 2 fixture recovery khởi tạo username trước token (đã đổi sang atomic establish); 1 async native decode polling quá ngắn dưới suite load (đã dùng bounded wait). Giữ log `full-flutter-tests.log`; không che lần fail. Full suite cuối chạy sau tất cả sửa đổi và pass.

4 SKIP: live AI Vision opt-in, live SQL public navigation, P0 live SQL navigation (thiếu opt-in/state), web-only routing branch trên Dart VM. Không chuyển skip thành PASS.

Backend: `FileLoadException` với `0x800711C7` khi nạp `WayMark.Api.Tests.dll`; Windows CodeIntegrity events 3077/3033 corroborate policy block. Không phải assertion failure hoặc bằng chứng SQL lỗi. Không tắt policy, không Unblock-File, đổi runner/path/signing để vượt block; full backend suite chưa chạy được trên host này.

Lệnh chính đã dùng (không bao gồm cấu hình nhạy cảm):

~~~powershell
# tại waymark/
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
flutter build apk --debug --no-pub --flavor liveTest --target tool/live_test_main.dart --dart-define=WAYMARK_LIVE_TEST=true
# tại workspace/
dotnet build WayMark.Api.Tests/WayMark.Api.Tests.csproj --no-restore
dotnet test WayMark.Api.Tests/WayMark.Api.Tests.csproj --no-restore --filter FullyQualifiedName~ProductCompletionCycle1Tests
~~~

## H. Android Builds và APK metadata

Hai APK mới ở `waymark/build/product-completion-artifacts/`, không ghi đè các APK đã đặt tên của Sprint trước.

| Metadata | Main | Live Test |
|---|---|---|
| File | WayMark-Main-Cycle1-20261030-internal-debug.apk | WayMark-Live-Test-Cycle1-20261030-internal-debug.apk |
| Package | com.example.waymark | com.example.waymark.livetest |
| Label | waymark | WayMark Live Test |
| Version / code | 1.0.0 /1 | 1.0.0 /1 |
| min /target /compile SDK | 24 /36 /36 | 24 /36 /36 |
| ABI | arm64-v8a, armeabi-v7a, x86_64 | arm64-v8a, armeabi-v7a, x86_64 |
| Signing | Existing Android Debug key | Same existing Android Debug key |
| SHA256 APK | 1A82CF05D3C0BCFBEFC1D9E1B4DE37B9B38CC7C709A077F7E78508813E479C54 | 9DFD44B6D59EAF16C6A543818D66234B300B7EEB3C2DA9EADCCAD3A897F9A855 |

`aapt dump badging` xác nhận metadata; `apksigner verify --print-certs` exit0 cả hai. Signer SHA256: `8c15d5eb313223a87d82ef435a13307e74f8abf1a9da2e9dd8de9c21b0cf4df2`. Không tạo key, đổi application ID hoặc signing config. Release Gradle hiện dùng debug signing, nên không gọi production-signed.

Emulator smoke và cleanup: xem phụ lục H1 được ghi sau khi kết thúc thao tác runtime. Không dùng emulator sensor làm bằng chứng step/heading thật.

### H1. Emulator smoke thực tế

AVD có sẵn `Medium_Phone_API_37.0`, Google sdk_gphone64_x86_64 /API37, chạy headless tại emulator-5580 với `-read-only -no-snapshot-load -no-snapshot-save`. Lần đầu default renderer bị treo install/screencap, UI dump trả null root; đã dừng đúng emulator đó và khởi động lại với `-gpu swiftshader`. Không sửa AVD config/userdata, không wipe hoặc thay policy.

- **INSTALL PASS:** cả Main và Live Test `adb install --no-streaming -r` trả Success, cùng tồn tại bằng hai package riêng.
- **MAIN UI SMOKE PASS:** launch MainActivity, screenshot Login; bấm Visitor theo bounds từ UI hierarchy, mở đúng public QR entry; Back hoạt động. Không nhập QR/token hoặc gọi backend.
- **LIVE TEST UI SMOKE PASS:** launch home, mở Sensor Probe; bridge report model/API, denied activity permission, stepDetector/stepCounter unavailable, rotationVector available. Start chuyển running và registration=registered cho rotationVector; Step Detector events vẫn0. Stop rồi Back, mở Local Pilot có nhãn sơ đồ tổng hợp. Không grant activity permission, không phát bước giả.
- **NOT VERIFIED:** camera scan→Published backend, toàn bộ Creator workflow trên APK, PDR accuracy, real StepDetector và native SAF/preferences smoke. Widget/service tests không thay các gate này.
- Evidence: `main-smoke.png`, `main-login.xml`, `main-public.xml`, `livetest-home.xml`, `livetest-probe.xml`, `livetest-running.xml`, `livetest-pilot.xml/png` trong evidence directory. Một số UI dump ngay sau cold launch trả null root; retry khi UI sẵn sàng thành công, không sửa app để né lỗi.
- Cleanup: force-stop đúng hai package trên emulator thuộc nhiệm vụ, `adb -s emulator-5580 emu kill`. Sau cleanup `adb devices -l` rỗng, không còn process AVD ở port5580 và không còn listener5580/5581. ADB server có trước nhiệm vụ được giữ. Không cài/xóa app trên điện thoại.

## I. Security / Data Preservation

Baseline đầu Cycle1: branch `auth-jwt-assignment`; **523 file hashed, 380 Git entries =43 modified +337 untracked, không staged**. Baseline JSON/hash/status lưu trong ignored evidence. Không nhận các file dirty trước đó là đóng góp Cycle1.

Đối chiếu trước viết báo cáo: đúng **12 file cũ đổi hash** trong D; **0 file mất**; đúng3 source/test mới. Sau thêm báo cáo, dự kiến527 file và384 entries; số thực tế và stage/branch check được ghi tại phụ lục I1.

Không chạy SQL thật/migration/DML/grant, không đổi secrets/JWT, không thu thập QR thật, không gọi AI live, không chỉnh LAN/firewall/DNS/TLS/CORS hoặc Windows security policy. Không khởi động API LAN. Dev-cert trust đã được phê duyệt trước đó giữ nguyên; Cycle1 không sửa certificate store. Không xóa user data/History/cache/APK cũ; không reset/clean/stage/commit/push/đổi branch.

Ignored build outputs/caches thay đổi theo build/test được phép, không thuộc source hash baseline. APK output thông thường của Flutter được build lại; các APK Sprint đã đặt tên không bị ghi đè. Không có thao tác cài APK lên điện thoại người dùng.

### I1. Final invariant checks

Sau tạo báo cáo: **527 Git tracked/untracked files, 384 status entries =43 modified +341 untracked**, branch vẫn `auth-jwt-assignment`, **0 staged**. So với baseline: **511/523 file cũ giữ nguyên hash; 12 file cũ đổi hash đúng danh sách D; 0 file mất; 4 file mới đúng danh sách D**. File ignored không thuộc hash manifest. Kết quả lưu `final-invariants.json`.

APK Sprint7 vẫn SHA256 `87ADD1157E7115F9A86C678659DF666356B5FFE3F5555302B62D27DBE115663D`, khớp evidence trước cycle. Không ghi vào thư mục APK Sprint cũ. Hai APK mới lần lượt 210,993,082 bytes (Main) và187,750,350 bytes (Live Test). Không có thay đổi source/config ngoài các file đã liệt kê.

## J. Những gate phụ thuộc môi trường / thiết bị thật

| Gate | Trạng thái | Điều kiện đóng |
|---|---|---|
| Backend integration execution | EXTERNAL DEPENDENCY BLOCKED | Test DLL được môi trường cho phép theo chính sách được chủ máy duyệt; chạy lại isolated HTTP/SQLite scenario và backend regression |
| Real Published read | AUTHORIZED_QR_NOT_AVAILABLE | QR được chủ bản đồ cung cấp an toàn; resolver→same snapshot→image GET với TLS mặc định |
| Real SQL/image identity | NOT VERIFIED trong cycle | Runtime identity đọc đúng DB/storage; không tự cấp grant/ACL hoặc tạo dữ liệu |
| Android trusted API endpoint | APPROVAL REQUIRED trước thay hạ tầng | Endpoint/cert/network được duyệt; PC localhost trust không tự áp dụng Android |
| SMTP/AI live | EXTERNAL DEPENDENCY PENDING | Cấu hình/delivery/provider được phép và budget nếu cần |
| Phone Published E2E | NOT VERIFIED | Đợt acceptance tổng thể sau code completion; không yêu cầu thử ở checkpoint này |
| Sensors/positioning accuracy | PHYSICAL ACCEPTANCE PENDING | Model/OEM, permission/lifecycle, corridor ground truth, false steps/heading/stride/QR correction evidence |
| Production signing/deploy | NOT READY | Signing/deployment configuration được chủ sản phẩm phê duyệt, không tạo key tùy ý |

Local API HTTPS startup và weatherforecast200 đã có bằng chứng trong `PublishedPilotLocalHttpsResolution20261029.md`; không chạy lại audit đó để tăng evidence, không chuyển HTTP transport PASS thành backend data PASS.

## K. Remaining Product Completion Work

Cycle1 đã đóng các lỗi đã chứng minh và build/test được phần độc lập; chưa phải Final Production RC. Backend combined scenario hiện là compiled specification, không phải INTEGRATION PASS. Android sensor accuracy và Published phone flow vẫn chưa nghiệm thu.

Các việc code tiếp theo không cần chờ điện thoại: kiểm retained cloud action owner qua switch/logout, expired-session routing không mất draft, bổ sung narrow layout coverage các màn hình trọng yếu và đo memory/image lifecycle. Không cần viết lại module ổn định, nâng toolchain hoặc mở rộng thuật toán.

## L. Proposed Cycle 2

1. Tái hiện owner switch trong retained Creator/cloud/confirmation workflow và session401 bằng deterministic tests; chốt giữ draft rồi sửa từng case có bằng chứng.
2. Mở rộng accessibility cho MyMaps→Builder dialogs→Search/Preview→Live panel trên màn hình nhỏ/text scaling/keyboard; không thay UX lớn khi chưa có failure.
3. Khi môi trường cho phép, chạy isolated backend flow + auth/authorization/publication/history/image regression. Nếu policy còn chặn, tiếp tục code/test độc lập; không bypass.
4. Đo image decode/cache/graph memory với fixture có kích thước kiểm soát; chỉ tối ưu theo before/after measurements.
5. Giữ hai APK riêng và chạy lại appropriate regression/build khi code thay đổi; gom các physical gates vào một đợt nghiệm thu tổng thể sau completion, không yêu cầu thử từng sprint.
6. Endpoint Android, QR thật, signing hoặc thay hạ tầng phải theo phê duyệt riêng. Định vị nâng cao chỉ làm sau field evidence, giữ nguyên safety invariants hiện tại.
