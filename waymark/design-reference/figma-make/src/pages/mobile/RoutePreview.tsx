import { useState } from "react"
import { useNavigate, useSearchParams } from "react-router"
import {
  ArrowLeft,
  ArrowUpRight,
  Building2,
  ChevronDown,
  ChevronUp,
  Clock3,
  Layers,
  MapPin,
  Navigation2,
  ShieldCheck,
} from "lucide-react"
import HospitalMap from "../../components/HospitalMap"
import { Button, Title } from "../../components/WaymarkUI"
import RoutePreferences, {
  preferences,
} from "../../components/RoutePreferences"

export function RoutePreview() {
  const navigate = useNavigate()
  const [params] = useSearchParams()
  const destination = params.get("to") || "Khoa Ngoại Thần Kinh"
  const [floor, setFloor] = useState(0)
  const [expanded, setExpanded] = useState(false)
  const [preference, setPreference] = useState(preferences[0])
  return (
    <div className="indoor-screen">
      <header className="indoor-header">
        <Button
          className="icon-button"
          aria-label="Quay lại"
          onClick={() => navigate(-1)}
        >
          <ArrowLeft size={20} />
        </Button>
        <div>
          <Title>Xem trước tuyến đường</Title>
          <p>Bệnh viện WayMark · Tòa A</p>
        </div>
        <div className="header-symbol">
          <Building2 size={21} />
        </div>
      </header>
      <div className="map-stage">
        <div className="map-caption">
          <span className="status-dot" />
          Sơ đồ trong nhà <span className="demo-badge">MINH HỌA</span>
        </div>
        <HospitalMap floor={floor} />
        <div className="floor-control">
          <Layers size={16} />
          {["L1", "G"].map((f, i) => (
            <Button
              key={f}
              className={floor === 1 - i ? "floor-selected" : ""}
              onClick={() => setFloor(1 - i)}
            >
              {f}
            </Button>
          ))}
        </div>
        <div className="map-floor-label">
          Tòa A <span> / </span>
          {floor ? "Lầu 1 · Khám chuyên khoa" : "Tầng trệt · Tiếp đón"}
        </div>
        <div className="map-legend">
          <span>
            <i className="legend-line" />
            Tuyến đi
          </span>
          <span>
            <i className="legend-dot" />
            Điểm WayMark
          </span>
          <span>Không định vị GPS</span>
        </div>
      </div>
      <section className="route-sheet">
        {params.get("from") && (
          <div className="access-note">
            Đã yêu cầu tính lại từ WM-G08. Bản mẫu chưa có bộ định tuyến; tuyến
            hiển thị bên dưới vẫn là tuyến minh họa từ Cổng A.
          </div>
        )}
        <Button
          className="sheet-handle"
          aria-label={expanded ? "Thu gọn hướng dẫn" : "Mở hướng dẫn"}
          onClick={() => setExpanded(!expanded)}
        >
          <span />
        </Button>
        <div className="route-summary">
          <div>
            <div className="eyebrow">ĐIỂM ĐẾN CỦA BẠN</div>
            <Title>{destination}</Title>
            <p>Phòng 204 · Lầu 1 · Tòa A</p>
          </div>
          <div className="route-distance">
            120 <small>m</small>
            <span>
              <Clock3 size={12} /> ~ 3 phút
            </span>
          </div>
        </div>
        <div className="journey-line">
          <span className="start-dot" />
          <span>Cổng chính A</span>
          <span className="journey-dash" />
          <Layers size={14} />
          <span>G → L1</span>
          <MapPin size={15} className="text-accent" />
        </div>
        <RoutePreferences
          value={preference}
          onChange={(value) => {
            setPreference(value)
            sessionStorage.setItem("waymark-route-preference", value)
          }}
        />
        <Button
          className="steps-toggle"
          onClick={() => setExpanded(!expanded)}
          aria-expanded={expanded}
        >
          <span>
            <ArrowUpRight size={17} /> 4 chặng · Qua thang máy E1
          </span>
          {expanded ? <ChevronDown size={17} /> : <ChevronUp size={17} />}
        </Button>
        {expanded && (
          <ol className="route-steps">
            <li>Đi thẳng 45 m theo hành lang B.</li>
            <li>Rẽ phải, đi 20 m đến thang máy E1.</li>
            <li>Đi thang máy từ tầng G lên L1.</li>
            <li>Theo hành lang A đến phòng 204, bên phải.</li>
          </ol>
        )}
        <Button
          className="primary-action"
          onClick={() => {
            sessionStorage.setItem("waymark-route-preference", preference)
            navigate(
              `/navigation?to=${encodeURIComponent(destination)}&preference=${encodeURIComponent(preference)}`,
            )
          }}
        >
          <Navigation2 size={19} />
          Bắt đầu dẫn đường
        </Button>
        <p className="prototype-note">
          <ShieldCheck size={12} /> Bản đồ minh họa, chưa được kiểm chứng thực
          địa
        </p>
      </section>
    </div>
  )
}
export default RoutePreview
