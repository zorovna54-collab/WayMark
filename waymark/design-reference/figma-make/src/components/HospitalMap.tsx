import { useId, useRef, useState } from "react"
import { Maximize, Minus, Plus } from "lucide-react"
import { Button } from "./WaymarkUI"

type Props = {
  floor: number
  active?: boolean
  progress?: number
  verified?: number
  editor?: boolean
  onNode?: (id: string) => void
  zoom?: number
}
export default function HospitalMap({
  floor,
  active = false,
  progress = 0,
  verified = 0,
  editor = false,
  onNode,
  zoom: initialZoom = 1,
}: Props) {
  const id = useId()
  const [zoom, setZoom] = useState(initialZoom)
  const [pan, setPan] = useState({ x: 0, y: 0 })
  const gesture = useRef<{
    x: number
    y: number
    panX: number
    panY: number
  } | null>(null)
  const upper = floor === 1
  const rooms = upper
    ? [
        {
          x: 28,
          y: 44,
          w: 135,
          h: 92,
          name: "KHOA NỘI",
          sub: "Phòng khám 201",
        },
        {
          x: 177,
          y: 44,
          w: 135,
          h: 92,
          name: "KHOA NHI",
          sub: "Phòng khám 202",
        },
        {
          x: 28,
          y: 185,
          w: 114,
          h: 100,
          name: "PHÒNG KHÁM",
          sub: "203 · Nội tổng quát",
        },
        {
          x: 196,
          y: 185,
          w: 116,
          h: 100,
          name: "THẦN KINH",
          sub: "204 · Điểm đến",
        },
        { x: 28, y: 336, w: 114, h: 89, name: "KHU CHỜ", sub: "Ghế nghỉ" },
      ]
    : [
        {
          x: 28,
          y: 44,
          w: 135,
          h: 92,
          name: "NHÀ THUỐC",
          sub: "G.01 · Nhận thuốc",
        },
        {
          x: 177,
          y: 44,
          w: 135,
          h: 92,
          name: "CHẨN ĐOÁN",
          sub: "G.02 · Hình ảnh",
        },
        {
          x: 28,
          y: 185,
          w: 114,
          h: 100,
          name: "KHÁM BỆNH",
          sub: "G.03 · Đa khoa",
        },
        {
          x: 196,
          y: 185,
          w: 116,
          h: 100,
          name: "TIẾP ĐÓN",
          sub: "G.04 · Đăng ký",
        },
        { x: 28, y: 336, w: 114, h: 89, name: "SẢNH CHÍNH", sub: "Lối vào A" },
      ]
  const route = upper
    ? "M 254 310 L 169 310 L 169 162 L 253 162 L 253 185"
    : "M 169 425 L 169 310 L 254 310"
  const nodes = upper
    ? [
        { x: 254, y: 310, id: "WM-L101" },
        { x: 169, y: 162, id: "WM-L102" },
        { x: 253, y: 185, id: "WM-L103" },
      ]
    : [
        { x: 169, y: 425, id: "WM-G01" },
        { x: 169, y: 310, id: "WM-G02" },
        { x: 254, y: 310, id: "WM-G03" },
      ]
  return (
    <div className={`hospital-map ${editor ? "editor-map" : ""}`}>
      <svg
        viewBox="0 0 340 475"
        role="img"
        aria-label={`Sơ đồ minh họa tầng ${
          upper ? "L1" : "G"
        }, tuyến đường dọc hành lang tới thang máy và phòng 204`}
        onPointerDown={(e) => {
          if (editor) return
          gesture.current = {
            x: e.clientX,
            y: e.clientY,
            panX: pan.x,
            panY: pan.y,
          }
          e.currentTarget.setPointerCapture(e.pointerId)
        }}
        onPointerMove={(e) => {
          const g = gesture.current
          const matrix = e.currentTarget.getScreenCTM()
          if (!g || !matrix) return
          setPan({
            x: Math.max(
              -340,
              Math.min(340, g.panX + (e.clientX - g.x) / matrix.a),
            ),
            y: Math.max(
              -475,
              Math.min(475, g.panY + (e.clientY - g.y) / matrix.d),
            ),
          })
        }}
        onPointerUp={() => {
          gesture.current = null
        }}
        onPointerCancel={() => {
          gesture.current = null
        }}
      >
        <defs>
          <pattern
            id={`${id}-grid`}
            width="16"
            height="16"
            patternUnits="userSpaceOnUse"
          >
            <circle cx="1" cy="1" r=".6" className="map-grid" />
          </pattern>
          <marker
            id={`${id}-arrow`}
            viewBox="0 0 10 10"
            refX="5"
            refY="5"
            markerWidth="4"
            markerHeight="4"
            orient="auto"
          >
            <path d="M2 2 L7 5 L2 8" className="map-arrow" />
          </marker>
        </defs>
        <rect width="340" height="475" fill={`url(#${id}-grid)`} />
        <g
          transform={`translate(${pan.x + 170 - 170 * zoom} ${pan.y + 237 - 237 * zoom}) scale(${zoom})`}
        >
          <path d="M20 36 H320 V433 H20 Z" className="map-building" />
          <path
            d="M169 136 V433 M20 162 H320 M142 310 H320"
            className="map-accessible"
          />
          {rooms.map((r, i) => (
            <g key={r.name}>
              <rect
                x={r.x}
                y={r.y}
                width={r.w}
                height={r.h}
                rx="3"
                className={`map-room room-${i}`}
              />
              <text
                x={r.x + r.w / 2}
                y={r.y + r.h / 2 - 4}
                className="room-name"
              >
                {r.name}
              </text>
              <text
                x={r.x + r.w / 2}
                y={r.y + r.h / 2 + 12}
                className="room-sub"
              >
                {r.sub}
              </text>
              <path
                d={`M ${r.x + r.w / 2 - 9} ${r.y < 180 ? r.y + r.h : r.y} h18`}
                className="map-door"
              />
            </g>
          ))}
          <rect
            x="196"
            y="336"
            width="54"
            height="89"
            rx="3"
            className="map-service"
          />
          <rect
            x="258"
            y="336"
            width="54"
            height="89"
            rx="3"
            className="map-service"
          />
          <path d="M214 336 h18 M276 336 h18" className="map-door" />
          <text x="223" y="371" className="service-icon">
            ↕
          </text>
          <text x="223" y="391" className="room-sub">
            Thang máy
          </text>
          <text x="223" y="406" className="room-sub">
            E1
          </text>
          <path d="M271 377 h6 v-7 h6 v-7 h6 v-7 h8" className="map-stairs" />
          <text x="285" y="398" className="room-sub">
            Cầu thang
          </text>
          <text x="82" y="157" className="corridor-label">
            HÀNH LANG A
          </text>
          <text x="85" y="314" className="corridor-label">
            HÀNH LANG B
          </text>
          <path d={route} className="route-halo" />
          <path
            d={route}
            className={`map-route ${active ? "route-upcoming" : ""}`}
          />
          {active &&
            progress < 4 &&
            ((!upper && progress < 2) || (upper && progress >= 2)) && (
              <path
                d={
                  !upper
                    ? progress === 0
                      ? "M169 425 L169 310"
                      : "M169 310 L254 310"
                    : progress === 2
                      ? "M254 310 L169 310"
                      : "M169 310 L169 162 L253 162 L253 185"
                }
                className="map-route route-active"
              />
            )}
          {!upper && (
            <>
              <path
                d="M169 392 V370 M190 310 H212"
                className="route-directions"
                markerEnd={`url(#${id}-arrow)`}
              />
              <text x="169" y="452" className="room-sub">
                LỐI VÀO CHÍNH
              </text>
            </>
          )}
          {upper && (
            <path
              d="M222 310 H200 M169 245 V225 M205 162 H224"
              className="route-directions"
              markerEnd={`url(#${id}-arrow)`}
            />
          )}
          {nodes.map((n, i) => (
            <g
              key={n.id}
              role={editor ? "button" : undefined}
              tabIndex={editor ? 0 : undefined}
              onClick={() => onNode?.(n.id)}
              onKeyDown={(e) => e.key === "Enter" && onNode?.(n.id)}
              className={editor ? "map-edit-node" : ""}
            >
              <circle
                cx={n.x}
                cy={n.y}
                r={i === 0 || (upper && i === 2) ? 10 : 5}
                className={upper && i === 2 ? "map-destination" : "map-node"}
              />
              {(i === 0 || (upper && i === 2)) && (
                <text x={n.x} y={n.y + 3.5} className="marker-letter">
                  {upper && i === 2 ? "B" : "A"}
                </text>
              )}
              {editor && (
                <text x={n.x} y={n.y - 17} className="node-id">
                  {n.id}
                </text>
              )}
            </g>
          ))}
          {active && !upper && verified === 0 && (
            <>
              <circle cx="169" cy="425" r="16" className="verified-ring" />
              <text x="115" y="418" className="map-status-label">
                QR gần nhất
              </text>
            </>
          )}
          {active &&
            verified > 0 &&
            ((verified < 2 && !upper) || (verified >= 2 && upper)) && (
              <g>
                <circle
                  cx={
                    verified === 1
                      ? 169
                      : verified === 2
                        ? 254
                        : verified === 3
                          ? 169
                          : 253
                  }
                  cy={
                    verified === 1 || verified === 2
                      ? 310
                      : verified === 3
                        ? 162
                        : 185
                  }
                  r="15"
                  className="verified-ring"
                />
                <text
                  x={verified === 1 || verified === 3 ? 122 : 275}
                  y={verified <= 2 ? 300 : 150}
                  className="map-status-label"
                >
                  QR gần nhất
                </text>
              </g>
            )}
          {active &&
            progress > verified &&
            ((progress === 1 && !upper) || (progress >= 2 && upper)) && (
              <rect
                x={
                  (progress === 1 || progress === 3
                    ? 169
                    : progress === 2
                      ? 254
                      : 253) - 6
                }
                y={(progress <= 2 ? 310 : progress === 3 ? 162 : 185) - 6}
                width="12"
                height="12"
                rx="2"
                className="manual-marker"
              />
            )}
        </g>
      </svg>
      {!editor && (
        <div className="mobile-map-tools">
          <Button
            aria-label="Phóng to bản đồ"
            onClick={() => setZoom((z) => Math.min(2.5, z + 0.25))}
          >
            <Plus size={16} />
          </Button>
          <Button
            aria-label="Thu nhỏ bản đồ"
            onClick={() => setZoom((z) => Math.max(1, z - 0.25))}
          >
            <Minus size={16} />
          </Button>
          <Button
            aria-label="Đặt lại bản đồ"
            onClick={() => {
              setZoom(1)
              setPan({ x: 0, y: 0 })
            }}
          >
            <Maximize size={15} />
          </Button>
        </div>
      )}
    </div>
  )
}
