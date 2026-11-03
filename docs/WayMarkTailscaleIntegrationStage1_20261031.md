# WayMark — Tailscale HTTPS Integration — Stage 1

Ngày kiểm tra: **01/11/2026 — Asia/Saigon**. Tên file giữ `20261031` theo yêu cầu.
Workspace: `D:\project\WayMark`.

**Stage 1: COMPLETE — Stage 2 deployment: APPROVAL REQUIRED /chưa GO vô điều kiện.**
Laptop và Android đã online, có Tailscale-layer ping thành công. Chưa bật Serve/cấp certificate; HTTPS readiness, access policy và upstream TLS còn gate cần xử lý có kiểm soát.

Kiến trúc được chọn:

~~~text
Android WayMark
  → private HTTPS laptop-pfrpmr3o.tail7697c0.ts.net:443
  → Tailscale Serve (TLS termination)
  → TLS mới, xác minh certificate: https://localhost:7199
  → WayMark API dưới Windows user hiện tại
  → SQL Server /image storage local
~~~

Không Funnel/public endpoint; không cần mở LAN7443, đổi Public→Private, cấp DNS riêng hay mở SQL. Packet LAN cũ là lịch sử, không triển khai các lệnh của nó theo quyết định Tailscale này. Không mở Development Cycle mới.

## A. Tailscale version /connection status

| Kiểm tra | Kết quả thực tế |
|---|---|
| CLI | `C:\Program Files\Tailscale\tailscale.exe`, có trên PATH |
| Version | **1.104.4**, daemon long version `1.104.4-t938213198-gd38c96d6a`; Go1.27.3 |
| BackendState | Running |
| Laptop | Self.Online=true, OS windows, có tailnet IPv4 |
| Machine label | **LAPTOP-PFRPMR3O** |
| FQDN từ status, không đoán | **laptop-pfrpmr3o.tail7697c0.ts.net** |
| Android | Ban đầu1 Android peer offline; sau owner xác nhận Connected, đọc lại thấy **1 Android peer online** |
| Connectivity probe | Một `tailscale ping`, tối đa1 lần/5s: exit0, có pong |
| Phạm vi bằng chứng | Ping ở Tailscale layer, không phải TCP443/HTTPS/grants/app E2E PASS |

Owner đã xác nhận Android Connected cùng tailnet. Không thu account/email, keys, serial, peer names, public relay endpoints hoặc device IPs vào báo cáo. Không cần phone cùng Wi-Fi với laptop để áp dụng kiến trúc overlay này; access policy và cả hai Tailscale clients vẫn phải phù hợp.

Help cục bộ của `ping` cho biết đây không phải phép thử qua OS TUN stack. Không suy ping thành công là firewall/ACL/Serve TCP443 đã đúng.

## B. Serve /Funnel /Services status

Đã chạy read-only:

~~~powershell
$ts = 'C:\Program Files\Tailscale\tailscale.exe'
& $ts version
& $ts status --json
& $ts serve --help
& $ts serve status --json
& $ts funnel status --json
& $ts serve get-config --help
& $ts serve get-config --all
& $ts ping --help
~~~

Trong phiên, JSON được parse và chỉ xuất metadata allowlist; không dump/persist raw status có account/public-key maps. Lệnh status raw trong block là inventory các lệnh đã dùng, không phải yêu cầu chia sẻ output nguyên vẹn.

| Config | Kết quả |
|---|---|
| Node-level Serve | `{}` — không TCP/web handlers hiện có |
| Funnel status | `{}` — không active AllowFunnel entries |
| Service configs | `get-config --all` chỉ trả schema version, **0 service** |
| Rechecks | Serve/Funnel vẫn trống; không reset/xóa cấu hình |
| Listener được kiểm | Không có5121/7199/443 tại thời điểm inventory; API chưa khởi động |

Config rỗng không chứng minh policy cấm mọi khả năng bật Funnel về sau. Không bật hoặc thay capability/policy Funnel, exit node, subnet router, SSH trong Stage 1.

**CLI help đối chiếu:**1.104.4 có `--https`, default foreground, `--bg` là tùy chọn; `serve status --json`, `funnel status --json` được hỗ trợ. `get-config` help nhắc `<file>` nhưng implementation tag1.104.4 xuất JSON ra stdout; chỉ dùng `get-config --all`, không tạo file hoặc gọi set-config. Nguồn: [CLI source đúng tag](https://github.com/tailscale/tailscale/blob/v1.104.4/cmd/tailscale/cli/serve_v2.go), [Serve CLI](https://tailscale.com/docs/reference/tailscale-cli/serve).

Một lần đọc help đặt `--help` sau positional arguments trong lời gọi `serve --https=443 off --help` bị CLI từ chối `invalid argument format`; không có thao tác tắt được áp dụng. Recheck config vẫn trống. Không thử lại lệnh off; cú pháp rollback được đối chiếu source, không thực thi.

## C. MagicDNS /certificate readiness /hostname privacy

| Gate | Kết quả |
|---|---|
| Tailnet MagicDNS | **Enabled=true** trong CurrentTailnet metadata |
| Laptop name resolution | Query A của FQDN thực tế thành công, đúng self tailnet IPv4; không in IP |
| Android name resolution | NOT TESTED; online/ping không chứng minh DNS/HTTPS trong phone |
| HTTPS eligibility | `CertDomains=null`, **0 nonempty eligible domains** được daemon quảng bá |
| HTTPS Certificates admin setting | **CHƯA XÁC NHẬN READY**; owner cần xem Admin Console → DNS → HTTPS Certificates |
| Existing *.ts.net leaf/chain | NOT VERIFIED; không yêu cầu certificate hoặc mở TLS frontend để kích hoạt issuance |
| Machine-name privacy | Owner xác nhận **không chứa thông tin riêng tư** |
| Certificate issuance /CT publication approval | **CHƯA ĐƯỢC PHÊ DUYỆT THỰC THI** |

Theo schema cùng tag, CertDomains là các tên control plane hỗ trợ certificate provisioning; null không phải bằng chứng đã enable HTTPS. Xem [status schema1.104.4](https://github.com/tailscale/tailscale/blob/v1.104.4/ipn/ipnstate/ipnstate.go). Cần owner kiểm tra authoritative admin setting, không tự chuyển toggle từ thiếu metadata.

Serve có thể tự provision certificate hoặc đưa ra consent flow nếu prerequisites thiếu. Vì vậy **không dùng chạy Serve để “chỉ kiểm tra” HTTPS trong Stage 1**, không `tailscale cert`. Stage 2 cần owner duyệt HTTPS enable nếu đang tắt và issuance trước khi chạy command.

FQDN có thể xuất hiện công khai trong Certificate Transparency: `laptop-pfrpmr3o.tail7697c0.ts.net`. Điều này công khai hostname/certificate metadata, không tự biến API thành public endpoint. Xác nhận tên không nhạy cảm khác với phê duyệt cấp cert; đổi tên sau này cần review hostname lại trước build. Tham chiếu [Tailscale HTTPS setup](https://tailscale.com/docs/how-to/set-up-https-certificates).

Không cần mua domain hoặc DNS API credentials của owner cho `*.ts.net` này. Không bật/tắt MagicDNS, đổi hostname/tailnet DNS name hoặc import CA.

## D. Access control findings

**Owner trả lời: chưa kiểm tra grants/ACL. Gate: ACCESS_POLICY_NOT_VERIFIED.**

Status map hiện thấy1 peer không phải authoritative inventory toàn tailnet, và không chứng minh chỉ phone đó được TCP443. Các lệnh status/Serve không cung cấp toàn bộ policy; Stage 1 chưa đọc được policy từ Admin Console và không dùng API key để lấy.

Owner cần review local trong Admin Console → Access controls, không gửi raw policy có email/account lên chat:

1. Xác định approved Android node(s) và laptop; map selector tới đúng thiết bị.
2. Xác nhận tất cả grants/legacy ACL paths cho **TCP443 trên laptop**. Một user/group selector có thể bao gồm nhiều thiết bị, không tự đồng nghĩa đúng một phone.
3. Kiểm broad allow-all hoặc grants khác. Thêm một grant hẹp không thu hẹp một allow rule rộng đang tồn tại; phải review union của các đường allow.
4. Ghi scope owner chấp nhận: chỉ approved phone(s), hay phạm vi trusted devices khác cụ thể. Không tự cho rằng toàn tailnet đều được phép.
5. Nếu cần sửa policy, chuẩn bị diff và accept/deny tests, xin approval riêng; không apply trong Stage 1. Không cần bật Tailscale SSH, routes hoặc exit node.
6. Funnel capability và active Funnel config là hai việc khác nhau; không dùng consent/`--yes` để chấp nhận quyền ngoài scope.

Default policies có thể permissive; không dựa vào khẩu hiệu deny-by-default để suy policy thực tế. Tham chiếu [Grants](https://tailscale.com/docs/features/access-control/grants), [grant examples](https://tailscale.com/docs/reference/examples/grants), [ACL defaults](https://tailscale.com/docs/features/access-control/acls).

WayMark JWT/authorization/rate limits vẫn giữ cho private endpoints. Tailscale identity headers không thay JWT/login/owner checks. Public QR/snapshot/image endpoints vẫn anonymous theo contract, nhưng chỉ trong network reachability mà owner duyệt.

## E. Local API prerequisites và upstream TLS risk

| Hạng mục | Kết quả |
|---|---|
| API target /binary | net10.0 binary sẵn trong `WayMark.Api/bin/Debug/net10.0`; không build/chạy |
| SQL | MSSQLSERVER Running; không SQL query/migration/seed/grant |
| Runtime user | Giữ user đã chạy API trước đây; không chuyển API sang SYSTEM/service user |
| API bind sau approval | Chỉ `https://localhost:7199`, tương ứng127.0.0.1/::1; không LAN/wildcard/HTTP default profile |
| Hosting process overrides | Không có key Kestrel/URLS/HTTP_PORTS/HTTPS_PORTS trong environment hiện kiểm |
| Launch profile | `https` profile hiện còn HTTP5121; **không dùng profile này** cho Stage 2 |
| Localhost dev leaf identity | SHA1 **CC2373AF077AADF1722A14404B74C67CF6D97BCE**, CN=localhost; còn hạn, SAN có localhost |
| Trust metadata | Exact cert có trong **operator CurrentUser\Root**, không có trong **LocalMachine\Root** |
| Tailscale daemon | Windows service Running/Auto, **LocalSystem** |
| Local API HTTPS trước đây | PRIOR PASS dưới operator ngày30/10; không retest trong Stage 1 |
| Serve→7199 TLS | **NOT TESTED; trust-context mismatch risk**, không coi operator PASS là daemon PASS |

Đã đọc public metadata của đúng cert đã được chỉ định/phê duyệt, không export hoặc đọc private key; không thay store/trust.

**INFERRED:** LocalSystem không dùng CurrentUser store của operator. Vì cert hiện chỉ trust ở user đó, Serve có nguy cơ lỗi unknown authority/x509 khi forward tới7199. Chưa thực hiện request từ daemon nên không tuyên bố lỗi đã tái hiện, cũng không khẳng định cert không thể được trust qua mọi service-specific mechanism.

Tailscale source cùng tag sử dụng backend HTTP transport với TLS validation cho `https://`; pseudo-scheme insecure mới bỏ verification. Windows có các certificate store scope khác nhau. Nguồn: [Serve transport1.104.4](https://github.com/tailscale/tailscale/blob/v1.104.4/ipn/ipnlocal/serve.go), [Windows system store locations](https://learn.microsoft.com/en-us/windows/win32/seccrypto/system-store-locations), [Go x509](https://pkg.go.dev/crypto/x509#Certificate.Verify).

**Không giải quyết tự động bằng import vào LocalMachine/LocalSystem, đổi service identity, tạo cert mới, `https+insecure`, TrustAll hoặc callback bypass.** Approval trust trước đây chỉ cho operator CurrentUser và vẫn giữ nguyên. Nếu Stage 2 gặp upstream x509 failure: stop phiên, báo typed cause đã sanitize; mọi phương án trust khác cần quyết định/scope riêng.

### HTTP loopback alternative — chỉ phương án có điều kiện

Owner có thể xem xét thêm upstream `http://127.0.0.1:<approved-port>` ở lượt riêng; Android→Serve vẫn HTTPS, loopback7199 giữ độc lập. **Chưa chọn hoặc áp dụng**, chưa chốt port/command.

Đây không phải drop-in với API hiện tại: Program.cs có UseHttpsRedirection, không thấy UseForwardedHeaders trong bootstrap. Cần review redirect/host/proto, trusted-proxy constraints và auth trước; không mặc định forwarded headers tự được consume hoặc đổi environment để trust mọi proxy. Nếu cần sửa source, điều đó ngoài Stage 1 và không được tự làm để né blocker. Không chạy HTTP trên LAN hoặc tự chuyển target khi TLS lỗi.

## F. Exact commands đề xuất cho Stage 2 — NOT EXECUTED

Thứ tự có điều kiện; các flag approval sau mặc định false. Không đủ điều kiện thì dừng, không tự đổi target/scope. Stage 2 có thể được duyệt như một phiên **deployment validation fail-closed**, chưa phải nghiệm thu Published.

### F1. Prelaunch review

- Owner kiểm HTTPS Certificates setting, scope grants/ACL; duyệt issuance/CT cho exact hostname.
- Chốt thời gian bắt đầu/kết thúc, rollback owner; đề xuất tối đa2 giờ như packet trước, chưa tự đặt lịch.
- Re-read status/Serve/Funnel/Services trước mutation. Nếu config không còn trống hoặc443 có owner khác, stop review; không overwrite/reset.
- Ghi owned API PID/start time và Serve foreground session; giữ API dưới user hiện tại.
- Không nâng quyền hoặc chạy consent UI trong Stage 1. Stage 2 Windows Serve có thể cần owner-controlled admin terminal; không đổi identity API.

### F2. Start API loopback trong terminal riêng

Mẫu process-only arguments đã dùng trong local verification trước; logging overrides chỉ tránh raw HTTP/token output, không sửa file cấu hình. Không dùng launch profile hoặc build.

~~~powershell
$Stage2ApiStartApproved = $false
if (!$Stage2ApiStartApproved) { throw 'STAGE 2 API START APPROVAL REQUIRED' }
Push-Location 'D:\project\WayMark\WayMark.Api'
try {
    & 'C:\Program Files\dotnet\dotnet.exe' `
        'D:\project\WayMark\WayMark.Api\bin\Debug\net10.0\WayMark.Api.dll' `
        --environment Development --urls 'https://localhost:7199' `
        --Logging:LogLevel:Default=None --Logging:LogLevel:Microsoft.AspNetCore=None
} finally { Pop-Location }
~~~

Kiểm listener theo owned PID chỉ127.0.0.1/::1:7199; nếu có LAN/wildcard/HTTP, dừng đúng process. Local HTTPS GET mặc định phải200 trước khi gọi Serve. Đây chỉ chứng minh operator trust, chưa kiểm daemon.

### F3. Serve foreground đúng yêu cầu

CLI help1.104.4 và official Serve reference hỗ trợ HTTPS target. **Không chạy trong Stage 1.**

~~~powershell
$Stage2ServeAndCertificateApproved = $false
if (!$Stage2ServeAndCertificateApproved) { throw 'STAGE 2 SERVE / CERTIFICATE APPROVAL REQUIRED' }
& 'C:\Program Files\Tailscale\tailscale.exe' serve --https=443 https://localhost:7199
~~~

Không `--bg`, `--yes`, `--service`, `--tun`, Funnel hoặc insecure target. Giữ foreground session có owner; nếu consent yêu cầu tính năng/policy ngoài scope thì dừng để review, không chấp nhận tự động. Có thể provision *.ts.net cert trong bước này nên cần approval trước lệnh.

Serve configuration phải chỉ proxy root443→`https://localhost:7199`, không active Funnel. Giữ path `/api/...` để API nhận resolver/snapshot/images đúng route. Không public static files hoặc directory từ workspace. Tham chiếu [Serve behavior](https://tailscale.com/docs/features/tailscale-serve), [HTTPS target syntax](https://tailscale.com/docs/reference/tailscale-cli/serve).

### F4. Verify riêng cả hai TLS legs

Sau approval, dùng helper dưới đây cho loopback rồi frontend thực tế. Không follow redirects, không callback/CA override hoặc raw body output.

~~~powershell
function Test-WayMarkHttpsTransport([uri]$Origin) {
    if (!$Origin.IsAbsoluteUri -or $Origin.Scheme -ne 'https' -or
        $Origin.UserInfo -or $Origin.Query -or $Origin.Fragment -or
        $Origin.AbsolutePath -notin @('','/')) { throw 'Approved HTTPS origin only' }
    Add-Type -AssemblyName System.Net.Http
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $handler.UseCookies = $false
    $client = [Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(20)
    $response = $null
    try {
        $uri = [uri]($Origin.GetLeftPart([UriPartial]::Authority) + '/weatherforecast')
        $response = $client.GetAsync($uri).GetAwaiter().GetResult()
        [pscustomobject]@{ Stage='HTTPS transport'; Status=[int]$response.StatusCode }
    } catch {
        [pscustomobject]@{ Stage='HTTPS transport'; FailureType=$_.Exception.GetBaseException().GetType().Name }
    } finally {
        if ($null -ne $response) { $response.Dispose() }
        $client.Dispose()
    }
}
# Run only inside approved Stage 2:
# Test-WayMarkHttpsTransport ([uri]'https://localhost:7199')
# Test-WayMarkHttpsTransport ([uri]'https://laptop-pfrpmr3o.tail7697c0.ts.net')
~~~

Leg1 Android/browser/app→actual *.ts.net: SAN/chain/expiry hợp lệ, DNS đúng tailnet, no warning. Leg2 Serve daemon→localhost7199: exact HTTPS target, normal TLS validation, request forwarded thành công. Frontend certificate hợp lệ nhưng502 không chứng minh upstream TLS PASS; xác định refused/timeout/x509/name/expiry theo diagnostic đã sanitize. Không suy mọi502 đều TLS.

Stage 2 chỉ được chốt **both TLS legs PASS** sau config/target identity được kiểm và `/weatherforecast`200 qua proxy; nếu upstream fail phải dừng, không tự fallback. Phone browser200 vẫn chưa chứng minh Flutter TLS hoặc QR/SQL/image reads.

### F5. Main APK — chỉ sau endpoint thật được xác nhận

Cycle3 Main vẫn `http://10.0.2.2:5121/api`; Settings không sửa global endpoint. Live Test có guest endpoint override, không đổi Auth/Creator/History.

FQDN hiện lấy từ status là candidate có thật, **chưa là endpoint HTTPS đã chạy**. Sau Serve/TLS PASS mới chốt Main base URL dự kiến:

`https://laptop-pfrpmr3o.tail7697c0.ts.net/api`

Nếu hostname thay đổi trước issuance, re-read và duyệt lại tên, không dùng candidate cũ. Build là approval riêng, không tự kèm vào việc bật Serve.

~~~powershell
$MainEndpointBuildApproved = $false
$EndpointHttpsVerified = $false
$ConfirmedApiBaseUrl = '' # set from actual verified Stage 2 endpoint, not a guess
if (!$MainEndpointBuildApproved -or !$EndpointHttpsVerified -or !$ConfirmedApiBaseUrl) {
    throw 'VERIFIED ENDPOINT AND MAIN BUILD APPROVAL REQUIRED'
}
Push-Location 'D:\project\WayMark\waymark'
try {
    & 'C:\src\flutter\bin\flutter.bat' build apk --debug --no-pub `
        -t lib/main.dart "--dart-define=WAYMARK_API_BASE_URL=$ConfirmedApiBaseUrl"
    if ($LASTEXITCODE -ne 0) { throw 'Main endpoint build failed' }
} finally { Pop-Location }
~~~

Giữ package `com.example.waymark`, existing debug signer và version/update constraints của Cycle3; không sinh signing key mới. Verify aapt/apksigner/hash, artifact/manifest mới sau build, không overwrite6 APK named gốc hoặc2 APK handoff. Không build/install bất cứ APK nào trong Stage 1.

## G. Rollback — chỉ sau một Stage 2 đã được duyệt

Hiện không có Serve/API mới để dừng.

1. Ctrl+C đúng Serve foreground terminal do Stage 2 tạo; recheck Serve/Funnel/Services config về baseline và không đụng cấu hình đồng thời của người khác.
2. Nếu foreground session không dọn được, khi đã xác minh443 thuộc phiên và baseline trước phiên trống, có thể dùng **lệnh dự kiến** `tailscale serve --https=443 off`. Syntax đối chiếu source1.104.4; chưa chạy thành công/off action trong Stage 1. Không `serve reset`, `clear`, `set-config` hoặc funnel commands để cleanup.
3. Dừng đúng API process do phiên tạo, kiểm7199 về baseline0. Không kill service Tailscale/process .NET khác; để laptop/phone Tailscale installation/connection nguyên trạng.
4. Không restore Public/Private hoặc firewall/DNS vì phương án này không thay chúng. Nếu về sau có thay đổi policy/HTTPS admin setting riêng, phải có snapshot và owner-approved rollback riêng; không disable HTTPS toàn tailnet vì có thể ảnh hưởng dịch vụ khác.
5. CT history/certificate đã cấp không biến mất khi tắt Serve; không revoke/delete cert/private key hoặc gỡ localhost trust tự động.
6. Giữ APK/data/draft/QR/SQL/storage. Không revoke/delete fixture hoặc reset database khi cleanup.

## H. Approval items /GO-NO-GO

| Gate | Trạng thái |
|---|---|
| CLI/service/laptop online | PASS |
| Android online | OWNER CONFIRMED + metadata PASS sau recheck |
| Tailscale-layer peer ping | PASS, không chứng minh TCP443 |
| Laptop MagicDNS | Enabled + resolution PASS |
| Hostname không chứa thông tin riêng tư | OWNER CONFIRMED |
| HTTPS Certificates enable/eligible domains | NOT READY FROM LOCAL METADATA; owner admin review/approval required |
| Grants/ACL effective scope | NOT VERIFIED; owner chưa kiểm policy |
| Current Serve/Funnel | EMPTY, không deployment |
| Localhost TLS dưới operator | PRIOR PASS + trust metadata giữ nguyên |
| Serve daemon upstream TLS | NOT TESTED, LocalSystem/CurrentUser trust risk |
| Stage 2 private deployment | APPROVAL REQUIRED; chưa unconditional GO |
| Main endpoint build | NOT APPROVED /NOT BUILT |
| Authorized QR | AUTHORIZED_QR_NOT_AVAILABLE |
| Published QR/snapshot/image, phone E2E, field accuracy | NOT TESTED /NOT VERIFIED |

**Đề nghị owner review trước khi phê duyệt Stage 2:**

- Admin DNS → HTTPS Certificates hiện Enabled hay Disabled; nếu cần Enable, chấp thuận exact hostname/CT và issuance cho Serve. Không yêu cầu key/cert files hoặc password.
- Admin Access controls → scope thực tế của TCP443 tới laptop; quyết định scope được phép, policy diff nếu cần phải duyệt riêng.
- Chốt window/rollback owner; có cho phép phiên Stage 2 fail-closed dùng HTTPS7199 và dừng nếu daemon x509 không trust hay không.
- Main rebuild và data/QR tests tách approval sau endpoint PASS; không gửi QR token/JWT/tài khoản thật lên chat.

Stage 1 đã chuẩn bị đủ findings và command plan để owner review. **Chưa báo “mọi điều kiện đã đủ để deploy”** khi HTTPS/policy chưa kiểm và upstream TLS chưa đo. Không xin mở LAN/firewall hoặc mở rộng certificate trust như một phần ngầm của Stage 2.

## I. Change safety /evidence scope

Baseline branch auth-jwt-assignment,397 entries,0 staged. Hash536 Git-listed files trong phạm vi đã loại config/key paths có thể nhạy cảm;6 APK named Cycle1/2/3 và2 handoff APK riêng. Không đọc appsettings/user-secrets/password, Tailscale private state, debug prefs/netmap/local-creds hoặc DNS credentials. Chỉ metadata/public certificate của exact approved thumbprint được đọc.

Serve/Funnel JSON baseline và các lần recheck đều trống; service configs0. Không cấp certificate, đổi trust/ACL/MagicDNS/firewall/network profile, cài phần mềm, bật Serve/Funnel/SSH/routes, launch API, rebuild APK hoặc gọi SQL/data write. Một ping và DNS query là read-only connectivity probes, không chức năng WayMark.

**Final integrity:**536 file trong phạm vi hash giữ aggregate SHA256;6 APK named gốc và2 handoff APK giữ hash. Git397→398 entries, chỉ thêm báo cáo này,0 staged và branch giữ nguyên. `git diff --check` exit0;5 PowerShell code blocks parse hợp lệ, không execute các kế hoạch Stage 2. Serve/Funnel vẫn trống, service configs0,7199/5121/443 đều không listener; laptop và1 Android peer online, MagicDNS vẫn bật, CertDomains nonempty vẫn0, Wi-Fi vẫn Public.

Chỉ tạo Markdown báo cáo này; không thêm helper scripts/logs hoặc chỉnh tài liệu/source khác. Các kế hoạch Stage 2 được parse syntax-only, không thực thi.
