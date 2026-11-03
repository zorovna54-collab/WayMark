# Sprint 10 — History, Visitor Zoom và WayMark Studio

Ngày: 26/10/2026. Branch: `auth-jwt-assignment`.

**Cập nhật 26/10: CODE PASS / API + SQL PASS / ANDROID PASS trong phạm vi fixture Development đã duyệt.** Đã dùng SQLCMD được cho phép, backup/VERIFYONLY và áp dụng đúng hai History migrations; History đã ghi/đọc lại trên SQL thật, kiểm tra Android và xóa fixture thành công. Chi tiết: [Sprint10SqlHistoryAcceptance.md](Sprint10SqlHistoryAcceptance.md).

Các mục BLOCKED BY WINDOWS POLICY bên dưới lưu lại trạng thái của lượt thử DLL trước đó, không còn là trạng thái chung hiện tại. Không chạy lại DLL, không thay Windows policy. Pinch hai ngón/camera vật lý vẫn MANUAL PENDING; 1×/2×/4× trên Published Map thật đã được đo từ ảnh Android qua debugger controller.

Không đọc/sửa Master Plan. Không commit/push, reset/clean/restore Git; không sửa Gradle, Windows generated hoặc Figma. Những thay đổi có sẵn được giữ nguyên.

## 1. Kết quả và nguyên nhân

| Feature | Root cause | Fixed | Test level | Manual pending |
|---|---|---|---|---|
| History từ QR | Bảng SQL chưa tồn tại; ghi trước đây bắt đầu ở Navigation, bỏ qua lần scan chưa chọn đích | Resolve snapshot thành công → tạo Scanned với SessionId; camera burst/retry giữ ID | Flutter HTTP mock; API/Identity/SQLite/file integration; SQL SELECT xác nhận thiếu bảng | SQL Server write/read/restart và Android đăng nhập thật |
| Destination / Start / Finish / Cancel | Thiếu vòng đời scan-first; có đường thoát không thể hiện lỗi đồng bộ | Cập nhật cùng ID; chỉ Finish rõ ràng mới Completed; thoát bất thường giữ phiên dở; lỗi mạng cho ở lại/thử lại | Backend lifecycle/idempotency/isolation; Flutter lifecycle và cancel lỗi | Lifecycle account trên Android + SQL Server |
| Home Recent | Lấy các WayMark đầu danh sách thay vì lịch sử tài khoản | Cùng NavigationHistoryService với History; refresh qua notifier; đổi account xóa dữ liệu UI ngay | Widget + HTTP mock, Guest Home thực trên emulator | Recent của account với SQL thật |
| Visitor Zoom | Painter vẽ marker/stroke trong scene-space nên scale cùng ảnh | Helper chung Builder/Visitor bù kích thước; tâm/edge endpoints vẫn theo ảnh | Raster thật 1×/2×/4× + pan, sai số ≤1 pixel; Viewer/Fit tests | Pinch trên Published map bằng API/Android thực |
| Studio / Home | Drawer tên Admin, điều hướng cũ thay route; Login còn mở dashboard số liệu giả và clear session | WayMark Studio theo capability; Home trực tiếp; giữ editor khi push; Save/Leave/Keep guard; Login mở Builder local thay dashboard giả | Widget; emulator main APK: local Builder → menu → guard Keep → Leave → Home | Creator đã đăng nhập trên API thực |
| Authorization | UI không phải hàng rào quyền | Policy/ownership backend giữ nguyên, private History luôn theo signed JWT subject | 96 regression tests gồm auth/history/publication/account security | SQL negative tests sau khi chạy được runner |

### History contract và chính sách

- `POST /api/me/navigation-history`: `{sessionId, qrToken}` tạo Scanned **sau khi QR active và published snapshot hợp lệ**; chưa cần đích. Tương thích request cũ có destination: vào InProgress.
- `PUT /{id}/destination`: lưu GUID node/tầng, tên đích, tổng khoảng cách Dijkstra tính từ snapshot, không từ pixel. Scanned giữ nguyên cho đến Start.
- `PUT /{id}/start`: Scanned → InProgress, idempotent.
- `PUT /{id}` với Completed/Cancelled: terminal một lần, cập nhật thời gian. Completed yêu cầu đã Start.
- GET list/detail/resume, DELETE một bản ghi: riêng chủ sở hữu; account khác (kể cả Admin) không đọc/xóa được. Guest 401 trên History, vẫn được dẫn đường public.
- Lưu map/version, start node/floor, destination nullable, scan/start/end time và distance. UI gọi distance là khoảng cách theo graph, không phải quãng đường người dùng đã thực đi.
- Một session theo map snapshot đi qua Search/Preview/Navigation; không tạo session từ build/dispose hoặc QR relocalization. Retry sau lỗi giữ nguyên ID. Finish lỗi không được báo đã đồng bộ.
- Guest chưa có persistent local History, không tự gộp vào account. Đổi account không gửi tiếp các request của session cũ.
- List tối đa 100 phiên mới nhất; Home lấy 3 từ cùng API. Không thêm Clear All giả.

## 2. Migration / SQL thực tế

SELECT trước và sau công việc: đúng `LAPTOP-PFRPMR3O / WayMarkDatabase / LAPTOP-PFRPMR3O\pc`; 5 business migrations đã áp dụng, mới nhất AddPublishedMapProjects. `NavigationHistory` chưa tồn tại.

Giữ nguyên migration cũ `20261025010000_AddNavigationHistory`. Tạo thêm `20261026001522_ExtendNavigationHistoryLifecycle` cùng Designer và snapshot tương ứng. Không đưa Identity vào business snapshot.

SQL preview: `docs/database/sprint10/NavigationHistory.review.sql`, sinh offline bằng EF SQL Server provider:

```powershell
dotnet run --project tools/Sprint10Review -- script
```

Tool xác minh model/snapshot không pending; không có connection string hoặc SQL execution path. Script chuyển từ AddPublishedMapProjects qua đúng hai History migrations; SHA-256:
`D0C84FBF8EC4129B1DB47B72F370210DD9EC32A2FFFBF24401158B1BCF1AAAA6`.

- Up cũ: tạo bảng History, PK Id, index UserId/StartedAtUtc, status constraint và migration-history entry.
- Up mới: destination GUIDs cho phép NULL; thêm nullable StartFloorKey, ScannedAtUtc, NavigationStartedAtUtc, DistanceMeters decimal(18,3); mở constraint cho Scanned; thêm history entry.
- Có transaction/COMMIT và GO tách hai migration. DROP chỉ là thay check/default constraint trên bảng History; không DROP bảng/cột, TRUNCATE hoặc DELETE dữ liệu nghiệp vụ trong Up script.
- Down mới xóa bốn cột, ép destination không NULL và không biểu diễn được Scanned; Down cũ xóa bảng. **Không sử dụng Down hoặc tự restore làm rollback dữ liệu thật.** Khi lỗi phải dừng, đối chiếu history/schema và chuẩn bị forward repair được review.

User đã duyệt backup mới + đúng hai migrations + 2 account test không email/không Admin và History trên published fixture P0Runtime hiện có. Runner `tools/Sprint10SqlSmoke` chuẩn bị đúng phạm vi này, không tạo/sửa map, QR, graph, role hay database. Có target/encryption gate, exact baseline, SQL SHA-256, FULL COPY_ONLY/CHECKSUM/VERIFYONLY, fingerprint bảng được bảo vệ, loopback API và restart, test isolation/delete chỉ ID History mới tạo.

**Runner chưa chạy được entry point do Windows policy.** Chưa tạo backup mới, chưa migration, chưa tạo 2 account, chưa chạy HTTP SQL History smoke, chưa xóa History. SELECT cuối xác nhận bảng vẫn vắng; backup gần nhất vẫn 24/10/2026 14:31:57. Không có SQL TEST FAILED: các case chưa khởi chạy.

## 3. Điều tra Windows policy (chỉ đọc)

- CodeIntegrity/Operational: **3077 và 3033**, path `D:\project\WayMark\tools\Sprint10SqlSmoke\bin\Debug\net10.0\Sprint10SqlSmoke.dll`, process `C:\Program Files\dotnet\dotnet.exe`.
- Policy `VerifiedAndReputableDesktop`, GUID `{0283ac0f-fff1-49ae-ada1-8a933130cad6}`; status `0xc0e90002`, requested signing level 2, validated 1. Runtime báo `0x800711C7`.
- Registry chỉ đọc `VerifiedAndReputablePolicyState=1`: Smart App Control đang bật. Không thay registry/policy, không Unblock-File hoặc ExecutionPolicy bypass.
- AppLocker EXE and DLL không có event trong khoảng kiểm tra; MSI/Script có 1 event nhưng không liên quan Sprint10SqlSmoke. Không kết luận AppLocker là nguồn chặn.
- DLL `NotSigned`; chỉ có stream `:$DATA`, không thấy Zone.Identifier. Log không phải bằng chứng Windows phát hiện malware trong source; bằng chứng trực tiếp là không đạt signing requirement.
- Project reference đúng API workspace; build bằng SDK .NET hiện có. Rebuild cùng source cho cùng SHA-256. Source hiện tại `Program.cs`: `5980850B502A43F65040568BECCDFFF7290064F2895B54D7C83C79F711A632E3`; project: `E5CB7FC488B64627D45CD31CAF7B35D035E0D80C3B0A42F63CF56FD833BD488E`; DLL hiện tại: `4378C7531007A2336089F45AB60DFC188B13110940CFE3D2CBCABFDEDC9BFA4B`.
- Event block ghi flat hash `CC1A4CC7C64E1AE758C897B28B368F3EA8235797FDB5BD65AE56801658D7F062` của build trước. Sau đó source bổ sung XACT_ABORT/rollback transaction do runner sở hữu rồi rebuild; vì thế hash hiện tại khác. Không giả định hai binary là một. Chưa thử chạy build mới để dò xem đổi hash có tránh được policy.
- SQLCMD sẵn tại `C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE`, Microsoft signature **Valid**, version 2022.0160.1000.06. SELECT chạy thành công. Đây là bằng chứng client SQL có sẵn dùng được cho đọc; chưa dùng để thay host/logic của assembly bị chặn hoặc để ghi SQL trong sprint này.

### Hướng xử lý hợp lệ, chưa thực hiện

1. Mở `eventvwr.msc` → Applications and Services Logs → Microsoft → Windows → CodeIntegrity → Operational; lọc ID 3077/3033, đối chiếu path/hash/policy ở trên. Có thể xem Windows Security → App & browser control → Smart App Control để xác nhận trạng thái, không đổi thiết lập.
2. Smart App Control hiện không có Allow riêng từng app. Không có bước “thêm ngoại lệ hash” ở giao diện SAC. [Microsoft FAQ](https://support.microsoft.com/en-us/windows/security/threat-malware-protection/smart-app-control-frequently-asked-questions).
3. Phương án phù hợp: người quản lý signing review source, build và ký code bằng chứng thư code-signing được trusted provider cấp (hoặc Artifact Signing đã được tổ chức phê duyệt). Ký đúng binaries cần thiết; không chép private key/password vào repo, không tự thêm root certificate hoặc dùng strong-name như thay thế Authenticode. [Microsoft signing guidance](https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/code-signing-for-smart-app-control).
4. Kiểm tra `Get-AuthenticodeSignature` trả Valid và publisher mong đợi; ghi hash sau ký; xác nhận policy chấp nhận trước khi chạy gói SQL đã duyệt. Không cần cấp lại phạm vi SQL, nhưng hiện chưa có bằng chứng tổ chức đã có signing certificate/service. Signing xác minh publisher và tính toàn vẹn, không thay review nghiệp vụ hoặc backup gate.
5. Nếu đây là máy do tổ chức quản lý với policy bổ sung khác, chuyển event/manifest cho người quản lý policy để họ đánh giá theo quy trình chính thức; không tự triển khai supplemental policy. Không đổi tên/copy binary, chạy host khác hoặc tắt bảo vệ để né chặn.

Evidence chỉ chứa metadata an toàn: `waymark/build/qr-publish-hotfix/sprint10-codeintegrity.json`, `sprint10-policy-manifest.json`, `sprint10-deterministic-build.log` (Git ignored).

## 4. Kiểm thử đã chạy

| Lệnh / mức kiểm thử | Kết quả |
|---|---|
| `flutter analyze --no-pub` | No issues |
| `flutter test --reporter expanded` cuối | **314 pass, 3 skip** (các live/browser tests opt-in; không coi skip là pass) |
| Targeted Flutter History/Studio/Zoom/QR/account/profile | **29/29** |
| Backend build + SQL runner build | 0 warnings, 0 errors; không đồng nghĩa runner được Windows cho thực thi |
| `dotnet test ... --filter NavigationHistoryTests/AccountSecuritySprint9Tests/AdminAuthorizationTests/PublishedMapTests` | **96/96**, dùng host cô lập/SQLite và tests SQL provider offline, không phải SQL Server persistence |
| Offline SQL generator | Model/snapshot khớp, sinh script thành công, không mở SQL connection |
| Android main debug APK | Build, install và launch thành công; giữ nguyên Gradle |
| Android demo entry `tool/mobile_map_demo.dart` | Có nhãn DEMO OFFLINE, không API/SQL: Preview → Navigation 6 bước → chuyển L1/G → Arrival → Finish về Preview |
| Android main UI | Login mở Builder local; menu Studio/Visitor; tạo scratch local mới, Home có guard, Keep không rời, Leave về Home; Guest Recent không hiện dữ liệu account |
| Zoom pixel proof | Raster marker/stroke invariant ±1 pixel ở 1×/2×/4× + pan; Fit và source coordinates tests pass. Chưa nghiệm thu pinch qua Published API trên emulator |
| `git diff --check` | PASS; có cảnh báo LF→CRLF theo Git, không phải whitespace error |

Ảnh ở `waymark/build/qr-publish-hotfix/`: `sprint10-demo-preview.png`, `sprint10-demo-navigation.png`, `sprint10-demo-ground.png`, `sprint10-demo-arrival.png`, `sprint10-studio-menu.png`, `sprint10-unsaved-guard.png`, `sprint10-home-final.png`. Ảnh demo không chứng minh SQL hoặc camera mới. Đã cài lại main APK sau khi thử demo; APK main tại `build/app/outputs/flutter-apk/app-debug.apk` và bản sao `build/qr-publish-hotfix/sprint10-main.apk`.

## 5. Functional audit — không đánh đồng các mức bằng chứng

- User tự nghiệm thu trước sprint: personal map → save server → QR → publish → account khác → scan → Search/Preview/Navigation/Arrival. Giữ nguyên, không gọi là lượt nghiệm thu mới của agent.
- History account/Home Recent: source và cô lập PASS; SQL thực chưa triển khai, không báo persistence thành công.
- QR burst/retry/revoked và AuthSession: automated PASS; không quét camera lại trong lượt này.
- Published snapshot/owner/User B/Guest: regression backend PASS ở môi trường cô lập; SQL History isolation chưa chạy.
- Profile, role-aware Settings và reset password: regression Flutter/backend PASS. Email reset Inbox đã được user xác nhận trong sprint trước; không gửi thêm email hoặc thử reset tài khoản thật trong lượt này.
- Admin dashboard metrics/tài khoản/Site/role/quota/traffic chưa có API thực tương ứng: dashboard demo đã không còn lối vào từ Login/Studio; System Admin item chưa khả dụng. Không dựng telemetry như dữ liệu thật. Class legacy vẫn giữ để không xóa công việc ngoài phạm vi.
- Local Builder/navigation/JSON nhiều tầng tiếp tục có regression; không publish bản local tự động, không thay Dijkstra/JWT/production graph.

## 6. File thuộc thay đổi Sprint 10

- Backend: `Models/NavigationHistory.cs`, `Data/NavigationHistoryModel.cs`, `Controllers/NavigationHistoryController.cs`, `Services/MapDrafts/MapDraftRegistration.cs`; lifecycle migration/Designer/snapshot.
- Backend tests: `NavigationHistoryTests.cs`, `AdminAuthorizationTests.cs`, `MapDraftTestHost.cs` (dispose null-safe để không che lỗi khởi tạo host).
- Flutter lifecycle: `services/navigation_history_service.dart`, `services/auth_session.dart`, `features/navigation/local_map_navigation.dart`, `features/scanner/scanner_page.dart`, `features/scanner/public_map_entry_page.dart`, `features/search/local_map_search_page.dart`, `features/route/route_preview_page.dart`, `features/navigation/navigation_page.dart`.
- Flutter UI: `features/history/history_page.dart`, `features/home/home_page.dart`, `features/admin/admin_page_shell.dart`, `features/admin/draft_map_editor.dart`, `features/admin/map_project_cloud_page.dart`, `features/auth/login/login_page.dart`.
- Zoom: `features/route/map_paint_scale.dart`, `features/route/floor_route_map.dart`, Builder painter dùng chung helper trong `draft_map_editor.dart`.
- Tests: `sprint10_history_test.dart`, `sprint10_studio_test.dart`, `sprint10_zoom_test.dart`, cập nhật `sprint9_account_history_test.dart`, `core_verification_qr_test.dart`, `draft_map_test.dart` (assertion nhãn đếm Node/Edge cũ).
- Review/execution source: `tools/Sprint10Review/`, `tools/Sprint10SqlSmoke/`, SQL preview và báo cáo này. Không stage/commit; status còn nhiều file từ các sprint trước, danh sách này không nhận toàn bộ dirty workspace là thay đổi mới.

## 7. Nghiệm thu thủ công (sau khi SQL gate được chạy hợp lệ)

> Checklist kế hoạch của lượt trước, đã được thay bằng quy trình SQLCMD và nghiệm thu trong `Sprint10SqlHistoryAcceptance.md`. Không chạy lại DLL/apply migrations theo bước 1 bên dưới; schema hiện đã được áp dụng thành công.

1. Chạy main API Development loopback bằng quy trình hiện có; chạy runner đã được Windows chấp nhận với `--execute-approved-history`: backup mới/VERIFYONLY phải PASS trước hai migrations. Nếu gate lỗi, dừng; không restore tự động.
2. Chạy main Android APK với `WAYMARK_API_BASE_URL=http://10.0.2.2:5121/api`, đăng nhập tài khoản test, quét QR Published hợp lệ; History phải có ngay Scanned dù chưa chọn đích. Giữ camera trên mã không nhân bản session.
3. Chọn destination → Preview → Navigation; kiểm tra cùng ID chuyển InProgress. Pinch 1×/2×/4×, pan và Fit: tâm bám ảnh, marker/stroke không phình; chuyển tầng không nối đường xuyên ảnh.
4. Xác nhận từng bước và QR đúng node; Arrival chưa tự ghi Completed. Bấm Kết thúc mới cập nhật; Home Recent và History cùng hiển thị. Thử Cancel và lỗi mạng: không giả báo lưu thành công.
5. Restart API/app, login lại: History vẫn còn; User B/Guest không thấy của A. Xóa một record rồi reload phải mất thật; không thử xóa dữ liệu người dùng ngoài fixture.
6. Trong Builder có chỉnh sửa chưa lưu, mở Home: Keep giữ draft, Save phải có xác nhận lưu thật/JSON, Leave chỉ khi đồng ý. Kiểm tra Creator không thấy công cụ System Admin hoạt động.

**Kết luận của lượt DLL trước (lịch sử):** source/Android độc lập đạt; DLL smoke bị Windows policy chặn trước SQL.

**Kết luận cập nhật hiện tại:** CODE PASS / API + SQL PASS / ANDROID PASS theo [nghiệm thu SQLCMD thực tế](Sprint10SqlHistoryAcceptance.md). Backup mới, hai History migrations và workflow History SQL/Android đã hoàn tất trong scope được duyệt; dữ liệu thử History đã được xóa và fingerprint được bảo vệ không đổi. Pinch hai ngón/camera vật lý còn MANUAL PENDING. Không còn yêu cầu cho phép DLL để sử dụng History đã triển khai.
