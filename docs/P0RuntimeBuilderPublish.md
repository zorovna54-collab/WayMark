# P0 runtime Builder → Server → QR → Publish — 25/10/2026

Chốt kiểm tra tiếp tục **26/10/2026**: resume read-only trên cùng fixture đạt **13/13**, bao gồm Flutter Guest GET thật → Arrival; không tạo thêm dữ liệu SQL. API do harness mở đã dừng đúng process sau kiểm tra. Emulator hiện không kết nối; evidence camera dưới đây thuộc lần nghiệm thu 25/10.

## Nguyên nhân và bản sửa

1. `_projectCloud()` gửi bản sao project Builder; nhưng `_load()` trong `map_project_cloud_page.dart` thay bản sao đó bằng graph server. Bấm **Tải draft** của workspace v1 rỗng có thể làm **Cloud Local = 0/0** trong khi Builder phía sau vẫn 3/2. Regression tái hiện thất bại trước sửa, đạt sau sửa. Đây là đường lỗi đã chứng minh; không có log thao tác cũ để khẳng định người dùng đã đi đúng nhánh này.
2. Đọc lại **cùng project** giờ chỉ refresh document/version/bindings/checklist; giữ graph/ảnh local. Tải project khác cần xác nhận, không tự thay Builder. Tầng đang vẽ được đồng bộ vào project theo GUID trước khi clone/save; mismatch dừng, không tự tạo ID để chữa lỗi. Save vẫn upload → PUT project → GET đối chiếu graph/ảnh/identity.
3. `appsettings.Development.json` chưa tồn tại; `MapImages.Enabled` mặc định false. Lần bật trước chỉ ở environment của terminal đã dừng. Đã tạo file Development **Git-ignored**, chỉ chứa MapImages (không JWT/connection string/SMTP), dùng lại root Core Sprint 6, quota 128 MiB/20 objects. API thật không override MapImages đã upload và đọc lại được ảnh. Không thêm static URL: draft image vẫn JWT/owner/Site; Guest chỉ đọc ảnh thuộc published snapshot.
4. Bộ đếm cũ đếm `places.length`, không đếm searchable Node, nên “0 phòng” không có nghĩa thiếu điểm đến. Giờ hiển thị **Node • Edge • điểm đến**, Room legacy chỉ xuất hiện nếu có. Destination type không tự bật searchable; form nói rõ. Search/counter loại trùng chỉ khi nhãn và entrance GUID cùng khớp; giữ kết quả Room để bảo toàn chọn cửa có tuyến ngắn nhất. JSON v2/v3, Room và routing giữ nguyên.
5. Android có bản khôi phục JSON v3 trong app-private `noBackupFilesDir`, khóa theo scope tài khoản/API/project, ghi bằng AtomicFile; không lưu JWT. Sau restart, mở đúng map từ My Maps sẽ hỏi trước khi lấy bản local thay server. Cancel giữ server; không tự Save/Publish. Backup không thay thế export: chỉ coi đã ghi khi UI xác nhận; không bảo đảm thay đổi vừa nhập trước khi debounce/ghi hoàn tất hoặc khi uninstall/clear data. Bản graph đã mất trước khi cài hotfix chỉ khôi phục được từ file backup còn tồn tại.

## Kết quả có bằng chứng

### CODE / ISOLATED TEST

- Flutter targeted: **75/75 PASS**, analyze sạch. Có case Cloud 3/2 → đọc v1 rỗng, JSON v2/v3, recovery accept/cancel (memory fake), destination count/Search, multi-floor, QR/retry/navigation.
- Backend targeted: **77/77 PASS**, build 0 warning/error. Bao gồm Identity/JWT SQLite, managed filesystem thật, upload/read/restart/quota/failure, ownership/personal publish/immutable snapshots. Đây không thay thế SQL runtime.
- Android debug APK build đạt; không đổi Gradle/Windows generated. Recovery native đã compile; chỉ chứng minh lưu native thật nếu có evidence Android tương ứng.
- Logs: `waymark/build/qr-publish-hotfix/runtime-*.log` (ignored).

### API + SQL RUNTIME

Người dùng phê duyệt fixture qua chat, chỉ trên `LAPTOP-PFRPMR3O` / `WayMarkDatabase`, Windows Authentication local, encryption bật và ngoại lệ trust certificate Development đã duyệt. Đã tạo **đúng 2 account ứng dụng không email/không Admin**, 1 personal workspace/Site/Building/Floor, 1 ảnh, 3 node, 2 cạnh 5 m + 7 m, 1 QR và snapshot. Không tạo thêm workspace cho B. Password sinh trong bộ nhớ, không lưu/in; không đọc/in JWT secret.

- RunId: `1e116efce42c`; map `b86cbcbb-786e-4baf-8b33-29800ed6e417`; floor SQL `7`; snapshot/draft **v2**.
- Register/login: 200; workspace/image-owner/upload: 201; Save/GET: 200; QR Junction/Publish: 200. GET so sánh chính xác project ID/floor GUID/node GUID/edges/ảnh/searchable/mét.
- Guest draft: 401; B private/publish: 403; Guest resolve/snapshot/ảnh: 200, đúng QR node/floor và graph 12 m.
- Harness đầu hoàn tất 25 checks nhưng bước restart gặp transient port probe; đã dừng process thuộc harness. Không chạy lại tạo fixture. Tiếp tục bằng **resume read-only**: 13 checks PASS, gồm SQL persisted graph, API mới đọc snapshot/QR/ảnh, không Admin, migration history không đổi và Flutter Guest GET thật → Search → Preview → Navigation → Arrival.
- Authenticated private image trước restart 200. Sau restart đã đọc SQL content và Guest image 200; **không thử lại private image bằng token A sau restart**, vì token/password chỉ giữ trong bộ nhớ của harness đầu đã kết thúc. Không giả tạo login/token để che giới hạn này.
- Hai personal map cũ vẫn v1, 0/0, không bị ghi đè. Legacy `WayMarks`/`NavigationNodes`/`NavigationEdges` vẫn 3/7/10. Resume chỉ SELECT+GET, fingerprint legacy graph/Auth legacy không đổi trong phiên resume. Không tuyên bố có fingerprint trước/sau toàn bộ lần ghi đầu (giá trị trước chưa được lưu lại khi harness lỗi).
- Evidence: `waymark/build/p0-runtime-1e116efce42c/{results,resume-results,public-state}.json`, `flutter-live.log`, ảnh fixture/QR/navigation. Public state chỉ có resource IDs/QR công khai, không password/JWT.

### ANDROID EMULATOR REAL FLOW

- **PASS Guest camera VirtualScene → SQL public QR → Search → Preview 12 m → Navigation 5 m + 7 m → Arrival** trên AVD `Medium_Phone_API_37.0`, `emulator-5554`, APK chính. PNG được render bằng hàm Flutter QR thật từ payload của fixture SQL. Đưa PNG vào poster wall/table; cấp camera và dùng macro SDK `Walk_to_image_room`. Không nhập payload vào field, không dart-define QR, không `analyzeImage` hoặc fake capture.
- Ảnh thực từ ADB: `android-camera.png` (hộp quyền), `android-scanned.png` (camera frames thấy QR), `android-search.png` (đã đối chiếu QR, P0 Start), `android-preview.png` (12 m), `android-navigation.png` (chặng 5 m), `android-arrival.png` (Bước 3/3). Tất cả trong thư mục evidence RunId đã nêu. `live-sql-widget-navigation.png` vẫn là widget, tách riêng.
- Đây là camera pipeline thật của Emulator với ảnh VirtualScene, **không phải camera điện thoại vật lý/webcam**. Tiến độ từ bước 1 → 2 → 3 được nhấn thủ công, không timer/GPS.
- **Creator Save/Publish chính bản đồ người dùng trên Android còn cần nghiệm thu thủ công**: agent không biết mật khẩu của người dùng và không được ghi đè map cũ. SQL fixture đã chứng minh API persistence/Personal Publish; widget chứng minh thao tác Builder/Cloud. Không đồng nhất chúng với Creator đã bấm Save/Publish trên chính map cũ trong emulator.
- Recovery native đã build; accept/cancel đã test bằng memory boundary. Chưa thử force-stop/reopen một personal workspace đăng nhập trên Android để nghiệm thu ghi AtomicFile thực tế. Các tài khoản fixture có mật khẩu ngẫu nhiên chỉ trong bộ nhớ đã kết thúc; không reset password hoặc tạo thêm account.

## Chạy và nghiệm thu bản đồ của người dùng

1. Giữ JSON + ảnh của graph 3/2 trước khi restart/cập nhật APK. Không uninstall/clear data. Nếu backup v2, mở đúng personal map rồi import và xác nhận khi GUID tầng khớp.
2. API smoke chỉ lắng nghe loopback `127.0.0.1:5121`, dùng MapImages Development persistent và encrypted SQL local đã duyệt; hiện đã dừng sau lượt kiểm tra 26/10. Khi tự khởi động lại, chạy PowerShell dưới đây (không chạy thêm instance nếu cổng đang được dùng). Không cần bật MapImages lại mỗi terminal, không thay User Secrets/JWT/SQL quyền và không tắt encryption:

   ```powershell
   Set-Location D:\project\WayMark
   # Ngoại lệ trust chỉ trong terminal Development local đã được phê duyệt.
   $env:ConnectionStrings__WayMarkDatabase = 'Server=.;Database=WayMarkDatabase;Integrated Security=True;Encrypt=True;TrustServerCertificate=True'
   dotnet run --project WayMark.Api/WayMark.Api.csproj --launch-profile http
   ```
3. APK: `waymark/build/app/outputs/flutter-apk/app-debug.apk`; API Android `http://10.0.2.2:5121/api`; debug marker Cloud **QR-P0-20261025.3**.
4. Builder 3/2 → Server/Publish/QR → đọc cùng map phải vẫn **Local 3/2**, server cũ có thể 0/0. Save → GET phải xác nhận 3/2 + ảnh; lỗi không xóa local.
5. Chọn Junction/Entrance/Node hợp lệ → QR → Publish. Guest quét QR → tìm đúng searchable destination → route theo mét/hướng cạnh đã nhập. Không cần Admin hoặc migration.
6. Restart API và mở lại map; kiểm tra ảnh/graph/QR. Không dùng fixture trên để ghi đè bản đồ của người dùng.

Không apply History migration, không sửa WayMarkAuthDatabase, không reset/commit/push. Fixture được giữ để đối chiếu, không xóa. Công cụ `.NET` tại `tools/P0RuntimeSmoke` có gate riêng; không chạy lại chế độ tạo fixture nếu chưa có phê duyệt mới. `--resume-readonly <results.json>` chỉ đọc fixture đã có. Không đổi Execution Policy/Application Control; file PowerShell thử nghiệm bị policy chặn đã bỏ khỏi source của tác vụ.

## File trong bản sửa

- Flutter source: `features/admin/{draft_map,draft_map_editor,draft_map_editor_mobile,draft_map_editor_project,draft_recovery,map_project_cloud_page}.dart`, `features/navigation/local_map_navigation.dart`, `features/search/local_map_search_page.dart`.
- Android: `MainActivity.kt` (AtomicFile recovery, không sửa Gradle/manifest).
- Backend: `Services/MapDrafts/MapProjectService.cs` (thông báo validation tiếng Việt).
- Tests: `p0_builder_state_test.dart`, `p0_live_sql_navigation_test.dart`, `qr_publish_hotfix_test.dart`, cập nhật nhãn counter trong `android_map_builder_test.dart`, `multifloor_navigation_test.dart`.
- Tool: `tools/P0RuntimeSmoke/{P0RuntimeSmoke.csproj,Program.cs}`; tài liệu này và đường dẫn cập nhật ở đầu `HotfixQrPersonalPublish.md`. Local config Development ignored; APK/log/evidence ignored.
