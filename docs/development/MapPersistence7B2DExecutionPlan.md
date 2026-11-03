# Phase 7B-2D-2A — SQL execution plan & approval gate

Ngày: **2026-10-21**. Repo `D:\project\WayMark`, branch `auth-jwt-assignment`,
HEAD `631a76cd196460318429ebff8da394818ccbdd2d`.

## 1. Quyết định: NO-GO thực thi; DỪNG tại APPROVAL GATE

Đã chuẩn bị SQL, runner từng bước, fixture và cấu hình mẫu. **Chưa được phép
provision/migrate/seed/cấp quyền/tạo storage/trust certificate.** Prompt hiện tại
không phải approval thực thi. Manifest `docs/database/e2e/ReviewManifest.json`
đang `Decision: NO-GO`; runner từ chối mọi bước ghi trước khi mở kết nối.

Hai blocker được chứng minh trong lượt này:

1. **Instance hiện tại chỉ Windows Authentication:** đọc trực tiếp
   `SERVERPROPERTY('IsIntegratedSecurityOnly') = 1`. E2E profile yêu cầu SQL login
   riêng, nên không thể dùng instance này theo kiến trúc hiện tại. Ưu tiên chọn
   instance test khác đã hỗ trợ SQL Authentication; tên database vẫn phải chính
   xác `WayMark_MapDraft_E2E_Test`. Không tự bật mixed mode/TCP, restart service,
   sửa registry hoặc thay đổi instance đang chứa hai DB bảo vệ. Nếu muốn đổi
   authentication mode trên instance chung, phải là quyết định/rủi ro và nhiệm vụ
   riêng; không nằm trong bundle này.
2. **Guard backend dùng sai lớp securable:**
   `WayMark.Api/Security/E2EConnectionInterceptor.cs:15–17` hiện gọi
   `HAS_PERMS_BY_NAME(NULL,'SERVER',...)`. Kiểm tra SELECT trực tiếp trả **NULL**;
   cú pháp server đúng là `HAS_PERMS_BY_NAME(NULL,NULL,...)`, trả **1** với caller
   sysadmin hiện tại. Vì `ValidateIdentity` yêu cầu ba cờ bằng false, guard cũ sẽ
   từ chối cả runtime hợp lệ. Không phải lỗi mở quyền: đây là lỗi từ chối kết nối.
   Cần approval riêng cho sửa tối thiểu ba lời gọi + regression test kiểm tra SQL
   thật/shape truy vấn; fake metadata tests trước đây không phát hiện lỗi này.
   **Không sửa backend trong lượt chỉ-script/tài-liệu này.**

Quy tắc lớp NULL được xác nhận trong [Microsoft HAS_PERMS_BY_NAME](https://learn.microsoft.com/en-us/sql/t-sql/functions/has-perms-by-name-transact-sql?view=sql-server-ver16).
264/264 là baseline hotfix; không thay thế bằng chứng SQL Server trực tiếp.

## 2. Bằng chứng chỉ đọc mới nhất

Đã đọc ba báo cáo Preflight/Hotfix/ManagedImageStorage, cấu hình, Program, DI,
design-time factories, guard, entities và toàn bộ forward migrations liên quan.
Đã chạy probe cấu hình không Build/Run API, `sqlcmd` SELECT và runner **chỉ với
Step Inventory**. Không gọi bất kỳ step ghi nào.

| Mục | Kết quả |
| --- | --- |
| Instance | DataSource `.`, SQL Server mặc định `MSSQLSERVER`, ServerName `LAPTOP-PFRPMR3O`, InstanceName NULL, `16.0.1000.6` |
| Provisioning caller | Windows hiện tại có sysadmin=1, CREATE ANY DATABASE=1, ALTER ANY LOGIN=1; chỉ được cân nhắc cho provisioning được duyệt |
| Hai DB bảo vệ | `WayMarkDatabase`, `WayMarkAuthDatabase`: ONLINE, RCSI ON, TRUSTWORTHY OFF, containment NONE; không thay đổi |
| DB test | Chưa có trong sys.databases; không giả định có thể tạo nếu chưa duyệt |
| Hai SQL login dự kiến | `WayMark_E2E_Runtime`, `WayMark_E2E_Migrator` chưa tồn tại; quyền thực tế của chúng **chưa thể kiểm chứng** |
| Development effective configuration | Connection từ appsettings → `WayMarkDatabase`, Integrated Security; JWT key/issuer/audience từ User Secrets; storage disabled/root thiếu |
| E2E effective configuration hiện tại | Template mask hai connection keys bằng chuỗi rỗng; key E2E/root/connection riêng chưa được cấp → startup fail closed |
| HTTPS | `dotnet dev-certs https --check` thấy cert localhost còn hiệu lực đến 2027-10-18; chưa xác nhận Chrome trust, không chạy trust/export/create |
| Published graph hiện tại | Sites=1, Buildings=1, Floors=2, Nodes=7, Edges=10, WayMarks=3; không đọc/copy Identity user data |

Không in connection string đầy đủ, password, JWT, password hash hay User Secrets.
Nếu chọn instance khác, **bằng chứng target/permissions ở trên không chuyển sang
instance mới**: phải chạy lại Inventory và duyệt ExpectedServerName mới trước ghi.

## 3. Configuration precedence và guard

`WebApplication.CreateBuilder`: appsettings chung → file environment → User Secrets
chỉ trong Development → environment variables → CLI. Trong MapDraftE2E không tự
nạp User Secrets Development. `E2ESafetyProfile.ReadAndApply` kiểm tra các giá trị
E2E tường minh trước, rồi thêm in-memory provider cuối để pin JWT và connection.
Không dùng launchSettings ép Development; launcher có `--no-launch-profile`.

- WayMarkDbContext và AuthDbContext dùng cùng profile SQL Server, cùng catalog
  allowlist, histories riêng `dbo.__EFMigrationsHistory` và
  `dbo.__AuthMigrationsHistory` (`Data/WayMarkDatabaseRegistration.cs`).
- Connection thiếu/sai catalog, Windows Integrated runtime, attach/failover,
  connection override xung đột, key thiếu hoặc storage thiếu đều bị từ chối.
- `E2EStartupCheck` kiểm tra mọi context đã đăng ký và chỉ OPEN + SELECT metadata;
  extra context thiếu interceptor/khác target bị từ chối. Interceptor xác minh
  actual server/catalog/login/ORIGINAL_LOGIN trước business query ở mỗi lần mở.
- `E2EDesignTimeFactories.cs` yêu cầu environment E2E tường minh; không fallback
  Development khi EF CLI. Không dùng EF để tạo DB/master: provisioning tách riêng.
- Program không Migrate/EnsureCreated/EnsureDeleted/seed ở startup. SQLite
  EnsureCreated trong test host không phải startup ứng dụng.
- **Startup/EF guard vẫn đang có blocker ở mục 1.** SQL trong bộ plan dùng đúng
  `HAS_PERMS_BY_NAME(NULL,NULL,...)`; không tự nhận đã sửa C#.

Runner plan chỉ nhận tên Step cố định, không nhận SQL tùy ý; cần manifest hash khớp
toàn bộ file đã review, Decision GO, approval ID và tên DB xác nhận. Mọi batch SQL
ghi có DB/server guard; migrations có thêm guard SQL login/privilege ở mỗi GO.
Runner dùng connection riêng không pool/ambient transaction và ngừng ở lỗi đầu.
Không tự rollback những step đã commit, không tự repair/reset/retry.

## 4. Bộ script chuẩn bị — chưa thực thi

Thư mục `docs/database/e2e/`; các SQL parameter được bind bằng SqlCommand,
**không** dùng sqlcmd text substitution cho password. Không paste các file có
`@ExpectedServerName` vào SSMS rồi bỏ guard. Dùng runner đã review.

| File | Tác động dự kiến sau approval |
| --- | --- |
| 00-ReadOnlyInventory.sql | SELECT master/server metadata, trạng thái 3 DB, hai login |
| 01-ReadOnlyProtectedEvidence.sql | SELECT trạng thái/histories/schema và count+SHA256 nội dung 6 bảng graph thật; không xuất Identity user rows |
| 10-CreateDatabase.sql | Tạo mới duy nhất DB test; RCSI OFF, recovery SIMPLE chỉ trên DB vừa tạo; nếu đã tồn tại thì dừng |
| 20-CreateLogins.sql | Tạo đúng 2 SQL login, mật khẩu độc lập nhập kín; CHECK_POLICY/EXPIRATION ON, không thêm server role |
| 21-CreateUsersAndMigrationPermissions.sql | DB mới phải rỗng: tạo 2 user và 2 history tables đúng EF; grant DDL giới hạn cho migrator |
| 30-AuthSchema.sql | EF-generated idempotent `0 → CreateAuthSchema`, chỉ Identity test và auth history |
| 31-WayMarkSchema.sql | EF-generated idempotent `0 → BindMapImagesToDrafts`, đầy đủ chain 4 migration WayMark |
| 40-RuntimePermissions.sql | Grant theo object, không db_owner/db_datawriter, không graph/role/membership writes hoặc DDL |
| 50-BootstrapIdentity.sql | Insert 4 tài khoản synthetic trên Identity rỗng, hash từ ASP.NET Identity PasswordHasher; không nhận/adopt/reset tài khoản sẵn có |
| 60-TestSitesAndMemberships.sql | Tạo Admin role, assign 3 test users; Site A/B, mỗi Site 1 Building, A có 2 Floor, B có 1 Floor; 2 membership |
| 70-OptionalQrGraph.sql | **Tùy chọn/approval riêng:** 5 node, 6 cạnh có hướng, 3 QR trên graph test rỗng; tuyến synthetic 23 m qua elevator, một node cô lập |
| 80-ReadOnlyVerification.sql | SELECT quyền actual runtime, hai histories và graph test fingerprints trước/sau draft writes |
| 90-SealMigratorDatabasePermissions.sql | Revoke quyền DDL/history DML/CONNECT của migrator trong DB test |
| 91-DisableMigratorLogin.sql | Disable đúng login migrator mới sau khi dùng xong; không disable runtime/Windows login/service |
| DraftRoomFixture.json | Contract backend, 3 draft nodes, 1 edge, 1 Place với 2 Entrance GUIDs; Unknown safety, không ảnh/Base64 và không publish |
| ReviewManifest.json | Hash SQL/scripts/migrations/guard/DI/config; trạng thái hiện tại NO-GO |

Không có DROP/TRUNCATE/DELETE, USE vào hai DB bảo vệ hoặc sp_configure trong SQL
bundle. Không copy graph/Identity/QR thật. Fixture bootstrap cố ý **dừng khi có dữ
liệu**, thay vì tự đoán quyền sở hữu hoặc ghi đè. Chỉ script GRANT/revoke và
migrations idempotent có thể chạy lại sau kiểm kê riêng; không replay cả bundle.

### Phân biệt quyền

- **Provisioner:** Windows principal đã duyệt, tạo database/login và thao tác
  bootstrap theo từng bước. CREATE DATABASE/ALTER ANY LOGIN và CONTROL trên test DB
  là quyền cần cho các bước tương ứng; không cấp các quyền này cho runtime.
  Việc tạo DB/login ghi system metadata **master**, không phải server setting.
- **Migrator:** SQL login riêng, user chỉ ở test DB; CREATE TABLE + ALTER/REFERENCES/
  VIEW DEFINITION trên dbo để tạo schema hiện hữu, SELECT/INSERT chỉ hai history
  tables. Có quyền DDL mạnh trong **test DB** trong cửa sổ migration; đây là principal
  tin cậy, không phải tài khoản vận hành API. Sau đó revoke và disable.
- **Runtime:** SELECT graph/hierarchy, memberships, Identity và histories;
  SELECT/INSERT/UPDATE AspNetUsers cho đăng ký/login/reset hiện có;
  SELECT/INSERT/UPDATE draft head, SELECT/INSERT revisions/assets. Không DELETE,
  UPDATE immutable revisions/assets, INSERT role/membership, graph writes hoặc DDL.
  Một số Admin CRUD ngoài scope sẽ bị SQL từ chối trong E2E: không nâng quyền chỉ
  để làm chúng chạy. Không có db_owner hoặc server admin role.
- Login mới không được map vào hai DB bảo vệ. Nếu guest/public/custom policy của
  instance làm HAS_DBACCESS protected=1, **dừng**, không tự DENY/sửa DB thật.

## 5. Migration review

Database test cần **cả chain**, không chỉ hai migration pending:

1. AuthDbContext: `20261010032404_CreateAuthSchema` → 7 bảng Identity, PK/FK/index
   Identity; history `__AuthMigrationsHistory`.
2. WayMarkDbContext: `20261018022742_CreateWayMarkSchema` → WayMarks và unique code.
3. `20261018053754_AddNavigationSchema` → Sites, Buildings, Floors, NavigationNodes,
   NavigationEdges, NavigationNodeId nullable trên WayMarks; các FK/index/checks
   graph giữ nguyên.
4. `20261020094848_AddMapDraftFoundation` → 4 bảng:
   - FloorMapDrafts: GUID PK, unique FloorId, FK Floor Restrict; Status='Draft', Version>0.
   - FloorMapImageAssets: GUID PK, unique StorageKey, index/FK Floor Restrict;
     width/height 1–8192, pixels ≤32M, bytes 1–10MiB, PNG/JPEG checks.
   - SiteMapMemberships: identity int PK; unique nonclustered (SiteId,UserId),
     index UserId, Site FK Restrict. UserId là logical Identity reference, không
     duplicate Auth entities/FK liên-context trong snapshot WayMark.
   - FloorMapDraftRevisions: PK (DraftId,Version), Version>0, FK Draft và nullable
     ImageAssetId Restrict, index ImageAssetId, ContentJson bắt buộc.
   Foundation có **5 FK, 6 index, 8 check constraints**. Required values không
   được giả định có SQL default: seed/API phải truyền đúng fields.
5. `20261020101304_BindMapImagesToDrafts` → unique alternate key
   AK_FloorMapDrafts_FloorId và FK image FloorId → draft FloorId Restrict.

Rooms/Place/Entrance/transition nằm trong immutable revision JSON, không có bảng
Room production mới; validation kiểm tra GUID/entrances/scope. X/Y normalized chỉ
để vẽ; DistanceMeters tách biệt; Unknown không được quảng cáo an toàn xe lăn.

Sau toàn chain dự kiến **19 bảng gồm 2 histories**. SQL forward chỉ thêm schema,
không DROP/UPDATE/DELETE nghiệp vụ. INSERT history là bookkeeping bình thường:
1 auth MigrationId + 4 WayMark MigrationId. Generated SQL có GO, transactions và
EXEC cho một số index để không compile sai cột mới. Không thay entity/migration/
snapshot. Auth legacy composite string keys giữ nguyên; kiểm tra warning/actual
key sizes khi apply, không tự thay schema để né cảnh báo.

Nếu schema/history có drift, object tồn tại ngoài chain, duplicate FloorId hoặc
image không có draft, **dừng**. Idempotent không sửa schema sai và không xác minh
checksum migration đã áp dụng. Không xóa row để ép FK thành công. Nhờ DBA đối
chiếu source/schema; approval lại mọi phương án reconcile. Bản test mới không
được khởi tạo bằng EnsureCreated hoặc copy backup dữ liệu thật.

SQL đã sinh offline bằng EF Core SQL Server **10.0.12**, assembly build hotfix:

```powershell
# CHỈ sinh lại file SQL; không kết nối SQL Server.
& scripts/mapdraft-e2e/Export-ReviewedMigrations.ps1 `
  -ApiOutputDirectory "$PWD/waymark/.dart_tool/phase7b2d-hotfix/dotnet/bin/WayMark.Api/debug" `
  -EfToolDll "$PWD/waymark/.dart_tool/phase7b2a/tools/.store/dotnet-ef/10.0.12/dotnet-ef/10.0.12/tools/net8.0/any/tools/net8.0/any/ef.dll"
```

Generator gọi `dotnet exec ... ef.dll migrations script 0 <Last> --idempotent
--context <Context> --assembly ... --startup-assembly ... --output ...` cho từng
context. Chỉ thêm guard trước từng batch, không viết lại logic migration. Nó dùng
credential CSPRNG dùng một lần/dummy server `.invalid` để dựng factory offline;
không chứa secret thật, không tạo root ảnh và khôi phục process environment sau
khi xong. Không cài global dotnet-ef; `dotnet ef` trên PATH hiện không có, local tool
10.0.12 đã có. Không dùng `database update` trong runbook này: apply SQL đã review
với principal migrator sau approval tương ứng.

## 6. Storage, HTTPS và backup/restore — chỉ kế hoạch

Root đề xuất (chưa tạo):
`%LOCALAPPDATA%\WayMark\MapDraftE2E\WayMark_MapDraft_E2E_Test\images`.
Chốt path thực tế sau khi inventory mọi root Dev/production; không dùng dummy
ProtectedImageRoots chỉ để vượt guard. OS account chạy API và SQL runtime login
là hai danh tính khác nhau. Chọn RuntimeIdentitySid đúng account chạy dotnet.

`Prepare-ApprovedE2EStorage.ps1` chỉ nhận thư mục **chưa tồn tại**, cấm overlap
repo/roots khác và Git/reparse ancestry; tạo root mới và ACL chỉ API SID Modify,
SYSTEM/Administrators Full Control. Không recursive ACL lên thư mục có sẵn. Nếu
lỗi, giữ thư mục mới để kiểm tra, không tự xóa/adopt dữ liệu. Private objects,
manifests, staging và leases sẽ được provider tạo khi upload sau này.

Quotas pin bởi profile: total **128 MiB/50 objects**; **8 images/32 MiB per floor**;
**20 revisions per floor**; mỗi ảnh ≤10 MiB, 8192 px/side, 32 MP. Không tự purge
revision/image để vượt quota. JWT/private download + Admin + membership vẫn bắt buộc.

HTTPS: dùng `https://localhost:7627`, Flutter origin `http://localhost:5628`,
base URL `https://localhost:7627/api`. Trust cert là approval **riêng**; không thêm
bypass kiểm tra TLS vào Flutter. Lệnh tương lai nếu được duyệt:
`dotnet dev-certs https --trust`. Không export private key vào Git. SQL TLS khác
HTTPS: runner mặc định verify SQL cert; switch `-AllowLocalSelfSignedSqlCertificate`
chỉ được duyệt cho SQL local kiểm soát được, không ngầm tắt TLS hoặc mở rộng host.

Backup pair sau khi có dữ liệu test: dừng writers/API, không dừng MSSQLSERVER chung;
backup full **test DB** + toàn objects `.bin/.json` cùng staging cần reconcile,
ghi version/checksum inventory kín ngoài Git. Ví dụ SQL cần approval backup riêng:

```sql
-- Target bắt buộc phải được guard như các script trên; path là parameter riêng.
BACKUP DATABASE [WayMark_MapDraft_E2E_Test] TO DISK=@NewPrivateBackupPath WITH COPY_ONLY,CHECKSUM;
RESTORE VERIFYONLY FROM DISK=@NewPrivateBackupPath WITH CHECKSUM;
```

Tên backup phải mới; không INIT/FORMAT/REPLACE, không backup vào repo/root production.
SQL service account cần ghi backup folder, backup operator cần quyền backup test;
**backup ghi file và msdb backup history**, cần liệt kê trong approval riêng. Không
coi VERIFYONLY là restore test. Thử restore trên instance cô lập mới, cùng catalog
allowlist/root riêng, không đè database đã có; schema/data SQL và objects/manifests
phải cùng điểm dừng. Đối chiếu mọi asset/revision reference/checksum, xử lý orphan
login SID trong test theo DBA review. Không cung cấp script restore-overwrite hoặc
drop/recreate trong bundle. Retention/xóa vật lý là approval khác.

## 7. Lệnh và runbook SAU KHI được duyệt lại

**Các lệnh ghi dưới đây chưa được chạy, và hiện bị manifest NO-GO chặn.** Sửa
source guard + kiểm thử + chọn target tương thích trước; refresh manifest rồi
review độc lập. Chỉ nhiệm vụ được duyệt mới đổi Decision sang GO. Mọi thay đổi
file/hash/instance/permissions phải xin review mới. Không chạy cả danh sách bằng loop.

Chuẩn bị terminal PowerShell mới; không bật transcript, không xuất credentials:

```powershell
Set-Location D:\project\WayMark
$run='./scripts/mapdraft-e2e/Invoke-ApprovedE2EStep.ps1'
$common=@{
  SqlDataSource='<approved-instance>'
  ExpectedServerName='<approved-SERVERPROPERTY-ServerName>'
  SqlClientDirectory="$PWD/waymark/.dart_tool/phase7b2d-hotfix/dotnet/bin/WayMark.Api/debug"
  ApprovedManifestSha256='<SHA256-of-newly-reviewed-GO-manifest>'
}
# Chỉ sau approval TLS SQL local riêng nếu cần:
# $common.AllowLocalSelfSignedSqlCertificate=$true
$approval=@{ApprovalId='7B2D2-<approved-change-id>';ConfirmDatabase='WayMark_MapDraft_E2E_Test'}
$runtime=Get-Credential -UserName 'WayMark_E2E_Runtime'
$migrator=Get-Credential -UserName 'WayMark_E2E_Migrator'
```

| Bước / lệnh chính xác | Target & quyền | Thành công cần thấy | Khi thất bại |
| --- | --- | --- | --- |
| 1. `& $run @common -Step Inventory` rồi `-Step ProtectedEvidence` | SELECT master + protected graph/history, provisioner read | Instance đúng, mixed auth=0, DB test chưa có, login mới chưa có; evidence trước ghi | Dừng nếu target/auth/privilege khác; không chuyển sang DB thật |
| 2. `& $run @common @approval -Step CreateDatabase` | New test DB + master catalog; CREATE ANY DATABASE | ONLINE, RCSI OFF, SIMPLE, trustworthy OFF | Create DB autocommit: có thể đã tạo trước khi option lỗi; kiểm kê, không replay/drop |
| 3a. `& $run @common @approval -Step CreateLogins -RuntimeCredential $runtime -MigratorCredential $migrator` | master new logins; ALTER ANY LOGIN | 2 login SQL mới, không server role | Login đã có thì dừng; không đổi password/adopt |
| 3b. `& $run @common @approval -Step CreateUsers` | Test DB; CONTROL | 2 users + 2 histories rỗng, migrator grants | Kiểm kê partial state; không EnsureCreated |
| 4a. `& $run @common @approval -Step MigrateAuth -Credential $migrator` | Test DB; scoped migrator | Auth history đúng 1 row, 7 Identity tables | Stop, connection đóng rollback transaction chưa commit; history/schema review |
| 4b. `& $run @common @approval -Step MigrateMap -Credential $migrator` | Test DB; scoped migrator | WayMark history đúng 4 row; latest BindMapImagesToDrafts, tổng 19 tables | Không tự chạy Down hoặc sửa history; chain có thể đã commit migration trước |
| 5a. `& $run @common @approval -Step RuntimeGrants` | Test DB; CONTROL | Object-specific grants đúng mục 4 | Không cấp db_owner/db_datawriter để bỏ qua lỗi |
| 5b. BootstrapIdentity theo block dưới | Test DB; CONTROL, hash private memory | 4 test users, không role tự cấp | Nếu có user thì dừng, không reset/overwrite |
| 5c. `& $run @common @approval -Step BootstrapSites` | Test DB; CONTROL | Site A/B, 2 buildings/3 floors, 3 Admin grants, 2 memberships | Transaction rollback step; không sửa user thật |
| 5d. Tùy chọn `& $run @common @approval -Step OptionalQrGraph` | Test DB; CONTROL, approval riêng | 5 nodes/6 edges/3 QR; route 23 m và isolated | Không dùng mã/ID/seed production |
| 5e. `& $run @common -Step VerifyRuntime -Credential $runtime` | Test DB; runtime SELECT | sysadmin/admin perms=0; protected access=0/NULL; DDL/role/membership/graph/DELETE permissions=0; draft grants=1 | Dừng nếu thiếu/rộng quyền; không sửa protected DB |
| 5f. `& $run @common @approval -Step SealMigrator` rồi `-Step DisableMigrator` | Test DB revoke, master chỉ login mới disable | DDL/history DML đã revoke, migrator disabled | Dừng, ghi evidence; không dùng migrator chạy API |
| 6. Storage script + private E2E env, HTTPS | Chỉ root E2E mới/process env; ACL operator và cert owner | Path độc lập, quotas, private key và runtime login tách biệt | Không fallback root Dev hoặc disable TLS |
| 7. `& ./scripts/Start-MapDraftE2E.ps1` | API E2E, đã duyệt riêng | Startup xác nhận target/permission/root; listening 7627 | Guard lỗi thì dừng, không đổi sang Development |
| 8. Flutter + checklist mục 8 | E2E HTTP/SQL/image root | Save/Load/image/revisions/auth isolation evidence | Giữ local draft, không publish hoặc blind retry |
| 9. VerifyRuntime trước/sau + ProtectedEvidence trước/sau | SELECT | Published graph hash không đổi, histories protected không đổi | Có diff thì dừng điều tra; không tự rollback DB thật |
| 10. Thu evidence/backup nếu duyệt | Private evidence/backup path, backup metadata | Timestamp, hashes, HTTP statuses, revision/image checksums; không credentials | Evidence không đủ thì chưa nghiệm thu |
| 11. Dừng API/Flutter do phiên test sở hữu; lặp Inventory/ProtectedEvidence | Chỉ tiến trình test và SELECT | Hai DB thật vẫn ONLINE/evidence khớp; test data/root giữ nguyên | Không kill SQL service/tiến trình người khác hoặc xóa môi trường |

Bootstrap account passwords chỉ nhập qua secure prompt; hasher ASP.NET được load
từ runtime đã cài và tự verify hash trong memory, không tự viết thuật toán hash:

```powershell
$testAccounts=@{}
foreach($name in 'wm-e2e-admin-a','wm-e2e-admin-b','wm-e2e-admin-none','wm-e2e-reader') {
  $testAccounts[$name]=Get-Credential -UserName $name
}
& $run @common @approval -Step BootstrapIdentity -TestAccounts $testAccounts `
  -AspNetRuntimeDirectory 'C:/Program Files/dotnet/shared/Microsoft.AspNetCore.App/10.0.13'
# Các password độc lập, ít nhất 16 ký tự, chữ hoa/thường/số và đáp ứng policy OS.
```

Storage sau approval, SID/path lấy từ operator, không từ client/browser:

```powershell
& ./scripts/mapdraft-e2e/Prepare-ApprovedE2EStorage.ps1 @approval `
  -Root '<approved-absolute-root>/WayMark_MapDraft_E2E_Test/images' `
  -ProtectedRoots @('<actual-Dev-root>','<actual-production-root>') `
  -RuntimeIdentitySid '<approved-API-process-SID>' `
  -ApprovedManifestSha256 $common.ApprovedManifestSha256
```

E2E private process settings theo template/hotfix: set E2E__SqlConnectionString
**chỉ từ credential runtime**, E2E__SqlDataSource, E2E__ExpectedServerName,
E2E__JwtSecretKey (CSPRNG Base64 ≥32 byte độc lập), E2E__ImageRoot,
MapImages__RootPath, E2E__ProtectedImageRoots__0..., E2E__StorageIsolationConfirmed=true.
Không set legacy ConnectionStrings overrides. Không tái dùng Development JWT.
Không in builder.ConnectionString hoặc token. Sau approval, cấu hình chính xác bằng:

```powershell
& ./scripts/mapdraft-e2e/Set-ApprovedE2EEnvironment.ps1 @approval `
  -SqlDataSource $common.SqlDataSource -ExpectedServerName $common.ExpectedServerName `
  -RuntimeCredential $runtime -SqlClientDirectory $common.SqlClientDirectory `
  -Root '<approved-absolute-root>/WayMark_MapDraft_E2E_Test/images' `
  -ProtectedRoots @('<actual-Dev-root>','<actual-production-root>') `
  -ApprovedManifestSha256 $common.ApprovedManifestSha256
# Chỉ thêm -AllowLocalSelfSignedSqlCertificate nếu exception TLS SQL đã được duyệt.
```

Script tạo key JWT mới trong process; chạy lại sẽ làm token test cũ mất hiệu lực.
Không chạy script trong terminal Development đang dùng. Launcher tự set matching DOTNET/
ASPNETCORE_ENVIRONMENT và khôi phục hai biến này sau khi dừng; đóng terminal riêng
sau test để bỏ private env. Không gọi `dotnet user-secrets set` lên project thật.

```powershell
Set-Location D:\project\WayMark\waymark
flutter run -d chrome --web-hostname localhost --web-port 5628 --dart-define=WAYMARK_API_BASE_URL=https://localhost:7627/api
```

## 8. Checklist E2E và evidence cần thu

1. Login admin-a trên đúng origin/API 7627. Xác nhận JWT issuer/audience E2E, role
   từ server, không log accessToken. Chọn Site A/Building/Floor theo codes/IDs
   **trả về thực tế**, không hardcode identity column values.
2. Export local backup trước thao tác test. Tạo draft, upload PNG/JPG không có dữ
   liệu bệnh nhân, đặt nodes/edges. Ghi draftId/version, normalized image checksum.
   POST create phải trước upload; PUT reference ảnh sau upload, không Base64 SQL.
3. Room UI chưa có. Dùng `DraftRoomFixture.json` qua Swagger validate/save với
   `{expectedVersion:<current>,content:<fixture>}`, giữ imageAssetId của ảnh đã upload
   nếu cần; Save sẽ tạo revision mới. Fixture là **backend contract**, không phải
   file local Flutter JSON v2 để import trực tiếp. Reload/Load bằng UI phải giữ
   Place, 2 Entrance GUIDs, Unknown states và ảnh; không nhập Figma demo logic.
4. Reload Chrome, Load lại; restart **API test**, Load lại. So sánh node/edge/Place,
   entrance IDs, X/Y, metadata ảnh, zoom/pan, version. AuthSession không mất do
   Save/Load; không giả định SQL test chứng minh camera.
5. Hai phiên cùng version: A save 200, B save stale 409; B giữ local draft và có
   đường tải version mới/backup, không ghi đè. Restore sourceVersion cũ tạo version
   mới, ảnh/revision cũ giữ nguyên; old image vẫn download đúng checksum.
6. Missing/invalid/expired JWT →401; reader và Admin không membership →403;
   Admin B truy cập mọi draft/image/restore Site A →403 và ngược lại. Site list/map
   đọc hiện vẫn theo semantics JWT chung; chỉ draft/image là Site scoped.
7. QR/route tùy chọn dùng WM-E2E-7B2D-START → DEST (23 m synthetic), isolated không
   có đường; không dùng WM-DEMO codes trong DB thật. Accessible claims vẫn Unknown/
   false, không diễn giải route này là an toàn xe lăn.
8. Chrome DevTools Offline/abort để kiểm thử timeout/lost response; giữ local draft.
   Nếu save/upload response mất, đọc head/image metadata trước retry vì commit có
   thể đã xảy ra. Không kill SQL Server chung để tạo lỗi mạng.
9. Storage fault injection chỉ trên root test, thay đổi ACL/quota tạm phải có
   approval riêng và bản ACL đã lưu; không đụng Dev/production root, không xóa ảnh
   đang được revision tham chiếu. Ghi rõ case nào chưa test.
10. Thu private evidence: thời điểm/server/catalog/login-role booleans, migration
    IDs, HTTP statuses 201/200/401/403/409/503 thực nhận, JSON đã redacted, checksum
    inventory và screenshots không chứa password/JWT/Authorization header.
    ProtectedEvidence trước/sau cho count+content hash graph, histories/state/schema
    bảo vệ. Đây không phải checksum mọi hàng Identity/hay full DB backup; không
    tuyên bố toàn bộ database bất biến chỉ dựa vào counts. Nếu có writer khác đang
    hoạt động, lập maintenance/evidence window để phân biệt thay đổi ngoài phiên test.

## 9. Kiểm tra đã thực sự chạy trong 2D-2A

- Read-only live configuration/SQL inventory, histories/counts; không chạy API.
  ProtectedEvidence đã SELECT thành công, lưu 6 graph fingerprints và metadata
  kín tại artifact ignored `waymark/.dart_tool/phase7b2d-hotfix/plan-protected-evidence-before.json`.
- Lời gọi HAS_PERMS đúng/sai lớp kiểm tra trực tiếp: NULL so với 1 cho sysadmin.
- Sinh hai file EF migration SQL offline qua local tool; không connect SQL.
- SQL Server 2022 `TSql160Parser` (ScriptDom từ SSMS) parse **14 SQL files**:
  không parse errors. Parser không chứng minh permissions/native SQL execution.
- `Test-ExecutionPlanOffline.ps1`: **29/29 checks đạt**, gồm guards/refusals, manifest NO-GO, PowerShell AST,
  SQL forbidden patterns, SqlConnection construction **không Open**, actual Identity
  hasher self-verification bằng password ngẫu nhiên không ghi DB/file.
  Baseline backend 264 không rerun vì không sửa C#.
- Runner **Inventory chỉ SELECT** đã kết nối thành công sau chuẩn bị đúng SqlClient
  Windows implementation/native SNI/dependency; không bật TCP/mixed mode để né lỗi.
- `dotnet dev-certs https --check` chỉ đọc. Không chạy --trust.
- `git diff --check` và hash đối chiếu toàn bộ file có sẵn để bảo toàn Kilo/Flutter/
  Gradle/generated/Figma/backend/migrations. Không stage/commit/push.

## 10. Danh sách thao tác ghi cần approval RIÊNG

1. Source hotfix guard backend và regression checks ở mục 1 (ngoài scope lượt này).
2. Chọn chính xác instance test hỗ trợ SQL Authentication/target ServerName; nếu
   đổi server settings chung, cần nhiệm vụ riêng, không có script đổi settings này.
3. Tạo **mới** DB test (master metadata, MDF/LDF ở default SQL paths), RCSI OFF,
   SIMPLE; không tạo nếu DB đã có. Duyệt default file locations/model inheritance.
4. Tạo hai SQL login/password độc lập (master metadata) và hai database users;
   scoped migrator permissions. Không cấp quyền trên hai DB thật.
5. Precreate 2 histories + apply 1 Auth và 4 WayMark migrations trong test DB.
6. Runtime object grants; insert 4 Identity test users, Admin role + 3 user-role
   links, 2 Sites/2 Buildings/3 Floors, 2 active SiteMapMemberships.
7. **Tùy chọn:** 5 graph nodes/6 directed edges/3 QR synthetic chỉ trong test DB.
8. Revoke quyền/disable migrator test sau migration/bootstrap.
9. Root/parent directories E2E mới và ACL; independent JWT/process env; HTTPS trust
   hoặc SQL local self-signed certificate exception nếu thật sự cần.
10. Khởi chạy E2E và thao tác HTTP tạo draft/revision/image; ghi objects/manifests/
    staging/leases dưới root test. Fault injection/ACL tạm phải duyệt rõ phạm vi.
11. Private evidence/backup files, SQL test backup và msdb backup records nếu chọn
    backup. Restore/retention/drop/recreate/purge **không** được gộp approval này.

Không có approval nào ở trên được suy ra từ prompt hiện tại. Sau khi blocker được
xử lý, chạy lại review, cập nhật manifest GO/hash và yêu cầu approval theo từng
nhóm thao tác. **Dừng ở đây; chưa đủ điều kiện bắt đầu SQL writes hoặc E2E.**
