# WayMark — Final Acceptance Checklist

Ngày chuẩn bị: **31/10/2026 — Asia/Saigon**.
Dùng cho **một đợt nghiệm thu tổng thể sau code completion**; không yêu cầu thử ngay trong Cycle3.
Mọi kết quả người dùng dưới đây khởi tạo **NOT TESTED**. Build/test fixture không tự điền PASS.

Bản cần dùng: Main `com.example.waymark`; Live Test `com.example.waymark.livetest`. Exact APK/hash nằm ở báo cáo `WayMarkFullProductCompletionCycle3_20261031.md`, mục K. Đây là internal debug builds, chưa production-signed. Kiểm hash trước cài; giữ APK cũ để đối chiếu.

Thông tin phiên thử (ghi ở nơi riêng được phép): ngày/giờ, model/OEM, Android/API, APK filename/hash, người thử ẩn danh, case ID. Không đưa serial, mật khẩu/JWT, QR payload/token, full URL có token, connection string, database IDs hoặc bản đồ nhạy cảm vào bug report/screenshot công khai.

| Nhóm | Cần API/SQL runtime thật? | Cần Android thật? | Trạng thái ban đầu |
|---|---|---|---|
| A — Cài APK / UI | Không | Có cho acceptance cài đặt | NOT TESTED |
| B/C — Creator / Publish / QR | Có; test workspace được phép | Có cho nghiệm thu UI/native file | NOT TESTED |
| D — Published Visitor | Có + QR được phép + ảnh đúng version | Có cho camera E2E | NOT TESTED |
| E — Sensor Probe / Local Pilot | Không với Local Pilot/Probe | Có; emulator không chứng minh bước chân | NOT TESTED |
| F — QR correction / chuyển tầng | Có với Published; Local Pilot chỉ kiểm phần local | Có | NOT TESTED |
| G — History / account / recovery | Có với History/private API | Có cho nghiệm thu tổng thể | NOT TESTED |
| H — AI / Settings / network | Có cho real AI/profile; provider cần được phép | Có cho UI thực | NOT TESTED |
| I — Độ chính xác thực địa | Không bắt buộc API nếu Local Pilot bố trí đúng; Published cần API | Có + ground truth | NOT TESTED |
| J — Bug / diagnostics | Không bắt buộc | Thiết bị đang thử | NOT TESTED |

Đánh dấu từng ca PASS / FAIL / NOT TESTED, ghi thời gian và evidence riêng. Không coi “không crash” là PASS của độ chính xác. Khi prerequisite thiếu, ghi NOT TESTED và blocker; không bypass để đạt.

## A. Cài APK chính

**Preconditions:** Có APK Main Cycle3 đã kiểm SHA256; đủ dung lượng máy; được phép cài nội bộ. Nếu đang có app, package và signer phải khớp. Chuyển file qua phương thức nội bộ bạn đã cho phép; không cần USB và không upload công khai.

**Steps:**

1. Giữ bản cài cũ và dữ liệu; mở APK Main, chọn cập nhật nếu Android cho phép.
2. Nếu báo signature/package mismatch, dừng và ghi lỗi. Không uninstall/xóa dữ liệu để né mismatch.
3. Mở Main; quan sát Login và các nút Guest/Visitor, Local Builder. Thử Back và mở lại.
4. Chạy riêng Live Test; xác nhận tên app khác và hai app cùng tồn tại.

**Expected:** Cài/cập nhật thành công, đúng app/version, Main không mở thẳng Live Test debug home. Không tự cấp Admin, xóa draft hoặc History.

**Result:** NOT TESTED.  
**Evidence:** APK/hash/version, màn hình thông báo cài đặt đã che thông tin riêng; crash timestamp nếu có. Không gửi dữ liệu app.

## B. Creator → Builder → Save/Reload

**Preconditions:** API/SQL/image storage runtime được phép; tài khoản Creator hoặc quyền personal workspace hợp lệ; **workspace thử riêng**, không dùng map người khác. API endpoint cần reachable và được điện thoại tin cậy theo prerequisite D.

**Steps:**

1. Login tài khoản thử A; vào Settings/My Maps → tạo workspace.
2. Thêm PNG/JPG thử không nhạy cảm, tạo node đầu/đích và cạnh có hướng; nhập mét theo phép đo phù hợp. Với hành lang gấp khúc cần geometry đã author đúng, không tự coi hai đầu là đủ.
3. Thêm/sửa/xóa một node/cạnh thử; kiểm hướng và khoảng cách; lưu draft.
4. Rời/mở lại và đọc server, kiểm tên/tầng/graph/ảnh giữ đúng.
5. Chỉnh chưa lưu, Back → chọn Giữ lại; nội dung vẫn còn. Thử export JSON/PNG theo thao tác được phép; Cancel file save không được báo đã lưu.
6. Với app-file native acceptance, thử mở file JSON backup riêng và quay lại. Không import đè dữ liệu thật.

**Expected:** Save chỉ xác nhận sau thành công/readback; lỗi không làm mất local. Directed edge không mặc định có chiều ngược. GUID và project identity không đổi chỉ vì rename/reorder. Import/export cancellation giữ draft, không báo thành công giả.

**Result:** NOT TESTED.  
**Evidence:** Case/phase, status UI, lỗi đã redact, số node/cạnh trước/sau; không gửi file bản đồ riêng nếu chưa được phép.

## C. Publish bản đồ và QR

**Preconditions:** Test workspace đã lưu, có ảnh truy xuất được, node đích searchable, mét/edges/links hợp lệ, quyền publish do server xác định. Chỉ publish/revoke **dữ liệu thử được chủ map cho phép**.

**Steps:**

1. Trong Server/Publish/QR, đọc lại server; chọn node khởi đầu từ graph đã lưu.
2. Tạo QR cho saved version trước khi Publish theo flow hiện tại.
3. Xem cảnh báo chia sẻ công khai; Cancel một lần và kiểm chưa publish.
4. Xác nhận Publish test snapshot; kiểm QR được pin version.
5. Sửa draft riêng sau publish, chưa publish lần nữa; dùng QR cũ để kiểm snapshot cũ giữ nguyên.
6. Chỉ nếu được phép, revoke một QR thử riêng; resolve sau revoke phải thất bại và không cập nhật vị trí.

**Expected:** Không tự publish khi Save hoặc AI apply. QR trỏ stable node/floor đúng snapshot. Draft edits không đổi nội dung publication cũ. Revoke không bị mô tả là xóa mọi snapshot/phiên offline ngay lập tức.

**Result:** NOT TESTED.  
**Evidence:** Tên case và kết quả, version có thể ghi trong hồ sơ riêng; che toàn bộ QR/token/GUID trong screenshot chia sẻ.

## D. Visitor quét QR → Navigation

**Preconditions:** Published QR được phép; API/SQL/images đang chạy. Điện thoại cần **HTTPS endpoint có certificate được Android tin cậy**. PC `localhost` không phải endpoint của điện thoại. Thay network binding/firewall/DNS/certificate/tunnel cần phê duyệt riêng trước; không dùng `-k`, TrustAll, cleartext hoặc tắt auth/CORS để vượt lỗi.

**Steps:**

1. Từ Main Login → Visitor/public QR; không login vẫn mở được public entry.
2. Dùng QR test qua camera; kiểm start node và tầng. Thử Cancel camera và quay lại.
3. Tải ảnh/snapshot; tìm node/phòng đích → Preview → Navigation.
4. Pan/zoom/đổi tầng đang xem; kiểm node/đường nằm cùng ảnh và transform.
5. Xác nhận từng chặng bằng Manual hoặc QR hợp lệ. Finish bằng thao tác rõ ràng.
6. Với QR revoked/mismatch/version khác trong fixture được phép, kiểm thông báo đúng; không tự đổi pin của phiên.

**Expected:** Public reads không cần JWT. Không thay ảnh demo để che lỗi tải. TLS/network/API/SQL/image/QR failures phải phân loại đúng. Manual tiến độ là xác nhận của người dùng, không tự nhận là vị trí được sensor chứng thực.

**Result:** NOT TESTED.  
**Evidence:** Phase load/resolve/image/search/route, HTTP status nếu UI/diagnostics cung cấp an toàn, MIME/length nếu được phép kiểm riêng. Không gửi full request URL/token/map data.

## E. Sensor Probe / Local Pilot / Live Navigation

**Preconditions:** Android thật; được phép runtime activity recognition khi người dùng chủ động bật bước chân. Local Pilot không cần API nhưng là sơ đồ tổng hợp; chỉ thử trong hành lang an toàn đã bố trí đúng hình học/metres của pilot. Không sử dụng làm chỉ dẫn cấp cứu hoặc chứng nhận lối đi an toàn.

**Steps:**

1. Live Test → Sensor Probe; ghi capability sáu sensor, model/API và permission.
2. Thử deny quyền; app không crash, có fallback rõ. Chỉ cấp quyền khi người thử đồng ý; không ép grant bằng công cụ.
3. Start → đi/dừng/quay tại chỗ → Stop. Kiểm Detector count/counter raw/orientation frame; không cộng detector và counter hai lần.
4. Pause/resume hoặc background/foreground10 vòng; kiểm không tăng listener/event trùng. Stop/Back phải dừng collection.
5. Local Pilot → Navigation → opt-in Live; làm guided5 bước: anchor → sensor → stride → hành lang/hướng → start.
6. Đi thật rồi dừng; chỉ observation bước hợp lệ được tích phân. Xoay máy tại chỗ không tự tạo quãng đường nếu không có bước; nếu Android phát false steps, ghi evidence, không tự thêm heuristic.
7. Detector thiếu/permission denied/heading stale/geometry thiếu → giữ/uncertain/manual, không phát bước giả.

**Expected:** Sensor capability không đồng nghĩa accuracy. Live opt-in, estimated khác QR verified. Hướng điện thoại không mặc nhiên là hướng người đi. Không hoạt động background ngoài scope.

**Result:** NOT TESTED.  
**Evidence:** Sensor availability/vendor nếu thấy, grant/deny, count truth/detected, timestamps/generation và reason UI; diagnostics opt-in đã sanitize. Emulator không thay bước này.

## F. QR correction và chuyển tầng

**Preconditions:** Published phiên đã pin; QR thứ hai thuộc cùng map/version tại node/tầng được phép. Các transition được author rõ; thiết bị thật.

**Steps:**

1. Đang Live, mở scanner → Cancel; kiểm không replay bước cũ hoặc tự tăng tiến độ trong lúc scan.
2. Quét QR hợp lệ; correction reset estimator/baseline atomically tại anchor, không đoán heading từ QR.
3. Thử resolve trễ/lỗi mạng; không cập nhật pose cũ sau pause/route replacement/close.
4. Tại junction khó phân biệt, chọn nhánh rõ hoặc chuyển Manual. Không tự chọn route đích để che ambiguity.
5. Tại link cầu thang/thang máy, kiểm yêu cầu xác nhận/anchor tầng mới. Không nội suy giữa hai ảnh hoặc suy tầng từ bước.
6. Kiểm budget: cảnh báo gần32, không nhận movement thứ41 kể từ anchor; anchor xác nhận mới mới reset budget. Không cần cố đi ở nơi nguy hiểm để đạt số bước.
7. Estimated dot chạm destination vẫn chưa tự Finish/history Completed.

**Expected:** Không gộp QR khác map/version, không auto floor/arrival. Manual/QR fallback vẫn hoạt động. Tác vụ trễ không dịch pose mới hoặc hồi sinh controller đã đóng.

**Result:** NOT TESTED.  
**Evidence:** Trạng thái trước/sau correction, reason/quality, floor transition, route revision trong diagnostics sanitize; không QR payload.

## G. History / account switch / session recovery

**Preconditions:** A và B là tài khoản thử được phép, API thật cho History; draft chưa lưu của A. Không xóa History thật để thử.

**Steps:**

1. A hoàn tất hành trình explicit → History chỉ một session với đúng trạng thái/đích. Mở lại khi cần.
2. Mở dialog Save-before-leave, Publish, revoke, logout hoặc menu Studio; đổi phiên trong môi trường thử phù hợp rồi quay lại. Confirmation cũ phải bị vô hiệu hóa; không thực thi dưới B.
3. Khi session thực sự bị API từ chối401, kiểm Builder không tự pop/xóa RAM graph. Không sửa JWT secret hoặc validation để tạo lỗi.
4. Chọn đăng nhập lại đúng A → xác minh owner → đối chiếu server trước ghi. Không tự Save/Publish lại.
5. Login B → không thấy cache/draft riêng A và không được tự rebind. Không sync draft A vào workspace B.
6. Thử lỗi403/network: không được tự hiểu là logout/expired. Một response401 cũ của A không được logout B.
7. Rời recovery khi có nháp trong RAM phải có cảnh báo mất nội dung. Không coi recovery RAM là backup qua app restart.

**Expected:** Owner/session identity xuyên dialog/request/navigation. Timeout sau mutation có thể đã commit; cần reconcile, không retry mù. Guest/manual Navigation không bắt buộc có History.

**Result:** NOT TESTED.  
**Evidence:** Owner ký hiệu A/B, phase và số request/callback nếu thấy; không username/email/token thật trong report công khai.

## H. AI / Settings / lỗi mạng

**Preconditions:** Profile API thật cho dữ liệu tài khoản; AI provider/budget/config được phép nếu thử thật. Không tự tạo/chia sẻ API key. Có ảnh thử không nhạy cảm.

**Steps:**

1. Settings/Profile → load/update display name; Back/reopen; không nhận quyền chỉ vì UI.
2. AI Assistant → request suggestions → Review/Edit/Accept/Reject. Cancel/reject giữ draft; chỉ apply sau review, không auto Publish.
3. Thử timeout/cancel với cách thử đã được phép; response trễ không sửa state đã đóng.
4. Mất kết nối tạm trên thiết bị thử rồi quay lại; thông báo lỗi giữ draft/tuyến; retry là hành động người dùng.
5. Kiểm text scale2, 320px/landscape/keyboard; cuộn tới confirm/cancel và warning. Nếu dùng bàn phím/reader, kiểm focus order và nhãn profile/menu/Back.

**Expected:** Phân biệt backend error/network/TLS/permission/expired. Không spinner vô hạn hoặc data replacement giả. AI outage không chặn editing/manual flow.

**Result:** NOT TESTED.  
**Evidence:** Provider kiểu cấu hình không chứa secret, phase, elapsed time, message đã redact, layout screenshot đã che private data.

## I. Đo bước chân / quãng đường / sai số thực địa

**Preconditions:** Hành lang thẳng10–20m đo bằng thước, geometry/map version đúng; hai đầu có mốc quan sát. Ghi điều kiện cầm máy, người/máy ẩn danh, stride calibration. Không dùng mét fixture làm ground truth.

**Steps:**

1. Đề xuất2 người ×2 điện thoại; mỗi cặp5 lượt mỗi chiều. Nếu chỉ một máy, ghi rõ pilot nhỏ, không suy rộng OEM khác.
2. Mỗi lượt ghi steps truth bằng người quan sát/clicker; detector count, counter delta riêng; quãng đường thật và estimated trước khi sửa bằng QR.
3. Thử đi–dừng10s–đi, quay tại chỗ30s, đi ngược, thay cách cầm trong ca riêng. Ghi false steps/holds, không xóa lượt lỗi.
4. QR cuối chỉ correction sau khi ghi endpoint error và correction delta.
5. Ghi signed/absolute step error, distance bias, endpoint error và failed/incomplete rate theo model/người/case. Truth steps0 thì ghi false count, không chia0.
6. Battery thử riêng với duration/screen/rate tương đương; không suy từ một lượt đi ngắn.

**Expected:** Có raw case records và tổng hợp n/mean/median/min/max; p95 chỉ khi n đủ và nêu giới hạn. Không công bố “độ chính xác mét” từ replay/emulator/build hoặc chỉ chọn lượt tốt.

**Result:** NOT TESTED.  
**Evidence:** Bảng từng lượt, ground truth method, điều kiện cầm, map fixture identity lưu nơi riêng, diagnostics sanitize. Accuracy acceptance threshold cần chủ sản phẩm chốt dựa trên campaign, không tự invent PASS threshold.

## J. Ghi bug / screenshots / diagnostics

**Preconditions:** Người thử chủ động cho phép xuất bằng Pilot toolkit/Diagnostics. Không tự upload hoặc persist raw sensors/location.

**Steps:**

1. Ghi case ID, APK/hash, model/OS, steps tái hiện, expected/actual, tần suất.
2. Chụp màn hình/ghi thời gian; che QR, identifiers, personal info và private map content.
3. Trong panel Live/Pilot, chọn export/copy khi cần; kiểm dữ liệu trước khi chia sẻ.
4. Đánh dấu PASS/FAIL/NOT TESTED từng ca. Lưu cả lượt lỗi và blockers.
5. Gom báo cáo cho một đợt acceptance tổng thể; không suy chức năng chưa thử là PASS.

**Expected:** Bug đủ tái hiện, evidence tối thiểu cần thiết, phân loại rõ UI/API/SQL/storage/TLS/QR/sensor/accuracy. Không đưa secret/token vào kênh công khai.

**Result:** NOT TESTED.  
**Evidence template:**

| Trường | Nội dung cần điền |
|---|---|
| Case /time /APK hash | … |
| Model /Android /người thử ẩn danh | … |
| Preconditions đã đạt /thiếu | … |
| Steps /expected /actual | … |
| PASS /FAIL /NOT TESTED | NOT TESTED |
| Screenshot /diagnostics đã redact | … |
| Blocker /severity /tần suất | … |

## Exit record

- CODE-LEVEL result: tham chiếu báo cáo Cycle3, không dùng làm physical PASS.
- PHONE PUBLISHED E2E: **NOT TESTED**.
- SENSOR PHYSICAL ACCEPTANCE: **NOT TESTED**.
- FIELD ACCURACY: **NOT TESTED**.
- PRODUCTION SIGNING/DEPLOYMENT: **PENDING**, cần phê duyệt riêng.
- Final campaign decision /owner /date: **chưa điền**.

Nếu prerequisites hạ tầng chưa được duyệt, chỉ tiến hành các nhóm local độc lập. Không mở LAN/firewall/tunnel, bỏ TLS hoặc cấp SQL/auth permission để làm checklist đạt.
