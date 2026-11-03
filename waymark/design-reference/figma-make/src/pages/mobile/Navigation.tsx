import { useState } from "react"
import { useNavigate, useSearchParams } from "react-router"
import {
  ArrowUp,
  ArrowUpRight,
  Check,
  ChevronDown,
  ChevronUp,
  Layers,
  QrCode,
  X,
} from "lucide-react"
import HospitalMap from "../../components/HospitalMap"
import { Button, Title } from "../../components/WaymarkUI"

const steps = [
  {
    title: "Đi thẳng theo hành lang B",
    detail: "45 m đến ngã rẽ bên phải",
    floor: 0,
    remain: 120,
  },
  {
    title: "Rẽ phải tới thang máy E1",
    detail: "20 m · Tiếp theo: lên lầu 1",
    floor: 0,
    remain: 75,
  },
  {
    title: "Đi thang máy lên lầu 1",
    detail: "Từ tầng G → L1 · Thang máy E1",
    floor: 1,
    remain: 55,
  },
  {
    title: "Đến phòng 204 bên phải",
    detail: "55 m theo hành lang A",
    floor: 1,
    remain: 55,
  },
]
export function Navigation() {
  const navigate = useNavigate()
  const [params] = useSearchParams()
  const initial = Math.min(4, Math.max(0, Number(params.get("step")) || 0))
  const verified = Math.min(4, Math.max(0, Number(params.get("verified")) || 0))
  const [step, setStep] = useState(initial)
  const [floor, setFloor] = useState(initial >= 2 ? 1 : 0)
  const [expanded, setExpanded] = useState(false)
  const [ending, setEnding] = useState(false)
  const current = steps[Math.min(step, 3)]
  const preference =
    params.get("preference") ||
    sessionStorage.getItem("waymark-route-preference") ||
    "Tuyến thông thường"
  return (
    <div className="indoor-screen navigation-screen">
      <header className="indoor-header">
        <div className="navigation-live">
          <span className="status-dot" />
          ĐANG DẪN ĐƯỜNG
        </div>
        <Button className="end-button" onClick={() => setEnding(true)}>
          <X size={16} />
          Kết thúc
        </Button>
      </header>
      <div className="instruction-banner">
        <div className="instruction-icon">
          {step === 1 ? <ArrowUpRight size={30} /> : <ArrowUp size={30} />}
        </div>
        <div>
          <Title>
            {step === 4 ? "Bạn đã xác nhận chặng cuối" : current.title}
          </Title>
          <p>
            {step === 4
              ? "Quét QR đích để xác nhận đã đến nơi"
              : current.detail}
          </p>
        </div>
      </div>
      <div className="map-stage">
        <HospitalMap floor={floor} active progress={step} verified={verified} />
        <div className="floor-control">
          <Layers size={16} />
          {[1, 0].map((f) => (
            <Button
              key={f}
              onClick={() => setFloor(f)}
              className={floor === f ? "floor-selected" : ""}
            >
              {f ? "L1" : "G"}
            </Button>
          ))}
        </div>
        <div className="map-floor-label">
          Tòa A · {floor ? "Lầu 1" : "Tầng trệt"}
          <span> · {step < 2 ? "Tiếp theo: G → L1" : "Điểm đến ở L1"}</span>
        </div>
      </div>
      <section className="route-sheet">
        <div className="navigation-preference">
          <Layers size={13} />
          {preference} · Qua thang máy E1
          {preference !== "Tuyến thông thường" && (
            <span>Tiếp cận chưa xác minh</span>
          )}
        </div>
        <div className="location-proof">
          <QrCode size={19} />
          <div>
            <strong>
              QR gần nhất:{" "}
              {verified === 0
                ? "Cổng chính A"
                : verified === 4
                  ? "Phòng 204"
                  : `Điểm WayMark ${verified + 1}`}
            </strong>
            <p>
              {verified === 0
                ? "WM-G01 · Tầng G"
                : `Chặng ${verified}/4 · Xác nhận trong bản mẫu`}
            </p>
          </div>
          <span className="proof-badge">QR</span>
        </div>
        {step > verified && (
          <p className="manual-note">
            <span className="manual-square" />
            Chặng {step}/4 do bạn xác nhận · Chưa xác minh vị trí
          </p>
        )}
        <div className="remaining-row">
          <strong>
            {step === 4 ? "0" : current.remain} m <span>còn lại</span>
          </strong>
          <span>Đích: Phòng 204 · L1</span>
        </div>
        <Button
          className="steps-toggle"
          onClick={() => setExpanded(!expanded)}
          aria-expanded={expanded}
        >
          <span>Hướng dẫn từng chặng · {Math.min(step + 1, 4)}/4</span>
          {expanded ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
        </Button>
        {expanded && (
          <ol className="route-steps">
            {steps.map((s, i) => (
              <li key={s.title} className={i === step ? "current-step" : ""}>
                {i < step && <Check size={13} />}
                {s.title}
              </li>
            ))}
          </ol>
        )}
        <Button
          className="primary-action"
          onClick={() =>
            navigate(
              `/scanner?mode=relocalize&step=${step}&verified=${verified}`,
            )
          }
        >
          <QrCode size={20} />
          Quét QR xác nhận vị trí
        </Button>
        <div className="progress-actions">
          <Button
            disabled={step === 0}
            onClick={() => {
              setStep(step - 1)
              setFloor(step - 1 >= 2 ? 1 : 0)
            }}
          >
            Bước trước
          </Button>
          <Button
            disabled={step === 4}
            onClick={() => {
              setStep(step + 1)
              setFloor(step + 1 >= 2 ? 1 : 0)
            }}
          >
            <Check size={16} />
            Đã đến điểm tiếp theo
          </Button>
        </div>
        <p className="prototype-note">
          Sơ đồ minh họa · Không theo dõi vị trí trực tiếp
        </p>
      </section>
      {ending && (
        <div className="modal-backdrop">
          <div
            className="confirm-card"
            role="dialog"
            aria-modal="true"
            aria-label="Kết thúc dẫn đường"
          >
            <Title>Kết thúc dẫn đường?</Title>
            <p>Bạn có thể chọn lại tuyến đường từ trang chủ.</p>
            <Button className="primary-action" onClick={() => navigate("/")}>
              Kết thúc
            </Button>
            <Button onClick={() => setEnding(false)}>Tiếp tục dẫn đường</Button>
          </div>
        </div>
      )}
    </div>
  )
}
export default Navigation
