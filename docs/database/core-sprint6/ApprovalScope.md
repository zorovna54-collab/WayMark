# Core Sprint 6 — local Development hiện tại, chờ phê duyệt A–E

Target duy nhất: `LAPTOP-PFRPMR3O`, instance `.`, `WayMarkDatabase`. Giữ nguyên `WayMarkAuthDatabase`, database architecture và Master Plan. RunId đề xuất **2e5448b2-7c06-4a93-a438-f0d22a2edca6**.

**Quyết định mới thay thế phương án cũ:** giữ Windows account hiện tại `LAPTOP-PFRPMR3O\pc` và quyền SQL sysadmin hiện có. Không tạo Windows account, SQL login/user hoặc thay quyền của account hiện tại. `PrepareWindowsRuntime.review.ps1` và `ProvisionRuntime.review.sql` đã nghỉ sử dụng, không chạy trong phương án này. Sysadmin runtime chỉ là ngoại lệ E2E local được duyệt theo RunId; không phải cấu hình production hoặc quyền System Admin của app.

## Precheck đã thực hiện (không SQL write)

- Branch auth-jwt-assignment; hai script migration giữ đúng SHA256 manifest Sprint 3, `git diff --check` đạt. Không regenerate SQL artifacts.
- MSSQLSERVER chạy; sqlcmd ODBC utility 16.0.1000.6 hỗ trợ `-N` (encryption), `-C` (trust override). Lỗi strict TLS đã được chứng minh trong Sprint 4/5; chưa dùng `-C` trong Sprint 6. Actual SQL target/history sẽ được SELECT lại trước mọi write sau khi ngoại lệ được duyệt; không dùng kết quả cũ thay kiểm tra đó.
- Registry LoginMode=1 (**Windows Authentication only**), TCP disabled. Không đổi Mixed Mode, bật TCP, firewall hoặc restart SQL Server. Chưa có chứng cứ encryption status của session mới: phải SELECT actual server/database/net_transport/encrypt_option sau approval. Nếu session/protocol không đáp ứng yêu cầu bảo mật thì dừng, không tự mở rộng ngoại lệ hoặc đổi server settings.
- SQL backup directory hiện có: `C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Backup`; ACL cho SQL service `NT SERVICE\MSSQLSERVER` và operator quyền ghi. C còn khoảng 118 GiB, D 178 GiB; chưa tạo/verify .bak mới.
- Agent đang chạy operator `LAPTOP-PFRPMR3O\pc` không elevated; phương án mới không cần elevation, đổi execution policy hoặc Windows identity. Không dùng tài khoản CodexSandbox. Quyền SQL cao chỉ được dùng theo phạm vi ghi được duyệt; không thay đổi membership/quyền của Windows account.

## Phạm vi đề nghị duyệt cùng một lần

| Phạm vi | Ghi/thay đổi cụ thể | Rủi ro / chốt dừng |
|---|---|---|
| A. TLS local | Chỉ dùng Encrypt=True + trust override (`sqlcmd -N -C` / SqlClient) trong migration/setup/test cho đúng instance local; không persist appsettings/secret | Không xác minh CA/name. SELECT actual server, database, ORIGINAL_LOGIN, auth_scheme, net_transport, encrypt_option trước write. Network transport phải mã hóa; Shared memory có thể không báo mã hóa mạng và được ghi rõ, chỉ chấp nhận trong ngoại lệ local đã duyệt. Không tắt Encrypt, không cho remote/LAN/SQL auth. |
| B. Backup | FULL COPY_ONLY,CHECKSUM vào file mới `C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Backup\WayMarkDatabase_Core6_2e5448b27c064a93a438f0d22a2edca6.bak`; backup metadata msdb; HEADERONLY/FILELISTONLY/VERIFYONLY WITH CHECKSUM | File phải chưa tồn tại; failure dừng trước migration. VERIFYONLY không phải restore rehearsal; không restore đè DB hoặc tự tạo DB thứ ba. |
| C. Migrations | Chạy artifact giữ nguyên checksum: AddMapDraftFoundation → BindMapImagesToDrafts → AddPublishedMapProjects; 8 bảng + constraints/index/FK + 3 history rows | Không sửa graph/Identity history. Mỗi migration transaction riêng; lỗi dừng/đọc history, không Down/cleanup. Backup verification là gate bắt buộc. |
| D. Hai app accounts test | Tạo mới `wm-core3-2e5448b27c064a93a438f0d22a2edca6-a` và `wm-core3-2e5448b27c064a93a438f0d22a2edca6-b`; email tương ứng `@example.invalid`, password random/private; A/B nhận Creator + active Site membership, **chỉ A** nhận SitePublisher | Không Admin/SiteManager; không sửa account cũ. Site `WM-DEMO-2A`, Building `WM-DEMO-2A-B`, Floor G/L1 có sẵn và chưa có draft; tra ID thực qua SELECT. Không thấy hierarchy phù hợp thì dừng, không seed graph. Names đã tồn tại thì dừng, không reset/adopt. |
| E. Storage + SQL E2E | Root `C:\Users\pc\AppData\Local\WayMark\CoreSprint6\2e5448b27c064a93a438f0d22a2edca6\images`, quota128 MiB/20objects; private plan/DPAPI credentials ở thư mục cha, evidence theo RunId trong build ignored; Save/Load/upload/QR/publish/private edit/revoke, start/restart child API | Dùng Windows account hiện tại/sysadmin chỉ cho loopback E2E. Quyền SQL này vẫn rộng, không thể gọi là least privilege; fingerprint phát hiện thay đổi, không ngăn mọi SQL write. Không mở firewall/static storage, đổi JWT gốc hoặc expose public server. Kiểm tra B403/Guest401, ảnh/snapshot/persist/revoke; không DELETE/TRUNCATE hoặc cleanup tự động. |

## Điều kiện thực thi

Sau khi người dùng duyệt rõ toàn bộ gói A–E, thực thi liên tục trong phạm vi trên, không hỏi lại từng câu lệnh nhỏ. **Prompt continuation và lời nhắn “tiếp tục” chưa phải consent ghi SQL/TLS** theo chính yêu cầu mục 8. Chưa backup, apply, tạo account hoặc dùng `-C`. Không cần terminal Administrator hoặc setup account Windows.

Giữ cả hai chốt `localDevelopmentCertificateExceptionApproved` và `localDevelopmentSysadminRuntimeExceptionApproved` mặc định false; chỉ bật trong private plan của đúng run sau consent. `expectedWindowsIdentity` phải là `LAPTOP-PFRPMR3O\pc`; SQL ORIGINAL_LOGIN phải khớp. Nguồn local, Windows auth, đúng target/history/session/checksum và `--execute-approved` vẫn bắt buộc. Default mode tiếp tục từ chối runtime có đặc quyền cao; không biến sysadmin thành default cho công cụ/API.

Command `bootstrap` chỉ nhận hai ID còn trống và đúng username RunId, tạo hai Identity user trong một transaction và lưu IDs vào private plan. Command `grant` sau đó kiểm tra chính xác ID/tên/email và chỉ cấp quyền D. Password lấy từ private environment/DPAPI, không command line/log/Git. Nếu DB commit thành công nhưng ghi plan thất bại, giữ account để review và xác định lại IDs; không tự xóa/retry/reset. Credential/password không chuyển tiếp vào child API; runtime SSPI không có SQL password.

Fingerprint trước/sau HTTP E2E bao gồm 6 bảng graph legacy, các bảng Identity, membership và hai migration history, lấy baseline **sau** bootstrap/grant được duyệt. Riêng account bootstrap/grant có tests rollback/không adopt; khi thực thi phải đối chiếu Identity legacy trước/sau ngoài các user/role/membership được phép thêm. Không dump password hash, JWT hoặc dữ liệu user vào evidence.

Các scripts được tạo để review; chưa chạy backup/provision/migrate/account setup/E2E. Không đánh dấu SQL Server E2E PASS. Sau approval và thực thi sẽ lưu bằng chứng/thống kê regression thật; nếu gặp lỗi ngoài phạm vi thì dừng để báo.
