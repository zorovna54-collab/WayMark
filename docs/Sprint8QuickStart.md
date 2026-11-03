# Sprint 8 — thử nhanh (25/10/2026)

Kiểm tra runtime sau khi operator cấu hình SMTP và bật API (25/10): Swagger WayMark HTTP200; đúng **một** anonymous POST `/api/Auth/forgot-password` trả **200 từ Kestrel**, không redirect/không JWT. OPTIONS với Origin `http://localhost:7357` trả204, Allow-Origin đúng origin, Allow-Headers có content-type và Allow-Methods có POST. Không tái hiện403 trên API hiện chạy. **SMTP delivery PASS: operator đã xác nhận thư đến Hộp thư đến.** Bằng chứng là HTTP thực + xác nhận inbox của operator, không chỉ HTTP200 generic. Không đọc thư/token và không gửi lại yêu cầu. Evidence không chứa token/password/email cá nhân: `waymark/build/sprint8-evidence/smtp-live-attempt.json` (ignored).

## Đã triển khai

- User đăng nhập → Cài đặt → **Bắt đầu tạo bản đồ** → form ngắn → draft server → Builder. Không yêu cầu role Creator trước khi bắt đầu.
- Mỗi map personal có Site/Building riêng mang namespace `WM-PERSONAL-`, không đại diện bệnh viện; owner lấy từ Identity. Entitlement `waymark:personal_site` nằm trong AspNetUserClaims hiện có. Membership chỉ được tạo cho scope mới đó. Không cấp Admin, SiteManager hoặc SitePublisher.
- Hai context dùng chung relational connection/transaction cho onboarding; lỗi rollback cả hierarchy, membership, entitlement và project. RequestId giữ nguyên khi retry; tối đa 10 workspace/user và 12 tầng/workspace.
- Personal publish chỉ cho owner với entitlement còn hiệu lực, xác nhận công khai, graph/ảnh hợp lệ và QR start có đường tới đích. Official facility vẫn cần quyền publish riêng + membership. Chỉnh draft không đổi snapshot.
- Role/capability đọc lại từ backend; policy Author/Admin và quyền publish kiểm tra role hiện tại trong Identity trên API thật, không chỉ JWT cũ. Scope personal không biến thành quyền quản lý cơ sở.
- My Maps mở lại project cùng cloud link trong Builder. Tầng personal mới được tạo/bind khi người dùng lưu. Save/upload lỗi vẫn giữ bản local; floor/asset đã tạo trước một lỗi mạng có thể còn trong workspace để đối chiếu, không tự xóa dữ liệu.
- Profile/Settings dùng card/group chung, form Save/Cancel, trạng thái email/quyền, xác nhận Logout, public QR entry. Admin/collaborator APIs chưa có được ghi rõ Chưa khả dụng.

Không cần migration: metadata thêm trong ContentJson và entitlement dùng bảng Identity đã có. Không apply migration, không ghi SQL thật, không thay secrets, không commit/push trong sprint này.

## Nghiệm thu Android

1. Khởi động API Development bằng profile `http` trong terminal/IDE của operator; profile cấu hình `http://localhost:5121`. Dùng JWT/connection string cục bộ đã có, giữ ngoại lệ certificate trust chỉ cho SQL local Development đã duyệt nếu cần. Không bật môi trường MapDraftE2E cũ.
2. Bật emulator rồi chạy `flutter run -d emulator-5554 --dart-define=WAYMARK_API_BASE_URL=http://10.0.2.2:5121/api` trong `D:\project\WayMark\waymark` (thay device ID thực nếu khác).
3. Login User → Settings → Bắt đầu tạo bản đồ. Nhập tên/địa điểm/tầng. Email liên hệ là dữ liệu readonly từ tài khoản, không được dùng để tự nhận ủy quyền cơ sở. Builder mở draft đã tạo.
4. Chọn ảnh; thêm Node/Edge/destination. Vào **Server / Publish / QR**, Save. Với bản personal, tầng mới tự được ghép vào scope riêng. Mở lại từ My Maps để kiểm tra ảnh và graph. Image storage cần được operator bật bằng root managed hiện có ngoài Git; nếu đang disabled, upload sẽ 503 và bản local được giữ nguyên.
5. Chọn Node start, tạo QR cho phiên bản đã lưu **trước** Publish (guard hiện có). Sau Publish mới tải PNG dùng cho Guest. Nút Thử như Visitor hoặc public QR entry mở snapshot → Search → Navigation. Bản personal luôn có nhãn cá nhân/demo, chưa xác minh cho bệnh nhân.
6. Kiểm tra B không sửa/publish/revoke map A, Guest không đọc draft; thử Profile Save/Cancel, refresh quyền, Logout và Back.

## Forgot Password / SMTP

Client dùng anonymous `POST /api/Auth/forgot-password`, không gửi JWT và không gọi `/api/Email/test`. Admin email endpoint giữ bảo vệ AdminOnly. Anonymous reset và trường hợp sender lỗi được kiểm thử bằng fake email: 200 generic; lỗi SMTP không sinh HTTP403 trong controller hiện tại.

Phát hiện/sửa lỗi source: reset sender trước đây dùng cấu hình admin test, vô tình bắt buộc `Smtp:TestRecipient`. Reset nay chỉ cần delivery settings; TestRecipient vẫn cần cho admin smoke test. Lỗi delivery được log theo loại, không log recipient/token/password. Flutter có thông báo riêng cho 403/429 và mạng lỗi.

**Nguồn 403 trước đây chưa xác định**: lúc kiểm tra source ban đầu API chưa chạy. Lần runtime mới trả200 cho đúng endpoint anonymous, preflight loopback204 và operator nhận thư trong Inbox, nên không có căn cứ nới authorization/CORS. Nguồn Development đọc được trước khi operator yêu cầu ngừng đọc secrets thiếu các key delivery; sau đó operator tự cấu hình. Không đọc lại secret. Lần kiểm tra mới chỉ gửi một request reset; không dùng token hoặc đổi mật khẩu tài khoản thật.

Operator cấu hình ngoài Git bằng User Secrets của WayMark.Api: `Smtp:Host`, `Smtp:Port`, `Smtp:UseStartTls=true`, `Smtp:Username`, `Smtp:AppPassword`, `Smtp:FromEmail`; `Smtp:SenderName` tùy chọn. Project đã có UserSecretsId, không init lại. Không dán password vào chat/source. Các lệnh này chỉ ghi các key SMTP được nêu, không sửa JWT/connection strings. Thay placeholder email gửi; ví dụ host Gmail, nhà cung cấp khác cần host/port phù hợp:

```powershell
$waymarkApiProject = 'D:\project\WayMark\WayMark.Api\WayMark.Api.csproj'
$waymarkSmtpSender = '<SMTP_SENDER_EMAIL>'
$waymarkSmtpPassword = Read-Host 'SMTP App Password' -AsSecureString
try {
    $waymarkSmtpCredential = [System.Net.NetworkCredential]::new('', $waymarkSmtpPassword)
    @{
        Smtp = @{
            Host = 'smtp.gmail.com'
            Port = 587
            UseStartTls = $true
            Username = $waymarkSmtpSender
            AppPassword = $waymarkSmtpCredential.Password
            FromEmail = $waymarkSmtpSender
            SenderName = 'WayMark Development'
        }
    } | ConvertTo-Json -Depth 3 | dotnet user-secrets set --project $waymarkApiProject
}
finally {
    $waymarkSmtpCredential = $null
    $waymarkSmtpPassword.Dispose()
}
cd D:\project\WayMark
$env:DOTNET_ENVIRONMENT = 'Development'
dotnet run --project .\WayMark.Api\WayMark.Api.csproj --launch-profile http
```

User Secrets ở ngoài Git, không phải kho secret production. MailKit đọc `Smtp`; Development đăng ký sender thật. `MapDraftE2E` đăng ký E2EDisabledEmail nên không dùng cho lần thử thư này. Đối chiếu `Now listening on: http://localhost:5121`; profile cấu hình không thay thế kiểm chứng process đang chạy.

Sau khi operator cấu hình và báo API sẵn sàng: xác nhận Swagger đúng API, path/method và preflight nếu Web; chỉ POST tối đa một yêu cầu reset cho tài khoản operator đã chỉ định. Không lưu email cá nhân vào repo. HTTP200 generic không chứng minh thư đã đến; cần operator kiểm tra inbox/spam. Không dùng quyền Admin để né 403, không nới Email/test, không tắt rate limit.

## Kiểm thử / file

- Backend: tests trọng tâm dùng Identity/SQLite và managed filesystem tạm thật cho personal Save/Load/Publish/QR/owner/rollback; tests auth dùng InMemory và fake email. Không kết nối SQL Server trong các tests này.
- Flutter: onboarding → Builder → refresh My Maps không cấp role; Settings theo capability, UI 320px, Save/Cancel/Logout, publish permission/QR guard và public QR/navigation dùng mock HTTP/camera. Chưa nghiệm thu Android camera hoặc SMTP thật.
- Log cuối tại `waymark/build/sprint8-evidence/` (ignored), APK tại `waymark/build/app/outputs/flutter-apk/app-debug.apk`.
- Backend chính: PersonalMapsController, PersonalMapOnboarding, PersonalMapAccess, DraftAccess, MapProjectService/DTO, MapsController, AuthController, WayMarkSecurity, EmailTestOptions/SmtpEmailService; test PersonalMapOnboardingTests/AdminAuthorizationTests.
- Flutter chính: CreateMapPage, MyMapsPage, AccountHeader/AccountSection, Profile/Settings, AccountProfile, AuthApiService, PublishedMapApiService, Builder initial project/cloud binding; nhãn personal trong Search/Preview/Navigation. JSON local v2/v3 giữ nguyên.

Trạng thái: source/smoke sẵn sàng; SMTP request + Inbox **PASS** theo lần kiểm thử runtime ở đầu tài liệu. Create/Save/Publish SQL runtime và Android thực vẫn **MANUAL PENDING**. Không có thiết bị trong adb lúc kiểm tra trước. Master Plan, Gradle, Windows generated và Figma giữ nguyên.
