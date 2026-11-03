# WayMark — Sprint 5: Guided Live Navigation UX & Observability Hardening

Ngày: **28/10/2026 — Asia/Saigon**  
Workspace: `D:\project\WayMark`; branch giữ nguyên: `auth-jwt-assignment`  
Căn cứ: báo cáo G0, Sprint 1, MVP Sprint 2–4 và yêu cầu Sprint 5. Không thay thế các báo cáo cũ.

## A. Executive Summary

**Sprint 5 đạt CODE COMPLETE và AUTOMATED PASS.** Đã build APK riêng cho người dùng cập nhật. Độ chính xác thực địa vẫn chưa được nghiệm thu.

| Loại bằng chứng | Kết luận |
|---|---|
| **CODE COMPLETE** | Guided setup 5 bước, hướng dẫn khôi phục, chuyển cạnh có điều kiện, junction choices, budget warning, diagnostics/timeline và replay tests đã triển khai |
| **AUTOMATED PASS** | Targeted 61 pass; full suite 487 pass / 4 skip; analyzer/format/diff checks, Android main/Live Test build, APK metadata và chữ ký đạt |
| **PHONE SMOKE EVIDENCE FROM USER** | Người dùng báo bản Live Test trước đã nhận bước trong Sensor Probe, Local Pilot có blue dot di chuyển khi đi thật, và dùng được sau khi hiểu cách xác nhận |
| **PHYSICAL ACCURACY STILL UNVERIFIED** | Chưa đo sai số mét, drift/heading/quay đầu, tỷ lệ false steps, battery hoặc Published QR E2E thực tế. APK Sprint 5 chưa được agent chạy trên điện thoại |

Người dùng cũng báo lắc điện thoại từng làm dot di chuyển. Đây là quan sát false positive cần thu thập tiếp; Sprint 5 **không** thêm ngưỡng gia tốc/bộ lọc chống lắc chưa có bằng chứng và không thay Android Step Detector.

Các cải tiến nhìn thấy:
- Chuẩn bị theo thứ tự vị trí → cảm biến → chiều dài bước → hành lang/hướng → bắt đầu.
- Khi dot giữ vị trí, có nguyên nhân tiếng Việt và thao tác tiếp theo, thay cho việc chỉ đọc reason code.
- Gần điểm giao tự mở bước chọn hành lang; nhãn/số lựa chọn theo graph, có đánh dấu tuyến gợi ý nhưng không ép chọn tuyến đó.
- Có thể tiếp tục qua nhiều đoạn khi candidate duy nhất, hướng mới đã hiệu chuẩn, geometry được đối chiếu và budget còn đủ. Các trường hợp khác yêu cầu xác nhận rõ.
- Thông tin generation/timestamps/edge ID/timeline chuyển vào Diagnostics ở debug build. Export chủ động, giới hạn bộ nhớ, không tự upload.

## B. Before/After UX

| Tình huống | Trước | Sau Sprint 5 |
|---|---|---|
| Bắt đầu | Nhiều điều khiển Node/Edge/stride/sensor chung một panel | Stepper 5 bước; bước cuối liệt kê điều kiện thiếu, không khởi động âm thầm khi chuẩn bị chưa xong |
| Vị trí thủ công/QR | Đã có source phân biệt nhưng thao tác khó hiểu | Ghi “điểm đang đứng”, tầng và thao tác xác nhận; thủ công không gọi là server verified |
| Sensor | Cần hiểu thứ tự permission/start | Có kiểm tra capability không prompt, cấp quyền rõ ràng, bật/tiếp tục; hướng dẫn Android Settings nếu quyền bị chặn |
| Hành lang tiếp theo | Có thể dừng tại Node ước lượng mà không hiểu nguyên nhân | Thông báo gần điểm giao, mở bước 4, chọn từ các outgoing edges thật; có lựa chọn ngoài route |
| Hướng cũ/không tin cậy | Reason kỹ thuật hoặc arrow từ estimate cũ | Hướng dẫn giữ máy/hiệu chuẩn; arrow ẩn khi observation không còn fresh; không tạo displacement để cập nhật UI |
| Gần/hết budget | Dừng sau nhiều bước, không giải thích trước | Cảnh báo từ observation 32, hiển thị số còn lại; tối đa 40 được xét, observation 41 giữ vị trí và yêu cầu re-anchor |
| Đích ước lượng | Có thể bị hiểu là đã đến/hoặc yêu cầu chọn cạnh quay lại | Thông báo rõ phải QR ở đích hoặc về manual để xác nhận hoàn tất; không tự finish |
| Chẩn đoán | Số liệu phẳng, một ít event code | Nhóm Sensor/PDR/Map Matching/Tracking, last transition/pause/hold reason, timeline có thời gian và generation |

### B1. Cách dùng luồng mới

1. Mở **WayMark Live Test → Local pilot**, chọn đích, mở Navigation và bật Live thử nghiệm. Published vẫn qua guest QR → Search → Preview → Navigation; cần API truy cập được.
2. **Xác nhận vị trí:** chọn đúng điểm/tầng đang đứng, bấm xác nhận thủ công; hoặc quét QR Published. Không dùng vị trí đoán để khai là đã được QR xác minh.
3. **Chuẩn bị cảm biến:** kiểm tra, cấp quyền nhận diện hoạt động nếu cần, bấm bật cảm biến. Thiếu StepDetector/denied vẫn có **Về manual / QR**.
4. **Hiệu chuẩn bước:** nhập mét/bước, hoặc quãng đo thật và bước đếm tay của phép đo liên tục. 0,70 m chỉ là gợi ý chưa đo; bấm xác nhận mới áp dụng. Lưu trong phiên.
5. **Chọn hướng:** chọn hành lang đang chuẩn bị đi, đối chiếu geometry/mét, hướng đỉnh điện thoại theo chiều hành lang, giữ gần nằm ngang. Có lựa chọn chiều thủ công thử nghiệm nếu orientation không tin cậy; trường hợp này không được dùng để chứng minh auto-transition.
6. **Bắt đầu:** bước cuối liệt kê điều kiện thiếu. Khi đủ, bấm bắt đầu; hướng được hiệu chuẩn tại thao tác đó, rồi UI thu gọn setup. Không cần hiểu GUID hoặc generation.
7. Muốn đi nhiều đoạn, có thể mở **Đối chiếu thêm hành lang trước khi đi** và chỉ đánh dấu các đoạn đã kiểm tra thực tế. Không đánh dấu hàng loạt chỉ để dot chạy liên tục.
8. Khi mơ hồ, panel mở bước 4. Số trên bản đồ tương ứng các hành lang cùng tầng trong danh sách. Chọn đúng hành lang, xác nhận geometry và hiệu chuẩn; lựa chọn hướng không đặt lại budget/anchor.
9. **Tạm dừng / Chuẩn bị tiếp tục** đưa về bước cảm biến. Nếu đã di chuyển trong lúc dừng, xác nhận lại điểm hoặc QR; nếu chưa đổi chỗ, dùng checkbox xác nhận tại chỗ rồi hiệu chuẩn lại.
10. Khi gần hết/hết budget, dùng **Xác nhận lại vị trí**. Tại cầu thang/thang máy, dùng thao tác chuyển tầng riêng và xác nhận điểm/tầng mới; không kéo dot giữa hai ảnh.

### B2. Khi nào tự tiếp tục, khi nào giữ vị trí?

Auto-transition chỉ diễn ra trên **một StepDetector hợp lệ tiếp theo**, sau khi đến endpoint theo ước lượng, với tất cả điều kiện:
- Cùng pinned map/version và sensor generation còn hợp lệ; Navigation đang active.
- Không có hard hold do overflow/budget; còn trong chính sách 40 movement observations.
- Có calibration hướng tương đối và observation mới/reliable; không dùng manual bearing để chứng minh nhánh.
- Toàn bộ outgoing graph sau xét hướng chỉ còn một candidate; không xét riêng route đến đích.
- Cạnh active, đúng chiều, cùng tầng, geometry eligible và đã được người thử đối chiếu/xác nhận.
- Matcher không phát hiện mơ hồ/geometry thiếu. Link chuyển tầng hoặc geometry chưa biết vẫn có thể ngăn tự chọn.

Phần dư ở endpoint không truyền sang nhánh tiếp theo; không tạo thêm bước. Node ở endpoint vẫn là **PDR / uncertain**, không reset anchor hoặc budget. Khi tự vào cạnh tiếp theo, source vẫn **PDR / estimated**. Chọn hành lang thủ công tại Node PDR cũng giữ nguồn PDR/chưa chắc chắn cho vị trí ban đầu, ghi event lựa chọn thủ công; không tự nâng thành manual anchor hoặc QR anchor.

Thiếu điều kiện → giữ vị trí và hướng dẫn chọn hành lang/QR/manual. Hướng cũ, heading conflict, geometry không phù hợp, floor transition, overflow, hết budget hoặc map/version đổi đều có hướng khôi phục. Không có dialog phát theo từng sample.

## C. Architecture Changes

Các đường dẫn sau có tiền tố `waymark/`.

### C1. Sửa 4 file đã có so với baseline Sprint 5

| File/class | Thay đổi có chủ đích |
|---|---|
| `lib/features/indoor_tracking/live_tracking_panel.dart` | Stepper 5 bước, validation trước start, recovery actions, junction labels, ước lượng còn lại theo route, budget warning, explicit arrival guidance, diagnostics debug-only |
| `lib/features/indoor_tracking/indoor_tracking_controller.dart` | Pre-confirm geometry, continuation guards, freshness presentation, route recommendation/remaining-distance chỉ phục vụ UI, sticky re-anchor requirement, bounded observability, pin/version defense |
| `lib/features/indoor_tracking/map_matching_engine.dart` | Thêm tham số source/confidence khi tạo đầu cạnh để giữ provenance của vị trí PDR sau lựa chọn thủ công. Không thay heuristic 36° hoặc thuật toán tích phân |
| `lib/features/indoor_tracking/blue_dot_overlay.dart` | Vẽ số/hint các outgoing corridors cùng tầng trong đúng scene; chỉ vẽ arrow khi controller cho phép hướng mới/calibrated/estimated |

### C2. Tạo mới 5 file source/test

| File | Vai trò |
|---|---|
| `lib/features/indoor_tracking/tracking_guidance.dart` | Mapping status/confidence/reason → tiếng Việt + recovery action; giữ code nội bộ |
| `lib/features/indoor_tracking/tracking_diagnostics.dart` | Immutable timeline event UTC/generation/event/reason và bounded queue |
| `test/support/live_tracking_replay.dart` | Test-only replay, fake provider, fake clock và graph local; không import từ `lib/` hoặc `tool/` |
| `test/live_guided_replay_test.dart` | 16 deterministic replay/policy/lifecycle/QR/version tests |
| `test/live_guided_setup_test.dart` | 5 widget tests setup/validation/junction/budget/fallback/arrival, có ca ở viewport 390×844 |

Báo cáo này là file mới thứ 6. Không sửa existing tests để làm kết quả đạt.

### C3. State, budget và freshness

~~~text
needsAnchor
  → explicit manual anchor hoặc valid Published QR
  → anchored
  → capability/permission + sensor start + stride
  → align selected actual corridor
  → tracking [PDR estimated]

endpoint estimated
  → next real step + unique full-graph candidate + trusted conditions
  → next edge estimated, SAME budget / NO new anchor
  hoặc → uncertain/junctionConfirmation → explicit corridor choice

overflow / >40 observations
  → uncertain + requiresAnchor [sticky across start/stride/alignment]
  → ONLY explicit valid manual/QR anchor clears counter/hold

pause / hidden route / app background / route replacement
  → collection stopped + uncertain pose
  → explicit sensors resume + position confirmation/alignment as appropriate

floorTransition
  → stop, retain from/target floor
  → explicit new-floor anchor

finish / dispose
  → stop subscriptions/timer/provider; old callbacks cannot mutate pose
~~~

- Giữ điều kiện cũ: `stepsSinceAnchor` tăng với movement observations, kiểm `>40`; tối đa 40 được xét tích phân, observation thứ 41 giữ vị trí. Có thể ít hơn 40 observations thực sự tạo displacement nếu matching giữ vị trí.
- Warning bắt đầu ở 32. Chọn cạnh, đổi stride, pause/start hoặc tự chạm Node không reset. Chỉ `_applyAnchor` từ thao tác manual hợp lệ hoặc QR đã validate reset.
- `requiresAnchor` giữ sau overflow/hết budget, chặn confirmEdge bỏ qua hold. Map/version thay đổi giữ pose, chặn motion/alignment/new anchor và hướng dẫn mở phiên snapshot phù hợp.
- Freshness cho UI/continuation tính độ cũ native receive−sensor timestamp trong cùng clock Android, cộng thời gian kể từ lúc nhận ở Dart. PDR vẫn dùng timestamp ns trước bước như cũ; không so trực tiếp DateTime với native timestamp.
- Timer 500 ms chỉ làm cũ trạng thái hướng/ẩn arrow khi không có samples; **không tạo bước, mét, position interpolation hoặc route progress**. Được cancel khi close.
- Route recommendation/ước lượng còn lại chỉ đọc route và pose hiện có. Ngoài route hoặc không ánh xạ được thì không hiện con số giả. Không dùng recommendation làm measurement/candidate prior.
- ManualNavigation/history arrival semantics giữ nguyên. Step không gọi confirmNext; estimated arrival chỉ đưa hướng dẫn QR/manual.

### C4. Diagnostics và timeline

Diagnostics chỉ hiện trong debug build, bao gồm APK Live Test bàn giao:
- **Sensor:** permission, detector registration, detected events, last accepted step ns, orientation freshness, overflow, inventory.
- **PDR:** stride, integrated distance ước lượng, alignment state, accepted/rejected movements.
- **Map Matching:** current edge/progress/candidate count, hold/ambiguity reason, confidence.
- **Tracking:** state/reason, last transition, pause reason, generation, re-anchor count/budget, QR correction/reroute, last error code.
- Timeline tối đa **96 events**, UI hiển thị tối đa 16 mới nhất; clipboard gồm timeline bounded. Có tracking start, manual/QR anchor, sensor start/resume, stride/heading, accepted detector step, rejected movement/reason, edge candidate/continuation, junction ambiguity/hold, QR accept/reject, pause/stop/dispose.
- Không log raw rotation/accel/gyro samples tần số cao. `stepAccepted` là detector sample được session nhận, không chứng minh bước chân vật lý đúng; `acceptedMovements` là matching đã tạo displacement.
- Timestamp timeline là UTC ghi nhận sự kiện tại client, tách native sample ns.
- Nút **Sao chép chẩn đoán đã làm sạch** mới đưa text vào clipboard. Không tự upload/network telemetry/persist.
- Export bỏ QR payload/token, JWT/password/URL, map/node/edge IDs, tên địa điểm, tọa độ và trace. Panel debug trên máy có thể chứa edge ID/progress; xem lại trước khi gửi screenshot.

## D. Tests

Kết quả dưới đây lấy từ **lần chạy cuối** sau thay đổi cuối cùng. Không cộng kết quả nhiều lần chạy.

| Kiểm tra | Kết quả | Evidence dưới `waymark/build/sprint5-evidence/` |
|---|---|---|
| Targeted 7 test files, gồm 40 tests MVP cũ + 21 mới | **61 PASS / 0 FAIL** | `targeted-tests.log` |
| Full Flutter suite | **487 PASS / 4 SKIP / 0 FAIL** | `full-tests.log`: `+487 ~4: All tests passed!` |
| Analyzer | **No issues found** | `analyze.log` |
| Format trên 9 file Dart sửa/tạo | **0 changed** ở check cuối | `format.log` |
| Git diff whitespace | **PASS** | `git -c core.safecrlf=false diff --check` |
| Main debug build | **PASS — assembleDebug** | `android-main-build.log` |
| Live Test debug build | **PASS — assembleLiveTestDebug** | `android-livetest-build.log` |
| aapt metadata | **PASS** | `main-apk-badging.txt`, `livetest-apk-badging.txt` |
| Signature verification và so cert bản cũ | **PASS — cùng certificate SHA256** | `previous-apk-signing.txt`, `new-apk-signing.txt` |
| Cài/cập nhật APK Sprint 5 trên điện thoại, native smoke mới | **NOT VERIFIED trong phiên này** | Không dùng ADB/cài/gỡ app |
| Physical accuracy/false positives/Published QR E2E thật | **Chưa nghiệm thu** | Có user smoke sơ bộ bản trước, chưa có bộ đo thực địa |

Bốn skip giữ các điều kiện suite sẵn có (live SQL/Vision/platform); không bật SQL E2E write và không tắt existing tests. Các regression Published QR/scanner/Builder/Search/Preview/manual/multifloor/zoom/AI preferences/SAF gateway/history nằm trong full suite với mocks/fixtures tương ứng; không gọi đó là native physical acceptance.

Replay bao phủ:
1. A→J→E qua candidate duy nhất đã xác nhận, source PDR/budget giữ nguyên.
2. Hai nhánh cùng hướng: hold, chọn nhánh ngoài route thủ công, không tạo anchor/reroute vô căn cứ.
3. Geometry kế tiếp chưa xác nhận hoặc chỉ có manual bearing: không auto-transition.
4. Reverse; đứng yên; quay máy không bước; duplicate Detector; Counter không double count.
5. Orientation stale: giữ point và ẩn arrow; presentation timer không displacement.
6. Warning 32, cho xét 40, hold 41; stride/pause/start/alignment không xóa budget.
7. 10 vòng pause/resume, late generation không replay.
8. QR correction với queued old generation; response sau route replacement không áp dụng.
9. Published version đổi bị fence; existing map replacement regression vẫn dispose controller.
10. Floor transition cần mốc tầng mới; overflow sticky hold; bounded sanitized timeline; cancel setup; absent/denied fallback.
11. Widget flow thật đi đủ 5 bước, thiếu điều kiện có message, junction options từ graph, budget recovery không reset âm thầm, explicit arrival/manual action.

Fake data chỉ ở `test/`. Fixture image decode chạy trên real event loop; test presentation timer dùng fake clock trong widget test, không sửa production behavior để khớp test.

Lệnh từ `D:\project\WayMark\waymark`:

~~~powershell
dart format --output=none --set-exit-if-changed <9 file Dart ở C1/C2>
flutter analyze --no-pub
flutter test --no-pub test/live_tracking_graph_test.dart test/live_pdr_matching_test.dart test/live_tracking_controller_test.dart test/live_navigation_ui_test.dart test/live_local_pilot_test.dart test/live_guided_replay_test.dart test/live_guided_setup_test.dart --reporter expanded
flutter test --no-pub --reporter expanded
flutter build apk --debug --no-pub
flutter build apk --debug --no-pub --flavor liveTest --target tool/live_test_main.dart --dart-define=WAYMARK_LIVE_TEST=true
~~~

Build có warning native-access Java/Gradle của môi trường nhưng exit thành công, không đổi toolchain. `apksigner.bat` ban đầu không thấy JAVA_HOME/PATH; đã dùng trực tiếp JBR của Android Studio hiện có để chạy `apksigner.jar`, không đổi biến môi trường toàn cục hoặc signing.

## E. APK

| Thuộc tính | Giá trị kiểm trực tiếp |
|---|---|
| Exact artifact | `D:\project\WayMark\waymark\build\live-navigation-artifacts\WayMark-Live-Test-Sprint5-20261028-debug.apk` |
| Package | `com.example.waymark.livetest` |
| Label / version | **WayMark Live Test**, `1.0.0` / code `1` |
| Flutter target / variant | `tool/live_test_main.dart` / `liveTestDebug`, define `WAYMARK_LIVE_TEST=true` |
| Kích thước | **187.675.352 bytes** (~187,68 MB; universal debug APK) |
| SHA256 file | `6EC453967314519E90FF8A14A36EFC8284F35DA5D52F3D0132C3BA0FC9B24D86` |
| min / target / compile SDK | **24 / 36 / 36** — tối thiểu Android 7.0 |
| ABI | arm64-v8a, armeabi-v7a, x86_64 |
| Permissions | INTERNET, CAMERA, ACTIVITY_RECOGNITION, ACCESS_NETWORK_STATE; permission nội bộ DYNAMIC_RECEIVER_NOT_EXPORTED của package test |
| Certificate SHA256 | `8c15d5eb313223a87d82ef435a13307e74f8abf1a9da2e9dd8de9c21b0cf4df2` — **khớp APK Live Test trước** |

APK main kiểm lại vẫn `com.example.waymark`, label `waymark`; không đổi package/signing/config Gradle/Manifest trong Sprint 5. Artifact test có tên riêng; APK cũ `WayMark-Live-Test-20261028-debug.apk` được giữ nguyên, SHA256 vẫn `24B6D14434B9D023E488EE1FAA7ADADF4829FB225E96356031F093488A65C7E5`.

**Cập nhật không cần USB:**
1. Người dùng tự chuyển đúng artifact qua Drive cá nhân/phương thức tin cậy, tải về Android và mở bằng Files. Agent chưa upload.
2. Chọn **Cập nhật** cho **WayMark Live Test**. Package và certificate của hai artifact local trùng nhau, không có migration/xóa dữ liệu app test. Theo cơ chế update Android, dữ liệu sandbox app test được giữ khi cài đè hợp lệ; việc cập nhật trên điện thoại **chưa được thử trong phiên này**.
3. Không gỡ WayMark chính hoặc Live Test, không xóa data để vượt lỗi cài. Nếu OS báo chữ ký/version/installer không tương thích, giữ app hiện có và gửi đúng thông báo để kiểm tra artifact đã cài; bản trên điện thoại có thể khác artifact local được so.
4. WayMark chính là package khác nên update này không nhắm vào sandbox app chính. Không thay signing hoặc tự uninstall/reinstall.
5. Sau mở app, thử luồng guided ở B1. Stride, anchor và timeline trong RAM theo phiên; đóng app/start lại không phải cơ chế lưu/replay vị trí.

## F. Remaining Limitations

- User smoke bản trước chứng minh bước và dot từng chạy trên một điện thoại theo báo cáo người dùng, chưa xác định model/OS/vendor, tỷ lệ count đúng hoặc sai số mét. Không suy rộng cho mọi thiết bị.
- Lắc máy có thể phát StepDetector false positive và làm estimate tiến. Không có filter chống lắc mới; cần phân biệt detector events với bước ground truth trước khi thay thuật toán.
- Phone orientation không đồng nghĩa travel direction. Đổi tay, bỏ túi, cầm lệch hoặc đi lùi nhưng giữ phone hướng cũ chưa được nhận biết đáng tin cậy. Manual direction luôn là giả định; không auto qua junction bằng giả định đó.
- Geometry chỉ hai endpoints, chưa wall mask/polyline. Người thử xác nhận đoạn thẳng không thay thế khảo sát bản đồ. Cạnh thiếu ảnh/geometry/loại hỗ trợ hoặc chuyển tầng không auto.
- Nhiều nhánh cùng hướng, heading chưa đủ mới, geometry chưa đối chiếu, hết budget/overflow đều có thể dừng. Không gỡ rào chắn để dot liên tục.
- Local pilot vẫn synthetic 10 m/đoạn, không phải cơ sở thật. Không lấy fixture meters làm ground truth khảo sát.
- Budget 40, heading freshness 1,5 s và tolerance 36° vẫn là policy/heuristic chưa được hiệu chỉnh theo số liệu thực địa. Timer chỉ phục vụ freshness UI; không có movement smoothing/timer displacement.
- QR Published cần endpoint/QR/version/map thật phù hợp; runtime E2E trên điện thoại chưa nghiệm thu. Không mở server/firewall, không thay auth, không giả QR khi offline.
- Arrival/manual checklist tiếp tục riêng với position estimate. Dot chạm đích không finish; QR hoặc manual flow hiện có quyết định.
- Diagnostics/export opt-in, bounded trong RAM; không có upload hoặc bộ thu trace vị trí. Khi cần screenshot phải tự tránh token/địa điểm riêng tư.
- APK debug lớn, chưa phải release tối ưu hoặc hệ thống định vị bệnh viện đã được chấp nhận.

## G. Next Recommendation

Có thể tiếp tục công việc code độc lập: chuẩn hóa mẫu bug report từ diagnostics v1, kiểm khả dụng/khả năng đọc UI với text scaling lớn hơn, và xây bộ fixture geometry/heading ambiguity phong phú hơn. Các thay đổi geometry schema hoặc thuật toán sensor mới cần công việc riêng có căn cứ.

Khi thuận tiện thử máy tiếp, ưu tiên thu số liệu cho đúng ba câu hỏi:
1. Với cùng stride đã xác nhận, mỗi lượt 10–20 m đo thật có bao nhiêu detector events so với bước đếm tay và endpoint error trước re-anchor?
2. Khi đứng yên/quay/lắc, có detector false positives hay chỉ vấn đề hướng/UX? Gửi timeline đã làm sạch và cách cầm, không gửi QR token.
3. Tại J, candidate/geometry/heading/budget nào đang giữ vị trí? Kiểm các recovery actions mới có giúp đi tiếp mà không phải đoán quy trình không?

Đây là bước thu bằng chứng khi người dùng sẵn sàng, không phải điều kiện phải kết nối ADB trước khi tiếp tục phát triển. Chưa đề xuất thay StepDetector bằng ngưỡng accelerometer, tăng budget hoặc đưa route recommendation vào matching.

## H. Change Safety

- Baseline trước sửa: **353 status entries = 43 modified + 310 untracked**, **496 file** Git tracked/untracked không bị ignore; giữ đầy đủ status/branch/SHA256 tại evidence ignored của Sprint 5.
- Sau bàn giao: **359 entries = 43 modified + 316 untracked**, **502 file**. **492/496 file cũ giữ nguyên hash**, đúng **4 file** ở C1 thay đổi; không mất file cũ; thêm 5 source/test và báo cáo này.
- Không sửa PDR Engine, SensorProvider/Session/AndroidSensorBridge, NavigationPage, Builder, AI, History, QR services/token/schema, Published snapshot/GUID, backend/SQL/auth, assets/map data, pubspec/lock hoặc Gradle/Manifest/signing.
- Không reset/clean/đổi branch/commit/push, không migration/SQL write/E2E, không đổi Windows security, không tự install/uninstall/upload. Không có file staged mới.
- Báo cáo tạo sau khi xác nhận chưa tồn tại; các báo cáo G0/Sprint 1/MVP giữ nguyên. Build/evidence/artifact nằm dưới `waymark/build/` bị ignore, không tính vào hash manifest Git.
- Toàn bộ delta nêu trên tính từ baseline đầu Sprint 5, không nhận các modified/untracked từ Sprint trước làm thay đổi mới.
