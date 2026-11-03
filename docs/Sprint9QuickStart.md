# Sprint 9 — Core flow + History

25/10/2026 · `auth-jwt-assignment`. Chỉ source/test; không SQL thật, email thật, sửa tài khoản thật, commit/push hoặc cập nhật Master Plan.

| Feature | Implemented | Smoke tested | Android / SQL pending | Known issues |
|---|---|---|---|---|
| Email binding | JWT subject + password hiện tại, token 30 phút/dùng một lần, kiểm tra normalized email | Account tests qua email sink ở lượt backend đầu; widget tests đạt | Chưa gửi email binding thật | Backend final tests bị Application Control chặn |
| Change / Forgot Password | Settings đổi password của signed user; Forgot riêng theo email/username | Account tests và widget/API mocks | Chưa đổi password account thật | JWT mới có security-stamp; JWT legacy không có stamp vẫn hết hạn theo TTL cũ |
| Personal Publish / QR | Chọn node bản đã lưu → tạo QR → Publish → QR ghim version | Widget flow đạt; personal API SQLite/filesystem đạt ở lượt backend đầu | Chưa nghiệm thu personal Publish trên Android/SQL trong sprint này | Không cấp SitePublisher; facility policy giữ nguyên |
| Guest / Navigation | Tái sử dụng public resolve/Search/Preview/Navigation | Public QR, relocalization/rerouting/navigation fixtures đạt | ADB không có thiết bị; chưa camera mới | Không tuyên bố camera/SQL E2E mới đã PASS |
| History | API + UI thật, signed UserId, start/complete/cancel/delete/resume | Flutter mocks đạt; backend tests đã compile | **Chờ migration và backend final tests** | Chỉ Published qua QR; local/legacy/Guest không ghi server |

**Lỗi tìm thấy:** Profile trước chỉ sửa tên và email read-only; Settings mở Forgot tự do, nên nhập email B khôi phục B, không phải session A. Chưa có bằng chứng account takeover. Nay tách Change Password, email binding và Forgot. Email-shaped input ưu tiên đúng normalized email, không để username khác che khuất. DTO mới không nhận role/UserId/EmailConfirmed. Khi ghi email, kiểm tra uniqueness trong SERIALIZABLE cùng registration; không merge account hoặc áp unique index lên email legacy. Writer bên ngoài API không được bảo đảm bởi cơ chế này.

**Publish:** backend đã hỗ trợ tạo QR trước Publish. UI nay dùng node bản đã lưu, chỉ dẫn thứ tự, báo lỗi cụ thể và giữ trạng thái luôn thấy. Test mới phát hiện lỗi `AlertDialog` đo intrinsic của `QrImageView/LayoutBuilder`; sửa bằng khung hữu hạn. Chưa có HTTP lỗi từ phiên personal thật để kết luận đây là nguyên nhân duy nhất lần trước. Email verified không cấp quyền cơ sở/Admin.

**History:** Home dùng `Navigator.push(HistoryPage)`, không có named route `/history`. Danh sách và nút xóa trước đây là giả. API mới `GET/POST /api/me/navigation-history`, `PUT/DELETE /{id}`, `GET /{id}/resume` đều JWT, luôn lọc UserId kể cả Admin. Session ID giữ qua rebuild/camera/reroute; chỉ bắt đầu ở Navigation. Server lấy map/version/tên điểm từ QR/public snapshot và kiểm tra đích, khả năng đi đến; không lưu polyline/JWT. Resume xác minh QR còn active, tải snapshot hợp lệ, hỏi xác nhận vị trí và tính tuyến mới; không tự đoán Room khi chung entrance. Mất mạng/schema thiếu báo chưa lưu, app bị kill có thể còn InProgress. Không ghép lịch sử Guest vào account.

**Migration chưa apply:** `20261025010000_AddNavigationHistory`, `WayMarkDbContext`, `__EFMigrationsHistory`. Up chỉ thêm bảng `NavigationHistory`, PK session GUID, check trạng thái và index `(UserId, StartedAtUtc)`. Giữ historical IDs, không FK cascade xóa theo map/Identity; resume kiểm tra dữ liệu hiện hành. Down chỉ DROP bảng mới, cũng không chạy. Công cụ scaffold bị Application Control chặn; source/snapshot chuẩn bị theo convention hiện có. Có test offline SQL Server model/snapshot/script nhưng **chưa chạy được**. Cần backend tests đạt, review SQL preview/backup và **phê duyệt riêng migration mới** trước khi apply WayMarkDatabase; approval ba migration Sprint 6 không bao gồm History. Giữ nguyên WayMarkAuthDatabase.

**Verification:**

- Flutter analyze sạch; **73 targeted tests PASS**; Android debug APK PASS (`http://10.0.2.2:5121/api`). APK: `waymark/build/app/outputs/flutter-apk/app-debug.apk`.
- Backend + test project build PASS, 0 warnings/errors.
- Backend lượt đầu **72/73**: gồm 6 account tests mới và personal SQLite/filesystem test. Test kiểm kê quyền chưa nhận endpoints self-service, đã cập nhật. Lượt sau bị Application Control chặn DLL (`0x800711C7`) trước khi chạy; không bypass. **Không có backend final PASS**; History tests và hai account tests bổ sung chưa chạy.
- `git diff --check` PASS; logs ignored tại `waymark/build/sprint9-evidence/`. Không chạy full regression/16 SQL E2E, không sửa Gradle/Windows generated/Figma/secrets/migration cũ.

**Smoke operator:**

1. Xử lý test runner theo chính sách máy, chạy backend targeted tests trước; restart API profile `http` để nạp source mới. Chạy Flutter với `flutter run -d emulator-5554 --dart-define=WAYMARK_API_BASE_URL=http://10.0.2.2:5121/api` khi emulator có sẵn.
2. Hồ sơ → email chưa thuộc account khác + password hiện tại → token xác minh → login lại. Bảo mật → Change Password đúng username. Không gửi token/password vào chat/log; Forgot là flow riêng.
3. Save ảnh/graph có node đích và cạnh hợp lệ → Cloud → chọn node đã lưu → tạo QR → đóng dialog → Publish → tải QR PNG. Thiếu ảnh/đích/QR/đường có hướng thì đọc lỗi hiển thị.
4. Logout → Guest camera scan QR mới → Search → Preview → Navigation → Arrival. QR revoked phải báo lỗi; draft không được đọc công khai; B không sửa/publish/revoke map A.
5. Sau **approval + apply History migration**, account A dẫn đường rồi hoàn tất/hủy → History → reload/login lại → xóa mục/reload. B/Admin khác không thấy lịch sử A. Resume phải xác minh QR/map và xác nhận vị trí trước tính tuyến mới.

**Files Sprint 9:** backend `Controllers/{AuthController,AccountSecurity,NavigationHistoryController}.cs`, `Services/{ISmtpEmailService,SmtpEmailService}.cs`, `Security/WayMarkSecurity.cs`, `Program.cs`; persistence `Models/NavigationHistory.cs`, `Data/{NavigationHistoryModel,WayMarkDbContext}.cs`, migration History `.cs/.Designer.cs` và map snapshot. Tests `AccountSecuritySprint9Tests`, `NavigationHistoryTests`, `AdminAuthorizationTests`, `MapDraftTestHost`. Flutter `auth/account_security_page`, `auth/password_reset_page`, `profile/profile_page`, `admin/settings_page`, `admin/map_project_cloud_page`, `history/history_page`, `navigation/{navigation_page,local_map_navigation}`, services `{auth_api_service,published_map_api_service,navigation_history_service}`; tests `{sprint9_account_history,map_project_cloud,password_reset_smoke}_test.dart`; tài liệu này.

**Chưa GO toàn bộ core SQL + History**: cần backend final tests và migration được kiểm chứng/phê duyệt. Source/Flutter đã sẵn sàng cho nghiệm thu có kiểm soát; không tự thực hiện các bước SQL còn chờ.
