# Core SQL Readiness Sprint 3 — 24/10/2026

**GO cho source, preview và kiểm thử cô lập. SQL Server E2E: PENDING / WAITING FOR USER APPROVAL.** Không chạy grant/e2e trên SQL Server, không backup, không apply migration và không tạo database thứ ba.

## A. Kiến trúc giữ nguyên

Đã đối chiếu lại bằng công cụ SELECT-only tại `2026-10-24 00:46:51 UTC` (07:46:51 Việt Nam): cả hai context vẫn dùng **WayMarkDatabase** trên instance mặc định `.`, history map `__EFMigrationsHistory`, Identity `__AuthMigrationsHistory`. WayMarkAuthDatabase ONLINE, legacy đối với backend hiện tại. Không đổi connection string, JWT, Identity hoặc SMTP.

Trạng thái vẫn như Sprint 2: map history mới có hai migration 18/10; Auth history một migration; chưa có 8 bảng draft/published/membership; 5 user trong DB active, 0 role/user-role. Graph cũ 1 Site/1 Building/2 Floor/7 Node/10 Edge/3 WayMark. Managed image storage Development vẫn Disabled, chưa có root. Windows SQL principal hiện tại vẫn sysadmin. Không truy xuất username/email/hash/token của người dùng thật.

## B. Migration và artifacts thực tế

Thứ tự, chỉ cho **WayMarkDbContext / WayMarkDatabase / __EFMigrationsHistory**:

1. `20261020094848_AddMapDraftFoundation`: FloorMapDrafts, FloorMapDraftRevisions, FloorMapImageAssets, SiteMapMemberships. Guid/surrogate PK, revision `(DraftId,Version)`, FloorId unique, membership `(SiteId,UserId)` unique, storage key unique, FK Restrict, CHECK version/status/MIME/bytes/dimensions/pixels.
2. `20261020101304_BindMapImagesToDrafts`: unique alternate key FloorMapDrafts.FloorId và FK image.FloorId → draft.FloorId.
3. `20261023063955_AddPublishedMapProjects`: MapProjects, MapPublications, MapPublicationImages, MapNodeQrs; project owner/local-id unique; version/publication composite PK/FK; token unique và filtered unique active QR; version CHECK, FK Restrict.

Không sửa migration/snapshot/entity. Nullable image reference và PublishedVersion được giữ; cột bắt buộc do service cung cấp, không giả định SQL có default cho các cờ/version. Không thêm Identity vào map context; không ALTER/DROP/ghi dữ liệu vào graph cũ.

Đã tạo bằng **EF Core SQL Server IMigrator.GenerateScript**, offline, không EF CLI factory/connection:

- [SQL chuyển tiếp](database/core-sprint3/PendingMapMigrations.review.sql): 199 dòng, 3 batch.
- [SQL idempotent](database/core-sprint3/PendingMapMigrations.idempotent.review.sql): 355 dòng, 3 batch.
- [Manifest SHA256](database/core-sprint3/review-manifest.json), [approval plan mẫu](database/core-sprint3/approval-plan.sample.json).
- [Runbook cụ thể: backup, launcher, grant, E2E, rollback](database/core-sprint3/README.md).

Mỗi script có 8 CREATE TABLE, 3 INSERT **migration history**, 0 DROP/TRUNCATE/DELETE/UPDATE dữ liệu nghiệp vụ. Chỉ ALTER bảng draft mới để thêm constraint/FK. Mỗi batch kiểm tra actual server + database + baseline; session mới không có transaction/implicit transaction; client phải fail-on-error. Cần cấp session context trong launcher đã review, không chạy raw file tùy ý.

SQL Server provider đã kiểm tra model/snapshot, SQL generation thường/idempotent, indexes, additive operations. Đây **không phải thực thi SQL Server**; chưa nghiệm thu DDL, lock, collation hoặc concurrency SQL Server thật. Đối chiếu SELECT chưa thấy các tên bảng mới xung đột và khóa hierarchy int phù hợp. Idempotent không sửa schema drift hoặc history giả.

## C. Rủi ro cụ thể

- **High, chưa triển khai:** runtime hiện có sysadmin. Harness mới từ chối sysadmin/CONTROL/DDL, server-management roles hoặc quyền ghi graph legacy/roles/membership; cần principal giới hạn được duyệt. Không tự cấp login/grant SQL.
- **High, cần phê duyệt quyền:** Admin là quyền toàn cục đối với WayMark CRUD, không phải chỉ map test. Plan yêu cầu operator xác nhận rõ; không tạo role Creator mới hoặc nâng quyền theo tên `admin`.
- **Medium:** DB hiện hữu dùng chung, namespace test không phải isolation database. Hai Floor phải được chọn rõ và chưa có draft; harness không overwrite draft hoặc auto resume/cleanup. Khi test lỗi sẽ còn dữ liệu test cần review.
- **Medium:** mỗi migration có transaction riêng. Migration sau lỗi không đồng nghĩa migration trước rollback. Down có xóa bảng mới, không dùng làm rollback mặc định sau khi có dữ liệu.
- **Medium:** backup history 18/10 không chứng minh backup hiện tại khôi phục được; chưa tạo hoặc verify backup mới. Filesystem và DB không atomic; cần bộ backup SQL + objects/manifests cùng mốc.
- **Low:** snapshot JSON được validator/service kiểm tra; database không có FK từ từng GUID trong JSON tới node. Không thay đổi mô hình production graph để ép liên kết.

## D. Storage readiness

Giữ nguyên provider đã có: raw PNG/JPG → signature/codec thật → giới hạn 10 MiB/8192 px/32 MP → SHA256 và immutable server key → private managed file + manifest. Không lấy filename client làm đường dẫn, không public static URL và không lưu Base64 vào SQL. Tests hiện hữu đã kiểm tra traversal, sai MIME/extension, quota, corrupt/missing object, storage disabled và restart bằng filesystem tạm thật.

Thêm `WayMark.Api/appsettings.Development.storage.example.json`: **template không tự load**, 128 MiB/50 objects, 8 ảnh và 32 MiB mỗi tầng, 20 revision/tầng. Chọn root ngoài repo thay vì nới provider để ghi trong Git. Chưa tạo root Development hoặc sửa config thực. Sau approval mới merge cấu hình cục bộ, giữ nội dung Development/User Secrets đang có, cấp ACL cho đúng runtime account và xác minh dung lượng/quyền.

Harness dùng root riêng `<RunId>/images` ngoài Git, từ chối root có file/link hoặc trùng storage hiện hành; child API 128 MiB/20 objects, 4 ảnh/tầng. Hai ảnh fixture PNG/JPG có checksum khác nhau; kiểm thử save/load và host restart kiểm tra đúng ảnh từng floor.

Map aggregate kiểm tra owner + Admin + active Site membership; public download chỉ lấy asset thuộc đúng publication/version. Private floor-image API vẫn **Site-scoped Admin** theo foundation, không phải owner-exclusive; không gọi đó là ảnh riêng tuyệt đối giữa hai Admin cùng Site. Guest không đọc được private image/draft; binary asset cũ không bị overwrite.

## E. Creator access đã chuẩn bị

`tools/CoreSqlReadiness` có `grant` cho **hai tài khoản test đã tồn tại, ID và tên/email khớp chính xác namespace RunId được duyệt**. Không tạo account, không reset password hoặc adopt tài khoản bất kỳ. Không tái kích hoạt membership bị hạn chế/thu hồi.

Hai context dùng chung transaction cho Admin role nếu thiếu, user-role và membership. Lỗi ghi membership trong SQLite đã được chứng minh rollback cả role/user-role, giữ hai account và membership khác nguyên trạng. Rerun grant đã đủ quyền không tạo trùng. Lỗi commit/mất kết nối có thể không xác định kết quả: dừng để kiểm tra, không tuyên bố rollback tuyệt đối hoặc tự retry.

Sample plan mặc định `writesApproved=false`, UUID/ID rỗng. CLI cần `--execute-approved`, plan hợp lệ, acknowledgement quyền Admin, connection riêng, actual server/database/history đúng. Các flag là chốt chống chạy nhầm của operator, **không thay thế phê duyệt của người dùng**. Không thêm API cấp quyền/startup seed.

## F. SQL E2E harness và giới hạn bằng chứng

Workflow HTTP dùng lại production AuthController/UserManager/JWT, DTO/service/upload/public API và Dijkstra hiện có. Không sửa Routing API, QR, Flutter hoặc thuật toán.

Đã chạy workflow trên **SQLite file + managed filesystem thật, TestServer**:

- Identity login A/B thật; cùng Site membership nhưng B sửa/publish/revoke map A → 403.
- Tạo hai floor draft, upload PNG/JPG, Save/Load project 0 Room, Node destination/Landmark/transition, tạo QR stable GUID, publish.
- Guest private draft/image → 401; unpublished → 404; public map/images đúng version/checksum → 200; public QR không cho quyền write.
- Private edit không đổi snapshot cũ; stale expected version → 409.
- Dispose/start test host mới với SQLite/image root cũ, login lại: private project/revision và public snapshot/images còn nguyên.
- Dijkstra trên snapshot tải về ra 13 m qua hai tầng, chiều ngược không có route; QR revoke → 410.
- Không sửa các bản ghi graph legacy trong fixture.

Sau approval, command `e2e` sẽ kiểm tra SQL runtime target/quyền/history, chạy child API loopback được pin connection/root, thực hiện cùng HTTP workflow, restart **child process do nó tạo**, kiểm tra SHA256 6 bảng graph legacy trước/sau, lưu IDs/evidence, giữ dữ liệu test. Không load cấu hình DB thứ ba hoặc chạy migration. Child launcher/permission queries đã compile và review; **chưa chạy trên SQL Server thật**. Restart TestServer trong test không được coi là bằng chứng restart SQL-backed process.

## G. Files và regression

File mới/sửa riêng Sprint 3:

- `tools/CoreSqlReadiness/`: csproj, Program, ReadinessPlan, MigrationPreview, TestCreatorAccess, SqlE2eWorkflow.
- `WayMark.Api.Tests/CoreSqlReadinessTests.cs`; mở rộng `MapDraftTestHost.cs` bằng tùy chọn Identity (mặc định cũ giữ nguyên); csproj thêm project reference tool, giữ dependency SQLite có sẵn.
- `WayMark.Api/appsettings.Development.storage.example.json`.
- `docs/database/core-sprint3/`: hai SQL preview, review manifest, approval sample, README.
- Báo cáo này; Master Plan v1.4 và archive v1.3.

| Kiểm tra | Kết quả |
|---|---|
| dotnet build backend/tool | Đạt, 0 warning/error |
| dotnet test toàn bộ | **301/301**, gồm 18 tests/cases mới |
| flutter analyze --no-pub | Không lỗi |
| flutter test --no-pub --reporter expanded | **263 pass / 1 Web-only skip** ở lần chạy lại |
| flutter build apk --debug | Đạt, main.dart; warning Java/Gradle native access hiện hữu |
| git diff --check | Đạt; LF/CRLF warnings hiện hữu |

Lần Flutter test đầu: Windows Application Control chặn flutter_tester cho file AI test; 239 pass/1 skip nhưng suite thất bại khi load file đó. Chạy lại **cùng lệnh bình thường**, không đổi security policy/source Flutter, đã đạt toàn bộ. Chưa xác định vì sao lần chặn đầu không lặp lại. Không che giấu lần thất bại; logs cả hai nằm trong `waymark/build/core-sql-readiness-evidence/` (ignored).

Không thử lại camera thủ công trong Sprint 3; giữ evidence VirtualScene Sprint 2. Không gọi LM Studio/AI Phase 2, không sửa Zoom/Pan. Gradle, Windows generated, AI source có SHA256 không đổi so baseline. Không sửa các thay đổi Codex/Kilo có sẵn, không commit/push/reset/clean.

## H/I. Approval gate và bước nhỏ nhất

**Mọi bước sau đều CHƯA THỰC HIỆN và cần phê duyệt cụ thể:**

1. Backup FULL mới WayMarkDatabase (đề nghị cả Auth legacy), đường dẫn/ACL/dung lượng, HEADER/FILELIST/VERIFY và phương án restore rehearsal không đè DB hiện tại. Không coi có .bak là đủ; [VERIFYONLY không kiểm tra cấu trúc dữ liệu đầy đủ](https://learn.microsoft.com/en-us/sql/t-sql/statements/restore-statements-verifyonly-transact-sql?view=sql-server-ver16).
2. Cửa sổ bảo trì và apply **đúng ba migration trên WayMarkDatabase**, bằng artifact/hash/launcher đã review. Không apply Auth hoặc WayMarkAuthDatabase. Không dùng factory/launcher MapDraftE2E cũ hoặc sửa history tay.
3. Chọn/cấp SQL runtime principal tối thiểu và storage root/ACL riêng. Không dùng Windows sysadmin cho harness runtime; không sửa JWT/connection string hiện hành để né guard.
4. Đăng ký hai test account có namespace RunId, xác nhận ID/tên/email/Site/hai Floor cụ thể và cấp Admin + membership. Không nâng quyền account thật.
5. Cho phép các API test ghi drafts/revisions/assets/projects/publications/QR, private edit và revoke; cho phép start/restart child API và ghi ảnh test ở root đã duyệt. Không cleanup SQL tự động.
6. Mọi restore/thu hồi quyền/dọn dữ liệu sau test là approval riêng, không chạy Down/DELETE tùy ý.

**Bước nhỏ nhất ngay sau đây:** chốt backup mới và target/schema/script hash; chỉ sau khi backup được nghiệm thu và người dùng duyệt mới apply ba migration trên DB hiện hữu. Runbook đã có lệnh preview an toàn và các command ghi được đánh dấu chờ duyệt. SQL E2E vẫn **PENDING**, không tạo DB thứ ba.
