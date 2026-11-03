# WayMark — Tailscale Stage 2 — Private HTTPS Validation

Ngày kiểm tra: **01/11/2026 — Asia/Saigon**. Workspace: `D:\project\WayMark`.

**Kết quả lượt này: READ-ONLY RECHECK COMPLETE — DEPLOYMENT BLOCKED: MISSING EXPLICIT APPROVALS.**
Không khởi chạy API, bật Serve hoặc cấp certificate. Chưa có frontend/upstream TLS runtime result cho Stage 2. Không mở Cycle4.

Căn cứ: [Stage 1](WayMarkTailscaleIntegrationStage1_20261031.md) và yêu cầu Stage 2, đặc biệt mục1 và câu cuối: **“Không coi prompt này tự thân là approval cho thay đổi hệ thống.”** Lượt này hoàn thành nhánh read-only + báo cáo mà yêu cầu cho phép khi thiếu approval; không phải một deployment đã thử rồi thất bại.

## A. Approval evidence

| Gate bắt buộc | Bằng chứng đã có | Còn thiếu |
|---|---|---|
| HTTPS Certificates + issuance/CT | Owner xác nhận hostname LAPTOP-PFRPMR3O không chứa thông tin riêng tư trong Stage 1 | **Chưa duyệt enable nếu cần, issuance và CT publication** cho exact FQDN |
| ACL/grants scope | Owner trả lời **“Chưa kiểm tra policy”** trong Stage 1 | Authoritative scope TCP443, review broad rules và chấp thuận scope thực tế; policy diff approval nếu cần sửa |
| Temporary loopback API | Có approval/runtime PASS trong nhiệm vụ local trước đây, đã cleanup | **Chưa phê duyệt riêng phiên API Stage 2** theo yêu cầu hiện tại |
| Private Serve foreground | Đã chọn kiến trúc Tailscale, cài Tailscale và xác nhận Android Connected | **Chưa phê duyệt bật Serve/certificate provisioning** cho phiên này |
| End time + rollback owner | Có đề xuất timebox từ các packet trước | **Chưa có start/end cụ thể và người chịu trách nhiệm rollback** |

Không suy việc chọn kiến trúc, cài VPN, tên không nhạy cảm hay việc gửi prompt thành các approval còn thiếu. Việc thiếu gate được xác định trước mutation; không thử Serve để tạo consent URL hoặc “xem có chạy không”.

Build Main là approval riêng **sau** both TLS legs PASS; không xin/áp build trước gate này. Không có approval data/QR mới.

## B. HTTPS Certificates status

| Read-only metadata hiện tại | Kết quả |
|---|---|
| CLI/daemon | **1.104.4**, BackendState Running |
| Laptop /Android | Laptop online;1 Android peer,1 online |
| FQDN từ daemon | **laptop-pfrpmr3o.tail7697c0.ts.net** |
| MagicDNS | Enabled=true |
| Eligible domains | **0 nonempty CertDomains**, self hostname chưa advertised eligible |
| HTTPS Certificates admin setting | **NOT VERIFIED**, chưa chứng minh Enabled |
| Public frontend certificate/chain | **NOT TESTED**; không cấp hoặc yêu cầu cert |

CertDomains thiếu không được tự quy thành bằng chứng authoritative setting Disabled; cũng không được coi Enabled. Cần owner xác nhận trong Admin Console → DNS → HTTPS Certificates. Không chạy `tailscale cert` hoặc Serve để kích hoạt provisioning trong lượt thiếu approval.

Hostname có thể được công bố qua CT khi issue certificate; chấp thuận tên không nhạy cảm chưa phải chấp thuận issuance. Serve có thể yêu cầu consent hoặc tự provision khi prerequisites đạt. Tham chiếu [Tailscale HTTPS](https://tailscale.com/docs/how-to/set-up-https-certificates), [Serve prerequisites](https://tailscale.com/docs/features/tailscale-serve).

## C. ACL/grants actual scope

**ACTUAL EFFECTIVE SCOPE: NOT VERIFIED. WILDCARD/BROAD ALLOW: NOT VERIFIED.**

Đã thử đọc UI bằng computer-use, không thực hiện input hoặc thay setting:

- Native helper `list_windows` trả **“Computer Use native pipe is unavailable … The system cannot find the file specified. (os error 2)”**.
- Browser selection trả **“No browser is available”**.
- Không truy cập được Admin Console trong phiên; không thao tác login, xin API key, đọc private node state hoặc tự sửa browser/native helper để vượt lỗi.

Đây là hạn chế công cụ riêng, không phải lỗi Tailscale network và không thay cho approval gate. Không kết luận máy không có Chrome hoặc owner không có tài khoản admin.

CLI status cho thấy1 peer không chứng minh toàn tailnet chỉ có một phone hay port443 chỉ cho phone này. Chưa có policy input đủ tin cậy để tạo diff; **không dựng một replacement policy từ giả định**.

Owner cần review toàn bộ đường allow vào **laptop TCP443**, gồm grants, legacy ACL, user/group/tag selectors và broad rules. Một rule hẹp thêm vào không thu hẹp allow rule rộng đang tồn tại. User selector cũng có thể bao gồm nhiều thiết bị. Nguồn: [Tailscale grants](https://tailscale.com/docs/features/access-control/grants).

Nếu cần sửa policy, bước tiếp theo phải chuẩn bị **diff trên policy hiện có**, không overwrite toàn file, kèm case tests:

| Policy test đề xuất, chưa chạy | Expected theo scope owner chọn |
|---|---|
| Approved Android node → laptop TCP443 | Allow |
| Một node ngoài approved scope → laptop TCP443 | Deny nếu chọn phone-only scope |
| Approved node → các port không được cấp | Theo policy đã review; không tự cấp thêm |
| Các existing authorized flows ngoài pilot | Giữ nguyên theo owner policy |
| Broad existing allow có tiếp tục bao phủ443 không | Phát hiện trước khi chấp nhận scope |

Không chạy test bằng tài khoản/node không được phép; identities và mapping thực tế giữ local. Owner có thể chấp nhận scope rộng hơn sau review, nhưng phải mô tả rõ; không gọi scope đó là “chỉ một phone”. Không in email, keys, raw policy vào báo cáo.

## D. API localhost runtime

**LOCAL API STAGE 2: BLOCKED /NOT STARTED.**

- Không listener ở7199/5121 lúc kiểm; không process API thuộc nhiệm vụ được tạo.
- Existing `WayMark.Api/bin/Debug/net10.0/WayMark.Api.dll` có sẵn; MSSQLSERVER Running.
- Không hosting override key Kestrel/URLS/HTTP_PORTS/HTTPS_PORTS trong process environment đã kiểm.
- Không đọc appsettings/user-secrets/connection strings hoặc gọi SQL trong lượt này.
- Runtime trước đây ngày30/10 có startup, loopback TLS và `/weatherforecast`200 PASS dưới operator; bằng chứng đó là **PRIOR PASS**, không thay Stage 2 runtime.

Sau approval riêng mới dùng Development dưới user cũ, existing binary/no launch profile, chỉ `https://localhost:7199`; verify owned PID chỉ127.0.0.1/::1:7199. Profile HTTPS hiện có HTTP5121 nên không dùng mặc định. Không bind LAN/wildcard, mở SQL hoặc sửa JWT/database permissions.

Command plan đã có ở [Stage 1 mụcF2–F4](WayMarkTailscaleIntegrationStage1_20261031.md); không thực thi trong lượt này.

## E. Serve configuration

| Kiểm tra read-only | Kết quả |
|---|---|
| `serve status --json` | `{}`, không current node-level handlers |
| `funnel status --json` | `{}`, không active Funnel entries |
| `serve get-config --all` |0 services |
| Listener443 |0 |
| `serve --help` | CLI1.104.4 hỗ trợ `--https`, foreground mặc định |

**SERVE DEPLOYMENT: NOT STARTED.** Không có owned Serve session hoặc configuration mới để cleanup.

Exact command đã review, **CHƯA CHẠY /chỉ dùng sau approval**:

~~~powershell
$Stage2ServeAndCertificateApproved = $false
if (!$Stage2ServeAndCertificateApproved) { throw 'EXPLICIT STAGE 2 APPROVAL REQUIRED' }
& 'C:\Program Files\Tailscale\tailscale.exe' serve --https=443 https://localhost:7199
~~~

Không `--bg`, `--yes`, Funnel, exit node, subnet router, SSH hoặc insecure target. Khi được duyệt phải recheck baseline trước launch; nếu config/443 đã có owner khác thì dừng review, không overwrite/reset.

## F. Frontend TLS

**FRONTEND TLS: NOT TESTED — APPROVAL GATE.**
**PROXIED HTTP `/weatherforecast`: NOT TESTED.**

Không gửi TLS/HTTP probe tới candidate frontend đang chưa có Serve để tránh gây hiểu nhầm hoặc kích hoạt issuance về sau ngoài scope. Không có certificate validation failure, HTTP502 hoặc200 nào trong lượt này để phân loại.

Sau approval: kiểm FQDN thực từ daemon và Serve config; default TLS SAN/chain/expiry đúng; GET `/weatherforecast` qua `https://laptop-pfrpmr3o.tail7697c0.ts.net` phải200, không redirect/bypass. Tiếp tục kiểm đúng target/owned API PID để chứng minh request chuyển tới API, không chỉ frontend handshake.

PC200 không tự chứng minh Android/Flutter trust, SQL/image read hoặc Published camera E2E.

## G. Upstream TLS

**UPSTREAM TLS: NOT TESTED. X509 FAILURE: NOT REPRODUCED.**

Public metadata đã đọc của đúng approved localhost cert SHA1:
`CC2373AF077AADF1722A14404B74C67CF6D97BCE`.

| Finding hiện tại | Nhãn |
|---|---|
| Subject CN=localhost, còn hạn | CONFIRMED về public metadata |
| Exact cert trong operator CurrentUser\Root | CONFIRMED |
| Exact cert trong LocalMachine\Root | Không thấy tại path đã kiểm |
| Tailscale Windows service | Running, **LocalSystem** |
| API operator TLS trước đây | PRIOR PASS |
| Daemon chấp nhận chain7199 hay không | NOT TESTED |

**INFERRED RISK:** operator CurrentUser trust không tự chứng minh LocalSystem trust. Chưa đo TLS từ Serve nên không đổi đánh giá rủi ro thành lỗi confirmed hoặc PASS. Xem [Windows certificate store scopes](https://learn.microsoft.com/en-us/windows/win32/seccrypto/system-store-locations), [Serve transport đúng version](https://github.com/tailscale/tailscale/blob/v1.104.4/ipn/ipnlocal/serve.go).

Nếu phiên được duyệt sau này trả502: cần phân biệt upstream refused/timeout, hostname/expiry, x509 authority hoặc lỗi proxy khác từ evidence đã sanitize; không quy mọi502 thành trust mismatch. Nếu x509/unknown authority được chứng minh, dừng owned Serve/API, giữ trust và service identity.

### Phương án khắc phục riêng nếu lỗi được tái hiện

| Phương án chỉ để review | Thay đổi security scope /approval cần có |
|---|---|
| HTTPS upstream dùng cert/chain mà daemon đã tin, SAN đúng tên target | Phải có public cert metadata và API binding plan; cert provisioning/config mới cần approval riêng. Không tự tạo cert |
| Trust đúng localhost leaf trong context daemon nếu owner chọn | Mở rộng trust ngoài operator CurrentUser; LocalMachine Root ảnh hưởng machine-wide. **Không nằm trong approval cũ**, không import trong nhiệm vụ hiện tại; cần scope riêng sau diagnosis |
| HTTP chỉ trên127.0.0.1 nếu owner chọn | Loại TLS trên một hop loopback; phải duyệt thiết kế riêng trước, không fallback tự động |

Với HTTP alternative: Program.cs hiện có UseHttpsRedirection, không thấy UseForwardedHeaders trong bootstrap. Cần phân tích X-Forwarded-Proto/trusted proxy, Host, redirect target/port, private auth và local-process access. Proxy headers không mặc định được app tin; không bật trust mọi proxy hoặc disable redirection/auth để né lỗi. External phone→Serve vẫn phải HTTPS; không bind HTTP lên LAN. Nếu cần sửa source, phải được giao scope riêng; không phát triển nó trong Stage 2 này.

Không dùng https+insecure, TrustAll, badCertificateCallback, thay service identity, certificate import hoặc cấp chứng chỉ mới làm workaround tự động.

## H. Android endpoint/build readiness

**MAIN ENDPOINT BUILD: NO-GO — TLS NOT TESTED, BUILD NOT APPROVED.**

- Main Cycle3 compile default emulator `http://10.0.2.2:5121/api`; không runtime global endpoint editor.
- Candidate FQDN đúng status hiện tại, chưa phải proven HTTPS service.
- Endpoint chỉ được chốt **sau both TLS legs PASS**: `https://laptop-pfrpmr3o.tail7697c0.ts.net/api`.
- Chỉ khi đó mới xin approval build Main bằng WAYMARK_API_BASE_URL, verify package/signing/hash/versionCode và giữ APK gốc/handoff.
- Không chạy Flutter/Gradle build, signer/key generation hoặc APK install trong lượt này.

Data gate: **AUTHORIZED_QR_NOT_AVAILABLE**. Không tìm/sinh token trong SQL/source/log/clipboard; không publish/revoke hoặc data write. Snapshot/image read, phone Published E2E và field accuracy vẫn NOT TESTED /NOT VERIFIED.

## I. Failures /blockers và input cần chốt

| Blocker | Tình trạng /owner action |
|---|---|
| HTTPS/CT approval | Chưa có. Owner duyệt enable nếu cần và certificate issuance/CT cho exact hostname |
| HTTPS Certificates admin status | Chưa xác minh Enabled; owner xem Admin DNS và cho biết trạng thái, không gửi secret |
| ACL actual scope/approval | Owner chưa review; cần mô tả approved source devices và effective TCP443 scope, broad-rule findings |
| API start approval | Chưa có cho phiên Stage 2 |
| Serve foreground approval | Chưa có cho phiên Stage 2 |
| Timebox/end/rollback owner | Chưa chốt start/end cụ thể +07:00 và người chịu trách nhiệm |
| Admin UI access | Native pipe unavailable và không có browser khả dụng; không phải permission/TLS/network failure của WayMark |
| LocalSystem trust context | Risk chưa thử; không phải lỗi đã được tái hiện |
| Main build /QR | Các gate sau TLS; không xin build sớm, không thu payload |

Không có startup/TLS/HTTP runtime failure của WayMark cần sửa trong lượt này vì chưa được phép bắt đầu các phép thử phụ thuộc.

### Owner response form — không phải blanket approval

~~~text
HTTPS Certificates hiện tại trong Admin DNS: Enabled /Disabled /chưa kiểm
Cho phép enable nếu cần + cấp cert/CT cho
laptop-pfrpmr3o.tail7697c0.ts.net: có /không
Đã review ACL/grants tới laptop TCP443: có /chưa
Scope thực tế được chấp nhận, dùng device aliases: ...
Broad allow-all/rule khác: có /không /chưa xác minh
Policy change: không cần /cần diff và approval riêng, chưa apply
Cho phép chạy tạm đúng một API Development dưới user hiện tại,
chỉ https://localhost:7199: có /không
Cho phép Serve foreground HTTPS443→https://localhost:7199,
private tailnet-only, dừng nếu upstream TLS lỗi: có /không
Start /end +07:00: ... /... (đề xuất tối đa2 giờ)
Rollback owner: ...
Main build: chưa duyệt trong bước này; chỉ xét sau TLS PASS
~~~

Các câu “đã cài Tailscale” hoặc “đồng ý Stage 2” không điền thay scope/timebox còn trống. Không cần account thật, email, key, password hoặc QR token trong response.

## J. Rollback and integrity

**Không có resources thuộc deployment Stage 2 được tạo.**

- API process started0; Serve sessions started0; certificate requests0.
- Không rollback/no-op off/reset commands; không dừng Tailscale VPN của laptop hoặc phone.
- Serve/Funnel baseline trống và Services0; kiểm cuối phải giữ như vậy.
- Không thay Windows trust/firewall/profile, tailnet DNS/ACL, SQL/data, source, APK hoặc signing.

Nếu triển khai sau approval: stop đúng owned foreground Serve; so config với baseline; stop đúng API PID/start identity và verify7199 về baseline. Không kill process khác hoặc reset Serve toàn bộ. Không xóa cert/trust, QR/app data/APK. Không disable HTTPS toàn tailnet khi cleanup vì có thể ảnh hưởng services khác.

Baseline Git: branch **auth-jwt-assignment**,398 entries,0 staged; aggregate SHA256537 Git-listed files trong phạm vi loại config/key paths có thể nhạy cảm;6 named APK Cycle1/2/3 và2 handoff APK riêng. Không đọc secret/private-key files hoặc raw policy.

**Final invariant đã kiểm:**537 file trong phạm vi hash giữ nguyên,6 APK named gốc và2 handoff APK giữ SHA256. Git398→399 entries, đúng một báo cáo mới,0 staged, branch giữ nguyên. Báo cáo đủ11 mục A–K, links/whitespace hợp lệ, PowerShell sample parse-only và `git diff --check` exit0. Serve/Funnel vẫn trống, Services0, các cổng443/7199/5121 không listener; Tailscale service vẫn Running và Wi-Fi vẫn Public.

Chỉ intended write là báo cáo Markdown mới này. Không thêm helpers/deployment scripts/logs vào workspace.

## K. GO/NO-GO for Main endpoint build and Final Acceptance

| Quyết định | Kết luận |
|---|---|
| Read-only recheck/report | COMPLETE |
| Stage 2 deployment validation | **BLOCKED — EXPLICIT APPROVALS MISSING** |
| Frontend/upstream TLS | **NOT TESTED**, không gọi PASS/FAIL giả |
| Main endpoint build | **NO-GO** đến khi cả hai TLS legs PASS và user duyệt build riêng |
| Real Published reads | NOT TESTED; AUTHORIZED_QR_NOT_AVAILABLE |
| Phone Published E2E | NOT TESTED |
| Field accuracy | NOT VERIFIED |
| Production/signing deployment | Không thuộc scope |

Bước tiếp theo: owner chốt form mụcI và actual admin settings/policy scope; sau đó mới thực hiện phiên validation được duyệt. Nếu có upstream trust failure thật, dừng và đưa remediation scope riêng thay vì tự chuyển kiến trúc/bỏ TLS.
