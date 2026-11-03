# Published Pilot — runbook không USB

Ngày: 28/10/2026. Dùng cùng APK **WayMark Live Test Sprint 7** và báo cáo Sprint 7.
Đây là quy trình thử nghiệm; mọi kết quả điện thoại/server thực tế mặc định **NOT TESTED**.

Đối chiếu môi trường ngày 29/10/2026 và lệnh thực thi/approval/rollback chi tiết: [Published Pilot Execution Preflight](PublishedPilotExecutionPreflight20261029.md). Tài liệu đó ghi rõ các gate đã kiểm read-only và các bước điện thoại chưa thực hiện.

## 1. Chuẩn bị và mở checklist

- Cập nhật đúng APK package `com.example.waymark.livetest`, chữ ký tương thích; không gỡ app hoặc xóa data để vượt lỗi cài.
- Live Test Home → **Published Pilot • checklist & báo cáo (không USB)**: checklist vận hành không nối sensor. Trong Navigation → Live → Diagnostics có cùng toolkit nhưng nối số liệu phiên thật.
- Mỗi mục tự chọn **PASS / FAIL / NOT TESTED** sau quan sát. App không đánh PASS từ fixture/widget test, cũng không tự chạy HTTP probe.
- Không có mục tự chứng nhận accuracy. PASS do người thử khai báo vẫn được export là USER_REPORTED_NOT_INDEPENDENTLY_VERIFIED.

| Gate | Cách xác minh thực tế | Trạng thái ban đầu |
|---|---|---|
| APK cài/cập nhật | Mở đúng icon WayMark Live Test, không ảnh hưởng WayMark chính | NOT TESTED |
| API reachable | Điện thoại truy cập đúng endpoint test qua kết nối/TLS hợp lệ; HTTP trả lời chưa chứng minh QR/SQL đạt | NOT TESTED |
| QR resolver | Quét QR thật và được resolver chấp nhận; không dùng payload fixture | NOT TESTED |
| Map/version | Snapshot đúng map/version, không bị ghép phiên | NOT TESTED |
| Ảnh tầng | Ảnh từng tầng cần dùng tải/hiển thị được | NOT TESTED |
| Preflight | Xem blocker/warning/partial support; dữ liệu đủ không phải khảo sát thật | NOT TESTED |
| Guided setup | Xong 5 bước, vị trí QR/manual và heading/stride rõ ràng | NOT TESTED |
| Real Detector | Đi bộ và đối chiếu event count với bước đếm tay | NOT TESTED |
| Blue dot | Có movement khi nhận bước hợp lệ; đứng/quay không tự tạo displacement | NOT TESTED |
| QR correction | Quét cùng snapshot, pose/baseline đổi đúng; QR lỗi không cập nhật | NOT TESTED |
| Manual fallback | Quay manual, sensors dừng và checklist cũ tiếp tục dùng được | NOT TESTED |

## 2. Những gì cần có ở API

Source hiện tại:
- `launchSettings.json`: HTTP localhost:5121; HTTPS localhost:7199 và HTTP localhost:5121.
- Frontend chính nhận `WAYMARK_API_BASE_URL` lúc build; mặc định Android là `http://10.0.2.2:5121/api`, desktop/web là localhost. Live Test Published pilot nhận endpoint riêng qua ô nhập runtime, không cần đổi secrets/config backend.
- `WayMarkDbContext` và `AuthDbContext` đăng ký SQL Server qua cấu hình có tên `WayMarkDatabase` (migration history riêng). Đây là tên cấu hình source, không phải bằng chứng database hiện chạy hoặc đã provision; không chạy migration/seed trong toolkit.
- Public GET: `/api/public/qr/{token}`, `/api/public/maps/{mapId}/versions/{version}`, `/api/public/maps/{mapId}/versions/{version}/images/{assetId}`.
- `PublicMapsController` AllowAnonymous; admin/project/publish endpoints vẫn Authorize. Không tắt JWT/roles.
- `MapProjectService` đọc MapNodeQrs/MapPublications/MapPublicationImages/FloorMapImageAssets; cần SQL schema/dữ liệu Published đúng và runtime identity có quyền đọc thích hợp.
- Ảnh dùng IMapImageStorage/ManagedFileMapImageStorage và đường dẫn MapImages ngoài repository, được cấu hình/cho phép đọc bởi người quản lý. Không tạo kho ảnh/SQL mới trong pilot toolkit.
- CORS Development hiện chỉ cho browser origin loopback; E2E có policy riêng. CORS do browser thực thi, không phải cách sửa network cho native Android. [Microsoft CORS](https://learn.microsoft.com/en-us/aspnet/core/security/cors?view=aspnetcore-10.0)
- API có `UseHttpsRedirection`. Flutter public request đặt followRedirects=false; nhập endpoint HTTPS cuối cùng, không dựa vào HTTP redirect.
- Binding HTTPS cần certificate thích hợp. `--urls` không tự tạo certificate tin cậy trên điện thoại. [Microsoft Kestrel](https://learn.microsoft.com/en-gb/aspnet/core/fundamentals/servers/kestrel?view=aspnetcore-10.0)

Không copy connection strings, JWT, cert password, QR payload hoặc thư mục vật lý vào báo cáo gửi lại.

## 3. Kế hoạch LAN có kiểm soát — CHƯA THỰC THI

Mọi thao tác mở listener/firewall/binding thực tế ở mục này cần người dùng phê duyệt riêng. Sprint 7 chỉ viết hướng dẫn, không thực hiện.

1. Người quản lý chọn API/database/storage test đã được phép dùng, cùng mạng Wi-Fi tin cậy và chỉ định máy/điện thoại được truy cập. Không dùng production database làm nơi thử write/migration.
2. Ghi lại cấu hình và process hiện có; xác định cổng test chưa dùng, DNS/LAN address và thời hạn thử. Không xuất secrets khi ghi baseline.
3. Chuẩn bị HTTPS endpoint có certificate đúng hostname và chain được Android tin cậy theo cấu hình test được quản lý. Không dùng “accept all certificates”, `-k`, tắt TLS hoặc bỏ auth. Certificate localhost của PC không tự hợp lệ cho LAN IP/Android.
4. Sau khi được duyệt, người quản lý có thể chạy **một process riêng** với override binding tạm, ví dụ dưới đây. Đây là mẫu, phải thay placeholder và cấu hình certificate hợp lệ ngoài Git trước:
   ~~~powershell
   dotnet run --project .\WayMark.Api\WayMark.Api.csproj --no-launch-profile -- --environment Development --urls "https://<approved-LAN-IP>:<approved-test-port>"
   ~~~
   Dùng **IP LAN cụ thể để bind**, còn URL nhập trên điện thoại có thể dùng DNS đã duyệt trỏ tới IP đó và khớp SAN certificate. Hostname thông thường trong Kestrel URL có thể bind wildcard trên mọi interface; không dùng hostname để giới hạn interface. Mẫu trên chỉ đủ khi đã có default HTTPS certificate hợp lệ; preflight có phương án endpoint/certificate store tạm rõ ràng. Không dùng `0.0.0.0`, public IP hoặc tunnel/public hosting mặc định. [Kestrel endpoint binding](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/servers/kestrel/endpoints?view=aspnetcore-10.0)
5. Nếu cần rule firewall, quản trị viên chỉ cho đúng executable/cổng, Private profile và địa chỉ điện thoại/subnet test đã duyệt, với tên rule/timebox rõ ràng. Không tắt firewall/Windows security. Không sửa CORS sang allow-all để chữa TLS/network.
6. Kiểm endpoint bằng điện thoại trên kết nối thực tế. Browser/TLS reachable chỉ là gate network; tiếp tục quét QR trong app mới xác minh resolver, snapshot và images. Cài một CA vào user store hoặc chấp nhận certificate trong browser không tự chứng minh Flutter/Dart tin cậy certificate đó. Không sửa APK/trust hoặc bypass TLS để vượt gate.
7. **Hoàn nguyên:** dừng đúng process pilot đã tạo bằng Ctrl+C/recorded PID; không kill mọi process dotnet. Xóa đúng rule firewall pilot đã tạo, bỏ override chỉ thuộc pilot, phục hồi setting đã ghi nhận nếu đã thay đổi. Không gỡ trust/cert dùng chung hoặc xóa cert ngoài phạm vi. Giữ cấu hình API/SQL/data cũ nguyên vẹn.
8. Kiểm tra cổng pilot đã đóng và app chính vẫn hoạt động. Không delete/purge Published data hoặc image storage để “dọn test”.

Có thể dùng endpoint test riêng đã quản lý thay PC LAN; không tự mở API ra Internet. Nếu chưa có endpoint phù hợp, đánh gate **NOT TESTED**, tiếp tục Local Pilot/code.

## 4. Thử Local và Published

**Local:** Home → Local pilot → chọn đích → Live → hoàn tất guided setup. Sơ đồ synthetic không phải ground truth. Dùng để smoke sensors/UI/lifecycle, không gọi QR verified offline.

**Published:**
1. Nhập `https://<approved-host>/api` ở Live Test Home; không credentials/query/token. Localhost/127.0.0.1 trỏ điện thoại, 10.0.2.2 dành cho emulator.
2. Quét QR thật → Search → Preview → Navigation → Live. Đối chiếu Published version/start/images/partial support trong preflight.
3. Xác nhận vị trí qua QR hiện tại hoặc manual được gắn nhãn, cấp quyền/bật cảm biến, stride, geometry và hướng. Chỉ đối chiếu cạnh thật sự đã đo/thấy phù hợp.
4. Mở Diagnostics → toolkit, chọn phase → **Bắt đầu ghi nhận**. Thao tác này không bật sensor; nút Live hiện có mới điều khiển sensor.
5. Đi/dừng/quay theo ca, đếm bước tay, đo error trước QR. **Chốt số liệu** đóng cửa sổ báo cáo, không dừng sensor; dùng Pause nếu cần dừng thu.
6. Điền số đo và nhãn ghi chú. Copy report chủ động. Khi manual fallback, toolkit giữ snapshot cuối trong **Pilot report • phiên Live vừa đóng**; có thể đánh dấu gate fallback sau quan sát rồi copy.
7. Report/checklist chỉ ở RAM. Copy trước khi rời Navigation/đóng app hoặc mở phiên Live mới. Không có auto-upload/persist/History write.
8. Quét QR bị thu hồi/sai version/mất mạng trong môi trường được phép: giữ pose/snapshot, ghi error/recovery. Không sửa SQL để tạo ca lỗi.

## 5. Gửi lỗi

- Gửi JSON từ **Sao chép báo cáo thử nghiệm đã làm sạch** và mẫu đo riêng nếu cần.
- Report bỏ endpoint, token/JWT/password, raw map/node/edge IDs, tên vị trí và coordinate trace. Device chỉ manufacturer/model từ probe có giới hạn, không serial/user account.
- Ghi chú app chỉ là fixed tags; ghi điều kiện bổ sung trong mẫu Markdown sau khi tự bỏ thông tin cá nhân.
- Screenshot/recording chỉ do người dùng tự thực hiện và tự kiểm token/địa điểm/người khác trước khi gửi; app không ghi âm/quay màn hình.
- Detector event count khác accepted displacement observations. False step có thể đến từ detector khi lắc; chưa có filter chống lắc mới.
