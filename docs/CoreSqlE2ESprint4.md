# Core SQL E2E Sprint 4 — 24/10/2026

**SQL Server E2E: BLOCKED / WAITING FOR USER APPROVAL.** Chỉ chạy preflight đọc. Không backup, apply migration, cấp quyền, tạo account hoặc ghi fixture SQL. Không sửa Master Plan.

## Preflight thực tế

- Branch `auth-jwt-assignment`; giữ toàn bộ thay đổi Git có sẵn.
- Công cụ Sprint 3 `CoreVerificationAudit` chạy lại lúc **01:09:45 UTC / 08:09:45 Việt Nam**: SQL Server `LAPTOP-PFRPMR3O`, instance `.`, hai context cùng `WayMarkDatabase`, SQL Server provider, history map `__EFMigrationsHistory`, auth `__AuthMigrationsHistory`. `WayMarkAuthDatabase` ONLINE, không chuyển/xóa dữ liệu.
- Map history vẫn chỉ có CreateWayMarkSchema và AddNavigationSchema; Auth history vẫn CreateAuthSchema. **Chưa áp dụng migration nào trong Sprint 4**. Ba migration pending theo thứ tự: `20261020094848_AddMapDraftFoundation`, `20261020101304_BindMapImagesToDrafts`, `20261023063955_AddPublishedMapProjects`.
- Counts không đổi: 5 Identity users, 0 roles/user-roles; 1 Site, 1 Building, 2 Floor, 7 Node, 10 Edge, 3 WayMark. Chưa có bảng draft/membership/publication. Không đọc email, tên hoặc password hash của 5 user để tự chọn tài khoản.
- Hai SQL artifacts khớp SHA256 trong [manifest](database/core-sprint3/review-manifest.json): normal `ae0494a7934a5f196f972755c202e5bb51a80aaef12855bdb7966485325acf57`, idempotent `9b0ef8402d79810909bcfc39a4f262ac5e55fc226b25ed361e0f8446099fab22`. Không sinh lại hoặc sửa artifact.

## Blockers cần giải quyết

1. **TLS của migration launcher:** lệnh đọc `sqlcmd -S . -d WayMarkDatabase -E -N -l 5 -t 5 -b -Q "...SELECT..."` thất bại trước truy vấn: `The certificate chain was issued by an authority that is not trusted`. Không thử lại với `-C`, không tắt encryption, không sửa certificate/trust store. Công cụ SELECT-only vẫn kết nối được theo cấu hình ứng dụng hiện có; điều đó không chứng minh launcher TLS đã hoạt động. Cần operator cấu hình/xác minh certificate, trust chain và server name phù hợp trước khi chạy launcher đã review; thay đổi certificate/trust cần duyệt riêng.
2. **Backup mới chưa được tạo/xác minh:** msdb chỉ thấy FULL ngày 18/10 (WayMarkDatabase 16:47:31, legacy Auth 11:00:08). Chưa đọc file .bak hoặc chạy VERIFYONLY/rehearsal. Do truy vấn sqlcmd bị TLS chặn, chưa xác minh default backup path/quyền ghi của SQL service trên thư mục đích. Service chạy `NT Service\MSSQLSERVER`. Ổ C còn khoảng 118 GiB, D khoảng 178 GiB tại preflight; không thay thế kiểm tra kích thước backup/ACL thực tế.
3. **Runtime SQL principal:** principal Windows hiện tại là sysadmin. Chưa cung cấp `WAYMARK_CORE3_RUNTIME_SQL` hoặc `WAYMARK_CORE3_SETUP_SQL`; chưa có bằng chứng runtime principal hạn chế. Không dùng sysadmin cho E2E runtime. Nếu cần tạo principal/cấp quyền, phải duyệt danh tính và quyền cụ thể trước, không coi bảng dưới là quyền cấp tùy ý.
4. **Storage:** effective Development storage Disabled, RootPath chưa có. `C:\WayMarkData` chưa tồn tại; không tạo hoặc thử ghi. Đề xuất root riêng `C:\WayMarkData\CoreSprint4\<RunId-N>\images` ngoài Git, quota harness 128 MiB/20 objects. ACL/root phải được duyệt và xác minh trước khi upload.
5. **Hai account test chưa được chọn:** chưa cung cấp ID/tên A/B và hai password cục bộ; không hỏi/gửi password trong chat. Admin + active Site membership bắt buộc với API hiện tại, Owner/membership riêng chưa đủ. Admin còn cho phép WayMark CRUD toàn cục, cần duyệt riêng. Tool hiện chỉ nhận account test đã tồn tại có tên `wm-core3-<RunId-N>-a/b`, email tương ứng `@example.invalid`. Chưa biết account được chọn có khớp hay không; không tự tạo account hoặc bỏ guard để nhận tài khoản thật. Nếu chọn tên khác, phải review thay đổi guard cho đúng ID cụ thể trước khi grant. Hai Floor thuộc cùng Site/Building và chưa có draft cũng chưa được chốt ID.

## Bảng phê duyệt — CHƯA THỰC HIỆN

| Bước | Database/file và ghi dự kiến | Công cụ/lệnh sau khi chốt thông số | Rủi ro / phục hồi |
|---|---|---|---|
| 1. Backup | File mới ở đường dẫn được duyệt; metadata backup msdb; không overwrite .bak | `BACKUP DATABASE [WayMarkDatabase] TO DISK=N'<new-approved-file>' WITH COPY_ONLY,CHECKSUM`; HEADERONLY/FILELISTONLY/VERIFYONLY WITH CHECKSUM theo runbook | Cần dung lượng/ACL SQL service; VERIFYONLY chưa chứng minh restore đầy đủ. Không tự restore đè DB. |
| 2. Migration | WayMarkDatabase: thêm 8 bảng + constraints/index/FK, thêm 3 history rows; không Auth migration/graph legacy | Launcher SQLCMD có expected-server/session-context và `:On Error exit`; `sqlcmd -S . -d WayMarkDatabase -E -N -b -V 16 -i '<reviewed-launcher>'` | Chỉ sau TLS và backup gate đạt. Mỗi migration transaction riêng; lỗi dừng, đọc history, không chạy Down/cleanup. |
| 3. Runtime/storage | Principal được duyệt, quyền SQL tối thiểu; root mới và ACL riêng, file ảnh/manifest test | Cấu hình private process/environment theo [runbook](database/core-sprint3/README.md); không sửa appsettings/User Secrets đang dùng | Không dùng db_owner/sysadmin/db_datawriter. Cần duyệt script quyền cụ thể nếu chưa có principal; giữ storage cũ nguyên trạng. |
| 4. Test Creator access | Chỉ đúng 2 Identity account được chọn: Admin role nếu thiếu, user-role, active Site membership | `dotnet run --project tools/CoreSqlReadiness/CoreSqlReadiness.csproj -- grant D:\project\WayMark '<private-plan.json>' --execute-approved` | Admin có quyền WayMark toàn cục. Grant transaction dùng chung context; commit mất kết nối cần đối chiếu, không retry mù. Không tạo/reset account. |
| 5. SQL E2E | Drafts/revisions/assets/projects/publications/QR mới theo RunId; private edit/revoke; ảnh trong root riêng | `dotnet run --project tools/CoreSqlReadiness/CoreSqlReadiness.csproj -- e2e D:\project\WayMark '<private-plan.json>' --execute-approved` | Start/restart chỉ child API do tool tạo. Lỗi giữ dữ liệu/evidence; không DELETE/TRUNCATE hoặc tự thu hồi quyền. So fingerprint graph legacy trước/sau. |

Backup legacy WayMarkAuthDatabase, restore rehearsal, tạo account nếu không có test account phù hợp, thay đổi certificate/trust hoặc tạo SQL principal mới là các phạm vi cần chốt/duyệt riêng. Không tạo DB thứ ba. Không đặt secret trong plan hoặc dòng lệnh.

## Kết quả và bước kế tiếp

- **Tất cả kịch bản SQL E2E 1–16: CHƯA CHẠY**, không đánh dấu PASS. Không có kết quả Save/Load/publish/restart SQL Server mới.
- Chỉ tạo file báo cáo này. Audit cũ tạo lại script offline trong `waymark/build/core-verification-evidence/` ignored theo hành vi có sẵn; không sửa SQL artifacts đã review.
- Không sửa business source, không chạy lại regression suite trong preflight. Baseline **Sprint 3**, không phải kết quả mới Sprint 4: backend 301/301, Flutter 263 pass/1 skip, analyze/APK đạt.
- **NO-GO cho thực thi hiện tại**: TLS, backup gate, runtime principal và account/floor/root cụ thể chưa đủ. Cần người dùng duyệt từng phạm vi và cung cấp lựa chọn A/B + Site/Floor + đường dẫn backup; credential chỉ nhập qua cấu hình private cục bộ. Sau đó xử lý TLS/gate, thực thi đúng thứ tự, rồi chạy regression và cập nhật chính báo cáo này bằng kết quả thật.
