# Core Verification Sprint 2 — 23/10/2026

## Kết luận

**GIỮ NGUYÊN kiến trúc database hiện hành. GO cho regression và camera VirtualScene + API/SQLite cô lập. SQL Server E2E: WAITING FOR USER APPROVAL.**

Đã đọc Master Plan thực tế `WayMark_Master_Plan_v1.2.md` và `CoreIntegrationSprint1.md`. Đầu sprint chưa có tên chuẩn `WayMark_Master_Plan.md`; đã tạo bản chuẩn v1.3 từ toàn bộ v1.2, giữ nguyên file v1.2. Quyết định mới không tạo SQL database thứ ba thay thế đề xuất E2E database riêng trong các runbook cũ. Không chạy các script provisioning cũ.

## A/B/C — Runtime, Identity và hai database

### Bằng chứng mới, không chỉ dựa báo cáo cũ

- `Program.cs:10,56,69` dùng WebApplication configuration chuẩn, đăng ký database chung và Identity store qua `AuthDbContext`.
- `Data/WayMarkDatabaseRegistration.cs:28–35`: hai context đều đọc `ConnectionStrings:WayMarkDatabase`; SQL Server; history khác nhau. Không có fallback sang WayMarkAuthDatabase.
- Công cụ mới `tools/CoreVerificationAudit` dựng configuration Development bằng ApplicationName của backend (để tải đúng User Secrets), gọi lại E2E safety parsing và chính registration này, resolve context/Identity store. Không start app, migrator, seeder hoặc provider ghi ảnh. Sau đó mở hai connection SQL và chỉ chạy các SELECT cố định (metadata, COUNT, history, backup history). ApplicationIntent=ReadOnly là hint; tính chỉ đọc của công cụ đến từ các command SELECT cố định, không phải tài khoản SQL bị giới hạn.
- Đồng thời đã thực sự chạy `dotnet run --no-build --project WayMark.Api/WayMark.Api.csproj --launch-profile http`: Development, content root đúng `WayMark.Api`, Kestrel `http://localhost:5121`. GET Swagger JSON **200**; GET `/api/admin/map-projects` thiếu JWT **401**. Không đăng nhập, không gọi API ghi trên backend này.
- Runtime DI được resolve trong tiến trình audit riêng bằng cùng registration/configuration; không thêm diagnostic endpoint vào API và không khẳng định đã bắt packet SQL của một request login. HTTP process xác minh startup/status; SQL process riêng xác minh chính database đã cấu hình có thật.
- Effective connection lấy từ `appsettings.json`; không có `ConnectionStrings:WayMarkAuthDatabase`. JWT SecretKey/Issuer/Audience effective lấy từ **User Secrets**, không hiển thị giá trị. Configuration áp dụng base → environment JSON → Development User Secrets → environment variables; launch profile http chỉ chọn Development/URL, không override connection.

| Context / database | Trạng thái xác minh |
|---|---|
| AuthDbContext | SQL Server `.`, default instance; `WayMarkDatabase`, `__AuthMigrationsHistory` |
| WayMarkDbContext (map/graph) | Cùng server/database, `__EFMigrationsHistory` |
| WayMarkDatabase | ONLINE; Identity và graph cùng tồn tại |
| WayMarkAuthDatabase | ONLINE, còn Identity legacy; không được hai context ứng dụng hiện tại tham chiếu |

SQL read-only ngày 23/10, không đọc username/email/hash/token:

| Metadata/count | WayMarkDatabase | WayMarkAuthDatabase |
|---|---:|---:|
| AspNetUsers | 5 | 1 |
| AspNetRoles / AspNetUserRoles | 0 / 0 | 0 / 0 |
| Site / Building / Floor | 1 / 1 / 2 | Không có |
| NavigationNodes / NavigationEdges / WayMarks | 7 / 10 / 3 | Không có |
| Draft, membership, publication tables | Chưa có | Không có |

WayMarkDatabase có 7 bảng AspNet Identity, history Auth `20261010032404_CreateAuthSchema`; history graph chỉ có `20261018022742_CreateWayMarkSchema`, `20261018053754_AddNavigationSchema`. WayMarkAuthDatabase có 7 bảng Identity và history cũ `__EFMigrationsHistory` chứa CreateAuthSchema. Không copy hoặc so sánh dữ liệu định danh cá nhân giữa hai DB.

**Trả lời chính xác:** runtime ứng dụng hiện tại dùng **một SQL database cho cả hai context**. WayMarkAuthDatabase là legacy/dự phòng đối với source hiện tại; không có bằng chứng một app khác có/không sử dụng nó. Hiện trạng phù hợp với báo cáo đã hợp nhất Identity, nhưng metadata này **không chứng minh thời điểm hoặc quá trình chuyển dữ liệu đúng ngày 18/10**. Không cần hợp nhất lại, không tách lại, không xóa DB legacy.

### User → owner và Creator

`AuthController.cs:90–152`: UserManager đọc qua AuthDbContext, password qua Identity; JWT sub/NameIdentifier là IdentityUser.Id, roles lấy từ Identity store. `WayMarkSecurity.cs` kiểm tra issuer/audience/lifetime/signature HS256 và AdminOnly. Không tin role do client gửi.

`MapProjectService.cs:21–36,59–68`: OwnerId lấy từ NameIdentifier đã xác thực; mỗi thao tác private kiểm tra owner + `DraftSiteAccess`. `DraftAccess.cs:26–37` suy ra Site từ Floor→Building→Site và yêu cầu Admin cùng active membership/CanEditDrafts. UserId/OwnerId là liên kết ứng dụng theo IdentityUser.Id; **không có FK Identity trong WayMarkDbContext**, không nhân đôi Identity. Chính sách xử lý owner bị xóa là giới hạn vận hành còn lại.

**Blocker thực tế:** chưa có Admin role/user-role trong DB active; cũng chưa có SiteMapMemberships. Không có Creator được cấp quyền ghi theo cơ chế hiện tại. Không tự cấp role/membership hoặc tạo tài khoản. “Creator” trong slice này vẫn là Admin được ủy quyền, chưa phải onboarding Creator tự phục vụ.

SMTP được đăng ký theo options/User Secrets, không dùng DB riêng. Effective SMTP configuration chưa đủ theo `EmailTestOptions.HasRequiredSettings`; không gửi mail và không sửa SMTP trong sprint này.

## D — Ba migration: review SQL Server, chưa apply

Tất cả thuộc **WayMarkDbContext**, history **__EFMigrationsHistory**, target dự kiến sau phê duyệt là **WayMarkDatabase**, không WayMarkAuthDatabase. AuthDbContext không có migration pending. Cần hai migration graph 18/10 đã nêu trước các migration dưới đây; DB hiện tại đã có chúng.

### 1. 20261020094848_AddMapDraftFoundation

- `FloorMapDrafts`: Guid Id PK, FloorId int FK Floors/unique index; Version bigint >0, Status chỉ Draft; timestamp và CreatedBy/UpdatedBy nvarchar(450).
- `FloorMapImageAssets`: Guid Id PK, FloorId FK Floors, StorageKey nvarchar(64) unique, MIME, Width/Height, ByteLength, SHA256, timestamp/actor. CHECK: PNG/JPEG; width/height 1–8192; tối đa 32 triệu pixel; byte length 1–10 MiB. Index FloorId.
- `SiteMapMemberships`: identity int Id PK; SiteId FK Sites; UserId nvarchar(450); IsActive/CanEditDrafts; unique `(SiteId,UserId)` và index UserId. UserId không FK sang Identity context.
- `FloorMapDraftRevisions`: PK `(DraftId,Version)`; ContentJson nvarchar(max), nullable ImageAssetId FK assets, FK DraftId, timestamp/actor; CHECK Version>0; index ImageAssetId. Room/entrance/Node-first metadata nằm trong validated ContentJson, không thêm Room vào production graph.

### 2. 20261020101304_BindMapImagesToDrafts

- Thêm alternate unique constraint `AK_FloorMapDrafts_FloorId`.
- Thêm FK `FloorMapImageAssets.FloorId → FloorMapDrafts.FloorId`.
- Nếu có image orphan ở môi trường khác, FK sẽ thất bại; phải kiểm tra và xử lý riêng, không xóa tự động. Trên DB đã audit, cả hai bảng này chưa tồn tại.

### 3. 20261023063955_AddPublishedMapProjects

- `MapProjects`: Guid Id PK; LocalProjectId; SiteId/BuildingId FK; OwnerId; Name; Version; ContentJson; UpdatedAt. Unique `(OwnerId,LocalProjectId)`, index SiteId/BuildingId, CHECK Version>0.
- `MapPublications`: PK `(MapId,Version)`, FK MapProjects; immutable name/content/actor/time; CHECK Version>0.
- `MapNodeQrs`: Guid Id PK; MapId FK; FloorKey/NodeId GUID; DraftVersion; nullable PublishedVersion FK `(MapId,PublishedVersion)` → publication; Token unique; active/actor/revocation metadata. Unique filtered `(MapId,DraftVersion,FloorKey,NodeId) WHERE IsActive=1`; index map/publication; CHECK DraftVersion>0 và PublishedVersion null hoặc bằng DraftVersion. IsActive concurrency token là metadata EF, không cột mới.
- `MapPublicationImages`: PK `(MapId,Version,AssetId)`, FK publication + assets, index AssetId.

Toàn bộ FK mới dùng Restrict/SQL `NO ACTION`. Các Guid/string/decimal/bit/JSON text mappings và filtered index được SQL Server provider sinh thành SQL; các PK composite nhỏ. Index membership/owner dài là **nonclustered unique index**, không phải clustered PK 900 byte. Không thêm Identity vào snapshot map.

### Tác động, xung đột và mức bằng chứng

- **Up thêm tổng cộng 8 bảng**, index/check/FK, cùng 2 constraint của migration 2. Không ALTER WayMarks, NavigationNodes/Edges, Sites/Buildings/Floors hoặc Identity; các bảng hierarchy chỉ được FK tham chiếu. Không có UPDATE/DELETE/TRUNCATE/DROP hoặc INSERT dữ liệu nghiệp vụ.
- Có đúng 3 **INSERT vào __EFMigrationsHistory**, đây là ghi lịch sử migration bình thường.
- Read-only sys.tables không thấy tên 8 bảng mới; Id/FK hierarchy hiện có là int đúng mapping. Chưa thấy xung đột ở mức kiểm tra này; không khẳng định đã xác minh mọi schema drift/permission/lock trên SQL Server.
- Down có DROP chính bảng/constraint mới. **Không dùng Down làm rollback mặc định sau khi đã có ảnh/revision/publication**, vì mất dữ liệu mới. Chưa chạy Up hoặc Down.
- Test `MapDraftModelTests` kiểm tra SQL Server model khớp snapshot, sinh SQL và additive checks, filtered index, history; không mở SQL Server. Integration tests ghi dữ liệu dùng SQLite/file storage riêng. Chưa thử thực thi SQL, filtered unique indexes, collation, deadlock/concurrency hoặc SQL Server restart persistence trên DB thật.
- Script EF provider đã sinh offline tại `waymark/build/core-verification-evidence/PendingMapMigrations.review.sql`, từ AddNavigationSchema đến AddPublishedMapProjects. 163 dòng; BEGIN/COMMIT mỗi migration; GO tại dòng 76,87,163. Chưa thực thi. File review không có guard target và **không phải launcher được phê duyệt**; không mở SSMS và chạy tùy ý. Nếu migration 2/3 lỗi, migration trước đã commit có thể vẫn còn; phải đọc history và xử lý từng bước, không tuyên bố cả chuỗi atomically rollback.

**GO cho review source/SQL generator; NO-GO cho tự apply.** Cần backup mới được kiểm chứng, target/permission gate và phê duyệt ghi cụ thể trước SQL E2E.

## E — Camera QR đã thử tới đâu?

### Static và automated

- Package hiện có `mobile_scanner: ^7.4.2`; main AndroidManifest có CAMERA/INTERNET. Release cleartext false; debug manifest bật HTTP development riêng. Không sửa manifest.
- `scanner_page.dart:88,161–202,251,333,396`: Web được ưu tiên đúng, Windows native tách riêng; controller back camera/autoStart false, lifecycle stop/resume/dispose, explicit retry, camera switch có điều kiện, `_lookupStarted` chặn scan lặp trước await.
- Scanner capture được dùng lại trong Visitor và Navigation. PNG được tạo bằng `nodeQrPng`, payload `WMQR1:<64 lowercase hex>`, server random token. Parser nhận payload/URL http(s) `/q/token`, không theo host quét, không gửi JWT tới host đó. GUID node không phải token hoặc nhãn N01/N02.
- Public API client không gửi JWT và không clear AuthSession; map/version/floor/node đều đối chiếu snapshot. 404/409/410/network lỗi không cập nhật vị trí. Navigation tiếp tục xác nhận thủ công, không timer/GPS giả.
- Test bổ sung: burst 8 camera events chỉ gọi resolve một lần; explicit retry; revoked QR không đi tiếp/không mất AuthSession. Backend test đổi name/NodeCode và đảo thứ tự nodes vẫn resolve cùng Node GUID đúng pinned version; không bắt buộc mọi node có QR.

### Camera frames E2E trên Android Emulator — ĐÃ CHẠY

1. AVD Medium_Phone_API_37.0 / emulator-5554 có cấu hình gốc back=webcam0. Chạy với **command-line override tạm** `-camera-back virtualscene -no-snapshot-save`, không sửa config.ini hoặc webcam vật lý.
2. Kestrel fixture 5188, SQLite file + managed image files temp, ký JWT fixture riêng; tạo/lưu/upload/publish qua HTTP fixture như Sprint 1. Không load appsettings/User Secrets/SQL Server trong host fixture.
3. Render PNG bằng **chính hàm Builder** qua opt-in Flutter test; đưa PNG vào `virtualscene-image wall/table`. Chạy app `tool/public_map_visitor.dart` với API 10.0.2.2:5188, **không dart-define payload** và không nhập mã vào field.
4. Nhấn “Quét bằng camera”; `ScannerPage.capture` mở CameraX/ML Kit thực trong Android. Macro SDK `Walk_to_image_room` đưa camera tới poster QR. Scanner tự đọc khung hình, đóng camera, resolve API và mở Search với start Entrance G/Ground.
5. Chọn đích → Preview **13 m**, 2 tầng/0 Room → Navigation → quét lại QR bằng camera tại node hiện tại: giữ Bước 1/4 và hiển thị vòng QR đã đối chiếu → manual bước tiếp theo G→L1 → Bước 4/4 “Đã xác nhận điểm đến”.

Đây là **camera pipeline trên nguồn VirtualScene**; không phải gọi analyzeImage, fake stream hay nhập QR thủ công. Không đồng nghĩa camera điện thoại/Webcam vật lý đã nghiệm thu. Computer Use Windows helper unavailable; chỉ dùng ADB/emulator console/macro SDK cho phần này.

Evidence (Git ignored) tại `waymark/build/core-verification-evidence/`:

- `camera-qr.png`: QR Builder thật của phiên fixture này.
- `android-camera.png`: camera đang mở ở VirtualScene.
- `android-camera-result.png`: Search sau camera scan.
- `android-camera-preview.png`: route 13 m.
- `android-camera-relocalized.png`: node hiện tại đã đối chiếu QR, bước không nhảy.
- `android-camera-level1.png`, `android-camera-arrival.png`.
- `camera-relocalization.mp4`: ghi màn hình lần quét lại QR trong Navigation.

Chưa chạy **camera thật + SQL Server**; chưa thử scan QR revoked bằng VirtualScene (đã có API/automated tests); reroute camera ngoài tuyến cần thêm QR fixture/thiết bị thực. Chưa mở LAN/firewall/HTTPS/public Internet. Ảnh bốn màu là fixture, không phải sơ đồ bệnh viện đã khảo sát.

### Chạy lại camera demo không ghi SQL Server

```powershell
# Terminal 1, repository root: fixture SQLite/file storage, NOT SQL Server
dotnet run --project tools/CoreIntegrationDemo/CoreIntegrationDemo.csproj -- D:\project\WayMark\waymark\build\core-integration-evidence
# Terminal 2, Flutter root
$qr = (Get-Content build/core-integration-evidence/public-qr.txt -Raw).Trim()
flutter test test/core_verification_qr_test.dart "--dart-define=WAYMARK_DEMO_PUBLIC_QR=$qr"
flutter run -d emulator-5554 -t tool/public_map_visitor.dart --dart-define=WAYMARK_API_BASE_URL=http://10.0.2.2:5188/api
```

Trong emulator VirtualScene đã khởi chạy riêng: nạp `camera-qr.png` vào wall/table bằng `adb emu virtualscene-image ...`, mở camera trong WayMark, chạy `adb emu automation play C:/Users/pc/AppData/Local/Android/Sdk/emulator/resources/macros/Walk_to_image_room`. Tool CLI theo SDK máy này; QR phải là phiên host đang sống, không dùng PNG cũ sau khi tái tạo fixture. Không dùng bất kỳ script SQL E2E cũ để chạy demo này.

Android thật: chọn API endpoint LAN/HTTPS đã được chủ máy cho phép; cấu hình URL qua dart-define, không dùng 10.0.2.2 trên điện thoại. Mở PNG QR của cùng server trên màn hình khác/tờ in → Login/Visitor → camera → kiểm tra đúng map/tầng/điểm đầu → Search/Preview/Navigation → quét lại cùng node và thử mã thu hồi. Nếu chưa được phép mở mạng/HTTPS, phần này vẫn chờ; không yêu cầu tắt firewall hoặc bỏ bảo mật.

Tài liệu SDK tham khảo: [Google AR emulator](https://developers.google.com/ar/develop/c/emulator), [Emulator controller proto](https://android.googlesource.com/platform/tools/base/+/refs/heads/mirror-goog-studio-main/emulator/proto/emulator_controller.proto). VirtualScene là nguồn ảnh mô phỏng, được tách rõ khỏi camera vật lý.

## F — Verification và file thay đổi

| Lệnh / mức kiểm thử | Kết quả |
|---|---|
| dotnet build WayMark.Api/WayMark.Api.csproj --no-restore | Đạt, 0 warning/error |
| dotnet test WayMark.Api.Tests/WayMark.Api.Tests.csproj --no-restore | **283/283**; SQLite/fake/temp storage, SQL Server metadata only |
| flutter analyze --no-pub | Không lỗi |
| flutter test --no-pub --reporter expanded | **263 pass, 1 Web-only skip** |
| Opt-in QR evidence test | 2 pass (burst regression + PNG render) |
| flutter build apk --debug | Đạt, main.dart; Gradle Java native-access warning hiện hữu |
| git diff --check | Đạt; warning LF/CRLF hiện hữu |
| Actual SQL Server | SELECT-only audit, không persistence E2E |
| Emulator manual | Camera VirtualScene → public API → Navigation/QR current node → Arrival đạt |

File mới/sửa **riêng sprint này**, ngoài toàn bộ dirty work có sẵn:

1. `tools/CoreVerificationAudit/CoreVerificationAudit.csproj` — tái sử dụng backend assembly, không thêm package production.
2. `tools/CoreVerificationAudit/Program.cs` — runtime DI/config audit an toàn, SELECT metadata/count, EF SQL generation offline.
3. `WayMark.Api.Tests/PublishedMapTests.cs` — thêm test stable node/QR/version, không sửa test cũ.
4. `waymark/test/core_verification_qr_test.dart` — burst/retry/revoked/AuthSession + opt-in export PNG camera fixture.
5. `docs/CoreVerificationSprint2.md`.
6. `docs/WayMark_Master_Plan.md` — v1.3, giữ v1.2 nguyên trạng.

Không phát hiện mắt xích production còn thiếu cần viết lại; không sửa app/backend business source, migration, connection/JWT, AI hoặc Zoom/Pan trong sprint này. SHA256 so với baseline trước xác nhận Gradle, ba Windows generated, AI provider/page không đổi. Không reset/clean/commit/push. Evidence/logs/build artifacts ở thư mục build ignored, không chứa JWT hoặc credentials.

Đã cài lại APK **main.dart** bằng `adb install -r` và mở màn hình Login trên emulator, không clear app data. Hai API do sprint tự mở (5121/5188) đã dừng; QR fixture cũ không còn là link server đang hoạt động. Emulator hiện còn command-line override VirtualScene của phiên kiểm thử; mở lại AVD bình thường không có override sẽ dùng cấu hình webcam0 cũ, config.ini không bị sửa. Ảnh `android-main-restored.png` xác nhận app chính đã được mở lại.

## G/H — Approval gate và P0 tiếp theo nhỏ nhất

**Không tạo SQL database thứ ba. Không dùng launcher MapDraftE2E cũ để thử trên WayMarkDatabase:** profile/factory/interceptor cũ cố ý pin `WayMark_MapDraft_E2E_Test`, từ chối DB được bảo vệ và Windows sysadmin. Giữ nguyên guard; không lách bằng `dotnet ef --connection` hoặc đổi tên environment. Migration preview ở trên dùng provider offline, không factory/connection.

Blocker trước SQL E2E trên DB hiện hữu:

- 3 migrations chưa apply; Admin role/membership chưa được cấp.
- Effective managed image storage **Enabled=false, RootPath chưa cấu hình**; upload trả 503 cho tới khi được cấu hình root riêng ngoài repo và ACL/quota/backup được duyệt.
- Runtime Windows principal có **sysadmin**; cần kế hoạch quyền tối thiểu trước vận hành thật. Không tự thay credentials/SQL grants.
- msdb có full backup history WayMarkDatabase **18/10 16:47:31**, WayMarkAuthDatabase **18/10 11:00:08** (thời gian SQL lưu). Chưa xác minh file/restore của các backup này và đã cũ so với sprint; **không coi là backup hiện tại đã nghiệm thu**.

Thứ tự **đề xuất, CHƯA ĐƯỢC THỰC HIỆN**:

| Bước chờ duyệt | Target/tác động | Xác minh / khi lỗi |
|---|---|---|
| 1. Backup đầy đủ và verify/restore rehearsal theo lịch được duyệt | Hai DB hiện hữu + backup files; backup có thể ghi msdb, nên cũng cần duyệt | Chốt tên file/đường dẫn/khả năng phục hồi; không tiếp tục nếu thiếu |
| 2. Dừng API ghi trong cửa sổ bảo trì; kiểm tra instance, DB_NAME, histories và schema lại | Chỉ WayMarkDatabase là target schema | Nếu khác audit hoặc object trùng tên: dừng, không drop hoặc đánh dấu history giả |
| 3. Review/duyệt script SQL EF đã sinh, bọc target guard và dùng executor fail-on-error | WayMarkDatabase, 8 bảng mới + constraints/index/FK + 3 history rows | Chỉ apply sau phê duyệt đích danh 3 migration. Không apply Auth hoặc WayMarkAuthDatabase. Không dùng launcher tạo DB test cũ |
| 4. Chuẩn bị runtime permissions và storage root/ACL/quota | SQL grants/local config/filesystem ngoài repo, phạm vi phải duyệt riêng | Không runtime sysadmin; upload fail không đổi local. Không sửa User Secrets/JWT hiện hành trong sprint này |
| 5. Chọn tài khoản Creator A/B và hierarchy demo hiện có | Admin role, user-role, SiteMapMembership cho đúng tài khoản do người dùng chọn | Dùng Identity APIs/approved bootstrap, không hardcode password/hash, không tự nâng user theo tên admin. Có thể duyệt A trước, B sau cho ownership negative test |
| 6. Chạy Save/Load/upload/restart/publish/QR/Guest/403 trên SQL Server | Chỉ bản ghi test có namespace trong các bảng mới + file ảnh quản lý; không seed/chỉnh NavigationNodes/Edges/WayMarks cũ | Đối chiếu trước/sau graph cũ, pin version/GUID; lỗi giữ local, không cleanup SQL tự động |
| 7. Camera trên cùng API SQL đã duyệt | Emulator VirtualScene hoặc điện thoại có mạng được duyệt | PNG mới → camera → resolve → Search → route; mã revoked phải không đổi vị trí |

Sau bước 3, xác nhận đủ 5 migration graph trong __EFMigrationsHistory, Auth history vẫn 1; không chỉ dựa thông báo SQL success. Khi lỗi: dừng API ghi, lưu error/history, không chạy Down/DELETE; chọn forward fix hoặc restore đầy đủ SQL + ảnh theo phương án phục hồi **được duyệt riêng**. Nếu migrations trước đã commit, chúng vẫn phải được tính trong kế hoạch khôi phục.

**Phê duyệt riêng cần có:** backup/verification; áp dụng 3 migration trên WayMarkDatabase; cấu hình/quyền runtime và storage; tài khoản/role/membership cụ thể; các API test ghi dữ liệu mới/publish; phương án restore nếu cần. WayMarkAuthDatabase tiếp tục giữ nguyên, không merge/drop/tách.

SQL E2E tiếp tục **WAITING FOR USER APPROVAL**. Sprint này không thực thi bất kỳ bước ghi nào ở bảng kế hoạch trên.
