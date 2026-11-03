# WayMark — Tailscale Stage 2 Deployment Result

Ngày: **01/11/2026 — Asia/Saigon**. Workspace: `D:\project\WayMark`.

**FAIL-CLOSED PRECHECK STOP — EFFECTIVE_POLICY_SCOPE_MISMATCH.**

Approval triển khai đã được ghi nhận đầy đủ trong prompt mới. Tuy nhiên packet filter đang được laptop sử dụng vẫn rộng hơn scope POCO→laptop TCP443. Theo điều kiện owner đặt ra, phiên dừng **trước khi khởi chạy API hoặc Serve**. Không đổi policy, cấp certificate hoặc build APK.

Đây là blocker đã được xác minh bằng metadata effective của daemon, không còn là tình trạng thiếu approval của [báo cáo Stage 2 trước](WayMarkTailscaleIntegrationStage2_20261101.md).

## A. Owner authorization scope và thời gian

Owner đã cho phép:

- Xác minh HTTPS eligibility và access scope POCO **100.104.185.21** → laptop **100.88.119.31**, TCP443, không sửa policy.
- Tạm chạy đúng một API Development dưới user hiện tại, chỉ HTTPS localhost7199.
- Serve private foreground443 → HTTPS localhost7199, không Funnel/background/insecure fallback.
- Certificate issuance và CT publication cho **laptop-pfrpmr3o.tail7697c0.ts.net**.
- Default TLS và GET-only `/weatherforecast`; Main debug build chỉ khi cả hai TLS legs PASS, không install lên phone.
- Giữ package/signing, APK gốc/handoff và dữ liệu.

Operator/rollback owner do owner chỉ định: **người sử dụng laptop trực tiếp giám sát**. Thời lượng triển khai tối đa60 phút kể từ khi bắt đầu deployment.

| Mốc | Kết quả |
|---|---|
| Stop decision của precheck | **2026-11-01 08:43:23 +07:00** |
| Deployment start | **NOT STARTED** |
| Deployment end | **NOT APPLICABLE — không có deployment được tạo** |
| Deployment timebox | Chưa kích hoạt; không bịa start/end hoặc gọi precheck là thời gian API/Serve chạy |
| Lý do không bắt đầu | Effective access policy không khớp owner-provided scope |

Không cần xin lại những approval vừa được cấp để làm read-only precheck. Mọi policy edit vẫn nằm ngoài scope đã duyệt.

## B. Tailscale precheck /actual access policy

### B1. Identity /HTTPS /baseline

| Kiểm tra thực tế | Kết quả |
|---|---|
| CLI/daemon | **1.104.4**, BackendState Running |
| Laptop | Online; IP self khớp100.88.119.31 |
| Android | Đúng1 Android peer có100.104.185.21; online |
| FQDN | **laptop-pfrpmr3o.tail7697c0.ts.net**, khớp owner input |
| MagicDNS | Enabled |
| CertDomains | Exact FQDN **eligible=true**; thay đổi tích cực so với Stage 1 |
| Serve/Funnel trước mutation | Đều trống |
| Existing listener443/7199 |0 |

HTTPS eligibility hiện phù hợp với owner xác nhận HTTPS Certificates Enabled. Đây là provisioning readiness; chưa đo public leaf/chain hoặc chứng minh certificate đã được cấp trong phiên này.

### B2. Effective filter đã đọc được, không cần account/API key

Đã đối chiếu implementation **đúng tag1.104.4**, rồi dùng GET-only LocalAPI qua CLI:

~~~powershell
$ts = 'C:\Program Files\Tailscale\tailscale.exe'
& $ts debug localapi GET /localapi/v0/debug-packet-filter-rules
& $ts debug localapi GET /localapi/v0/debug-packet-filter-matches
~~~

Trong thực thi, output được parse và chỉ phát metadata cần thiết; không dump full status/netmap, email, keys hoặc raw Admin policy. Các endpoint này trả packet filter rules/compiled matches của backend hiện tại; không gọi endpoint sửa policy/prefs.

Nguồn implementation: [LocalAPI debug handlers1.104.4](https://github.com/tailscale/tailscale/blob/v1.104.4/ipn/localapi/debug.go), [FilterRule schema1.104.4](https://github.com/tailscale/tailscale/blob/v1.104.4/tailcfg/tailcfg.go).

**Rules observed, được recheck và đối chiếu compiled matches:**

| Thành phần | Effective trên laptop |
|---|---|
| Rule count |1 |
| Source range1 |100.115.94.0–100.127.255.255 |
| Source range2 |100.64.0.0–100.115.91.255 |
| Source IPv6 |fd7a:115c:a1e0::/48 |
| Raw destination |`*` |
| Ports |**0–65535** |
| IPProto raw |Không set tường minh |
| Compiled protocols |**6/TCP,17/UDP,1/ICMPv4,58/ICMPv6** |
| Compiled destinations |**0.0.0.0/0 và ::/0**, port0–65535 |
| Compiled source representation |14 prefixes; biểu diễn phân rã của các ranges, không phải14 thiết bị |

POCO nằm trong source range quan sát, nên TCP443 được bao gồm; **vấn đề là quyền rộng hơn scope**, không phải một kết quả POCO bị deny443.

Kết quả trên là policy/filter hiện laptop đã nhận, không phải suy đoán từ số peer hoặc owner declaration. Không suy từ `Dst=*` rằng Admin policy chắc chắn viết literal `dst:*`: control plane có thể tối ưu filter theo node. Nhưng source ranges rộng, all-port range và compiled TCP/UDP đã đủ chứng minh filter trên laptop chưa giới hạn đúng phone/TCP443.

**Gate FAIL:** effective network scope không khớp grant hẹp mà owner cho biết. Không tuyên bố đã xác định chính xác dòng grant/ACL trong Admin Console; chưa đọc authoritative policy file. Không kết luận tất cả các địa chỉ này là thiết bị thực tế đang có hoặc đã truy cập API.

## C. API listener và localhost HTTPS

**API STARTUP: NOT ATTEMPTED — POLICY PRECHECK FAILED.**
**LOCAL HTTPS GET: NOT TESTED trong lượt triển khai này.**

Không tạo API process, không dùng launch profile, không bind LAN/wildcard/HTTP5121 hoặc mở SQL. Localhost HTTPS PASS ngày30/10 vẫn là prior evidence trong [báo cáo local trust](PublishedPilotLocalHttpsResolution20261029.md), không được nâng thành runtime PASS mới.

Chỉ khi effective policy đạt scope mới tiếp tục existing binary/user/Development, kiểm owned PID chỉ127.0.0.1/::1:7199 và default-TLS GET200 trước khi Serve. Không thay auth, connection strings, database hoặc Windows trust.

## D. Serve configuration và cert

**SERVE: NOT STARTED. CERTIFICATE REQUESTS BY THIS TASK:0.**

Baseline trống và không listener443/7199 trước deployment. Không chạy target command `serve --https=443 https://localhost:7199`, không consent/`--yes`/`--bg`, Funnel hoặc `serve reset`.

Owner đã duyệt issuance/CT; gate ngăn triển khai là policy mismatch, không còn thiếu CT approval. CertDomains eligible không thay cho runtime TLS evidence. Không đọc private certificate/key cache hoặc cấp cert “để thử trước”.

## E. Frontend HTTPS result

**NOT TESTED.** Không frontend handshake, SAN/chain/expiry inspection hoặc GET `/weatherforecast` qua *.ts.net trong lượt này.

Không HTTP200,502 hoặc TLS error nào được quan sát để báo PASS/FAIL của frontend. Không dùng TLS probe nhằm kích hoạt issuance khi policy gate đã fail.

## F. Upstream HTTPS result

**NOT TESTED. X509/UNKNOWN AUTHORITY: NOT REPRODUCED.**

Rủi ro LocalSystem/CurrentUser trust từ Stage 1 vẫn là rủi ro chưa đo. Phiên dừng sớm hơn TLS layer; không gán blocker hiện tại cho certificate.

Không import LocalMachine Root, đổi service identity, tạo cert localhost mới, dùng insecure target hoặc chuyển HTTP. Chưa có lý do thực nghiệm để chọn PKI remediation trong lượt này.

## G. Exact cause nếu fail

**Một blocker ưu tiên: `EFFECTIVE_POLICY_SCOPE_MISMATCH`.**

Evidence:

1. Đúng laptop identity/IP/FQDN và CLI1.104.4.
2. GET packet-filter-rules cho source ranges rộng, all ports.
3. Recheck normalized arrays vẫn cùng dữ liệu; compiled packet-filter-matches xác nhận TCP/UDP và destination all-port ranges.
4. Bởi vậy owner-provided statement “allow-all đã thay bằng grant giới hạn” **chưa phản ánh filter laptop đang sử dụng**.

Chưa xác minh nguyên nhân phía control plane: có thể policy chưa save/apply, chọn nhầm tailnet hoặc còn một allow path rộng, hoặc cấu hình chưa đồng bộ. Đây là giả thuyết cần owner đối chiếu, không phải root cause đã chứng minh.

Không chạy force-netmap-update, reconnect/restart service hoặc sửa policy để ép trạng thái. Không thêm rule hẹp lên trên broad allow rồi coi scope đã thu hẹp.

## H. Main APK build/hash/signature

**BUILD: SKIPPED BY REQUIRED TLS GATE.**

Hai TLS legs chưa được thử nên không được build Main trong lượt này, dù owner đã duyệt build có điều kiện. Không chạy Flutter/Gradle/analyzer/regression; không thay source/build config và không tạo signing key.

`WayMark-Main-Tailscale-HTTPS-Internal-debug.apk` **chưa được tạo**; không có SHA256/manifest mới để công bố. Không install APK lên phone.

Endpoint chỉ được chốt sau HTTPS thật PASS:
`https://laptop-pfrpmr3o.tail7697c0.ts.net/api`.

Giữ nguyên6 APK named Cycle1/2/3 và2 handoff APK. Published QR gate vẫn `AUTHORIZED_QR_NOT_AVAILABLE`; không SQL/token lookup, publish/revoke hoặc data write. Phone Published E2E và field accuracy NOT TESTED/NOT VERIFIED.

## I. Rollback /integrity

- API owned processes created0; Serve foreground sessions created0.
- Không có deployment resource để rollback; không chạy off/reset hoặc kill process.
- Giữ Tailscale VPN của cả laptop/phone; không stop service hoặc đổi network/firewall.
- Không certificate issuance/trust changes, policy write, SQL operation, APK modification hoặc user-data deletion.

Baseline branch **auth-jwt-assignment**,399 Git entries,0 staged. Hash538 Git-listed files trong phạm vi loại config/key paths có thể nhạy cảm;6 APK named và2 handoff APK riêng. Không đọc secret/private-node state hoặc private keys. Public source/GET filter data được dùng cho kiểm scope, không phải Admin account export.

**Final integrity lúc2026-11-01 08:45:45 +07:00:**538 file trong phạm vi hash giữ nguyên;6 APK named gốc và2 handoff APK giữ SHA256. Git399→400 entries, chỉ thêm báo cáo này,0 staged, branch giữ nguyên. Mẫu PowerShell/JSON parse hợp lệ; links/whitespace và `git diff --check` đạt. Artifact Main Tailscale chưa tồn tại. Serve/Funnel vẫn trống, Services0, các cổng443/7199/5121 không listener; service Tailscale vẫn Running và Wi-Fi vẫn Public.

Chỉ intended write là Markdown result mới này. Không thêm helper scripts, deployment logs hoặc manifest/APK mới.

## J. NEXT ACTION — APPROVAL REQUIRED /READY

**DEPLOYMENT: NOT READY — OWNER POLICY CORRECTION REQUIRED.**

Hành động ưu tiên duy nhất: owner mở đúng tailnet trong Admin Console, kiểm Saved/active policy và loại/thu hẹp allow path đang bao phủ rộng laptop; giữ các quyền hợp lệ khác theo chủ đích. Nếu policy trong Console đã hẹp, kiểm save/apply và đồng bộ bình thường tới đúng laptop trước khi tiếp tục. Không cần tự tạo thêm một chuỗi audit report mới.

Target grant để **đối chiếu**, không phải replacement policy hoặc diff đã apply:

~~~json
{
  "src": ["100.104.185.21"],
  "dst": ["100.88.119.31"],
  "ip": ["tcp:443"]
}
~~~

Không có authoritative policy source nên chưa thể nêu line-level diff an toàn. Owner có thể tự sửa/lưu trong Console; nếu muốn agent sửa, cần scope approval riêng và diff trên đúng policy hiện có, không overwrite cả file.

| Policy acceptance cần kiểm sau sửa, chưa chạy | Expected |
|---|---|
| POCO→laptop TCP443 | Allow |
| POCO→laptop TCP7199/5121 hoặc port khác ngoài scope | Deny theo pilot policy |
| POCO→laptop UDP443 | Không được grant pilot TCP443 vô tình cho phép |
| Node khác ngoài approved phone scope→laptop TCP443 | Deny theo scope owner đã chọn |
| Existing flows hợp lệ không thuộc pilot | Không bị sửa/xóa mù |

Khi owner xác nhận đã lưu policy đúng, đọc lại effective rules/compiled matches một lần. Chấp nhận semantics đã được compiler tối ưu, không yêu cầu raw destination literal phải luôn trùng IP nếu filter node-local tương đương. Nếu scope đã đạt, tiếp tục **cùng authorization đã cấp** với phiên có operator giám sát, tối đa60 phút kể từ deployment start, rồi đo hai TLS legs. Không cần xin lại CT/API/Serve chỉ vì precheck này dừng.

Không mở rộng trust hoặc chuyển HTTP trước khi có upstream TLS failure thật. Nếu TLS PASS thì mới build artifact đã được duyệt có điều kiện; không tuyên bố Published E2E PASS khi chưa có QR và Android test thật.
