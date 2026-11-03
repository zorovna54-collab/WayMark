# Core Integration Sprint 1 — 23/10/2026

## Kết quả và phạm vi

Không có `docs/WayMark_Master_Plan.md`; đã đọc tài liệu hiện hữu `WayMark_Master_Plan_v1.1.md`. Giữ Image-first, Node-first, Room legacy, JSON v2/v3, graph nhiều tầng và AI optional. Không sửa Zoom/Pan hoặc AI.

Đã nối source theo vertical slice:

1. Builder local → ghép tầng với hierarchy server đã được cấp quyền → upload ảnh bằng storage hiện có → lưu project draft nhiều tầng.
2. Chọn node GUID ổn định → server cấp QR ngẫu nhiên → preview/export PNG → publish snapshot đã lưu.
3. Visitor không cần JWT → resolve QR → tải snapshot/ảnh đúng version → Search node destination → Preview → Navigation từng bước.
4. QR trong Navigation đối chiếu map/version/floor/node; cùng tuyến dùng quy tắc QR hiện có; ngoài tuyến yêu cầu xác nhận trước khi Dijkstra tính lại trên cùng snapshot. Lỗi/hủy không đổi tuyến/tiến độ.

**GO cho demo cô lập; chưa nghiệm thu trên SQL Server và chưa triển khai Internet.**

## Những phần đã tái sử dụng / khoảng trống đã sửa

- Tái sử dụng Site/Building/Floor, `IDraftSiteAccess`, JWT/AdminOnly, `FloorMapImageAsset`, codec/checksum/private managed storage, file gateway Android/Web, Scanner/camera lifecycle, LocalMapProject v3, Dijkstra local, Search/Preview/Navigation/floor canvas.
- Draft server cũ chỉ theo một tầng, chưa lưu `displayName`, `searchableAsDestination`, `landmarkNote`: đã bổ sung DTO/validator/mapper tương thích ngược, không thêm cột node nghiệp vụ.
- Local project chưa có aggregate server, publication hoặc QR public: bổ sung 4 bảng riêng, không copy vào `NavigationNodes`, `NavigationEdges` hoặc sửa mapping WayMarks cũ.
- Native Android file-save luôn dùng MIME JSON: sửa đúng MIME cho JSON/PNG/JPG để QR PNG thực sự lưu như ảnh.
- Cache liên kết server giữ expected version và so sánh ảnh bằng bytes: mở lại Builder để sửa rồi lưu vẫn dùng cùng map, không tạo map mới hoặc upload lặp ảnh không đổi. Xung đột phải tải lại/giữ local, không ghi đè tự động.

## Quyền và quy tắc version

- Creator trong slice này là **Admin đã có active SiteMapMembership/CanEditDrafts**, đồng thời là `MapProject.OwnerId` từ subject JWT do server xác thực. Không tự tạo role Creator, tài khoản, membership hoặc nâng quyền.
- Các floor phải thuộc cùng Building/Site được server suy ra từ hierarchy. Đổi mapId, SiteId giả hoặc giả role trong client không cấp quyền.
- Map project private chỉ chủ sở hữu có scope hợp lệ được đọc/sửa/publish/quản lý QR; Creator khác cùng Site cũng không có quyền project này. Image upload/read private vẫn giữ chính sách Site-scoped Admin của foundation, không trở thành endpoint public tùy ý.
- Save draft không công khai và không sửa publication. Save/create giống hệt có thể trả lại cùng bản ghi; không tạo phiên bản vô ích. Save khác dùng optimistic concurrency.
- Publish cần xác nhận công khai, đầy đủ ảnh tải được, cấu trúc/ID/transition đúng, khoảng cách mét hợp lệ, ít nhất một destination và một QR start active có đường có hướng đến đích. Không chứng nhận lối đi thực địa hay xe lăn.
- QR payload `WMQR1:<64 hex>` do server sinh từ 32 byte random; không chứa URL máy Windows, JWT hoặc graph. Có thể import URL `/q/{token}` nhưng app chỉ lấy token và gọi API đã cấu hình, không theo host của URL quét.
- QR **ghim vào saved draft version/publication version**, không tự remap sang bản mới. Sau sửa draft, tạo QR cho version mới trước khi publish. QR cũ vẫn trỏ snapshot cũ cho đến khi thu hồi; không âm thầm đổi node/tọa độ. Revoke → resolve 410.
- Public DTO không trả owner, storage key/path, publishedBy, source-node/WayMark provenance. Ảnh chỉ tải khi có FK `MapPublicationImages` của đúng map/version; checksum/length được kiểm tra lại. File cũ vẫn được giữ và FK Restrict bảo vệ metadata đang tham chiếu.

## API

| Method | Path (prefix `/api`) | Quyền |
|---|---|---|
| GET, POST | `/admin/map-projects` | JWT Admin; list của owner; create kiểm tra Site scope |
| GET, PUT | `/admin/map-projects/{id}` | Owner + Admin + active Site scope |
| POST | `/admin/map-projects/{id}/publish` | Như trên; expectedVersion + confirmPublic |
| GET, POST | `/admin/map-projects/{id}/qrs` | Như trên; tạo theo floorKey/nodeId GUID |
| POST | `/admin/map-projects/{id}/qrs/{qrId}/revoke` | Như trên |
| GET | `/public/qr/{token}` | Anonymous, chỉ QR active đã publish |
| GET | `/public/maps/{id}/versions/{version}` | Anonymous, snapshot đã publish |
| GET | `/public/maps/{id}/versions/{version}/images/{assetId}` | Anonymous, đúng ảnh của publication |

Create/save gửi `name`, `content: {id, floors:[{id, floorId, name, code, content: MapDraftContent}], links:[...]}`; ảnh là assetId, không Base64 trong SQL. PUT thêm `expectedVersion`. Publish gửi `{expectedVersion:1, confirmPublic:true}`. Tạo QR gửi `{expectedVersion:1, floorKey:"<floor UUID>", nodeId:"<node UUID>"}`.

Resolve trả `{mapId, version, floorKey, nodeId, mapName, nodeName}`. Map public trả `{mapId, version, name, content, publishedAt, verifiedForPatientUse:false}`. HTTP: 400 dữ liệu/publish chưa hợp lệ; 401 JWT thiếu/sai; 403 owner/scope sai; 404 không có tài nguyên public; 409 version conflict/chưa publish; 410 QR thu hồi; 503 DB/storage chưa khả dụng. Không trả stack trace.

## SQL thực tế: chỉ đọc

- Effective Development (base → Development → User Secrets → environment nếu có): server `.`, database `WayMarkDatabase`, Windows integrated authentication. Launch profile `http` dùng Development, port 5121.
- Cả `WayMarkDatabase` và `WayMarkAuthDatabase` **ONLINE**. Hai DbContext runtime đều dùng `ConnectionStrings:WayMarkDatabase`, provider SQL Server; history graph `__EFMigrationsHistory`, Identity `__AuthMigrationsHistory`. Không fallback sang WayMarkAuthDatabase.
- Trong WayMarkDatabase: graph đã có `20261018022742_CreateWayMarkSchema`, `20261018053754_AddNavigationSchema`; Identity có `20261010032404_CreateAuthSchema` và các AspNet tables.
- **Chưa có** FloorMapDrafts/Revisions/ImageAssets/SiteMapMemberships ở DB này. Hai migration foundation vẫn pending. Tài khoản Windows hiện kết nối có sysadmin; không nên dùng quyền này làm runtime khi triển khai thật. Chưa thay quyền hay connection string.
- Không ghi SQL Server, không chạy database update, không seed, không tạo database hoặc khởi chạy production startup để thử tính năng mới.

### Migration chờ review/áp dụng

Sau migration graph hiện có, cần theo thứ tự:

1. `20261020094848_AddMapDraftFoundation`
2. `20261020101304_BindMapImagesToDrafts`
3. **Mới:** `20261023063955_AddPublishedMapProjects`

Migration mới được EF Core local tool 10.0.12 sinh với factory E2E chỉ phục vụ design-time; không mở kết nối SQL để tạo schema. Up chỉ CREATE 4 bảng `MapProjects`, `MapPublications`, `MapPublicationImages`, `MapNodeQrs`, index, FK Restrict và check constraints. IsActive QR là concurrency token để publish thất bại nếu QR bị revoke đồng thời. Designer/snapshot đã đối chiếu model bằng test SQL Server provider, không thêm Identity.

Down của migration mới DROP chính 4 bảng mới theo thứ tự phụ thuộc; **không chạy Down** và không rollback trên dữ liệu cần giữ. Không sửa migration cũ. Không có ALTER/DROP/INSERT graph production trong Up mới.

## Kiểm thử và evidence

- `dotnet build WayMark.Api/WayMark.Api.csproj`: đạt, 0 warning/error.
- `dotnet test WayMark.Api.Tests/WayMark.Api.Tests.csproj`: **282/282** đạt. 18 kiểm tra mới gồm API signed JWT, owner A/B kể cả cùng Site, Guest private/public, publish validation, revoke, immutable versions, idempotency, SQL Server migration metadata và SQLite/file storage restart.
- `flutter analyze`: sạch. `flutter test --reporter expanded`: **262 pass / 1 Web-only skip**; 16 test mới gồm mapper, 3 tầng 0 Room, HTTP/JWT, QR/pinned version/floor, reroute, hủy/lỗi/revoke không đổi tiến độ, Scanner→Search→Preview→Navigation với fake camera, cloud save tiếp tục bản đang sửa, reuse/upload ảnh và PNG MIME.
- `flutter build apk --debug`: đạt với entrypoint chính `lib/main.dart`; APK tại `waymark/build/app/outputs/flutter-apk/app-debug.apk`. `git diff --check`: đạt, chỉ có cảnh báo quy ước LF/CRLF hiện hữu.
- Android: real `MobileScannerController.analyzeImage` đọc đúng payload từ PNG tạo bởi `QrPainter`; document picker lưu `.png` và đã pull lại file 8041 bytes. Đây là native **giải mã file**, chưa phải camera quét QR vật lý mới.
- API thật: Kestrel loopback 5188 + SQLite file riêng + managed image files temp, được fixture tạo qua HTTP bằng JWT ký khóa random của test. Không dùng appsettings/User Secrets/Identity thật/SQL Server. Guest GET resolve/map/images thành công.
- Android Emulator gọi API này qua `10.0.2.2:5188/api`, nhập locator QR, tải 2 tầng/0 Room, Search → Preview **13 m** → manual Navigation → chuyển G/L1 → Arrival, Landmark đúng tầng. Ảnh fixture bốn màu là dữ liệu kiểm thử, không phải ảnh bệnh viện đã khảo sát.
- Chưa nghiệm thu Creator login/save/publish trên SQL Server thật, camera quét vật lý QR mới, Android LAN thật, HTTPS/public hosting, App Links/web fallback. Widget tests dùng camera/HTTP fake được phân biệt với API/socket/file/native tests ở trên.
- Evidence và logs nằm trong `waymark/build/core-integration-evidence/` (Git ignore): `android-public-search.png`, `android-public-navigation.png`, `android-public-level1.png`, `android-public-arrival.png`, `android-native-qr-decoder.png`, `exported-public-qr.png`.
- Khi chốt báo cáo, host demo không còn lắng nghe cổng 5188 và emulator đã ngắt kết nối. APK chính đã build, chưa xác nhận cài lại APK chính lên emulator sau phiên kiểm thử công cụ QR.

## Chạy lại demo an toàn

Terminal 1 tại repository root:

```powershell
dotnet run --project tools/CoreIntegrationDemo/CoreIntegrationDemo.csproj -- D:\project\WayMark\waymark\build\core-integration-evidence
```

Host chỉ lắng nghe loopback; database/ảnh là fixture trong thư mục temp có owner marker. Không đọc cấu hình SQL Server. Ctrl+C dừng host và giải phóng tài nguyên fixture. Public QR/map fixture thay đổi mỗi lần khởi chạy, không dùng QR cũ sau khi tạo lại.

Terminal 2:

```powershell
cd D:\project\WayMark\waymark
$qr = (Get-Content build/core-integration-evidence/public-qr.txt -Raw).Trim()
flutter run -d emulator-5554 -t tool/public_map_visitor.dart --dart-define=WAYMARK_API_BASE_URL=http://10.0.2.2:5188/api "--dart-define=WAYMARK_DEMO_PUBLIC_QR=$qr"
```

Entrypoint này gọi API HTTP thật, không nhúng graph/ảnh/token đăng nhập. Trong app chính, Login có nút Visitor công khai; Scanner mặc định cũng nhận QR mới. Builder có nút **Server / Publish / QR**. Không dùng Admin demo UI chưa đăng nhập làm bằng chứng quyền ghi.

## File sprint (ngoài các thay đổi có sẵn)

- Backend: `Contracts/MapDraftDtos.cs`, `Contracts/PublishedMapDtos.cs`, `Controllers/MapProjectsController.cs`, `Models/PublishedMaps.cs`, `Data/PublishedMapModel.cs`, `Data/WayMarkDbContext.cs`, `Services/MapDrafts/{MapDraftValidator,MapDraftService,MapDraftRegistration,MapProjectService}.cs`, migration mới + Designer + snapshot.
- Backend tests: `PublishedMapTests.cs`, `MapDraftModelTests.cs`, `AdminAuthorizationTests.cs`, `E2ESafetyTests.cs`, `MapDraftTestHost.cs`, `EvidenceAccess.cs`; `tools/CoreIntegrationDemo/{CoreIntegrationDemo.csproj,Program.cs}` chỉ phục vụ demo cô lập.
- Flutter: `pubspec.yaml/lock` (+ qr_flutter 4.1.0, qr 3.0.2), `services/published_map_api_service.dart`, `features/admin/{draft_server_session,draft_map_editor,draft_map_editor_mobile,map_project_cloud_page}.dart`, `features/navigation/{local_map_navigation,manual_navigation,navigation_page}.dart`, `features/search/local_map_search_page.dart`, `features/route/route_preview_page.dart`, `features/scanner/{scanner_page,public_map_entry_page}.dart`, `features/auth/login/login_page.dart`.
- Android: `MainActivity.kt` chỉ thêm allowlist MIME và dùng MIME khi save, giữ code hiện có.
- Flutter tests: `published_map_test.dart`, `map_project_cloud_test.dart`, `fixtures/published_map_fixture.dart`, thêm PNG gateway test trong `android_map_builder_test.dart`; tools `public_map_visitor.dart`, `public_qr_export_check.dart`.

## P0 tiếp theo — cần phê duyệt

1. Chốt target database E2E riêng và backup, duyệt áp dụng cả 3 migration pending theo runbook preflight hiện có; chưa chạy trên hai DB được bảo vệ.
2. Cấu hình managed image root riêng ngoài repo + runtime principal quyền tối thiểu; backup/restore database cùng immutable image objects và manifest, không chỉ sao chép SQL.
3. Bootstrap **chỉ trong database test được duyệt** một Admin/Creator có membership cho Building/Floors hiện hữu. Không tự cấp quyền trên dữ liệu thật.
4. Chạy Creator UI Save/Load/Publish → in PNG → camera scan từ app chính trên dataset đã duyệt. Không cần AI. Giữ local offline Builder/Navigation làm dự phòng.

Chưa có onboarding Creator tự phục vụ, CRUD hierarchy, unpublish map, audit dashboard/quota/rate-limit production, public Internet hoặc web fallback. Snapshot public chỉ được xem là graph dữ liệu hợp lệ, không là chứng nhận an toàn bệnh viện.

Không commit/push/reset/clean; không sửa Gradle, Windows generated, Figma reference, JWT/connection strings hoặc AI Phase 1.
