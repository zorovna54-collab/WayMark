# Phase 9B-2 — Android custom map navigation

## Kết quả

GO cho **xem trước cục bộ, một tầng**, không phải bản đồ đã publish hoặc chứng nhận lối đi an toàn.

- Builder → Validate Map → Thử dẫn đường → chọn start node/phòng → Route Preview → Navigation thủ công → quay lại Builder.
- Không bắt export/import để thử: tạo snapshot độc lập ngay từ bản nháp đang chỉnh. Không sửa bản nháp khi chọn tuyến hoặc đi từng bước.
- Dijkstra dùng cạnh có hướng, active và khoảng cách mét đã nhập. Với nhiều cửa, chọn Entrance có tuyến đi được ngắn nhất; không dùng tâm/nhãn phòng làm đích.
- Validation chặn tham chiếu sai, GUID/code trùng, tọa độ sai, mét chưa nhập, Room thiếu Entrance. Cảnh báo riêng node cô lập, thiếu ảnh và an toàn Unknown.
- Snapshot giữ ảnh và tọa độ; map painter hiện có vẽ tuyến/nhãn phòng trên cùng hệ tọa độ. Fit Image và zoom/pan dùng chung transform.
- Route và graph chỉ được dùng với snapshot phát hành chúng. ID local không phải ID SQL; không biến NodeCode thành WayMark QR.
- Local mode không gọi API, không QR/relocalization/rerouting backend, không tùy chọn xe lăn, không timer/GPS. Luồng backend mặc định giữ nguyên.

## File của phase này

- `waymark/lib/features/navigation/local_map_navigation.dart` (mới): validation, snapshot, Room entrance resolution, local route adapter.
- `waymark/lib/features/search/local_map_search_page.dart` (mới): chọn start/tìm phòng cục bộ.
- `waymark/lib/features/admin/draft_map.dart`: tách thuật toán local khỏi yêu cầu xem ảnh của editor.
- `waymark/lib/features/admin/draft_map_editor.dart`, `draft_map_editor_mobile.dart`: Validate/Thử dẫn đường.
- `waymark/lib/features/route/route_preview_page.dart`, `floor_route_map.dart`: tái sử dụng Preview/painter với nguồn local rõ ràng.
- `waymark/lib/features/navigation/manual_navigation.dart`, `navigation_page.dart`: cho phép điểm local không có QR trong mode riêng; giữ xác nhận thủ công.
- `waymark/test/local_map_navigation_test.dart`, `test/fixtures/local_navigation_fixture.dart` (mới); `test/android_map_builder_test.dart`: thuật toán, validation, snapshot isolation, provenance, Preview/Navigation/return và AuthSession.
- `waymark/tool/generate_custom_plan_test.dart`: đầu vào thử riêng, không bundle/default app map.

## Kiểm chứng đã chạy

- `flutter analyze --no-pub`: sạch.
- `flutter test --no-pub --reporter expanded`: **194 đạt, 1 Web-only skip**. Gồm regression QR/rerouting/backend navigation hiện có bằng test tự động, không phải gọi backend/SQL thật trong phase này.
- `flutter build apk --debug --no-pub`: đạt với entrypoint ứng dụng mặc định.
- `flutter build web --no-pub`: đạt.
- `git diff --check`: đạt (Git có thông báo LF/CRLF của workspace hiện có).
- Android `emulator-5554`: chạy editor thật qua `flutter run -d emulator-5554 -t tool/android_map_builder.dart --no-pub`; nhập fixture JSON v2/PNG 900×598 tự tạo, 4 node/2 directed edge/1 Room. Đây là dữ liệu thử nhập vào, không tuyên bố mọi đối tượng đã được tạo thủ công trong lần chạy này.
- Validate cảnh báo đúng node cô lập; START → HALL → DOOR-101 trả **17,25 m**; ảnh và polyline nhìn thấy trong Preview/Navigation. Xác nhận từng bước đến cửa, quay lại và chọn node cô lập: báo không có đường đi, không cho bắt đầu.
- Lưu qua Android SAF thành `waymark-9b2-saved.json`, kéo file về đối chiếu: ảnh, graph, GUID, Room/Entrance và workspace không đổi. Mở lại file trong Builder và thử lại vẫn 17,25 m.
- Screenshot/log/file đối chiếu nằm trong `waymark/build/local-navigation-evidence/` (ignored): `builder.png`, `validation.png`, `preview.png`, `navigation.png`, `arrival.png`, `no-route.png`, `reopened-preview.png`.
- So hash với đầu phase: không sửa backend, Gradle, Windows generated, Figma hoặc các thay đổi ngoài phạm vi có sẵn. Không SQL/migration/commit/push.
- Lượt tiếp tục ngày 22/10: sửa nhãn node khi quay lại bước trước; analyze sạch, chạy lại đủ 194 tests đạt/1 skip, Android debug build và Web build đều đạt. Emulator chưa kết nối tại lần kiểm tra này; screenshot ở trên là bằng chứng lần chạy Android đã ghi nhận, không phải ảnh chụp mới sau sửa nhãn.

## Nghiệm thu (6 bước)

1. Chạy Android ứng dụng bình thường, vào Map Builder; hoặc dùng lệnh tool ở trên để mở trực tiếp cùng editor mà không cần backend/login. Tạo bản đồ mới, chọn ảnh của bạn.
2. Đặt ít nhất 3 node (cửa phòng phải là Entrance), nhập 2 cạnh một chiều với mét đã đo; tạo Room và gắn cửa. Lưu JSON + ảnh nếu muốn giữ sau khi đóng app.
3. Validate Map: sửa lỗi đỏ; đọc cảnh báo Unknown. Bấm Thử dẫn đường → Chọn điểm và phòng, chọn start và tìm Room theo tên/số.
4. Kiểm tra Preview kết thúc tại cửa phù hợp; thử Fit Image, zoom/pan. Bắt đầu, xác nhận bước kế tiếp/bước trước rồi hoàn tất. Không tự tiến bước khi chờ.
5. Quay lại Builder: ảnh/graph/Room còn nguyên. Chọn start cô lập hoặc chiều không đi được: phải báo không có tuyến, không vẽ đường giả.
6. Lưu và mở JSON v2, thử lại cùng start/phòng: tuyến và khoảng cách phải giữ nguyên; không thay đổi AuthSession hoặc tuyến backend.

## Giới hạn

JSON v2 hiện chứa một Floor. Có transitions/liên kết ngoài tầng sẽ bị chặn; hỗ trợ nhiều tầng cần định dạng chứa nhiều floor/image/graph và liên kết chuyển tầng đã đối chiếu. Chưa kiểm chứng lối đi/độ dài ngoài đời, an toàn xe lăn, QR local hoặc publish. Ảnh dùng thử do công cụ test tạo; không phải mặt bằng bệnh viện thật. Kiểm thử QR/backend/camera thực tế trước đó không được chạy lại trong phase này.
