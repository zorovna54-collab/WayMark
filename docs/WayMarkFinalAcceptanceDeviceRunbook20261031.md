# WayMark — Final Acceptance Device Runbook

Ngày chuẩn bị: **31/10/2026 — Asia/Saigon**.
Một campaign tổng thể, **không mở Development Cycle mới**. Tài liệu này rút gọn [checklist A–J](WayMarkFinalAcceptanceChecklist20261031.md); giữ checklist gốc cho expected results chi tiết.

**Chưa yêu cầu thử ngay.** Đóng gói đã xong; full Published phone campaign chờ [approval packet mụcE](WayMarkFinalAcceptanceEnvironmentReadiness20261031.md). Tất cả kết quả người thử dưới đây **NOT TESTED**.

## Chuẩn bị trước buổi thử

- Hai APK Cycle3 + README + manifest trong `waymark/build/final-acceptance-handoff/`, hash đúng trước cài. Main và Live Test là internal debug, khác package.
- **Main Cycle3 hiện trỏ `http://10.0.2.2:5121/api`, không đổi global endpoint trong Settings.** Chỉ UI/Probe/Local Pilot có thể chạy độc lập. Full account/Published phone test cần Main build mới với endpoint HTTPS đã phê duyệt; không dùng alias emulator trên phone.
- Live Test có ô endpoint HTTPS cho **Published guest**; không đổi Auth/Creator/History. Có thể dùng nó cho guest Published sau khi endpoint/QR sẵn sàng.
- Endpoint FQDN/SAN/chain, interface/port/firewall allowlist và time window đã được duyệt, triển khai, kiểm chứng bằng TLS mặc định. Không import CA/bypass/cleartext để vượt lỗi.
- API, SQL và image storage đúng runtime identity/config hoạt động suốt buổi. Chỉ API HTTPS được phone truy cập; không cần mở SQL ra mạng.
- Test workspace không nhạy cảm và account A/B được owner cho phép; quyền create/publish/revoke case thử phải rõ. Không dùng map người khác.
- Camera, activity recognition do người thử chủ động chấp thuận khi bật chức năng; model/OS/API/sensor capabilities ghi tại buổi thử.
- Hành lang an toàn đo thật10–20m, người quan sát/clicker, cách cầm máy và test fixture geometry phù hợp. Có backup nháp cần giữ; không uninstall/wipe app data.
- AI provider/budget nếu cần case H phải được cho phép riêng; không mặc định AI dùng cùng API endpoint.

Thiếu prerequisite thì ghi **NOT TESTED + blocker**, không làm thêm infrastructure change để đạt PASS. Không cần thử rời rạc trong khi chờ hạ tầng.

## Thứ tự một buổi nghiệm thu

| Bước | Checklist | Prerequisite riêng | Thao tác /bằng chứng cần giữ | Result |
|---|---|---|---|---|
|1. Cài/cập nhật Main và Live Test | A | Hash/package/key đúng, Android24+ với ABI phù hợp; đủ dung lượng | Cài từ Files qua kênh nội bộ đã cho phép; chọn update nếu phù hợp. Mở cả hai, ghi filename/hash/version và thông báo cài. Signature/code mismatch thì dừng, không uninstall | NOT TESTED |
|2. Giao diện cơ bản | A, H | Cài thành công; chưa cần API cho entry/local | Main vào Login/Guest/Local Builder; Live Test vào debug home riêng. Back/reopen, text scale2/landscape/keyboard/focus; không cấp role hoặc xóa data | NOT TESTED |
|3. Probe và Local Pilot offline | E | Android thật, hành lang pilot bố trí đúng; không cần API | Probe sáu sensor → deny rồi chỉ grant nếu người thử đồng ý → Start/đi/dừng/quay → Stop. Background/foreground10 vòng, Stop/Back dừng collection. Local Pilot opt-in Live theo5 bước anchor→sensor→stride→hành lang/hướng→start. Ghi counts/frame/reason; synthetic pilot không phải real Published map | NOT TESTED |
|4. Creator/Builder/Save/Reload | B | Main mới đúng approved HTTPS endpoint, API/SQL/images, tài khoản A/quyền hợp lệ | Tạo workspace thử, ảnh không nhạy cảm, node/cạnh có hướng/metres; Save rồi read server/reopen. Thử chỉnh chưa lưu→Back/giữ nháp, export/import backup riêng và Cancel save. Không import đè dữ liệu thật | NOT TESTED |
|5. Publish test map và lấy QR | C | Saved version hợp lệ, owner cho phép publish QR | Đọc lại server, chọn start node→tạo QR saved version→Cancel publish một lần→xác nhận publish riêng. Giữ QR PNG/payload riêng. Sửa draft sau publish và kiểm QR cũ vẫn pin; revoke chỉ test QR riêng nếu đã được cho phép | NOT TESTED |
|6. Visitor camera→Search→Navigation | D | Authorized QR, approved endpoint, ảnh đúng version | Main Guest/Visitor hoặc Live Test guest với ô HTTPS đúng `/api`. Camera Cancel/return rồi scan; kiểm start/tầng, snapshot/ảnh, đích, Preview/Navigation và pan/zoom. Manual/QR confirmation và Finish rõ. Guest không cần JWT | NOT TESTED |
|7. Published Live Tracking | E | Phiên Published pin đúng, Android detector/orientation phù hợp, corridor geometry và mét đã kiểm thật | Opt-in Live, neo/stride/hướng/hành lang theo guided flow; đi/dừng/quay tại chỗ và ghi estimated/uncertain/verified riêng. Geometry/heading/permission không đủ thì hold/manual. Không timer-step, không tự Finish vì dot tới đích | NOT TESTED |
|8. QR correction /multi-floor /manual | F | QR thứ hai cùng map/version, transition fixture được phép | Mở scan→Cancel không replay bước; scan hợp lệ reset anchor/baseline; lỗi/trễ không overwrite pose mới. Junction ambiguous dùng lựa chọn rõ/manual. Chuyển tầng cần xác nhận/anchor, không nội suy hai ảnh. Kiểm budget gần32/movement41 trong ca an toàn | NOT TESTED |
|9. History /account /recovery /Settings | G, H | Main approved endpoint, A/B hợp lệ; provider AI riêng nếu test thật | Một journey **đăng nhập A** explicit finish→History đúng một session; Guest không kỳ vọng History. Đổi A/B với draft/dialog đang mở theo case G, giữ owner isolation. Expiry401 thật không xóa RAM/auto save;403/network không thành logout. Profile/AI review/cancel/timeout/layout theo H, không sửa secret hoặc validation để ép lỗi | NOT TESTED |
|10. Đo thực địa và đóng evidence | I, J | Ground truth và threshold do product owner chốt; consent export diagnostics | Ghi từng lượt thật, steps truth/detector/counter riêng, distance/endpoint error **trước correction QR**. Đi–dừng, quay tại chỗ, đi ngược/cách cầm trong ca riêng; giữ lượt lỗi. Tổng hợp theo model/người/case và xuất diagnostics opt-in đã kiểm sanitize | NOT TESTED |

Trong mọi bước, dùng mẫu bug J: case/time/APK hash/model/OS/người thử ẩn danh → preconditions → steps/expected/actual → PASS/FAIL/NOT TESTED → evidence đã redact. Không đợi đến cuối mới ghi lỗi. Không tự chữa UI/thuật toán khi chưa có lỗi và scope được giao.

Nếu chỉ có một phone, nêu pilot hạn chế, không suy rộng OEM khác. Campaign đề xuất2 người×2 phone, mỗi cặp5 lượt mỗi chiều; thêm ca dừng/quay/đi ngược và battery riêng như checklist I. Steps truth0 dùng false-step count, không chia0. Accuracy threshold chưa chốt thì báo số đo, không tự phát minh PASS.

## Kiểm kết nối trước khi bắt đầu nhóm online

Các lệnh dưới đây là **read-only cho lúc endpoint đã được phê duyệt/triển khai**; không start/bind LAN hoặc sửa firewall. Đọc current listener/profile bằng:

~~~powershell
Get-NetTCPConnection -State Listen -LocalPort 7199,7443 -ErrorAction SilentlyContinue |
    Select-Object LocalAddress,LocalPort,OwningProcess
Get-NetConnectionProfile | Select-Object InterfaceAlias,InterfaceIndex,NetworkCategory
Get-NetFirewallProfile | Select-Object Name,Enabled
~~~

Với phương án LAN A, expected chỉ loopback7199 và đúng LAN IP:7443 trong scope được duyệt; không wildcard/HTTP listener mới. Nếu chọn managed443, dùng expected topology đã review thay vì áp port7443 cho mọi phương án.

PC kiểm HTTPS mặc định với approved API base URL **không chứa token**, ví dụ dạng `https://<approved-FQDN>:7443/api`:

~~~powershell
$api = [uri](Read-Host 'Approved HTTPS API base URL (khong QR/token)')
if (!$api.IsAbsoluteUri -or $api.Scheme -ne 'https' -or $api.UserInfo -or
    $api.Query -or $api.Fragment -or $api.AbsolutePath.TrimEnd('/') -ne '/api') {
    throw 'Expected approved HTTPS origin + /api only'
}
Resolve-DnsName -Name $api.DnsSafeHost
Test-NetConnection -ComputerName $api.DnsSafeHost -Port $api.Port -InformationLevel Quiet
Add-Type -AssemblyName System.Net.Http
$handler = [System.Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $false
$handler.UseCookies = $false
$client = [System.Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromSeconds(20)
$response = $null
try {
    $uri = [uri]($api.GetLeftPart([System.UriPartial]::Authority) + '/weatherforecast')
    $response = $client.GetAsync($uri).GetAwaiter().GetResult()
    [pscustomobject]@{
        Stage = 'PC HTTPS transport'
        Status = [int]$response.StatusCode
        Http200 = ([int]$response.StatusCode -eq 200)
        Mime = [string]$response.Content.Headers.ContentType.MediaType
    }
} catch {
    [pscustomobject]@{ Stage = 'PC HTTPS transport'; FailureType = $_.Exception.GetBaseException().GetType().Name }
} finally {
    if ($null -ne $response) { $response.Dispose() }
    $client.Dispose()
}
~~~

Không có validation callback/certificate override. FailureType chỉ định loại, không đủ kết luận root cause; đối chiếu listener/DNS/cert metadata và error đã redact. HTTP3xx phải review đúng endpoint/proxy, không tự bật redirect hoặc gửi JWT qua host khác.

Trên phone cùng mạng được duyệt: browser mở **origin đã duyệt + `/weatherforecast`**, không QR URL, không click-through certificate warning. Sau đó app Main mới → Settings/Kết nối API probe kiểm chính Flutter network stack. Probe anonymous chạm protected endpoint có thể trả401 và chứng minh reachability/TLS; **không** là login/data PASS. Browser200, app probe và Published resolver là ba gate khác nhau.

PC `/weatherforecast`200 không chạm SQL. PC không mô phỏng camera/phone TLS. Muốn kiểm resolver→snapshot→images trước camera, dùng **GET-only PowerShell đoạn4C/4E** tại [PublishedPilotExecutionPreflight20261029.md](PublishedPilotExecutionPreflight20261029.md), authorized input riêng, không transcript/raw body/token output. Không SELECT QR từ SQL.

## QR và dữ liệu thử

Hiện tại: **AUTHORIZED_QR_NOT_AVAILABLE**. Không cần gửi QR lên chat để hoàn tất readiness.

Owner lấy QR từ Server/Publish/QR của test workspace có quyền quản lý. Ưu tiên PNG để hiển thị trên PC cho phone camera. Nếu cần PC payload file, dùng editor local, lưu ngoài repo/handoff/cloud-sync và kiểm ACL phù hợp; xem [readiness mụcF](WayMarkFinalAcceptanceEnvironmentReadiness20261031.md). Không đặt payload trong command line hoặc bug report. Case multi-floor/second-anchor/revoked QR cần fixture được phép riêng; thiếu thì NOT TESTED, không tự tạo/revoke map thật.

Record stage/status/HTTP MIME/bytes và validation booleans; không ghi map/database IDs, QR token/full request URL, JWT/password/connection string/private map content. Dù client không log token, server/proxy có thể log request path: không chia sẻ raw access logs.

## Khi lỗi hoặc prerequisite thiếu

- Không listener/process exit: startup/config/runtime identity; TCP/DNS failure: network/listener/profile; TLS failure: hostname/SAN/chain/clock. Dừng đúng lớp, không cleartext/bypass/import certificate.
-401 private request: session;403: permission/owner/policy. Không grant Admin, sửa JWT hoặc retry mutation mù. Timeout sau Save/Publish có thể đã commit: read/reconcile trước khi retry.
- QR404/409/410: locator/not-published/revoked-or-missing-node. Snapshot/image5xx hoặc MIME sai: SQL/storage/proxy/data pin; không thay demo image hay reset storage.
- Sensor absent/permission denied/heading stale/ambiguous: fallback và ghi reason; không tự chạy dot. “Không crash” không chứng nhận accuracy.
- Bug UI/rendering vẫn giữ ảnh/snapshot/route gốc để tái hiện nếu được phép; không gửi private data công khai.

## Kết thúc campaign

1. Stop Live/Probe, rời navigation và kiểm collection dừng; export diagnostics chỉ khi người thử chủ động cho phép.
2. Kiểm screenshot/diagnostics trước chia sẻ: che QR/IDs/email/private maps; lưu số đo raw nơi riêng được phép, giữ cả lượt lỗi.
3. Operator dừng đúng API PID đã khởi động cho phiên, kiểm listener về baseline. Nếu có approved LAN rule/DNS/profile mới, rollback đúng scope đã ghi; không kill process khác, không reset data hoặc xóa localhost trust.
4. Không tự revoke/delete test map hoặc xóa app data khi chưa có owner instruction; giữ APK gốc và bản ghi kết quả.
5. Chốt checklist A–J từng case. Thiếu fixture/infrastructure/provider thì NOT TESTED và blocker, không đánh PASS theo build logs.

| Exit gate | Hiện tại |
|---|---|
| APK handoff integrity | VERIFIED trên PC |
| Main full phone endpoint | BLOCKED, chờ approval + endpoint build |
| Authorized QR /Published read mới | AUTHORIZED_QR_NOT_AVAILABLE /NOT TESTED |
| PHONE PUBLISHED E2E | NOT TESTED |
| SENSOR PHYSICAL ACCEPTANCE | NOT TESTED |
| FIELD ACCURACY | NOT TESTED |
| Final campaign owner/date/decision | Chưa thực hiện |
| Production signing/deployment | PENDING, approval riêng |

Chỉ bắt đầu campaign tổng thể sau khi prerequisites tương ứng đạt; tài liệu chuẩn bị không phải biên bản nghiệm thu.
