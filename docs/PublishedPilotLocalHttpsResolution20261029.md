# WayMark — Local HTTPS Trust Resolution & Runtime Recheck

Chẩn đoán ban đầu: **29/10/2026 — Asia/Saigon**; cập nhật sau phê duyệt: **30/10/2026**.  
Workspace: `D:\project\WayMark`  
Đầu vào: [Local Runtime Verification](PublishedPilotLocalRuntimeVerification20261029.md).

**Đã hoàn tất trust theo phê duyệt ngày30/10/2026. Chứng chỉ giữ đúng identity; API chỉ bind loopback, TLS mặc định thành công và GET `/weatherforecast` trả HTTP200. API đã dừng; trust được giữ lại theo yêu cầu.**

**Gate hiện tại: `LOCAL_DEV_CERT_TRUST_RESOLVED`.** Kết quả thực thi ngày30/10 ở mục6–8; mục2–5 giữ lịch sử chẩn đoán/kế hoạch ngày29/10 và không phải trạng thái trust hiện tại.

## 1. Gates hiện tại

| Gate | Trạng thái | Bằng chứng / giới hạn |
|---|---|---|
| **LOCAL CERTIFICATE TRUST** | **PASS** | Trust command exit0; `--check --trust` exit0; chỉ thêm đúng thumbprint vào CurrentUser\Root |
| **LOCAL API STARTUP** | **PASS** | Runtime ngày30/10, API PID8052 chỉ có hai loopback listeners7199 |
| **LOCAL HTTPS HTTP RESPONSE** | **PASS** | TLS peer khớp cert đã duyệt; GET weatherforecast HTTP200 qua verification mặc định |
| **PUBLISHED QR READ** | **NOT TESTED** | HTTPS đã PASS; chưa có file payload được phép: `AUTHORIZED_QR_NOT_AVAILABLE` |
| **SNAPSHOT/IMAGE READ** | **NOT TESTED** | Chưa có resolver/pin hợp lệ cho phiên này |
| **PHONE PUBLISHED E2E** | **NOT TESTED / NOT VERIFIED** | Không chạy trên điện thoại |
| **FIELD ACCURACY** | **NOT TESTED / NOT VERIFIED** | Không có phép đo thực địa |

Các PASS trên là bằng chứng runtime ngày30/10, không suy ra Published data read hoặc nghiệm thu điện thoại.

## 2. Read-only diagnosis — lịch sử ngày29/10

Đã chạy:

~~~powershell
dotnet dev-certs https --check --trust
dotnet dev-certs https --help
~~~

Help của SDK cục bộ xác nhận `--check` không thực hiện thay đổi; kết hợp `--check --trust` chỉ kiểm có certificate và có trust. Lệnh kiểm trả **exit7**, thông báo có **1 certificate**, không certificate nào trusted. Không chạy `dotnet dev-certs https --trust` riêng.

Public metadata đọc từ Windows certificate stores:

| Thuộc tính | Kết quả |
|---|---|
| Store chứa cert | **CurrentUser\My** |
| Thumbprint SHA-1 định danh certificate | **`CC2373AF077AADF1722A14404B74C67CF6D97BCE`** |
| Subject / Issuer | `CN=localhost` / `CN=localhost` |
| ASP.NET Core Development marker | Có extension OID `1.3.6.1.4.1.311.84.1.1` |
| Validity | 18/10/2026–18/10/2027; **ValidNow=true** |
| Server Authentication EKU | Có, OID `1.3.6.1.5.5.7.3.1` |
| Basic constraints | **End Entity** |
| Private key | `HasPrivateKey=true`; chỉ đọc boolean, không mở/export key |
| Signature algorithm | SHA256 with RSA, OID `1.2.840.113549.1.1.11` |
| SAN | `localhost`, `*.dev.localhost`, `*.dev.internal`, `host.docker.internal`, `host.containers.internal`, `127.0.0.1`, `::1` |
| Cùng thumbprint trong CurrentUser\Root | **Không có** |
| Cùng thumbprint trong CurrentUser\CA | **Không có** |
| Cùng thumbprint trong LocalMachine\Root | **Không có** |

Phân biệt nguyên nhân:

- **Expired:** không; certificate còn hạn tại thời điểm kiểm.
- **Hostname mismatch của candidate đối với `https://localhost:7199`:** metadata không cho thấy mismatch, vì SAN có `localhost`.
- **Trust missing:** xác nhận bằng CLI check, vị trí store và lỗi TrustFailure của lần runtime trước.
- **Certificate mismatch với Kestrel thực tế:** **chưa xác minh bằng peer certificate**. API đang tắt và port7199 trống. Không bật API trước gate phê duyệt để thực hiện các bước post-trust.
- Không có Kestrel/hosting override trong JSON base/Development/user-secrets hoặc environment được kiểm. Có đúng một valid ASP.NET Development candidate do CLI tìm thấy; đây là cơ sở dự kiến lựa chọn default, không thay cho quan sát certificate server thực sự phục vụ.

Không export certificate/private key, không đọc/xuất secrets hay credentials.

## 3. Kế hoạch trust ngày29/10 — đã được duyệt và thực thi ngày30/10

**Lệnh được đề xuất ngày29/10; đã thực thi ngày30/10 theo phê duyệt mới:**

~~~powershell
dotnet dev-certs https --trust
~~~

Đối tượng dự kiến: certificate Development `CN=localhost`, thumbprint **`CC2373AF077AADF1722A14404B74C67CF6D97BCE`** đang có trong CurrentUser\My.

Phạm vi: thêm trust cho certificate hiện có trong Windows của **user hiện tại**, dự kiến có trusted copy trong CurrentUser\Root. Không trust CA khác, không thay certificate của API bằng certificate mới. Trước khi chạy phải kiểm lại đúng thumbprint/candidate; nếu certificate biến mất, đổi identity hoặc có candidate khác thì dừng để đối chiếu, không để CLI tự tạo replacement ngoài dự định.

Trust là thiết lập tồn tại sau khi dừng API và có hiệu lực với các client dùng Windows trust của user. Nó không giới hạn riêng port7199; certificate còn có các SAN Development liệt kê ở mục2. Thay đổi này không mở listener/LAN, không sửa DNS/firewall và không thiết lập Android trust.

Yêu cầu chờ duyệt đến trực tiếp từ **Giai đoạn2 của yêu cầu người dùng**: “Yêu cầu người dùng phê duyệt trước khi thực thi.” Không suy việc giao nhiệm vụ chẩn đoán là đã duyệt lệnh trust.

Hoàn nguyên nếu sau này đã duyệt và thực sự thêm trust: xác minh đúng copy do phiên tạo trong `CurrentUser\Root` rồi chỉ bỏ copy có thumbprint trên. Giữ certificate/private key trong `CurrentUser\My`; không `--clean`, không xóa chứng chỉ khác. Chưa có thay đổi trust nào cần rollback trong lượt này.

## 4. Kế hoạch kiểm tra sau phê duyệt — kết quả thực tế ở mục6

Chỉ thực hiện khi người dùng đã duyệt và trust thành công:

1. Đối chiếu lại candidate thumbprint và chạy lệnh trust được duyệt. Nếu Windows hiển thị consent dialog, người dùng xem đúng certificate/phạm vi rồi chấp thuận; không vượt dialog bằng bypass.
2. Chạy lại `dotnet dev-certs https --check --trust`; cần exit0. Kiểm trusted copy đúng thumbprint. Không ghi PASS chỉ từ việc lệnh trust được gọi.
3. Kiểm lại port7199/hosting overrides; chạy API Development với `--no-restore --no-launch-profile --urls https://localhost:7199` như báo cáo runtime trước.
4. Xác minh API chỉ mở `127.0.0.1:7199` và `[::1]:7199`, không listener khác thuộc process.
5. Dùng TLS client mặc định, không validation callback, để đối chiếu public peer certificate khi handshake được chấp nhận. So thumbprint thực tế với certificate đã duyệt; mismatch thì dừng điều tra, không xóa/tạo certificate.
6. Gửi GET `/weatherforecast` qua HTTPS verification mặc định. Chỉ HTTP200 hợp lệ mới đánh **LOCAL HTTPS HTTP RESPONSE: PASS**.
7. Nếu vẫn TrustFailure, kiểm identity/chain/store bằng read-only và giữ BLOCKED. Không import CA khác, không sửa callback/certificate validation, không đổi SQL/TLS config.
8. Chỉ khi HTTPS PASS và có file QR payload local được chủ bản đồ cho phép mới chạy resolver→pin/membership→từng ảnh theo Preflight4E. Không có file thì giữ `AUTHORIZED_QR_NOT_AVAILABLE`; không tìm token trong SQL/source/clipboard.
9. Dừng đúng API process đã tạo, kiểm port7199 trở lại baseline; ghi kết quả thực tế vào báo cáo này.

Tại checkpoint ngày29/10 chưa thực hiện các bước phụ thuộc. Ngày30/10 đã thực hiện trust/startup/TLS/weatherforecast và cleanup; Published data read chưa thử vì thiếu QR được phép.

## 5. Baseline, cleanup và invariants — lịch sử ngày29/10

- Baseline: **522 file** tracked/untracked không bị ignore; **379 Git status entries =43 modified +336 untracked**; branch `auth-jwt-assignment`, không staged entries.
- Đã ghi baseline SHA256/status trong bộ nhớ phiên.
- Port7199 không có listener trước/sau chẩn đoán; không có dotnet/API process trong inventory đầu phiên. Không khởi động API nên không có process mới phải dừng.
- Chỉ đọc certificate stores; không trust/import/export/clean/remove certificate.
- Không thay network/firewall/LAN/DNS/SQL/JWT/permissions/QR/APK/source; không migration/data write.
- Chỉ tạo **`docs/PublishedPilotLocalHttpsResolution20261029.md`**. Các báo cáo cũ giữ nguyên.

Kiểm tra cuối: **522/522 file cũ giữ nguyên SHA256**; chỉ thêm báo cáo này. Git sau: **523 file /380 entries =43 modified +337 untracked**, branch và staged state giữ nguyên. Tập hash này không bao gồm ignored/build/cache hoặc certificate stores; không khẳng định kiểm toàn bộ hệ điều hành bằng Git manifest.

Checkpoint ngày29/10 đã dừng chờ phê duyệt. Phê duyệt ngày30/10 đã giải quyết gate đó như các mục dưới; không có Phone Published E2E hoặc field accuracy acceptance mới.

## 6. Thực thi theo phê duyệt ngày30/10/2026

Người dùng phê duyệt rõ lệnh `dotnet dev-certs https --trust` đối với thumbprint **`CC2373AF077AADF1722A14404B74C67CF6D97BCE`**, chỉ dưới Windows user hiện tại, và yêu cầu **giữ trust sau thử**.

### 6.1. Kiểm tra trước thay đổi

Đối chiếu lại public metadata ngay trước khi thực hiện:

- Subject/Issuer vẫn `CN=localhost`; còn hạn; SAN và Server Authentication EKU giữ đúng như mục2.
- Có private key hiện hữu; không đọc/export private key.
- **Đúng một** valid ASP.NET Core Development candidate trong CurrentUser\My, có đúng thumbprint được duyệt.
- `--check --trust` trước thay đổi vẫn exit7; CurrentUser\Root chưa có certificate này.
- Không có hosting/Kestrel/Urls/E2E overrides ngoài dự kiến trong JSON/user-secrets/environment được kiểm.
- Port7199 trống; baseline không có dotnet/API process.

Không phát sinh identity mismatch; không tạo hoặc thay certificate.

### 6.2. Trust và kiểm tra certificate stores

Đã thực hiện:

~~~powershell
dotnet dev-certs https --trust
dotnet dev-certs https --check --trust
~~~

| Sự kiện | Kết quả thực tế — Asia/Saigon |
|---|---|
| Lệnh trust | **Exit0**, “Successfully trusted the existing HTTPS certificate.”, lúc **09:38:19 ngày30/10** |
| Hộp thoại Windows | User xác nhận đã chọn **Yes** cho thao tác đã phê duyệt |
| Kênh UI automation | Báo native pipe unavailable; không bấm được bằng automation, không dùng SendKeys/helper thay thế hoặc bỏ qua dialog |
| Kiểm tra trust sau thay đổi | **Exit0**, tìm thấy trusted certificate đúng thumbprint, lúc **09:38:39** |
| CurrentUser\Root | Thêm đúng `CC2373AF077AADF1722A14404B74C67CF6D97BCE` |
| Certificate public bytes | Bản CurrentUser\Root có RawData giống bản CurrentUser\My |
| CurrentUser\My, CurrentUser\CA | Danh sách thumbprints giữ nguyên |
| LocalMachine\My, Root, CA | Danh sách thumbprints giữ nguyên |

Đối chiếu trước/sau **6 stores** chỉ thấy **1 addition trong CurrentUser\Root, 0 removal**. Không import/trust CA khác, không `--clean`, không xóa/tạo certificate.

### 6.3. API runtime và listener

Chạy trong terminal PTY riêng:

~~~powershell
dotnet run --project .\WayMark.Api\WayMark.Api.csproj --no-restore --no-launch-profile -- `
    --environment Development --urls https://localhost:7199 `
    --Logging:LogLevel:Default=None `
    --Logging:LogLevel:Microsoft.Hosting.Lifetime=Information
~~~

- Application started, environment **Development**.
- Wrapper **dotnet PID19528**; child **WayMark.Api PID8052**.
- Quan sát lúc **09:39:21**: API owner chỉ có hai listeners **`127.0.0.1:7199` và `[::1]:7199`**.
- Không có LAN/wildcard hoặc port HTTP khác thuộc API owner.
- Không chỉnh file cấu hình, SQL/JWT/permissions; logging overrides chỉ thuộc process.
- Không restore packages/migration/seed/data write. `dotnet run --no-restore` có thể cập nhật ignored bin/obj như lượt runtime trước.

**LOCAL API STARTUP: PASS.**

### 6.4. Certificate thực tế Kestrel phục vụ và HTTPS HTTP

Dùng **SslStream không validation callback**, gọi `AuthenticateAsClient('localhost')` với verification mặc định. Đọc public peer metadata chỉ sau handshake được chấp nhận:

| Trường | Kết quả lúc09:39:32 |
|---|---|
| Peer subject | `CN=localhost` |
| Peer thumbprint | **`CC2373AF077AADF1722A14404B74C67CF6D97BCE`** |
| Khớp certificate được duyệt | **true** |
| IsAuthenticated / IsEncrypted | **true / true** |
| Protocol quan sát | **TLS1.3** |
| Validation callback | **Không có** |

Danh tính certificate thực tế đã được xác minh; không còn để gate Kestrel certificate mismatch ở trạng thái unknown cho lần chạy này.

Sau đó dùng Windows `System.Net.Http.HttpClient`, verification mặc định, callback toàn cục null, không auth/cookie/proxy/redirect, để gửi:

~~~text
GET https://localhost:7199/weatherforecast
~~~

| Trường | Kết quả lúc **09:39:46** |
|---|---|
| HTTP | **200** |
| MIME | **application/json** |
| Body length | **393 bytes** trong lần response này |
| JSON | Parse thành công, **5 bản ghi** |
| Schema kiểm | Mỗi bản ghi có date/temperatureC/temperatureF/summary |
| Client elapsed | **1810ms**, không dùng làm performance benchmark |
| Certificate verification | Mặc định, không bypass hoặc callback chấp nhận cert |
| Body output/persistence | Không in body, không ghi file |

**LOCAL HTTPS HTTP RESPONSE: PASS.** `/weatherforecast` không đọc SQL theo source; HTTP200 này không chứng minh Published SQL/storage hoạt động.

### 6.5. Published read

**Không có file QR payload được phép sử dụng được cung cấp trong lượt này.**

- Giữ **`AUTHORIZED_QR_NOT_AVAILABLE`**.
- Không tìm token trong source/fixtures/SQL/clipboard; không tạo/publish/revoke QR.
- Không thực hiện resolver, snapshot, membership hoặc image GET.
- **PUBLISHED QR READ và SNAPSHOT/IMAGE READ: NOT TESTED.**
- Không chạy SQL query để thay thế gate thiếu QR.
- Không có Phone Published E2E hoặc field accuracy evidence mới.

## 7. Cleanup và invariants ngày30/10

Gửi **Ctrl+C vào đúng terminal API đã tạo**; có log `Application is shutting down...`. Terminal exit1 do Ctrl+C chủ động, không phải startup failure.

Kiểm tra lúc **09:39:55**:

- PID8052 và wrapper PID19528 không còn; không có dotnet/API process trong inventory sau.
- Port7199 không còn listener, trở lại baseline.
- So toàn bộ listener tuples address/port/owner trước/sau: **0 addition /0 removal**.
- Network profile snapshot giữ nguyên.
- **Giữ trust** theo yêu cầu: certificate đã duyệt vẫn trong CurrentUser\Root.
- Kho ảnh objects/staging/leases: **19/19 file giữ nguyên hash**, không thêm/mất file trong tập được kiểm.
- APK Sprint7 giữ nguyên SHA256 `87ADD1157E7115F9A86C678659DF666356B5FFE3F5555302B62D27DBE115663D`.

Baseline Git của lượt30/10: **523 file /380 status entries =43 modified +337 untracked**, branch `auth-jwt-assignment`, không staged. Sau cập nhật báo cáo: cùng số file/entries và branch; **522/523 file baseline giữ nguyên SHA256**, chỉ báo cáo này đổi hash. Không mất file, không thêm source file hoặc sửa báo cáo cũ khác.

Không đổi firewall/LAN/DNS/SQL/JWT/QR/APK/source ứng dụng; không git reset/clean/stage/commit/push. Thay đổi ngoài repo có chủ đích duy nhất là **trust đúng certificate trong CurrentUser\Root**; không rollback trust lúc cleanup.

## 8. Hoàn nguyên trust đúng certificate — chỉ khi cần về sau

**Chưa thực hiện; hiện giữ trust cho Development theo yêu cầu.** Khi chủ máy muốn gỡ trust này, kiểm lại đúng thumbprint và chỉ xóa trusted copy trong CurrentUser\Root:

~~~powershell
$expected = 'CC2373AF077AADF1722A14404B74C67CF6D97BCE'
$trustedPath = 'Cert:\CurrentUser\Root\' + $expected
$trusted = Get-Item -LiteralPath $trustedPath -ErrorAction Stop
if ($trusted.Thumbprint -ne $expected -or
    $trusted.Subject -ne 'CN=localhost' -or
    $trusted.Issuer -ne 'CN=localhost') {
    throw 'Certificate identity differs; stop'
}
# Chỉ chạy dòng này khi thực sự muốn hoàn nguyên trust:
Remove-Item -LiteralPath $trustedPath -ErrorAction Stop
dotnet dev-certs https --check --trust
~~~

Không xóa `Cert:\CurrentUser\My\...`, không dùng `-DeleteKey`, không `--clean`, không đụng LocalMachine hoặc certificate khác. Nếu không còn trust qua store nào khác, check sẽ trở lại trạng thái chưa trusted; nếu vẫn trusted, kiểm read-only store/identity, không tự xóa thêm.

Hoàn nguyên trust không đổi SQL hoặc dữ liệu; các client HTTPS Development dựa vào Windows trust có thể lại bị TrustFailure. Trust của PC không tự làm Android tin cậy endpoint LAN.

**Kết luận hiện tại: LOCAL CERTIFICATE TRUST / LOCAL API STARTUP / LOCAL HTTPS HTTP RESPONSE đều PASS. Published QR/snapshot/image chưa thử vì thiếu QR được phép; Phone Published E2E và field accuracy vẫn NOT VERIFIED.**


