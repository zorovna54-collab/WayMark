# WayMark — Sprint 6: Published Real-Map Live Navigation Readiness

Ngày: **28/10/2026 — Asia/Saigon**  
Workspace: `D:\project\WayMark`; Flutter: `waymark/`; branch giữ nguyên: `auth-jwt-assignment`  
Phạm vi: triển khai Flutter/read-only validation, Published preflight và QR/network readiness. Không nghiệm thu accuracy hoặc server/camera thật.

## A. Executive Summary

**Sprint 6 đạt IMPLEMENTATION COMPLETE và AUTOMATED PASS trong phạm vi đã giao.**

| Kết luận độc lập | Trạng thái / bằng chứng |
|---|---|
| **IMPLEMENTATION** | **COMPLETE**: validator read-only, preflight, tích hợp guided setup hiện có, lỗi QR/mạng có phân loại, APK riêng |
| **AUTOMATED** | **PASS**: 97 targeted; full suite 522 PASS / 4 SKIP; analyzer, format, diff, main/Live Test build, metadata/signature đạt |
| **PUBLISHED FLOW** | **TESTED WITH MOCKS/FIXTURES**: service loadQr qua MockClient và UI Search → Preview → Navigation → preflight → guided setup; không phải server/camera E2E thật |
| **ANDROID PHONE TEST** | APK Sprint 6 **chưa chạy/cài/cập nhật trên điện thoại trong phiên này**. Có user smoke Local Pilot ở bản trước; chưa có Published phone acceptance |
| **REAL-WORLD POSITIONING ACCURACY** | **NOT VERIFIED**: chưa đo sai số mét, heading/drift, false positives, battery hoặc xác minh hình học cơ sở thật |

Đã bổ sung:
- Báo cáo readiness gồm trạng thái dữ liệu, issues/reasonCode, phạm vi floor/node/edge nội bộ và suggestedAction.
- Phân biệt **eligibleByData** với **physicallySurveyed**; hai endpoints/mét nhập không được coi là khảo sát thực tế.
- Published preflight hiển thị version, ảnh tầng, start, số đoạn tuyến phù hợp và các đoạn manual/QR. Không hiển thị GUID kỹ thuật cho người dùng phổ thông.
- Bảo toàn provenance map/version lúc tải bằng binding một lần, phát hiện field publication bị gán lại mà snapshot không đổi.
- Lỗi endpoint/network/timeout/revoke/map/version/anchor/image được trình bày riêng; correction thất bại không đổi vị trí/snapshot.
- Khi route mới không thuộc snapshot đang dùng, dispose Live trước khi áp dụng route; giữ tuyến manual cũ và thông báo, thay vì che màn hình bằng route bị từ chối.

Không đổi SensorManager/StepDetector, PDR/stride/heading, 40-observation budget, matching/continuation policy, QR atomic correction hoặc lifecycle fencing.

## B. Published Map Integration Audit

### B1. Luồng và identity thực tế

~~~text
PublicMapEntryPage / ScannerPage
 → publicQrToken [WMQR1 hoặc /q/token; không đi theo host trên QR]
 → GET public/qr/{opaque token}
 → server mapId + published version + floorKey/node GUID
 → GET public/maps/{mapId}/versions/{version}
 → project() + từng ảnh đúng version + FloorPlanAsset.validate
 → LocalMapNavigation.fromProject [copy tách khỏi project/editor]
 → bindPublishedOrigin(mapId, version) [một lần, không JSON mới]
 → stableStartKey → Search khóa start → Preview → route
 → Navigation opt-in
 → TrackingGraph + MapReadinessInput từ snapshot riêng của phiên
 → MapReadinessValidator
 → blocked: giữ manual/QR; supported/partial: cùng LiveTrackingPanel 5 bước
 → StepDetector/PDR/matching/overlay hiện có

QR correction
 → pause/capture → resolver closure giữ id/version
 → validate membership → VerifiedTrackingAnchor(source=qr)
 → controller atomic reset / ticket+generation fencing hiện có
~~~

| Điểm audit | Kết quả và hành vi Sprint 6 |
|---|---|
| Server map/version | Dùng server mapId + published version, không thay bằng LocalMapProject.id. Getter publishedOrigin ghi nhận lúc load, khác field publication có thể gán lại |
| Stable GUID | floor/node/directed edge GUID giữ từ snapshot; không dùng RouteEdge.id phiên-local |
| UI identity | Readiness so node UI int/floor int, normalized point, endpoints/mét/type/active và graph key với bản snapshot đã pin |
| Draft isolation | Đọc trackingSnapshotBytes từ bản copy riêng của LocalMapNavigation; không đọc Builder draft đang chỉnh sửa |
| Floor image | Loader tải ảnh đúng version, validate bytes/mime/dimensions bằng codec. Adapter kiểm ảnh snapshot có metadata hợp lệ và image provider của tầng tương ứng |
| Tọa độ | Finite, normalized [0,1]; ảnh/aspect dùng cho projection/bearing, không biến pixel thành mét |
| Mét/hướng | distanceMeters finite >0; cạnh tường minh from→to, active; không tạo implicit reverse |
| Route/start | Phải thuộc đúng map owner và có stable membership; từng cặp route nodes phải có cạnh outgoing active |
| Multi-floor | Link đúng loại Stairs/Elevator, giữ floor endpoints; luôn yêu cầu xác nhận tầng mới, không eligible cho nội suy ngang |
| Pin consistency | So immutable loading origin, publication hiện tại và TrackingGraph. Sai version/identity → chặn Live, không tự tải/ghép version mới |
| QR source | Correction hợp lệ giữ source QR và confidence confirmedAtScan; manual và PDR không bị nâng thành verified |

Ảnh “sẵn sàng” ở đây là **đã tải/được loader decode và có provider**, chưa phải bằng chứng GPU/renderer trên điện thoại thật đã hiển thị. Lỗi ảnh khi load được báo trước Navigation; không giả map có ảnh để tiếp tục.

Dữ liệu server malformed có thể bị parser/loader hiện có từ chối trước khi có Navigation. Validator không bypass parser hoặc sửa IDs để biến snapshot lỗi thành hợp lệ. Tests rule độc lập có thể đưa typed input lỗi trực tiếp để kiểm từng reason.

### B2. Các chỗ Local Pilot có thể chạy nhưng Published chưa chạy

1. Endpoint chỉ nghe trên máy tính/localhost, không reachable từ điện thoại, hoặc TLS/camera permission chưa phù hợp.
2. QR không published/revoked/khác map hoặc version; không có quyền hợp lệ để đọc tài nguyên đã công khai.
3. Snapshot/ảnh không tải hoặc decode được, start không có trong version, GUID/reference không nhất quán.
4. Map có mét nhưng geometry thật cong/không phù hợp; cạnh không phải Corridor/Door hoặc có transition.
5. Sensor trên máy thật thiếu/permission denied; preflight dữ liệu không chứng minh sensor readiness.
6. Route khác owner hoặc metadata publication bị gán lại; Live phải chặn thay vì dùng identity trộn.

Sprint 6 làm rõ các trường hợp này; không tự khởi chạy server/SQL, cấu hình firewall hoặc tạo public hosting để biến chúng thành PASS.

## C. Readiness Validator Rules

Module: `waymark/lib/features/indoor_tracking/map_readiness.dart`.

- `MapReadinessInput`: immutable lists/records cho key, floors, nodes, directed edges, route và ownership. Adapter đọc raw JSON của bản snapshot đã nhận, không đi qua authoring mapper có thể sinh ID.
- `MapReadinessIssue`: level, reasonCode, message, suggestedAction; affected floor/node/edge chỉ là identity nội bộ.
- `EdgeReadiness`: eligibleByData, physicallySurveyed, reasonCode.
- `MapReadinessReport`: readyByData, level readyByData/warning/blocked, canStartLive, ordered route segments và eligibleRouteEdges.
- Validator chỉ đọc; không gọi HTTP, không ghi map/draft/backend hoặc persist survey flags.

| Rule | Reason chính | Tác động |
|---|---|---|
| Map GUID không rỗng/zero, version >0 | invalidMapIdentity | Block Live |
| Pin/current khác nhau | mapVersionMismatch | Block; mở lại hành trình |
| Tầng/GUID thiếu hoặc trùng global | floorsMissing, floorIdentity | Block |
| Node GUID/floor/normalized coordinates | nodeIdentity, nodeFloorMissing, nodeCoordinates | Block |
| Directed edge GUID, duplicate pair, endpoints/floor | edgeIdentity, duplicateDirection, edgeEndpointMissing | Block |
| Distance finite >0 | edgeDistance | Block; không tự đoán/sửa mét |
| Active state | edgeInactive | Không eligible; route dùng cạnh inactive bị block topology |
| Same-floor Corridor/Door + ảnh/aspect + endpoints khác nhau | readyByData hoặc floorImageMissing/unsupportedEdgeType/degenerateGeometry | Theo từng cạnh; có thể partial Live |
| Cross-floor type Stairs/Elevator | floorTransition / transitionType | Transition không eligible cho tracking ngang; sai loại là block |
| Route owner/start/membership/kết nối directed | routeStartOrIdentity, routeDisconnected | Block |
| Graph phần khác không reachable từ start | disconnectedGraph | Warning; không suy ra coverage đầy đủ |
| Không tạo graph hoặc snapshot/graph khác key/identity/geometry/UI mapping | trackingGraphUnavailable, snapshotGraphMismatch | Block |
| Không có đoạn tuyến eligible | noEligibleRouteEdges | Không bật Live trên route; manual/QR vẫn dùng được |
| Chưa đối chiếu thực địa | physicalSurveyRequired | Warning, yêu cầu xác nhận ở bước 4; không tự cấp chứng nhận |

**Ý nghĩa trạng thái:**
- `eligibleByData=true`: đủ dữ liệu kỹ thuật cho cạnh thẳng theo mô hình hiện có; không chứng minh đường đi thẳng/thông thoáng/đúng mét.
- `physicallySurveyed=true`: chỉ khi caller cung cấp xác nhận cạnh trong phiên. Đây là khai báo đối chiếu của người thử, không chứng nhận độc lập hoặc trạng thái backend.
- `readyByData=true`: toàn bộ đoạn route đủ dữ liệu cho Live ngang, không có blocker toàn phiên. Level vẫn có thể warning vì chưa đối chiếu thực tế hoặc có warning ngoài route.
- `canStartLive=true` với readyByData=false: chỉ một số đoạn phù hợp; UI phân biệt đoạn Live và đoạn manual/QR.
- Structural corruption chặn cả Live session, kể cả lỗi nằm ngoài route, vì graph hiện có không thể được tạo/đối chiếu an toàn. Không lọc bỏ lỗi để âm thầm “sửa” Published Map.

Giữ graph topology đầy đủ; các nhánh không eligible vẫn tồn tại để matcher không nhầm thành candidate duy nhất. Không dùng route recommendation làm bằng chứng vị trí. Cache ordered route report tránh duyệt lại toàn graph trên mỗi cập nhật UI.

## D. Guided Preflight UX

Published preflight xuất hiện khi người dùng bật Live, **trước khi bắt đầu thu cảm biến**:
- Snapshot đã tải, Published version đang pin.
- Ảnh sẵn sàng theo tầng và điểm bắt đầu.
- Số đoạn route đủ dữ liệu / tổng đoạn; không dùng tỷ lệ này làm coverage hoặc accuracy.
- Chi tiết từng đoạn: eligible nhưng chưa đối chiếu, đã khai báo đối chiếu trong phiên, hoặc phải manual/QR/confirm new floor.
- Sensor chưa kiểm tra/đang sẵn sàng; đi tiếp bước 2 để probe/permission/registration, không tự prompt quyền.
- Hướng dẫn 5 bước và nút quay về manual/QR.

Không tạo wizard Published thứ hai. `LiveTrackingPanel` Sprint 5 nhận readiness optional; Local Pilot giữ flow hiện có. Trong bước 4:
- Cạnh đủ dữ liệu có thể chọn, vẫn cần đối chiếu thực tế và alignment.
- Cạnh chưa phù hợp bị vô hiệu hóa và có lý do bằng tiếng Việt; không giấu nhánh khỏi tracking graph.
- Transition có thao tác xác nhận riêng, không nội suy ngang.
- Các thông số GUID/generation không đưa vào preflight phổ thông.

Khi blocked, không tạo IndoorTrackingController/provider subscription; checklist manual vẫn enabled. Khi đang Live mà route replacement không thuộc snapshot, dispose Live trước, giữ tuyến manual trước đó và hiện report/mô tả; body kiểm route đang được áp dụng thay vì route bị từ chối.

QR tải map ban đầu cung cấp start cho Search/Preview. Controller Live vẫn yêu cầu **xác nhận vị trí tại bước 1 bằng QR hiện tại hoặc manual**; không ngầm xem việc tải map là một anchor verified mới. Correction QR hợp lệ giữ provenance QR; estimated/manual không được nâng cấp.

### Hướng dẫn thử

**Local Pilot:** Cài/cập nhật APK → Local pilot → Navigation → Live → hoàn tất 5 bước như Sprint 5. Không cần API; không có QR server giả.

**Published Real-Map:**
1. Người dùng chuẩn bị endpoint test an toàn reachable từ điện thoại và Published map/QR thật. Nhập `http(s)://host/api` ở trang Live Test; không kèm credentials/query/token.
2. `localhost`/`127.0.0.1` trỏ điện thoại, không phải máy tính; `10.0.2.2` là địa chỉ đặc thù emulator. LAN/DNS/TLS phải do người dùng cấu hình phù hợp.
3. Mở guest QR → chọn điểm đến → Preview → Navigation → Live. Xem version/start/ảnh/chi tiết đoạn trong preflight.
4. Nếu blocked, dùng manual/QR hoặc mở lại snapshot phù hợp; không tick khảo sát để vượt structural error.
5. Nếu partial, chỉ dùng Live trên các đoạn đủ dữ liệu đã đối chiếu. Tầng mới hoặc đoạn không phù hợp dùng xác nhận/QR/manual.
6. Quét QR ở bước 1, chuẩn bị cảm biến/stride/hướng rồi bắt đầu. Thử correction cùng version, khác version, revoke/offline trong môi trường test do người dùng chuẩn bị.
7. Mở Diagnostics và sao chép bản đã làm sạch khi cần. Không gửi token hoặc screenshot chứa QR/địa điểm riêng tư.

Debug Manifest **đã có từ trước** cleartextTraffic=true cho development, main Manifest release giữ false. Sprint 6 không đổi Manifest/TLS/firewall/auth; endpoint hợp lệ về cú pháp chưa chứng minh mạng/server đang hoạt động.

## E. QR / Network Error Handling

`PublishedReadException` và helper allowlist chỉ trả mã/thông báo cố định, không xuất URL/QR payload/response title/exception raw.

| Trường hợp | Code đọc công khai / recovery |
|---|---|
| Endpoint sai scheme/host/port/path, có credentials/query/fragment | published_invalidEndpoint; sửa URL trước khi gửi request |
| Payload QR sai định dạng | published_invalidQr; quét/nhập lại |
| Không kết nối server | published_network; kiểm tra mạng/endpoint, giữ tuyến/pose |
| Timeout | published_timeout; thử lại sau; không áp dụng kết quả muộn |
| Server trả qr_revoked | published_qrRevoked; dùng QR khác/manual |
| QR chưa public/không tìm thấy/410 không có code cụ thể | published_qrUnavailable; đối chiếu với quản lý map |
| QR map khác | published_mapMismatch; không đổi phiên, mở hành trình khác rõ ràng |
| QR/snapshot version khác | published_versionMismatch; mở lại hành trình phù hợp |
| Node/floor đã mất hoặc không thuộc pin | published_anchorMissing; không cập nhật vị trí |
| Ảnh không tải/decode được | published_imageUnavailable; tải lại/liên hệ quản lý |
| Snapshot malformed/không hỗ trợ | published_snapshotInvalid; không tự sửa JSON |
| Camera denied | UI Scanner hiện có hướng dẫn quyền Android/Web, retry hoặc quay lại; không sửa SensorBridge/camera contract |
| Late reply sau pause/route replacement/dispose | Ticket/session fencing hiện có từ chối; không anchor mới |

Network exceptions của request vẫn giữ MapDraftApiException/status/code cho các consumer cũ; validation Published là FormatException subtype. Các private/write flows giữ cách xử lý hiện có; chỉ message timeout public GET được diễn đạt đúng là thao tác đọc.

QrRelocalization ánh xạ thành reasonCode đã làm sạch. Controller vẫn dùng transaction/reset/ticket logic cũ; panel lấy lỗi QR cụ thể để đưa hướng dẫn, giữ reason nội bộ phục vụ Diagnostics. Không giả verified khi offline, không follow host trong QR, không gửi JWT đến public reader hoặc tự đổi map/version.

## F. Source Files Created / Modified

Tất cả đường dẫn dưới có tiền tố `waymark/`.

| Tạo mới | Vai trò |
|---|---|
| `lib/features/indoor_tracking/map_readiness.dart` | Input/report/rules/read-only snapshot adapter |
| `lib/features/indoor_tracking/published_live_preflight.dart` | Published preflight tiếng Việt |
| `lib/services/published_read_failure.dart` | Endpoint validation và sanitized read errors |
| `test/fixtures/published_live_fixture.dart` | Published fixture tổng hợp, không dữ liệu riêng tư |
| `test/published_map_readiness_test.dart` | 20 rule tests |
| `test/published_live_integration_test.dart` | 15 service/UI/integration/error/lifecycle tests |

| Sửa thêm so với baseline Sprint 6 | Lý do |
|---|---|
| `lib/features/navigation/local_map_navigation.dart` | Published loading origin bound một lần, không serialization mới |
| `lib/services/published_map_api_service.dart` | Bind origin; lỗi public resolve/load/image/timeout rõ ràng |
| `lib/features/navigation/navigation_page.dart` | Gate bằng readiness, xử lý blocked/partial/route replacement và manual fallback |
| `lib/features/indoor_tracking/live_tracking_panel.dart` | Nhận report optional, dùng cùng stepper, vô hiệu hóa cạnh chưa phù hợp, hướng dẫn QR cụ thể |
| `lib/features/indoor_tracking/qr_relocalization.dart` | Sanitized typed read failure codes; không đổi atomic reset |
| `lib/features/indoor_tracking/tracking_guidance.dart` | Recovery text cho các QR failure codes |
| `lib/features/scanner/public_map_entry_page.dart` | Error text public reader nhất quán, không raw exception |
| `tool/live_test_main.dart` | Dùng chung endpoint validator thay điều kiện lặp |

Không sửa existing tests, Builder/AI/History, backend/DTO/SQL/auth, assets/maps, pubspec/Gradle/Manifest/signing. TrackingGraph, controller/PDR/matcher/native source giữ nguyên so với đầu Sprint 6.

## G. Tests, Analyzer, Build Results

**Kết quả lần chạy cuối sau sửa lỗi route replacement**, không cộng targeted vào full suite:

| Gate | Kết quả | Evidence tại `waymark/build/sprint6-evidence/` |
|---|---|---|
| Targeted 8 test files | **97 PASS / 0 FAIL** | targeted-tests.log |
| Full Flutter suite | **522 PASS / 4 SKIP / 0 FAIL** | full-tests.log: `+522 ~4: All tests passed!` |
| Analyzer | **No issues found** | analyze.log |
| Format 14 file Dart liên quan | **0 changed** | format.log |
| Git diff whitespace | **PASS** | git -c core.safecrlf=false diff --check |
| Main debug APK | **PASS — assembleDebug** | android-main-build.log |
| Live Test APK | **PASS — assembleLiveTestDebug** | android-livetest-build.log |
| Actual APK package/SDK/label/permissions | **PASS** | main-apk-badging.txt, livetest-apk-badging.txt |
| apksigner verify + so certificate Sprint 5 | **PASS — khớp** | sprint5-apk-signing.txt, sprint6-apk-signing.txt |
| Android Sprint 6 install/update/phone smoke | **NOT RUN** | Không ADB/cài/gỡ app |
| Server/SQL/camera Published E2E thật, accuracy/pin | **NOT VERIFIED** | Không khởi động/cấu hình server hoặc SQL write |

Bốn skip là điều kiện cũ của suite (live SQL/Vision/platform); không tắt tests để pass. Regression giữ QR scanner, Published, Builder, Search/Preview, manual/multifloor, Zoom/Pan, AI preferences/SAF và History trong phạm vi automated fixtures/mocks.

20 readiness tests gồm: input đầy đủ, read-only, survey không tự sinh, thiếu floor/image, zero/negative/NaN/infinite mét, duplicate floor/node/edge identity, pin/version lỗi, normalized coordinates/endpoints, reverse directed edge, inactive/implicit reverse, graph disconnect, transition, partial support, graph/UI mismatch, missing graph và invalid route/start.

15 integration tests gồm: endpoint sai, revoke/offline/timeout/wrong map/version/missing node/floor, valid QR provenance/late route response, ảnh hỏng, loading origin không bị đổi theo publication assignment, guest UI chain, blocked/manual, sensor unavailable và foreign route replacement. Body/rendering của route cũ vẫn hiển thị sau khi từ chối route mới.

Service tests dùng PublishedMapApiService thật với MockClient; UI chain dùng session đã load từ fixture qua adapter SessionApi để kiểm UI. Camera/native dùng mocks hoặc regression existing; không gọi đây là backend/camera E2E thật. Fake steps/resolver chỉ nằm dưới test, không thêm vào production entrypoint.

Lệnh chính từ `D:\project\WayMark\waymark`:

~~~powershell
dart format --output=none --set-exit-if-changed <14 file Dart liên quan>
flutter analyze --no-pub
flutter test --no-pub test/published_map_readiness_test.dart test/published_live_integration_test.dart test/published_map_test.dart test/qr_publish_hotfix_test.dart test/live_navigation_ui_test.dart test/live_tracking_controller_test.dart test/live_guided_setup_test.dart test/live_guided_replay_test.dart --reporter expanded
flutter test --no-pub --reporter expanded
flutter build apk --debug --no-pub
flutter build apk --debug --no-pub --flavor liveTest --target tool/live_test_main.dart --dart-define=WAYMARK_LIVE_TEST=true
~~~

Có Java native-access warning từ toolchain hiện có; build/signature verification exit thành công. Dùng JBR Android Studio hiện có để chạy apksigner.jar; không đổi JAVA_HOME toàn cục hoặc nâng SDK/Gradle/Kotlin.

## H. APK Metadata / Signing / Path

| Thuộc tính kiểm từ artifact | Giá trị |
|---|---|
| Exact APK | `D:\project\WayMark\waymark\build\live-navigation-artifacts\WayMark-Live-Test-Sprint6-20261028-debug.apk` |
| Package / label | `com.example.waymark.livetest` / **WayMark Live Test** |
| Version / variant / target | 1.0.0 / code 1; liveTestDebug; tool/live_test_main.dart |
| Kích thước | **187.707.544 bytes** (~187,71 MB, universal debug APK) |
| SHA256 APK | `0C4411CA5597B85E35B71795580D5CC4B22ADA4247D9A24570D640EA3A474CF9` |
| Certificate SHA256 | `8c15d5eb313223a87d82ef435a13307e74f8abf1a9da2e9dd8de9c21b0cf4df2` — **trùng artifact Sprint 5** |
| Android min/target/compile | **24 / 36 / 36** — tối thiểu Android 7.0 |
| ABI | arm64-v8a, armeabi-v7a, x86_64 |
| Permissions | INTERNET, CAMERA, ACTIVITY_RECOGNITION, ACCESS_NETWORK_STATE và permission nội bộ DYNAMIC_RECEIVER_NOT_EXPORTED của package test |

APK chính kiểm lại vẫn `com.example.waymark`, label waymark. Artifact Sprint 5 giữ nguyên, SHA256 vẫn `6EC453967314519E90FF8A14A36EFC8284F35DA5D52F3D0132C3BA0FC9B24D86`; không ghi đè bản bàn giao cũ.

**Cập nhật qua Google Drive, không USB:**
1. Người dùng tự chuyển đúng artifact Sprint 6 lên Drive cá nhân/phương thức tin cậy, tải hoàn chỉnh về Android và mở bằng Files. Agent chưa upload.
2. Chọn **Cập nhật WayMark Live Test**. Package và chữ ký của hai artifact local tương thích, không có migration hoặc lệnh xóa data. Cài đè hợp lệ theo cơ chế Android giữ sandbox app test; việc update trên điện thoại chưa được agent thử.
3. Không gỡ app, không xóa dữ liệu hoặc đổi signing để vượt lỗi cài. Nếu OS báo không tương thích, giữ bản hiện có và gửi thông báo để đối chiếu artifact/chữ ký đã cài.
4. Package WayMark chính khác nên APK này không nhắm vào app/data chính. Không cần USB debugging/root.
5. Sau cập nhật thử Local Pilot trước, rồi Published Real-Map theo D khi có endpoint/QR phù hợp. Anchor/stride/timeline vẫn theo phiên trong RAM như Sprint trước.

## I. Remaining Limitations

- Chưa có Published server/camera/Android real-map acceptance hoặc chứng nhận accuracy. User smoke Local Pilot bản trước không chứng minh Published E2E hoặc sai số mét.
- Readiness là lint/check dữ liệu, không survey engine, không chứng nhận tường/lối đi/accessibility/patient-use. `isMeasured` chỉ là dữ liệu nhập.
- Tải snapshot/ảnh lớn và copy JSON có chi phí bộ nhớ/khởi tạo; chưa benchmark trên nhiều model. Không validate lại toàn graph trên mỗi bước.
- Ảnh chưa tải/decode được chặn mở session mới ở loader. Không thể dùng manual cho map chưa có dữ liệu; hành trình đã tải trước đó không bị lỗi QR mới thay thế.
- Không wall mask/polyline, không xử lý mọi hành lang cong. Chỉ live các cạnh thẳng đã đối chiếu trong phạm vi hiện có.
- StepDetector false positives khi lắc, stride bias, phone–travel direction, drift và tư thế bỏ túi vẫn chưa được giải quyết bằng thuật toán mới. Không thay policy 40 bước hay tolerance/freshness.
- Cross-floor vẫn QR/manual, không floor inference hoặc interpolating hai ảnh.
- QR correction cần mạng, không push revoke realtime tới phiên offline; quét hợp lệ không chứng minh biển QR đặt đúng vị trí vật lý. Không tự ghép version mới.
- Field publication vẫn tồn tại để tương thích luồng hiện có; origin từ loader là readonly getter/bind một lần và preflight/controller phát hiện mismatch. Không đổi backend hoặc snapshot schema.
- Diagnostics chỉ xuất trạng thái/codes đã làm sạch theo thao tác; screenshot debug có thể chứa địa điểm, cần tự kiểm trước khi chia sẻ.

## J. Next Recommended Sprint

Ưu tiên một gói **Published pilot evidence & preparation**: chuẩn hóa bảng ghi lỗi preflight/recovery, mở rộng fixtures theo mẫu bản đồ thật đã ẩn dữ liệu riêng tư, và benchmark thời gian/bộ nhớ tải map/ảnh trên dữ liệu lớn. Đây là công việc code/data có thể tiếp tục mà không yêu cầu ADB ngay.

Khi người dùng thuận tiện thử thực tế, chọn một Published map có hành lang 10–20 m đo thật, ảnh đúng aspect, QR đầu/cuối cùng version và endpoint test reachable. Ghi model/OS, bước đếm tay/detector, error trước correction, trường hợp uncertain/revoke/offline và sanitized diagnostics. Dùng số liệu này trước khi đề xuất tăng budget, anti-shake filter hoặc heading/stride model mới.

## K. Change Safety

Baseline đầu Sprint 6: **359 status entries = 43 modified + 316 untracked**, SHA256 **502 file** tracked/untracked không bị ignore. Status/branch/hash đầy đủ lưu tại evidence ignored của Sprint 6 trước khi sửa.

Sau bàn giao: **366 entries = 43 modified + 323 untracked**, **509 file** trong tập kiểm. **494/502 file cũ giữ nguyên hash**; đúng **8 file** trong bảng modified ở F đổi hash; không mất file cũ; thêm **6 source/test + báo cáo này**. Tổng diff lớn của repository gồm nhiều thay đổi đã có từ trước, không nhận làm kết quả Sprint 6.

Không reset/clean/đổi branch/commit/push, không staging mới, không SQL write/migration/E2E, không thay auth/roles/QR payload/Published DTO, không sửa Builder/AI/History/maps/assets hoặc Windows security. Không tự mở server public, install/uninstall hoặc upload APK.

Báo cáo tạo mới sau khi kiểm chưa tồn tại; các báo cáo G0/Sprint 1/MVP/Sprint 5 giữ nguyên. Build/evidence/artifacts dưới `waymark/build/` bị ignore và không tính vào hash manifest Git.
