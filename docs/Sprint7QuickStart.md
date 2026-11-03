# Sprint 7 — chạy thử nhanh

Kết quả 24/10/2026: Flutter analyze sạch; 278 Flutter tests đạt / 2 skip; 60 tests nhóm API/xác thực đạt; backend build 0 warnings/errors; Android debug APK và git diff --check đạt. Không chạy lại toàn bộ backend regression. Lần build APK đầu bị PowerShell coi cảnh báo native-access của Java là lỗi; chạy lại với xử lý stderr thông thường build đạt, không sửa Gradle/JDK hoặc policy Windows.

Không chạy lại SQL E2E, migration hoặc seed. Không sửa Master Plan. Các thử nghiệm backend tự động dùng Identity/EF InMemory và email counter; không ghi SQL Server hoặc gửi email thật.

## Khởi chạy từ terminal/IDE của người dùng

API không được agent khởi động lại bằng cách vượt policy. Trong **terminal PowerShell mới**, dùng đúng ngoại lệ SQL local Development đã duyệt (không dùng cấu hình này cho production):

```powershell
cd D:\project\WayMark
$env:ConnectionStrings__WayMarkDatabase = 'Server=.;Database=WayMarkDatabase;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;Connect Timeout=5'
dotnet run --project .\WayMark.Api\WayMark.Api.csproj --launch-profile http
```

JWT và SMTP tiếp tục lấy từ cấu hình cục bộ/User Secrets hiện có; không đặt key/password vào source. Profile không cần bật image storage. API chỉ nghe loopback `http://localhost:5121` theo launch profile. Nếu Windows từ chối thực thi, dừng và xử lý theo chính sách máy; không tắt Application Control.

Sau khi mở Android Emulator trong Android Studio, dùng terminal thứ hai:

```powershell
cd D:\project\WayMark\waymark
flutter devices
flutter run -d emulator-5554 --dart-define=WAYMARK_API_BASE_URL=http://10.0.2.2:5121/api
```

Nếu ID khác, dùng ID thực trong `flutter devices`. Web có thể dùng:

```powershell
flutter run -d chrome --dart-define=WAYMARK_API_BASE_URL=http://localhost:5121/api
```

## Nghiệm thu 5 bước

1. **Zoom:** mở Builder qua Creator → Cài đặt → Bản đồ của tôi. Nhập ảnh/JSON, zoom 1×/2×/4×, pan, chọn/kéo node, chọn cạnh và Fit Image. Marker/chữ/nét không phình; tâm node vẫn theo ảnh. Pinch bằng hai ngón hủy thao tác drag chưa commit. Export/import không đổi GUID/metres; tọa độ chỉ đổi khi thực sự di chuyển node.
2. **Profile:** Login → avatar Home → Hồ sơ. Kiểm tra username/email/roles của phiên/email verification; đổi tên → Lưu → quay lại/mở lại. Tên lưu bằng claim `waymark:display_name` trong Identity hiện có, không đổi username dùng để login. Dùng tài khoản thử để nghiệm thu persistence SQL; sprint này chỉ kiểm chứng persistence tự động trong test InMemory.
3. **Logout:** từ Profile hoặc Settings, Đăng xuất → Login. Back không mở lại trang cũ; token/username/profile bị xóa khỏi AuthSession. Đây là logout local theo cơ chế hiện tại, không phải thu hồi mọi JWT đã phát hành trên server.
4. **Settings:** Guest có Đăng nhập và kiểm tra API; User không có nút quản trị; Creator/Admin/SiteManager có lối vào Builder sau khi API xác nhận thông tin. 401 khi probe không gửi JWT nghĩa là API đã phản hồi, không chứng minh database khỏe. Các cấu hình AR/theme/ngôn ngữ chưa có hạ tầng đã bỏ khỏi trang, không còn nút lưu giả. API vẫn quyết định quyền Site/owner.
5. **Forgot Password:** Login → Quên mật khẩu → username/email → gửi yêu cầu → lấy token từ email → dán token, nhập/xác nhận mật khẩu mới → quay lại Login. Có thể nhập token trực tiếp; chưa có deep-link tự điền token. Token sai/hết hạn/dùng lại không đổi mật khẩu. Hai endpoint chung giới hạn 5 request/10 phút/IP trong một API process; 429 thì chờ. Email trùng nhiều account phải dùng username. Chưa nghiệm thu SMTP delivery thật; request được nhận không bảo đảm email đã đến.

## Kiểm tra và file chính

- Canvas: `floor_plan_canvas.dart`, `draft_map_editor.dart`.
- Profile/session/client: `profile_page.dart`, `account_profile.dart`, `auth_session.dart`, `auth_api_service.dart`, `logout.dart`, `home_page.dart`.
- Settings/reset: `settings_page.dart`, `password_reset_page.dart`, `login_page.dart`.
- Backend: AuthController + DTO profile, rate-limit registration, reset-account resolution, SMTP body; không đổi schema.
- Tests: `map_zoom_smoke_test.dart`, `profile_settings_smoke_test.dart`, `password_reset_smoke_test.dart`, `settings_navigation_test.dart`, `AdminAuthorizationTests.cs`.
- Logs cuối nhóm tính năng: `waymark/build/sprint7-evidence/` (Git ignored). Android APK: `waymark/build/app/outputs/flutter-apk/app-debug.apk`.

Trạng thái Android thao tác thật, SQL Profile persistence và SMTP: **MANUAL PENDING**. Không có emulator gắn với adb khi kiểm tra sprint này. Không dùng kết quả widget/fake email để tuyên bố đã thử camera hay nhận thư thật.
