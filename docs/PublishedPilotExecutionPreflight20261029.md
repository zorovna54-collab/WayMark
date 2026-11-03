# WayMark — Published Pilot Execution Preflight

Ngày kiểm tra: **29/10/2026 — Asia/Saigon**  
Workspace: `D:\project\WayMark`  
Phạm vi: read-only source/configuration/environment và SQL `SELECT`; chỉ ghi báo cáo này và sửa lỗi hướng dẫn trong Runbook cũ.

**CONDITIONAL GO cho chuẩn bị/thử loopback có kiểm soát. BLOCKED cho thực thi Published E2E trên điện thoại cho đến khi có endpoint HTTPS, DNS/certificate và phạm vi mạng được duyệt. Chưa có E2E PASS.**

CONFIRMED = quan sát trong phiên này; SOURCE = hành vi thấy trong code; NOT VERIFIED = chưa thực thi hoặc chưa có bằng chứng phù hợp. SQL read thành công không thay cho API chạy bằng Microsoft.Data.SqlClient/EF; file ảnh tồn tại không thay cho ảnh được public endpoint xác minh và Flutter decode.

## 1. Current Environment

| Hạng mục | Kết quả ngày 29/10 |
|---|---|
| ASP.NET Core | `WayMark.Api.csproj`: net10.0; SDK cục bộ **10.0.402** |
| Launch profiles | `http`: `http://localhost:5121`; `https`: `https://localhost:7199;http://localhost:5121`; đều Development |
| API listener | Không thấy listener **5121/7199** trong inventory đầu phiên; không khởi động API. Không suy ra mọi port/host khác đều dừng |
| Kestrel override | Không có `Kestrel`/`Urls` trong hai appsettings chính/Development; không thấy override liên quan trong environment của shell; user-secrets không có key liên quan ConnectionStrings/MapImages/Kestrel/Urls/E2E được kiểm |
| Startup auth | Chỉ kiểm boolean: JWT key decode Base64 >=32 bytes, issuer/audience có cấu hình. Không xuất giá trị. Public GET vẫn cần startup auth configuration hợp lệ |
| SQL service | **MSSQLSERVER Running**, SQLBrowser Stopped; không thấy listener1433 trong inventory ban đầu. Local connection có thể dùng transport khác, không cần mở SQL ra LAN |
| SQL runtime read | **PASS** bằng `System.Data.SqlClient`, danh tính Windows của phiên hiện tại, connection hiện có, timeout5s; database **ONLINE**, nhìn thấy **4/4** bảng Published được hỏi |
| Published aggregate | **5** rows `MapPublications`; **6** rows `MapNodeQrs` có `IsActive=1 AND PublishedVersion IS NOT NULL`. Không lấy token/content/raw IDs; chưa đối chiếu QR vật lý cụ thể |
| SQL security hiện có | Integrated Security=true, TrustServerCertificate=true; **Encrypt không được đặt tường minh** trong connection string base. Operator probe dùng default Encrypt=false của System.Data.SqlClient; default provider Microsoft.Data.SqlClient của API có thể khác. Không chỉnh connection string hoặc suy API TLS từ probe này; không mở1433 |
| Image storage | Development: `MapImages.Enabled=true`, root tuyệt đối tồn tại ngoài workspace; root không có ReparsePoint. `objects`: **6 .bin +6 .json**; `staging`:0 file; `leases`:7 file. Không mở manifest/image content, không acquire lease/cleanup |
| Quyền storage | Metadata listing được bằng user hiện tại; ACL/quyền của process chạy bằng identity khác, validation toàn bộ ancestor và checksum/public binding **NOT VERIFIED** |
| Network | Profile có IPv4 Internet hiện quan sát: **Public** (InterfaceIndex17). Firewall Domain/Private/Public enabled. Không đổi profile/rule/DNS/router |
| Certificate | `dotnet dev-certs https --check`: có cert development hợp lệ **CN=localhost**, hạn 18/10/2026–18/10/2027 UTC. Không xác nhận PC trust bằng thao tác cài trust; cert này không chứng minh SAN LAN/Android trust |
| APK | Artifact Sprint7 tồn tại, **187,745,970 bytes**, package `com.example.waymark.livetest`, label `WayMark Live Test`, version1.0.0/code1, min24/target36/compile36, ba ABI |
| APK hash/signature | SHA256 `87ADD1157E7115F9A86C678659DF666356B5FFE3F5555302B62D27DBE115663D`; `apksigner verify` exit0; signer SHA256 `8c15d5eb313223a87d82ef435a13307e74f8abf1a9da2e9dd8de9c21b0cf4df2` |
| Điện thoại | Không cần USB cho preflight. Không cài/update APK, không kiểm camera/sensors/mạng/TLS trên máy thật trong lượt này |

Artifact giữ nguyên: [APK Sprint7](../waymark/build/live-navigation-artifacts/WayMark-Live-Test-Sprint7-20261028-debug.apk). Hash/signature nhận dạng artifact local; không chứng minh APK đã cài trên điện thoại.

Cấu hình được đọc nội bộ và chỉ xuất whitelist boolean/count; không dump appsettings/user-secrets/environment values. Các kết quả trên phản ánh cấu hình Development trong shell hiện tại; chạy bằng account/environment/command override khác phải kiểm lại.

### Đối chiếu source và Runbook

- `Program.cs`: `UseHttpsRedirection`, auth/rate limiter/authorization giữ nguyên; Swagger trong Development, `/weatherforecast` là GET không truy cập SQL. **Không có `/health` endpoint riêng** trong luồng này; `/api` trả404 có thể hoàn toàn bình thường.
- `WayMarkDatabaseRegistration.cs`: hai context dùng `WayMarkDatabase`, migrations histories khác nhau; không gọi migration/seed trong startup thường đã kiểm. Không dùng launcher `MapDraftE2E` để phục vụ pilot hiện tại.
- `MapProjectsController.cs`: public QR/snapshot/image `[AllowAnonymous]`; quản lý/publish/QR creation/revoke cần policy. Pilot dùng dữ liệu đã publish, không thực hiện các POST/PUT/DELETE này.
- `MapProjectService`: QR token opaque → map/version/floor/node; checks active/publication/membership; ảnh phải có binding đúng publication và asset metadata.
- `ManagedFileMapImageStorage.OpenReadAsync` + `MapDraftService.OpenVerifiedImageAsync`: validate metadata, file length/hash. **Không gọi `InspectAsync` để “read-only kiểm kho”**: hàm đó gọi Prepare/acquire lease, có thao tác ghi.
- `PublishedMapApiService`: public request không Authorization; `followRedirects=false`; JSON giới hạn8MiB, ảnh10MiB, timeout30s/request. Mỗi ảnh được tải/validate; source không hứa cache download qua nhiều lần load.
- `live_test_main.dart`: nhập runtime endpoint riêng, không cần rebuild; đường dẫn kết thúc `/api`, không credentials/query/fragment. Parser chấp nhận cả HTTP nhưng phiên pilot này yêu cầu **HTTPS cuối cùng**.
- Main manifest cleartext=false; debug overlay cleartext=true. Điều đó không tạo HTTPS trust và không phải lý do dùng HTTP cho phiên này. Không thấy custom trust/badCertificateCallback trong source khảo sát.
- **Đã sửa Runbook cũ**: hostname trong Kestrel URL không giới hạn interface như mô tả trước. Dùng IP cụ thể để bind; DNS dùng cho client/certificate. Bổ sung cảnh báo browser trust khác app trust và liên kết báo cáo này. Không thay source/config.

Kestrel xem hostname thông thường khác IP/localhost là wildcard; tránh dùng hostname để giới hạn socket. [Microsoft endpoint binding](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/servers/kestrel/endpoints?view=aspnetcore-10.0)

## 2. Dependencies & Blockers

| Gate | Đã có | Còn thiếu / điều kiện dừng |
|---|---|---|
| API local | SDK/config/source | Startup process + GET loopback chưa chạy; thiếu package/build artifact thì dừng, không tự restore/upgrade |
| SQL | Service, ONLINE, SELECT aggregate | API identity/provider thực sự đọc được snapshot/QR; query operator không chứng minh mọi quyền EF/auth/schema |
| Storage | Root/objects tồn tại | Public image GET + đúng MIME/bytes + decode trong app; không tạo root trống thay cho kho ảnh cũ |
| QR thật | 6 active published rows | Chủ bản đồ cung cấp biển/payload đã được phép dùng tại điểm thật; không SELECT/dump token vào báo cáo |
| LAN | PC có kết nối | IP PC/điện thoại, interface/profile/port/thời hạn cụ thể; AP isolation/VPN/DNS; hiện Public profile |
| HTTPS | localhost development cert | Cert server SAN đúng DNS/IP truy cập, chain/intermediates đầy đủ, private-key access, Android/Dart trust thật |
| APK/device | Artifact local đã verify | Update qua kênh tin cậy không USB; camera/Activity Recognition; sensor capability và thực thi |
| Map/field | Snapshot contract/validator có | Corridor thẳng/chiều dài khảo sát thật, đích reachable, QR cùng pin; không bật Live ở đoạn bị blocker |

Ưu tiên endpoint test HTTPS **đã được quản lý và được Android tin cậy**, trỏ tới đúng dữ liệu pilot đã duyệt. Nếu dùng PC LAN, chọn DNS đã quản lý trỏ LAN IP và cert chain được stock app chấp nhận; CA công khai hợp lệ cho DNS sở hữu có thể dùng với private DNS routing, không đòi công khai API. Không tự cấp cert, tạo DNS/tunnel hoặc import CA.

Dart default trust lấy từ platform trên Android; cài CA user store hoặc browser chấp nhận cert chưa chứng minh stock Flutter app chấp nhận. Không sửa trust config/rebuild APK trong preflight. Nếu hiện chỉ có localhost cert thì **dừng gate TLS**, xin phương án endpoint/cert cụ thể. [Dart SecurityContext](https://api.dart.dev/dart-io/SecurityContext/defaultContext.html), [Android trust configuration](https://developer.android.com/privacy-and-security/security-config)

## 3. Step-by-step Safe Test Runbook

Các lệnh dưới đây là **hướng dẫn cho lượt thực thi tiếp theo**, trừ các phép inventory/SQL aggregate/hash đã ghi ở mục1. Không sao chép toàn tài liệu thành một script chạy liền. Những block có nhãn **AFTER APPROVAL** chưa được áp dụng.

1. Giữ bản đồ/QR/version hiện tại. Chọn phone A/trial alias, hành lang đo10–20m và QR đầu/cuối đã tồn tại. Mở [mẫu lượt đo](PublishedPilotFieldTrialTemplate20261028.md); để trống mục chưa đo.
2. Kiểm inventory/config bằng mục4A/B. Nếu startup auth/SQL/storage thiếu, báo đúng gate và dừng; không migration/seed/cấp quyền/sửa secret.
3. Chạy **loopback HTTPS** mục4C trong terminal riêng. Xác nhận listener chỉ loopback và weatherforecast200 với certificate verification. Lỗi TLS không dùng `-k` hay tự `--trust`.
4. Chọn endpoint đã quản lý hoặc hoàn tất phiếu duyệt mục5. Chỉ sau duyệt mới thực hiện binding/firewall/certificate/DNS đã chỉ định. Không áp dụng mẫu7443 khi chưa có IP/cert/profile/phone/thời hạn được chốt.
5. Kiểm DNS/TCP/TLS từ PC bằng mục4D, rồi trên **browser điện thoại cùng mạng** mở `/weatherforecast`. Không chấp nhận warning/captive portal. PC200 chưa chứng minh phone reachable; browser200 chưa chứng minh Flutter trust/QR.
6. Trên PC có thể chạy GET QR→snapshot→từng ảnh ở mục4E bằng payload nhập kín, không ghi vào command history. Kết quả này chỉ là PC server-read gate; nếu không muốn nhập token trên PC, dùng app và ghi HTTP/code qua nguồn đã làm sạch khi cần.
7. Người dùng tự chuyển APK đúng hash qua Drive cá nhân/kênh tin cậy, tải bằng Files, chọn **Cập nhật WayMark Live Test**. Không uninstall/xóa data nếu lỗi signing/version. Không cần USB; không upload từ agent.
8. Mở Live Test Home → nhập `https://<approved-DNS>:<approved-port>/api` → **Mở QR Published • guest**. Không dùng localhost/127.0.0.1/10.0.2.2 của PC trên điện thoại; không nhập `/swagger` hoặc URL QR vào ô endpoint.
9. Camera scan QR thật → tải snapshot và ảnh → Search → chọn đích → Preview → Navigation. Đối chiếu version/start/tầng/ảnh; QR URL host không phải API host, app chỉ lấy token và gọi endpoint đã nhập. Không cần JWT/đăng nhập để public read.
10. Chọn Live opt-in, xem preflight: số đoạn hỗ trợ, ảnh, blocker/partial support. Không tick khảo sát khi chưa đối chiếu hành lang thật. Blocked route vẫn dùng manual/QR; không sửa map để vượt gate trong phiên này.
11. Hoàn tất 5 bước: **Xác nhận vị trí → Chuẩn bị cảm biến → Hiệu chuẩn bước chân → Chọn hướng bắt đầu → Bắt đầu Live Navigation**. Dùng QR fresh cùng pin để đánh gate QR; mốc manual phải ghi manual. Chọn đúng hành lang và hướng cầm máy; rotation phone không phải chứng cứ travel heading.
12. Trong Live → **Diagnostics • nâng cao** → toolkit: chọn phase, **Bắt đầu ghi nhận**. Đếm bước tay, đi/dừng/quay riêng; ghi estimate/false steps, không kết luận accuracy từ dot chuyển động. Hai nút ghi/chốt report không bật/tắt sensors.
13. Trước QR cuối: ghi endpoint error đo thật và estimate. Quét QR cùng map/version; xác nhận correction/reanchor và baseline trong diagnostics, pose đúng tầng/node; làm lại heading/edge setup nếu UI yêu cầu. QR không tự chứng minh heading đúng. Đo lại error sau QR, không tự ghi0.
14. QR khác map/version/revoked/offline chỉ dùng ca đã có và được phép; không tạo/revoke dữ liệu để thử. Lỗi phải giữ pin/pose đã biết và không nhận anchor mới. Không gọi kết quả resolve cache là fresh online verification.
15. **Chốt số liệu**, nhập đo thật, chọn checklist PASS/FAIL/NOT TESTED theo quan sát, copy **báo cáo thử nghiệm đã làm sạch**. Chưa quan sát fallback thì giữ NOT TESTED; có thể copy trước, chuyển manual và quan sát rồi copy report cuối ở **Pilot report • phiên Live vừa đóng**.
16. Kiểm Pause/Resume/manual fallback theo ca; không suy listener đã dừng chỉ từ màn hình đứng yên. Ghi trạng thái/counters/lifecycle thật. Copy trước khi rời Navigation/new session/đóng app vì report chỉ ở RAM.
17. Hoàn nguyên đúng mục6; giữ data/QR/APK và evidence đã làm sạch. Không đổi PASS chỉ vì lệnh khác trước đó thành công.

## 4. PowerShell Verification Commands

Chạy tại PowerShell trên PC; không `Start-Transcript`, không `Tee-Object` request/console thô có QR path. Output raw debug server có thể chứa URL token; chỉ chia sẻ HTTP status và code allowlist, không raw logs/bodies. Không đưa token/connection string vào lệnh literal/argv.

### 4A. Inventory, certificate và APK — read-only

~~~powershell
Set-Location -LiteralPath 'D:\project\WayMark'
git status --porcelain=v1 -uall
dotnet --list-sdks
Get-Service -Name MSSQLSERVER,SQLBrowser | Select-Object Name,Status
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object LocalPort -in 5121,7199,7443 |
    Select-Object LocalAddress,LocalPort,OwningProcess
Get-NetConnectionProfile |
    Select-Object InterfaceIndex,NetworkCategory,IPv4Connectivity
dotnet dev-certs https --check

$pilotApk = 'D:\project\WayMark\waymark\build\live-navigation-artifacts\WayMark-Live-Test-Sprint7-20261028-debug.apk'
(Get-FileHash -LiteralPath $pilotApk -Algorithm SHA256).Hash
& 'C:\Program Files\Android\Android Studio\jbr\bin\java.exe' -jar `
    "$env:LOCALAPPDATA\Android\sdk\build-tools\36.0.0\lib\apksigner.jar" `
    verify --print-certs $pilotApk
if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed' }
~~~

PASS từng phần: đúng hash/signature; cert check chỉ valid localhost certificate; listener/profile là inventory. Không tự chạy `dev-certs --trust/--clean`. Không có listener = API chưa có trên port đó; `SQLBrowser Stopped` không phải lỗi bắt buộc cho local default instance.

### 4B. SQL và storage — read-only, không in secrets

Block dưới mô phỏng những key cần dùng trong Development: base → Development JSON → user-secrets nested/flat → environment. Đây không thay toàn bộ ASP.NET configuration engine; chạy lại nếu thêm provider/command overrides. Dùng Windows PowerShell có `System.Data.SqlClient`; đây là operator probe, không giả là EF runtime gate. Chỉ timeout được đặt5s trong bộ nhớ; không thêm/sửa Encrypt hoặc TrustServerCertificate trong chuỗi cấu hình. Default Encrypt của hai provider có thể khác, nên API GET vẫn là gate bắt buộc.

~~~powershell
$ErrorActionPreference = 'Stop'
$pilotBase = Get-Content -Raw -Encoding UTF8 .\WayMark.Api\appsettings.json | ConvertFrom-Json
$pilotDev = Get-Content -Raw -Encoding UTF8 .\WayMark.Api\appsettings.Development.json | ConvertFrom-Json
[xml]$pilotProject = Get-Content -Raw .\WayMark.Api\WayMark.Api.csproj
$pilotSecretsPath = Join-Path $env:APPDATA ('Microsoft\UserSecrets\' +
    [string]$pilotProject.Project.PropertyGroup.UserSecretsId + '\secrets.json')
$pilotSecrets = $null
if (Test-Path -LiteralPath $pilotSecretsPath) {
    $pilotSecrets = Get-Content -Raw -Encoding UTF8 -LiteralPath $pilotSecretsPath | ConvertFrom-Json
}
function Get-PilotSetting([string]$section, [string]$key) {
    $value = $pilotBase.$section.$key
    if ($null -ne $pilotDev.$section.$key) { $value = $pilotDev.$section.$key }
    if ($null -ne $pilotSecrets) {
        if ($null -ne $pilotSecrets.$section.$key) { $value = $pilotSecrets.$section.$key }
        $flat = $pilotSecrets.PSObject.Properties[($section + ':' + $key)]
        if ($null -ne $flat) { $value = $flat.Value }
    }
    $override = [Environment]::GetEnvironmentVariable($section + '__' + $key, 'Process')
    if ($null -ne $override) { $value = $override }
    return $value
}
$pilotConnection = [System.Data.SqlClient.SqlConnectionStringBuilder]::new(
    [string](Get-PilotSetting 'ConnectionStrings' 'WayMarkDatabase'))
$pilotConnection['Connect Timeout'] = 5
$pilotDb = [System.Data.SqlClient.SqlConnection]::new($pilotConnection.ConnectionString)
try {
    $pilotDb.Open()
    $query = $pilotDb.CreateCommand()
    $query.CommandTimeout = 5
    $query.CommandText = "SELECT COUNT(*) FROM sys.tables WHERE name IN ('MapPublications','MapNodeQrs','MapPublicationImages','FloorMapImageAssets')"
    $tables = [int]$query.ExecuteScalar()
    $query.CommandText = 'SELECT COUNT_BIG(*) FROM dbo.MapPublications'
    $publications = [long]$query.ExecuteScalar()
    $query.CommandText = 'SELECT COUNT_BIG(*) FROM dbo.MapNodeQrs WHERE IsActive=1 AND PublishedVersion IS NOT NULL'
    $qrs = [long]$query.ExecuteScalar()
    [pscustomobject]@{SqlRead='PASS'; VisibleTables=$tables; Publications=$publications; ActivePublishedQrRows=$qrs}
} catch {
    # Không in $_ / Exception.Message / ConnectionString.
    $sqlError = $_.Exception
    while ($sqlError.InnerException) { $sqlError = $sqlError.InnerException }
    $number = $null
    if ($sqlError -is [System.Data.SqlClient.SqlException]) { $number = $sqlError.Number }
    [pscustomobject]@{SqlRead='FAIL_OR_PARTIAL'; SqlErrorNumber=$number}
} finally {
    $pilotDb.Dispose()
    $pilotConnection = $null
}

$pilotImageRoot = [string](Get-PilotSetting 'MapImages' 'RootPath')
[pscustomobject]@{
    StorageEnabled = [string](Get-PilotSetting 'MapImages' 'Enabled')
    RootConfigured = -not [string]::IsNullOrWhiteSpace($pilotImageRoot)
    RootExists = ($pilotImageRoot -and (Test-Path -LiteralPath $pilotImageRoot -PathType Container))
}
if ($pilotImageRoot -and (Test-Path -LiteralPath $pilotImageRoot -PathType Container)) {
    foreach ($area in @('objects','staging','leases')) {
        $folder = Join-Path $pilotImageRoot $area
        $files = @(Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue)
        [pscustomobject]@{Area=$area; Exists=(Test-Path -LiteralPath $folder); FileCount=$files.Count}
    }
}
$pilotBase = $null; $pilotDev = $null; $pilotSecrets = $null; $pilotImageRoot = $null
~~~

Không in `$files`, root/ACL identity, database/server names hoặc secret objects. SELECT fail do thiếu bảng/quyền phải dừng, không tự sửa schema/grant. File counts không chứng minh metadata/state/hash/binding; bước4E và Flutter mới kiểm ảnh được dùng.

### 4C. Chạy local API và HTTP helper

**Chưa chạy trong preflight.** Terminal1, user hiện tại, chỉ loopback; build có thể ghi bin/obj, không migration/SQL write theo startup source đã kiểm:

~~~powershell
Set-Location -LiteralPath 'D:\project\WayMark'
dotnet run --project .\WayMark.Api\WayMark.Api.csproj --no-restore --no-launch-profile -- `
    --environment Development --urls 'https://localhost:7199'
~~~

Nếu thiếu restore/build assets hoặc startup thiếu configuration: dừng và báo gate; không tự chạy setup SQL hoặc sửa JWT. Không dùng shell có `E2E__*`/`Kestrel__*` override không được duyệt. Terminal2 kiểm7199 chỉ `127.0.0.1`/`::1`; wildcard/LAN ngoài dự kiến → Ctrl+C terminal1.

Helper cho terminal2 (Windows PowerShell/.NET hoặc PowerShell7): TLS verification mặc định, không redirect, không auth/cookie, không ghi file. Body ở RAM, chỉ gọi với endpoint đã duyệt; không để function return object chưa gán ra console.

~~~powershell
Add-Type -AssemblyName System.Net.Http
$pilotHandler = [System.Net.Http.HttpClientHandler]::new()
$pilotHandler.AllowAutoRedirect = $false
$pilotHandler.UseCookies = $false
$pilotHttp = [System.Net.Http.HttpClient]::new($pilotHandler)
$pilotHttp.Timeout = [TimeSpan]::FromSeconds(30)
$pilotHttp.MaxResponseContentBufferSize = 10 * 1024 * 1024
function Get-PilotHttp([uri]$uri) {
    $response = $null
    try {
        $response = $pilotHttp.GetAsync($uri).GetAwaiter().GetResult()
        $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        $safeCode = $null
        if (-not $response.IsSuccessStatusCode) {
            $safeCode = 'unrecognized_or_missing'
            try {
                $problem = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
                $allowedCodes = @('map_not_found','map_not_published','qr_revoked','qr_node_missing',
                    'draft_storage_unavailable','draft_unavailable','image_storage_unavailable',
                    'image_storage_configuration','image_object_unavailable','image_metadata_invalid',
                    'image_integrity_failure','image_storage_busy','invalid_storage_key')
                if ([string]$problem.code -cin $allowedCodes) { $safeCode = [string]$problem.code }
            } catch { }
            $problem = $null
        }
        return [pscustomobject]@{
            Status = [int]$response.StatusCode
            Mime = [string]$response.Content.Headers.ContentType.MediaType
            Code = $safeCode
            Bytes = $bytes
        }
    } catch {
        # Chỉ xuất nhóm lỗi, không in Message/URI chứa token.
        $failureCode = 'HTTP_TRANSPORT_OR_BUFFER_LIMIT'
        $cause = $_.Exception
        while ($null -ne $cause) {
            if ($cause -is [System.Security.Authentication.AuthenticationException]) {
                $failureCode = 'TLS_CERTIFICATE_OR_HANDSHAKE'
            } elseif ($cause -is [System.Net.WebException] -and
                [string]$cause.Status -in @('TrustFailure','SecureChannelFailure')) {
                $failureCode = 'TLS_CERTIFICATE_OR_HANDSHAKE'
            } elseif ($cause -is [System.Net.Sockets.SocketException]) {
                $failureCode = 'DNS_OR_SOCKET'
            } elseif ($cause -is [System.Threading.Tasks.TaskCanceledException]) {
                $failureCode = 'TIMEOUT_OR_CANCELED'
            }
            $cause = $cause.InnerException
        }
        throw ('HTTP probe stopped: ' + $failureCode)
    } finally {
        if ($null -ne $response) { $response.Dispose() }
    }
}
$pilotOrigin = 'https://localhost:7199'
$weather = Get-PilotHttp ([uri]($pilotOrigin + '/weatherforecast'))
[pscustomobject]@{Stage='Loopback transport'; HTTP=$weather.Status; MIME=$weather.Mime}
$weather = $null
~~~

200 JSON = API transport/routing loopback; không kiểm SQL. 404 chỉ ở `/api` không phải health fail. 3xx không theo redirect; dùng HTTPS origin cuối cùng. TLS error trên PC không tự trust cert; kiểm chain/SAN/clock bằng quản trị viên.

### 4D. DNS/TCP/TLS sau khi endpoint được duyệt

Điền **giá trị được duyệt**, không chạy placeholder:

~~~powershell
$pilotDns = Read-Host 'Approved DNS name only'
$pilotPort = [int](Read-Host 'Approved HTTPS port')
if ($pilotPort -lt 1 -or $pilotPort -gt 65535) { throw 'Invalid port' }
Resolve-DnsName -Name $pilotDns -Type A
Test-NetConnection -ComputerName $pilotDns -Port $pilotPort -InformationLevel Quiet
$pilotOrigin = 'https://' + $pilotDns + ':' + $pilotPort
$weather = Get-PilotHttp ([uri]($pilotOrigin + '/weatherforecast'))
[pscustomobject]@{Stage='Approved PC HTTPS'; HTTP=$weather.Status; MIME=$weather.Mime}
$weather = $null
~~~

DNS phải về IP/interface đã duyệt, TCP true rồi HTTPS200. DNS/route metadata giữ cục bộ. Các lệnh này chạy từ PC; browser phone phải kiểm riêng cùng origin/path. Nếu endpoint reverse proxy có prefix, người quản trị phải xác nhận mapping `/api/public/...` và health path trước, không tự suy weather path được proxy.

### 4E. QR → snapshot → ảnh — GET only

Chạy sau4C/4D bằng cùng `$pilotOrigin` cuối cùng. Payload nhập kín từ QR đã được chủ bản đồ cung cấp; không dán QR vào terminal command literal, browser address hay chat. GET path vẫn có thể được server/proxy log: giữ log kín và không gửi raw log.

~~~powershell
$pilotQrSecret = Read-Host 'Authorized WMQR1 payload (hidden)' -AsSecureString
$pilotPayload = [System.Net.NetworkCredential]::new('', $pilotQrSecret).Password
try {
    if ($pilotPayload -cnotmatch '^WMQR1:[a-f0-9]{64}$') { throw 'Invalid QR format' }
    $pilotToken = $pilotPayload.Substring(6)
    $qrRead = Get-PilotHttp ([uri]($pilotOrigin + '/api/public/qr/' + $pilotToken))
    [pscustomobject]@{Stage='QR resolver'; HTTP=$qrRead.Status; Code=$qrRead.Code}
    if ($qrRead.Status -ne 200) { throw 'QR gate failed; classify status/code locally' }
    $qr = [Text.Encoding]::UTF8.GetString($qrRead.Bytes) | ConvertFrom-Json
    $mapId = [guid]$qr.mapId
    $version = [long]$qr.version
    if ($mapId -eq [guid]::Empty -or $version -le 0) { throw 'Invalid pin' }

    $mapPath = '/api/public/maps/' + $mapId + '/versions/' + $version
    $mapRead = Get-PilotHttp ([uri]($pilotOrigin + $mapPath))
    [pscustomobject]@{Stage='Pinned snapshot'; HTTP=$mapRead.Status; Code=$mapRead.Code}
    if ($mapRead.Status -ne 200 -or $mapRead.Bytes.Length -gt 8*1024*1024) { throw 'Snapshot gate failed' }
    $snapshot = [Text.Encoding]::UTF8.GetString($mapRead.Bytes) | ConvertFrom-Json
    if ([guid]$snapshot.mapId -ne $mapId -or [long]$snapshot.version -ne $version) { throw 'Pin mismatch' }
    $floors = @($snapshot.content.floors)
    $anchorFloor = @($floors | Where-Object { [string]$_.id -eq [string]$qr.floorKey })
    if ($anchorFloor.Count -ne 1) { throw 'Anchor floor missing' }
    $anchorNode = @($anchorFloor[0].content.nodes |
        Where-Object { [string]$_.id -eq [string]$qr.nodeId })
    if ($anchorNode.Count -ne 1) { throw 'Anchor node missing' }
    [pscustomobject]@{Stage='Pin and membership'; Result='PASS'; Version=$version; Floors=$floors.Count}

    $ordinal = 0
    foreach ($floor in $floors) {
        $ordinal++
        $asset = [guid]$floor.content.imageAssetId
        if ($asset -eq [guid]::Empty) { throw 'Floor image reference missing' }
        $imageRead = Get-PilotHttp ([uri]($pilotOrigin + $mapPath + '/images/' + $asset))
        $ok = ($imageRead.Status -eq 200 -and $imageRead.Bytes.Length -gt 0 -and
            $imageRead.Mime -in @('image/png','image/jpeg'))
        [pscustomobject]@{Stage='Floor image'; Ordinal=$ordinal; HTTP=$imageRead.Status; Code=$imageRead.Code; MIME=$imageRead.Mime; Bytes=$imageRead.Bytes.Length; Passed=$ok}
        if (-not $ok) { throw 'Floor image gate failed' }
        $imageRead = $null
    }
} catch {
    # Không xuất raw $_, response body, IDs hay token.
    Write-Output 'QR/map/image probe stopped; retain only last stage/status and sanitized code'
} finally {
    $pilotPayload=$null; $pilotToken=$null; $pilotQrSecret=$null
    $qrRead=$null; $qr=$null; $mapRead=$null; $snapshot=$null
    $anchorFloor=$null; $anchorNode=$null; $floors=$null; $floor=$null
    $mapPath=$null; $mapId=$null; $asset=$null; $imageRead=$null
}
# Khi xong toàn bộ HTTP probes:
$pilotHttp.Dispose()
~~~

HTTP helper giữ cap10MiB; snapshot thêm cap8MiB. Memory-bound GET ảnh không ghi file; MIME/length200 vẫn chưa thay Flutter decode hoặc đúng biển QR vật lý. `Code` chỉ lấy từ allowlist; lỗi HTML/code lạ trả `unrecognized_or_missing`, không in body. Không có script shell nào chứng minh camera, sensor hoặc QR correction; các gate đó phải thao tác thật trên điện thoại.

## 5. Network/TLS Approval Requirements

**CHƯA ĐƯỢC DUYỆT — KHÔNG CHẠY MỤC5A/5B.** Ranh giới chờ duyệt đến từ yêu cầu trực tiếp của người dùng. Không cần approval bổ sung cho tài liệu/read-only đã làm.

Không sửa file cấu hình hiện có là phương án đề xuất. Trước khi áp dụng phải điền đủ: LAN IP PC, DNS/SAN, certificate đã có trong store và chain trust, phone IPv4, interface, port, program thực tế, thời hạn, identity/account chạy API, scope dữ liệu và người rollback. Hiện chưa có các giá trị này; đây là approval plan cụ thể theo key, chưa phải một cấu hình LAN sẵn để áp dụng.

| Vị trí/key | Hiện tại không nhạy cảm | Đề xuất cần duyệt | Phạm vi/rủi ro và rollback |
|---|---|---|---|
| `WayMark.Api/Properties/launchSettings.json` | localhost5121/7199 | **Không sửa** | Giữ local developer profiles |
| `appsettings.json`, `appsettings.Development.json`, user-secrets | SQL/JWT có cấu hình; storage enabled/root ngoài Git; không Kestrel endpoints | **Không sửa**, không copy secret | Không đổi SQL/auth/data/storage |
| Process-only `Kestrel__Endpoints__Pilot__Url` | Chưa đặt | `https://<specific-approved-RFC1918-IPv4>:7443` nếu7443 rảnh | Mở một interface LAN. Dừng đúng process + restore env |
| Process-only `...__Certificate__Subject/Store/Location/AllowInvalid` | Chưa đặt cho Pilot | `<approved-cert-DNS>` / `My` / `CurrentUser` / `false` | Dùng cert đã được cấp, một match hợp lệ có private key; không xuất key/password. Restore env |
| `Program.cs` Development behavior | Swagger + developer error UI khi Development | Không sửa, chạy timebox trên mạng test; owner phải chấp nhận phạm vi này | Rule hẹp không thay auth; không chia sẻ raw error pages/logs |
| Windows certificate stores | Có localhost devcert; chưa kiểm cert LAN được chọn | **Không import/generate/remove trong kế hoạch thực thi này**. Nếu chưa có cert phù hợp, xin plan cấp/import riêng | Cert/chain/private key/trust distribution là thay đổi riêng; không coi devcert là đáp án LAN |
| Windows Firewall | Enabled; active interface quan sát Public, rule cho pilot chưa tạo; existing broad allows chưa audit đầy đủ | Một rule tên `WayMark-PublishedPilot-20261029`, Public, TCP7443, đúng LAN IP/interface, đúng phone IPv4, đúng executable | Chỉ giới hạn **rule mới**; rule allow rộng có sẵn có thể vẫn cho nguồn khác. Cần owner review effective policy. Xóa duy nhất rule mới |
| Network profile | Public trên interface17 tại inventory | **Giữ Public**. Không tự đổi Private, không tạo rule Private rồi khẳng định hiệu lực ở mạng Public | Public profile cần explicit approval cho rule hẹp. Nếu profile/interface đổi, dừng và duyệt lại |
| DNS/router/AP/VPN | Chưa xác minh phone resolution/isolation | DNS quản lý trỏ về đúng LAN IP; không NAT/port-forward/public tunnel; không tự thay router/DNS | Nếu cần tạo DNS record: chủ quản duyệt tên/record/TTL/old value và rollback riêng; chưa có lệnh tự áp dụng |
| Android APK/trust | Sprint7 giữ nguyên; stock TLS verification | Nhập runtime `https://<approved-DNS>:7443/api`; không sửa APK/network security | Browser trust và app trust kiểm riêng; thất bại thì dừng |
| SQL/image/QR contracts | Giữ nguyên | Không migration/grant/publish/create/revoke/upload | Không có data rollback vì không cho phép data write |

Chọn7443 chỉ là đề xuất port; phải kiểm rảnh tại lúc áp dụng. Không mở5121/7199/1433 ra LAN. Rule không có expiry tự động: ghi giờ đóng theo Asia/Saigon và người chịu trách nhiệm, rollback khi kết thúc hoặc fail gate. [Firewall rule parameters](https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule?view=windowsserver2025-ps)

### 5A. AFTER APPROVAL — process-only Kestrel, certificate store

Dùng **terminal thường riêng**, cùng Windows account/config đã được kiểm. Phương án này yêu cầu sẵn cert có subject DNS được chọn trong CurrentUser\My, chain hợp lệ và private key dùng được. Kestrel hỗ trợ certificate store theo Subject/Store/Location và AllowInvalid=false. [Microsoft certificate configuration](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/servers/kestrel/endpoints?view=aspnetcore-10.0)

~~~powershell
Set-Location -LiteralPath 'D:\project\WayMark'
$pilotLanIp = Read-Host 'Approved PC RFC1918 IPv4'
$pilotDns = Read-Host 'Approved certificate DNS subject and client hostname'
$pilotPort = 7443 # Chỉ khi approval chốt đúng port này.
$parsedIp = [ipaddress]::Parse($pilotLanIp)
$b = $parsedIp.GetAddressBytes()
$isPrivate4 = $b.Length -eq 4 -and (
    $b[0] -eq 10 -or ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or
    ($b[0] -eq 192 -and $b[1] -eq 168))
if (-not $isPrivate4) { throw 'Require approved specific private IPv4' }
$localInterface = @(Get-NetIPAddress -AddressFamily IPv4 -IPAddress $pilotLanIp -ErrorAction Stop)
if ($localInterface.Count -ne 1) { throw 'IP must identify one approved local interface' }
if (Get-NetTCPConnection -State Listen -LocalPort $pilotPort -ErrorAction SilentlyContinue) {
    throw 'Pilot port already occupied; do not stop another process'
}
if (@(Get-ChildItem Env: | Where-Object Name -like 'Kestrel__*').Count -gt 0) {
    throw 'Existing Kestrel overrides need review'
}
$store = [Security.Cryptography.X509Certificates.X509Store]::new('My','CurrentUser')
$store.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
try {
    $certs = $store.Certificates.Find(
        [Security.Cryptography.X509Certificates.X509FindType]::FindBySubjectName, $pilotDns, $true)
    if ($certs.Count -ne 1 -or -not $certs[0].HasPrivateKey) {
        throw 'Need exactly one approved valid server certificate with private key'
    }
    # Kiểm SAN + Server Authentication EKU + chain với quản trị viên trước bước này.
    # Không export private key. Việc tìm cert không chứng minh Android trust.
} finally { $store.Close() }

$pilotOverrides = @{
    'Kestrel__Endpoints__Pilot__Url' = ('https://' + $pilotLanIp + ':' + $pilotPort)
    'Kestrel__Endpoints__Pilot__Certificate__Subject' = $pilotDns
    'Kestrel__Endpoints__Pilot__Certificate__Store' = 'My'
    'Kestrel__Endpoints__Pilot__Certificate__Location' = 'CurrentUser'
    'Kestrel__Endpoints__Pilot__Certificate__AllowInvalid' = 'false'
}
$pilotOldEnv = @{}
foreach ($name in $pilotOverrides.Keys) {
    $pilotOldEnv[$name] = [Environment]::GetEnvironmentVariable($name,'Process')
}
try {
    foreach ($name in $pilotOverrides.Keys) {
        [Environment]::SetEnvironmentVariable($name,$pilotOverrides[$name],'Process')
    }
    dotnet run --project .\WayMark.Api\WayMark.Api.csproj --no-restore --no-launch-profile -- `
        --environment Development
} finally {
    foreach ($name in $pilotOverrides.Keys) {
        [Environment]::SetEnvironmentVariable($name,$pilotOldEnv[$name],'Process')
    }
}
~~~

Lệnh chạy foreground để user Ctrl+C đúng process, không background launch. Nếu một localhost API đang chạy có thể giữ nguyên; process pilot dùng port riêng và cùng approved read data. Không dùng `$pilotDns` làm bind URL. Nếu cert subject/DNS/SAN không phù hợp với mẫu, dừng để duyệt phương án cert khác, không đặt AllowInvalid=true.

### 5B. AFTER APPROVAL — rule firewall tối thiểu

**Terminal Administrator riêng**, chỉ sau khi socket5A đã đúng LAN IP và owner path đúng API. Giữ terminal/biến đến rollback. Block không đổi network profile. Điện thoại DHCP đổi IP → không mở rộng subnet; cập nhật approval trước.

~~~powershell
$pilotLanIp = Read-Host 'Approved PC LAN IPv4'
$pilotPhoneIp = Read-Host 'Approved phone IPv4 (one device)'
$phoneAddress = [ipaddress]::Parse($pilotPhoneIp)
if ($phoneAddress.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
    throw 'Require a single approved phone IPv4, not a subnet or wildcard'
}
$pilotPhoneIp = $phoneAddress.ToString()
$pilotPort = 7443
$pilotRuleName = 'WayMark-PublishedPilot-20261029'
$pilotRuleCreated = $false
if (Get-NetFirewallRule -Name $pilotRuleName -ErrorAction SilentlyContinue) {
    throw 'Rule name exists; do not overwrite or adopt it'
}
$ipInfo = @(Get-NetIPAddress -AddressFamily IPv4 -IPAddress $pilotLanIp -ErrorAction Stop)
if ($ipInfo.Count -ne 1) { throw 'Review interface' }
$profile = Get-NetConnectionProfile -InterfaceIndex $ipInfo[0].InterfaceIndex
if ([string]$profile.NetworkCategory -ne 'Public') { throw 'Profile differs from approved plan' }
$listeners = @(Get-NetTCPConnection -State Listen -LocalPort $pilotPort -ErrorAction Stop)
if ($listeners.Count -ne 1 -or $listeners[0].LocalAddress -ne $pilotLanIp) {
    throw 'Unexpected listener binding'
}
$pilotOwnerPid = $listeners[0].OwningProcess
$pilotProcess = Get-Process -Id $pilotOwnerPid -ErrorAction Stop
# Người quản trị đối chiếu PID/path này với đúng process5A trước khi tạo rule.
$pilotProcess | Select-Object Id,ProcessName,Path
$pilotProgram = $pilotProcess.Path
if ([string]::IsNullOrWhiteSpace($pilotProgram)) { throw 'Cannot identify API executable' }
New-NetFirewallRule -Name $pilotRuleName -DisplayName $pilotRuleName `
    -Direction Inbound -Action Allow -Enabled True -Profile Public -Protocol TCP `
    -LocalAddress $pilotLanIp -LocalPort $pilotPort -RemoteAddress $pilotPhoneIp `
    -InterfaceAlias $ipInfo[0].InterfaceAlias -Program $pilotProgram -EdgeTraversalPolicy Block |
    Out-Null
$pilotRuleCreated = $true
Get-NetFirewallRule -Name $pilotRuleName | Select-Object Name,Enabled,Profile,Direction,Action
Get-NetFirewallRule -Name $pilotRuleName | Get-NetFirewallAddressFilter
Get-NetFirewallRule -Name $pilotRuleName | Get-NetFirewallPortFilter
Get-NetFirewallRule -Name $pilotRuleName | Get-NetFirewallApplicationFilter
~~~

PID/path/network output chỉ xem cục bộ. Nếu existing effective allow rules quá rộng hoặc Group Policy chặn, không disable firewall/sửa rule cũ. Yêu cầu chủ quản duyệt lại. PC `Test-NetConnection` không chứng minh rule cho phone; phone test cần tiếp tục4D.

## 6. Rollback Steps

1. Copy sanitized evidence trước khi rời Navigation. Pause/stop Live hoặc manual fallback; đóng app theo nhu cầu, không xóa data/uninstall APK.
2. Ctrl+C **terminal API pilot5A**; `finally` phục hồi đúng process environment ban đầu. Terminal local4C cũng Ctrl+C nếu do phiên này tạo. Không kill mọi dotnet/SQL Server. Nếu terminal đã mất, đối chiếu PID, executable, start time và socket đã ghi trước khi stop đúng process; không dùng PID cũ mà không kiểm lại.
3. Trong **cùng terminal Admin tạo rule5B**, chỉ xóa rule phiên này:

~~~powershell
if ($pilotRuleCreated) {
    Remove-NetFirewallRule -Name $pilotRuleName -ErrorAction Stop
    $pilotRuleCreated = $false
}
Get-NetFirewallRule -Name 'WayMark-PublishedPilot-20261029' -ErrorAction SilentlyContinue |
    Select-Object Name,Enabled
Get-NetTCPConnection -State Listen -LocalPort 7443 -ErrorAction SilentlyContinue |
    Select-Object LocalAddress,LocalPort,OwningProcess
~~~

Không còn rule vừa tạo và không còn listener pilot là expected. Nếu PID khác đã dùng port sau đó, kiểm riêng, không kill. Nếu terminal rollback mất, quản trị viên xác minh đúng rule name/filter/approval record rồi mới xóa; không dùng wildcard remove.

4. Không có file config nào cần restore theo kế hoạch này. Đóng terminal pilot loại process env; không ghi user/machine env. Nếu sau này duyệt phương án chỉnh file, backup bytes/hash ngoài Git trước, restore **chỉ thay đổi phiên đó**, không dùng Git để thay dirty files.
5. Cert/DNS/router/profile **chưa thay trong preflight**. Nếu có một approval riêng cho provisioning thì rollback theo record cụ thể đã duyệt: chỉ cert/trust/DNS record phiên tạo, không gỡ cert dùng chung hoặc trust store toàn bộ. Thiếu record thì dừng, hỏi chủ quản; không `dev-certs --clean`.
6. Giữ nguyên database, rows publication/QR, image objects/manifests/leases, APK, auth/CORS. Không “dọn” bằng delete/revoke/purge/migration. Kiểm app/API local trước đó vẫn theo baseline; port5121/7199 chỉ phải trở về trạng thái trước phiên thực thi, không ép đóng process có sẵn.

## 7. Failure Classification

| Bằng chứng | Nhóm lỗi / bước xử lý tiếp |
|---|---|
| Không listener đúng port, terminal startup exit | API chưa chạy/startup fail: kiểm SDK/build assets/JWT config/cert/local port; không sửa network trước |
| SQLBrowser dừng nhưng SELECT local pass | Không kết luận SQL fail; Browser không phải gate bắt buộc ở transport hiện có |
| PC loopback200, LAN DNS sai/NXDOMAIN | DNS/hostname; kiểm tên và record đã duyệt, không đổi QR host |
| PC TCP false | Bind/port/process/routing/firewall; TLS chưa bắt đầu. Ping fail không đủ kết luận vì ICMP có thể bị chặn |
| PC TCP true, HTTPS handshake/name/chain fail | TLS: SAN, expiry, full chain, trust store, clock. Không bypass/accept warning |
| PC HTTPS200, phone timeout | Phone Wi-Fi khác mạng, AP/client isolation, VPN/DNS khác, firewall IP/profile/routing; không suy SQL fail |
| Phone browser HTTPS200, app `published_network` hoặc timeout | Chưa phân biệt chắc TLS/socket bằng message Flutter; kiểm đúng endpoint, app trust, DNS/VPN rồi public GET. Không gắn nhãn CORS cho native Android |
| 301/302/307/308 | Sai final origin/proxy/HTTPS redirect; app không follow. Sửa endpoint được duyệt, không cho redirect tới host tùy ý |
| `/weatherforecast`200 | Transport/routing PASS riêng; không chứng minh DB/QR/ảnh |
| Public401/403 | Server/proxy/auth policy không như public contract; không thêm JWT để che lỗi hoặc tắt auth |
| QR404 (`map_not_found`) | Không tồn tại/malformed token hoặc publication lookup; không phân biệt bằng404 đơn lẻ, owner đối chiếu QR đúng môi trường |
| QR409 `map_not_published` | QR chưa có PublishedVersion; dừng, không tự publish |
| QR410 `qr_revoked` / `qr_node_missing` | Thu hồi hoặc node không có trong pinned snapshot; không dùng correction |
| API503 `draft_storage_unavailable` | DB/provider exception theo filter; SELECT operator pass vẫn có thể API identity/schema/SQL transport khác |
| API503 `image_storage_unavailable` / `image_storage_configuration` | Storage disabled/root unsafe; không tạo root trống, không tự cấp quyền |
| API503 `image_object_unavailable` / `image_metadata_invalid` / `image_integrity_failure` | File thiếu/metadata/hash; owner storage đối chiếu, không thay ảnh/nới validation |
| Image404 (`map_not_found`) | Thiếu binding publication/asset, chưa chứng minh file vật lý mất |
| API503 `draft_unavailable` | Lỗi khác được sanitize; không chắc SQL hay filesystem chỉ từ503; kiểm server cục bộ, không gửi raw exception |
| App `published_invalidQr`, `published_snapshotInvalid`, `published_imageUnavailable` | Parser/JSON/schema/image decode/limit; đối chiếu stage HTTP/MIME/size. HTTP200 HTML cũng là lỗi payload/proxy |
| `published_mapMismatch` / `published_versionMismatch` / anchor missing | QR correction khác context hoặc membership; giữ pin/pose, mở hành trình mới nếu cần, không ghép ID |
| Map tải, preflight blocked/partial | Dữ liệu/readiness/geometry có giới hạn; khác network fail. Dùng manual/QR, không ép dot đi |
| Sensor denied/unavailable/register failure | Quyền/capability/native lifecycle; khác API fail; không giả step |
| Detector có count nhưng dot dừng | Có thể heading stale/budget40/edge selection/uncertain/pause; đọc guidance + sanitized reason, không tự tăng budget |
| Lắc sinh step/dot tiến | Ghi false events với ground truth0; chưa có anti-shake acceptance, không gọi accuracy PASS |

Các tên code từ `MapProjectService`, `MapDraftExceptionFilter`, `published_read_failure.dart`; QR/snapshot/image có thể dùng chung `map_not_found`. Không dựa vào HTTP status đơn lẻ để kết luận nguyên nhân cuối cùng. CORS là browser policy; giữ policy hiện có. [Microsoft CORS](https://learn.microsoft.com/en-us/aspnet/core/security/cors?view=aspnetcore-10.0)

## 8. Expected Evidence

Mỗi gate giữ PASS/FAIL/NOT TESTED độc lập, kèm thời điểm Asia/Saigon và trial alias. Không gửi token/QR ảnh rõ, URL chứa secret, JWT, connection strings/SQL credentials, physical storage paths, raw map/node/edge IDs hoặc location trace.

| Bằng chứng cần có sau lượt thực thi | Preflight hiện tại |
|---|---|
| APK hash/package/signature local | CONFIRMED mục1; phone install/update NOT TESTED |
| Local API process/listener/weather200 + TLS verification | NOT TESTED; chỉ inventory/source |
| SQL service/ONLINE/schema4/aggregate | CONFIRMED bằng operator SELECT; API SQL runtime chưa kiểm |
| Image filesystem inventory | CONFIRMED counts; public binding/hash/decode NOT TESTED |
| Approval record: IP/DNS/cert scope/port/phone/profile/rule/timebox/rollback owner | Chưa điền/chưa duyệt, không đưa private deployment detail vào report chia sẻ |
| Phone browser HTTPS200 không warning | NOT TESTED |
| PC resolver→snapshot→từng ảnh | NOT TESTED |
| Phone camera→resolver→snapshot→ảnh→Search/Preview/Navigation | NOT TESTED |
| Preflight +5 setup steps +real detector vs manual steps +dot | NOT TESTED |
| QR correction cùng pin; error trước/sau đo riêng | NOT TESTED |
| Pause/resume/manual fallback và copy sau close | NOT TESTED |
| Rollback port/rule đúng phạm vi | NOT APPLICABLE trong preflight vì chưa mở mạng |
| Real positioning accuracy | NOT VERIFIED; không có số đo mới |

JSON từ toolkit là `WayMarkPilotEvidence1`, checklist do người dùng tự khai báo; vẫn có `physicalAccuracy=NOT_VERIFIED` và `publishedServerCameraE2e=NOT_INDEPENDENTLY_VERIFIED`. Không sửa flags để biến user report thành independently verified. Dùng [field template](PublishedPilotFieldTrialTemplate20261028.md) ghi ground truth/manual count/detector/accepted displacement/stride/estimate/error trước-sau QR/false events/hold/uncertain/budget/pause. Ground truth0 dùng false count, không chia0; distance bias không phải endpoint position error.

## 9. GO / CONDITIONAL GO / BLOCKED

- **GO — preflight/documentation:** đã hoàn tất audit, SQL SELECT aggregate, inventory storage, verify APK và đối chiếu source.
- **CONDITIONAL GO — loopback/operator server-read trial:** chạy bằng đúng Development config/identity, không migrate/seed, cert PC verify thành công; các lệnh4C–E hiện chưa chạy.
- **BLOCKED — phone Published E2E execution hiện tại:** chưa có endpoint LAN/DNS/certificate Android trust đã chốt, chưa có approval cho thay đổi mạng, chưa có QR/phone trial thật.
- **NOT VERIFIED — native sensor accuracy/Published camera E2E:** giữ nguyên cho đến có evidence thật; user smoke Local Pilot trước đây không thay cho gate này.

Phê duyệt tiếp theo cần chốt **một phương án endpoint cụ thể**: endpoint HTTPS đã quản lý, hoặc LAN plan mục5 với đủ giá trị và trust prerequisites. Không áp dụng network/security change trong lượt bàn giao này.

## 10. Verification & Change Safety

Đã đọc ba tài liệu Sprint7/Runbook/FieldTemplate, source API/Published/storage/security/Flutter Live Test/native manifests; đối chiếu tài liệu chính chủ về Kestrel/certificate stores/Dart/Android/firewall/CORS. Không chạy lại Flutter/.NET test/build vì chỉ thay Markdown; log532 PASS/4 SKIP của Sprint7 là bằng chứng cũ, không phải test của preflight.

Các command thực thi: Git inventory/SHA256; selective JSON parsing chỉ xuất boolean/count; .NET SDK/devcert check; services/listeners/network/firewall inventory; SQL `SELECT DATABASEPROPERTYEX`, `sys.tables`, count publications và active published QR; directory metadata counts; APK hash/aapt/apksigner. Lần probe PowerShell đầu gặp lỗi setter `ConnectTimeout` trước khi mở connection; đã đổi đúng cú pháp `['Connect Timeout']` và chạy thành công. Không dùng output lỗi có secret.

SQL connection từ Windows identity hiện tại; không thay connection string lưu trữ hoặc thêm Encrypt/TrustServerCertificate override, chỉ timeout5s cho operator probe. Không INSERT/UPDATE/DELETE/DDL/migration/grant, không SELECT token/content. SQL có thể ghi audit/query statistics nội bộ khi nhận SELECT; không có application data mutation được yêu cầu.

Không start API/ADB/camera, không HTTP tới QR thật, không firewall/bind/DNS/certificate/profile/tunnel change, không chỉnh appsettings/secrets/source/APK, không install/upload. SHA256 baseline tracked/untracked không bị ignore dùng để kiểm cuối; APK hash kiểm riêng vì build bị ignore.

Hai file được phép thay đổi:
- Tạo `docs/PublishedPilotExecutionPreflight20261029.md`.
- Sửa `docs/PublishedPilotRunbook20261028.md`: sửa binding hostname→specific IP, thêm trust distinction và link preflight.

Kiểm tra cuối: baseline **520 file /377 status entries**; sau preflight **521 file /378 entries** (43 modified +335 untracked). **519/520 file cũ giữ nguyên SHA256**; chỉ Runbook cũ đổi hash, chỉ thêm báo cáo này, không mất file. Không có staged entry; branch `auth-jwt-assignment` giữ nguyên. APK Sprint7 kiểm hash/signature riêng, giữ nguyên.

**9/9 block PowerShell parse không lỗi**, local Markdown links tồn tại, kiểm whitespace đạt. Đây là kiểm cú pháp/hướng dẫn; không đánh các block startup/LAN/HTTP/phone chưa chạy thành PASS. Build/test và các thay đổi network trong block mẫu không được thực thi trong lượt này.



