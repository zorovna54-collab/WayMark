# WayMark — Final Acceptance Environment Readiness

Ngày chuẩn bị: **31/10/2026 — Asia/Saigon**. Workspace: `D:\project\WayMark`.
Trạng thái giữ nguyên: **CODE-LEVEL FINAL RC READY — PHYSICAL ACCEPTANCE PENDING**.
Đây là kiểm tra cấu hình, integrity và đóng gói; không mở Cycle4.

**Kết luận:** bộ handoff Cycle3 sẵn sàng. Full phone Published campaign **NO-GO tại thời điểm này**: chưa có endpoint HTTPS cho Android được phê duyệt, Main hiện tại compile endpoint emulator, và thiếu authorized QR. Các nhóm local/offline có thể thực hiện khi người dùng bắt đầu campaign; chưa có kết quả nghiệm thu trên điện thoại trong phiên này.

Quy ước: **CONFIRMED** là kiểm trực tiếp file/cấu hình/metadata trong phiên; **HISTORICAL PASS** là bằng chứng phiên trước, không chạy lại; **NOT TESTED** là chưa có phép thử thực tế; **PROPOSED / APPROVAL REQUIRED** là chưa triển khai.

## A. APK integrity

Thư mục bàn giao: [`waymark/build/final-acceptance-handoff`](../waymark/build/final-acceptance-handoff/).
Chứa đúng **2 APK + README.md + manifest.json**. Bản gốc giữ nguyên trong `waymark/build/product-completion-artifacts/`.

| Thuộc tính | Main | Live Test |
|---|---|---|
| File | WayMark-Main-Cycle3-20261031-internal-debug.apk | WayMark-Live-Test-Cycle3-20261031-internal-debug.apk |
| Bytes | 211010342 | 187770181 |
| SHA256 | CADA53AF3B82F586C31B115FF6714CCF03F46D706B4C18C6F0FA3D71376031AB | 2A7E8B75F461D2888974420C5A473D96ACAF31DC3B2B863538D6C42ED9389CB4 |
| Package | com.example.waymark | com.example.waymark.livetest |
| Label | waymark | WayMark Live Test |
| Version /code | 1.0.0 /1 | 1.0.0 /1 |
| min /target /compile SDK | 24 /36 /36 | 24 /36 /36 |
| ABI | arm64-v8a, armeabi-v7a, x86_64 | arm64-v8a, armeabi-v7a, x86_64 |

**CONFIRMED:** SHA256 và byte length khớp release manifest gốc Cycle3; `aapt dump badging/xmltree` kiểm package/ABI/merged manifest; `apksigner verify --print-certs` thành công cho cả hai. Bốn APK Cycle1/2 cũng được verify signer lại. Cả sáu cùng signer certificate SHA256:

`8c15d5eb313223a87d82ef435a13307e74f8abf1a9da2e9dd8de9c21b0cf4df2`

Đây là **Android Debug/internal builds, chưa production-signed**. Hai package khác nhau cho phép cài cùng tồn tại; Cycle3 có bằng chứng cài cả hai trên emulator. Cài cùng tồn tại trên Android thật vẫn **NOT TESTED**, không suy từ metadata thành physical PASS.

Cập nhật in-place cần cùng package/signer và versionCode phù hợp với policy máy. Cycle1/2/3 đều code1; không nhận dạng build bằng versionName đơn thuần. Dùng filename/hash và record installation. Nếu đã có code>1, key khác hoặc installer từ chối, dừng để duyệt cách xử lý/version mới; không uninstall, wipe app data hoặc ép downgrade. Same signer không bảo đảm mọi recovery theo origin được tự chuyển. Backup/export nháp cần giữ trước lần thay endpoint/build sau này.

Evidence: `waymark/build/final-acceptance-readiness-20261031/apk-verification.json`, `prior-apk-signers.json`; manifest gốc `waymark/build/full-product-cycle3-20261031/release-manifest.json`; manifest của bản copy trong handoff. Không build lại APK.

## B. Actual compiled API configuration

**Default hiệu lực theo compile provenance của cả hai APK: `http://10.0.2.2:5121/api`.**

Căn cứ kết hợp: exact APK khớp release manifest, lệnh Gradle cuối trong build logs Cycle3 không có `WAYMARK_API_BASE_URL` trong `-Pdart-defines`, source `String.fromEnvironment` dùng fallback Android, kernel trong từng APK chứa tên cấu hình và marker host tương ứng. Hash của `waymark_api_service.dart` còn khớp baseline trước build Cycle3. Live Test có `WAYMARK_LIVE_TEST=true`; Main không có flag này. Không dựa riêng vào tìm chuỗi binary để khẳng định const value; chưa quan sát Settings trên điện thoại thật trong phiên này.

| Luồng | Cấu hình thực tế | Hệ quả |
|---|---|---|
| Main Auth /Creator /History /Published mặc định | WayMarkApiService.baseUrl; không có define endpoint khi build | Trỏ alias emulator, chưa sẵn sàng backend trên phone |
| Main Settings → Kết nối API | Hiển thị URL và nút probe; không có editor API global | Không thể nhập endpoint mới để sửa APK hiện tại |
| Live Test → Published guest | Ô endpoint ban đầu trống, bắt nhập URL hợp lệ rồi tạo PublishedMapApiService(baseUrl: value) riêng | Có thể nhập HTTPS đã duyệt mà không build lại cho guest flow; không tự dùng default khi ô trống |
| QR correction trong Published guest override | Resolver closure dùng cùng service/base URL và pin map/version | Không quay về default chỉ vì quét QR thứ hai |
| Auth /Creator /History khi có Live Test override | Không được reconfigure bởi ô guest | Không dùng ô này để chứng nhận full account campaign |
| AI | Endpoint/provider riêng; local fallback còn dùng emulator host/port1234 | Không phải WayMark API; cần provider/budget được phép riêng |

`String.fromEnvironment` là compile-time define; chỉ đổi Windows environment hoặc router không đổi APK đã build.

| Nơi gọi | Endpoint phù hợp |
|---|---|
| Windows PC loopback | `https://localhost:7199` — historical TLS/HTTP PASS |
| Android Emulator | `10.0.2.2` là alias host loopback; default hiện tại là HTTP5121, không phải phone endpoint |
| Android thật | FQDN HTTPS reachable, SAN khớp, chain được app/Android chấp nhận; chưa có endpoint đã duyệt |

Ý nghĩa alias emulator được xác nhận bởi [Android Emulator networking](https://developer.android.com/studio/run/emulator-networking-address). `localhost` trên phone là phone; không dùng nó để gọi PC.

**Android policy đã kiểm trên chính APK:** `debuggable=true`, `usesCleartextTraffic=true`; không có `networkSecurityConfig` trong merged manifest. Main source manifest đặt cleartext=false, debug overlay bật true. Không thấy TLS bypass/custom validation trong luồng HTTP Dart đã khảo sát. Cleartext được artifact cho phép không đồng nghĩa HTTPS được bỏ kiểm chứng chỉ, và không được dùng HTTP để vượt gate.

Android target24+ mặc định không tự tin user-added CAs như system CAs; không có custom config trong APK này để dựa vào việc import một user CA. Dart Android cũng dùng platform trust context; Windows đã trust không tự chứng minh Android/Flutter trust. Phải kiểm trong app thật sau endpoint approval. Tham chiếu [Android Network Security Configuration](https://developer.android.com/privacy-and-security/security-config), [Dart SecurityContext.defaultContext](https://api.dart.dev/dart-io/SecurityContext/defaultContext.html).

**Cần phê duyệt build tiếp theo:** Main với `--dart-define=WAYMARK_API_BASE_URL=https://<approved-FQDN>:<approved-port>/api`. Có thể build Live Test cùng default nếu muốn, nhưng guest override không bắt buộc rebuild. Chưa có hostname/port cuối cùng được duyệt nên **không chạy build**. Dùng filename/manifest mới, giữ hai Cycle3 gốc, package/signing hiện tại; nếu cần tăng versionCode phải duyệt riêng. Không hardcode endpoint vào source.

Source đối chiếu: `waymark/lib/services/waymark_api_service.dart`, `auth_api_service.dart`, `map_draft_api_service.dart`, `published_map_api_service.dart`, `navigation_history_service.dart`; `waymark/lib/features/admin/settings_page.dart`; `waymark/tool/live_test_main.dart`; Android main/debug manifests. Build provenance: `android-main.log`, `android-livetest.log` dưới thư mục evidence Cycle3.

## C. Backend /SQL /storage prerequisites

| Kiểm tra trong phiên | Kết quả và giới hạn |
|---|---|
| SDK /project | SDK10.0.402 có sẵn; API target net10.0 |
| Development configuration | appsettings.Development.json tồn tại; cấu hình được đọc và chỉ xuất metadata/boolean allowlist |
| Hosting override | Không thấy key Kestrel/Urls/E2E override trong nguồn cấu hình được kiểm và process environment hiện tại; khi start lại vẫn cần kiểm listener |
| Runtime hiện tại | Không có listener ở các cổng5121,7199,7443 tại lúc kiểm; không khởi động API trong nhiệm vụ này |
| SQL service | MSSQLSERVER Running; SQLBrowser Stopped. Không tự bật service |
| Provider /identity | EF SQL Server qua Microsoft.Data.SqlClient; AuthDbContext và WayMarkDbContext dùng cấu hình database hiện có; Integrated Security=true nên Windows identity của API process cần quyền đã có |
| SQL cấu hình | Connection/database được cấu hình; server local; TrustServerCertificate=true là cấu hình SQL đã tồn tại; Encrypt không set tường minh. Không sửa giá trị nào |
| JWT | Issuer/audience được cấu hình; key đạt kiểm tra chiều dài hiện có. Không xuất nội dung/đổi secret |
| MapImages | Enabled; root tồn tại, nằm ngoài workspace; root không phải reparse point |
| Storage inventory | objects12 files, staging0, leases7. Chỉ liệt kê metadata/count; không đọc ảnh hay lease content, không acquire/cleanup lease |
| Local dev certificate | Thumbprint CC2373AF077AADF1722A14404B74C67CF6D97BCE có ở CurrentUser My và Root, subject CN=localhost, hiện còn hạn |
| Network | Wi-Fi InterfaceIndex17, địa chỉ192.168.1.21/24, profile **Public**; firewall Domain/Private/Public đều Enabled |

Không có SQL SELECT mới, không mở database connection, migration/seed/data write/grant. “Service Running”, connection string hiện hữu và folder đọc được **không phải** API SQL/image GET PASS. Provider defaults của operator System.Data.SqlClient dùng parse cấu hình không được coi là bằng chứng runtime Microsoft.Data.SqlClient. SQL TrustServerCertificate hiện hữu là link DB riêng; không dùng nó làm lý do bỏ app HTTPS validation.

**HISTORICAL PASS:** báo cáo [Local HTTPS resolution](PublishedPilotLocalHttpsResolution20261029.md) ghi hoàn tất trust ngày30/10, API chỉ loopback7199, TLS mặc định và `/weatherforecast`200, process đã dừng. Không lặp toàn bộ bài thử hoặc sửa certificate store. SAN hiện tại phục vụ localhost/dev names và loopback IP; không có endpoint LAN cuối cùng, không chứng minh Android trust.

**Runtime cần giữ trong campaign:** SQL service, image root và metadata đúng, API process dưới identity được phép với config Development hiện tại; phone/PC ở mạng được duyệt; hostname resolution/cert đúng. Không chuyển sang Windows service/user mới rồi mặc định SQL/storage quyền vẫn đúng. Normal Program.cs không tự migration/seed; không dùng E2E launcher thay cho API Development hiện tại.

Public endpoints `[AllowAnonymous]`, không đòi JWT:

~~~text
GET /api/public/qr/{token}
GET /api/public/maps/{mapId}/versions/{version}
GET /api/public/maps/{mapId}/versions/{version}/images/{assetId}
~~~

QR opaque locator resolve ra map/version/floor/node; snapshot và ảnh phải đúng pinned version. Inactive→410, chưa published→409; missing/malformed→404; node mất khỏi snapshot→410. QR URL host không tự chọn API destination; Flutter trích payload và gọi configured API. Public calls tách Authorization, không tự follow redirect sang host khác.

Creator/private endpoints vẫn auth/authorization. Dùng account thử hợp lệ và personal workspace/owner/site role được server xác nhận; nhãn UI không tự cấp quyền publish. Không cấp Admin, sửa JWT hoặc grant để vượt403. CORS Development chỉ loopback origins; native Android HTTP không cần nới CORS để gọi API. `/weatherforecast` anonymous không chạm SQL, nên200 chỉ là HTTP transport.

Source: `WayMark.Api/Program.cs`, `Security/WayMarkSecurity.cs`, `Data/WayMarkDatabaseRegistration.cs`, `Controllers/MapProjectsController.cs`, `Services/MapDrafts/MapProjectService.cs`, storage service, `Properties/launchSettings.json`. Không đưa connection string/database identifiers/storage path/JWT vào report. Evidence sanitize: `waymark/build/final-acceptance-readiness-20261031/environment-sanitized.json`.

## D. Recommended trusted Android endpoint

| Phương án | DNS /TLS /bind | Scope, dữ liệu và private API | Chi phí /nhược điểm /rollback |
|---|---|---|---|
| **A — Private LAN HTTPS, đề xuất có điều kiện** | FQDN thuộc quyền quản lý, DNS phone trỏ192.168.1.21; SAN đúng FQDN, cert/full chain từ CA Android tin cậy. Pilot bind đúng LAN IP:7443; giữ loopback7199 riêng | Chỉ phone IP allowlist trên mạng Private đã xác nhận; không WAN forwarding/tunnel, không mở SQL. SQL/storage giữ local và identity hiện tại. JWT/authorization/rate limits giữ nguyên | Cần domain/cert/DNS phù hợp, có thể có phí theo dịch vụ hiện hữu; chưa định giá. Phụ thuộc PC/IP/Wi-Fi isolation. Rollback owned process, đúng rule mới và DNS/profile đã duyệt |
| B — Managed HTTPS endpoint | FQDN443, system-trusted chain; bind/proxy do managed infrastructure quản lý; backhaul phải được bảo vệ/xác minh | Access restriction tương thích native JSON/JWT, không gateway login redirect. Cần backend kết nối đúng SQL/storage/test data bằng identity đã được phép; không tự chuyển dữ liệu hoặc mở SQL1433 ra Internet | Có yêu cầu hosting/domain/cert/logging và chi phí chưa xác định. Public exposure/logs lớn hơn; không công khai Development/Swagger. Rollback deployment/routing/access rule riêng do owner quản lý |
| C — Hạ tầng VPN/private proxy đã được duyệt, nếu có | Vẫn HTTPS với hostname/chain hợp lệ; TLS backhaul không bị bỏ xác minh | Chỉ dùng hạ tầng có sẵn và scope được chấp thuận; VPN không thay auth hoặc TLS | Không tự tạo VPN/tunnel/proxy. Cần owner vận hành/rollback; hiện không có bằng chứng hạ tầng này sẵn |

**Đề xuất A**, vì giữ database/storage tại PC và tránh deploy/copy dữ liệu ra ngoài. Tuy nhiên Wi-Fi hiện **Public**, chưa xác nhận là mạng riêng đáng tin cậy. Không mở rule cho Public hoặc tự đổi profile. Nếu mạng không thuộc quyền kiểm soát hoặc không có domain/cert phù hợp, dùng B đã được quản lý thay vì nới bảo mật.

Rule Windows Firewall phụ thuộc network profile. Vì vậy đổi Public→Private có thể làm các rule Private hiện có của ứng dụng khác có hiệu lực trên interface này; đây là rủi ro cần review trước approval, không chỉ xét rule WayMark mới. Ưu tiên mạng Private do owner quản lý. Tham chiếu [Windows Firewall profiles](https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/).

Chứng chỉ phải khớp hostname phone gọi; không nhập IP192.168.1.21 nếu SAN chỉ là DNS. Không tái dùng localhost dev cert làm cert phone. Có thể cấp public-CA cert cho domain trỏ private service bằng DNS ownership validation mà không công khai web API; mọi thao tác domain/DNS/issuance đều cần owner duyệt. Tham chiếu [Let’s Encrypt DNS-01](https://letsencrypt.org/docs/challenge-types/). Không đưa DNS credential/private key lên chat.

Kestrel nên dùng named endpoints, bind IP tường minh thay vì coi FQDN là giới hạn interface. Đề xuất Pilot cert riêng, không thay default certificate của loopback. Cấu hình endpoint phải được kiểm cùng listener sau launch; xem [Kestrel endpoints .NET10](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/servers/kestrel/endpoints?view=aspnetcore-10.0).

Nếu endpoint public, public resolver/snapshot/images vốn anonymous: tên/phòng/graph/ảnh đã publish có thể truy cập theo locator/identifier; QR không phải access-control cho bản đồ bí mật. Reverse proxy/access logs có thể chứa QR path; không chia sẻ raw logs. Bảo vệ JWT endpoints không biến public snapshots thành private. Dùng test map riêng không nhạy cảm; không publish dữ liệu bệnh viện/người dùng thật để thử. API Development có Swagger nên chỉ mở trong scope LAN hẹp đã duyệt; không đưa nguyên Development instance ra Internet.

## E. APPROVAL REQUIRED BEFORE PHONE PUBLISHED E2E

**Chưa phê duyệt. Không có network/certificate/DNS/firewall/build thay đổi nào được áp dụng.**
Không coi việc giao nhiệm vụ preparation là approval. Các placeholder dưới đây phải được chốt; chưa đủ dữ liệu để triển khai chỉ từ câu “đồng ý A”.

| Thành phần | Hiện tại, không nhạy cảm | Đề xuất cần duyệt | Scope /rollback |
|---|---|---|---|
| Phone API URL | Chưa có; Main compile emulator | `https://<approved-FQDN>:7443/api` cho A, hoặc managed443 | Cần FQDN thuộc quyền quản lý; restore đúng DNS record cũ nếu đã đổi |
| PC/interface | Wi-Fi17 /192.168.1.21 /Public | A chỉ trên interface này khi owner xác nhận mạng kiểm soát được và duyệt profile Private, hoặc chọn mạng Private riêng | Ghi profile/IP trước thay đổi; chỉ restore phần được task đã duyệt thay |
| Pilot listener | Không có ở7443 | Named Pilot URL `https://192.168.1.21:7443`, đồng thời Loopback `https://localhost:7199` | Không wildcard0.0.0.0, không HTTP5121; dừng đúng owned PID |
| Kestrel process config | Chưa có named endpoint override | Thêm process-scoped `Kestrel__Endpoints__Loopback__Url`, `Kestrel__Endpoints__Pilot__Url`, `Kestrel__Endpoints__Pilot__Certificate__Path`; nếu PFX cần password, `Kestrel__Endpoints__Pilot__Certificate__Password` chỉ nhận local secret input, không argv/log/report | Không sửa appsettings/source/secrets có sẵn. Terminal/child process mới; đóng process và bỏ riêng các env key mới |
| Server cert/chain | Localhost dev cert trong Windows user, giữ nguyên | Cert leaf SAN đúng FQDN, còn hạn, full chain từ CA có trong trust Android/Dart; owner cung cấp public metadata/thumbprint và private path an toàn | Không import CA, không sửa default validation, không xóa localhost trust. Nếu path/ACL chưa đọc được thì dừng xin scope riêng |
| Windows firewall | Tất cả profile Enabled; chưa rule thử nghiệm | Rule tên riêng theo session, TCP7443, local IP192.168.1.21, interface17, **Private only**, remote IP đúng từng phone | Cần danh sách phone IP. Không whole-subnet/WAN/SQL. Remove đúng rule mới theo tên, không rule khác |
| Android | Chưa biết model/API/trust result | Wi-Fi/DNS đúng endpoint; cài nội bộ và quyền cảm biến/camera do người dùng chủ động cho phép | Không root/CA import/bypass TLS. Rollback Wi-Fi/DNS mới nếu có, giữ app data |
| Thời gian /owner | Chưa chốt | Đề xuất một phiên tối đa2 giờ, mốc bắt đầu/kết thúc cụ thể cần người dùng chọn; operator chủ máy chịu trách nhiệm stop/rollback | Không để listener/rule mở vô hạn; giữ record PID/rule trước bắt đầu |
| Data/account | Không có authorized QR | Test workspace và account A/B được owner cho phép; map không nhạy cảm; quyền tạo/publish/revoke test QR nếu cần phải rõ | Không đụng map thật; cleanup/revoke/delete data là quyết định riêng, không tự làm |
| APK cho full account campaign | Cycle3 original không chỉnh | Sau endpoint approval, build Main với WAYMARK_API_BASE_URL chính xác; cân nhắc Live Test default cùng URL | Artifact mới và hash mới, cùng package/key hiện có; không ghi đè Cycle3; version change nếu cần duyệt riêng |
| Managed option B | Chưa chỉ định | Nếu chọn B: endpoint/provider, access scope, backend identity/storage/DB connectivity, TLS backhaul và owner phải được review riêng | Không tự provision hosting, public tunnel hay migrate data |

**Cần người dùng chốt một quyết định:** chọn A hay endpoint B đang quản lý; cung cấp hostname và public certificate identity/chain có sẵn (không private key/password), xác nhận mạng/interface và phone IP allowlist, time window/rollback owner, test workspace/data scope. Sau đó mới có thể hoàn thiện approval thực thi chính xác. Không cần yêu cầu thử từng tính năng ngay trong bước này.

### Rollback của phương án chưa triển khai

Hiện tại **không có rollback network cần chạy**. Nếu A được duyệt và triển khai ở bước sau: ghi owned PID, chỉ stop PID đó; kiểm listener về baseline; remove đúng named firewall rule đã thêm; hoàn nguyên DNS/profile đúng baseline nếu đã thay dưới approval; xóa riêng process env mới bằng đóng terminal. Không kill mọi dotnet process. Không `dev-certs --clean`, không xóa cert thumbprint CC2373AF077AADF1722A14404B74C67CF6D97BCE, không reset SQL/draft/QR/app data. PFX/key gốc do owner quản lý, không tự xóa.

## F. Authorized QR prerequisite

Gate: **AUTHORIZED_QR_NOT_AVAILABLE**. Người dùng chưa chỉ định payload/file cho phép trong nhiệm vụ. Không tìm token trong SQL/source/logs/clipboard hoặc tự tạo/publish/revoke để có đầu vào.

Sau hạ tầng được duyệt: trong WayMark bằng tài khoản owner/publisher của **test workspace**, lưu và đọc lại draft, chọn start node, mở Server/Publish/QR, tạo QR theo saved version rồi xác nhận Publish riêng. Có thể dùng QR đã published được owner cho phép; không cần tạo mới nếu có. QR PNG dùng cho camera trên phone; che QR hoàn toàn trong screenshot chia sẻ.

Nếu cần file cho PC probe: owner lưu **WMQR1 payload** bằng editor local vào folder riêng ngoài repo/handoff/cloud-sync, ví dụ `%LOCALAPPDATA%\WayMark\AcceptancePrivate\authorized-qr.txt`; xác minh ACL folder phù hợp trước khi lưu, không tự đổi ACL trong nhiệm vụ này. Không đặt token trong argv, console history, transcript, báo cáo hoặc chat; không gửi file/payload cho ChatGPT. File chỉ đọc khi owner chỉ định path và authorization.

Pipeline cần kiểm theo thứ tự:

~~~text
Authorized QR
 → HTTPS default certificate verification
 → anonymous resolver
 → map/version pin + node/floor membership
 → pinned floor images (HTTP/MIME/length/integrity)
 → Flutter Visitor camera → Search → Preview → Navigation
~~~

PC dùng GET-only probe có sẵn tại [Preflight mục4E](PublishedPilotExecutionPreflight20261029.md), prerequisite/HTTP helper tại4C. Đây là đoạn PowerShell trong tài liệu, không phải CLI mới. Chỉ stage/status/MIME/bytes/validation được ghi; IDs/token/URL/JSON map giữ trong RAM, không xuất. Không follow redirect/bypass TLS. Sau đó vẫn cần phone camera E2E; PC200 không thay phone evidence.

QR correction thứ hai cần cùng pinned map/version. Nếu không có fixture multi-floor/QR thứ hai được phép, các case tương ứng NOT TESTED. Revoke một test QR chỉ khi owner đã duyệt case đó; không suy revoke sẽ hủy phiên offline ngay tức thì.

## G. Device acceptance instructions

Runbook ngắn: [WayMarkFinalAcceptanceDeviceRunbook20261031.md](WayMarkFinalAcceptanceDeviceRunbook20261031.md).
Checklist gốc [A–J](WayMarkFinalAcceptanceChecklist20261031.md) giữ nguyên và **không tự điền PASS**.

Thứ tự một campaign sau khi prerequisites hoàn tất: install cả hai → UI → Probe/Local Pilot → Creator save/reload → Publish test QR → Visitor → Published Live → correction/multi-floor/manual → History/account recovery → AI/Settings/network/layout → field measurement và diagnostics. Runbook giải thích rõ phần nào không cần API, phần nào chờ endpoint/Main build/QR.

Mọi human test, real sensors, phone Published E2E và field accuracy vẫn **NOT TESTED**. Không đặt accuracy threshold mới hoặc thay thuật toán để làm campaign đạt.

### Phân loại khi chạy campaign

| Biểu hiện | Nhóm cần kiểm | Không được suy /thao tác né |
|---|---|---|
| Không có listener hoặc process exit | API startup/config/SQL/storage exception đã sanitize | Không gọi lỗi TLS nếu chưa bắt tay HTTPS |
| TCP timeout/refused, DNS không đúng | Routing/DNS/listener/firewall/profile/client isolation | Không mở mọi interface/firewall để thử |
| TLS trust/name/expiry/chain failure | Hostname/SAN/chain/clock và trust của chính Flutter | Không click-through/k/TrustAll/import CA không duyệt |
| `/weatherforecast`200 | API HTTPS transport | Không gọi SQL/images/Published PASS |
|401 private request | Auth/session; probe anonymous protected endpoint có thể kỳ vọng401 | Không sửa JWT, không tự retry mutation dưới account khác |
|403 | Owner/site role/permission hoặc policy cụ thể | Không coi là logout hay grant Admin |
| QR404/409/410 | Unknown/malformed /not published /revoked-or-missing node | Không tìm token khác trong SQL |
| Snapshot/image5xx, MIME/length sai | API/SQL/storage identity, metadata/checksum, proxy trả HTML | Không seed/grant/reset storage; không thay ảnh demo che lỗi |
| UI decode/error sau transport | Flutter parsing/rendering/pin/context | Ghi phase, không kết luận network nếu HTTP hợp lệ |
| Detector thiếu/count/heading drift | Capability/permission/sensor/field conditions | Không timer-step/đặt dot chạy để “PASS” |

Browser phone kiểm TLS/transport là gate riêng; Settings/app request kiểm Flutter trust là gate riêng. Mọi lỗi dừng ở lớp tương ứng và giữ dữ liệu hiện có.

## H. Blockers và change safety

| Gate | Trạng thái |
|---|---|
| Exact Cycle3 APK integrity/handoff | VERIFIED |
| Local backend config/service/storage prerequisites | CONFIRMED về metadata; SQL/image read mới NOT TESTED |
| Localhost Windows TLS/HTTP | HISTORICAL PASS, không lặp toàn bài thử |
| Trusted phone endpoint/network scope | BLOCKED — approval và DNS/cert/allowlist chưa chốt |
| Main endpoint cho full phone campaign | BLOCKED — cần approved endpoint build mới |
| Authorized QR /PC resolver snapshot image run mới | AUTHORIZED_QR_NOT_AVAILABLE /NOT TESTED |
| Phone install/UI/camera/sensors/account campaign | NOT TESTED |
| Field accuracy /production signing/deployment | NOT TESTED /PENDING riêng |

Baseline branch **auth-jwt-assignment**, **394 Git entries =44 modified +350 untracked**,0 staged; hash **536 tracked/untracked nonignored files** và6 APK Cycle1/2/3 riêng. Không reset/stage/commit/push hoặc đổi branch.

Chỉ ghi hai tài liệu readiness/runbook mới; ignored build outputs gồm evidence và handoff bốn file. Không đổi source/UI/schema/security/signing/config/SQL/network/cert store; không API launch, build/test/emulator/device install trong phiên này. Chỉ hash/parse/verify/copy artifacts và metadata read-only.

**Invariant đã kiểm cuối:**536/536 file baseline giữ SHA256;6/6 APK gốc Cycle1/2/3 giữ hash; hai bản copy khớp manifest. Git394→396 entries, đúng hai tài liệu mới,44 modified giữ nguyên/352 untracked,0 staged, branch giữ nguyên. Handoff đúng4 files. JSON manifest và PowerShell samples parse thành công; `git diff --check` exit0 (có warning LF/CRLF hiện hữu, không sửa line-ending policy). Evidence: `waymark/build/final-acceptance-readiness-20261031/invariants.json`. Không chạy lại application tests/build cho thay đổi tài liệu/copy artifact.

## I. GO /NO-GO for Final Acceptance Campaign

- **GO — handoff preparation:** completed; Cycle3 giữ code-level Final RC.
- **CONDITIONAL GO — các nhóm local/offline:** người dùng có thể chạy khi chủ động bắt đầu campaign; physical results vẫn NOT TESTED.
- **NO-GO — full Published phone campaign ngay bây giờ:** cần approved trusted endpoint + Main build trỏ endpoint + authorized test data/QR + phone/time window.
- **Chưa production/field acceptance:** không biến emulator tests, metadata, local HTTPS200 trước đây thành phone hoặc accuracy PASS.

Bước tiếp theo là **chốt approval packet mụcE**, không mở Cycle4 và không yêu cầu người dùng test rời rạc trong lúc chuẩn bị.
