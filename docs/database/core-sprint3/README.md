# Core Sprint 3 — review / approval gate

**Chỉ `preview` được chạy trong Sprint 3. Chưa duyệt backup, apply SQL, cấp quyền hoặc ghi API trên SQL Server.** Cập nhật source Sprint 5/6: test Creator không còn cần Admin; chỉ A nhận SitePublisher. Phương án local Development mới dùng Windows identity hiện tại với ngoại lệ runtime được duyệt, không tạo account Windows/SQL login. Approval plan cũ phải review lại, không tự chuyển đổi hoặc thực thi. Không dùng scripts `database/e2e` cũ; chúng dành cho DB thứ ba không còn nằm trong quyết định hiện tại.

## 1. Sinh lại preview không kết nối SQL

```powershell
dotnet run --project tools/CoreSqlReadiness/CoreSqlReadiness.csproj -- preview D:\project\WayMark
```

Hai file SQL được EF Core SQL Server `IMigrator.GenerateScript` sinh từ `20261018053754_AddNavigationSchema` tới `20261023063955_AddPublishedMapProjects`; không dùng design-time factory, không gọi database update. Bản idempotent kiểm tra history, **không tự sửa schema drift**. Manifest lưu SHA256 để review lại đúng artifact. Regenerate sẽ cập nhật artifacts này; không sửa plan đã điền trực tiếp trong file sample.

Mỗi batch kiểm tra DB_NAME=WayMarkDatabase, actual SERVERPROPERTY so với session context do operator cấp, và baseline navigation history. Session mới phải không có transaction và IMPLICIT_TRANSACTIONS OFF; RAISERROR/RETURN từ chối trước SET XACT_ABORT. Client vẫn bắt buộc dừng khi lỗi. Đây là chốt chống chạy nhầm, không thay thế quyền SQL hay phê duyệt của người dùng.

## 2. Backup/verify — các lệnh DỰ KIẾN, chưa chạy

Chốt đường dẫn **mới, chưa tồn tại**, quyền ghi của SQL Server service, dung lượng và tài khoản backup. Không dùng INIT, FORMAT hoặc ghi đè file cũ. Sau khi được duyệt riêng:

```sql
BACKUP DATABASE [WayMarkDatabase]
 TO DISK=N'<APPROVED_NEW_FULL_BACKUP_FILE>' WITH COPY_ONLY,CHECKSUM;
RESTORE HEADERONLY FROM DISK=N'<APPROVED_NEW_FULL_BACKUP_FILE>';
RESTORE FILELISTONLY FROM DISK=N'<APPROVED_NEW_FULL_BACKUP_FILE>';
RESTORE VERIFYONLY FROM DISK=N'<APPROVED_NEW_FULL_BACKUP_FILE>' WITH CHECKSUM;
```

Backup tạo file và metadata msdb: cũng là thao tác chờ phê duyệt. Đề nghị backup mới cả WayMarkAuthDatabase trước cửa sổ bảo trì dù không migrate DB đó. Không suy ra phục hồi chắc chắn từ file .bak, history, hay VERIFYONLY: VERIFYONLY không kiểm tra toàn bộ cấu trúc dữ liệu. Rehearsal restore chỉ trên SQL Server instance cô lập được duyệt, cùng tên database, không restore đè hai DB hiện tại và không tự tạo DB thứ ba trong instance dự án. [Microsoft VERIFYONLY](https://learn.microsoft.com/en-us/sql/t-sql/statements/restore-statements-verifyonly-transact-sql?view=sql-server-ver16), [COPY_ONLY](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/copy-only-backups-sql-server?view=sql-server-ver16).

Nếu chưa có môi trường restore được phép: ghi rõ chưa rehearsal, giữ NO-GO cho thao tác phụ thuộc backup đã nghiệm thu; không tự vượt gate.

## 3. Apply — mẫu launcher cho operator review, CHƯA ĐƯỢC CHẠY

Không chạy raw SQL file trực tiếp trong session SSMS đang làm việc. Sau approval tạo một launcher **cục bộ riêng** và review actual server name, hash script, backup, baseline lần cuối:

```sql
:On Error exit
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
DECLARE @approvedServer nvarchar(128)=N'<APPROVED_ACTUAL_SERVER_NAME>';
IF DB_NAME() COLLATE Latin1_General_100_BIN2<>N'WayMarkDatabase'
 OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))<>@approvedServer
    THROW 51000,'Wrong reviewed target',1;
EXEC sys.sp_set_session_context @key=N'WayMarkApprovedServer',@value=@approvedServer,@read_only=1;
GO
:r "D:\project\WayMark\docs\database\core-sprint3\PendingMapMigrations.idempotent.review.sql"
```

Lệnh dự kiến (fresh dedicated connection; dùng trusted provisioning principal):

```powershell
sqlcmd -S . -d WayMarkDatabase -E -N -I -b -V 16 -i '<REVIEWED_PRIVATE_LAUNCHER.sql>'
```

TLS/certificate lỗi thì dừng, không tự tắt encryption hoặc sửa chứng chỉ. Với SQL authentication, dùng nguồn credential riêng được duyệt; không đưa password lên command line/source/log. Tool CoreSqlReadiness **không có lệnh apply migration**.

Sprint 6 thực thi đã gặp lỗi 1934 do ODBC sqlcmd mặc định QUOTED_IDENTIFIER OFF khi tạo filtered index. Mẫu launcher trên đã sửa **session options**, không sửa server/database settings hay SQL artifacts. `-I` bật QUOTED_IDENTIFIER từ lúc kết nối; các SET còn lại giữ đúng điều kiện filtered index. Lần chạy lỗi đã dừng sau hai migration đầu; không chạy lại mẫu baseline hai migration cũ. Dùng [resume launcher có guard history bốn migration](../core-sprint6/ResumePublishedMigration.review.sql) sau khi tiếp tục; file này **chưa thực thi**. Chi tiết [báo cáo SQL Sprint 6](../../CoreSqlE2ESprint6.md).

Quyền DDL phải do operator được duyệt giữ riêng: CREATE TABLE, ALTER schema/object cần tạo, REFERENCES các bảng FK liên quan, SELECT/INSERT map history. Không dùng principal DDL làm backend runtime. Sau apply kiểm tra map history đủ 5 migration, Auth history vẫn 1; không đánh dấu history thủ công.

## 4. Hai tài khoản test cụ thể và quyền Creator

Dùng **Creator + active CanEditDrafts Site membership + project Owner**. Creator chỉ truy cập floor draft mình tạo, không đọc/sửa bản nháp/ảnh của Creator khác cùng Site. Floor vẫn có một draft duy nhất; không tự nhận floor đã có draft của người khác. Admin giữ quyền cộng tác floor hiện có, không bị hạ quyền; SiteManager chỉ quản lý map/floor trong Site có membership active + CanEditDrafts. Creator/SiteManager không có quyền WayMark CRUD hoặc Email/test toàn cục.

Publish đòi quyền riêng **`SitePublisher:<SiteId>`**, do operator cấp trong Identity, cùng Creator/membership/owner. Role publisher một mình không cho phép truy cập author API. Creator có membership chỉ sửa được, không tự publish đại diện bệnh viện; email verified không cấp quyền. SiteManager được publish trong Site đã được ủy quyền; Admin giữ hành vi cũ. Không có HTTP API đăng ký/tự cấp các role này.

- Dùng RunId đã được chốt trong phạm vi phê duyệt. Sau approval, command `bootstrap` tạo hai app accounts mới `wm-core3-<RunId dạng N>-a/b`, email `<username>@example.invalid`; hai ID trong private plan phải còn trống. Password lấy từ environment private/DPAPI, không command line/plan/Git; conflict dừng thay vì adopt/reset. Identity writes dùng transaction, sau commit ghi IDs vào private plan nằm cạnh thư mục images ngoài Git. Nếu ghi plan lỗi sau commit, giữ dữ liệu để review, không xóa hoặc retry mù. Chưa tạo các tài khoản đó trên SQL Server.
- Lấy chính xác hai IdentityUser.Id bằng kiểm tra được duyệt; chép sample plan ra ngoài Git và điền RunId, expected server, hai FloorId chưa có FloorMapDraft cùng Building/Site, hai ID/username, storage riêng `<RunId dạng N>\images` ngoài repo. Không mặc định ID 1/10/11 trong SQL thật.
- Chỉ khi được duyệt các thay đổi này, đặt `writesApproved=true` và `creatorScopeAcknowledgement` đúng câu trong `ReadinessPlan.CreatorAcknowledgement`. Approval plan chứa trường Admin cũ sẽ bị từ chối, không được tự đổi sang consent mới.
- `grant` không tạo/reset/adopt account: kiểm tra cả ID, username và email test; không bật lại membership đã bị vô hiệu hóa. Cả A/B chỉ nhận Creator + membership; **chỉ A** có SitePublisher của đúng Site. Từ chối role khác/Admin/SiteManager hoặc B đã có publisher, không tự gỡ role. Role/user-role và membership dùng chung transaction hai DbContext. Lỗi trước commit rollback toàn bộ; rerun grant đã đủ quyền không tạo membership trùng. Không tự thu hồi quyền sau test; đó là approval riêng.

```powershell
# CHỜ PHÊ DUYỆT. Connection lấy từ nguồn cục bộ an toàn, không chứa trong plan.
# WAYMARK_CORE3_SETUP_SQL: provisioning principal, explicit WayMarkDatabase, Encrypt=True, TrustServerCertificate=False, timeout <=10s.
dotnet run --project tools/CoreSqlReadiness/CoreSqlReadiness.csproj -- grant D:\project\WayMark '<PRIVATE_PLAN.json>' --execute-approved
```

Command tạo hai accounts (chỉ sau duyệt, sau đủ migrations và private plan; không chạy trong giai đoạn chuẩn bị):

```powershell
dotnet run --project tools/CoreSqlReadiness/CoreSqlReadiness.csproj -- bootstrap D:\project\WayMark '<PRIVATE_PLAN.json>' --execute-approved
```

## 5. SQL E2E — chuẩn bị, chưa chạy

Mặc định `WAYMARK_CORE3_RUNTIME_SQL` vẫn yêu cầu target/actual server đúng, Encrypt=True, certificate validation và không có sysadmin/CONTROL/DDL/quyền ghi graph legacy. Phương án local Sprint 6 mới cho phép giữ Windows identity/sysadmin hiện tại **chỉ sau khi duyệt gói A–E**: private plan cần `localDevelopmentSysadminRuntimeExceptionApproved=true`, `expectedWindowsIdentity` khớp ORIGINAL_LOGIN, server là máy local và source mặc định; Windows auth bắt buộc, API child Development/loopback. Đây không phải least privilege hoặc production setup; kiểm tra fingerprint phát hiện nhưng không ngăn mọi thao tác SQL mà sysadmin có thể làm. Không tạo/grant SQL principal hay đổi quyền Windows account hiện có.

TLS exception có flag **riêng**, mặc định false: `localDevelopmentCertificateExceptionApproved=true`, chỉ local Windows auth/approved RunId, không remote/SQL auth/Encrypt=False. SELECT actual target, session identity, auth_scheme/net_transport/encrypt_option trước write; TCP/Named pipe phải báo encryption, Shared memory có thể không có encryption mạng và được ghi rõ chỉ trong ngoại lệ local. Không đổi trust store, firewall, execution policy hoặc persist ngoại lệ vào app config. Default modes vẫn từ chối các ngoại lệ chưa duyệt. Xem [phạm vi Sprint 6 chờ duyệt](../core-sprint6/ApprovalScope.md).

`WAYMARK_CORE3_A_PASSWORD`, `WAYMARK_CORE3_B_PASSWORD` được nhập bằng nguồn riêng của terminal/process; không in, không ghi plan, không truyền lên command line. Password login và setup connection không chuyển tiếp sang child API. Runtime SQL connection được pin vào child environment, **không sửa appsettings/User Secrets**.

```powershell
# CHỜ PHÊ DUYỆT. Build source đã review trước; chưa chạy trong sprint này.
dotnet build WayMark.Api/WayMark.Api.csproj
dotnet run --project tools/CoreSqlReadiness/CoreSqlReadiness.csproj -- e2e D:\project\WayMark '<PRIVATE_PLAN.json>' --execute-approved
```

Harness kiểm tra đủ migration trước mọi write, từ chối floor đã có draft hoặc storage có file, pin child API loopback port riêng, không override Kestrel endpoint khác nếu có, không ghi vào storage đang dùng. Quota child: 128 MiB/20 objects, 4 ảnh/tầng, 20 revision/tầng. File/quota/ACL thực tế vẫn cần nghiệm thu trên máy khi được duyệt.

Workflow: login A/B thật → 2 floor drafts → 2 ảnh PNG/JPG → Save/Load → project/QR/publish → Guest snapshot/images/checksum/route 13 m → B save/publish/revoke 403 → Guest private 401 → private edit/concurrency 409 → restart child API → reload private/public/images → revoke 410 → so SHA256 graph legacy, Identity, membership và migration histories trước/sau runtime (baseline sau bootstrap/grant được duyệt). Tuyến từ snapshot dùng Dijkstra hiện có; không gọi legacy POST /api/routes cho project custom.

Các ID test ghi sớm vào `waymark/build/core-sql-evidence/<RunId>/steps.log`; kết quả chứa graph test/checksum/public QR, không JWT/password. Lỗi giữ nguyên dữ liệu và file để review, không DELETE/Down/cleanup SQL hoặc tự resume. Tool chỉ dừng process API do chính nó tạo; không dừng API khác. Không dùng output fixture như bản đồ bệnh viện đã xác minh.

## 6. Backup ảnh / khôi phục / downtime

Để có điểm khôi phục nhất quán: ngừng API ghi trong cửa sổ được duyệt, backup SQL, sao chép toàn bộ immutable image objects + manifest của đúng root, đối chiếu asset count/SHA256. Không chỉ backup SQL và quên ảnh; không xóa object đang có reference. Bảo vệ backup bằng ACL tương ứng, lưu cấu hình root riêng khỏi Git.

Lỗi migration: stop client ngay, đọc history (mỗi migration có transaction/commit riêng), không chạy Down tự động. Ưu tiên forward fix đã review; restore SQL + bộ ảnh cùng mốc chỉ khi có phê duyệt phục hồi riêng, vì có thể mất thay đổi sau backup. Không hứa TRY/CATCH/XACT_ABORT bắt mọi lỗi compile/recompile hoặc mất kết nối.

Chưa đo downtime SQL thật. Dự trù cửa sổ 10–20 phút cho backup, gate, apply, verify trên dataset nhỏ; thời gian DDL/lock/IO cần đo và có thể vượt dự trù. Dừng ghi suốt cửa sổ; không cam kết zero downtime.

## 7. TLS diagnosis cập nhật Sprint 5 — chưa thay cấu hình máy

- `sqlcmd` đang dùng là **ODBC utility 16.0.1000.6**, lỗi kết nối chỉ ra **ODBC Driver 17**; ODBC 18 cũng đã cài nhưng không vì thế mà launcher tự dùng driver 18. `-N` yêu cầu encryption; không có `-C` nên vẫn xác minh chứng chỉ.
- DI/config offline bằng **Microsoft.Data.SqlClient 6.1.6** xác nhận effective connection `Encrypt=True; TrustServerCertificate=True`. Audit đọc được không phải bằng chứng trust chain hợp lệ: connection này đã được cấu hình bỏ kiểm tra certificate. Không đổi cấu hình ứng dụng/secret trong Sprint 5.
- Registry SQL instance `MSSQL16.MSSQLSERVER`: Certificate binding rỗng, ForceEncryption=0; LocalMachine/My hiện không có certificate. Đây là dấu hiệu SQL đang dùng fallback tự sinh, **chưa lấy được certificate thực trên wire để khẳng định subject/issuer/SAN/validity**. ERRORLOG đọc bị từ chối; event query không trả certificate metadata. Không thay ACL để đọc tiếp.
- `sqlcmd -N` với `LAPTOP-PFRPMR3O` thay `.` vẫn thất bại ở trust chain. Thay hostname không tự sửa CA trust; còn phải kiểm tra SAN/name sau khi chain được giải quyết.

Lệnh offline an toàn, không mở SQL connection:

```powershell
dotnet run --project tools/CoreVerificationAudit/CoreVerificationAudit.csproj -- D:\project\WayMark --tls-config
```

Đã thêm `scripts/Test-CoreSqlTls.ps1`: diagnostic read-only, `-N` bắt buộc, expected actual server + WayMarkDatabase, timeout hữu hạn, không retry giảm bảo mật. Syntax parse đạt nhưng chạy file bị Windows execution policy chặn; **chưa chạy thành công launcher này**, không đổi execution policy hoặc dùng Bypass. Có thể dùng lệnh native SELECT-only đã được review trong terminal cho phép; không chạy migration launcher để thử TLS.

**Phương án ưu tiên, cần operator phê duyệt thay đổi máy:** cấp/bind certificate phù hợp SQL Server và DNS/SAN hostname, cấp private-key ACL cho SQL service, thiết lập đúng CA trust trên client bằng quy trình được duyệt, review thời gian restart dịch vụ. Sau đó diagnostic dùng hostname đúng + Encrypt=True + TrustServerCertificate=False, xác minh SELECT/actual server và encrypt_option; chỉ khi đạt mới xét gate migration. Chưa cài certificate, đổi trust store hoặc restart SQL Server.

**Ngoại lệ Development-only nếu chưa có CA:** chỉ đề xuất cho native SELECT diagnostic trên đúng instance cục bộ/WayMarkDatabase, vẫn mã hóa nhưng tạm tin certificate mà không xác minh (`-C`). Có nguy cơ giả mạo server/MITM; không áp dụng LAN/production hoặc launcher migration, không persist vào config. **Chưa được duyệt, chưa thực hiện**; người dùng phải đồng ý phạm vi cụ thể trước khi dùng. Không tắt encryption.

Nguồn chính thức: [SQL certificate validation](https://learn.microsoft.com/en-us/troubleshoot/sql/database-engine/connect/error-message-when-you-connect), [SQL encryption certificate configuration](https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/configure-sql-server-encryption), [sqlcmd flags](https://github.com/MicrosoftDocs/sql-docs/blob/live/docs/tools/sqlcmd/sqlcmd-utility.md). Không coi đề xuất TLS là quyền thay đổi máy hoặc quyền ghi SQL.
