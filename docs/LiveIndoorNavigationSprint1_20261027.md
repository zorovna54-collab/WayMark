# WayMark Live Indoor Navigation — Sprint 1: Android Sensor Infrastructure

Ngày: **27/10/2026 — Asia/Saigon**  
Workspace: D:/project/WayMark  
Branch giữ nguyên: **auth-jwt-assignment**  
Căn cứ: [G0 Readiness Audit](LiveIndoorNavigationG0Readiness20261027.md). Tài liệu Live Plan tùy chọn chưa tồn tại; không tạo thay thế.

**Quyết định: CONDITIONAL GO.** Hạ tầng cảm biến độc lập đã triển khai, analyzer/tests và hai Android debug build đạt. **Physical Android Sensor Test: NOT VERIFIED.** Có thể chuẩn bị thiết kế Sprint 2; chưa nghiệm thu native runtime hoặc độ chính xác PDR.

## A. Summary

Đã triển khai:

- Contract/codec Dart cho sáu sensor, timestamp gốc int64 nanoseconds, units, reference frame, accuracy, sequence và generation.
- Kotlin SensorManager bridge độc lập, capability probe thực qua hệ thống, permission theo thao tác người dùng, kết quả đăng ký từng sensor.
- MethodChannel điều khiển và EventChannel samples/status/registration/recoverable errors, tách hai channel AI/SAF hiện có.
- Provider Dart, fallback unsupported platform, controller start/stop/pause/resume/dispose có serialization và chặn event cũ.
- Debug probe và entrypoint riêng, không cần đăng nhập/API/SQL/LM Studio, không thêm menu sản phẩm.
- Fake deterministic chỉ dưới test/, cùng model/channel/controller/widget tests.
- Giữ nguyên Navigation, Builder, QR, Published snapshots, History, backend, database và dependencies/toolchain.

Chưa triển khai PDR, đo quãng đường bằng bước, blue dot, travel heading, map matching, QR correction, branch/floor inference hoặc rerouting mới. Không dùng timer để tạo bước chân; timer duy nhất trong controller dùng throttle thông báo UI.

Chưa có điện thoại thật kết nối. Permission, registration, bước chân, orientation và lifecycle **trên thiết bị thật** còn cần xác minh. Test fake/channel và APK build không thay thế gate này.

## B. Architecture

### B1. Modules và communication flow

~~~text
SensorManager → SensorEventListener trên HandlerThread
  → copy values + giữ SensorEvent.timestamp
  → bounded native queue
  → EventChannel trên main thread
  → AndroidSensorProvider: codec + generation/per-sensor order gate
  → SensorSessionController: state + bounded observations + throttled notify
  → SensorProbePage (DEBUG only)

Probe / explicit permission / start / stop / native clock
  ← MethodChannel waymark/sensors/control
~~~

| Module | Trách nhiệm / source |
|---|---|
| Sensor domain | sensor_models.dart: SensorKind, SensorSample, SensorCapabilities, SensorConfig, SensorRegistration, SensorStartResult, SensorProviderStatus, SensorSampleGate |
| Provider boundary | sensor_provider.dart: SensorProvider interface và createSensorProvider; web/desktop dùng UnsupportedSensorProvider, không phát sample giả |
| Android adapter | android_sensor_provider.dart: decode channels, ownership, start handshake, serial controls, sample fencing, subscription cancellation |
| Session | sensor_session_controller.dart: observable hạ tầng và debug observation, không phụ thuộc Navigation/Builder |
| Native bridge | AndroidSensorBridge.kt: SensorManager, permission, listeners, native clock, queue/lifecycle |
| Probe | sensor_probe_page.dart + tool/sensor_probe_main.dart: UI riêng, không nối router sản phẩm |
| Test-only fake | test/support/fake_sensor_provider.dart: phát dữ liệu chỉ khi test gọi emit; không import từ lib/ hoặc tool/ |

### B2. Channel/schema contract v1

Tên channel:

- MethodChannel: **waymark/sensors/control**.
- EventChannel: **waymark/sensors/events**.
- Không đổi **waymark/ai_preferences** hoặc **waymark/draft_files**.

| Control method | Request → response |
|---|---|
| probe | Không xin quyền → schemaVersion, device manufacturer/model, androidApi, permission, inventory đủ sáu kind, metadata và registration state |
| requestPermission | Chỉ gọi qua nút explicit ở probe → schemaVersion + permission; native chặn request khi Activity không foreground hoặc đã có request đang chờ |
| clock | → schemaVersion + nativeTimestampNs từ elapsedRealtimeNanos, dùng seed generation; không dùng wall clock |
| start | schemaVersion, generation int64, kinds, samplingPeriodUs → generation, permission và registration outcome từng kind |
| stop | → null; unregister, fence callbacks, xóa queue, hủy callback drain |

Event sample:

~~~text
type = sample
schemaVersion = 1
kind, androidType
generation, sequence
sensorTimestampNs, nativeReceiveTimestampNs
values
accuracy
units, referenceFrame
~~~

Event status có type=status, schemaVersion, state, generation, message; state=registration còn mang registrations[] tương tự start response. Các phase gồm listening, registration, running, paused, stopped, error, recoverableError, overflow, accuracyChanged. Native hiện dùng listening/registration/paused/stopped/error/overflow; accuracy của mỗi sample nằm trong sample.accuracy.

Kết quả start qua MethodChannel là dữ liệu authoritative để chọn registeredKinds. Sensor có mặt nhưng registerListener trả false/exception được báo **failed**, không gộp thành “ready”. Thiếu sensor → unavailable; thiếu quyền bước → permissionDenied. Orientation vẫn có thể chạy khi bước bị từ chối/không có.

### B3. Sensor model

| Kind | Android type | Values / units | Reference frame |
|---|---:|---|---|
| stepDetector | 18 | [1.0] / steps — một event phát hiện bước | none |
| stepCounter | 19 | [cumulativeSteps] nguyên không âm / steps | none |
| rotationVector | 11 | x/y/z, optional w và estimated heading accuracy / unitless | androidEastMagneticNorthUp |
| gameRotationVector | 15 | x/y/z, optional w / unitless | androidRelativeZUp |
| accelerometer | 1 | x/y/z / m/s2, có gravity | androidDevice |
| gyroscope | 4 | x/y/z / rad/s | androidDevice |

Giữ nguyên vector gốc. Getter quaternion chỉ bổ sung w khi vector ba thành phần thiếu w; không xoay trục theo màn hình, không tính travel heading. Heading accuracy tùy chọn của rotation vector vẫn nằm trong values[4]. Không đồng nhất game rotation với hướng bắc.

Codec kiểm schema/type, int64/timestamp/generation/sequence, kind, số phần tử, kiểu số, NaN/Infinity, đơn vị/frame, detector=1, counter nguyên không âm và rotation vector hợp lệ. Payload sai phát recoverableError và không crash luồng hợp lệ. Timestamp khác loại sensor có thể tới lệch thứ tự; chỉ loại duplicate/backwards timestamp hoặc sequence trong cùng sensor.

**Timestamp và latency:** SensorEvent.timestamp được truyền nguyên Long → Dart int, không thay bằng DateTime.now. Native receive timestamp lấy elapsedRealtimeNanos trong callback. nativeDeliveryLatencyNs chỉ là receive−sensor cùng đồng hồ; nếu receive<sensor thì trả null. Đây **không phải** phép đo latency native→Dart hay end-to-end. Test có timestamp 9007199254740993 để phát hiện việc vô tình chuyển qua double.

Đặc tính Android đối chiếu với [SensorEvent](https://developer.android.com/reference/android/hardware/SensorEvent), [SensorManager](https://developer.android.com/reference/android/hardware/SensorManager) và [Motion sensors](https://developer.android.com/develop/sensors-and-location/sensors/sensors_motion). Không suy khả năng thiết bị từ việc API tồn tại.

### B4. Lifecycle và giới hạn hiệu suất

- Controller states: idle, starting, running, paused, permissionDenied, unavailable, error, disposed.
- Start đang running trả lại session hiện tại; controller không tạo listener thứ hai. Provider còn chặn hai instance đồng thời chiếm cùng engine channels.
- Probe/start/resume không mở permission dialog. Chỉ requestPermission explicit có thể xin quyền.
- Resume thực hiện probe lại capability/permission, dùng generation mới seed từ native clock để tránh tái sử dụng ID nếu Dart provider được tạo lại trong Activity còn sống.
- Native listener được tạo riêng cho mỗi generation; event callback giữ generation gốc. Event timestamp trước lúc registration bị bỏ. Callback cũ không được gắn nhãn thành phiên mới.
- Pause/stop fence Dart gate ngay, rồi unregister native; không dùng StreamSubscription.pause để thay native cleanup.
- Native onPause, EventChannel onCancel và onDestroy đều cleanup. Terminal native status cũng khiến provider hủy subscription, để start lại trực tiếp không bỏ quên subscriber cũ.
- Các thao tác bất đồng bộ được serialize; controller dùng revision để start trả trễ không khôi phục session đã stop/dispose.
- Probe theo dõi app lifecycle và route visibility riêng bằng WidgetsBindingObserver + RouteObserver. Bị che bởi route khác vẫn dừng sensor dù app còn resumed.
- **Quay lại foreground/route không tự thu lại. Người dùng bấm Resume.** Resume kiểm tra lại quyền, không tự prompt. Manual pause cũng được giữ.
- Re-probe phát hiện quyền step bị thu hồi sẽ dừng session có sensor bước; probe failure cũng cleanup session đang thu.
- Raw counter chỉ hiển thị cumulative reading; không sinh step từ delta và không cộng counter vào Detector count. Resume không phát lại backlog như các bước vừa xảy ra.
- Native callback chạy trên HandlerThread, không tính PDR hoặc làm I/O. EventChannel sink dùng main thread, queue giới hạn **256**, drain tối đa 32 events/lượt; overflow được báo rõ.
- Dart buffer khi start và debug recent buffer mỗi loại giới hạn **128**; UI sample notify throttle **200ms**. Không lưu log/file cảm biến mặc định, không network.
- Sensor worker tạo lazy lúc cần registration; Activity giữ một worker, dispose Activity dọn worker. App chính chỉ mở bình thường không đăng ký listeners.
- Sampling mặc định 20.000µs, config cho phép 20–1000ms; đây là yêu cầu sampling, không bảo đảm HAL thực hiện chính xác. Không dùng HIGH_SAMPLING_RATE_SENSORS, foreground service hoặc background tracking.

### B5. Debug probe sử dụng thế nào

Entrypoint: **waymark/tool/sensor_probe_main.dart**. main.dart và menu ứng dụng chính không thay đổi. Entrypoint và page có guard kDebugMode; page release không tạo Android provider thật.

1. Mở probe trên thiết bị test đã được phép dùng.
2. Probe tự đọc capability; **không xin quyền** lúc mở.
3. Nhấn “Xin quyền bước chân” nếu cần, xử lý dialog Android bằng thao tác người dùng.
4. Start: mặc định yêu cầu Detector, Counter và Rotation Vector; nếu hệ thống không có Rotation Vector thì chọn Game Rotation Vector với frame relative.
5. Bật checkbox raw diagnostics trước Start nếu muốn thêm accelerometer/gyroscope.
6. Quan sát inventory/registration, detector event count, counter raw, vector/accuracy, timestamps, generation/sequence và native delivery latency.
7. Pause/Stop hoặc rời probe sẽ dừng thu; quay lại nhấn Resume.

Probe không cung cấp export log trong Sprint 1. Không gọi PDR, API hoặc SQL.

## C. Changed Files

### C1. Tạo mới — 12 source/test files

| File | Lý do |
|---|---|
| waymark/lib/features/indoor_tracking/sensors/sensor_models.dart | Domain/codec/validation và acceptance gate |
| waymark/lib/features/indoor_tracking/sensors/sensor_provider.dart | Interface, platform factory và unsupported fallback |
| waymark/lib/features/indoor_tracking/sensors/android_sensor_provider.dart | Flutter channel adapter và ownership/cleanup |
| waymark/lib/features/indoor_tracking/sensors/sensor_session_controller.dart | Session lifecycle, observation, bounded buffer/UI throttle |
| waymark/lib/features/indoor_tracking/debug/sensor_probe_page.dart | Debug-only sensor UI, app/route visibility |
| waymark/tool/sensor_probe_main.dart | Standalone entrypoint |
| waymark/android/app/src/main/kotlin/com/example/waymark/sensors/AndroidSensorBridge.kt | Native sensors/capability/permission/stream |
| waymark/test/support/fake_sensor_provider.dart | Deterministic fake và sample fixture, test-only |
| waymark/test/sensor_models_test.dart | Codec/types/frames/timestamps/status tests |
| waymark/test/android_sensor_provider_test.dart | Mock channel/control/events/ownership/error tests |
| waymark/test/sensor_session_controller_test.dart | State/race/lifecycle/permission/order/buffer tests |
| waymark/test/sensor_probe_page_test.dart | Capability/controls/fallback/route/app/unmount widget tests |

Tạo thêm báo cáo này: **docs/LiveIndoorNavigationSprint1_20261027.md**. Đã kiểm tra chưa tồn tại trước khi tạo, không ghi đè báo cáo cũ/G0.

### C2. Sửa bổ sung — đúng hai file có sẵn

| File | Thay đổi |
|---|---|
| waymark/android/app/src/main/AndroidManifest.xml | Thêm ACTIVITY_RECOGNITION; không khai báo sensor hardware bắt buộc |
| waymark/android/app/src/main/kotlin/com/example/waymark/MainActivity.kt | Import/khởi tạo bridge, forward onResume/onPause/permission result, dispose trước cleanup hiện hữu |

Đã so sánh MainActivity với nội dung working tree ngay trước Sprint: bỏ các đoạn sensor thêm mới thì **toàn bộ body cũ giữ nguyên về nội dung**. Hai channel AI/preferences và draft files, SAF request codes 9721/9722, worker, onActivityResult và cleanup file hiện có được giữ. Sensor permission request dùng code 9731.

Không sửa pubspec/lock, Gradle/Kotlin/SDK config, main.dart, Flutter production Navigation/Builder/scanner, tests cũ, backend/SQL/QR/snapshot/History/AI/Master Plan.

Generated artifacts/logs nằm trong build/ bị Git ignore; không phải thay đổi source hay dữ liệu bản đồ.

## D. Sensor Capabilities

| Sensor | Có API/bridge/codec hỗ trợ | Xác nhận trên Android thật |
|---|---|---|
| Step Detector | Có | NOT VERIFIED |
| Step Counter | Có, raw cumulative đối chiếu | NOT VERIFIED |
| Rotation Vector | Có | NOT VERIFIED |
| Game Rotation Vector | Có, relative frame rõ | NOT VERIFIED |
| Accelerometer | Có, optional diagnostics | NOT VERIFIED |
| Gyroscope | Có, optional diagnostics | NOT VERIFIED |

Capability lấy SensorManager.getDefaultSensor cho từng loại, không đoán từ SDK/model. Metadata gồm name/vendor/version/range/resolution/minDelay; start report registration riêng.

Permission behavior được triển khai:

- API29+: kiểm và xin ACTIVITY_RECOGNITION khi nhấn nút explicit.
- API<29: notRequired, không mở runtime dialog này.
- Không xin camera/location/Bluetooth cho sensor probe; không xin quyền lúc launch.
- Denial không chặn quan sát orientation nếu registration hợp lệ; không tự lặp prompt.
- Resume/re-probe kiểm lại quyền; native step callback cũng kiểm quyền trước forward. Thiết bị/OEM có thể kill process khi revoke, cần thử thật.
- Fake/mock tests xác nhận contract grant/deny/notRequired và revocation flow; **dialog/permission behavior Android thật vẫn NOT VERIFIED**.

## E. Automated Tests

Kết quả dưới đây từ lệnh thực hiện trong Sprint, không dùng lại kết quả 357 tests của G0.

| Kiểm tra | Kết quả cuối |
|---|---|
| Dart format trên 11 file Dart mới | PASS; kiểm cuối 0 file cần đổi |
| flutter analyze --no-pub | **PASS — No issues found** |
| Targeted model/channel/controller/widget sensor tests | **69 PASS / 0 FAIL** |
| Full Flutter suite, một lần chạy cuối | **426 PASS / 4 SKIP / 0 FAIL** |
| Android debug build, app chính lib/main.dart | **PASS** |
| Android debug build, tool/sensor_probe_main.dart | **PASS** |
| git diff --check | **PASS** |
| Emulator runtime test | Không chạy |
| Physical Android Sensor Test | **NOT VERIFIED** |

Không cộng targeted vào full-suite count. Full result 426/~4 là một dòng kết thúc duy nhất của lần chạy cuối. Bốn skip là các điều kiện platform/opt-in sẵn có; không bật SQL-live state hoặc Vision live flags. Không chạy E2E ghi database.

Các lệnh chính từ D:/project/WayMark/waymark:

~~~powershell
dart format lib/features/indoor_tracking tool/sensor_probe_main.dart test/sensor_models_test.dart test/android_sensor_provider_test.dart test/sensor_session_controller_test.dart test/sensor_probe_page_test.dart test/support/fake_sensor_provider.dart
flutter analyze --no-pub
flutter test --no-pub test/sensor_models_test.dart test/android_sensor_provider_test.dart test/sensor_session_controller_test.dart test/sensor_probe_page_test.dart --reporter expanded
flutter test --no-pub --reporter expanded
flutter build apk --debug --no-pub
flutter build apk --debug --no-pub --target tool/sensor_probe_main.dart
git diff --check
~~~

Có dùng dart fix chỉ với lint fixes trên module mới, không áp dụng toàn repo hoặc tests cũ. Kiểm format cuối dùng --output=none --set-exit-if-changed trên đúng 11 file mới.

Coverage có ý nghĩa:

- Sáu sensor kinds; schema/type/unit/frame/shape/NaN/Infinity; quaternion optional fields; int64 không mất precision; native latency âm trả null.
- Permission grant/deny/notRequired; missing sensor; partial registration; register failure; channel error/malformed payload; timeout handshake; failure cleanup/retry.
- Hai provider không chiếm/dừng nhầm session của nhau; start/stop idempotent; terminal native pause tự cancel subscription và start lại bằng generation mới.
- Late/duplicate/wrong-generation/wrong-kind events; cross-sensor timestamp reorder hợp lệ; same-sensor timestamp reversal bị loại.
- **10 vòng pause/resume bằng fake**, không double count/backlog; start-stop/dispose race, partial-start exception; revoked permission/re-probe failure.
- Buffer hữu hạn/throttle; explicit permission UX; unavailable/registration UX; route cover khác app lifecycle; cleanup khi unmount.

Regression: full suite bao gồm QR, Published Map, manual Navigation, multi-floor, Builder/zoom/AI và tests mock các channel AI preferences/draft files. Không sửa các test cũ. **SAF/camera thực trên Android không được coi là đã smoke-test bằng mocks**; phần source MainActivity cũ được giữ nguyên và Kotlin build đạt.

Logs hiện có, Git ignored:

- waymark/build/sensor-sprint1-evidence/analyze.log
- waymark/build/sensor-sprint1-evidence/sensor-tests.log
- waymark/build/sensor-sprint1-evidence/full-tests.log
- waymark/build/sensor-sprint1-evidence/android-main-build.log
- waymark/build/sensor-sprint1-evidence/android-probe-build.log

Build có cảnh báo native-access của JDK/Gradle; cả hai command exit 0. Không đổi toolchain/cờ bảo mật để ẩn cảnh báo. Không còn lỗi analyzer/test/build được biết ở phiên bản cuối.

APK hiện tại: **waymark/build/app/outputs/flutter-apk/app-debug.apk**, do lần build target probe cuối tạo. APK vẫn dùng applicationId hiện tại com.example.waymark; **chưa cài lên thiết bị nào**. Khi thực hiện physical gate cần chọn thiết bị test và kiểm tra app/data hiện hữu trước khi cài; không uninstall/xóa dữ liệu để thử probe.

## F. Physical Device Evidence

Lệnh thực hiện: adb devices -l bằng platform-tools của Android SDK hiện có, cả lúc preflight và kiểm cuối. Kết quả: **List of devices attached, danh sách rỗng**.

| Hạng mục | Bằng chứng vật lý |
|---|---|
| Model/OEM/Android API | NOT VERIFIED — không có thiết bị |
| Sensor list/registration thực | PENDING |
| Permission grant/deny/revoke thật | PENDING |
| Step Detector đi bộ/đứng yên/false steps | PENDING |
| Counter cumulative behavior | PENDING |
| Rotation/Game vector quay máy tại chỗ | PENDING |
| Pause/resume 10 vòng trên máy | PENDING |
| Stop/dispose/onCancel listener cleanup | PENDING |
| Duplicate/stale events thực | PENDING |
| Native latency/rate/accuracy quality | PENDING |
| Battery | PENDING |

Không cài APK, grant permission bằng ADB, xóa app data hoặc uninstall. Không dùng fake/emulator làm bằng chứng điện thoại thật.

Gate ngắn cho lượt thử thiết bị sau:

1. Xác nhận thiết bị thật/model/OS/API, sáu capability và kết quả registration; tên model đơn lẻ chưa đủ.
2. Từ probe: xin/deny quyền bằng thao tác người dùng, retry explicit, kiểm revoke/resume.
3. Đi bộ đếm tay, đứng yên, quay máy tại chỗ; Detector events và Counter raw ghi riêng, không tính distance sản phẩm.
4. Pause/Resume 10 vòng, background/return và route cover; xác nhận không sample trong khoảng dừng, generation đổi và không duplicate/backlog.
5. Stop/rời probe; xác minh listeners đã unregister, không phát callback vào session cũ.
6. Ghi observations native latency/accuracy/rate và các lỗi, không tuyên bố độ chính xác theo mét.

## G. Safety

### G1. Working-tree baseline và delta

| Kiểm tra | Trước Sprint | Sau khi thêm source và báo cáo |
|---|---:|---:|
| Modified entries | 42 | 42 |
| Untracked entries, -uall | 281 | 294 |
| Tổng git status entries | 323 | 336 |
| File cũ trong manifest SHA256 | 467 | 465 giữ nguyên + đúng 2 file Android được sửa |

MainActivity/Manifest đã modified từ trước nên số modified entries không tăng; đây không có nghĩa hai file không được sửa bổ sung. Danh sách 13 untracked mới gồm 12 files ở C1 và báo cáo này. Không có entry ban đầu biến mất.

Đối chiếu hash trước/sau: chỉ hai file có sẵn ở C2 được đổi; **465 file cũ còn lại giữ nguyên SHA256**, không có file cũ bị xóa. G0 report, backend, dependencies/config, production Dart và tests cũ thuộc tập giữ nguyên. Baseline hash chỉ bao phủ Git tracked/untracked không bị ignore; build outputs/cache được tạo lại theo các lệnh được giao.

Branch vẫn auth-jwt-assignment. Không git reset/clean/checkout-discard/branch change/commit/push; không ghi SQL hoặc migration, không khởi chạy backend, không đọc/xuất secret/connection credentials. Không thay QR payload/GUID/snapshot, không publish bản đồ.

### G2. Lệnh kiểm tra an toàn

git status --short, git status --porcelain=v1 -uall, git branch --show-current, git ls-files --cached --others --exclude-standard, Get-FileHash SHA256; rg/Get-Content trên các integration points và G0; tìm AGENTS áp dụng; kiểm tra plan/report tồn tại. Chỉ AGENTS trong Figma reference tree, ngoài scope; không có AGENTS áp dụng vào các file Sprint.

Đã so sánh riêng body MainActivity trước/sau để xác nhận chỉ bổ sung sensor wiring, giữ nội dung AI/SAF hiện hữu. Test/build chỉ ghi generated outputs/logs trong build/cache, không ghi đè fixtures/map JSON/assets nguồn.

## H. Remaining Risks

| Rủi ro | Trạng thái / biện pháp |
|---|---|
| Thiếu Step Detector hoặc sensor OEM không hoạt động | Capability/registration/fallback có code và fake tests; cần máy thật để kiểm |
| Permission behavior/API/OEM/revoke | Explicit request/re-probe/native checks; dialog thật, process death và restart chưa thử |
| Latency | Giữ native timestamps và native delivery diagnostic; **chưa đo native→Dart end-to-end** hay latency thật |
| Event ordering/gaps | Gate theo sensor và generation; native overflow báo loss, không hứa lossless |
| Timestamp validity | Giữ int64; không wall-clock subtraction; frame/units rõ; clock reset/reboot trên máy thật cần gate |
| Lifecycle cleanup | Serial controls, callback fences, native cleanup và tests fake/race đạt; OEM/background/hot restart thực chưa thử |
| Battery | Worker lazy, foreground only, optional raw sensors và throttle; chưa đo pin |
| Shared engine channels | Provider có one-owner guard trong cùng Dart runtime; chưa kiểm multi-engine trên thiết bị |
| Hardware orientation | Chỉ device attitude, không travel direction; nhiễu từ/yaw drift chưa đo |
| Camera/SAF/preferences coexistence thực | Source cũ giữ nguyên + build và mock regression pass; cần smoke trên máy thật trước nghiệm thu native tổng thể |
| Cài APK probe | Cùng applicationId với app hiện tại; chưa cài, cần bảo vệ dữ liệu thiết bị test |

Không có claim cảm biến hoạt động trên điện thoại thật, số mét chính xác, nhận biết hướng đi hay lối đi an toàn.

## I. Sprint 2 Readiness

**CONDITIONAL GO cho chuẩn bị thiết kế Sprint 2; chưa GO nghiệm thu native sensor runtime hoặc bật live navigation.**

Đã có nền contract/codec/provider/fake/debug probe, automated tests và APK build để tiếp tục làm PDR khi qua device gate. Chưa có physical Android sensor evidence; cần ít nhất một máy có Detector + rotation source đăng ký và chạy thật, thử quyền/lifecycle/event quality. Nếu máy thiếu Detector, chỉ nghiệm thu capability/orientation path, không ghi Detector PASS.

Các prerequisite G0 còn nguyên cho Sprint 2:

- Tracking graph adapter giữ (server mapId, published version), stable floorKey/node/edge GUID và mapping sang int renderer. Không dùng RouteEdge.id phiên-local làm stable key.
- Geometry cho straight corridor đã khảo sát, interpolation theo mét; hành lang cong cần authoring trung gian hoặc thiết kế polyline riêng.
- Heading/map calibration và quan hệ phone orientation với travel direction; QR hiện chỉ neo vị trí/tầng.
- Policies cho uncertainty, stale orientation, ngã rẽ, đi ngược, QR correction và map-version mismatch.
- Lifecycle/route ownership khi tích hợp Navigation sau này, giữ manual/QR fallback.

Không thay schema, không xây adapter/engine/blue dot hoặc sửa Navigation ở Sprint này.

### Evidence references chính

- sensor_models.dart:6,86,129,255,308,343,381 — kind/model/codec/status/gate.
- sensor_provider.dart:8,20,25 — interface/factory/unsupported.
- android_sensor_provider.dart:9,124,199 — provider ownership/start/cleanup (line có thể dịch khi chỉnh format).
- sensor_session_controller.dart:22,297,305 — state/visibility/close.
- sensor_probe_page.dart:13 và tool/sensor_probe_main.dart:5 — debug page/entrypoint.
- AndroidSensorBridge.kt:28,157,245,310,316,325 — native registration/queue/lifecycle/permission/dispose.
- MainActivity.kt:174,179,184 — lifecycle/permission forward; Manifest ACTIVITY_RECOGNITION.
- Bốn files test mới ở C1 và logs ở E là bằng chứng automated; **không phải evidence vật lý**.
