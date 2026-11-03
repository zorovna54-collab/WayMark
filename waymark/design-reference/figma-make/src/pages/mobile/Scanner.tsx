import { useState } from "react"
import { useNavigate, useSearchParams } from "react-router"
import {
  ArrowLeft,
  CheckCircle2,
  CameraOff,
  QrCode,
  TriangleAlert,
} from "lucide-react"
import { Button, SelectField, Title } from "../../components/WaymarkUI"

const cases = [
  {
    label: "QR tại điểm tiếp theo",
    title: "Đúng điểm tiếp theo",
    text: "Mã QR khớp với điểm WayMark kế tiếp. Xác nhận để cập nhật tiến trình.",
    action: "Xác nhận điểm tiếp theo",
  },
  {
    label: "QR tại điểm hiện tại",
    title: "Bạn đang ở điểm đã xác nhận",
    text: "Mã QR trùng với điểm hiện tại. Tiến trình tuyến đường được giữ nguyên.",
    action: "Xác nhận lại vị trí",
  },
  {
    label: "QR tại điểm xa hơn",
    title: "Bạn đã đến một điểm xa hơn",
    text: "Điểm này nằm sau hai chặng trên tuyến. Chỉ bỏ qua các chặng trước khi bạn xác nhận.",
    action: "Xác nhận chuyển đến điểm này",
  },
  {
    label: "QR ngoài tuyến",
    title: "Vị trí nằm ngoài tuyến đường",
    text: "WM-G08 · Sảnh phụ, tầng G. Tuyến cũ sẽ được thay thế chỉ khi bạn đồng ý tính lại.",
    action: "Tính lại đường từ vị trí này",
  },
  {
    label: "QR không hợp lệ / không khả dụng",
    title: "Không thể sử dụng mã QR",
    text: "Mã không thuộc WayMark hoặc điểm đã ngừng hoạt động. Vị trí và tuyến đường chưa thay đổi.",
    action: "Thử quét lại",
  },
  {
    label: "Từ chối quyền camera",
    title: "Chưa có quyền truy cập camera",
    text: "Cho phép camera trong cài đặt trình duyệt để quét mã. Bản mẫu không truy cập camera thật.",
    action: "Tôi đã kiểm tra quyền · Thử lại",
  },
]
export function Scanner() {
  const navigate = useNavigate()
  const [params] = useSearchParams()
  const relocalize = params.get("mode") === "relocalize"
  const step = Number(params.get("step")) || 0
  const verified = Number(params.get("verified")) || 0
  const [scenario, setScenario] = useState(0)
  const [result, setResult] = useState(false)
  const item = cases[scenario]
  function confirm() {
    if (scenario >= 4) {
      setResult(false)
      return
    }
    if (!relocalize) {
      navigate("/search")
      return
    }
    if (scenario === 3) {
      navigate("/preview?from=WM-G08")
      return
    }
    const next =
      scenario === 0
        ? Math.min(4, step + 1)
        : scenario === 1
          ? verified
          : Math.min(4, step + 2)
    navigate(`/navigation?step=${next}&verified=${next}`)
  }
  return (
    <div className="qr-screen">
      <header className="indoor-header">
        <Button
          className="icon-button"
          aria-label="Quay lại"
          onClick={() => navigate(-1)}
        >
          <ArrowLeft size={21} />
        </Button>
        <Title>
          {relocalize ? "Xác nhận vị trí bằng QR" : "Quét mã WayMark"}
        </Title>
      </header>
      {!result ? (
        <>
          <div className="scanner-viewport">
            <div className="scanner-target">
              <QrCode size={90} strokeWidth={1} />
            </div>
            <p>Đưa mã WayMark vào trong khung</p>
            <span>Giao diện mô phỏng · Không dùng camera thật</span>
          </div>
          <div className="scanner-panel">
            <div className="eyebrow">QR RELOCALIZATION · BẢN MẪU</div>
            <p>Chọn tình huống để xem phản hồi</p>
            <SelectField
              aria-label="Tình huống QR"
              value={scenario}
              onChange={(e) => setScenario(Number(e.target.value))}
            >
              {cases.map((c, i) => (
                <option key={c.label} value={i}>
                  {c.label}
                </option>
              ))}
            </SelectField>
            <Button className="primary-action" onClick={() => setResult(true)}>
              <QrCode size={19} />
              Mô phỏng quét QR
            </Button>
            <p className="prototype-note">Không có cập nhật vị trí tự động.</p>
          </div>
        </>
      ) : (
        <div className="qr-result">
          <div className={`result-symbol ${scenario >= 3 ? "warning" : ""}`}>
            {scenario === 5 ? (
              <CameraOff size={38} />
            ) : scenario >= 3 ? (
              <TriangleAlert size={38} />
            ) : (
              <CheckCircle2 size={38} />
            )}
          </div>
          <Title>{item.title}</Title>
          <p>{item.text}</p>
          <div className="qr-result-location">
            <QrCode size={24} />
            <div>
              <strong>
                {scenario === 3
                  ? "WM-G08 · Sảnh phụ"
                  : scenario >= 4
                    ? "Chưa xác nhận vị trí mới"
                    : scenario === 2
                      ? "Điểm WayMark sau hai chặng"
                      : scenario === 1
                        ? "Điểm đã xác nhận gần nhất"
                        : "Điểm WayMark kế tiếp"}
              </strong>
              <span>Dữ liệu mô phỏng, chưa kiểm chứng thực địa</span>
            </div>
          </div>
          <Button className="primary-action" onClick={confirm}>
            {item.action}
          </Button>
          <Button onClick={() => setResult(false)}>Quét mã khác</Button>
          <Button
            onClick={() =>
              navigate(
                relocalize
                  ? `/navigation?step=${step}&verified=${verified}`
                  : "/",
              )
            }
          >
            Hủy · Giữ nguyên tuyến đường
          </Button>
        </div>
      )}
    </div>
  )
}
export default Scanner
