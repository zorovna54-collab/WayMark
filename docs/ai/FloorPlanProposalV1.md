# Hợp đồng đề xuất AI vision — Phase 7B-1

Đây là thiết kế cho bước tiếp theo, **chưa có client gọi LM Studio hoặc importer
AI trong runtime**. JSON Schema: `FloorPlanProposalV1.schema.json` (2020-12).
Không sao chép suggestions, timer, confidence hoặc role giả từ Figma Make.

## Request dự kiến

Client giữ context tin cậy `{requestId, siteId, buildingId, floorId, imageSha256,
decodedWidth, decodedHeight, revision}` và gửi ảnh PNG/JPG đã kiểm tra cùng yêu cầu
trả JSON theo schema. Endpoint/model/capability vision phải được xác minh ở phase
AI, chưa gọi trong 7B-1. Không gửi JWT của WayMark hoặc dữ liệu bệnh nhân vào prompt.
Text OCR trên ảnh và output model đều là dữ liệu không tin cậy, không phải chỉ dẫn
thực thi; không dùng làm URL, câu SQL, quyền truy cập hoặc lệnh publish.

## Response và quy tắc bắt buộc

- Rooms/Corridors: polygon chuẩn hóa 0–1 trên đúng ảnh đã giải mã, gốc trên trái.
- Doors/Stairs/Elevators: landmark trên ảnh; nhãn cần người quản trị đối chiếu.
- NavigationNodes: proposal ID `AI-*`, label, loại node theo enum hiện tại và X/Y.
  Proposal ID không phải database ID, NodeCode hoặc WayMarkCode. Không gắn QR tự động.
- NavigationEdges: một hàng là một hướng, tham chiếu proposal node, polyline,
  EdgeType. `distanceMeters=null`: ảnh chuẩn hóa không cung cấp mét; người khảo sát
  phải nhập khoảng cách trước khi đưa cạnh vào DraftMap hiện tại.
- Confidence 0–1, reviewStatus=pending, requiresVerification=true, evidence và
  warnings. Confidence cao không có nghĩa đã được phê duyệt hoặc phù hợp xe lăn.
- Accessibility luôn unverified; không tự tạo IsAccessible=true. Thang máy trên
  một ảnh chưa chứng minh liên kết tầng; quản trị viên phải đối chiếu các tầng.
- Rooms/Doors là annotation đề xuất, không thêm enum/bảng nghiệp vụ vào SQL Server
  trong phase này. Khi chấp nhận thành node, quản trị viên chọn loại được hỗ trợ.

## Validator và review cần triển khai ở phase AI

Schema chỉ kiểm tra hình dạng. Validator tương lai còn phải kiểm tra ID duy nhất,
FK proposal tồn tại, self-loop, cạnh trùng, polygon hữu hạn/không tự cắt, giới hạn
tổng pixel/số phần tử, kích thước/hash ảnh và request/revision còn hiện hành.
Kết quả đến muộn sau khi đổi ảnh/tầng phải bị loại bỏ. Không tin context/floor ID
do AI trả về. Không thực thi chuỗi evidence/label và không hiển thị như HTML.

Giao diện tương lai phải hiển thị layer đề xuất riêng; mỗi đối tượng có Accept,
Edit, Reject và chứng cứ kiểm tra do con người ghi lại. Chấp nhận chỉ sao chép vào
bản nháp cục bộ, làm mất xác nhận alignment cũ và vẫn `verifiedForPatientUse=false`.
Không publish, ghi API hoặc SQL. Server validation, lưu bền, role reviewer/admin,
audit log và quy trình phê duyệt đều **chờ Phase 7A Authorization**.

## Mức sẵn sàng

7B-1 cung cấp ảnh bytes/metadata, tọa độ cùng canvas và draft JSON độc lập. Có thể
dùng làm đầu vào triển khai vision sau khi chốt schema. Chưa có model capability
probe, inference, JSON repair, runtime schema validator, quản lý proposal/revision
hoặc đo độ chính xác thực địa; chưa sẵn sàng tự động sinh bản đồ cho người sử dụng.
