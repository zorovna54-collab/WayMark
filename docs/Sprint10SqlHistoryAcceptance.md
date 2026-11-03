# Sprint 10 — nghiệm thu History API + SQL Server + Android

Ngày 26/10/2026. RunId `ef357675a078`. Branch `auth-jwt-assignment`.

| Mức nghiệm thu | Kết luận | Bằng chứng |
|---|---|---|
| CODE | **PASS** | Analyze sạch; chạy lại 9 Flutter History/Zoom/Studio tests và 8 backend History tests đều đạt |
| API + SQL | **PASS** trong phạm vi fixture đã duyệt | SQLCMD backup/migration; HTTP thật; SELECT cùng Session ID; restart/login, isolation và xóa thật |
| ANDROID | **PASS** trên emulator với APK chính | Camera VirtualScene → Published snapshot → Search → Preview → Navigation → Finish → History/Home Recent; logout/login lại và UI delete |
| MANUAL PENDING | Pinch hai ngón và camera điện thoại vật lý | Zoom chính xác 1×/2×/4× đã render trên Android thật bằng debugger controller; pan/Fit dùng thao tác Android. Không gọi đó là kiểm thử pinch vật lý |

## Phạm vi và cách thực thi

- Chỉ `LAPTOP-PFRPMR3O / . / WayMarkDatabase`, Windows Authentication `LAPTOP-PFRPMR3O\pc`, kết nối SQL được mã hóa.
- Dùng `sqlcmd.exe` Microsoft đã được cho phép và API khởi chạy bằng `dotnet run --project WayMark.Api/WayMark.Api.csproj --no-build --launch-profile http` trong terminal workspace.
- Không chạy lại Sprint10SqlSmoke.dll, không điều tra lại Windows events, không thay Windows policy. Không dùng host khác để nạp DLL bị chặn.
- Tái sử dụng published fixture `P0Runtime-1e116efce42c`, map ID `b86cbcbb-786e-4baf-8b33-29800ed6e417`, snapshot v2, 3 node/2 cạnh 12 m, tầng P0 Ground. Không sửa map/ảnh/QR/graph của fixture hoặc người dùng.
- Tạo đúng 2 application test accounts `s10-ef357675a078-a/b`, không email, không role/Admin/membership grant. Password/JWT chỉ giữ trong bộ nhớ terminal, không ghi source/evidence/báo cáo. Các tài khoản được giữ lại, không tự reset password sau test.

## Backup và migration — PASS

1. Trước ghi: xác nhận server/database/session, encryption=TRUE; đúng 5 migrations nền, History chưa tồn tại. Lấy fingerprint read-only trước thao tác.
2. Tạo FULL COPY_ONLY mới, không ghi đè/append file cũ:
   `C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Backup\WayMarkDatabase_Sprint10_ef357675a078_copyonly.bak`.
3. Backup kết thúc 26/10/2026 13:26:16 giờ máy SQL. Metadata xác nhận COPY_ONLY/checksum; VERIFYONLY WITH CHECKSUM trả “The backup set on file 1 is valid”. SHA-256 file: `D9AD131C2FB13D259A595A8043EDDFEDAF6A72AC155C3D86F4921402A23AA3A9`.
4. Đối chiếu SQL preview SHA-256 `D0C84FBF8EC4129B1DB47B72F370210DD9EC32A2FFFBF24401158B1BCF1AAAA6`, kiểm tra target/baseline lại và VERIFYONLY lại ngay trước apply.
5. Áp dụng đúng `20261025010000_AddNavigationHistory` và `20261026001522_ExtendNavigationHistoryLifecycle`. Sau apply có đúng 7 business migrations. Không chạy Identity migration hoặc migration khác, không Down/restore tự động.

Các script native mới:

- `docs/database/sprint10/BackupHistory.sql`: clean-session/IMPLICIT guard, target/encryption, filename mới, backup/metadata/VERIFYONLY.
- `docs/database/sprint10/ApplyHistory.sql`: target, exact baseline, backup mới cùng RunId, VERIFYONLY, XACT_ABORT, include SQL EF đã review và postconditions.
- `docs/database/sprint10/ProtectedFingerprint.sql`: SELECT/hash, không xuất row data hoặc credentials.

Lệnh đã dùng từ root repo (đã hoàn tất; **không chạy apply lại**):

```powershell
sqlcmd -S . -d WayMarkDatabase -E -N -C -b -l 5 -t 180 -v RunId=ef357675a078 -i docs/database/sprint10/BackupHistory.sql -o <ignored-evidence>/backup.log
sqlcmd -S . -d WayMarkDatabase -E -N -C -b -l 5 -t 180 -v RunId=ef357675a078 -i docs/database/sprint10/ApplyHistory.sql -o <ignored-evidence>/migration.log
```

`ApplyHistory.sql` cố ý từ chối nếu schema/history không còn là baseline trước migration. Không dùng script này để sửa một deployment dở dang.

## History API + SQL thực — PASS

| Tình huống | Kết quả thực tế |
|---|---|
| QR active và snapshot Published | Public GET 200; dữ liệu từ snapshot v2 hiện có |
| Scan chưa có đích | POST 201, Scanned, destination NULL; SELECT SQL đọc đúng bản ghi |
| 8 request lặp cùng SessionId | 200, cùng ID, tổng số session vẫn 1 |
| Destination → Start | PUT 200, cùng ID; destination GUID/tầng đúng; InProgress; khoảng cách SQL 12.000 m |
| Start lặp | 200, không thêm record |
| Finish | PUT 200, Completed và EndedAtUtc trên cùng ID |
| Cancel trước chọn đích | PUT 200, Cancelled; destination/distance vẫn NULL |
| User B đọc/sửa/xóa A | 404, dữ liệu A không thay đổi; GET list B 200 rỗng |
| Guest | GET private History 401, public map/QR vẫn 200 |
| QR không tồn tại | 404, không tạo phiên |
| Restart API + login lại | JWT mới từ login thật; GET đọc lại Completed/distance 12 m; SELECT SQL xác nhận |
| Xóa trên Android rồi reload | Sau request UI hoàn tất: API GET theo ID 404, list không còn ID; SELECT count theo ID = 0 |

Raw evidence đã lưu **37 HTTP checks đều đạt** trước cleanup cuối. `http-checks.json` cũng giữ các probe debugger ban đầu thất bại do dịch vụ biên dịch biểu thức không có; các probe này là lỗi instrumentation, không phải HTTP/SQL test failure. Sau đó lời gọi compiled methods của controller render thành công. Một read ngay khi chạm Delete tới trước request bất đồng bộ; chờ UI hoàn tất rồi kiểm tra lại được 404/SQL 0. Không bỏ qua lỗi sản phẩm để gán PASS.

Có 4 History fixture được tạo: 2 qua HTTP (Completed/Cancelled) và 2 qua camera, vì có dùng nút Quét lại. SELECT ngay sau lần camera đầu xác nhận chỉ thêm 1 Scanned. Phiên camera thứ hai `9c33ddb3-6434-4c35-a70b-1ee4c3676287` đi qua Navigation và Finish; phiên camera trước đó giữ Scanned khi chưa bắt đầu, không tự Completed. **Cả 4 đã được xóa qua UI trong đúng tài khoản test A**. Không xóa History của tài khoản khác.

Sau cleanup: fixture History=0, tổng History=0 (trước test cũng 0), test accounts=2, role assignments=0, email=0. Fingerprint trước/sau giống hệt cho WayMarks, NavigationNodes, NavigationEdges, toàn bộ MapProjects/MapPublications/MapNodeQrs, AspNetUsers legacy trong WayMarkAuthDatabase và Auth migration history. Không thực hiện câu lệnh ghi vào WayMarkAuthDatabase.

## Android / Zoom / Studio

- APK **main** dùng `WAYMARK_API_BASE_URL=http://10.0.2.2:5121/api`, không phải entry demo offline. Login A thật, camera mobile_scanner nhận frames VirtualScene của emulator và resolve QR qua API thật.
- Search hiển thị đã lưu scan trước chọn đích; Preview/Navigation tải ảnh Published hiện có. API/SQL theo dõi cùng session. Đợi trong Navigation vẫn Bước 1/3/InProgress; không tăng theo timer.
- Arrival 3/3 vẫn InProgress trên API. Chỉ bấm Kết thúc mới Completed. Trở về Home thấy Recent cập nhật ngay, không cần login lại.
- Restart API, logout qua Settings, restart app, login A lại: Home Recent và History vẫn có Completed đúng timestamp/12 m. Sau Delete và confirm, History cập nhật rỗng sau khi xóa hết fixture.
- Đã đặt controller của chính canvas đang hiển thị trên APK ở 1×/2×/4× bằng debugger compiled-method calls (không thay source, graph, routing, AuthSession hoặc SQL để làm bằng chứng). Đo trên screenshot Android:

| Zoom | Đường kính marker | Nét tuyến | Nhãn số |
|---|---:|---:|---:|
| 1× | 56 px | 16 px | 12×20 px |
| 2× | 56 px | 16 px | 12×20 px |
| 4× | 56 px | 16 px | 12×20 px |

- ADB touch swipe pan tại 4×: marker 57 px (AA sai số 1 px), route và tường trên ảnh cùng dịch 40 px theo Y; điểm vẫn bám ảnh. Không suy displacement từ độ dài swipe vì touch slop tiêu thụ một phần cử chỉ.
- Chạm **Fit Image** thật: so 26.320 điểm pixel trong vùng ảnh/graph với bản 1× ban đầu, **0 khác biệt**.
- Studio/Home/unsaved guard đã có bằng chứng Android local draft ở lượt Sprint 10 trước (`sprint10-studio-menu.png`, `sprint10-unsaved-guard.png`, `sprint10-home-final.png`) và chạy lại tests hiện tại đạt. Không thay source Flutter giữa hai lượt; không cấp Creator/Admin để ép test. Nhãn/menu capability được kiểm tra bằng widget; quyền thật vẫn ở server.
- Runtime `node_repl` cho computer-use không được cung cấp trong phiên, nên không điều khiển cửa sổ Windows bằng skill đó. Chưa nghiệm thu pinch hai ngón hoặc camera điện thoại vật lý; không thay bằng lời khẳng định đã thử.

## Evidence và verification

Evidence riêng, Git ignored: `waymark/build/sprint10-native-ef357675a078/`.

- SQL: `backup.log`, `backup-sha256.txt`, `migration.log`, `protected-before.txt`, `protected-after.txt`, `sql-history-before-restart.txt`, `sql-history-after-restart.txt`, `sql-after-history-delete.txt`.
- API: `http-checks.json`, `native-acceptance-results.json`, fixture ID metadata. Không có JWT/password.
- Android: `android-camera-live.png`, `android-published-preview.png`, `android-published-navigation-{1,2,4}x.png`, `android-published-navigation-4x-pan.png`, `android-published-fit-image.png`, `android-published-arrival.png`, `android-home-after-Finish.png`, `android-relogin-History-persisted.png`, `android-history-list.png`, `android-after-delete.png`, `android-history-empty-after-delete.png`.
- Đo pixel: `android-pixel-measurements.json`, `android-pan-measurements.json`, `android-fit-comparison.json`.
- Chạy lại: analyze sạch; Flutter targeted **9/9**; backend History **8/8**; diff-check PASS. Baseline cùng source trước lượt SQL: Flutter **314 pass/3 skip**, backend auth/history/publication/account regression **96/96**, main APK debug build PASS. Không chạy lại full suite/build vì lượt này không đổi application source.

Các file thay đổi trong lượt nghiệm thu này: 3 native SQL scripts trên, báo cáo này và ghi chú cập nhật `Sprint10HistoryZoomStudio.md`. Giữ nguyên application source/migrations/connection strings/JWT, Gradle, Windows generated, Figma, Master Plan và các thay đổi Git có sẵn. Không commit/push.

## Tự thử tiếp

Schema History đã sẵn sàng, không cần apply lại. Các tiến trình thử nghiệm của phiên trước đã dừng; lúc đối chiếu cuối không có listener 5121 hoặc emulator đang chạy. Khởi động lại khi muốn demo:

```powershell
# Từ D:\project\WayMark, terminal thứ nhất
dotnet run --project WayMark.Api/WayMark.Api.csproj --no-build --launch-profile http
# Từ D:\project\WayMark\waymark, terminal thứ hai, sau khi mở emulator
flutter run -d emulator-5554 --dart-define=WAYMARK_API_BASE_URL=http://10.0.2.2:5121/api
```

1. Login tài khoản của bạn, quét QR Published hợp lệ: History phải xuất hiện ngay Scanned, chưa cần đích.
2. Chọn đích → Preview → Navigation; pinch hai ngón, pan/Fit; kiểm tra marker/nhãn/nét giữ kích thước khi zoom.
3. Arrival chưa tự lưu Completed; bấm Kết thúc, kiểm tra Recent/History rồi logout/login lại.
4. Xóa một hành trình do bạn chủ động chọn, xác nhận và reload; chỉ thử xóa dữ liệu bạn đồng ý xóa.
5. Builder local → thay đổi chưa lưu → Home: Keep giữ draft; Leave chỉ sau xác nhận; Save phải có bằng chứng lưu thật.

**Kết luận: CODE PASS / API + SQL PASS / ANDROID PASS trong phạm vi Development fixture đã duyệt. MANUAL PENDING: pinch hai ngón và camera vật lý. Không còn blocker schema History hoặc yêu cầu phê duyệt migration cho hai migration đã hoàn tất.**
