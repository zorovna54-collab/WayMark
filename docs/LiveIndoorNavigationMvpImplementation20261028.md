# WayMark Live Indoor Navigation — MVP Sprint 2–4

Ngày bàn giao: **28/10/2026 — Asia/Saigon**  
Workspace: `D:\project\WayMark`; Flutter: `waymark/`  
Phạm vi: triển khai pipeline định vị thử nghiệm, tích hợp Navigation và APK test riêng. Không nghiệm thu độ chính xác thực địa.

Quy ước: **IMPLEMENTED** = có source; **AUTOMATED PASS** = đã chạy kiểm tra trong lượt này; **NOT VERIFIED** = chưa chạy/đo trên Android thật. Tests dùng fake/channel mock không chứng minh phần cứng hoạt động.

## A. Executive Summary

**Đã hoàn thành MVP ở mức code, tích hợp, automated regression và APK. Chưa nghiệm thu định vị thực tế.**

| Trải nghiệm | Kết quả |
|---|---|
| Published Search → Preview → Navigation → bật Live tự nguyện | IMPLEMENTED; manual vẫn là mặc định |
| SensorProvider Sprint 1 → PDR → full-topology matching → IndoorPosition → blue dot | IMPLEMENTED; pipeline được kiểm bằng fake deterministic |
| Chiều dài bước nhập tay hoặc quãng đo/số bước; hiệu chuẩn hướng tương đối | IMPLEMENTED; cần xác nhận rõ, không tự lấy hướng route làm hướng người |
| Điểm giữa cạnh, đi ngược, giao lộ, geometry thiếu | Nội suy theo mét; giữ uncertain khi không đủ điều kiện |
| QR correction cùng map/version, revoke/offline/late response | Dùng resolver Published hiện có; pause, validate, reset baseline; automated PASS |
| Lệch tuyến | Hiển thị ước lượng ngoài tuyến; chỉ reroute từ Node xác nhận bằng QR hoặc thủ công thử nghiệm; cooldown |
| Pause/resume/background/scanner/route replacement/dispose | Có cleanup, generation/ticket fencing; automated PASS |
| Chuyển tầng | Trạng thái transition, yêu cầu QR hoặc xác nhận Node/tầng mới; không suy tầng từ bước |
| Local pilot không API | Có graph hai tầng tạo trong bộ nhớ; dùng provider Android thật, không phát bước giả |
| APK riêng | Đã build và kiểm metadata trực tiếp: `com.example.waymark.livetest` |
| Sensor/bước/heading/latency/pin/sai số trên điện thoại | **NOT VERIFIED** |

Không chạy timer để tăng quãng đường, không cộng StepCounter vào StepDetector, không tự hoàn tất checklist/arrival từ tổng bước. MapMatching không nhận route mong muốn làm input chọn nhánh. Blue dot dùng repaint riêng trong map scene.

Giới hạn chính: chỉ cạnh thẳng đã đối chiếu và xác nhận; không có wall mask/polyline; stride và tương quan phone–travel direction là giả định có điều kiện. Local pilot là sơ đồ tổng hợp, không phải dữ liệu khảo sát. QR xác nhận node/tầng/version qua server, không xác nhận heading hoặc người thật đứng cạnh biển.

## B. Architecture

### B1. Source và data flow

Các đường dẫn `lib/...`, `test/...`, `tool/...` dưới đây có tiền tố `waymark/`.

~~~text
Published QR → existing loadQr → snapshot/mapId/version → Search/Preview
  → NavigationPage [opt-in Live]
  → TrackingGraph (detached snapshot + stable GUID ↔ UI int mapping)

Android SensorBridge Sprint 1 → AndroidSensorProvider
  → SensorSessionController.observations [accepted events only]
  → PdrEngine [real StepDetector + stride + prior orientation/calibration]
  → MapMatchingEngine [full graph, confirmed straight edges]
  → IndoorTrackingController.position [ValueNotifier<IndoorPosition?>]
  → BlueDotPainter [CustomPainter repaint in shared map scene]

QR hiệu chỉnh
  → stop integration / pause native → ScannerPage.capture
  → existing resolvePublishedQr [map/version/revoke/node/floor checks]
  → VerifiedTrackingAnchor → atomic position/baseline reset
  → explicit sensors resume + direction alignment
~~~

| File/module | Trách nhiệm |
|---|---|
| `tracking_graph.dart` | Graph bất biến từ bản sao snapshot; stable map/version/floor/node/directed edge GUID; mapping qua routeIdentity; metric interpolation |
| `indoor_position.dart` | NodeAnchor/OnEdge/FloorTransition/Unknown, source, confidence, reason, ns time/generation, client anchor confirmation UTC |
| `pdr_engine.dart` | StrideCalibration, HeadingObservation/Calibration, step gate, orientation buffer, MovementObservation |
| `map_matching_engine.dart` | Full outgoing graph, heading candidates, reverse/bounds/overshoot; không có destination prior |
| `qr_relocalization.dart` | Adapter resolver Published đã pin; fail bằng mã lỗi cố định, không đưa payload vào diagnostics |
| `indoor_tracking_controller.dart` | State, sensor ownership, anchor/correction, lifecycle, route replacement, cooldown, bounded diagnostics |
| `blue_dot_overlay.dart` | Scene coordinate/floor isolation, dot/halo/arrow, repaint theo position, bù zoom |
| `live_tracking_panel.dart` | Opt-in calibration/control/status/fallback/diagnostics; quản lý app và route visibility |
| `pilot/local_pilot.dart` | Graph/image tổng hợp hai tầng trong RAM; mở Navigation hiện có |

### B2. Identity, geometry và thời gian

- Tracking key Published = `(server mapId, published version)`. Local pilot có key local riêng/version 0 và bị gắn nhãn thủ công thử nghiệm.
- Đọc `LocalMapNavigation.trackingSnapshotBytes()` rồi decode bản copy; không giữ draft Builder mutable. Floor/node/edge GUID lấy từ snapshot, không dùng `RouteEdge.id` làm identity. UI int chỉ qua mapping tường minh.
- Same-floor cạnh hợp lệ cần ảnh/aspect ratio, endpoints khác nhau, loại Corridor/Door, active và mét dương; đây mới là điều kiện dữ liệu, **chưa chứng minh hành lang thẳng thực tế**.
- Người thử phải đánh dấu đã đối chiếu từng cạnh thẳng/mét phù hợp. Không đủ geometry thì từ chối live trên cạnh, giữ manual/QR.
- `t = progressMeters / edge.meters`; `point = A + t(B − A)` trong normalized scene. Bearing dùng aspect ratio ảnh; không biến pixel/normalized distance thành mét.
- Progress chỉ trong `[0,L]`. Phần dư ghi nhận diagnostic, không truyền sang nhánh. Endpoint từ PDR có confidence uncertain, không phải đã xác nhận arrival.
- Native sample timestamps giữ ns monotonic cùng clock sensor; không trừ với DateTime. Anchor UTC là thời điểm client chấp nhận xác nhận, không phải sensor timestamp hay chứng thư server.

### B3. PDR, heading và matching

Chiều dài bước được xác nhận trong phiên, trong khoảng 0,2–1,5 m/bước. Có phép đo `quãng đường đo thật / số bước đếm tay`, từ chối số 0, dữ liệu không hữu hạn hoặc phép đo bị đánh dấu gián đoạn. Giá trị UI 0,70 chỉ là gợi ý chưa áp dụng tự động. Không lưu hồ sơ cá nhân hay upload.

Mỗi StepDetector hợp lệ tạo tối đa một movement observation. Counter chỉ quan sát đối chiếu. Duplicate, timestamp/generation cũ bị loại; zero-step và rotation-only không tạo displacement. Dùng orientation trước bước, không lấy mẫu ở tương lai để hồi chiếu; buffer 32 mẫu, freshness tối đa 1,5 giây.

Hiệu chuẩn khi người dùng chọn cạnh thực tế, hướng đỉnh vật lý điện thoại theo chiều đó, giữ gần nằm ngang và bấm xác nhận. Rotation/GameRotation dùng thay đổi yaw tương đối từ lần xác nhận; không cần giả map north. Projection/accuracy không đạt thì yêu cầu chờ hoặc chọn hướng thủ công. GameRotation vẫn có drift. Hướng thủ công là giả định thử nghiệm và estimate tiếp theo được đánh uncertain.

Matching dùng toàn bộ cạnh outgoing, bao gồm nhánh ngoài route và transition. Heading tolerance 36° là heuristic chưa hiệu chuẩn thực địa. Nhiều candidate/geometry chưa xác nhận → uncertain. Có thể tiếp tục ở Node khi chỉ một candidate phù hợp đã xác nhận; nhánh chưa biết yêu cầu người dùng chọn/xác minh. Đi ngược giảm progress, đi ngược cạnh một chiều bị cảnh báo; không ép bước luôn tiến về đích.

Sau hơn 40 movement observations kể từ anchor, controller giữ vị trí và yêu cầu mốc mới. Overflow giữ vị trí, hủy alignment. Các giới hạn này là biện pháp bảo thủ, không phải bảo đảm độ chính xác. Không có EKF/particle filter hay stride động.

### B4. QR, lifecycle, reroute và Navigation

- QR dùng closure `resolvePublishedQr` đã có: giữ map/version, kiểm membership node/floor; server contract quyết định revoke/offline. Không tạo format/table/backend mới.
- Trước camera, controller dừng tích phân và native collection. Ticket phiên chống response cũ sau pause/route change/dispose; correction hợp lệ reset position, heading baseline và anchor step budget atomically. Giữ before-position trong RAM để đối chiếu.
- QR không tự restart tracking hoặc đặt hướng theo route. Sau correction cần bật lại sensors, chọn cạnh và alignment. Sai QR/mất mạng không thay tọa độ/snapshot; confidence giảm và có thể thử lại/manual.
- Reroute dùng routing snapshot hiện có, chỉ sau anchor Node xác nhận ngoài route. Manual anchor được ghi source thủ công thử nghiệm; không gọi nó QR verified. Cooldown 8 giây, một request đang chạy; không Dijkstra/API trên từng bước.
- Scanner phủ route không nhất thiết đưa app background: panel kiểm route visibility riêng. Background/route phủ/pause/native state stop đều chặn motion. Resume là thao tác rõ ràng, tạo sensor generation mới và alignment mới.
- Pause giữa cạnh cần xác nhận chưa đổi chỗ; nếu đã đi khi pause thì quét QR/chọn Node thật lại. Chuyển tầng giữ from/target floor, dừng sensors; không nội suy giữa hai ảnh.
- `NavigationPage` sở hữu controller, dọn khi unmount/finish/map replacement. ManualNavigation/history vẫn riêng; bước chân không gọi `confirmNext()`. Các nút checklist manual được khóa khi Live đang bật và trở lại sau fallback.
- Panel Live hiển thị cạnh thực tế đang ước lượng. Header/checklist điều hướng cũ vẫn theo xác nhận manual/QR; MVP không tự đẩy checklist bằng blue dot.
- Overlay đặt sau route trong scene `FloorPlanCanvas`, trước transform InteractiveViewer; painter nghe position trực tiếp. Giữ graph/image cache, halo là trạng thái trực quan, không bán kính mét. Tầng đang xem khác tầng pose có thông báo, không vẽ dot nhầm tầng.

## C. Code Changes

### C1. Tạo mới: 15 file source/test

| Nhóm | Files |
|---|---|
| Model/graph/PDR/matching | `lib/features/indoor_tracking/indoor_position.dart`; `tracking_graph.dart`; `pdr_engine.dart`; `map_matching_engine.dart` |
| Điều phối/QR/UI | `lib/features/indoor_tracking/indoor_tracking_controller.dart`; `qr_relocalization.dart`; `blue_dot_overlay.dart`; `live_tracking_panel.dart` |
| Pilot/entrypoint | `lib/features/indoor_tracking/pilot/local_pilot.dart`; `tool/live_test_main.dart` |
| Tests | `test/live_tracking_graph_test.dart`; `live_pdr_matching_test.dart`; `live_tracking_controller_test.dart`; `live_navigation_ui_test.dart`; `live_local_pilot_test.dart` |

Tên file rút gọn trong mỗi hàng cùng thư mục với file đầy đủ đứng trước. Báo cáo này là file mới thứ 16.

### C2. Sửa 7 file có sẵn so với baseline đầu lượt

| File | Lý do |
|---|---|
| `lib/features/navigation/local_map_navigation.dart` | Xuất bản sao snapshot bytes để adapter giữ stable edge GUID |
| `lib/features/indoor_tracking/sensors/sensor_session_controller.dart` | Expose stream observations đã fence; đếm overflow status; cleanup stream |
| `lib/features/navigation/navigation_page.dart` | Opt-in Live, ownership, QR/cancel/finish/reroute, manual fallback |
| `lib/features/route/floor_route_map.dart` | Truyền overlay, floor isolation và cho xem tầng graph ngoài route |
| `lib/features/route/floor_plan_canvas.dart` | Hook overlay nằm cùng scene/transform |
| `android/app/build.gradle.kts` | Flavor Live Test chỉ bật khi có dart-define, applicationId suffix và label riêng |
| `android/app/src/main/AndroidManifest.xml` | Label placeholder; không thêm quyền mới trong lượt MVP |

Không viết lại hạ tầng native Sprint 1. Kotlin bridge, MainActivity, pubspec/lock, Gradle versions, Builder, scanner, Search/Preview, Published services/contracts, ManualNavigation và History source giữ nguyên hash so với baseline. Các integration point mới gọi lại luồng sẵn có.

Không sửa backend/SQL/migrations/JWT/role, map assets/JSON/draft/snapshot, app settings hoặc dữ liệu người dùng. Không restart API/ADB, không install/grant trên thiết bị, không commit/push/reset/clean/đổi branch. Không tạo Master Plan/Live Plan thay thế.

## D. Tests

Các con số dưới đây là kết quả lượt hiện tại; không cộng nhiều lần chạy. Baseline Sprint 1 426 pass/4 skip chỉ để tham chiếu, không dùng làm kết quả mới.

| Kiểm tra cuối | Kết quả | Evidence dưới `waymark/build/live-mvp-evidence/` |
|---|---|---|
| 5 targeted MVP test files | **40 PASS / 0 FAIL** | `targeted-tests.log` |
| Full Flutter suite, một lần chạy cuối | **466 PASS / 4 SKIP / 0 FAIL** | `full-tests.log` |
| `flutter analyze --no-pub` | **PASS — No issues found** | `analyze.log` |
| Dart format kiểm tra 20 file liên quan | **PASS — 0 changed** | Kết quả lệnh trong phiên |
| `git -c core.safecrlf=false diff --check` | **PASS** | Kết quả lệnh trong phiên |
| Android main debug | **PASS — assembleDebug** | `android-main-build.log` |
| Android Live Test debug | **PASS — assembleLiveTestDebug** | `android-livetest-build.log` |
| APK metadata bằng aapt | **PASS — package/label/min/target/permissions/ABI** | `main-apk-badging.txt`, `livetest-apk-badging.txt` |
| Android thật/emulator runtime smoke, SAF/preferences native thao tác thật | **NOT VERIFIED** | Không có thiết bị trong phiên |
| SQL/API live E2E, hành lang/pin/accuracy | **NOT VERIFIED / không chạy** | Không bật chế độ live/write |

Targeted: graph 9, PDR/matching 8, controller 15, rendering/navigation 6, local pilot 2 = 40 tests trong cùng lần chạy targeted. Full-suite count lấy từ dòng `+466 ~4: All tests passed!`. Bốn skip là các điều kiện sẵn có của suite (live SQL/Vision/platform); không sửa/tắt existing tests để pass.

Coverage chính:
- Graph GUID khi đảo thứ tự; frozen copy; mét/bounds; directed reverse; zero/coincident/unknown geometry; transition/map mismatch.
- Không bước/rotation/counter không displacement; stride N bước, duplicate/generation, prior/stale/future/missing orientation; invalid calibration; reverse, overflow và overshoot.
- Full topology tại giao lộ; geometry chưa xác nhận không tự đi; ngoài route chỉ reroute sau anchor xác nhận, cooldown.
- Valid QR, revoked, wrong map/version, missing node/floor, offline, late pause/dispose; point/snapshot giữ nguyên khi fail; không network trên từng bước.
- Live/manual, permission denied/absent sensors, resume không replay, route/map replacement, scanner phủ route, finish/unmount cleanup.
- Raster dot ở zoom 1×/2×/4× và pan/contain/floor; step không thay map state hoặc image widget; clipboard chỉ khi bấm và loại thông tin nhạy cảm.
- Full suite gồm các regression existing Published QR/scanner, Builder/Search/Preview/manual/multifloor/zoom, History, AI preferences/channel và SAF gateway mock. Đây là automated coverage, không phải native runtime smoke.

Lệnh chạy từ `D:\project\WayMark\waymark`:

~~~powershell
flutter test --no-pub test/live_tracking_graph_test.dart test/live_pdr_matching_test.dart test/live_tracking_controller_test.dart test/live_navigation_ui_test.dart test/live_local_pilot_test.dart --reporter expanded
flutter test --no-pub --reporter expanded
flutter analyze --no-pub
flutter build apk --debug --no-pub
flutter build apk --debug --no-pub --flavor liveTest --target tool/live_test_main.dart --dart-define=WAYMARK_LIVE_TEST=true
~~~

Format đã chạy trên danh sách file sửa/tạo liên quan bằng `dart format`, rồi `dart format --output=none --set-exit-if-changed`. Các checkpoint đã được kiểm targeted trong quá trình triển khai; bảng trên dùng kết quả cuối sau tích hợp. Build có warning Java native-access từ Gradle hiện có nhưng kết thúc thành công; không đổi toolchain để che warning.

Môi trường: `adb devices -l` danh sách rỗng. Không thấy listener tại API port 5121 lúc kiểm tra; không kết luận mọi port/host khác đều dừng. Không có runtime measurement, không coi mock/emulator/build là sensor acceptance.

## E. Live Test APK

| Thuộc tính | Giá trị kiểm từ artifact |
|---|---|
| Artifact bàn giao | `D:\project\WayMark\waymark\build\live-navigation-artifacts\WayMark-Live-Test-20261028-debug.apk` |
| Application ID | `com.example.waymark.livetest` |
| Nhãn | **WayMark Live Test** |
| Version | `1.0.0` / code `1` |
| Variant / Flutter target | `liveTestDebug` / `tool/live_test_main.dart`; define `WAYMARK_LIVE_TEST=true` |
| Kích thước | **171.308.301 bytes** (~171,31 MB, universal debug APK) |
| SHA256 | `24B6D14434B9D023E488EE1FAA7ADADF4829FB225E96356031F093488A65C7E5` |
| Minimum / target / compile | API **24** (Android 7.0) / **36** / **36** |
| ABIs | `arm64-v8a`, `armeabi-v7a`, `x86_64` |
| Permissions trong APK | INTERNET, CAMERA, ACTIVITY_RECOGNITION, ACCESS_NETWORK_STATE; permission nội bộ `com.example.waymark.livetest.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` |
| Signing | Debug theo cấu hình hiện có; không đổi signing |
| Upload/install | Không tự upload hoặc install |

Đã kiểm APK main riêng: `com.example.waymark`, label `waymark`, min24/target36. Package Live Test khác nên Android phân biệt app/data sandbox với app chính. Khả năng cài đồng thời trên điện thoại **chưa được thử thực tế**. Không dùng file `app-debug.apk` để gửi; file đó có thể bị build khác ghi đè.

Build main thông thường giữ nguyên lệnh và application ID. Cấu hình chỉ tạo flavor khi dart-define Live Test có mặt; build Live Test phải dùng đầy đủ command ở D. Bản sao có tên riêng ở trên độc lập với output build; không tự ghi đè artifact cũ.

**Chuyển và cài không USB:**

1. Người dùng tự tải đúng file artifact lên thư mục Google Drive cá nhân hoặc chuyển qua phương thức tin cậy; Codex chưa upload. Có thể đối chiếu SHA256 ở máy tính bằng `Get-FileHash -Algorithm SHA256 -LiteralPath '<đường dẫn APK>'`.
2. Trên Android, tải APK hoàn chỉnh về Downloads, mở bằng Files. Nếu OS yêu cầu, cho phép ứng dụng đang mở file cài APK; chỉ bật cho nguồn tin cậy. Không cần root hoặc USB debugging.
3. Màn hình cài phải hiển thị **WayMark Live Test**. Không gỡ app WayMark chính hoặc xóa dữ liệu app chính. Nếu máy đã có test package khác chữ ký, dừng và báo lỗi cài thay vì gỡ dữ liệu không rõ nguồn.
4. Mở icon **WayMark Live Test**. Sau cài có thể tắt lại quyền cài từ nguồn đó. ACTIVITY_RECOGNITION/camera cấp theo chức năng; không cần location/GPS/BLE.

## F. User Testing Manual

### F1. Bắt đầu local pilot

1. Chọn **Sensor Probe — kiểm tra phần cứng**. Ghi model, Android/API, StepDetector/Counter/RotationVector/GameRotationVector available/registration. Probe không tự bật permission dialog. Bấm quyền/Start rõ ràng rồi đi/dừng/quay; đây mới là phép kiểm native đầu tiên.
2. Quay lại, chọn **1. Local pilot — không cần API**. Graph có A–J–E, nhánh J–N/J–S, tầng trên S1–D1; các đoạn ngang giả định 10 m, link thang 3 m. Chọn E để có tuyến A→J→E. Sơ đồ sinh RAM; không thay map cá nhân.
3. Chuẩn bị hành lang trống đo thật, đánh dấu A/J cách 10 m. Chỉ thử nhánh nếu không gian thực sự bố trí phù hợp; không đi theo hình tổng hợp vào nơi có vật cản.
4. Mở Navigation, bấm **Live** thử nghiệm. Trong panel **Mốc, bước và hướng — cần xác nhận**, chọn Node A đúng tầng rồi bấm **Tôi xác nhận đang ở Node này**. Đây luôn là mốc thủ công, không QR verified.
5. Bấm **Quyền bước chân**, cho phép nhận diện hoạt động nếu được hỏi; bấm **Bật cảm biến**. API<29 không có prompt runtime activity. Nếu denied/StepDetector missing, dùng manual; không trông đợi dot chạy bằng counter.
6. Nhập mét/bước và bấm xác nhận. Tốt hơn: trước phiên này đi một quãng đo riêng, đếm tay số bước, nhập hai ô quãng đo/số bước; không dùng quãng gián đoạn. Giá trị chưa đo cần ghi là ước lượng.
7. Chọn cạnh A→J, tick xác nhận geometry/mét sau đối chiếu. Hướng đỉnh điện thoại theo chiều A→J, giữ gần nằm ngang, chờ orientation mới rồi bấm **Xác nhận hướng và bắt đầu ước lượng**. Chỉ dùng hướng thủ công khi hiểu đó là giả định, dot có thể amber/uncertain.
8. Mở **Diagnostics (on-device)** khi cần; không cần mở để tracking hoạt động. Đọc status, confidence/reason, step count, stride, integrated distance, progress, yaw/direction, generation/overflow.

### F2. Checklist từng ca

Ghi PASS/FAIL/chưa thử theo từng ca, không đánh PASS mặc định.

| Ca | Cách thử | Hành vi mong đợi / cần báo |
|---|---|---|
| Đi thẳng | 10 m đo thật, đếm tay bước; ít nhất 5 lượt mỗi chiều | Dot chỉ nhảy theo event bước; so detected/truth, progress và độ lệch endpoint trước khi sửa anchor |
| Dừng | Đứng yên 10–30 giây giữa đoạn | Không tự tăng progress nếu không có StepDetector; ghi false steps nếu cảm biến phát nhầm |
| Quay tại chỗ | Quay máy 90°/180°, giữ chân tại chỗ | Không dịch vị trí chỉ vì rotation; nếu máy báo false step, ghi rõ count/time |
| Giao lộ/rẽ | Đến J; chọn nhánh N khi đích E | Không tự ép E; candidate/uncertain nếu mơ hồ; xác nhận J rồi chọn nhánh thật, geometry và alignment mới |
| Lệch tuyến | Đi nhánh J→N, sau đó xác nhận đang N | Estimate ngoài route chưa reroute liên tục; anchor xác nhận N mới tính lại; kiểm số reroutes/cooldown |
| Đi ngược | Pause giữa cạnh, chưa đổi chỗ, resume; tick xác nhận chưa đổi vị trí và đi ngược; align theo hướng ngược | Progress giảm; không tự tiến tới đích. Đi lùi mà giữ phone hướng cũ không tự nhận biết đáng tin |
| Zoom/pan/tầng | Zoom nhiều mức, pan, đổi tầng xem | Dot bám scene, kích thước tương đối ổn định; không dot trên tầng khác, có cảnh báo floor mismatch |
| Pause/resume | Lặp 10 vòng; đứng yên trong pause | Native dừng; không bù bước trong thời gian pause; generation đổi, cần alignment lại |
| Đã đi khi pause | Di chuyển rồi resume | Không tick “chưa đổi vị trí”; dùng Node/QR thật để re-anchor |
| App background | Home/tắt màn hình rồi trở lại | Không tracking nền; resume thủ công, không replay bước bị bỏ lỡ |
| Route bị phủ | Mở scanner hoặc màn khác rồi trở lại | Ngưng collection/integration; scanner correction xử lý đúng ticket |
| Thiếu sensor/deny/revoke | Từ chối quyền; hoặc revoke trong Settings rồi quay lại; máy thiếu detector nếu có | Trạng thái rõ, không crash, không giả bước; manual vẫn hoạt động |
| Chuyển tầng | Chọn S→S1 tại S trong pilot; xem floor state | Dừng ở transition; xác nhận S1 trên tầng mới, bật sensors/alignment lại; không kéo dot xuyên hai ảnh |
| Finish/cancel | Kết thúc hoặc thoát Navigation | Không tiếp tục count/pose phiên đã đóng; không tự arrival chỉ nhờ tổng khoảng cách |
| Manual fallback | Bấm **Về manual / QR** | Stop/dispose live; checklist và QR flow cũ dùng lại được |

Local pilot không có QR server, nút correction không khả dụng. Muốn kiểm full QR phải dùng F3.

### F3. Published QR pilot thật

1. Người dùng cấu hình endpoint test an toàn có thể truy cập từ điện thoại, ví dụ `https://<host-test>/api`; ô URL không nhận token/credentials/query. Không dùng literal placeholder. `localhost` trỏ chính điện thoại; `10.0.2.2` dành cho emulator, không phải địa chỉ LAN máy tính.
2. Nhập endpoint ở trang **Published QR pilot**, mở guest QR. Chỉ dùng map đã publish, ảnh tải được, QR thật đúng version, cạnh/mét đã khảo sát phù hợp. Lượt này không mở server public, không đổi firewall/TLS/auth để tạo endpoint.
3. Quét hoặc nhập QR qua PublicMapEntry hiện có → Search → Preview → Navigation → Live. Có thể quét **QR hiệu chỉnh** để controller nhận anchor verified trong phiên; initial QR không được dùng ngầm như một alignment hướng.
4. Đi một đoạn, ghi estimate/step/progress trước correction. Quét QR node khác cùng snapshot; sensors phải pause trước camera, anchor về node/tầng hợp lệ. Ghi result/corrections, rồi bật sensors và align lại để tiếp tục.
5. Thử QR khác map/version, QR revoked do người quản lý chuẩn bị, node/floor không hợp lệ nếu có fixture test an toàn: tọa độ không được thay bằng QR bị từ chối. Không sửa database thật chỉ để tạo ca lỗi.
6. Sau khi snapshot đã tải, ngắt mạng và đi trên cạnh đã xác nhận; PDR xử lý tại máy. QR correction offline phải fail, không giả verified; kết nối lại và quét mới. Map chưa tải không thể mở bằng offline pilot Published.
7. Mở scanner rồi cancel; mở scanner rồi background/đổi route trong lúc resolve: response cũ không áp dụng vào phiên khác. Ghi steps/generation/reason trước và sau.
8. QR ở đích có thể xác nhận hoàn tất qua semantics QR hiện có. Chỉ bước tới tổng mét không tự xác nhận đã đến.

### F4. Gửi kết quả không cần ADB

- Mở Diagnostics → **Sao chép chẩn đoán đã làm sạch**, dán vào ghi chú/tin nhắn gửi lại khi chủ động. Export không chứa QR/JWT/URL, map/node/edge ID, tên địa điểm, tọa độ hoặc trace; chỉ các số/trạng thái phục vụ chẩn đoán.
- Panel trên máy có thể hiển thị map/edge/floor và yaw: kiểm tra/cắt thông tin nhạy cảm trước khi chụp hoặc quay màn hình; tránh quay biển QR/token, người khác hoặc địa điểm riêng tư.
- Gửi model/Android/API (tự ghi, clipboard hiện không chứa model), local hay Published, tên ca, cách cầm, đoạn đo thật, stride đã nhập, số bước đếm tay/sensor, thời điểm pause/correction, error/reason, count overflow/rejected/reroutes. Kèm screenshot/screen recording bằng chức năng OS nếu đồng ý.
- Mỗi lượt ghi ground-truth distance, detected/truth steps, endpoint error trước correction, failed/incomplete; không bỏ lượt lỗi. Ground truth 0 dùng false-step count, không chia cho 0.
- Sau pilot một máy, nên kiểm ít nhất hai model và hai người; hướng đi/cách cầm phân nhóm. Chưa có số liệu nên không đưa mean/p95 hay claim sai số mét ở báo cáo này.

## G. Known Limitations

1. **Chưa chạy trên Android thật**: capability listing/permission/registration, count accuracy, sensor-to-Dart latency, listener cleanup 10 vòng, drain pin và OEM behavior còn NOT VERIFIED. APK build không thay thế các phép thử đó.
2. Phone yaw không quan sát được chắc chắn người đi lùi khi vẫn hướng máy về trước, đổi tay, máy lệch hoặc bỏ túi. Điều kiện v1 là cầm máy đúng hướng/near horizontal; phá điều kiện phải pause/anchor/alignment lại. Không có thuật toán nhận biết mọi tư thế.
3. StepDetector có thể bỏ bước/phát nhầm. Raw counter không sửa bù thành live steps. Stride một hằng số trong phiên, chưa thích ứng tốc độ/dáng đi, chưa có mô hình sai số metric.
4. Không wall collision hoặc polyline. Checkbox geometry là xác nhận người thử, không engine kiểm tường. Hành lang cong/ảnh thiếu/loại cạnh chưa hỗ trợ giữ fallback; authoring geometry phải là công việc riêng.
5. Giao lộ và endpoint bảo thủ; không đảm bảo tự chọn hết mọi nhánh. Phần dư tại endpoint không replay sang cạnh kế. Có thể cần QR/manual anchor thường xuyên; 40 bước là giới hạn thử nghiệm.
6. Không tự suy floor/elevator/stairs từ bước/barometer; chuyển tầng cần xác nhận. Manual anchor/floor là khai báo người dùng, không bằng chứng cảm biến.
7. QR correction cần mạng; không push revoke realtime đến snapshot đã tải. QR verified nói resolver chấp nhận tại lúc quét, không chứng minh biển QR chưa bị di chuyển. Initial QR không tự khẳng định heading.
8. Blue dot estimate và checklist/historical completion tách nhau. Không tự sync node instruction/arrival bằng bước; phần panel Live là hướng dẫn cho estimate hiện tại, manual/QR vẫn quyết định xác nhận.
9. Local image/graph là synthetic, 10 m/đoạn giả định. Muốn đo error phải bố trí/quay lại hành lang đo thật; không dùng số fixture làm ground truth.
10. Debug universal APK lớn, không phải bản phát hành tối ưu. Không thêm package, không nâng SDK/Gradle/Kotlin, không BLE/UWB/Wi-Fi RTT/Google Maps.
11. Diagnostics bounded trong RAM, không persist/telemetry. Không có chứng nhận định vị bệnh viện, an toàn/accessibility hay patient-use mới.

## H. Final Decision

| Kết luận độc lập | Trạng thái | Căn cứ / điều kiện |
|---|---|---|
| **IMPLEMENTATION STATUS** | **Complete** trong phạm vi MVP thử nghiệm đã giới hạn | Pipeline sensor→position→overlay, calibration/uncertainty/full graph/QR/lifecycle/fallback, local+Published entrypoints và APK riêng đã có |
| **AUTOMATED VALIDATION** | **PASS** trong phạm vi chạy | 40 targeted; full 466 pass/4 skip; analyzer/format/diff/main+test builds và APK metadata pass |
| **PHONE TEST READINESS** | **CONDITIONAL** | APK sẵn để chuyển/cài; local pilot không API. Cần điện thoại có detector và cài thử; Published cần endpoint/QR/map phù hợp |
| **REAL-WORLD POSITIONING ACCEPTANCE** | **NOT VERIFIED** | Chưa đi bộ/đo native trên thiết bị/hành lang thật, chưa biết drift/false steps/error/pin |

Không có blocker backend/schema cần thay đổi để bàn giao code/Local Test APK. Điều kiện thực địa còn thiếu không bị đổi thành PASS bởi automated tests. APK dành cho thử nghiệm chủ động, chưa triển khai cho người dùng cuối như hệ thống định vị đã nghiệm thu.

## I. Change Safety / Evidence Integrity

Baseline đầu lượt ở branch `auth-jwt-assignment`: **336 Git status entries = 42 modified + 294 untracked**; SHA256 **480 file** tracked/untracked không bị ignore. Danh sách đầy đủ và hash được giữ trong bộ nhớ phiên trước khi sửa, không đọc/xuất secrets.

Sau bàn giao: **353 entries = 43 modified + 310 untracked**; **496 file** thuộc tập kiểm SHA256. Baseline cũ không mất file; **473/480 giữ nguyên hash**, đúng **7 file** đổi hash ở C2; thêm **15 source/test + báo cáo này**. Một modified entry mới là Gradle app build; hai file được sửa thêm ở lượt này vốn đã untracked từ trước (LocalMapNavigation, SensorSessionController).

Báo cáo tạo mới sau khi kiểm `Test-Path` chưa tồn tại. Artifact/log/build outputs nằm trong `waymark/build/` bị Git ignore, không tính trong hash manifest. Không sửa các existing tests/assets/backend vốn đã dirty. Không có staged/commit/push mới. So sánh hash giúp phân biệt thay đổi MVP với tổng diff lớn đã có trước, không nhận thay đổi baseline làm công việc của lượt này.

Evidence cuối nằm tại `D:\project\WayMark\waymark\build\live-mvp-evidence\`, artifact bàn giao ở E. Đây là log/build mới của lượt MVP; các báo cáo G0/Sprint 1 giữ nguyên.

