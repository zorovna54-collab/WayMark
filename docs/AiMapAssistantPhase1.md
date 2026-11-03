# AI Map Assistant Phase 1

## Phạm vi và kiến trúc

- `AiMapProvider`: contract lấy model và phân tích ảnh; `OpenAiMapProvider` dùng API tương thích OpenAI của LM Studio. Có thể thay provider sau này.
- Không dùng `AuthSession`, JWT ứng dụng hoặc token compile-time của màn hình text AI cũ. Token LM Studio nhập riêng, che nội dung và chỉ giữ trong bộ nhớ màn hình; không lưu file/log.
- Nhập Base URL kết thúc `/v1`, bấm kiểm tra kết nối và chọn **ID thật** trả từ `/models`. GET thành công chưa chứng minh model đang load hoặc hỗ trợ Vision.
- POST `/chat/completions`: multipart message text + `image_url` dạng data URI đúng MIME, không stream. Không dùng endpoint/API key production mặc định, không theo redirect mang token sang host khác.
- Contract tương thích theo [LM Studio Chat Completions](https://lmstudio.ai/docs/developer/openai-compat/chat-completions); payload HTTP là JSON chứa các content parts, không phải multipart/form-data.
- Ảnh lấy từ tầng đang chọn, đã qua signature/codec validation hiện có. Đầu vào tối đa 4 MB / 8 MP. Bản sao gửi AI thu nhỏ cạnh dài tối đa 768 px, giữ tỷ lệ và toàn khung; không sửa ảnh gốc, lịch sử chỉnh ảnh hay tọa độ draft.
- Giới hạn response 512 KB, JSON content 128 KB, tối đa 40 mục parse; prompt yêu cầu tối đa 8. Timeout Vision có thể chọn 60/120/300 giây; GET models 10 giây. Không tự retry.
- Kiểm tra kiểu dữ liệu, tên/loại, confidence và tọa độ hữu hạn [0,1], ID trùng. Bỏ từng mục lỗi; không có mục hợp lệ thì báo lỗi. Không lấy một đoạn JSON tùy ý trong văn bản; chỉ nhận object JSON hoặc một fenced `json` block.
- Review là màn hình tách biệt, **không có tham chiếu mutable đến DraftMap**. Overlay dùng `FloorPlanCanvas` hiện có nên ảnh và số đề xuất cùng transform/contain/zoom/pan.
- Accept chỉ chọn vào hàng đợi; Edit cần duyệt lại; Reject gỡ khỏi hàng đợi. Nút thêm và hộp thoại xác nhận cuối mới trả kết quả về Builder.
- Trước khi thêm, kiểm tra đúng draft/tầng/ảnh nguồn, validate cả batch và giới hạn 2000 node. Append bằng GUID cục bộ mới, không dùng ID AI để ghi đè node. Không tạo Edge/QR hoặc thay đổi mét, Room, Entrance, liên kết tầng.
- Node thêm có Landmark Note cảnh báo `AI chưa xác minh vị trí/lối đi`, được lưu bằng JSON v2/v3 hiện có. `layoutReviewed` bị hủy để yêu cầu đối chiếu lại. Không có chứng nhận cửa/lối đi/khả năng tiếp cận từ AI.
- Lỗi/offline/timeout hoặc rời màn hình không thay đổi bản nháp thủ công. Production graph, backend và SQL không tham gia tính năng này.

## Cấu hình và chạy

1. Trong LM Studio, chạy server port 1234, chọn/load model Vision cùng projector phù hợp.
2. Android Emulator: nhập `http://10.0.2.2:1234/v1`; Windows: `http://127.0.0.1:1234/v1`.
3. Android thật: nhập IP LAN hiện tại của Windows, ví dụ địa chỉ người dùng cung cấp `http://192.168.1.15:1234/v1`. Kiểm tra server lắng nghe LAN và Windows Firewall cho đúng mạng riêng; không tắt firewall toàn cục.
4. Nếu bật Require Authentication, nhập token vào trường riêng. Không dùng JWT WayMark. Không truyền token bằng dart-define hoặc URL.
5. Mở Builder, chọn tầng/ảnh, bấm **AI đề xuất node** → kiểm tra kết nối → chọn model → phân tích. Kiểm tra số trên ảnh và tên/tọa độ, sửa hoặc từ chối, rồi xác nhận thêm.
6. Lưu JSON như trước để giữ node đã duyệt. Bộ đề xuất chưa thêm không được lưu và sẽ mất khi đóng màn hình.

URL có thể nhập ở UI hoặc cung cấp mặc định phát triển:

```powershell
cd D:\project\WayMark\waymark
flutter run -d emulator-5554 --dart-define=WAYMARK_AI_BASE_URL=http://10.0.2.2:1234/v1
```

Android đã có INTERNET permission. Cleartext được chuyển từ main sang **debug manifest**: HTTP chỉ dành development. Main/release HTTPS-only; cấu hình backend HTTP cũ cũng cần HTTPS khi phát hành release. Provider từ chối HTTP ngoài debug. Web cần chính sách CORS phù hợp trên server AI nếu bị trình duyệt chặn.

## Bằng chứng kiểm thử thực tế

- Windows GET `/v1/models` thành công, có `qwen/qwen3-vl-8b` và model embedding. Không suy diễn capability từ tên model.
- POST ảnh gốc 1380 × 1380 đầu tiên timeout sau 150 giây; không xem là thành công.
- POST bản thu nhỏ 512 × 512 của ảnh sơ đồ thật qua loopback thành công: model đọc `KHO DƯỢC`, `KHOA TAI - MŨI - HỌNG`, `WC`, đối chiếu được với ảnh gốc.
- Android `emulator-5554`, entrypoint rehearsal hiện có `tool/android_map_builder.dart`, **provider thật**, endpoint `10.0.2.2:1234/v1`, ảnh chọn bằng Android file picker: POST có ảnh trả JSON hợp lệ. Đề xuất `KHOA NGOẠI`, Destination, X=0.770, Y=0.670, confidence=0.8; uncertainty yêu cầu kiểm tra vị trí/lối đi.
- Review overlay hiển thị trên ảnh thật. Đã bấm Reject (0 node), Edit X thành 0.780, Accept, xác nhận cuối; trở về Builder có 1 node / 0 edge. Đây là draft thử cục bộ mới, không sửa graph sản xuất.
- Ảnh và screenshot chỉ ở thư mục test máy người dùng / `waymark/build/ai-map-evidence/` bị Git ignore. Không thêm ảnh bệnh viện vào assets hoặc gửi tới dịch vụ ngoài. Screenshot: `android-review.png`, `android-accepted.png`.
- Chưa kiểm thử máy Android vật lý/LAN, server bắt buộc token thật, release HTTPS hoặc nhiều model/provider khác. Không đánh giá chính xác y khoa, cửa hoặc lối đi ngoài thực địa.

## Verification

`flutter analyze --no-pub`, `flutter test --reporter expanded`, `flutter build apk --debug`, `git diff --check`.

Kết quả cuối: `flutter analyze` và `--no-pub` sạch; toàn bộ **246 tests pass / 1 Web-only skip** (24 test mới); Android debug build đạt; `git diff --check` exit 0. Gradle còn cảnh báo Java native-access hiện có, không chặn build. Không sửa Gradle để che cảnh báo.

Các test mới dùng MockClient/FakeAi (không gọi server) kiểm tra schema, HTTP/auth/timeout, ảnh truyền thật trong request, giới hạn ảnh, resize đúng tỷ lệ, review Accept/Edit/Reject, commit rõ ràng, ảnh nguồn stale, không ghi batch lỗi, JSON roundtrip và offline không thay đổi draft. Bằng chứng Vision thật nằm riêng ở phần trên.

Không sửa SQL/JWT, migrations, backend, Gradle, Windows generated; không commit/push.
