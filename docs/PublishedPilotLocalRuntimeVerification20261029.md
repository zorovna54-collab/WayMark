# WayMark — Local API Runtime & Public Read Verification

Ngày thực hiện: **29/10/2026 — Asia/Saigon**  
Workspace: `D:\project\WayMark`  
Đầu vào: [Published Pilot Execution Preflight](PublishedPilotExecutionPreflight20261029.md), mục4C/4E, phân loại lỗi và rollback.  
Phạm vi thực thi: **chỉ `https://localhost:7199`**, không LAN/public endpoint.

**API khởi động thành công trên loopback. HTTPS bị chặn bởi certificate trust verification của Windows. Không có HTTP200, không thực hiện Published QR/snapshot/image request. API đã dừng và listener trở về baseline.**

| Kết luận bắt buộc | Kết quả | Bằng chứng / giới hạn |
|---|---|---|
| **LOCAL API STARTUP** | **PASS** | Application started, Development, process thực sự mở7199 trên hai loopback addresses |
| **LOCAL HTTPS TRANSPORT** | **BLOCKED** | Default certificate verification thất bại: `TrustFailure` / `AuthenticationException`; không nhận HTTP status |
| **PUBLIC QR READ** | **NOT TESTED** | HTTPS blocked; đồng thời **AUTHORIZED_QR_NOT_AVAILABLE** tại lúc bàn giao |
| **PUBLISHED SNAPSHOT/IMAGE READ** | **NOT TESTED** | Không có resolver/pin được xác minh và không tiếp tục HTTPS sau trust failure |
| **PHONE PUBLISHED E2E** | **NOT VERIFIED** | Không thao tác điện thoại/camera hoặc endpoint LAN |
| **FIELD ACCURACY** | **NOT VERIFIED** | Không có phép đo bước/mét/endpoint error mới |

## A. Environment và Git baseline

| Kiểm tra trước chạy | Kết quả thực tế |
|---|---|
| API project | `WayMark.Api/WayMark.Api.csproj`, target **net10.0** |
| SDK | **10.0.402** |
| Installed runtimes | Microsoft.AspNetCore.App **10.0.13**; Microsoft.NETCore.App **10.0.13** |
| Port7199 | **Không có listener** trước chạy |
| .NET/API process | Không có `dotnet.exe`/`WayMark.Api.exe` trong inventory ban đầu |
| Hosting overrides | Không có key hosting/Kestrel/Urls/E2E ngoài dự kiến trong JSON base/Development, user-secrets và environment đã kiểm |
| Development configuration | JWT key format/length hợp lệ, issuer/audience và named SQL connection có cấu hình; chỉ xuất boolean, không xuất giá trị |
| Restore assets | `WayMark.Api/obj/project.assets.json` tồn tại; dùng `--no-restore`, không chạy NuGet restore |
| Storage | Đã enable; root hiện có. Baseline SHA256 **19 file** trong `objects/staging/leases`, không xuất tên object/root vật lý |
| Dev certificate | `dotnet dev-certs https --check` tìm thấy valid development cert **CN=localhost**, hạn18/10/2026–18/10/2027 UTC; lệnh check này chưa chứng minh trust |
| Network | Profile hiện có Public giữ nguyên; không cần LAN binding/firewall change |
| Git branch | `auth-jwt-assignment`, giữ nguyên |
| Git baseline | **521 file** tracked/untracked không bị ignore; **378 status entries =43 modified +335 untracked**, không staged entries |

Đã lưu status đầy đủ và SHA256 baseline trong bộ nhớ phiên. Không đưa toàn bộ danh sách dirty có sẵn vào báo cáo để tránh nhận chúng là thay đổi của nhiệm vụ này.

Đọc lại startup/database registration: environment thường không gọi migration/seed/EnsureCreated, và không bật MapDraftE2E. Không có yêu cầu tạo dữ liệu mới để thử startup/transport. Bằng chứng SQL ONLINE/các bảng Published từ preflight trước **không được tính thành API SQL runtime PASS trong lượt này**.

## B. API startup result

Chạy API trong **terminal PTY riêng**, tại workspace, bằng đúng Windows identity hiện tại:

~~~powershell
dotnet run --project .\WayMark.Api\WayMark.Api.csproj --no-restore --no-launch-profile -- `
    --environment Development --urls https://localhost:7199 `
    --Logging:LogLevel:Default=None `
    --Logging:LogLevel:Microsoft.Hosting.Lifetime=Information
~~~

Hai override Logging chỉ thuộc process để giảm log và giữ thông báo startup/shutdown; không sửa file cấu hình. Category Microsoft có mức riêng trong cấu hình hiện có nên warning Kestrel vẫn hiển thị. Không có request QR nào để token đi vào request logs.

Bằng chứng runtime:

- `Application started. Press Ctrl+C to shut down.`
- `Hosting environment: Development`.
- `Now listening on: https://localhost:7199`.
- Process wrapper `dotnet.exe` **PID16300**; API child `WayMark.Api.exe` **PID19124**, quan hệ parent→child được kiểm.
- Lúc **12:43:56 Asia/Saigon**, API PID19124 có đúng hai TCP listeners:
  - `127.0.0.1:7199`.
  - `[::1]:7199`.
- Không có listener khác thuộc API owner PID; không thấy port HTTP5121 hoặc LAN/wildcard address do API này tạo.

**LOCAL API STARTUP: PASS.** Việc process khởi động không chứng minh SQL/ảnh đã được đọc.

## C. Loopback HTTPS/TLS result

Server phát warning Kestrel:

> The ASP.NET Core developer certificate is not trusted.

Sau đó thực hiện **một** HTTPS GET tới `/weatherforecast` bằng `System.Net.Http.HttpClient` trong PowerShell trên Windows:

- Certificate verification mặc định; kiểm tra callback toàn cục đang null, không gán validation callback.
- Không custom trust, không đổi protocol/cipher/trust store.
- `AllowAutoRedirect=false`, `UseCookies=false`, `UseProxy=false` để request đi trực tiếp loopback; không Authorization.
- Timeout15s, response buffer64KiB; không ghi response body ra file/log.

Kết quả lúc **12:44:21 Asia/Saigon**:

| Trường | Giá trị quan sát |
|---|---|
| Result | `TLS_VERIFICATION_BLOCKED` |
| HTTP status | **Không có** |
| Innermost exception | `System.Security.Authentication.AuthenticationException` |
| WebException status | **`TrustFailure`** |
| Exception chain | MethodInvocationException → HttpRequestException → WebException → AuthenticationException |
| Thời gian client attempt | **221ms**, không phải HTTP latency benchmark |
| Default certificate verification | Được giữ nguyên |

Phân loại: **TLS/certificate trust**, có warning tương ứng từ Kestrel và lỗi trust từ client. Không có bằng chứng để quy lỗi này cho SQL/storage hoặc Flutter.

Đã **dừng phần HTTPS ngay sau kết quả này** theo yêu cầu. Không retry bằng HTTP, client bỏ kiểm cert, `-k`, TrustAll, `--trust`, import certificate hoặc sửa certificate store. Không xác nhận TLS version/cipher vì phiên HTTPS chưa được chấp nhận.

## D. Actual HTTP transport result

**LOCAL HTTPS TRANSPORT: BLOCKED.**

`GET https://localhost:7199/weatherforecast` không nhận HTTP response vì TLS verification không thành công. Vì vậy:

- Không có HTTP200 để ghi PASS.
- Không có MIME/length/JSON response được xác minh.
- Listener TCP và Application started chỉ là bằng chứng startup/binding.
- `/weatherforecast` không gọi SQL theo source; ngay cả khi trả200 về sau cũng chỉ chứng minh transport/routing.

Không thử `/api`, Swagger, public QR hoặc public map để vượt gate TLS. Không có HTTP redirect được theo.

## E. Public QR resolver result

**PUBLIC QR READ: NOT TESTED.**

Hai gate độc lập:

1. **TLS_VERIFICATION_BLOCKED** như mụcC.
2. **AUTHORIZED_QR_NOT_AVAILABLE**: chưa được cung cấp đường dẫn file payload local đã được chủ bản đồ cho phép trong lượt này. Đã yêu cầu chỉ cung cấp đường dẫn, không gửi token/payload vào chat; tại lúc bàn giao chưa có đầu vào đó.

Không tìm token trong repository/fixtures/SQL hoặc clipboard để thay thế. Không SELECT token, không tạo/publish/revoke QR. Không dùng payload giả để tuyên bố public read hoạt động.

Không có resolver request, HTTP status hoặc sanitized QR error code thực tế. Danh sách6 active published QR trong báo cáo preflight trước chỉ là aggregate cũ, không phải quyền dùng một payload cụ thể.

## F. Pinned Snapshot và image GET results

**PUBLISHED SNAPSHOT/IMAGE READ: NOT TESTED.**

| Gate | Trạng thái |
|---|---|
| Resolver trả mapId/version/floor/node thật | NOT TESTED |
| GET đúng Published map/version | NOT TESTED |
| So sánh pin và node/floor membership | NOT TESTED |
| GET từng floor image theo Published version | NOT TESTED |
| MIME/length/metadata/hash validation qua API | NOT TESTED |
| Flutter image decode/camera/navigation | NOT VERIFIED |

Không có mapId/version/assetId được lấy ra cho phiên này. Không đọc nội dung bản đồ, không ghi response/map/QR ra disk. Chỉ hash bytes kho ảnh hiện có để kiểm invariant, không dùng hash inventory thay cho image HTTP validation.

## G. Runtime SQL/storage issues

**Chưa quan sát lỗi SQL/storage qua API runtime**, vì không có request đi đến data endpoints. Điều này không đồng nghĩa SQL/storage đã PASS.

- Startup thường không mở/validate toàn bộ SQL data/schema.
- Không chạy SQL query trong nhiệm vụ này; không migrate/seed/INSERT/UPDATE/DELETE/grant.
- Không gọi storage Inspect/Prepare/upload/acquire lease hoặc sửa ACL.
- `System.Data.SqlClient` read probe trong preflight trước khác Microsoft.Data.SqlClient/EF của API; giữ nguyên sự phân biệt đó.
- Default Encrypt giữa provider có thể khác; không thêm/sửa Encrypt/TrustServerCertificate hoặc connection string để vượt lỗi.
- Image filesystem baseline19 file còn nguyên hash sau chạy. API public binding/metadata/hash/read permissions vẫn chưa được exercise bằng GET.

Không cần và không thực hiện sửa quyền SQL, certificate SQL hoặc storage ACL trong phạm vi thử này.

## H. Process cleanup và invariant checks

Ngay sau TLS failure, gửi **Ctrl+C vào đúng terminal API đã tạo**:

- Có log `Application is shutting down...`.
- Terminal kết thúc với exit1 sau Ctrl+C chủ động; đây không phải kết luận build/startup fail.
- Kiểm tra lúc **12:44:29 Asia/Saigon**: PID19124 và wrapper PID16300 đều không còn.
- Port7199 không còn listener, đúng baseline ban đầu.
- Inventory toàn máy trước/sau đều24 TCP listeners; so sánh tuple **address +port +owner PID**: **0 thêm /0 mất**.
- Không còn dotnet/API process trong inventory sau; không kill các process khác.
- Network profile snapshot trước/sau giữ nguyên.

| Invariant | Kết quả cuối |
|---|---|
| File cũ tracked/untracked | **521/521 SHA256 giữ nguyên** |
| Git status cũ | Giữ toàn bộ378 entries; chỉ thêm báo cáo này |
| Git cuối | **522 file /379 entries =43 modified +336 untracked**; không staged entries |
| Branch | Giữ `auth-jwt-assignment` |
| Storage objects/staging/leases | **19/19 hash giữ nguyên**, không thêm/mất file trong tập được kiểm |
| APK Sprint7 | SHA256 giữ `87ADD1157E7115F9A86C678659DF666356B5FFE3F5555302B62D27DBE115663D` |
| Source/config/docs cũ | Không sửa, kể cả Preflight/Runbook cũ |
| Network/DNS/firewall/certificate/security | Không chạy thao tác thay đổi |
| SQL/data/QR | Không chạy SQL hoặc API mutation |
| Build outputs | `dotnet run --no-restore` có thể cập nhật bin/obj ignored; không xóa để cleanup |

Ngoại lệ ghi có chủ đích duy nhất trong source tree: **`docs/PublishedPilotLocalRuntimeVerification20261029.md`**. Không git reset/clean/stage/commit/push, không xóa data/cache/APK hoặc Git files. Không khẳng định hash kiểm soát mọi file ignored ngoài APK và tập storage được nêu.

## I. Những gate chưa thể thử

- Windows client chấp nhận certificate localhost bằng verification mặc định: **BLOCKED**.
- Public QR payload được phép và có đầu vào local an toàn: **AUTHORIZED_QR_NOT_AVAILABLE**.
- Resolver/snapshot/image read bằng API runtime identity: **NOT TESTED**.
- Publish readiness/geometry/đúng biển QR vật lý: **NOT VERIFIED**.
- Phone installation/TLS/camera/sensor/QR correction: **NOT VERIFIED**.
- Field accuracy/latency/battery: **NOT VERIFIED**.

Không đổi các gate này thành FAIL của data layer vì chưa exercise; cũng không đổi thành PASS từ startup/source review hoặc preflight aggregate.

## J. Quyết định tiếp theo cho Phone Published Pilot

**Giữ Phone Published Pilot ở trạng thái chưa đủ điều kiện thực thi.**

Việc tiếp theo cần chủ quản quyết định bên ngoài phạm vi lượt này:

1. Xử lý trust của endpoint localhost theo một phương án được duyệt riêng nếu muốn tiếp tục local HTTPS runtime test. Không tự trust/import/đổi cert từ nhiệm vụ này.
2. Cung cấp **đường dẫn** tới payload QR local đã được phép dùng; không gửi payload vào chat. Chỉ chạy4E sau khi gate HTTPS đã đạt.
3. Chạy lại cùng loopback flow, kiểm HTTP200 và public reads bằng runtime identity, rồi cleanup tương tự.
4. Endpoint HTTPS tin cậy cho điện thoại, phạm vi mạng và approval LAN vẫn là gate riêng trong Preflight. Trust được localhost trên PC không tự giải quyết LAN SAN/DNS/Android trust.

**Không có Published E2E PASS hoặc claim độ chính xác mới.** Lượt này nâng được **LOCAL API STARTUP → PASS**, xác định được blocker TLS thật và xác minh cleanup hoàn tất.

