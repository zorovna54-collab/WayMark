# Hotfix QR Node / Personal Publish — 25/10/2026

> Cập nhật runtime tiếp theo: xem `P0RuntimeBuilderPublish.md`. Đã sửa nhánh Cloud thay local bằng workspace rỗng, lưu cấu hình MapImages Development ngoài Git, chạy fixture SQL được phê duyệt và Guest camera VirtualScene → Arrival. Các mục MANUAL PENDING bên dưới thuộc lượt kiểm tra trước; không phải trạng thái mới nhất.

**Nguyên nhân đã xác minh:** SELECT trên đúng `LAPTOP-PFRPMR3O` / `WayMarkDatabase` thấy cả hai personal project vẫn **v1, 0 node, 0 cạnh, 0 ảnh, 0 QR**. Floor draft/revision cá nhân hiện có cũng rỗng. Owner Identity, active edit membership và personal entitlement đều còn. Dropdown lấy `MapProjects.ContentJson`, không lấy graph local; list rỗng → không chọn được node → chưa tạo QR → Publish bị khóa. Dòng “Draft server v1” trước đây có thể chỉ là workspace được tạo, chưa phải graph đã lưu.

Không có request log của lần Save cũ để khẳng định HTTP lỗi đầu tiên. Source cho thấy upload ảnh thất bại sẽ chặn PUT graph; đồng thời lỗi `image_storage_unavailable` trước khi ghi bị coi như upload có thể đã thành công, làm lần thử sau mắc ở đối chiếu asset không tồn tại. Đã tái hiện và sửa nhánh đó. Không suy đoán dropdown bị khóa bởi Admin/SitePublisher.

## Thay đổi

- Luôn GET bản đã lưu khi mở/refresh và sau Save, đếm local/server riêng; chỉ xác nhận Save khi graph/ảnh đọc lại khớp request. GUID và định dạng số JSON .NET/Dart được đối chiếu đúng; không đổi GUID.
- Dropdown dùng tên + N01/N02 và stable node/floor GUID từ server đã xác minh. Entrance/Junction đều tạo QR được, không thêm loại Start. Mọi guard có lý do hiển thị; debug marker `QR-P0-20261025.2` không chứa JWT/token/account/physical root.
- Bổ sung **GET** `/api/admin/map-projects/{id}/publish-readiness`, cùng JWT/ownership/Site authorization hiện tại. Checklist ảnh, storage, node/đích, mét, QR, tuyến có hướng và quyền Publish. Chỉ kiểm tra cấu hình/đọc ảnh; không tạo thư mục/probe file/SQL write. POST Publish vẫn validate phía server, không nới quyền.
- Phân biệt storage-disabled trước khi ghi với lỗi metadata/DB/timeout chưa rõ kết quả. Trường hợp mơ hồ vẫn phải đối chiếu; local được giữ nguyên. Nêu chính xác bước upload/PUT/GET lỗi.
- Export project đã gắn server luôn dùng v3 kể cả một tầng. Import v2 vào personal map đang mở chỉ giữ project ID sau xác nhận và GUID tầng khớp; không tự gắn file khác vào server, không tự Save. Tải draft khác với local cũng cần xác nhận.

## Bằng chứng

- Backend: **40 targeted tests PASS**, build sạch. Có Identity/JWT thật trong SQLite, filesystem tạm thật, upload → save/reload 3 node/2 cạnh → QR Junction → publish → Guest đúng ảnh/graph/GUID/distance 12 m; owner B bị 403, revoked QR 410, sửa draft không đổi snapshot.
- Flutter: **88 targeted tests PASS**, `flutter analyze --no-pub` không có lỗi. Kiểm tra HTTP/JSON round-trip thay vì chỉ nhét graph sẵn vào widget; cả v1 rỗng, upload 503/retry, GUID, backup v2/v3 và Builder → QR PNG → Publish → Guest Search/Preview/Navigation/Arrival. Kết quả cuối trong `waymark/build/qr-publish-hotfix/flutter-final.log` và `verification-final.json`.
- PNG QR render thật **640×640**. Ảnh UI viewport 390×844: `waymark/build/qr-publish-hotfix/widget-qr-created.png`, `widget-published.png`. Đây là **widget rendering với HTTP/camera fake**, không phải screenshot Emulator/quét camera thật.
- Actual API + SQL, chỉ GET: Swagger 200, private readiness không JWT 401, QR/snapshot đã tồn tại 200, hai ảnh tầng 200. Đây là snapshot Core Sprint 6 đã có, **không phải personal map mới đã publish**.
- Root ảnh được duyệt từ Sprint 6 tồn tại; cả 2 file khớp checksum/metadata SQL. API smoke chạy loopback bằng root này rồi đã dừng đúng process của tác vụ; không sửa User Secrets/appsettings.
- Analyze sạch, debug APK đạt, `git diff --check` đạt. ADB không còn thiết bị khi thử smoke; Android camera + personal SQL write vẫn **MANUAL PENDING**. Không chạy 16 SQL E2E, không apply History migration, không ghi/seed SQL thật, không đổi quyền/secret/Gradle/Windows generated/Figma/Git history, không commit/push.

## Nghiệm thu bản đồ hiện tại (6 bước)

1. **Giữ bản local:** xuất JSON kèm ảnh trước khi cập nhật APK/restart app; không clear/uninstall dữ liệu. SQL hiện không có graph 3 node để tự tải lại. Nếu backup cũ là v2, mở đúng personal map trong My Maps rồi Mở JSON; chỉ xác nhận khôi phục khi GUID tầng khớp.
2. Chạy API Development với **root ảnh cũ đã đối chiếu**, không trỏ sang thư mục mới làm mất ảnh published cũ:

   ```powershell
   Set-Location D:\project\WayMark
   $env:MapImages__Enabled = 'true'
   $env:MapImages__RootPath = Join-Path $env:LOCALAPPDATA 'WayMark\CoreSprint6\2e5448b27c064a93a438f0d22a2edca6\images'
   $env:MapImages__MaxStorageBytes = '134217728'
   $env:MapImages__MaxObjects = '20'
   dotnet run --project .\WayMark.Api\WayMark.Api.csproj --launch-profile http
   ```

   Các biến chỉ áp dụng phiên terminal Development; không lưu secret, không chạy migration. Không dùng root/quota này làm cấu hình production mặc định.
3. Dùng APK `waymark/build/app/outputs/flutter-apk/app-debug.apk` hoặc chạy từ thư mục `waymark`: `flutter run -d emulator-5554 --dart-define=WAYMARK_API_BASE_URL=http://10.0.2.2:5121/api`. Kiểm tra debug marker hotfix trên màn hình Cloud. API smoke của agent đã dừng để operator chủ động chạy terminal.
4. Mở personal map, giữ/khôi phục graph local. Cloud → Đọc lại trạng thái server → xem checklist → Save. Cần thấy **GET xác nhận 3 node/2 cạnh**, không chỉ workspace v1. Nếu upload lỗi, đọc đúng phase/code; local vẫn còn. Không cần Admin/SitePublisher hoặc migration.
5. Chọn N01 (Entrance/Junction) từ server → Tạo/xem QR → Publish khi checklist hợp lệ → QR phải ghi Published đúng version → lưu PNG. Không công bố thay đổi local chưa Save.
6. Đăng xuất → Guest quét QR PNG → Search Node đích → Preview → Navigation → Arrival. Kiểm tra ảnh/tầng, chiều cạnh, mét và điểm xuất phát. Đây là bước Android/SQL personal cần operator nghiệm thu; agent chưa có approval tạo fixture mới trên SQL thật.

## Files trong hotfix

- Backend: `Contracts/PublishedMapDtos.cs`, `Controllers/MapProjectsController.cs`, `Services/MapDrafts/{MapProjectService,ManagedFileMapImageStorage}.cs`; test mới `PersonalQrPublishHotfixTests.cs`.
- Flutter: `features/admin/{map_project_cloud_page,project_publish_state,local_map_project,draft_map_editor,draft_map_editor_mobile}.dart`, services `{map_draft_api_service,published_map_api_service}.dart`.
- Tests: `qr_publish_hotfix_test.dart`, `map_project_cloud_test.dart`, fixtures `{personal_qr_http_fixture,map_draft_fixture}.dart`; tài liệu này. Log/PNG/APK nằm trong build ignored.
