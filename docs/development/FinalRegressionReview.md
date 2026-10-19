# WayMark — final regression review (2026-10-18)

## Kết luận và phạm vi bằng chứng

**GO cho kiểm thử có kiểm soát trên Android Emulator. Chưa GO cho production.**
Các kết quả tự động ở dưới dùng HTTP/camera fake và EF InMemory/TestServer; không
chứng minh đã quét QR thật hoặc gọi SQL Server thật trong lượt review này.
4A–4C đã được người dùng xác nhận trước đây. 4D–4E vẫn cần kiểm thử trực tiếp theo
checklist dưới đây, đặc biệt khi dữ liệu hiện hữu chỉ có hai QR START/DEST.

Branch được kiểm tra: `auth-jwt-assignment`. Mọi thay đổi đã có trước lượt review
được giữ nguyên. Không chạy seed, SQL, database update/migration, commit/push/reset;
không sửa secrets, Authentication, schema hoặc ba file Windows generated.

## Phát hiện theo mức độ

| Mức độ | Phát hiện và bằng chứng | Xử lý / ảnh hưởng |
| --- | --- | --- |
| Critical | Chưa phát hiện trong phạm vi diff và test đã chạy | Không đồng nghĩa đã audit toàn bộ hệ thống hoặc môi trường production |
| High, có sẵn | `WayMarksController.cs`: POST/PUT/DELETE chỉ kế thừa `[Authorize]` của controller, không có policy/role quản trị. `Program.cs` không định nghĩa policy quản trị | Chưa sửa Authentication trong review. Chỉ thử nghiệm với dữ liệu kiểm thử và tài khoản tin cậy; cần chốt phân quyền server trước production. Việc ẩn UI Admin không bảo vệ API |
| Medium, đã sửa | Bộ chọn tầng trước đây chỉ nằm trong `_canvas` sau khi GET graph thành công. Khi tầng đầu trả lỗi, không thể chọn tầng còn lại | Test mới thất bại vì không tìm thấy `floor-2`; đã dùng chung `_floorChoice` cho canvas và trạng thái lỗi. Test sau sửa đạt, không thay đổi tuyến hay tạo cạnh |
| Medium, môi trường | Test Chrome dừng ở loading harness; GET `/canvaskit/chromium/canvaskit.js` và `.wasm` trên server test nội bộ đều HTTP 404, dù SDK có file | Đã dừng đúng phiên test bằng Ctrl+C. Chưa xác định nguyên nhân harness phục vụ sai tài nguyên; không sửa SDK, không coi test Chrome thành công. Web build được đánh giá riêng |
| Medium, chưa xác minh | NuGet trả NU1900: không truy cập được vulnerability feed | Build/test đạt không chứng nhận dependency sạch lỗ hổng. Cần chạy audit dependency khi feed hoạt động; không nâng cấp hàng loạt trong review |
| Medium, giới hạn sản phẩm | Chưa có metadata khảo sát/phê duyệt xe lăn; `IsAccessible` không đủ chứng minh an toàn | `wheelchair=true` bị chặn HTTP 422 `accessibility_not_verified`, kể cả tuyến một node. Flutter cũng từ chối response 200 xe lăn; không tự bỏ bộ lọc |
| Low, có sẵn | Bản nháp chỉ lưu trong bộ nhớ đến khi export; refresh/đóng tab có thể mất dữ liệu. File import có liên kết WayMark chỉ là đề xuất | Có nhãn draft, cảnh báo, giới hạn đầu vào và guard đổi tầng/Back/drawer. Cần kiểm tra file tải xuống; không có publish/write API mới |

Backend chưa được khởi chạy hoặc restart trong review. Request đọc Swagger tại
`http://localhost:5121/swagger/v1/swagger.json` đã timeout (lần kiểm tra cuối 3 giây),
không nhận được mã HTTP. Đây không phải bằng chứng cổng khác cũng không hoạt động.
Không có kiểm thử JWT/route với server thật trong lượt này; cần xác nhận listener
thực tế khi chạy backend. Android Manifest hiện cho HTTP cleartext phục vụ môi
trường phát triển; không coi cấu hình debug này là cấu hình triển khai production.

## Thay đổi riêng của lượt review

- `waymark/lib/features/route/floor_route_map.dart`: giữ lựa chọn tầng khi một tầng
  không tải được; dùng chung cách tạo chip, không đổi topology hoặc navigation.
- `WayMark.Api.Tests/RouteApiTests.cs`: so sánh response đầy đủ của request cũ với
  `options: {}` và options mặc định; thêm options null, boolean sai kiểu và
  preference null vào kiểm tra HTTP 400.
- `waymark/test/floor_plan_canvas_test.dart`: kiểm tra ảnh/overlay cùng bounds khi
  zoom + pan và tọa độ tap được chuyển ngược đúng về 0–1.
- `waymark/test/floor_route_map_test.dart`: kiểm tra đổi tầng reset transform,
  resize, và phục hồi bằng chọn tầng khác khi GET graph lỗi.
- `waymark/test/navigation_qr_flow_test.dart`: xác nhận token/username không thay
  đổi sau các luồng QR/reroute/lỗi; kết quả reroute đến muộn sau khi rời màn hình
  không được gọi callback hoặc sửa màn hình đã dispose.
- `waymark/test/draft_map_test.dart`: PNG chỉ còn header, thiếu dữ liệu pixel phải
  bị từ chối. Kiểm tra này đã đạt với validator hiện tại, không sửa validator.
- Tài liệu review này, gồm checklist và danh sách file dự kiến commit.

## Kết quả review luồng 4A → 4E

| Luồng | Xác nhận từ source/test | Cần kiểm thử trực tiếp |
| --- | --- | --- |
| 4A | Scanner chuẩn hóa QR, GET map-location có JWT; so node ID và floor ID hợp lệ; Search chọn đích; API service POST codes với base URL hiện có | Camera và dữ liệu SQL thật sau các thay đổi mới |
| 4B | `/routes` không trả X/Y: widget tải tọa độ bằng GET floor graph. Chỉ vẽ cạnh theo thứ tự response, cùng tầng; thiếu node không nối tắt; cạnh liên tầng chỉ có marker | Căn ảnh tầng đã khảo sát với tọa độ thật nếu có ảnh |
| 4C | Tiến độ chỉ đổi do nút thủ công/QR hợp lệ; next/previous/chuyển tầng/hoàn tất/một node/rỗng được test; không có timer tiến độ | Responsive/gesture và hành vi trên Emulator đang chạy |
| 4D | Node ID + floor ID quyết định vị trí, không so WayMarkCode với NodeCode. QR hiện tại giữ bước; kế tiếp cập nhật; bước xa cần xác nhận; node lặp chọn lần xuất hiện; lỗi không đổi tiến độ | Các QR thực tương ứng node kế tiếp, bước xa, sai tầng, node lặp; chỉ có thể thử nếu dữ liệu có sẵn |
| 4E | QR ngoài tuyến yêu cầu xác nhận reroute; giữ đích, options và accessibleOnly; thay route sau khi validate response; hủy/lỗi/response muộn giữ trạng thái cũ; Preview nhận route mới | QR ngoài tuyến có thật và đường từ node đó; hủy rồi chấp thuận khi API thật hoạt động |

AuthSession dùng cơ chế token/username trong bộ nhớ hiện có. Không tạo luồng login
khác và không xóa session do lỗi mạng/QR hoặc HTTP 401. Test 401 xác nhận hiển thị
yêu cầu đăng nhập lại; điều này không phải tự refresh JWT. Refresh tab/khởi động
lại ứng dụng không được cam kết giữ session vì hiện không có lưu bền token.

Không có hardcoded `WM-DEMO-*`, `120m`, ETA, timer di chuyển hoặc dữ liệu phòng
Figma trong Route Preview/Navigation mới. Grid fallback có nhãn sơ đồ node, không
là bản đồ vật lý và không dùng để suy ra mét. Một số màn hình Admin/Settings cũ
còn điều khiển/placeholder chưa nối backend; review này không triển khai chúng.

### Transform bản đồ

- `normalizedMapPoint`: gốc trên trái, X/Y hữu hạn trong 0–1; nhân với kích thước
  vùng nội dung, không nhân khoảng trống letterbox.
- `FloorPlanCanvas`: lấy kích thước ảnh giải mã; BoxFit.contain tạo đúng một vùng
  chung cho ảnh, painter và hit testing. InteractiveViewer áp cùng transform cho
  tất cả. Test tap sau scale 2 + translation kiểm tra tọa độ chuẩn hóa chính xác.
- Resize giữ cùng tỷ lệ ảnh/overlay. Đổi tầng đổi key theo floor ID, không giữ
  transform của ảnh tầng cũ. Nút reset đưa về identity.
- Thứ tự lần qua tầng được giữ, kể cả quay lại tầng cũ; không vẽ đoạn xuyên giữa
  hai sơ đồ. QR marker và node thủ công có trạng thái hiển thị riêng.
- Bằng chứng là test hình học/widget. Chưa đối chiếu bản đồ bệnh viện thật hoặc
  chứng nhận chất lượng đo đạc ngoài hiện trường.

## API routing và Accessible Routing

`POST /api/routes` vẫn `[Authorize]`; tests dùng JWT ký ngẫu nhiên trong TestServer,
EF InMemory riêng từng test, không đọc/ghi SQL thật.

Request cũ:

```json
{"startWayMarkCode":"WM-DEMO-2A-START","destinationWayMarkCode":"WM-DEMO-2A-DEST"}
```

Request mới:

```json
{
  "startWayMarkCode":"WM-DEMO-2A-START",
  "destinationWayMarkCode":"WM-DEMO-2A-DEST",
  "options":{"avoidStairs":true,"wheelchair":false,"preference":"PreferElevators"}
}
```

| Kiểm tra thực tế qua TestServer | Kết quả |
| --- | --- |
| Request cũ / options rỗng / options mặc định | 200; toàn bộ response giống nhau trên fixture test |
| Options mới hợp lệ | 200 và echo options; test thuật toán kiểm tra tránh cầu thang/preference |
| Options null / boolean sai kiểu / preference null, rỗng, lạ | 400 |
| Không có/sai/hết hạn JWT | 401 |
| Thiếu WayMark / chưa liên kết node | 404 / 409 với problem code riêng |
| Không có tuyến / wheelchair chưa xác minh | 422, hai problem code khác nhau |
| Lỗi dữ liệu DB được inject | 503 đã lược bỏ thông tin riêng |
| Graph không hợp lệ / lỗi server khác | 500 đã lược bỏ thông tin riêng |

Fixture API test có tổng 10 m, không phải graph demo thật 40 m. Không nhầm kết quả
fixture với kiểm thử SQL Server. Graph demo 40 m là thông tin người dùng xác nhận
trước review; checklist yêu cầu đối chiếu lại response thật.

`accessibleOnly` chỉ lọc IsAccessible. AvoidStairs là hạn chế cứng. PreferElevators
giảm số cạnh Stairs/Ramp rồi giảm mét; LessWalking giảm mét ngoài thang máy rồi
giảm tổng mét. Đây là các tiêu chí trên graph, không phải đo an toàn hoặc thời
gian chờ. Tổng khoảng cách vẫn là tổng DistanceMeters thật, không phải điểm ưu
tiên; không dùng X/Y chuẩn hóa làm khoảng cách vật lý.

## Bảo mật input, bản nháp và authorization

- Không có endpoint upload ảnh hoặc import/export server mới. MapBuilder đọc
  `/api/Maps/...` và map-location đã bảo vệ JWT; chỉnh sửa chỉ trên đối tượng draft.
  Không dùng DTO draft vào `/routes`, không SaveChanges hoặc publish từ editor.
- Ảnh chỉ PNG/JPG, tối đa 10 MB; extension/MIME/magic phải khớp; giải mã lấy kích
  thước, tối đa 8192 px mỗi chiều và 32 triệu pixel. Test dữ liệu rỗng, sai MIME,
  quá lớn, hỏng và bị cắt. Không nhận SVG/HTML hoặc đường dẫn server để thực thi.
- Ảnh nền từ API chỉ HTTP(S), không user-info; không chuyển Bearer header cho
  NetworkImage. Lỗi tải ảnh dùng fallback có thông báo. CORS ảnh thực cần thử Web.
- Import JSON tối đa 18 MB, version 1/status draft/verifiedForPatientUse=false,
  đúng Site/Building/Floor, tối đa 2000 node/10000 cạnh. Kiểm tra tọa độ, enum,
  mã trùng, tham chiếu node, self-loop, chiều và khoảng cách trước khi thay draft.
  Không eval nội dung; export dùng Blob tải file, không upload SQL/backend.
- Không thể cam kết NodeCode duy nhất toàn SQL từ draft cục bộ. Liên kết QR trong
  file import chưa phải liên kết được duyệt; không dùng file này cho bệnh nhân.
- File picker/download và import round-trip qua browser dialog vẫn cần kiểm thử
  thủ công. Trên Android, nhập/xuất file Web không được giả vờ là đã hỗ trợ.
- Đã kiểm tra APK debug: có đủ 4 Inter TTF và OFL.txt, không có file TSX,
  HospitalMap hoặc thư mục design-reference. Web bundle sau build cũng được kiểm
  tra danh sách tài nguyên riêng, không bundle source Figma.
- Quét các file thay đổi cho private-key block, JWT literal và mẫu password/
  secret gán trực tiếp không phát hiện mẫu phù hợp; không in các giá trị config.
  Đây là kiểm tra mẫu giới hạn, không thay thế secret scanner/audit toàn repo.

## Lệnh và kết quả tự động

Từ `waymark/` (các lệnh dưới đã hoàn tất, trừ test Chrome bị chặn đã nêu):

| Lệnh | Kết quả |
| --- | --- |
| `flutter analyze --no-pub` | Đạt, không có issue sau sửa source |
| `flutter test --reporter expanded` | Đạt: 136 passed, 1 test Web-only skip trên VM, không lỗi |
| `flutter build web --no-pub` | Đạt sau sửa source: 83.1 giây, tạo build/web, Wasm dry run đạt |
| `flutter build apk --debug --no-pub` | Đạt: assembleDebug 22.0 giây, tạo app-debug.apk; có cảnh báo Java native access, không lỗi Kotlin/Gradle |
| `flutter test --no-pub --platform chrome --reporter expanded test/routing_flow_test.dart` | Chưa chạy được test; HTTP 404 CanvasKit harness, đã dừng phiên |
| `flutter devices` | Windows, Chrome, Edge; chưa có Android Emulator kết nối |
| `git diff --check` | Đạt; Git có thông báo chuẩn hóa LF/CRLF, không lỗi whitespace |

Từ repository root:

```powershell
& 'C:\Program Files\dotnet\dotnet.exe' build WayMark.Api/WayMark.Api.csproj --no-restore --artifacts-path D:\project\WayMark\WayMark.Api.Tests\bin\sprint
& 'C:\Program Files\dotnet\dotnet.exe' test WayMark.Api.Tests/WayMark.Api.Tests.csproj --no-restore --artifacts-path D:\project\WayMark\WayMark.Api.Tests\bin\sprint
```

Backend build đạt, 0 lỗi; 60/60 backend tests đạt, không skip. Cả hai lệnh có cảnh
báo NU1900. Output riêng nằm trong thư mục bin đã ignore. Không ghi đè executable
đang được dùng hoặc dừng backend của người dùng.

## Checklist kiểm thử thủ công theo thứ tự

Mọi mục dưới đây **chưa được xác nhận hoàn tất trong lượt review**.
Ghi thiết bị, commit/source đang chạy, request/status và ảnh màn hình khi thực hiện.
Không tạo thêm dữ liệu thật chỉ để làm đủ checklist.

1. [ ] Mở Medium Phone API 37.0 từ Device Manager, chạy `flutter devices` để lấy
   DEVICE_ID. Nếu cần webcam, chọn camera AVD phù hợp; Flutter không đổi VirtualScene
   thành webcam vật lý. Xác nhận camera preview/cấp quyền, từ chối rồi thử lại.
2. [ ] Khởi chạy backend bằng terminal workspace đang quản lý backend; nếu có phiên
   cũ, dừng đúng phiên đó trước khi chạy phiên mới. Không mở hai listener cùng cổng.
   Dùng `& 'C:\Program Files\dotnet\dotnet.exe' run --project WayMark.Api`, đọc địa chỉ/cổng log thực tế; không đổi
   connection string, secrets hoặc chạy migration để né lỗi.
3. [ ] Mở Swagger đúng listener; đăng nhập bằng tài khoản kiểm thử có sẵn, không
   đăng ký thêm nếu không cần. Thử hai body JSON ở trên; kiểm tra HTTP 200, code
   start/dest, options echo, tổng mét và node/cạnh thứ tự. 40 m chỉ khi graph thật
   vẫn như dữ liệu đã kiểm thử trước. Wheelchair=true phải 422 có thông báo rõ.
4. [ ] Chạy Flutter Android với base URL là địa chỉ host qua Emulator:
   `flutter run -d DEVICE_ID --dart-define=WAYMARK_API_BASE_URL=http://10.0.2.2:5121/api`.
   Thay 5121 bằng cổng vừa xác nhận; dùng đúng scheme. Đăng nhập bằng UI, không
   in/chụp token vào báo cáo. Web dùng Chrome + `http://localhost:PORT/api`.
5. [ ] 4A: quét START thật → map-location đúng node/tầng → Search chọn DEST →
   Preview. Đối chiếu tổng mét và thứ tự node/cạnh với Swagger, không chỉ chữ 40 m.
6. [ ] 4B: đổi Ground/Level 1, kiểm tra chỉ vẽ cạnh cùng tầng, marker chuyển tầng;
   zoom/pan/reset, xoay Emulator và resize Web. Nếu có ảnh thật, kiểm tra node và
   đường bám ảnh. Không có ảnh: phải ghi rõ chỉ là sơ đồ node. Chặn GET graph một
   tầng trên Web: thông báo lỗi và vẫn chọn được tầng khác; mở lại và Retry.
7. [ ] 4C: bắt đầu Navigation, đứng yên ít nhất một phút: không tự tăng bước. Next,
   Previous, chuyển tầng, tới đích và Kết thúc về Preview. Test start=destination.
   Phải giữ đăng nhập, không tự gửi route lại khi chỉ kết thúc Navigation.
8. [ ] 4D: QR node hiện tại giữ tiến độ; QR kế tiếp tiến đúng một bước, đánh dấu
   nguồn QR; dùng Next thủ công sau đó phải hiển thị nguồn thủ công riêng.
9. [ ] 4D: QR bước xa hiển thị xác nhận. Hủy giữ nguyên; đồng ý chuyển nhưng các
   bước giữa vẫn chưa xác nhận. Node lặp phải chọn lần xuất hiện, không tự chọn;
   kiểm tra chọn bước xa rồi Hủy. Không có QR/dữ liệu tương ứng: ghi BLOCKED.
   Ca node lặp đã có fixture tự động; Dijkstra với cạnh có khoảng cách dương
   không sinh tuyến ngắn nhất có chu trình. Không sửa graph thật để ép ca này.
10. [ ] 4D: QR sai tầng, ngoài tuyến, không tồn tại, chưa liên kết node, nội dung
    không hợp lệ; lỗi camera/quyền camera, API offline, JWT hết hạn. Tiến độ/tuyến
    không đổi. QR ngoài tuyến chỉ đề nghị reroute, không tự nhảy. Không tạo/xóa
    node/WayMark thật để thử; thiếu dữ liệu thì ghi BLOCKED, không coi là đã pass.
11. [ ] 4E: QR ngoài tuyến có sẵn → Hủy: không POST routes, tiến độ giữ nguyên.
    Quét lại → đồng ý: giữ đích và bộ lọc, response hợp lệ mới thay tuyến, node đầu
    khớp QR. Trở lại Preview phải thấy tuyến mới. Thiếu QR ngoài tuyến: BLOCKED.
12. [ ] 4E: mạng ngắt/timeout/401/404/409/422/503 khi reroute giữ tuyến/tiến độ cũ;
    phục hồi mạng rồi thử lại. Rời Navigation lúc request đang chờ: response muộn
    không đổi màn hình hoặc gọi callback Preview. Không sửa JWT secret để thử lỗi.
13. [ ] Options: AvoidStairs không đi Stairs; preference không bị coi như hạn chế
    cứng; accessibleOnly không được ghi là đã an toàn xe lăn. Wheelchair phải bị
    chặn; không tự fallback tuyến thường, kể cả sau reroute.
14. [ ] Web MapBuilder: chọn hierarchy thật; PNG/JPG hợp lệ, file hỏng/sai MIME/quá
    lớn; di chuyển node khi zoom/pan; thêm cạnh có hướng bằng mét đo; export và xác
    nhận file tải xong. Import cùng tầng giữ dữ liệu; sai tầng/JSON hỏng bị từ chối
    và draft cũ còn nguyên. Hủy picker/đổi tầng/Back/drawer không mất draft. Theo
    dõi Network: chỉ GET maps/map-location, không POST upload/publish/SQL.
15. [ ] Settings: Back từ trang đã push, Back hệ thống, mở trực tiếp không có route
    trước và đóng drawer. Quay lại Home không tạo vòng lặp, token vẫn dùng được.

## Phân loại Git và file dự kiến commit

Trước khi thêm báo cáo này có 100 file thay đổi/chưa theo dõi: 26 source, 17 test,
6 docs, 6 assets font/license, 3 cấu hình build và 42 design-reference. Không có
migration/schema thay đổi hoặc build artifacts được Git theo dõi trong diff này.
`bin/`, `obj/`, `waymark/build/`, `.dart_tool/` được ignore; ảnh fixture test ở
`.dart_tool/sprint-previews/` cũng không phải source cần commit.

**Không đưa vào commit sprint mặc định:**

- `waymark/design-reference/figma-make/**`: 42 file export do người dùng cung cấp,
  gồm TSX/CSS, package/lock và `.figma/make` tooling; chỉ làm tài liệu tham chiếu.
  Không chạy script của export; pubspec không bundle thư mục này. Nếu cần lưu
  reference trong Git, review license/metadata và commit riêng theo quyết định người dùng.
- `waymark/android/gradle.properties`: thay đổi có sẵn `kotlin.incremental=false`,
  đã giữ nguyên; chỉ đưa vào commit cấu hình Android riêng nếu người dùng muốn.
- Build output/APK/Web bundle, bin/obj/cache, cấu hình local/secrets và ba file
  Windows generated. Hash ba file Windows, gradle.properties và appsettings.json
  vẫn khớp baseline; không reset hoặc ghi đè các file này.

Danh sách 58 file cụ thể bên dưới chỉ là đề xuất; chưa stage/commit bất kỳ file nào.

```text
docs/development/AutonomousSprint.md
docs/development/FinalRegressionReview.md
docs/development/MapNavigationSprint.md
docs/routing/FlutterFloorMap4B.md
docs/routing/FlutterNavigation4C.md
docs/routing/FlutterQrNavigation4D.md
docs/ScannerSettingsAndroid.md
WayMark.Api.Tests/RouteApiTests.cs
WayMark.Api.Tests/RoutingOptionsTests.cs
WayMark.Api/Contracts/RouteDtos.cs
WayMark.Api/Controllers/RoutesController.cs
WayMark.Api/Services/Routing/DijkstraRouter.cs
WayMark.Api/Services/Routing/RoutePlanner.cs
WayMark.Api/Services/Routing/RoutingOptions.cs
waymark/assets/fonts/Inter-Bold.ttf
waymark/assets/fonts/Inter-Medium.ttf
waymark/assets/fonts/Inter-Regular.ttf
waymark/assets/fonts/Inter-SemiBold.ttf
waymark/assets/fonts/OFL.txt
waymark/assets/fonts/README.md
waymark/lib/core/theme/map_ui_theme.dart
waymark/lib/features/admin/admin_page_shell.dart
waymark/lib/features/admin/draft_files.dart
waymark/lib/features/admin/draft_files_stub.dart
waymark/lib/features/admin/draft_files_web.dart
waymark/lib/features/admin/draft_map.dart
waymark/lib/features/admin/draft_map_editor.dart
waymark/lib/features/admin/floor_plan_asset.dart
waymark/lib/features/admin/map_builder_page.dart
waymark/lib/features/admin/settings_page.dart
waymark/lib/features/navigation/manual_navigation.dart
waymark/lib/features/navigation/navigation_page.dart
waymark/lib/features/navigation/reroute_navigation.dart
waymark/lib/features/route/floor_plan_canvas.dart
waymark/lib/features/route/floor_route_geometry.dart
waymark/lib/features/route/floor_route_map.dart
waymark/lib/features/route/route_preferences.dart
waymark/lib/features/route/route_preview_page.dart
waymark/lib/features/scanner/scanner_page.dart
waymark/lib/models/route_models.dart
waymark/lib/services/waymark_api_service.dart
waymark/pubspec.lock
waymark/pubspec.yaml
waymark/test/draft_map_test.dart
waymark/test/fixtures/qr_navigation_fixture.dart
waymark/test/fixtures/routing_fixture.dart
waymark/test/floor_plan_canvas_test.dart
waymark/test/floor_route_map_test.dart
waymark/test/manual_navigation_test.dart
waymark/test/map_layout_test.dart
waymark/test/navigation_page_test.dart
waymark/test/navigation_qr_flow_test.dart
waymark/test/navigation_qr_match_test.dart
waymark/test/route_preferences_test.dart
waymark/test/routing_flow_test.dart
waymark/test/routing_options_test.dart
waymark/test/scanner_camera_test.dart
waymark/test/settings_navigation_test.dart
```
