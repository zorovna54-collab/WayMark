# WayMark — phạm vi bản mẫu

## Existing Mobile Screens
Giữ nguyên Trang chủ `/`, Tìm kiếm `/search`, Lịch sử `/history`,
Đăng nhập `/login`, Đăng ký `/register` và cấu trúc quản trị.
Đăng nhập/đăng ký chưa kết nối xác thực JWT.

## Enhanced Indoor Navigation
`/preview`: sơ đồ hai tầng G/L1, chọn tầng, bảng hướng dẫn thu gọn,
điểm bắt đầu/đích và chuyển sang `/navigation`.
`/navigation`: tiến trình chỉ thay đổi sau hành động người dùng.
Vòng tròn nét đứt biểu thị QR gần nhất, hình vuông vàng biểu thị
chặng do người dùng xác nhận. Không dùng GPS hay bộ đếm tự báo đến.

## QR Relocalization
`/scanner?mode=relocalize`: chọn một trong sáu tình huống QR rồi nhấn
“Mô phỏng quét QR”. Không dùng camera thực tế. Mọi cập nhật cần xác nhận.
QR ngoài tuyến dẫn tới yêu cầu tính lại, nhưng không chạy Dijkstra;
giao diện giải thích rõ tuyến còn là tuyến mẫu.

## Accessible Routing
Chọn tùy chọn tuyến ở `/preview`. Có cảnh báo khi chưa có tuyến xe lăn
đã kiểm chứng. Tùy chọn chưa làm thay đổi đồ thị hay tính toán tuyến.
Mọi sơ đồ và thông tin tiếp cận là dữ liệu minh họa.

## Admin Map Management
`/admin/map-builder` gồm bốn tab: Trình chỉnh sửa, Mặt bằng,
Phân tích AI và Kiểm tra & xuất bản.

- Ảnh PNG/JPG được đọc cục bộ, hiện ngay trên canvas; có kéo thả,
  kiểm tra định dạng, giới hạn 20 MB, kích thước và dung lượng.
- Mỗi bệnh viện/tòa/tầng có ảnh, đồ thị và lịch sử riêng. Tòa A có
  hai tầng mẫu; tòa B và cơ sở 2 bắt đầu ở trạng thái trống.
- Thêm, kéo, chọn, xóa nút/QR; chỉnh phòng, cửa, hành lang,
  thang máy, cầu thang, đích và thuộc tính tiếp cận.
- Nối cạnh có hướng, chỉnh đầu/cuối, xóa cạnh, undo/redo đồ thị;
  zoom, pan và vừa khung.
- Xem tuyến ẩn các cạnh biên tập; tìm đường có hướng bằng BFS
  trong đồ thị prototype, không phải Dijkstra có trọng số thực tế.
- Lưu nháp hiển thị giờ lưu và phiên bản. Thay đổi đồ thị hủy
  trạng thái kiểm duyệt trước đó.
- Nháp → kiểm tra cấu trúc → chờ duyệt → xuất bản mô phỏng.
  Kiểm tra liên thông, tuyến có hướng, QR, liên tầng và gợi ý AI.
  Cảnh báo tiếp cận phải được người duyệt xác nhận.
- Chuyển vai trò Admin/Reviewer chỉ mô phỏng giao diện phân quyền.
  Xuất bản cần kiểm tra đạt, reviewer duyệt và dialog xác nhận.

Tọa độ canvas chuẩn hóa theo khung 1000 × 660; chưa có hiệu chuẩn
đo lường, kiểm tra xuyên tường hay xác minh tiếp cận thực tế.
Bản nháp, ảnh và phiên bản chỉ tồn tại trong phiên, chưa có API.
Tải lại trang khôi phục dữ liệu mẫu. Không xuất bản ra hệ thống thực.
`/admin/qrs` và `/admin/settings` vẫn giữ route hiện có.

## AI-Assisted Floor Plan Import
Mô phỏng kết nối mô hình thị giác LM Studio, tiến trình phân tích,
ảnh gốc và ảnh chú thích đặt cạnh nhau. Có bảy gợi ý cố định:
phòng, hành lang, cửa, thang máy, cầu thang, mốc QR và cạnh nối.
Cho phép sửa tên/tọa độ, chấp nhận hoặc từ chối từng gợi ý.
Chấp nhận thêm đối tượng vào bản nháp; cạnh cần hai đầu nút đã được duyệt.
Gợi ý còn chờ xử lý sẽ chặn bước kiểm duyệt.

AI không đọc/phân tích tệp thật, không gọi endpoint và không gửi ảnh ra ngoài.
Các phần trăm tin cậy đều là dữ liệu mẫu, không phải đo lường từ mô hình.
Không tự động xuất bản hoặc coi đề xuất là dữ liệu thực địa.
