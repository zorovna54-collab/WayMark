# Phase 7B-2D-1 — SQL Server Integration Preflight

Ngày kiểm tra: **2026-10-20**. Repository: `D:\project\WayMark`.
Branch và HEAD xác nhận: `auth-jwt-assignment`,
`631a76cd196460318429ebff8da394818ccbdd2d`.

## 1. Kết luận

**NO-GO để bắt đầu thao tác database hoặc nghiệm thu SQL Server ở 7B-2D-2.**
Preflight đã hoàn thành; không tạo database, chạy migration, seed, cấp quyền,
thay đổi secrets hoặc khởi chạy API thật. Chỉ tạo báo cáo này và các artifact
kiểm tra tạm bị Git ignore. Không sửa source ứng dụng hoặc migration.

Các điểm chặn phải được xử lý trong một nhiệm vụ được phê duyệt riêng:

| Mức | Phát hiện và bằng chứng | Việc cần làm trước khi ghi dữ liệu test |
| --- | --- | --- |
| High | Chỉ đổi environment thành `MapDraftE2E` vẫn lấy database `WayMarkDatabase` từ `appsettings.json`; chưa có guard tên database/server. Tài khoản Windows của phiên kiểm tra là SQL sysadmin. | Thêm launcher + startup/bootstrap guard fail-closed; dùng principal SQL chỉ có quyền trên database test. Không dùng Windows sysadmin làm runtime E2E. |
| High | `dotnet test` không biên dịch: CS0535 tại `WayMark.Api.Tests/AdminAuthorizationTests.cs:340`; `CountingEmail` thiếu `SendPasswordResetEmailAsync` vừa được thêm vào interface. | Cập nhật fake email không gửi mạng, chạy lại toàn bộ backend tests. Chưa biết có lỗi tiếp theo sau khi sửa lỗi compile này; không dùng kết quả 212 cũ để thay thế. |
| High | `WayMark.Api/appsettings.json:7` có JWT key literal Base64 hợp lệ 32 byte, khác HEAD. Custom E2E environment sẽ dùng literal đó nếu không override. | Chủ sở hữu xác định đây là key thật hay mẫu; tách cấu hình nhạy cảm khỏi file được Git theo dõi bằng nhiệm vụ riêng. E2E phải có key mới độc lập. Không hiển thị key/hashes; không kết luận key production đã bị lộ khi chưa có bằng chứng. Rotate riêng nếu đã sử dụng/chia sẻ ngoài phạm vi cho phép. |
| Medium | Không có `appsettings.MapDraftE2E.json`, storage đang disabled, chưa có root riêng; Swagger/CORS chỉ bật trong Development. | Cấu hình private storage, quotas và CORS/Swagger chỉ cho environment E2E loopback. Không đổi sang Development chỉ để vượt qua thiếu cấu hình. |
| Medium | Chưa có CLI/bootstrap test-only và account/membership test được cấp có kiểm soát. | Thiết kế/duyệt bootstrap và dữ liệu giả; mọi cấp quyền chỉ trong DB test, không tự cấp khi đăng nhập. |
| Medium | Flutter bảo toàn Room/Place nhưng chưa có công cụ tạo/sửa Room trong UI. | Checklist phải dùng fixture JSON v2 có kiểm soát để tạo Room/entrance, không tuyên bố thao tác này đã có trên canvas. |
| Medium | SQL đọc thực tế cho thấy READ_COMMITTED_SNAPSHOT **ON** ở cả hai DB hiện hữu, khác lựa chọn OFF đã nêu trước đây. | Ghi nhận drift và chốt chế độ cho DB test trước khi tạo. Không tự ALTER hai DB hiện hữu. Optimistic concurrency vẫn phải kiểm thử trên SQL Server thực tế. |

## 2. Workspace và phạm vi audit

Lúc bắt đầu có **18 tracked files modified**, **83 untracked files**:

| Nhóm untracked | Số file |
| --- | ---: |
| Application source | 20 |
| Tests / fixtures | 10 |
| Migration + designer đang pending | 4 |
| Báo cáo 7B-2A/2B/2C | 3 |
| Figma reference | 45 |
| `.kilo` local planning | 1 |

Các tracked modifications hiện hữu:

```text
WayMark.Api.Tests/AdminAuthorizationTests.cs
WayMark.Api.Tests/WayMark.Api.Tests.csproj
WayMark.Api/Controllers/AuthController.cs
WayMark.Api/Data/AuthRequests.cs
WayMark.Api/Data/WayMarkDbContext.cs
WayMark.Api/Data/WayMarkMigrations/WayMarkDbContextModelSnapshot.cs
WayMark.Api/Program.cs
WayMark.Api/Services/ISmtpEmailService.cs
WayMark.Api/Services/SmtpEmailService.cs
WayMark.Api/WayMark.Api.csproj
WayMark.Api/appsettings.json
waymark/android/gradle.properties
waymark/lib/features/admin/draft_map.dart
waymark/lib/features/admin/draft_map_editor.dart
waymark/lib/features/auth/login/login_page.dart
waymark/lib/features/auth/register/register_page.dart
waymark/lib/services/auth_api_service.dart
waymark/test/draft_floor_workflow_test.dart
```

Ngoài các phase map, có thay đổi quên mật khẩu/email/đăng ký/đăng nhập và
appsettings đang dở. Đây là trạng thái workspace được kiểm tra, không phải các
thay đổi do preflight tạo. Không reset/restore/clean/stash hoặc stage chúng.

Đã đọc ba báo cáo trước, Program, hai DbContext, model/mapping/snapshot,
hai migration và designer, DTO/controller/service/validator/access/storage,
security registration, cấu hình có che giá trị nhạy cảm, Flutter API client,
mapper/session/editor và test hosts liên quan.

So sánh với HEAD cho routing service, RoutesController/DTO, MapsController,
WayMarksController, NavigationNode/NavigationEdge không có diff. Thay đổi
WayMarkDbContext chỉ thêm DbSet/cấu hình draft, giữ mapping graph/QR hiện hữu.
`MapDraftService` chỉ ghi draft/revision/image; không có publish hoặc cập nhật
NavigationNodes/NavigationEdges/WayMarks. Đọc source không thay thế nghiệm thu
SQL thực tế; số lượng row không phải bằng chứng đầy đủ rằng nội dung bất biến.

## 3. SQL Server và cấu hình thực tế — bằng chứng chỉ đọc

### 3.1 Cách xác minh

Dùng một console probe tạm trong
`waymark/.dart_tool/phase7b2d1/probe/`:

- Dựng `WebApplicationBuilder` với content root/application assembly của API,
  để đọc cấu hình Development và custom E2E; **không Build/Run application**.
- Không gọi Program của API, đăng ký Identity/storage, startup migration hay seed.
- Chỉ in tên nguồn cấu hình, server/catalog và boolean về credential/key; không
  in connection string, password, JWT key, user secrets hoặc reset token.
- Dùng SQL provider metadata để kiểm tra snapshot và sinh SQL trong bộ nhớ.
- Mở đúng kết nối hiệu lực Development; chỉ SELECT metadata/history/counts,
  timeout ngắn. Không thử fallback hoặc kết nối riêng vào WayMarkAuthDatabase.
- `ApplicationIntent=ReadOnly` được dùng cho probe, nhưng **không phải chốt
  cấm ghi trên primary**. Bảo đảm của lần kiểm tra này là toàn bộ lệnh thực thi
  chỉ SELECT. Không dựa vào ApplicationIntent để bảo vệ E2E sau này.

Artifact đã được che giá trị:
`waymark/.dart_tool/phase7b2d1/config-sql-readonly.json` (ignored).
Không có API/Kestrel hay SMTP thật được khởi chạy.

### 3.2 Kết quả kết nối

| Mục | Xác nhận |
| --- | --- |
| SQL service | `MSSQLSERVER` đang Running |
| DataSource cấu hình | `.` — instance mặc định trên máy hiện tại |
| SQL metadata | InstanceName = NULL; ProductVersion = `16.0.1000.6` (SQL Server 2022 theo môi trường đã cung cấp) |
| DB_NAME qua kết nối hiệu lực | **WayMarkDatabase** |
| Authentication | Windows Integrated; không có User ID/password trong connection được chọn |
| Transport hiện tại | Encrypt=True, TrustServerCertificate=True; ghi nhận cấu hình, không thay đổi |
| Quyền caller | `IS_SRVROLEMEMBER('sysadmin') = 1`; không thích hợp làm principal E2E runtime |
| WayMarkDatabase | ONLINE; READ_COMMITTED_SNAPSHOT ON |
| WayMarkAuthDatabase | ONLINE; READ_COMMITTED_SNAPSHOT ON; ứng dụng không chọn database này |
| WayMark_MapDraft_E2E_Test | Chưa tồn tại trong `sys.databases`; caller sysadmin có quyền thấy danh sách đầy đủ |

Các bảng published hiện có: Sites=1, Buildings=1, Floors=2,
NavigationNodes=7, NavigationEdges=10, WayMarks=3. Không đọc/hiển thị thông tin
người dùng Identity hoặc dữ liệu cá nhân. Nội dung riêng của database cũ
WayMarkAuthDatabase không được mở/kiểm kê trong preflight này.

Không thấy listener trên 5121, 7199, 7627, 5628 tại thời điểm kiểm tra. Đây không
phải cam kết các cổng sẽ luôn trống. Dev HTTPS certificate hợp lệ; chưa xác minh
Chrome tin cậy certificate và không chạy thao tác trust/cài certificate.

### 3.3 Hai DbContext và configuration precedence

| Context | Provider | Connection key | History |
| --- | --- | --- | --- |
| AuthDbContext | Microsoft.EntityFrameworkCore.SqlServer | `ConnectionStrings:WayMarkDatabase` | `dbo.__AuthMigrationsHistory` |
| WayMarkDbContext | Microsoft.EntityFrameworkCore.SqlServer | cùng key trên | `dbo.__EFMigrationsHistory` |

Bằng chứng: `WayMark.Api/Program.cs:51`, `:56`; AuthDbContext kế thừa
IdentityDbContext, WayMarkDbContext không chứa Identity entities.

`WebApplication.CreateBuilder(args)` dùng cấu hình mặc định: appsettings chung,
file environment nếu có, User Secrets trong Development, environment variables
và command-line overrides. Với các app keys, nguồn về sau có thể ghi đè nguồn
trước. Host environment cũng phụ thuộc cách launch/CLI; phải kiểm tra tiến trình
E2E tương lai, không suy ra từ file launchSettings duy nhất.

Kết quả probe hiện tại:

| Key/nhóm | Development | MapDraftE2E nếu chỉ đổi tên environment |
| --- | --- | --- |
| WayMarkDatabase connection | appsettings.json → WayMarkDatabase | **cũng appsettings.json → WayMarkDatabase** |
| WayMarkAuthDatabase connection key | Không có | Không có |
| Jwt SecretKey/Issuer/Audience | User Secrets (`secrets.json`) | appsettings.json |
| JWT key | Có, Base64 hợp lệ 32 byte; khác literal trong appsettings | Có literal Base64 hợp lệ 32 byte trong file tracked |
| MapImages.Enabled / RootPath | Chưa cung cấp → disabled / null | như Development |
| appsettings.Development.json | Không tồn tại | không áp dụng |
| appsettings.MapDraftE2E.json | không áp dụng | Không tồn tại |

Không thấy environment override liên quan DB/JWT/storage trong shell của lần
kiểm tra. Đây là cấu hình của probe theo hai profile; không khẳng định biết
environment/CLI arguments của một tiến trình API khác đã chạy trước đó.

Không có fallback `WayMarkAuthDatabase` trong đăng ký DbContext, không có
design-time factory đổi database/provider, không thấy startup EnsureCreated,
Migrate hoặc seed trong API. Tuy nhiên **fallback cấu hình chung sang
WayMarkDatabase trong E2E là có thật** và hiện chưa bị chặn. Chỉ tạo file cấu
hình môi trường mà thiếu override cũng chưa đủ an toàn.

## 4. Migration status và review

### 4.1 Đối chiếu source với history đọc trực tiếp

| Context / migration | SQL Server WayMarkDatabase |
| --- | --- |
| Auth: `20261010032404_CreateAuthSchema` | Đã có trong __AuthMigrationsHistory |
| WayMark: `20261018022742_CreateWayMarkSchema` | Đã có trong __EFMigrationsHistory |
| WayMark: `20261018053754_AddNavigationSchema` | Đã có trong __EFMigrationsHistory |
| WayMark: `20261020094848_AddMapDraftFoundation` | **Pending** |
| WayMark: `20261020101304_BindMapImagesToDrafts` | **Pending** |

Hai history table đọc được đều ghi EF `10.0.12`. Bốn bảng draft/membership chưa
tồn tại trong database hiện tại. Không có schema/history mismatch thấy được
cho hai migration mới. `HasPendingModelChanges()` = false cho cả hai context:
source model khớp snapshot, **không có nghĩa database đã áp dụng migration**.

### 4.2 AddMapDraftFoundation — Up

| Bảng | Cột và khóa chính | FK / index / constraint |
| --- | --- | --- |
| FloorMapDrafts | Id uniqueidentifier PK; FloorId int; Version bigint; Status nvarchar(20); CreatedAt/UpdatedAt datetimeoffset; CreatedBy/UpdatedBy nvarchar(450), tất cả NOT NULL | FloorId → Floors.Id Restrict; UNIQUE IX_FloorMapDrafts_FloorId; Version>0; Status='Draft' |
| FloorMapImageAssets | Id uniqueidentifier PK; FloorId int; StorageKey nvarchar(64); MimeType nvarchar(20); Width/Height int; ByteLength bigint; Sha256 nvarchar(64); CreatedAt datetimeoffset; CreatedBy nvarchar(450), tất cả NOT NULL | FloorId → Floors.Id Restrict; index FloorId; UNIQUE StorageKey; mỗi chiều 1..8192; pixels≤32,000,000 dùng CAST bigint; bytes 1..10,485,760; MIME PNG/JPEG |
| SiteMapMemberships | Id int IDENTITY(1,1) PK; SiteId int; UserId nvarchar(450); IsActive/CanEditDrafts bit, tất cả NOT NULL | SiteId → Sites.Id Restrict; UNIQUE(SiteId,UserId); index UserId |
| FloorMapDraftRevisions | PK(DraftId uniqueidentifier,Version bigint); ContentJson nvarchar(max); CreatedAt datetimeoffset; CreatedBy nvarchar(450) NOT NULL; **ImageAssetId uniqueidentifier NULL** | DraftId → FloorMapDrafts.Id Restrict; ImageAssetId → FloorMapImageAssets.Id Restrict; index ImageAssetId; Version>0 |

Ngoài IDENTITY của membership, không có default constraints SQL cho các cột này.
GUID/timestamps/version được service cấp; Status='Draft' là initializer/service
rule và check constraint, không phải SQL DEFAULT. Boolean membership mặc định
false ở CLR; bootstrap phải thiết lập có chủ đích, không giả định SQL tự cấp quyền.

UserId/CreatedBy/UpdatedBy là logical references tới Identity, không có FK qua
AuthDbContext. Bootstrap phải dùng UserManager xác minh user tồn tại. Thiết kế
PK membership int tránh PK rộng; unique scope index là index riêng.

### 4.3 BindMapImagesToDrafts — Up

- Thêm `AK_FloorMapDrafts_FloorId` UNIQUE constraint.
- Thêm `FK_FloorMapImageAssets_FloorMapDrafts_FloorId`:
  ImageAsset.FloorId → Draft.FloorId, Restrict.
- Bảo đảm ảnh thuộc một floor có draft; upload yêu cầu tạo draft trước.
- UNIQUE index FloorId và alternate key cùng tồn tại: có chi phí index trùng
  chức năng, nhưng không gây thay đổi dữ liệu/graph. Không sửa migration vì việc
  tối ưu này trong preflight.
- Nếu từng có image metadata không có draft thì FK phải thất bại, không tự xóa
  dữ liệu để vượt qua. Trên DB hiện tại chưa có bốn bảng mới; DB test mới phải
  áp dụng chuỗi đúng thứ tự trước khi seed.

Tất cả FK mới dùng Restrict (SQL NO ACTION), tránh cascade xóa graph/draft và
multiple cascade paths. Revision không được sửa qua API; restore tạo revision
mới. Đây là tính bất biến do service/API, không phải trigger chống mọi SQL UPDATE
của một DBA có quyền.

### 4.4 Room/Place, entrance và dữ liệu không nằm trong DDL

Room/Place/entrance/nodes/edges/transitions của draft nằm trong ContentJson của
revision, không có bảng published Room hoặc PlaceEntrances mới. Validator kiểm
tra GUID, normalized X/Y, type, khoảng cách mét, hướng cạnh, một/nhiều Entrance
nodes, label/polygon và Unknown safety. Label/tâm phòng không phải route target.
Chuyển tầng pin target draft/version/node cùng Site; không tự nối xuyên tường
hoặc cập nhật routing graph. JSON references và quan hệ ảnh cùng floor được
service kiểm tra, không phải tất cả đều có SQL FK/ISJSON constraint riêng.

Metadata SQL Server provider và forward script sinh **trong bộ nhớ** xác nhận:

- Hai Up additive; tạo 4 bảng và ALTER/constraint chỉ trên bảng draft mới.
- Không DROP/TRUNCATE, không ALTER WayMarks hoặc production graph/Identity.
- Không business INSERT/UPDATE/DELETE, không seed.
- Có đúng **2 INSERT __EFMigrationsHistory** bình thường của EF.
- Chưa thực thi DDL trên SQL Server, nên chưa gọi đây là kiểm thử migration SQL
  thành công. Nghiệm thu đó chỉ được thực hiện trên DB test sau phê duyệt.

Down của foundation DROP 4 bảng mới; Down của binding bỏ FK/alternate key.
Không chạy Down hoặc dùng rollback migration làm cách dọn E2E tự động.

## 5. Flutter ↔ backend contract và các giới hạn

Đã đối chiếu `MapDraftDtos.cs`, `MapDraftsController.cs`,
`map_draft_api_service.dart`, `draft_server_session.dart`:

| Luồng | Contract tương thích |
| --- | --- |
| Metadata/create | GET/POST `/api/admin/floors/{floorId}/map-drafts`; POST content schemaVersion=1 → metadata GUID/Version/Status='Draft' |
| Save | PUT `/{draftId}` với expectedVersion/content; Version bigint được Dart kiểm tra trong miền số nguyên an toàn |
| Graph | GET `/{draftId}/graph?version=N`; client kiểm tra draft/floor/version/status trước khi thay local |
| Ảnh | POST `/images` raw bytes MIME PNG/JPEG, không multipart/Base64; GET `/images/{assetId}` có Bearer rồi decode vào MemoryImage |
| Lịch sử/restore | GET `/{id}/versions?take=50&beforeVersion=N`; POST `/{id}/restore` với expectedVersion/sourceVersion |
| Recovery | GET `/images?page=N&take=100` metadata scoped; download + xác nhận ảnh trước khi dùng |
| Errors | 400/401/403/404/409/413/503; chỉ `draft_version_conflict` được xem là version conflict; quota không phải quyền overwrite |
| Mapping | Local JSON v2 nhúng ảnh/code refs → server v1 GUID refs/imageAssetId; SourceNodeId/ExistingWayMarkCode chỉ provenance |

Enum string, nullable image/distance, Room label/polygon/Entrance GUIDs và pinned
transitions được bảo toàn; không thấy mismatch tên field/method/shape hiện tại.
DTO không cho client khai báo ownership tùy ý. Request dùng AuthSession hiện có
và chung WAYMARK_API_BASE_URL, không thêm luồng xác thực khác.

Save mới có ảnh: tạo owner draft chưa có ảnh → upload → append revision gắn asset.
Upload thành công/save lỗi giữ pending asset; retry không upload lại ảnh giống
nhau trong session. Upload chưa rõ kết quả yêu cầu recovery, không tự xóa asset.
Load lỗi giữ nguyên local; restore thành công nhưng download lỗi thông báo cần
Reload. Không claim lỗi mạng chứng minh server chưa commit.

Room/Place hiện được giữ và hiển thị read-only, không có Room drawing editor.
Chỉ có Preview Route cục bộ, chưa có routing tới Room hoặc publish. AuthSession
vẫn là bộ nhớ: reload Chrome cần đăng nhập lại, rồi chọn tầng/Load; đây không
phải mất draft đã lưu server. Nội dung chưa lưu vẫn cần export trước khi reload/
đóng tab; beforeunload là cảnh báo best-effort do browser quyết định.

## 6. Thiết kế môi trường E2E riêng — chưa tạo

| Thành phần | Đề xuất |
| --- | --- |
| Environment | `MapDraftE2E`, launcher dùng --no-launch-profile; không kế thừa Development User Secrets |
| SQL instance | Instance local được operator allowlist và kiểm tra SERVERPROPERTY thực tế; có thể cùng SQL service nhưng DB/principal tách biệt |
| Database duy nhất cho hai context test | **WayMark_MapDraft_E2E_Test**, tuyệt đối không WayMarkDatabase/WayMarkAuthDatabase |
| SQL principals | Operator riêng tạo DB; migrator có DDL trong DB test; runtime/bootstrap dùng quyền tối thiểu, không sysadmin, không quyền trên hai DB bảo vệ |
| Identity | Users/roles/token trong DB test; UserManager/RoleManager như production, không copy AspNetUsers từ DB thật |
| JWT | Key mới Base64 ≥32 random bytes, issuer `waymark-mapdraft-e2e`, audience `waymark-mapdraft-e2e-web`, nằm trong cấu hình riêng ngoài Git; không dùng key hiện tại |
| API | Đề xuất `https://localhost:7627`; xác minh certificate trust trước khi thử Chrome |
| Flutter Web | `http://localhost:5628`; define API base đúng `https://localhost:7627/api` |
| CORS | Exact origin trên chỉ trong E2E; không AllowAnyOrigin, không bỏ JWT/AdminOnly/membership |
| Image root | `%LOCALAPPDATA%\WayMark\MapDraftE2E\WayMark_MapDraft_E2E_Test\images`; ngoài repo/wwwroot và khác root development; không tạo ở preflight |
| Email | Không dùng SMTP/User Secrets thật. Đề xuất adapter test-only không gửi mạng trong E2E, hoặc fail-closed không có SMTP credentials; không thực hiện trong preflight |
| RCSI | Chốt rõ trước tạo DB. Đề xuất profile đầu tiên ON để kiểm thử concurrency như trạng thái hiện tại; nếu chọn OFF thì chỉ thay DB test sau phê duyệt. Không chỉnh DB thật |

Giới hạn image provider giữ nguyên: PNG/JPG ≤10 MiB input/output, mỗi chiều
≤8192 và ≤32 MP; decode/re-encode; checksum trên **bytes chuẩn hóa** có thể khác
file gốc. Root private, opaque server keys, no public/static URL. Cấu hình quota
E2E đề xuất: 128 MiB root, 50 objects, 20 revisions/floor, 8 images/floor,
32 MiB images/floor. Quota thấp để có thể thử conflict có kiểm soát; không áp
dụng sang môi trường hiện hữu. Không tự purge ảnh/revision.

### 6.1 Guard tối thiểu cần triển khai và kiểm thử trước

Hiện **chưa có** các guard dưới đây; không coi bảng cấu hình đề xuất là đã an toàn:

1. Launcher chỉ nhận environment MapDraftE2E, yêu cầu connection/JWT/storage từ
   nguồn riêng rõ ràng, không fallback. Chặn launch profile Development và config
   thiếu. Truyền environment như argument rõ ràng cho cả API và EF tools.
2. Startup guard trước khi ứng dụng nhận request: parse SQL connection bằng
   SqlConnectionStringBuilder; catalog phải khớp chính xác tên test, server nằm
   trong allowlist; cấm AttachDbFilename/failover/catalog hai DB bảo vệ. Thiếu
   cấu hình thì dừng, không mở connection dựa trên appsettings chung.
3. Kiểm tra chỉ đọc server thực/DB_NAME sau connect, đối chiếu với profile được
   duyệt; runtime SQL login không được là sysadmin. Nếu profile dùng nhầm DB thì
   SQL principal cũng phải bị từ chối kết nối/ghi.
4. Kiểm tra JWT issuer/audience riêng, không nhận giá trị mặc định hoặc secret từ
   tracked appsettings. Không log secret/full connection. Không sửa key môi trường
   hiện có. Root phải chính xác root E2E được duyệt, khác development, private ACL,
   không Git/wwwroot/symlink; DB+root có manifest pairing bên ngoài Git.
5. Cùng guard cho migrator/bootstrap/reset tool; mọi script sau này kiểm tra
   DB_NAME và server trước khi ghi. Không có auto migration/auto seed startup.
6. Bổ sung negative tests cho thiếu config, typo/mismatched catalog, hai tên DB
   bảo vệ, sai server, sysadmin runtime, sai root/JWT scope; dừng trước ghi dữ liệu.
7. Cho CORS/Swagger hoạt động có giới hạn trong custom E2E environment. Chỉ
   Development hiện tại không đáp ứng custom environment. Giữ registration
   authentication/production routing hiện có.

Thay đổi source tối thiểu dự kiến (cần duyệt): startup/launcher guard, nhánh
CORS/Swagger E2E và cấu hình ngoài Git; tool bootstrap test-only dùng shared guard;
cập nhật fake email + tests. Không cần entity/migration mới cho việc tách E2E.

### 6.2 Chuỗi schema khi tạo database test rỗng

Database test rỗng cần **cả chuỗi**, không chỉ hai migration cuối:

1. AuthDbContext → `20261010032404_CreateAuthSchema`, history riêng.
2. WayMarkDbContext → `20261018022742_CreateWayMarkSchema`.
3. WayMarkDbContext → `20261018053754_AddNavigationSchema`.
4. WayMarkDbContext → `20261020094848_AddMapDraftFoundation`.
5. WayMarkDbContext → `20261020101304_BindMapImagesToDrafts`.

Không cần copy/restore database thật vào test. Xác minh history + FK/check/index
trong test, snapshot match và không Identity trong WayMark model. Operator chỉ
được áp dụng sau khi review SQL/guard/quyền và phê duyệt tạo DB test.

## 7. Bootstrap và dữ liệu test — kế hoạch, chưa chạy

Tool test-only (chưa tồn tại) phải kiểm tra guard ở trên trước mỗi giai đoạn,
idempotent theo code/UserId đã xác minh và không tự sửa dữ liệu xung đột:

1. Tạo Site A và Site B giả với namespace `E2E-7B2D-*`; Building A/B, hai Floor
   của A và một Floor B để kiểm thử đổi tầng/truy cập chéo Site. Tra ID theo code,
   không giả định ID 1/2 hoặc dùng bản ghi demo của DB thật.
2. Tạo các tài khoản test mới bằng UserManager với password riêng ngoài Git:
   ordinary reader, Admin A, Admin B, Admin không membership. Email dùng domain
   example.invalid; không gọi SMTP hoặc forgot/reset password trong bootstrap.
3. RoleManager tạo role Admin **chỉ trong DB test** nếu chưa có. Cấp role cho đúng
   UserId test được operator duyệt; không dựa vào username `admin`, không mở grant
   API, không grant trong login/register. Server sẽ phát role claim sau login.
4. WayMarkDbContext cấp membership A/B cho đúng UserId theo scope được duyệt,
   IsActive/CanEditDrafts explicit. Thêm inactive/no-edit fixtures nếu cần.
   Role Admin một mình không đủ quyền. Không gán membership cho người dùng thật.
5. Có thể tạo published baseline giả nhỏ trong DB test cho kiểm tra bất biến và
   SourceNodeId/QR provenance. Ghi nhận sorted IDs/fields/hash trước/sau; dữ liệu
   này không được chép vào WayMarkDatabase. Không cần hardcode tuyến demo 40 m.
6. Chuẩn bị JSON v2 synthetic cùng ảnh không có PHI: 2 Entrance nodes, junction,
   elevator, cạnh có hướng đo theo fixture, Room với một/nhiều Entrance GUID.
   Floor metadata phải lấy từ DB test. Chuyển tầng pin draft/version tầng còn lại
   sau khi draft đó đã có, không nối tùy ý vào node production.

Hai context không tự chia sẻ một SQL transaction chỉ vì cùng connection string.
Tool tương lai phải thiết kế atomicity hoặc các bước idempotent/kiểm tra sau lỗi
có chủ đích. Nếu role/user được tạo nhưng membership chưa xong thì draft access
vẫn bị từ chối; không báo bootstrap hoàn tất. Dừng trước xung đột và yêu cầu review.

## 8. Backup, restart, restore và reset test

- Không xóa dữ liệu test theo timer/startup. Một DB test dùng một root ổn định;
  restart API phải giữ nguyên cả hai.
- Dừng writer test, chụp cặp backup SQL test + toàn bộ objects `.bin`/`.json`
  (gồm ảnh revision cũ, pending/reconciliation); lưu manifest pairing/checksum
  ngoài Git với quyền hạn chế. Không chỉ backup ảnh current head.
- Restore cặp vào môi trường test được allowlist; kiểm tra mọi image reference,
  metadata/hash và download trước mở writer. Không xóa asset missing để làm test
  qua. Chưa có backup/restore thực tế nào được kiểm chứng ở sprint này.
- Recreate chỉ là phương án operator: cần phê duyệt riêng để DROP/recreate **DB
  test đúng tên/server** và root test có owner manifest. Không dùng EnsureDeleted,
  reset/clean repository, xóa computed path mù quáng hoặc migration Down tự động.
- Nếu chỉ cần chạy lại fixture, không overwrite đồ thị đã chỉnh; dùng fresh run
  namespace hoặc restore baseline test đã duyệt. Hai DB hiện hữu tuyệt đối không
  tham gia quy trình backup/recreate E2E này.

## 9. Checklist E2E thực tế — tất cả CHƯA CHẠY

Chỉ bắt đầu khi blockers/guard/schema/bootstrap được duyệt và hoàn tất trên DB
test. Thu Network HTTP status, expected/actual version, JSON graph và checksum
ảnh chuẩn hóa; không chụp token/credentials/PHI trong screenshot hoặc logs.

| # | Thao tác | Kết quả và bằng chứng cần có |
| ---: | --- | --- |
| 0 | Xác minh API profile, SQL DB_NAME/server, runtime principal, root pair | Chỉ DB test; histories đúng chain; không có quyền với hai DB bảo vệ. Chụp hash published baseline của DB test |
| 1 | Login Admin A bằng Identity test | HTTP 200, JWT được server phát, không log JWT; AuthSession dùng token này |
| 2 | Kiểm tra membership A; Admin không membership | A được phép; không membership/inactive/no-edit trả 403 |
| 3 | Flutter chọn Site A → Building A → Floor A1 | IDs đúng dữ liệu test; chưa tự tạo draft hoặc ghi graph |
| 4 | Tạo local nodes hành lang/cửa/elevator, directed edges; tạo draft | POST base 201 khi chưa có; Version 1. QR provenance chỉ dùng bản ghi test đã xác minh |
| 5 | Chọn PNG rồi JPG synthetic | Canvas có pixels, Fit/zoom/pan khớp; POST image 201, MIME/dimensions đúng; ảnh upload không phải static public URL |
| 6 | Room/Place một/nhiều cửa | UI chưa có Room editor: export JSON v2 vừa có, bổ sung Room fixture offline bằng GUID của Entrance nodes, import đúng tầng; label/polygon/Unknown giữ nguyên, không coi label là destination |
| 7 | Save graph + image | PUT 200, expectedVersion đúng, imageAssetId gắn đúng asset. Chỉ lúc này UI đánh dấu saved; graph không chứa Base64 gửi SQL |
| 8 | Export backup trước nếu có unsaved edits; reload Chrome | Dirty prompt có thể hủy; sau reload AuthSession in-memory mất theo thiết kế, đăng nhập lại bằng tài khoản test |
| 9 | Chọn cùng tầng, Load Draft | GET metadata → graph version pinned → JWT image GET; khôi phục cả pixels/geometry/Room/entrance/transition refs |
| 10 | So sánh với JSON trước save và tọa độ | IDs, cạnh có hướng, inactive/unmeasured, label/polygon, tầng và asset reference khớp; SHA trên bytes download khớp metadata, không bắt buộc khớp upload gốc |
| 11 | Dừng/restart backend với cùng DB/root | Load vẫn thành công từ SQL/file thực; dùng log/ảnh/root thực, không fake storage |
| 12 | Hai tab load N; A save trước, B save sau | A 200 N+1; B 409 draft_version_conflict. B giữ local, có keep/export/reload; không overwrite |
| 13 | History + restore revision cũ | Versions paged đúng; restore 200 tạo version mới, giữ revision cũ/ảnh cũ; chỉ thay local sau download thành công |
| 14 | Không JWT/expired/bad signature; user thường; Admin A sửa URL floor/image B | 401/403 phù hợp, không đọc bytes/private graph B, DB/head không đổi. Các API published vốn quyền đọc toàn cục không được nhầm với Site isolation của draft |
| 15 | Storage disabled/quota/failure/timeout/offline trong profile test | 503/409 quota/413 tách biệt; local/ảnh không mất; không Saved giả. Upload-ack/save-fail retry reuse asset; upload uncertain dùng scoped recovery. Không tạo orphan bằng cách tự xóa file đang tham chiếu |
| 16 | Restore đã 200 nhưng image GET lỗi | Thông báo server đã restore và cần Reload; giữ local; không restore lặp mù quáng |
| 17 | Đổi Floor/Site, Reload, Back khi dirty; đổi mạng | Hủy thì giữ đúng map/room/image/AuthSession. Cấu hình đang chọn không hiển thị bản của floor khác |
| 18 | Kiểm tra graph trước/sau | Sorted content/hash/count production-like baseline **trong DB test** không đổi; không UPDATE WayMarks/Nodes/Edges hoặc FloorPlanImageUrl do draft API |
| 19 | Kết thúc/review artifacts | Không publish; backup cặp test hoặc giữ để review; không purge, commit secrets, migrate hay seed DB thật |

Lỗi mạng không đồng nghĩa SQL chưa commit: reload metadata/recovery để đối chiếu.
Không tuyên bố giữ draft chưa lưu sau browser crash/process kill; cần export
backup hoặc save đã xác nhận. Fault injection chỉ vào test profile/root/data.

## 10. Lệnh sau khi được phê duyệt — CHƯA THỰC THI

Các lệnh sau **không phải cách chạy an toàn với source hiện tại**: guard/profile
E2E và blocker test phải được xử lý trước. Đây là runbook tương lai; không chứa
connection string/credential thật. `--no-launch-profile` tránh profile cũ ép về
Development. Cần cung cấp secret qua kênh riêng, không paste vào terminal history.

```powershell
# PowerShell mới, chỉ sau khi guard E2E + schema/bootstrap TEST được duyệt.
Set-Location D:\project\WayMark
$env:DOTNET_ENVIRONMENT = 'MapDraftE2E'
$env:ASPNETCORE_ENVIRONMENT = 'MapDraftE2E'

# Operator cung cấp biến môi trường riêng ngoài Git:
# ConnectionStrings__WayMarkDatabase -> chính xác DB test bằng principal test-only
# Jwt__SecretKey -> key E2E mới; không dùng key Development/production
if ([string]::IsNullOrWhiteSpace($env:ConnectionStrings__WayMarkDatabase) -or
    [string]::IsNullOrWhiteSpace($env:Jwt__SecretKey)) {
    throw 'Thiếu cấu hình E2E riêng. Không được dùng fallback.'
}
$env:Jwt__Issuer = 'waymark-mapdraft-e2e'
$env:Jwt__Audience = 'waymark-mapdraft-e2e-web'
$env:MapImages__Enabled = 'true'
$env:MapImages__RootPath = Join-Path $env:LOCALAPPDATA 'WayMark\MapDraftE2E\WayMark_MapDraft_E2E_Test\images'
$env:MapImages__MaxStorageBytes = '134217728'
$env:MapImages__MaxObjects = '50'
$env:MapDraftLimits__MaxRevisionsPerFloor = '20'
$env:MapDraftLimits__MaxImagesPerFloor = '8'
$env:MapDraftLimits__MaxImageBytesPerFloor = '33554432'

# Chỉ sau khi launcher/startup guard được triển khai và kiểm thử:
dotnet run --project WayMark.Api/WayMark.Api.csproj --no-launch-profile -- --environment MapDraftE2E --urls https://localhost:7627
```

Terminal Flutter riêng sau khi xác nhận API dùng đúng SQL/root test:

```powershell
Set-Location D:\project\WayMark\waymark
flutter run -d chrome --web-hostname localhost --web-port 5628 --dart-define=WAYMARK_API_BASE_URL=https://localhost:7627/api
```

Đối với schema, operator duyệt riêng việc tạo database rồi dùng migrator có cùng
guard/connection riêng: AuthDbContext tới CreateAuthSchema, WayMarkDbContext tới
BindMapImagesToDrafts (đầy đủ chain ở mục 6.2). Không cung cấp hoặc thực thi một
lệnh `database update` không có guard và chưa có approval trong preflight.
Không dùng EnsureCreated cho SQL Server E2E: cần kiểm thử đúng migration history.

## 11. Verification đã thực sự chạy

| Kiểm tra | Kết quả lần này |
| --- | --- |
| `dotnet build WayMark.Api/WayMark.Api.csproj --artifacts-path waymark/.dart_tool/phase7b2d1/dotnet` | PASS, 0 warnings / 0 errors; không ghi đè output API đang được tiến trình khác dùng |
| `dotnet test WayMark.Api.Tests/WayMark.Api.Tests.csproj --artifacts-path ...` | **BLOCKED/FAIL compile CS0535**, không test case backend nào được chạy. 212/212 là baseline cũ |
| SQL-provider model + script generation probe | PASS, cả hai snapshot match; đúng migrations/history, không chạy SQL DDL |
| SQL read-only metadata/history | PASS trên connection thực tế, xác nhận pending và trạng thái hai DB |
| `flutter analyze --no-pub` | PASS, không issues |
| `flutter test --no-pub --reporter expanded` | **175 PASS, 1 SKIP** như baseline |
| `git diff --check` | PASS; cảnh báo line-ending CRLF của Git không phải lỗi whitespace |
| Web build | Không chạy lại trong preflight; baseline 7B-2C là lịch sử, không coi là build mới |

Audit test hosts trước khi chạy: EF InMemory hoặc SQLite private/in-memory,
TestServer, random JWT keys, fake SMTP. MapDraftModelTests dùng SQL provider chỉ
sinh model/script không có connection string. ManagedImageTestStorage tạo file
tạm có owner guard ngoài Git, không root ảnh development thật. EnsureCreated
chỉ xuất hiện trong SQLite test fixture, không trong Program/API runtime.

Do backend compile bị chặn, lần này không có bằng chứng mới rằng filesystem
provider/integration backend đã chạy. Flutter suite dùng mock API; chưa có E2E
Save/Load với SQL Server, camera, cấp quyền, storage thực hay restart API thật.

Logs/config metadata đã che giá trị và hash baseline nằm trong
`waymark/.dart_tool/phase7b2d1/`, Git ignore. Probe không chứa credential literal,
không khởi tạo database hay gọi startup code của API. Không tạo/xóa root ảnh
thật; build/test artifacts chỉ phục vụ kiểm tra này.

## 12. Danh sách phê duyệt cần có và điểm dừng

1. Cho phép sửa source tối thiểu: fake email/test đang chặn build test, E2E
   launcher/startup/bootstrap guards, CORS/Swagger exact-origin trong E2E; rerun
   backend suite đầy đủ và các guard negative tests.
2. Duyệt xử lý JWT literal trong tracked appsettings và cấu hình E2E riêng;
   không tự sửa/rotate key hiện có. Quyết định xử lý key nếu đã dùng/chia sẻ.
3. Chấp thuận đúng instance + tên **WayMark_MapDraft_E2E_Test**, principal
   migrator/runtime riêng và chế độ RCSI test. Không chấp thuận ngầm thay hai DB thật.
4. Phê duyệt tạo database test và áp dụng đầy đủ migration chain **chỉ tại test**
   sau khi guard/source verification đạt. Duyệt SQL forward; không apply từ API startup.
5. Phê duyệt fixture Site/Building/Floor/graph test, tài khoản test, role Admin
   và Site membership test qua tool có kiểm soát. Không tạo/grant tài khoản thật.
6. Phê duyệt root/ACL/quota/pair backup test, browser certificate trust nếu cần,
   và fault injection network/storage giới hạn ở môi trường này.
7. Reset/drop/recreate database/root test là approval riêng sau này, không nằm
   trong việc chạy checklist thông thường; tuyệt đối không dùng hai DB bảo vệ.

Chỉ khi 1–6 đã được duyệt/thực hiện/xác minh mới đổi trạng thái sang GO cho chạy
7B-2D-2. **DỪNG tại preflight; chưa cấp quyền hoặc thực hiện các thao tác trên.**

File được thêm vào workspace trong sprint này: duy nhất báo cáo
`docs/development/MapPersistence7B2DPreflight.md` (ngoài artifact ignored).
Đối chiếu hash toàn bộ tracked/untracked ở đầu và cuối lượt để bảo toàn mọi
source/secret config/migration/Gradle/Windows-generated/Figma/local planning có sẵn.
Không stage, commit hoặc push.
