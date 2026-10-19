# WayMark Phase 7B-1 — sơ đồ tầng trực quan

Ngày review/triển khai: **2026-10-19**, branch `auth-jwt-assignment`.

## Trạng thái

**GO cho bản nháp cục bộ; chưa sẵn sàng production.**

Ngày 2026-10-19, người dùng xác nhận **6/6 kiểm thử thủ công trên Chrome đạt**:

| Kiểm thử thủ công | Kết quả người dùng xác nhận |
| --- | --- |
| PNG/JPG hiển thị đúng trên canvas chính | Đạt |
| Fit Image không làm biến dạng ảnh | Đạt |
| Ẩn/Hiện mặt bằng | Đạt |
| Zoom/pan đồng bộ ảnh và graph | Đạt |
| Kéo node và Preview Route | Đạt |
| Export/import JSON v2 khôi phục ảnh và graph | Đạt |

Đây là kết quả nghiệm thu do người dùng cung cấp, không phải tuyên bố agent đã
tự chạy lại cả sáu tình huống. Bản sửa canvas và bằng chứng Chrome riêng được ghi
trong [FloorPlanCanvasRenderingFix.md](FloorPlanCanvasRenderingFix.md).
Baseline tự động sau bản sửa: 147 Flutter tests đạt, 1 browser-only test skip trên VM.

Phạm vi GO chỉ gồm editor/preview và file nháp cục bộ. Chưa publish/upload server,
chưa phê duyệt dữ liệu bản đồ cho bệnh nhân, chưa hoàn tất **Phase 7A Authorization**.
Không dùng kết quả 6/6 để coi bản đồ hoặc phân quyền production đã an toàn.

Các ghi chú môi trường và kết quả 144 tests bên dưới là **lịch sử lượt triển khai
ban đầu, trước bản sửa canvas và nghiệm thu 6/6**; không còn là trạng thái chờ Chrome.

## Nguyên nhân lỗi ảnh

Luồng cũ đọc được bytes bằng File.arrayBuffer, sau đó gọi
`FloorPlanAsset.validate` → `ImageDescriptor.encoded` → `descriptor.width/height`.
Trong SDK Web đang dùng, `C:/src/flutter/bin/cache/flutter_web_sdk/lib/ui/painting.dart`,
ImageDescriptor encoded chỉ giữ bytes; width/height gọi `_throw` với thông báo
`ImageDescriptor.width is not supported on web.` / height tương tự. Lỗi xảy ra
trước phép gán `draft.image`, nên không có ảnh mới cho MemoryImage/canvas.

Test cũ chạy trên Dart VM, nơi descriptor đọc được kích thước, nên không bắt được
khác biệt Web này. Phản hồi cũ là dòng text chung phía trên workspace; không lưu
tên ảnh và không có thumbnail/trạng thái giải mã cụ thể, khiến lỗi khó nhận ra.
Đây là bằng chứng từ source/SDK, không phải kết luận rằng picker chưa đọc file.

Decoder mới đọc kích thước PNG IHDR/JPEG SOF để kiểm tra giới hạn trước khi cấp
phát pixel, rồi dùng `instantiateImageCodec` và `getNextFrame` để giải mã thật.
Kích thước lấy từ frame đã giải mã, dùng được trên native/Web; codec/image được
dispose. Chỉ gán ảnh vào draft sau khi toàn bộ kiểm tra đạt. Lỗi hoặc hủy giữ ảnh
và graph cũ. MIME trống từ OS được suy ra nhưng extension/magic/decode vẫn phải
khớp; MIME được cung cấp mà sai bị từ chối.

## Chức năng đã triển khai

- Panel mặt bằng: thumbnail, tên file, kích thước pixel/dung lượng, tầng đang sửa,
  nút chọn/thay PNG/JPG, giới hạn 10 MB, 8192 px mỗi chiều và 32 MP.
- Có thông báo đang đọc/giải mã, banner + snackbar thành công/lỗi/hủy. Sau tải
  thành công, workspace cuộn tới canvas. File picker gắn vào DOM và được dọn sau
  chọn/hủy; URL download chỉ revoke sau khi browser có thời gian bắt đầu tải.
- Canvas dùng ảnh thật đã chọn, BoxFit.contain; ảnh/painter/hit testing cùng một
  vùng nội dung. Zoom/pan/reset đồng bộ. Tọa độ lưu chuẩn hóa 0–1 trên ảnh, không
  dùng pixel để suy ra mét.
- Edit Graph: tạo node, chọn và kéo node, chỉnh tên/loại/QR đề xuất, xóa node với
  xác nhận và xóa các cạnh liên quan **chỉ trong draft**. Kéo bị hủy không đổi
  tọa độ đã lưu. Pan dùng công cụ riêng; chạm vào cạnh để chọn/sửa/xóa.
- Cạnh có hướng: tạo/sửa đầu-cuối, loại cạnh và khoảng cách dương do người dùng
  nhập. Đường hai chiều cần hai cạnh. Không tự suy ra hành lang đi được từ ảnh.
- Ký hiệu: hành lang/lối vào tròn, QR đề xuất vuông Q, đích hình thoi, thang máy E,
  cầu thang T, cạnh có mũi tên. QR trong draft không làm thay đổi liên kết server.
- Preview Route: chọn node đầu/cuối; bắt buộc đối chiếu graph với ảnh bằng checkbox
  cho lần xem trước. Chỉ vẽ node/cạnh thuộc tuyến tìm được, không vẽ graph chỉnh
  sửa. Có trạng thái không có đường, một node và chưa chọn tuyến.
- Preview tính trên graph có hướng **của một tầng nháp**, bằng khoảng cách cạnh đã
  nhập; không gọi/thay backend Dijkstra, không dùng AuthSession mới và không chuyển
  sang Navigation production. Mọi sửa graph/ảnh làm mất xác nhận alignment cũ.
- Bố cục ba vùng trên màn hình rộng, xếp dọc trên màn hình hẹp; màu/font dùng hệ
  thống hiện có, tham khảo Figma Make mới, không nhúng React/source Figma vào build.

Chọn ảnh mới **giữ graph để người dùng căn lại**, kèm cảnh báo và vô hiệu hóa
alignment đã xác nhận. Không tự xóa graph hoặc giả định tọa độ cũ khớp ảnh mới.
Đổi tầng/hierarchy có guard bản nháp chưa export; mỗi file là một tầng. Không có
lưu bền tự động: cần lưu JSON trước refresh/đóng tab hoặc đồng ý bỏ draft.

## Định dạng bản nháp

Version 2 JSON chứa status=draft, verifiedForPatientUse=false, Site/Building/Floor
IDs, metadata tầng, node/cạnh và object ảnh `{name,mime,width,height,byteLength,
dataBase64}`. **Ảnh bytes thực được nhúng Base64**, không phải chỉ đường dẫn máy.
File tối đa 18 MB; graph tối đa 2000 node/10000 cạnh. Export kiểm tra giới hạn để
file tạo ra có thể import lại. Bản nháp version 1 có imageBase64 vẫn import được.

Import kiểm tra hierarchy/version, shape JSON, mã trùng/enum/X/Y, FK cạnh, self-loop,
khoảng cách, image decode và metadata ảnh trước khi thay state. File lỗi giữ draft
cũ. Không tin verified/accessibility trong file; chưa xác minh cho bệnh nhân và
phải kiểm tra alignment lại sau import. Global NodeCode, liên kết QR đề xuất và
quyền xuất bản vẫn cần server xác minh trong phase sau.

## Tham khảo Figma đã đọc

`waymark/design-reference/figma-make/`:

- `src/pages/admin/MapBuilder.tsx`
- `src/components/map-builder/MapCanvas.tsx`, `model.ts`, `AIAnalysis.tsx`
- `src/pages/mobile/Navigation.tsx`, `RoutePreview.tsx`
- `src/index.css`

Áp dụng luồng upload → nhìn ảnh → sửa graph → preview và cấu trúc panel/canvas.
Không sao chép floorArtwork, seedDocument, suggestions/confidence AI giả, role
switcher, publish giả, tuyến minh họa hoặc timer. Không tuyên bố khớp từng pixel
với screenshot Figma Make; đầu vào tham khảo là source TSX/CSS do người dùng cung cấp.

## Files của riêng Phase 7B-1

Thay đổi source hiện có:

1. `waymark/lib/features/admin/floor_plan_asset.dart`
2. `waymark/lib/features/admin/draft_files_web.dart`
3. `waymark/lib/features/admin/draft_map.dart`
4. `waymark/lib/features/admin/draft_map_editor.dart`
5. `waymark/lib/features/route/floor_plan_canvas.dart`

Tạo mới:

6. `waymark/lib/features/admin/draft_file_gateway.dart`
7. `waymark/test/draft_floor_workflow_test.dart`
8. `waymark/test/support/map_builder_visual_main.dart` — harness test riêng, không
   được import từ lib/main.dart hoặc route của ứng dụng.
9. `docs/ai/FloorPlanProposalV1.schema.json`
10. `docs/ai/FloorPlanProposalV1.md`
11. Tài liệu này.

Các thay đổi Git của sprint trước vẫn giữ nguyên. Không sửa source backend, JWT,
QR, routing options, Dijkstra, rerouting, SQL, migrations, Gradle hoặc Windows
generated trong phase này. Shared FloorPlanCanvas chỉ thêm callbacks drag tùy
chọn cho editor; production không truyền callbacks đó.

## Lịch sử kiểm thử tự động trước bản sửa canvas

| Kiểm tra | Kết quả |
| --- | --- |
| `flutter analyze --no-pub` | Đạt, không có issue |
| `flutter test --reporter expanded` | 144 đạt, 1 test browser-only skip trên VM |
| `flutter build web --no-pub` | Đạt: 71.4 giây, build/web, Wasm dry run thành công |
| Backend test project, isolated artifacts | 60/60 đạt, không skip; warning NU1900 vì vulnerability feed không truy cập được |
| `git diff --check` | Đạt; có thông báo Git chuẩn hóa LF/CRLF ở file sprint trước |

8 test mới bao gồm PNG/JPG decode, ảnh hỏng/quá giới hạn/MIME, round-trip ảnh bytes
và graph/metadata, import v1, file sai tầng/metadata/node/cạnh/approval, preview có
hướng/không có đường/một node, kéo dưới zoom lưu X/Y, chỉnh/xóa cạnh và xác nhận
xóa node, preview ẩn graph, responsive rộng/hẹp. Tests dùng file gateway/camera/HTTP
fake; không ghi SQL. Các test hồi quy Navigation 4A–4E và AuthSession vẫn đạt.

Các lần pumpAndSettle ban đầu bị timeout do native image decode/re-cache trong
widget fake async; test hiện nhường real async có giới hạn và precache ảnh trước
khi settle. Không bỏ qua test lỗi. Một lệnh dart fix mất nhiều thời gian; phiên
lệnh có test khởi động sau đó đã được ngắt, rồi chạy lại các lệnh test hoàn chỉnh.

Ảnh render fixture đã được xem để xác nhận canvas có background + node + thumbnail:
`waymark/.dart_tool/phase7b/editor-1600.png` (artifact ignore, không commit).
Có thể tái tạo:

```powershell
cd D:\project\WayMark\waymark
flutter test --no-pub --reporter expanded --dart-define=WAYMARK_CAPTURE_FLOOR_EDITOR=true test/draft_floor_workflow_test.dart
```

Harness Web fixture đã build thành công trước khi chỉnh màu chip cuối cùng:
`flutter build web --no-pub --target test/support/map_builder_visual_main.dart --output .dart_tool/phase7b/web`.
Một static server test chưa chạy được do Execution Policy chặn file PS1; không đổi
Execution Policy. Computer Use dừng vì không xác định được URL, nên không kiểm thử
file dialog Web bằng UI thật trong lượt này. Không dùng đường khác để tiếp tục
điều khiển browser sau khi công cụ dừng. Không tuyên bố Web UI đã nghiệm thu.

## Hướng dẫn tự thử bằng ảnh của bạn

1. Chạy backend đã được thiết lập, ghi nhận URL/port thực tế; không chạy migration
   hoặc seed. Từ `waymark/` chạy Flutter Web mới:

   ```powershell
   flutter run -d chrome --dart-define=WAYMARK_API_BASE_URL=http://localhost:5121/api
   ```

   Thay port/scheme bằng listener backend thực tế. Full restart để bảo đảm dùng
   source mới; giữ quy trình đăng nhập JWT hiện có.
2. Vào Map Builder → chọn Site → Building → Floor từ API. Bấm **Chọn ảnh PNG/JPG**
   ở panel Mặt bằng tầng. Chọn ảnh tĩnh dưới giới hạn. Cần thấy banner “Đã tải…”,
   tên ảnh, thumbnail, pixel size và chính ảnh đó trên canvas. Nếu không thấy,
   gửi screenshot + dòng lỗi (không gửi token); chưa coi bước này là thành công.
3. Dùng **Thêm node** rồi chạm lên ảnh, nhập code namespace riêng và tên/loại.
   **Chọn** rồi kéo node để sửa vị trí; dùng **Pan** để di chuyển bản đồ và wheel/
   pinch để zoom, nút góc dưới để reset. Chọn node để sửa/xóa; node QR phải nhập
   WayMarkCode có thật và được API đối chiếu, chỉ là đề xuất nháp.
4. **Thêm cạnh có hướng**: chọn đầu/cuối, EdgeType và mét đo được. Chọn đường trên
   ảnh hoặc kết nối trong thuộc tính node để sửa cạnh; muốn hai chiều, thêm cạnh
   ngược. Tự kiểm tra không xuyên tường, cửa/lối đi và các giới hạn thực tế.
5. Chuyển **Preview Route**, đối chiếu graph với ảnh rồi tick xác nhận cục bộ,
   chọn xuất phát/đích và **Xem tuyến nháp**. Chỉ tuyến đang chọn được vẽ. Nếu
   không có đường, sửa graph trong Edit Graph; không có tuyến giả hoặc bỏ hạn chế.
6. **Lưu bản nháp JSON + ảnh**, kiểm tra download thực sự tồn tại. Mở file có
   object image.dataBase64. Chọn **Mở bản nháp JSON** trên đúng tầng và xác nhận
   bỏ draft đang sửa khi cần: ảnh/node/cạnh/X/Y phải trở lại. Thử file hỏng, sai
   tầng hoặc thay ảnh hỏng: phải thấy lỗi và dữ liệu hiện tại giữ nguyên.
7. Đổi tầng và resize Web để kiểm tra không mang ảnh/transform tầng trước sang
   tầng mới. Export trước khi đổi tầng/đóng tab. Bản nháp một tầng không tự dựng
   tuyến liên tầng hoặc đồng bộ các tầng chưa có trong file.

Nếu backend chưa chạy nhưng cần kiểm tra ảnh không dùng SQL, dùng harness riêng:

```powershell
flutter run -d chrome -t test/support/map_builder_visual_main.dart
```

Trang này phải có nhãn **VISUAL TEST ONLY — API fixture, no SQL, no publish**.
Ảnh do bạn chọn vẫn đi qua gateway/decoder/canvas thật; hierarchy là fixture cho
test. Không dùng harness này làm bản build giao cho người dùng.

## Trước khi dùng bản đồ thật / AI

- Navigation production hiện đọc FloorPlanImageUrl từ API graph; ảnh URL hợp lệ
  được hiển thị bằng NetworkImage trên cùng FloorPlanCanvas. Khi chưa có URL,
  vẫn là sơ đồ node. **Ảnh draft không tự đi vào Navigation production**.
- Cần khảo sát và căn node với ảnh đúng tầng, đo mét, kiểm tra cửa/hành lang,
  chiều đi, chuyển tầng và accessibility. Preview cục bộ không chứng nhận bản đồ.
- Lưu server, upload/publish ảnh, duyệt map, authorization admin/reviewer và audit
  log đều chờ **Phase 7A Authorization**; không thêm API ghi trong 7B-1.
- Hợp đồng AI Rooms/Corridors/Doors/Stairs/Elevators/NavigationNodes/Edges,
  confidence và review trạng thái nằm trong `docs/ai/`. Chỉ là hợp đồng thiết kế:
  chưa gọi LM Studio, chưa có validator AI runtime hay tự chuyển đề xuất thành
  dữ liệu production. Confidence không thay thế người kiểm tra; không suy mét từ ảnh.
