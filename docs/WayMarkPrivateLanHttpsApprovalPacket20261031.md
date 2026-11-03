# WayMark — Private LAN HTTPS Pre-deployment Decision Pack

Ngày: **31/10/2026 — Asia/Saigon**. Workspace: `D:\project\WayMark`.

**Phương án A được chọn về kiến trúc; CHƯA phê duyệt triển khai.**
Decision pack hoàn tất; **LAN HTTPS DEPLOYMENT: BLOCKED / APPROVAL REQUIRED**.
Không mở Cycle4. Không thử chức năng trên điện thoại trong lượt chuẩn bị này.

Quy ước: **VERIFIED** = metadata/source đã kiểm trong lượt này; **PRIOR EVIDENCE** = báo cáo phiên trước; **OWNER CONFIRMATION REQUIRED** = không suy đoán; **PLANNED, NOT EXECUTED** = chưa áp dụng.

Đã đối chiếu [Environment Readiness](WayMarkFinalAcceptanceEnvironmentReadiness20261031.md), [Device Runbook](WayMarkFinalAcceptanceDeviceRunbook20261031.md) và [Checklist A–J](WayMarkFinalAcceptanceChecklist20261031.md). Tài liệu này cụ thể hóa approval hạ tầng; không thay checklist hoặc tự điền physical PASS.

## A. Verified prerequisites

| Hạng mục | Kết quả | Giới hạn |
|---|---|---|
| Adapter | Wi-Fi, InterfaceIndex **17**, Up | Không thu SSID/BSSID/MAC hoặc danh sách thiết bị khác |
| LAN IPv4 | **192.168.1.21/24**, origin **DHCP** | Có thể thay đổi; cần xác minh lại trước triển khai, không tự đặt IP tĩnh/reservation |
| Gateway | **192.168.1.1** | Không đăng nhập/đổi cấu hình router; không chứng minh quyền sở hữu mạng |
| Network category | **Public** | **OWNER CONFIRMATION REQUIRED** về mạng riêng/tin cậy; IP RFC1918 hoặc profile không chứng minh ownership |
| DNS IPv4 của laptop | **116.97.90.124**, **116.97.90.127** | Không phải gateway; chưa biết resolver của phone |
| NRPT | Effective policy trả **0** rule | Không chứng minh router/phone/VPN/Private DNS không có policy khác |
| Firewall effective ActiveStore | Domain/Private/Public đều Enabled; inbound **Block**, outbound **Allow**; local-rule merge True | Không thay policy. Quyền admin để áp rule chưa được thử bằng mutation |
| Enabled inbound allow rules | **162** tổng; **131** có Private hoặc Any; **50** có Private nhưng không Public/Any | Đây là eligibility theo profile, không phải số port sẽ mở hoặc kết quả port scan |
| Network Discovery | **10** trong 50 rule nêu trên có tên prefix `NETDIS-` | Cần owner review các rule khác trước khi duyệt đổi profile |
| Listener | **0** ở 5121/7199/7443 | Chỉ các cổng kiểm, không kết luận mọi API/port đều dừng |
| API process configuration | Không có hosting override key Kestrel/URLS/HTTP_PORTS/HTTPS_PORTS trong process environment đang kiểm | Không đọc lại secret-backed configuration; báo cáo trước đã audit cấu hình. Prelaunch vẫn cần gate listener/config |
| API source/runtime artifacts | Program.cs dùng WebApplication.CreateBuilder; không thấy explicit Listen/UseUrls/ConfigureKestrel trong file; existing net10.0 DLL/apphost có sẵn | Không launch API, build hoặc kiểm SQL runtime mới |
| Tooling | dotnet executable, Flutter bat, cmdlets NetSecurity/NetConnection/DNS cần thiết tồn tại | Availability không chứng minh có quyền đổi mạng |
| FQDN/certificate của pilot | Chưa có owner-provided FQDN hay public certificate metadata/path | Không enumerate certificate stores hoặc tìm PFX/private key để thay đầu vào thiếu |
| Main/Live Test | Hash APK gốc/copy được lấy lại; đối chiếu config bằng source + evidence compile Cycle3 | Chi tiết ở F; không rebuild/re-sign |

Audit đã dùng Get-NetAdapter/IPAddress/Route/ConnectionProfile, Get-DnsClientServerAddress, Get-DnsClientNrptPolicy, Get-NetFirewallProfile/Rule/PortFilter/AddressFilter và Get-NetTCPConnection. Không scan phone/router ports, không query DNS cho placeholder và không gọi endpoint API.

### DNS/router constraints còn chưa xác minh

- Quyền quản lý router, AP/client isolation, guest Wi-Fi/VLAN và router WAN/UPnP mappings: **NOT VERIFIED**. Cùng subnet không bảo đảm phone được nói chuyện với PC; không tuyên bố đã chứng minh không có WAN exposure.
- Router DNS override chỉ có tác dụng với client thực sự dùng resolver đó. Windows hiện dùng hai DNS server khác gateway; Windows hosts entry cũng không cấu hình DNS cho phone.
- Phone có thể dùng Private DNS/VPN/proxy khác Windows. Cần owner xác nhận cấu hình đang có, không tự tắt chúng. Google mô tả Private DNS riêng trong [Android network settings](https://support.google.com/android/answer/9654714?hl=en).
- Resolver có thể lọc private-IP answers từ upstream. Ví dụ dnsmasq có cơ chế chống DNS rebinding; **chưa biết router này dùng phần mềm/policy gì**. Không đề xuất tắt filter toàn cục. Xem [dnsmasq manual](https://dnsmasq.org/docs/dnsmasq-man.html).
- FQDN cuối cùng cần A record resolve đúng PC trên cả laptop và phone; không có AAAA/địa chỉ khác ngoài scope được duyệt. DNS cache/TTL và DHCP changes là gate trước scan QR.

## B. User-provided values còn thiếu

Hai câu hỏi thông tin domain/DNS và ownership Wi-Fi đã được gửi trong phiên chuẩn bị; **chưa có câu trả lời tại lúc chốt packet**. Không dùng lựa chọn mặc định trong UI làm câu trả lời hoặc approval.

| Input owner cần chốt | Cần cung cấp an toàn | Hiện tại |
|---|---|---|
| A. Domain/DNS | Có/không domain; có quyền sửa authoritative DNS hay người có quyền; provider loại nào, không credential | OWNER CONFIRMATION REQUIRED |
| B. FQDN | Tên cụ thể, ví dụ cấu trúc `pilot.<owner-controlled-domain>`; đây chỉ là placeholder | NOT PROVIDED |
| C. Phone IP | IPv4 thực tế từng phone trên đúng Wi-Fi tại thời điểm thử; model/Android/API nếu biết | NOT PROVIDED — không suy từ ARP/DHCP clients |
| D. Trusted network | Xác nhận owner quản lý và tin cậy Wi-Fi; có quyền đổi profile/router DNS nếu cần | OWNER CONFIRMATION REQUIRED |
| E. Time window | Ngày/giờ bắt đầu–kết thúc, múi giờ +07:00, tối đa **2 giờ** | NOT PROVIDED |
| F. Stop/rollback owner | Vai trò/người chịu trách nhiệm trực tiếp, có khả năng stop process và gỡ rule đúng hạn | NOT PROVIDED |
| G. Data scope | Test workspace alias, account A/B pseudonyms, quyền create/save/publish và authorized QR; revoke/delete là scope riêng | NOT PROVIDED; AUTHORIZED_QR_NOT_AVAILABLE |
| H. Approval từng nhóm | DNS record/issuance; profile; firewall; process binding; Main endpoint build; data actions | EXECUTION NOT APPROVED |

Nếu đã có certificate phù hợp, owner chỉ chỉ định **public metadata**: subject, SAN, issuer/chain, validity, thumbprint kèm thuật toán. PFX path có thể giữ riêng trên máy khi triển khai; không yêu cầu gửi PFX/password/private key/DNS API key/JWT/QR payload hoặc tên tài khoản thật lên chat.

**Cách xem phone IP, khi owner chuẩn bị thông tin:** Android Settings → Network & Internet → Internet/Wi-Fi → mạng đang kết nối → biểu tượng bánh răng/Network details/Advanced → IP address. Samsung thường là Connections → Wi-Fi → bánh răng → View more. Tên menu tùy OEM; chỉ đọc IPv4 hiện có, không đổi DHCP sang Static hoặc cung cấp MAC/serial. Kiểm lại IP ngay trước buổi thử; không chọn một địa chỉ còn trống theo suy đoán.

## C. Proposed exact endpoint architecture

| Thành phần | Đề xuất cố định hoặc còn thiếu |
|---|---|
| Phone API base URL | `https://<approved-FQDN>:7443/api` — **FQDN chưa có** |
| PC bind | `https://192.168.1.21:7443` trên Wi-Fi17; phải xác minh DHCP/IP còn đúng trước launch |
| Loopback riêng | `https://localhost:7199`, tương ứng127.0.0.1/::1 nếu stack hỗ trợ; certificate localhost hiện tại độc lập |
| Kestrel | Một owned API process, hai named endpoints **Loopback** và **Pilot**, không wildcard hoặc HTTP listener |
| Firewall | Inbound TCP7443, LocalAddress192.168.1.21, InterfaceAlias Wi-Fi, Profile Private, RemoteAddress từng approved phone IPv4 |
| SQL/storage | Giữ local, runtime Windows user hiện tại; không Windows service identity mới, không SQL exposure/grant/migration |
| API private/public | JWT/authorization/rate limits giữ nguyên; Published resolver/snapshot/images anonymous theo contract hiện có |
| Network boundary | Không WAN forwarding, public tunnel hoặc listener IPv6 LAN; không thay auth/CORS để sửa network failure |

Các key **chỉ trong child-process environment**, không appsettings/source/user-secrets edit:

| Key mới dự kiến | Giá trị đề xuất |
|---|---|
| Kestrel__Endpoints__Loopback__Url | https://localhost:7199 |
| Kestrel__Endpoints__Pilot__Url | https://192.168.1.21:7443 |
| Kestrel__Endpoints__Pilot__Certificate__Path | Absolute owner-approved server PFX path, chưa được chỉ định |
| Kestrel__Endpoints__Pilot__Certificate__Password | Chỉ nếu PFX yêu cầu, qua local secret input được duyệt; không argv/log/report |
| ASPNETCORE_ENVIRONMENT /DOTNET_ENVIRONMENT | Development cho child API theo môi trường hiện tại |

Không set `Kestrel__Certificates__Default`: tránh thay cert loopback. Không trộn thêm `--urls`/wildcard hoặc launch profile mở HTTP5121. Nếu config khác vẫn thêm endpoint ngoài scope, **stop đúng owned process và BLOCKED**, không tự sửa config bí mật.

Kestrel hỗ trợ named endpoints từ configuration và cert riêng cho endpoint; endpoint thiếu cert dùng fallback default/dev cert. Tham chiếu [Kestrel .NET10](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/servers/kestrel/endpoints?view=aspnetcore-10.0). Cần kiểm binding thực tế, không coi FQDN/SNI là giới hạn interface.

## D. Certificate /hostname plan

**Chưa có certificate được owner chỉ định cho pilot. Không tìm hoặc tạo cert trong phiên này.** Localhost dev cert đã trust ở Windows theo report trước chỉ phục vụ loopback; không reuse để gọi FQDN trên Android.

Phương án có điều kiện khi owner có domain/DNS:

1. Chốt FQDN, CA/client và người quản lý DNS; xác nhận quyền thay đúng record. Không tự đăng ký ACME account hoặc mua domain/dịch vụ.
2. Ưu tiên **DNS-01**: owner phê duyệt tạo TXT `_acme-challenge.<approved-FQDN>` tại authoritative DNS hoặc delegation phù hợp. DNS-01 không đòi mở web API/port80 ra Internet. DNS API credentials và ACME account key do owner quản lý local; không đọc trong pre-deployment.
3. CA/client cụ thể chưa được chọn nên **chưa có lệnh issuance hoặc DNS-write hoàn chỉnh để approve**; không giả định Certbot/win-acme hay plugin nào đã cài. Sẽ chốt commands sau domain/provider/owner inputs.
4. Owner xác nhận leaf SAN khớp FQDN, Server Authentication purpose, còn hạn toàn phiên; server trình bày leaf và intermediate(s) đúng. Trust root phải được thiết bị chấp nhận sẵn, không import CA vào Windows/Android.
5. Chỉ public metadata được review; việc tạo key/certificate files sau này cần approval issuance riêng. Server sử dụng private key qua approved PFX local khi chạy, không export/print key và không ghi password vào repo/command line.
6. Chọn cách resolve FQDN dưới đây, kiểm A/AAAA và TLS mặc định trên PC rồi Android/app trước mọi QR request.

| DNS routing | Điều kiện /rủi ro cần duyệt |
|---|---|
| **Ưu tiên split DNS nếu đã có resolver LAN được quản lý**: private A record→192.168.1.21; DNS-01 TXT ở authoritative public zone | Cần router/resolver support và cả PC/phone dùng đúng resolver. Windows hiện không trỏ gateway nên không coi router record là đủ; mọi thay đổi DNS client/router cần scope/rollback riêng |
| Public authoritative A→192.168.1.21 | Chỉ dùng khi owner duyệt DNS metadata công khai và các resolver/Private DNS thực tế chấp nhận private answer. Không tự tạo WAN route, nhưng rebinding filter/cache có thể cản; không tắt bảo vệ toàn cục |
| Không có domain/DNS control hoặc không có cách resolve được duyệt | **LAN HTTPS BLOCKED**. Có thể review managed/private HTTPS endpoint có sẵn, đúng CA/SAN và private backend connectivity; không tự tạo public endpoint/tunnel/account hoặc chuyển HTTP |

DNS-01 và delegation được mô tả tại [Let’s Encrypt challenge types](https://letsencrypt.org/docs/challenge-types/). Certificate issuance cũng có thể công khai hostname/public certificate qua CT; rollback API/DNS không xóa lịch sử đó. Owner cần chấp thuận hostname không nhạy cảm. Xem [Certificate Transparency](https://letsencrypt.org/docs/ct-logs/).

**Android gates:** target36/min24 không chứng minh mọi OEM/OS có trust root phù hợp. User-added CA không được mặc định tin cho app target24+; APK hiện không có custom networkSecurityConfig. Dart Android lấy trusted roots từ platform stores. Không sửa validation callback/trust store; cần chứng minh chain trong chính Flutter app, browser200 chỉ là gate riêng. Tham chiếu [Android trust configuration](https://developer.android.com/privacy-and-security/security-config), [Dart defaultContext](https://api.dart.dev/dart-io/SecurityContext/defaultContext.html).

## E. Firewall /profile impact

**Không đổi Public→Private trong lượt này.** Effective rules audit ghi162 inbound allows,131 Private/Any, trong đó50 Private-not-Public candidates;10 là Network Discovery. Mẫu port filters của candidates gồm UDP3702/3540/137 và TCP5357/5358/2869; có mẫu RemoteAddress=Any, có mẫu hẹp hơn.

**INFERRED từ metadata:** đổi profile có thể khiến rules của ứng dụng/dịch vụ khác phù hợp trên Wi-Fi này. Chưa đánh giá mọi app/service/address/interface/block-rule condition, nên không nói50 ports sẽ mở hoặc toàn bộ candidates thực sự reachable. Không tự disable/delete các rules hiện có để làm network “an toàn”.

Owner/admin cần review candidates local trước approval; ưu tiên mạng Private do owner quản lý. Nếu mạng shared/guest hoặc không review được tác động, giữ profile và deployment BLOCKED. Không tạo rule Public như đường vòng.

Lệnh read-only để owner xem danh sách candidates trên máy, không cần gửi raw inventory lên chat:

~~~powershell
Get-NetFirewallRule -PolicyStore ActiveStore -Enabled True -Direction Inbound -Action Allow |
    Where-Object {
        $_.Profile.ToString() -match 'Private' -and
        $_.Profile.ToString() -notmatch 'Public|Any'
    } | Select-Object Name,DisplayName,Profile,PolicyStoreSourceType
~~~

Rule mới đề xuất tên `WayMark-Pilot-7443-<approved-session-id>`: Private-only, đúng local IP/interface, TCP7443, từng phone IP, EdgeTraversal Block; không Any/LocalSubnet/CIDR range/SQL ports. Rule scoped không thay thế auth. Việc chuyển category có tác động ngoài rule mới, cần approval riêng. Tham chiếu [Windows Firewall profiles](https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/) và [New-NetFirewallRule parameters](https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule).

NetSecurity/profile thay đổi có thể cần admin. Không nâng quyền hoặc vô hiệu hóa Windows policy trong phiên này. Nếu thực thi sau, chỉ admin console làm network actions đã duyệt; API tiếp tục chạy dưới Windows user/runtime identity hiện có, không chuyển sang SYSTEM/service user khác.

## F. Android endpoint build requirements

| Artifact/config | Kết quả đối chiếu |
|---|---|
| Main Cycle3 | com.example.waymark, version1.0.0/code1; compiled fallback `http://10.0.2.2:5121/api` |
| Live Test Cycle3 | com.example.waymark.livetest, version1.0.0/code1; cùng service fallback; WAYMARK_LIVE_TEST=true |
| Compile evidence | Hai APK không có WAYMARK_API_BASE_URL define ở Cycle3 build; actual hashes khớp release/handoff manifest |
| Main Settings | Chỉ hiển thị/probe baseUrl; không runtime global editor |
| Live Test Published guest | Runtime URL tạo service riêng, không đổi Auth/Creator/History; QR correction dùng cùng instance/pin |
| Android merged policy | Debuggable/cleartext=true ở hai APK hiện có; không dùng cleartext làm phương án test |
| TLS source audit | Không thấy badCertificateCallback/TrustAll/SecurityContext override trong các luồng đã kiểm; không đổi policy |

Main gốc SHA256 `CADA53AF3B82F586C31B115FF6714CCF03F46D706B4C18C6F0FA3D71376031AB`; Live Test `2A7E8B75F461D2888974420C5A473D96ACAF31DC3B2B863538D6C42ED9389CB4`.

Sau endpoint và build scope approval mới build Main với `WAYMARK_API_BASE_URL=https://<approved-FQDN>:7443/api`; không đổi source. Giữ package và signer SHA256 `8c15d5eb313223a87d82ef435a13307e74f8abf1a9da2e9dd8de9c21b0cf4df2`; không sinh key mới hoặc tăng versionCode khi chưa duyệt. Nếu signing key hiện hữu không sẵn hoặc installed code>1, BLOCKED để chốt update path; không uninstall/downgrade.

Artifact mới tên/session directory mới, manifest/hash/signature mới; giữ cả sáu APK Cycle1/2/3 và hai bản copy handoff. Live Test guest có thể nhập approved HTTPS, không bắt buộc rebuild; optional build riêng dùng flavor liveTest và flag WAYMARK_LIVE_TEST=true. Không đổi AI provider từ ô guest.

Source: `waymark/lib/services/waymark_api_service.dart`, `features/admin/settings_page.dart`, `tool/live_test_main.dart`, Android Gradle/main/debug manifests. Evidence compile: `waymark/build/final-acceptance-readiness-20261031/apk-verification.json`; package/hash manifest ở handoff. Không build/test/install trong lượt này.

## G. Data authorization scope

Đề xuất **một test workspace riêng**, ảnh sơ đồ không nhạy cảm, account A/B do owner cho phép; owner xác nhận quyền create/save/publish và Published QR của workspace. Chỉ dùng aliases trong báo cáo; không cần username/email thật.

Gate hiện tại: **AUTHORIZED_QR_NOT_AVAILABLE**. Không đọc token từ SQL/repository/logs/clipboard hoặc tìm payload file. Không publish/revoke/delete dữ liệu trong lượt này; future revoke/delete fixture cần authorization riêng, không tự cleanup dữ liệu sau test.

Sau approval và khi owner cung cấp input an toàn: default-verified HTTPS → anonymous QR resolver → exact pinned snapshot → node/floor membership → floor images HTTP/MIME/length/integrity → Flutter camera Visitor. PC GET200 không thay phone camera E2E. Dùng GET-only probe mục4C/4E của [Published preflight](PublishedPilotExecutionPreflight20261029.md), không raw URL/body/token logs. Ảnh/map khác ngoài fixture không được đổi; không SQL migration/seed/grant/schema.

Public snapshots/images là anonymous theo contract, không bí mật chỉ vì QR locator khó đoán. Không expose Development/Swagger rộng ngoài approved phone IPs; không chia sẻ access logs có QR paths.

## H. Timebox and rollback

Thời điểm chưa chốt: cần start/end ISO8601 có `+07:00`, tối đa2 giờ và owner chịu trách nhiệm trực tiếp. DNS/certificate/build preparation sau approval có thể làm trước window, không mở listener/rule trong lúc chờ issuance/propagation. Không tự hẹn giờ theo thời điểm hiện tại.

Trước launch, owner lưu record không chứa secret: interface/IP/profile/DNS baseline, exact rule name, API executable/PID/start time, start/end và các DNS record/TTL đã được phép thay. Prelaunch IP/phone/profile/config khác packet thì dừng, không tự điều chỉnh scope.

Rollback theo thứ tự, chỉ những gì phiên đã tạo/thay:

1. Ngừng gửi request, không còn mutation chưa reconcile; stop đúng owned API process. Không kill mọi dotnet. Watchdog/end-window và operator phải được chốt trong bước triển khai; **không có auto-rollback đang chạy trong pre-deployment**.
2. Kiểm7199/7443 về baseline0, không wildcard/new listeners; API stop phải đóng Pilot ngay cả khi DNS cache còn.
3. Gỡ đúng firewall rule do phiên tạo, không sửa50 candidates hoặc rules khác.
4. Nếu phiên đổi Public→Private dưới approval, restore đúng interface/profile trước phiên. Nếu sử dụng mạng Private có sẵn, không đổi nó về Public.
5. DNS owner restore đúng record/value/TTL trước đó hoặc xóa record mới đã được duyệt; gỡ đúng challenge TXT/delegation mới nếu thuộc scope. Cache/CT metadata không biến mất tức thì.
6. Child-process env kết thúc cùng process; không sửa env User/Machine. Giữ Windows localhost trust hiện có, không import/remove cert/CA và không dev-certs clean.
7. PFX/key/certificate lifecycle theo owner/CA policy, không tự xóa/revoke. Không delete workspace/QR/app data/cache/APK; cleanup data cần lệnh riêng.

**Hiện tại không có thay đổi hạ tầng cần rollback.** Chỉ một Markdown packet mới là intended Git delta.

## I. Commands planned but NOT EXECUTED

Các block sau là **review templates**, chưa phải script deploy đã được approve. Không chạy chúng trong lượt này. Mutating commands chỉ được dùng sau khi điền input thực tế và owner duyệt đúng scope; đặt flag=true không thay thế approval. Audit Get-only đã chạy ở A.

### I1. Inputs và guard cho lượt triển khai sau

~~~powershell
$ExecutionApproved = $false
$TrustedNetworkConfirmed = $false
$ProfileChangeApproved = $false
$FirewallApproved = $false
$ApiBindingApproved = $false
$BuildApproved = $false
$ApprovedFqdn = ''
[string[]]$PhoneIPv4 = @()
$ApprovedSessionId = ''
$WindowStart = $null # DateTimeOffset, owner specifies +07:00
$WindowEnd = $null
$PfxPath = '' # private local path; never upload
$PcIPv4 = '192.168.1.21'
$InterfaceIndex = 17
$InterfaceAlias = 'Wi-Fi'
$PilotPort = 7443
if (!$ExecutionApproved) { throw 'APPROVAL REQUIRED; no changes' }
if ([uri]::CheckHostName($ApprovedFqdn) -ne [UriHostNameType]::Dns -or
    !$ApprovedSessionId -or $ApprovedSessionId -notmatch '^[A-Za-z0-9-]+$' -or
    !$PhoneIPv4.Count -or !$WindowStart -or !$WindowEnd) {
    throw 'Owner inputs incomplete'
}
if ($WindowEnd -le $WindowStart -or
    ($WindowEnd - $WindowStart).TotalHours -gt 2 -or
    [DateTimeOffset]::Now -lt $WindowStart -or
    [DateTimeOffset]::Now -ge $WindowEnd) { throw 'Outside approved window' }
foreach ($value in $PhoneIPv4) {
    $parsed = $null
    if (![Net.IPAddress]::TryParse($value, [ref]$parsed) -or
        $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or
        $parsed.ToString() -ne $value -or
        $value -notmatch '^192\.168\.1\.(?:[1-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-4])$' -or
        $value -in @($PcIPv4,'192.168.1.1')) { throw 'Invalid approved phone IPv4' }
}
$ApiBaseUrl = 'https://{0}:7443/api' -f $ApprovedFqdn
$RuleName = 'WayMark-Pilot-7443-' + $ApprovedSessionId
~~~

Guard dùng /24 hiện tại; nếu thực tế đổi subnet/IP/interface, packet phải sửa và duyệt lại, không mở rộng regex/range để né gate. FQDN cũng phải đúng hostname được owner duyệt; kiểu DNS hợp lệ không chứng minh ownership.

### I2. Profile/firewall — admin console riêng

Trước block này cần recheck IP/index và không có listener, review50 rules local. Không đổi profile nếu owner chỉ duyệt rule. Không reuse tên rule đã tồn tại.

~~~powershell
if (!$ExecutionApproved -or !$FirewallApproved -or !$TrustedNetworkConfirmed) {
    throw 'NETWORK/FIREWALL APPROVAL AND TRUSTED NETWORK REQUIRED'
}
$ErrorActionPreference = 'Stop'
if (!$WindowEnd -or [DateTimeOffset]::Now -ge $WindowEnd) { throw 'Window ended' }
$currentProfile = Get-NetConnectionProfile -InterfaceIndex $InterfaceIndex
$currentIp = @(Get-NetIPAddress -InterfaceIndex $InterfaceIndex -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -eq $PcIPv4 -and $_.AddressState -eq 'Preferred' })
if ($currentProfile.InterfaceAlias -ne $InterfaceAlias -or !$currentIp.Count) {
    throw 'Interface/IP changed'
}
if (@(Get-NetTCPConnection -State Listen -ErrorAction Stop |
    Where-Object { $_.LocalPort -in @(7199,7443) }).Count) {
    throw 'Ports not at approved baseline'
}
if (Get-NetFirewallRule -Name $RuleName -ErrorAction SilentlyContinue) {
    throw 'Rule name already exists; do not overwrite'
}
$ProfileBefore = $currentProfile.NetworkCategory
$ProfileChangedByThisSession = $false
$RuleCreatedByThisSession = $false
if ($ProfileBefore -ne 'Private') {
    if ($ProfileBefore -ne 'Public' -or !$ProfileChangeApproved) {
        throw 'Separate trusted-network/profile approval required'
    }
    Set-NetConnectionProfile -InterfaceIndex $InterfaceIndex -NetworkCategory Private -ErrorAction Stop
    $ProfileChangedByThisSession = $true
}
if ((Get-NetConnectionProfile -InterfaceIndex $InterfaceIndex).NetworkCategory -ne 'Private') {
    throw 'Private profile not effective'
}
New-NetFirewallRule -Name $RuleName -DisplayName $RuleName -PolicyStore PersistentStore `
    -Direction Inbound -Action Allow -Enabled True -Protocol TCP -LocalPort $PilotPort `
    -LocalAddress $PcIPv4 -RemoteAddress $PhoneIPv4 -InterfaceAlias $InterfaceAlias `
    -Profile Private -EdgeTraversalPolicy Block -ErrorAction Stop | Out-Null
$RuleCreatedByThisSession = $true
~~~

Đây không phải transaction: nếu create rule/start API thất bại sau profile change, rollback các action đã hoàn tất theo flags/owner record. Không disable firewall hoặc retry với Public/Any.

### I3. API child process — current runtime user, không build/launch profile

Mẫu chỉ dùng binary có sẵn sau cert/config review. Password nếu cần nhận qua local approved mechanism tại lượt triển khai, không yêu cầu trong chat. Không dump ProcessStartInfo/environment. Không `dotnet run` kéo theo build hoặc thêm child API ngoài PID đang sở hữu.

~~~powershell
if (!$ExecutionApproved -or !$ApiBindingApproved) { throw 'API BINDING APPROVAL REQUIRED' }
if (!$WindowStart -or !$WindowEnd -or [DateTimeOffset]::Now -lt $WindowStart -or
    [DateTimeOffset]::Now -ge $WindowEnd) { throw 'Outside approved window' }
if (!$PfxPath -or !(Test-Path -LiteralPath $PfxPath -PathType Leaf)) {
    throw 'Approved server certificate file missing'
}
$apiDll = 'D:\project\WayMark\WayMark.Api\bin\Debug\net10.0\WayMark.Api.dll'
if (!(Test-Path -LiteralPath $apiDll)) { throw 'Existing API binary missing' }
$psi = [Diagnostics.ProcessStartInfo]::new()
$psi.FileName = 'C:\Program Files\dotnet\dotnet.exe'
$psi.Arguments = '"' + $apiDll + '" --environment Development'
$psi.WorkingDirectory = 'D:\project\WayMark\WayMark.Api'
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.EnvironmentVariables['ASPNETCORE_ENVIRONMENT'] = 'Development'
$psi.EnvironmentVariables['DOTNET_ENVIRONMENT'] = 'Development'
$psi.EnvironmentVariables['Kestrel__Endpoints__Loopback__Url'] = 'https://localhost:7199'
$psi.EnvironmentVariables['Kestrel__Endpoints__Pilot__Url'] = 'https://192.168.1.21:7443'
$psi.EnvironmentVariables['Kestrel__Endpoints__Pilot__Certificate__Path'] = $PfxPath
# $LocalPfxPassword, if needed, is supplied only by an approved LOCAL secret flow.
if ($null -ne $LocalPfxPassword) {
    $psi.EnvironmentVariables['Kestrel__Endpoints__Pilot__Certificate__Password'] = $LocalPfxPassword
}
$ownedApi = [Diagnostics.Process]::new()
$ownedApi.StartInfo = $psi
[void]$ownedApi.Start()
$OwnedPid = $ownedApi.Id
$OwnedStartTime = $ownedApi.StartTime
# Drain/discard raw output; never forward token-bearing HTTP logs to chat/files.
$stdoutDrain = $ownedApi.StandardOutput.BaseStream.CopyToAsync([IO.Stream]::Null)
$stderrDrain = $ownedApi.StandardError.BaseStream.CopyToAsync([IO.Stream]::Null)
$LocalPfxPassword = $null
~~~

Sau start phải kiểm owned PID chỉ có loopback7199 và192.168.1.21:7443; wildcard/LAN IPv6/HTTP/unexpected endpoint hoặc process exit→stop/BLOCKED. Parent wrapper giữ process handle và thực thi end-window cleanup; mẫu này chưa gồm watchdog hoàn chỉnh và **không được dùng unattended**. Startup failure cần chẩn đoán local đã redact, không bật chia sẻ raw logs hoặc đọc secret để đoán lỗi.

### I4. DNS /TLS /HTTP /Published gates sau triển khai

~~~powershell
if (!$ExecutionApproved) { throw 'APPROVAL REQUIRED' }
$a = @(Resolve-DnsName -Name $ApprovedFqdn -Type A -ErrorAction Stop |
    Where-Object { $_.Type -eq 'A' })
if (!$a.Count -or @($a | Where-Object { $_.IPAddress -ne $PcIPv4 }).Count) {
    throw 'Unexpected DNS A result'
}
# Also review AAAA: absent is expected; query failure is not proof of absence.
Get-NetTCPConnection -OwningProcess $OwnedPid -State Listen |
    Select-Object LocalAddress,LocalPort,OwningProcess
Add-Type -AssemblyName System.Net.Http
$handler = [Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $false
$handler.UseCookies = $false
$client = [Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromSeconds(20)
$response = $null
try {
    $uri = [uri]('https://{0}:7443/weatherforecast' -f $ApprovedFqdn)
    $response = $client.GetAsync($uri).GetAwaiter().GetResult()
    [pscustomobject]@{ Stage='PC HTTPS'; Status=[int]$response.StatusCode }
} catch {
    [pscustomobject]@{ Stage='PC HTTPS'; FailureType=$_.Exception.GetBaseException().GetType().Name }
} finally {
    if ($null -ne $response) { $response.Dispose() }
    $client.Dispose()
}
~~~

Chưa chạy DNS query/handshake/GET này. Không có TLS callback, `-k` hoặc redirect following. Thử loopback7199 độc lập; verify peer certificate public identity/chain với FQDN đã duyệt trước QR. PC200 chỉ transport, không SQL/storage PASS.

Khi bắt đầu campaign đã duyệt: phone browser origin + `/weatherforecast` không certificate warning; Main endpoint build Settings probe kiểm chính Flutter TLS (anonymous protected probe401 có thể là reachability); sau đó **authorized QR** GET-only→snapshot→images rồi camera Visitor. Thiếu QR giữ AUTHORIZED_QR_NOT_AVAILABLE. Không gửi URL/token/body/IDs ra log. Không đề nghị người dùng làm các thử nghiệm này ngay trong pre-deployment.

### I5. Main endpoint build — approval riêng, không overwrite Cycle3

~~~powershell
if (!$BuildApproved) { throw 'ENDPOINT BUILD APPROVAL REQUIRED' }
if ([uri]::CheckHostName($ApprovedFqdn) -ne [UriHostNameType]::Dns) {
    throw 'Approved FQDN required'
}
$ApiBaseUrl = 'https://{0}:7443/api' -f $ApprovedFqdn
Push-Location 'D:\project\WayMark\waymark'
try {
    & 'C:\src\flutter\bin\flutter.bat' build apk --debug --no-pub `
        -t lib/main.dart "--dart-define=WAYMARK_API_BASE_URL=$ApiBaseUrl"
    if ($LASTEXITCODE -ne 0) { throw 'Main endpoint build failed' }
} finally { Pop-Location }
~~~

Chưa chạy. Trước build phải xác nhận existing signing key/config sẵn, không sinh keystore; chốt installed versionCode/update path. Sau build verify package/ABI/signature bằng aapt/apksigner, SHA256 và manifest; copy generated app-debug.apk sang **tên/folder session mới đã duyệt**, refuse nếu destination tồn tại. Generated build cache có thể được thay bởi build được duyệt, các named Cycle3/handoff APK không bị ghi đè. Chưa có session/FQDN nên không tự chọn filename/copy path hoặc optional Live Test build.

### I6. Rollback mẫu — từng console chỉ thao tác tài nguyên nó sở hữu

API console giữ original process handle; network admin console giữ create/change flags. Owner lưu record không nhạy cảm để xử lý khi console mất. Không dựa vào một PID trần có thể đã bị reuse.

~~~powershell
# API console: only the original owned process object.
if ($null -ne $ownedApi -and !$ownedApi.HasExited) {
    $ownedApi.Kill()
    [void]$ownedApi.WaitForExit(10000)
}
Get-NetTCPConnection -State Listen -ErrorAction Stop |
    Where-Object { $_.LocalPort -in @(7199,7443) } |
    Select-Object LocalAddress,LocalPort,OwningProcess

# Network admin console: only actions this session actually completed.
if ($RuleCreatedByThisSession) {
    Remove-NetFirewallRule -Name $RuleName -PolicyStore PersistentStore -ErrorAction Stop
}
if ($ProfileChangedByThisSession) {
    Set-NetConnectionProfile -InterfaceIndex $InterfaceIndex -NetworkCategory $ProfileBefore -ErrorAction Stop
}
~~~

Nếu listener còn nhưng process khác, không kill nó. DNS/cert lifecycle rollback do owner theo đúng record/provider đã duyệt, chưa có CLI khi provider chưa biết. Không có command xóa dữ liệu hoặc certificate trust trong plan.

## J. APPROVAL REQUIRED / GO-NO-GO

| Gate | Quyết định hiện tại |
|---|---|
| Read-only decision pack | **COMPLETE** |
| Kiến trúc A | **SELECTED**, không phải execution approval |
| LAN HTTPS deployment | **NO-GO /BLOCKED** — thiếu domain/FQDN/cert/DNS route, trusted-network confirmation, phone allowlist, timebox/owner |
| Profile/firewall/cert issuance/DNS/API binding | **APPROVAL REQUIRED**, chưa áp dụng |
| Main endpoint build | **APPROVAL REQUIRED**, chưa rebuild |
| Authorized data /QR | **OWNER AUTHORIZATION REQUIRED /AUTHORIZED_QR_NOT_AVAILABLE** |
| Phone Published E2E /physical sensors /field accuracy | **NOT TESTED**, không biến local200 hoặc code-level tests thành PASS |

**Owner response form**, điền thông tin không nhạy cảm trước khi xin execution approval cuối:

~~~text
Domain /DNS control: ...
Approved FQDN: ...
DNS routing: managed split DNS /public A private-IP /chưa có
Existing cert public identity, SAN, issuer/chain, validity: ... /cần issuance
Wi-Fi thuộc quyền quản lý và được tin cậy: có /không /chưa xác nhận
Cho phép review/đổi Public→Private trên Wi-Fi17: ... (approval riêng)
Phone IPv4 từng máy, model/API nếu biết: ...
Start /end +07:00, <=2 giờ: ...
Stop/rollback owner và quyền vận hành network: ...
Test workspace alias /account A-B /authorized QR: ...
Cho phép create/save/publish fixture: ... ; revoke/delete: không /scope riêng
Scope muốn duyệt tiếp: DNS/cert /profile /firewall /API process /Main build
~~~

Sau khi có giá trị thật, chốt chính xác change set/commands/rollback và xin phê duyệt từng scope trước triển khai. Nếu không có domain/DNS access, giữ LAN BLOCKED; chỉ review managed/private HTTPS đã có hoặc điều kiện để có domain/cert phù hợp. Không tự mua/đăng ký/tạo account/tunnel/HTTP workaround.

### Change preservation

Baseline: branch auth-jwt-assignment,396 entries =44 modified +352 untracked,0 staged. Đã lấy aggregate SHA256 của535 Git-listed files sau khi loại đường dẫn cấu hình có thể chứa secret và certificate/key files; không đọc secret/private key/DNS credentials. Hash6 named APK Cycle1/2/3 và2 APK handoff riêng. Không claim audit nội dung secret-backed config trong lượt này.

**Final invariant đã kiểm:**535 file trong phạm vi hash giữ aggregate SHA256;6 APK named gốc và2 bản copy giữ hash, hai Cycle3/copy khớp release manifest. Git396→397 entries, chỉ thêm packet này;44 modified giữ nguyên/353 untracked,0 staged, branch không đổi. Network snapshot cuối vẫn Public/192.168.1.21, DNS và162/131/50 rule counts giữ nguyên; listener5121/7199/7443 vẫn0. `git diff --check` exit0; Markdown links/whitespace và7 PowerShell blocks được parse-only, không thực thi plan.

Chỉ intended write: Markdown packet mới này. Không network/DNS/trust/firewall/SQL mutation, certificate issuance, API start, APK rebuild/install hoặc product source change trong lượt pre-deployment. Không ghi thêm helper/deployment scripts hoặc logs vào workspace.
