# Phase 9B-2A — Multi-floor local navigation

GO cho project cục bộ nhiều tầng; chưa publish hoặc xác nhận lối đi ngoài thực tế.

## Đã triển khai

- Android Builder thêm, đổi tên, chọn và xóa tầng (xác nhận xóa ảnh/graph/Room/liên kết). Chuyển tầng giữ nguyên các DraftMap riêng; xóa node đang được liên kết tầng hoặc đổi loại node đó bị chặn.
- Project JSON **v3** bọc các floor JSON **v2** và danh sách liên kết có hướng. Ảnh PNG/JPG, kích thước, GUID, Room/Entrance và tọa độ nằm riêng trong từng floor. JSON v2 cũ vẫn nhập được; bản một tầng tiếp tục xuất v2.
- Nối tầng bằng cách chọn hai node Stairs hoặc hai Elevator, nhập mét; có tùy chọn tạo thêm cạnh ngược chiều. Sửa/xóa/active liên kết qua danh sách. Không suy ra liên kết hoặc khoảng cách từ pixel; accessibility luôn Unknown.
- Validation kiểm tra GUID toàn project, mã tầng, tham chiếu đúng floor/node/type và trọng số. Dijkstra dùng snapshot local, tìm cửa đi được ngắn nhất trên toàn project; không gọi graph/backend demo.
- Search phân biệt start/Room theo tầng. Preview/Navigation tái sử dụng UI cũ, đổi đúng ảnh/graph/Room của tầng; cạnh chuyển tầng chỉ hiện hướng dẫn, không vẽ xuyên ảnh. Thao tác xác nhận thủ công giữ nguyên.
- Thay ảnh tầng có graph yêu cầu xác nhận; không sửa tọa độ hoặc mét. Metadata ảnh và tọa độ chuẩn hóa vẫn tách khỏi khoảng cách vật lý. Crop/phối cảnh về sau phải có biến đổi tọa độ được đối chiếu hoặc căn chỉnh lại; chưa tự động hỗ trợ tác vụ đó.
- Quota: 1–12 tầng; project tối đa 64 MB, mỗi ảnh theo giới hạn 10 MB/codec hiện có; local routing tối đa 2000 node/10000 cạnh, 1000 liên kết tầng. Android SAF giới hạn tăng tương ứng, không thêm quyền storage.

## File thay đổi trong phase

Mới:

- `waymark/lib/features/admin/local_map_project.dart`
- `waymark/lib/features/admin/draft_map_editor_project.dart`
- `waymark/test/fixtures/multifloor_fixture.dart`
- `waymark/test/multifloor_navigation_test.dart`
- `waymark/tool/generate_multifloor_test.dart`
- Tài liệu này.

Cập nhật:

- `waymark/lib/features/admin/draft_map_editor.dart`, `draft_map_editor_mobile.dart`
- `waymark/lib/features/navigation/local_map_navigation.dart`
- `waymark/lib/features/search/local_map_search_page.dart`
- `waymark/lib/features/route/floor_route_map.dart`
- `waymark/android/app/src/main/kotlin/com/example/waymark/MainActivity.kt` (quota picker/save 64 MB)
- `waymark/test/android_map_builder_test.dart` (scroll đến nút sau khi thêm bộ chọn tầng).

## Kiểm chứng

- `flutter analyze --no-pub`: sạch.
- `flutter test --no-pub --reporter expanded`: **200 đạt, 1 Web-only skip**.
- `flutter build apk --debug --no-pub`: đạt với `lib/main.dart`.
- `git diff --check`: đạt.
- Test mới: round trip ba ảnh/graph độc lập; v2 import; cùng tầng/xuyên tầng/không có kết nối/chiều ngược; GUID trùng và sai loại cửa chuyển tầng; snapshot độc lập; thêm/đổi tên/xóa/chọn tầng; UI khai báo cạnh ngược có chủ đích; Navigation đổi tầng, không vẽ cạnh liên tầng lên canvas và hoàn tất tại Entrance.
- Đã chạy editor thật trên `emulator-5554`: nhập fixture G/I/II, ba ảnh màu riêng và 9 node/9 cạnh cùng tầng/2 cạnh cầu thang. START tầng G → Room 301 tầng II: **30 m**, 5 node/4 chặng; xác nhận thủ công qua tầng I và II rồi hoàn tất tại cửa. Quay lại Builder giữ project và chọn được ảnh tầng II riêng (240×200).
- Lưu project qua Android picker, kéo file về: **trùng byte** fixture ban đầu, đủ 3 floor/2 link. Việc mở lại và tính tuyến được kiểm tra tự động; không tuyên bố đây là bản đồ bệnh viện thật hoặc mọi đối tượng được tạo thủ công trong lần chạy emulator.
- Bằng chứng (ignored): `waymark/build/multifloor-evidence/preview-g.png`, `navigation-i.png`, `navigation-ii.png`, `arrival-ii.png`, `builder-ii.png`, `saved-project-v3.json`, `tests.txt`, `android-build.txt`.
- Không sửa backend, SQL, migration, Gradle, Windows generated, JWT hoặc Figma. Không commit/push/reset/clean; các thay đổi có sẵn được giữ lại.

## Chạy và nghiệm thu — 6 bước

Từ `D:\project\WayMark\waymark`: `flutter run -d emulator-5554 -t tool/android_map_builder.dart --no-pub` mở cùng editor thật trực tiếp để thử offline; ứng dụng bình thường vẫn vào Builder qua luồng cũ.

1. Bản đồ mới → tầng G → ảnh của G; Thêm tầng I/II và chọn ảnh riêng. Chuyển qua lại để kiểm tra ảnh/graph không mất.
2. Đặt node hành lang, Stairs/Elevator và Entrance; nhập cạnh có hướng bằng mét; tạo Room và gắn cửa ở đúng tầng.
3. Nối tầng → chọn đúng hai node khác tầng cùng loại → nhập mét. Chỉ bật tạo cạnh ngược khi lối đi thực sự cho phép; mọi thuộc tính tiếp cận còn Unknown.
4. Validate Map → Thử dẫn đường → chọn start G và Room II. Kiểm tra Preview từng tầng/Fit/zoom; Navigation chỉ chuyển bước sau xác nhận.
5. Hoàn tất tại cửa → quay lại Builder; thử thiếu liên kết/chiều không đi được phải báo không có đường, không vẽ giả.
6. Lưu JSON + ảnh → mở lại project → thử cùng start/Room; kiểm tra ảnh, Entrance và khoảng cách giữ nguyên. Thử đổi tên/xóa tầng có xác nhận trước khi xóa.

Giới hạn: chưa publish, chưa QR local/GPS, chưa chứng nhận accessibility hoặc mét/lối đi thực tế; ảnh chụp bệnh viện thật cần đối chiếu thủ công. Fixture ảnh đơn giản dùng màu riêng để kiểm chứng lớp ảnh, không phải dữ liệu production. JSON v3 chỉ dùng local, chưa nối với server draft APIs.
