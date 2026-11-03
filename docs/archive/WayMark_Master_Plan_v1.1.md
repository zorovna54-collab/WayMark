# WAYMARK — TÀI LIỆU ĐỊNH HƯỚNG GỐC (LIVING MASTER PLAN)

> **Phiên bản tài liệu:** 1.1  
> **Cập nhật:** 23/10/2026 (Asia/Ho_Chi_Minh)  
> **Mục đích:** Lưu giữ quyết định sản phẩm, kiến trúc và backlog đã thảo luận; tránh đổi định hướng hoặc làm lại phần đã có.  
> **Mức tin cậy:** Trạng thái mã nguồn và kiểm thử bên dưới dựa trên **báo cáo của Codex/Copilot/Kilo do người dùng chuyển lại**; tài liệu không tự xác nhận đã kiểm tra toàn bộ mã nguồn, cơ sở dữ liệu hoặc dịch vụ ngoài thực tế.

## 0. Quy ước duy trì tài liệu

- Đây là **nguồn tham chiếu định hướng** khi trao đổi WayMark trong các phiên tiếp theo. Mỗi thay đổi lớn phải cập nhật mục liên quan, trạng thái, nhật ký quyết định và ngày sửa.
- Phân biệt rõ **ĐÃ TRIỂN KHAI**, **ĐÃ THỬ THEO BÁO CÁO**, **CHƯA XÁC MINH**, **ĐÃ THỐNG NHẤT NHƯNG CHƯA TRIỂN KHAI**, **ĐANG CÂN NHẮC**.
- **Không tự viết prompt cho Codex/Copilot/Kilo Code** nếu người dùng chưa yêu cầu rõ ràng. Trước đó chỉ phân tích, hỏi/làm rõ khi thực sự cần và ghi quyết định vào tài liệu.
- Không mặc định ý tưởng đã thành code chỉ vì từng có prompt đề xuất.
- Không tự xóa/di chuyển/đổi dữ liệu SQL, không `git reset`, `git clean`, commit, push, migration hoặc thao tác phá hủy khi chưa được người dùng cho phép.
- Giữ nguyên dữ liệu legacy và bản demo ổn định khi mở rộng; ưu tiên thay đổi nhỏ, kiểm thử hồi quy.
- Nếu một bản copy được đặt trong repo, vị trí khuyến nghị: `D:\project\WayMark\docs\WayMark_Master_Plan.md`. Đường dẫn chỉ là **vị trí khuyến nghị**, chưa xác nhận đã được chép vào đó.
- Mọi bản cập nhật nên tăng version (1.1, 1.2...), thêm mục trong **Nhật ký cập nhật**, và giữ bản trước để đối chiếu.

## 1. Tầm nhìn sản phẩm

**WayMark là nền tảng dẫn đường trong nhà cho bệnh viện/cơ sở nhiều tầng dựa trên sơ đồ ảnh, Node/Edge, mốc nhận biết và mã QR.**

Luồng sản phẩm cuối cùng cần khép kín:

`Creator đăng ký/xác thực → tạo bản đồ Node-first → lưu bản nháp → kiểm tra/duyệt → xuất bản lên API/SQL → chọn Node để sinh/in QR → Visitor quét QR → lấy bản đồ đã xuất bản + vị trí Node → chọn đích → Route Preview → Navigation → quét lại QR để định vị lại / reroute.`

### 1.1 Nguyên tắc sản phẩm đã thống nhất

1. **Image-first:** nhập ảnh PNG/JPG sơ đồ có sẵn phòng, nhãn và hành lang; không bắt buộc vẽ lại các hình phòng đè lên ảnh.
2. **Node-first:** Node có thể là điểm đến **trực tiếp** (ví dụ Node tại cửa Phòng mổ, không cần tạo Room). Chỉ Node bật `searchableAsDestination` được tìm như điểm đến.
3. **Graph thật:** Node là vị trí, Edge là đường nối có hướng, khoảng cách theo mét và trạng thái hợp lệ; việc ảnh có một đường kẻ **không đủ** chứng minh người thực sự đi được.
4. **Room/Place legacy được giữ:** không bắt buộc cho bản đồ mới; có thể ẩn trong mục nâng cao để giữ tương thích cũ. Không xóa model hoặc dữ liệu cũ chỉ để đơn giản UI.
5. **Landmark:** biển hiệu, ghế chờ, quầy... là mốc để nhận biết; không tự suy ra lệnh rẽ từ một ghi chú tĩnh nếu hướng tiếp cận khác nhau.
6. **QR gắn chặt Node:** ít nhất một Node xuất phát có QR **trước khi bản đồ được xuất bản theo chế độ QR**; Node khác có QR hay không là tùy chọn.
7. **Creator/Visitor phân quyền:** Visitor xem bản đồ công khai và dẫn đường mà không cần đăng nhập; quyền sửa/xuất bản do backend cấp, không phụ thuộc vào việc sở hữu đường link hay QR.
8. **AI là trợ lý gợi ý:** AI đề xuất Node/Edge, người có quyền phải chỉnh/xác nhận; không tự công bố lối đi, khoảng cách hay tính tiếp cận chưa kiểm chứng.
9. **Đảm bảo demo offline với AI:** AI lỗi/LM Studio tắt không được làm hỏng bản đồ và local navigation đã được xác nhận.
10. **Ưu tiên kỹ thuật đã thống nhất:** QR ↔ Node ↔ API/SQL ↔ quyền sở hữu/xuất bản là hướng cốt lõi, quan trọng hơn mở rộng AI Phase 2 trước hạn báo cáo.
11. **Phân giai đoạn nguồn lực:** dùng Codex cho những công việc cốt lõi liên quan nhiều tầng kiến trúc, luồng end-to-end và nguy cơ regression; profile/settings/admin UI và nghiệp vụ phụ có thể tách thành phần nhỏ thực hiện sau bằng Copilot, Kilo, thủ công hoặc ChatGPT hỗ trợ chỉnh file/code.
12. **Không nhầm giao diện với chức năng:** button/screen xuất hiện không chứng minh backend và luồng bảo mật đã hoạt động; cần kiểm tra API, storage và test phân quyền thật.

## 2. Thông tin dự án và môi trường

- Workspace: `D:\project\WayMark`; Flutter: `D:\project\WayMark\waymark`; API: `D:\project\WayMark\WayMark.Api`.
- Stack: Flutter/Dart Android-first; ASP.NET Core API/JWT; SQL Server; LM Studio Vision AI trên máy Windows.
- API phát triển cũ: `http://localhost:5121` (Android Emulator gọi `http://10.0.2.2:5121/api` khi cấu hình phù hợp).
- LM Studio phát triển: Windows `http://127.0.0.1:1234/v1`; Android Emulator `http://10.0.2.2:1234/v1`; IP LAN trong một lần thử là `http://192.168.1.15:1234/v1` (**có thể thay đổi**).
- Vision Model đã thử theo Codex: `qwen/qwen3-vl-8b`.
- Những database đã từng được nhắc: `WayMarkDatabase`, `WayMarkAuthDatabase`. **Không giả định schema mới đã migrate hoặc production publish đã tồn tại.**
- Bản đồ local sử dụng dữ liệu **JSON v2/v3**; v3 hỗ trợ dự án nhiều tầng, dữ liệu legacy cần được đọc tiếp.
- Mục tiêu báo cáo: **Thứ Ba 27/10/2026**. Kế hoạch người dùng: tiếp tục code thứ Sáu 23 và thứ Bảy 24/10; làm slide Chủ nhật 25/10; rà soát/demo ngày 26/10.

## 3. Trạng thái kỹ thuật đã có (theo báo cáo tác nhân)

### 3.1 Local Builder / Navigation — ĐÃ TRIỂN KHAI THEO BÁO CÁO

- Chọn ảnh sơ đồ PNG/JPG, tạo graph trên mỗi tầng, Node/Edge có hướng và khoảng cách mét.
- Nhiều tầng, từng tầng có ảnh/graph riêng; khai báo nối tầng stairs/elevator, manual navigation/preview theo từng tầng; JSON v3 import/export, tương thích v2.
- Node có `displayName`, `searchableAsDestination`, `landmarkNote`; Node Editor sửa được 3 trường, JSON round-trip đã được test.
- Search phân biệt Room/Place và Node được đánh dấu; định tuyến trực tiếp tới Node không cần Room, cùng tầng và khác tầng.
- Landmark Note được hiển thị ở Node hiện tại và Node kế tiếp đúng `nodeId`/`floorId` theo báo cáo.
- Validation không còn bắt buộc Room nếu có Node đích; công cụ tạo Room thủ công đã chuyển sang **Nâng cao / Tương thích cũ**.
- N01/N02... thống nhất trên canvas/list/dropdown; UUID không làm nhãn chính; ảnh không bị che quá mức; nút thêm cạnh/đánh dấu điểm đến dễ tiếp cận hơn.
- Codex Node-first polish: `flutter analyze` sạch, **222 tests đạt / 1 skip**, Android debug build đạt; emulator G → I → II, không Room, Search → Preview → Navigation → quay lại Builder giữ dữ liệu.
- Lưu ý: N01/N02 là nhãn UI theo tầng, **không thay GUID thật hoặc khóa liên kết Edge**.

### 3.2 AI Map Assistant Phase 1 — ĐÃ TRIỂN KHAI THEO BÁO CÁO

- Provider abstraction, URL/model/token cấu hình; LM Studio API; giới hạn ảnh, timeout, validate schema/tọa độ.
- Trên Android Emulator đã thử Vision **thật** với model `qwen/qwen3-vl-8b`; đề xuất tên **KHOA NGOẠI** tọa độ chuẩn hóa `(0.770, 0.670)` từ ảnh sơ đồ.
- Giao diện duyệt: **Reject → Edit → Accept → xác nhận cuối**; thêm 1 Node, 0 Edge; giữ nguyên ảnh.
- Ảnh gửi model được giảm kích thước lớn nhất 768 px để tránh timeout; ảnh nguồn không bị thay đổi.
- `flutter analyze` sạch, **246 tests đạt / 1 skip**, debug APK đạt, `git diff --check` sạch.
- **Chưa thử** thiết bị Android vật lý/LAN hoặc xác thực token bắt buộc thực tế; tọa độ cần người quản trị kiểm tra.
- Tài liệu địa phương do Codex báo: `D:\project\WayMark\docs\AiMapAssistantPhase1.md` (không được xem trực tiếp trong tài liệu này).

### 3.3 Backend QR / Auth — CÓ NỀN TẢNG, CHƯA ĐỒNG BỘ VỚI LOCAL BUILDER

- Theo lịch sử kiểm thử người dùng, backend đã có JWT/QR scan → xác định vị trí → tìm Room → route preview → manual navigation → quét QR khác reroute; đã có lần test Android+API theo 8 kịch bản và báo đạt.
- Đã có nền tảng draft/save API và file storage; **chưa chứng minh** quy trình xuất bản Node-first v3 vào SQL + public download + quyền Creator end-to-end.
- Chưa xác minh chức năng sinh/tải/in QR theo Node local, email verification, quyền chủ bản đồ, xuất bản public giữa nhiều điện thoại.
- Phần demo QR backend và phần Builder Node-first có thể vẫn là **hai luồng riêng**. Việc hợp nhất là nhiệm vụ lớn nhất cần kiểm tra.

### 3.4 Giao diện Zoom/Pan — ĐANG CẦN CHỈNH; CHƯA TRIỂN KHAI PROMPT FIX ZOOM

- Có chế độ Zoom/Pan, người dùng nhận thấy Node và Edge bị **phóng to cùng ảnh**.
- Đã thống nhất yêu cầu chính xác tại mục 6; **chưa giao/hoàn thành prompt sửa**.

### 3.5 AI Phase 2 — CHƯA TRIỂN KHAI

- Từng thảo luận tự đề xuất Node giao thông/cửa/ngã rẽ/Edge trên sơ đồ, cùng bước duyệt; **người dùng chưa chạy prompt Phase 2**.
- Hiện chưa phải ưu tiên số một so với tích hợp QR–SQL–ownership.

## 4. Nghiệp vụ người tạo bản đồ (Creator)

### 4.1 Luồng mục tiêu

1. Đăng ký/đăng nhập; xác nhận email nếu muốn trở thành Creator.
2. Có thể tạo bản nháp bản đồ cá nhân; nếu công bố đại diện một cơ sở bệnh viện thật cần sự phê duyệt/quyền quản lý từ cơ sở hoặc admin.
3. Nhập ảnh từng tầng; tạo/chỉnh Node, Edge, nối tầng, Landmark. AI Vision chỉ gợi ý và người quản trị duyệt.
4. Thiết lập các Node đích được tìm kiếm, các Node bắt đầu và QR đặt ở vị trí thực tế.
5. Kiểm tra graph, đường đi, khoảng cách thực, điểm có thể tiếp cận và khả năng sử dụng.
6. **Lưu bản nháp lên server**, rồi gửi duyệt/xuất bản thành phiên bản công khai phù hợp; **không cho phép bản nháp đang sửa tự thay đổi tuyến của Visitor**.
7. Chọn Node được gắn QR; sinh QR, xem trước, tải ảnh QR để in, quản lý trạng thái đang hoạt động/thu hồi.
8. Sau cập nhật: version mới, kiểm tra ảnh hưởng đến QR và Node được tham chiếu, rồi xuất bản phiên bản mới.

### 4.2 Quy tắc tối thiểu để xuất bản map dùng QR

- Có ≥ 1 Node xuất phát **gắn QR**, được map đến Node hợp lệ trong phiên bản công bố.
- Có ít nhất một Node/Room đích tìm được và **tuyến hợp lệ từ điểm QR khởi đầu đến một điểm đến**, thay vì chỉ kiểm tra node tồn tại.
- Node/Edge ID ổn định, cấu trúc tầng, ảnh, đồ thị, transitions hợp lệ; không chấp nhận cạnh không có khoảng cách cần thiết hoặc sai hướng.
- Không khẳng định toàn bộ graph an toàn cho bệnh nhân chỉ vì pass schema/routing tests; vẫn cần nghiệm thu tại hiện trường.
- QR có trạng thái active/revoked và một cách xử lý rõ nếu Node/bản đồ không còn hợp lệ.

## 5. QR ↔ Node ↔ Map: đặc tả nghiệp vụ đã thống nhất

### 5.1 Mục tiêu

- QR gắn với **một vị trí vật lý**, ứng với một Node và tầng trong bản đồ công khai của một cơ sở.
- Không bắt buộc mọi Node có QR. Node tại cửa chính/quầy tiếp nhận/thang máy có thể có QR; Junction thông thường không cần.
- Quét QR phải giải được **bản đồ nào, tầng nào, Node xuất phát nào**, và không cấp quyền sửa.
- QR bổ sung dọc hành trình cho phép **xác nhận vị trí mới / reroute**.
- Người dùng không bắt buộc đăng nhập khi xem bản đồ công khai và dẫn đường.

### 5.2 Payload QR đề xuất

- Chứa URL với **token công khai khó đoán / QR public ID** do backend phân giải, ví dụ MINH HỌA `https://waymark.example/q/A7K29P` (domain này **chưa tồn tại/không phải link hoạt động**).
- Không nhúng JWT, API key, thông tin nhạy cảm, toàn bộ JSON graph hoặc đường dẫn nội bộ Windows.
- Backend giải token → record `QrLocation` → Map đã publish / version tương thích → `nodeId` / `floorId` → thông tin khởi hành.
- Không cần dịch vụ tạo QR bên ngoài; có thể render offline bằng Flutter thư viện QR phù hợp. Chưa chốt thư viện cụ thể.
- QR được in từ hình PNG/SVG/PDF nếu cần; tên vị trí, tầng, cơ sở là **nhãn in**, không nhất thiết chứa trong payload.

### 5.3 Quy tắc ổn định khi bản đồ thay đổi

- Quản lý ánh xạ QR sang Node thật bằng ID bất biến, **không** dùng thứ tự hiển thị N01/N02 làm khóa.
- Cần quyết định cách duy trì QR qua MapVersion: Node stable ID, version snapshot và remapping được kiểm duyệt; không tự trỏ QR sang Node khác nếu graph thay đổi.
- Xóa/di chuyển/đổi ý nghĩa Node có QR: cảnh báo, cần xác nhận, có thể thu hồi hoặc tái liên kết có kiểm toán.
- Trường hợp mã hết hiệu lực, bản đồ ẩn, bệnh viện dừng công bố: trả thông báo thân thiện; không điều hướng sai.

### 5.4 Visitor flow mục tiêu

1. Dùng camera/ứng dụng WayMark quét QR ở cửa chính.
2. Mở WayMark hoặc deep link/đường web tương thích (**chi tiết mở khi chưa cài app chưa chốt**).
3. API kiểm tra QR còn hiệu lực, map public, phiên bản phù hợp, trả floor/node hiện tại và graph phục vụ đọc.
4. Tìm destination theo tên, xem preview, bắt đầu navigation bằng Node-first shortest path.
5. Khi quét QR khác giữa đường: xác nhận thay đổi điểm xuất phát, xử lý ở cùng bản đồ/khác bản đồ, và tính lại tuyến theo quy tắc an toàn.
6. Mất mạng: có thể giữ bản đồ/route đã tải và thông báo trạng thái; không tự giả định vị trí mới chưa xác thực.

## 6. Zoom/Pan: trải nghiệm chuẩn đã thống nhất (CHƯA IMPLEMENT FIX)

**Tư tưởng:** Node cố định trong **hệ tọa độ ảnh**, không cố định ở **một pixel màn hình**.

Khi Zoom từ 1× lên 3×:

- Ảnh nền phóng 3× quanh tiêu điểm pinch; có thể pan để khám phá các vùng bị khuất.
- **Tọa độ tâm Node** biến đổi cùng ảnh; Node có thể ra ngoài viewport và bị cắt/ẩn tự nhiên.
- **Bán kính/đường kính hiển thị Node** giữ gần như không đổi theo pixel màn hình; nhãn/cỡ chữ cũng thế.
- **Hai đầu Edge** luôn bám vị trí Node biến đổi cùng ảnh. **Chiều dài Edge trên màn hình tăng/giảm** đúng theo hình học.
- **Độ dày nét Edge** giữ gần như không đổi theo pixel màn hình, không dày lên 3×.
- Route overlay tương tự: hình học scale theo ảnh, nét và nhãn điều hướng dễ đọc.
- Pan dịch chuyển khung nhìn, **không làm đổi tọa độ nguồn của Node**.
- Cho phép Node/Edge bị khuất ngoài viewport và **clip đúng phạm vi bản đồ**, không ép chúng luôn hiện trong màn hình.
- Hit-testing thêm/chọn/kéo Node chính xác ở mọi tỷ lệ; vùng chạm đủ lớn. Có Fit Image/reset; zoom theo tâm hai ngón.
- Không áp dụng `scale(1/zoom)` bừa bãi cho toàn bộ overlay khiến vị trí Node lệch; chỉ bù kích thước hoặc render theo hệ tọa độ màn hình đã biến đổi.
- Đã có **minh họa tương tác trong hội thoại** và người dùng xác nhận nó đúng hoàn toàn với ý tưởng.

**Trạng thái:** Chưa chạy prompt Fix Map Zoom; không coi đây là chức năng đã hoàn tất.

## 7. AI Map Assistant

### 7.1 Phase 1 — Có theo báo cáo

- Nhập ảnh đang chọn → gửi LM Studio Vision → phản hồi có cấu trúc về Node → validate → review vị trí trên ảnh → Accept/Edit/Reject → xác nhận cuối → thêm DraftNode.
- Không thay ảnh nguồn, không tạo Edge từ AI, không công bố graph chưa duyệt.

### 7.2 Phase 2 — Ý tưởng, chưa chạy prompt

- AI đề xuất Corridor/Junction/Entrance/Stairs/Elevator và Edge cùng tầng khi có căn cứ từ ảnh.
- Mỗi Node/Edge phải có định danh tạm, tọa độ chuẩn hóa, confidence/uncertainty, evidence và trạng thái review.
- Edge chỉ được chấp nhận khi điểm đầu/cuối tồn tại và đã được duyệt; không tự điền mét từ pixel; không tự kết luận giao nhau trên ảnh là thông được.
- Chưa tự nối tầng, chưa tự duyệt đường đi hoặc accessibility.
- **Ưu tiên hiện thời:** thấp hơn việc nối QR/Creator/SQL với graph thực.

### 7.3 Sự thật cần bảo toàn

- OCR hoặc Vision nhận ra nhãn "KHOA NGOẠI" không chứng minh vị trí đó là cửa tiếp cận.
- Mốc "ghế xanh", biển hiệu... chỉ hiển thị nếu người quản trị đã nhập/xác nhận hoặc AI được duyệt; không tưởng tượng landmark.
- Cần máy chạy model đủ RAM/VRAM; LM Studio chủ yếu là dev dependency, không bắt buộc có khi Visitor đi tìm đường.

## 8. Quyền truy cập và xác nhận email

| Vai trò | Xem map công khai | Tạo draft | Sửa draft của người khác | Công bố map cơ sở |
|---|---|---|---|---|
| Visitor / Guest | Có, không đăng nhập | Không | Không | Không |
| User | Có | Theo chính sách cấp quyền | Không | Không |
| Creator xác nhận email | Có | Có | Không trừ khi được mời | Không mặc định với cơ sở thật |
| Facility Admin / được ủy quyền | Có | Có | Theo membership | Có sau quy trình duyệt |
| System Admin | Có | Theo quyền quản trị | Có kiểm soát | Có kiểm soát |

- Xác thực email qua luồng đăng ký, email có link/token thời hạn và cơ chế chống lạm dụng nếu triển khai; **chưa xác minh đã có**.
- **Email verified ≠ được bệnh viện ủy quyền.** Phải xác minh chủ sở hữu/quyền quản lý bản đồ cơ sở trước khi công bố nhân danh bệnh viện.
- Các API CRUD/publish/QR revoke cần resource-based authorization: kiểm tra quyền thật với `mapId`/`facilityId`, không chỉ dựa trên vai trò/ẩn nút frontend.
- Creator không được chỉnh bản đồ của Creator khác nếu không có quyền membership. Quyền không do QR quyết định.
- Trường audit tối thiểu: `createdBy`, `updatedBy`, `publishedBy`, timestamp, version, action và trạng thái.
- Phân tách endpoint đọc public và endpoint quản trị có JWT; không để public trả draft hoặc thông tin riêng tư.

### 8.1 Backlog tài khoản, Profile, quên mật khẩu, Settings và quản trị hệ thống — THẢO LUẬN 23/10/2026

> **Trạng thái:** Các chức năng dưới đây là **nhu cầu sản phẩm/định hướng**, chưa được chứng minh đã triển khai. Người dùng báo giao diện Home có nút avatar và tab Cài đặt, nhưng nhiều nút/màn hình mới chỉ là vỏ UI, chưa thực hiện nghiệp vụ thật. Ảnh chụp xác nhận có nút avatar trên Home, không chứng minh luồng profile hoặc settings đã được nối.

**Profile và xác thực tài khoản (sau lõi QR/Publish):**
- Chạm avatar ở Home → màn hình Profile xem/sửa thông tin được phép (tên hiển thị, email, avatar nếu có, trạng thái xác thực email, vai trò hiện có), đăng xuất và quản lý phiên đăng nhập.
- Màn hình Login/Register cần **Quên mật khẩu** thật: gửi link/token đặt lại qua email nếu tài khoản đủ điều kiện; token một lần và hết hạn; không làm lộ email có tồn tại hay không; lưu hash mật khẩu đúng chuẩn backend; kiểm thử replay/rate limit.
- **Xác nhận email** phục vụ quyền nâng cấp Creator; không đánh đồng email verified với quyền đại diện bệnh viện. Nếu yêu cầu cấp quyền Creator, nêu trạng thái chờ, duyệt/từ chối rõ ràng.
- Phân biệt luồng sửa profile công khai với nghiệp vụ nhạy cảm như đổi email/mật khẩu và phân quyền; những nghiệp vụ nhạy cảm cần xác thực phù hợp.

**Cài đặt theo vai trò** (mục hiển thị chỉ mang tính dẫn đường UI; API backend là nơi quyết định quyền thực tế):
- **Visitor/User:** cài đặt ngôn ngữ/giao diện, khả năng tiếp cận, tuỳ chọn dẫn đường, quyền camera, thông báo (nếu có), quyền riêng tư, lịch sử hoạt động của chính mình, trợ giúp/đăng xuất; xem hồ sơ và trạng thái tài khoản.
- **Creator:** thêm mục **Bản đồ của tôi**, bản nháp/đã xuất bản, số lượng/quota lưu trữ, tài nguyên ảnh, quản lý QR theo Node, đồng sở hữu/cộng tác viên khi được cấp phép, lịch sử chỉnh sửa, cảnh báo publish/approval. Creator chỉ thấy/sửa map được phép quản lý.
- **Facility Admin:** quản lý các bản đồ thuộc cơ sở được ủy quyền, lời mời cộng tác viên, xuất bản/thu hồi QR theo quy trình duyệt; không tự có quyền cơ sở khác.
- **System Admin:** bảng quản trị tài khoản/roles, khóa hoặc cấm tài khoản theo chính sách, kiểm tra trạng thái hệ thống/API, dung lượng ảnh/map/quota, số lượt truy cập và sử dụng QR (dữ liệu tổng hợp phù hợp quyền riêng tư), audit logs, quản trị quyền và kiểm duyệt công bố. Cần thao tác có xác nhận, log và kiểm tra quyền máy chủ; tránh đưa thông tin nhạy cảm, vị trí cá nhân hoặc số liệu chưa đo vào dashboard.
- Tránh để tab Cài đặt là 'vỏ rỗng': mục chưa có backend nên ẩn hoặc đánh dấu **Chưa khả dụng**, không để nút giả tạo cảm giác thành công.

**An ninh/vận hành:**
- JWT/role không đủ nếu thiếu **resource-based authorization** theo `mapId`, `facilityId`, `userId` trên API; không bảo vệ chỉ bằng cách giấu nút trong Flutter.
- Admin có chức năng ban/suspend/unban nhưng phải được ghi audit, có lý do, quyền phù hợp, kiểm soát abuse và cơ chế tránh khóa nhầm/chặn truy cập vô cớ.
- Lưu lượng, storage/quota, truy cập phải lấy từ telemetry/log/backend có định nghĩa rõ, không dựng số liệu placeholder như dữ liệu thật. Xem xét retention, privacy, rate limits và việc dọn file mồ côi.
- Xác thực email/quên mật khẩu phụ thuộc SMTP/email provider thật, không mặc nhiên hoạt động trong demo LAN/offline.

**Ưu tiên và phân công đã thống nhất:**
- **Trước hạn báo cáo:** tập trung Codex vào QR ↔ Node ↔ Published Map ↔ SQL Server ↔ Creator/Visitor authorization; giữ bản Android stable làm phương án dự phòng.
- **Sau khi lõi khép kín hoặc khi có dư thời gian:** profile/avatar, forgot password, email flows, Settings theo vai trò, admin dashboard/quota/traffic/ban. Chia từng chức năng nhỏ, agent khác hoặc ChatGPT có thể sửa mã nguồn do người dùng cung cấp và trả lại bản vá/file; không kỳ vọng ChatGPT tự thay đổi ổ đĩa Windows nếu không được kết nối.
- Không triển khai hàng loạt màn hình khi API/quyền chưa sẵn sàng; ưu tiên từng luồng hoàn chỉnh có test và báo trạng thái đúng.

## 9. API, SQL Server, lưu trữ và xuất bản

### 9.1 Các thực thể/tables ĐỀ XUẤT (chưa chắc đã tồn tại)

- `Users`, `Roles`, `EmailVerificationTokens` (hoặc cơ chế auth hiện hữu tương đương).
- `Facilities` (cơ sở), `Maps`, `MapMemberships` / permission grants.
- `MapVersions` (Draft/Submitted/Published/Archived), `Floors`, `Nodes`, `Edges`, `FloorTransitions`.
- `QrLocations` (`publicQrId`, `mapId`, `stableNodeId`, `floorId`, status, createdBy, revokedAt, ...).
- `Assets`/metadata ảnh hoặc đường dẫn tới file storage; có thể lưu file thực tế do backend quản lý và metadata trong SQL.
- `AuditLogs` và cấu trúc duyệt công bố nếu cần.

**Lưu ý:** đây là mô hình logic, không phải chỉ thị tạo ngay các bảng trùng với schema hiện có. Phải đối chiếu backend/API, các migration và dữ liệu thật trước khi quyết định mở rộng.

### 9.2 Bản nháp và bản đã xuất bản

- Creator có thể edit draft, import/export JSON local.
- Nút **Publish** chỉ công bố snapshot đã validate và được phép công bố; Visitor luôn lấy snapshot published bất biến trong phiên, không thấy draft đang sửa.
- Backend lưu graph Node-first tương đương dữ liệu local đã duyệt, có quy trình map IDs / version IDs, lưu ảnh tầng tương ứng.
- Khi cập nhật công khai: tạo version kế tiếp; tránh làm mất route giữa chừng hoặc khiến mã QR trỏ sai.
- Cần giới hạn size ảnh, quyền tải file, cache/invalidation và kiểm soát tài nguyên.

### 9.3 Truy cập từ bệnh viện

- `localhost`, `10.0.2.2` là dev-specific; **không** làm QR công khai có thể dùng được trên điện thoại ngoài thực tế.
- Demo LAN cần host ASP.NET Core nghe IP phù hợp, Android và server kết nối mạng được, firewall đúng.
- Triển khai thật cần HTTPS/public DNS/domain ổn định, quyền truy cập server và chính sách bảo mật.
- Nếu muốn mở QR bằng camera điện thoại không cài app, cần quyết định web fallback/deep link/Universal Link/App Link, cách cài hoặc mở ứng dụng.

## 10. Ưu tiên công việc và độ rủi ro

> P0 = nền tảng giá trị sản phẩm/đảm bảo demo; P1 = rất hữu ích khi có thời gian; P2 = mở rộng. Các mục dưới đây là **backlog**, không phải cam kết đã code.

| ID | Ưu tiên | Hạng mục | Trạng thái | Tiêu chí đạt chính |
|---|---|---|---|---|
| QR-01 | P0 | Rà soát QR/backend scan hiện có và mapping QR→Node | Chưa xác minh end-to-end với Node-first | Quét QR xác định đúng Map/Floor/Node |
| PUB-01 | P0 | Local v3 → server draft → published read | Chưa xác minh/khả năng mới có nền tảng | Thiết bị khác tải bản đồ published mà không cần source local |
| QR-02 | P0 | Sinh, xem trước, tải/in QR cho một Node | Chưa xác minh | In QR và quét trở lại đúng node |
| QR-03 | P0 | Ít nhất 1 QR start khi publish | Chưa triển khai hoặc chưa xác minh | Bản đồ thiếu QR khởi đầu không được publish ở chế độ QR |
| QR-04 | P0 | QR visitor → Search → Preview → Navigation → reroute | Backend cũ có, chưa nối với Node-first public map | Demo đầu-cuối xuyên tầng, không Room |
| AUTH-01 | P0 | Chỉ chủ sở hữu/cộng tác viên được sửa map | Chưa xác minh | Forbidden trên server khi Creator B sửa map A |
| PUB-02 | P0 | Public map read không cần JWT; write đòi quyền | Chưa xác minh | Khách xem được nhưng không sửa được |
| ZOOM-01 | P1 | Zoom/Pan Node anchored + constant marker/line width | Đã thống nhất hành vi, chưa triển khai | Test 1x/2x/4x, kéo/nhấn đúng |
| PROF-01 | P1 sau lõi | Avatar Home → Profile, sửa thông tin/đăng xuất | Theo người dùng: UI chưa hoàn chỉnh; chưa xác minh API | Có dữ liệu thật, phân quyền và thao tác lưu được kiểm chứng |
| AUTH-03 | P1 sau lõi | Quên mật khẩu, reset qua email an toàn | Chưa xác minh | Reset token hạn dùng/một lần; không lộ tài khoản; email delivery đã thử |
| SET-01 | P1 sau lõi | Settings theo Visitor/User/Creator/Facility Admin | Hiện nhiều mục chỉ là UI; chưa xác minh thực tế | Mỗi vai trò thấy đúng mục, API từ chối truy cập sai quyền |
| ADMIN-01 | P1/P2 sau lõi | System Admin: tài khoản, khóa/ban, audit | Ý tưởng, chưa xác minh | Chỉ admin thao tác được; mỗi hành động có lý do/audit và kiểm tra quyền |
| ADMIN-02 | P2 sau lõi | Thống kê truy cập, QR usage, lưu lượng/storage/quota | Ý tưởng, chưa xác minh nguồn số liệu | Metrics có định nghĩa, nguồn dữ liệu và kiểm soát privacy |
| AUTH-02 | P1 | Đăng ký Creator + xác nhận email | Chưa xác minh | Xác thực email trước khi cấp Creator theo policy |
| PUB-03 | P1 | Facility ownership approval / publish review | Chưa triển khai/không rõ | Không ai tự công bố dưới tên bệnh viện |
| QR-05 | P1 | Quản lý thu hồi/tái gán QR và map version | Chưa triển khai/không rõ | QR cũ không định vị sai sau edit |
| MAP-01 | P1 | Tối ưu editor annotation, không vẽ room | Hướng chính đã có, còn UX refinements | Sử dụng thuận lợi trên Android |
| AI-02 | P2 | Vision đề xuất Node/Edge cùng tầng có review | Ý tưởng, chưa chạy prompt | Không tự ghi edge thiếu mét |
| EXT-01 | P2 | Google Maps hoặc API map khác | Chưa cần thiết | Chỉ triển khai nếu có use case cụ thể |

### 10.1 Trước ngày báo cáo 27/10/2026

- Người dùng dự định hoàn thiện code 23–24/10, làm slide Chủ nhật 25/10.
- **Không phá bản Node-first stable** đang có (AI phase1 + 246 tests theo báo cáo).
- Có thể thu hẹp demo public publishing nếu hạ tầng Internet chưa sẵn sàng; cần nói rõ demo là LAN/dev chứ không công bố Internet thật.
- Ưu tiên một luồng đã kiểm chứng bằng điện thoại hoặc Emulator: **Creator → publish → QR tại Node → Visitor scan → route đến Node khác**.
- Để dự phòng, vẫn giữ demo local navigation và file ảnh/video ngay cả khi server/email/AI không hoạt động tại buổi báo cáo.

## 11. Acceptance tests quan trọng cho kiến trúc QR cuối cùng

1. Creator A tạo bản đồ nhiều tầng có 0 Room nhưng có Node destinations và ít nhất một QR source.
2. Lưu draft lên server; trước khi publish, Visitor **không** đọc được draft.
3. Sau khi publish, Visitor không cần đăng nhập vẫn lấy được published map (đúng ảnh/graph/version).
4. Creator B không thể sửa, xóa, publish hoặc thu hồi QR của map A bằng cách đoán `mapId`.
5. Creator A chọn Node N01 tại cửa chính, tải/in QR; QR scan resolve đúng map/floor/stableNodeId.
6. Quét QR ở vị trí N01 rồi chọn Node đích "Phòng mổ"; route đúng và có Landmark tương ứng.
7. Quét QR N khác trên đường đi: cập nhật vị trí/tuyến; QR bị thu hồi hoặc không đúng map không định vị bừa.
8. JSON v2/v3 import/export không mất dữ liệu; Route cũ tới Room vẫn được nếu legacy map.
9. Mất mạng khi đang dẫn đường: không làm mất route hiện hữu; hiển thị lỗi truy cập đúng.
10. Cập nhật/thu hồi MapVersion hay Node gắn QR không khiến QR ngoài thực địa âm thầm trỏ đến vị trí sai.
11. Graph không hợp lệ (một chiều sai, không có đường, thiếu chuyển tầng, thiếu khoảng cách) không được xuất bản hoặc dẫn đường giả.
12. Xác thực Creator qua email (nếu triển khai): token hết hạn, dùng lại, sai email đều được xử lý; riêng quyền đại diện cơ sở phải xét độc lập.
13. Dùng Android Emulator `10.0.2.2` cho demo dev; dùng điện thoại thật phải thử mạng LAN/HTTPS tương ứng.

## 12. Những quyết định CHƯA CHỐT cần hỏi/định hướng sau

- QR có mở WayMark app bằng App Link/deep link và có web fallback nếu chưa cài? Hay chỉ hỗ trợ quét trong WayMark ở MVP?
- Một QR công khai có cố định phiên bản map hay tự luôn trỏ tới phiên bản mới nhất sau kiểm duyệt? Cơ chế remap Node ID?
- Creator cá nhân có được publish public map riêng hay luôn cần System Admin duyệt? Cơ sở bệnh viện xác nhận quyền quản lý bằng cách nào?
- Email provider nào để gửi verification (SMTP/transactional API)? Hạ tầng demo offline/LAN có xử lý được không?
- Map public thật đặt ở server nào, domain nào, chi phí/bảo mật ra sao? Có cần chỉ làm LAN demo lúc báo cáo?
- Cần hỗ trợ QR dạng ảnh PNG đơn lẻ, tờ nhãn in A4 nhiều mã, hay cả PDF?
- Khi đổi ảnh có crop/rotate: buộc hiệu chỉnh lại normalized coordinates hay sử dụng thuật toán quy đổi? Phải kiểm chứng Map ảnh–Node luôn khớp.
- Khoảng cách mét, lối đi xe lăn, giờ mở các khu vực, biển chỉ dẫn do ai khảo sát và duyệt?
- Có cần cho Visitor chọn vị trí bắt đầu thủ công nếu QR bị hỏng hoặc camera không có quyền?
- Xử lý quyền Creator với cơ sở nhiều người cùng làm, ai có quyền thu hồi QR/publish?

### 12.1 Các chi tiết tài khoản/cài đặt còn cần quyết định khi triển khai (KHÔNG cần trả lời ngay)

- Các loại tài khoản/role chính thức đang có trong backend và các màn hình Flutter tương ứng là gì? Có `Creator` hoặc `Admin` thực tế chưa?
- Đăng ký/đăng nhập hiện hỗ trợ email/password hay còn phương thức khác? Đang dùng ASP.NET Core Identity, JWT tự xây hay provider khác?
- Email delivery nào sẽ dùng cho xác nhận email và quên mật khẩu? Chỉ môi trường demo hay production?
- Ai có quyền duyệt Creator và ủy quyền đại diện một bệnh viện? Có cần Facility Admin khác System Admin?
- Profile cần trường nào có thể sửa, avatar lưu nơi nào, có cho đổi email hay không?
- Quota lưu trữ/người tạo bản đồ đo theo file, ảnh, tổng byte hay phiên bản? Ai được xem traffic chi tiết và giữ logs bao lâu?
- Chính sách ban/suspend, khiếu nại/khôi phục và quyền quản trị tài khoản do ai quyết định?

## 13. Tài liệu và bằng chứng đã được nhắc (đường dẫn trên máy người dùng)

**Đây là đường dẫn trong máy Windows của người dùng, không phải file có thể tải xuống từ tài liệu này.**

- Android polish evidence: `D:\project\WayMark\waymark\build\node-polish-evidence\builder.png`, `edge-dropdown.png`, `navigation.png`.
- AI Android review: `D:\project\WayMark\waymark\build\ai-map-evidence\android-review.png`.
- AI phase1 docs: `D:\project\WayMark\docs\AiMapAssistantPhase1.md`.
- Android debug APK: `D:\project\WayMark\waymark\build\app\outputs\flutter-apk\app-debug.apk`.
- Figma Make tham khảo: `https://www.figma.com/make/ca8paZh7LfyGO9Kpn2vRB3/WayMark-Navigation-App-Design`.

## 14. Nguyên tắc khi nhờ coding agent

- Chỉ tạo prompt khi người dùng nói rõ **"Tổng hợp thành prompt"**, **"Viết prompt cho Codex"** hoặc tương đương.
- Trước khi agent lập trình tính năng lớn: ưu tiên **read-only audit** trạng thái code/backend/schema để tránh làm lại hay phá API cũ; chỉ khi được giao mới thực thi.
- Tách nhiệm vụ vừa đủ nhỏ; có acceptance tests rõ; cho biết dữ liệu nào user test, dữ liệu nào fixture/mock.
- Không tự làm schema/migration hay chỉnh database sản xuất chỉ dựa trên thiết kế trong tài liệu.
- Không reset/clean Git; không commit/push nếu chưa xin phép; giữ các thay đổi chưa commit, assets, cấu hình nhạy cảm và local data.
- Mọi báo cáo hoàn thành cần nêu file đổi, lệnh test, APK, demo thực tế và giới hạn còn lại.

## 15. Nhật ký quyết định và cập nhật

| Ngày | Version | Ghi nhận |
|---|---|---|
| 23/10/2026 | 1.0 | Khởi tạo tài liệu gốc sau thảo luận QR–Node–SQL–Creator; ghi rõ Node-first, AI Phase1, Zoom/Pan chuẩn, AI Phase2 chưa chạy, định hướng xuất bản và phân quyền. |
| 23/10/2026 | 1.1 | Bổ sung backlog Profile/avatar, quên mật khẩu, email, Settings theo vai trò, Facility/System Admin, ban/audit, traffic/storage/quota và chiến lược dùng Codex cho lõi, agent khác cho phần nhỏ sau; ghi rõ trạng thái chưa xác minh và câu hỏi cần quyết định sau. |

### Mẫu bổ sung khi cập nhật tiếp

```text
Ngày:
Version mới:
Quyết định/ý tưởng được thêm hoặc thay đổi:
Lý do:
Ảnh hưởng tới tính năng/kiến trúc:
Trạng thái: Ý tưởng / Đã thống nhất / Đang làm / Đã test / Hoãn
Bằng chứng kiểm thử hoặc link tài liệu:
Các mục backlog/acceptance cần chỉnh:
```

---

**Điểm neo định hướng:** Không phát triển WayMark thành công cụ vẽ sơ đồ đơn thuần. Giá trị cốt lõi là **một người được cấp quyền công bố bản đồ bệnh viện có graph được kiểm tra, gắn QR với Node thật, và một Visitor chỉ cần quét QR là có thể được dẫn đường chính xác đến điểm cần tới**.
