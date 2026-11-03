# Mẫu lượt đo Published Pilot — KHÔNG CÓ SỐ LIỆU THỰC TẾ ĐIỀN SẴN

Ngày tạo mẫu: 28/10/2026. Mỗi bản sao ứng với một lượt. Không dùng mét trong Local Pilot synthetic làm ground truth.

## Chuẩn bị

- Chọn hành lang thẳng 10–20 m đo bằng thước; đánh dấu đầu/cuối, đúng geometry trên Published map đã được phép dùng.
- Hai người nếu có thể: người đi và người đếm tay/ghi thời điểm. Dùng mã ẩn danh P1/P2 và máy A/B; không cần tên thật, serial hoặc raw GUID.
- Ghi các lần thất bại/gián đoạn, không loại bỏ để làm đẹp trung bình. Đứng yên 10–30 giây là ca riêng có ground truth 0.
- Lưu endpoint error **trước** khi quét QR; sau QR phải đo lại nếu muốn ghi số, không tự điền 0.
- App form chỉ ghi số đo/arithmetics, không hiệu chuẩn PDR hoặc cập nhật SQL/History. Bật/tắt Live riêng.

## Bảng một lượt — để trống nếu chưa đo

| Trường | Giá trị người thử nhập |
|---|---|
| Trial alias (không PII) | |
| Người/máy ẩn danh, model/Android API nếu biết | |
| Phase: đi thẳng / đứng yên / quay / đi ngược / lifecycle / correction | |
| Published version (chỉ số version, không raw GUID/token) | |
| Bắt đầu / kết thúc, múi giờ | |
| Quãng đường đo thật (m) | |
| Số bước đếm tay | |
| StepDetector events trong cùng cửa sổ | |
| Accepted displacement observations trong cửa sổ | |
| Rejected movement observations | |
| Stride đã cấu hình (m/bước), đã đo hay chỉ ước lượng | |
| WayMark estimated integrated distance trong lượt (m) | |
| Endpoint error đo trước QR (m, nêu cách đo) | |
| Endpoint error đo sau QR (m, chưa đo thì để trống) | |
| False detector events khi đứng yên | |
| Cách cầm / hướng đỉnh máy / đổi tay / bỏ túi | |
| Uncertain có/không/chưa ghi; reason | |
| Có dừng vì budget? / cần chọn hành lang lại? | |
| QR correction result/code, không payload | |
| Overflow / pause/resume / gián đoạn | |
| Hoàn tất / FAIL / incomplete và nguyên nhân | |
| Ghi chú điều kiện đã loại PII | |

## Phép tính có thể suy ra

- Detector step bias = detector events − bước đếm tay.
- Relative step error = bias / bước đếm tay, chỉ khi bước đếm tay >0.
- Distance bias = WayMark estimated distance − quãng đo thật.
- Relative distance error = distance bias / quãng đo thật, chỉ khi quãng đo >0.
- Ground truth =0: dùng số false events và estimated displacement, không chia cho 0.
- **Distance bias không phải measured endpoint position error.** Đi sai nhánh/quay đầu có thể làm hai giá trị khác hẳn nhau.
- Không tự điền after-QR error bằng 0; QR xác nhận node qua resolver không chứng minh biển đặt đúng vật lý.
- Không ghi accuracy radius/p95/mean khi chưa có mẫu thực tế. Khi tổng hợp, phân nhóm model/người/cách cầm/hướng và giữ cả lượt lỗi.

Gửi kèm sanitized JSON nếu đồng ý; không gửi token, endpoint có secrets hoặc trace vị trí riêng tư.
