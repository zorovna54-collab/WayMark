import { useEffect, useState } from "react"
import {
  Check,
  CheckCircle2,
  Circle,
  Cpu,
  LoaderCircle,
  Pencil,
  Play,
  ShieldAlert,
  Sparkles,
  X,
} from "lucide-react"
import { Button, TextField, Title } from "../WaymarkUI"
import MapCanvas from "./MapCanvas"
import type { Graph, MapNode, PlanImage } from "./model"
import { kindLabels } from "./model"

type Suggestion = {
  id: string
  name: string
  kind: MapNode["kind"] | "edge"
  confidence: number
  x: number
  y: number
  status: "pending" | "accepted" | "rejected"
}
const suggestions: Suggestion[] = [
  {
    id: "ai-room",
    name: "Phòng khám · cần đối chiếu",
    kind: "room",
    confidence: 94,
    x: 160,
    y: 250,
    status: "pending",
  },
  {
    id: "ai-corridor",
    name: "Nút giao hành lang",
    kind: "corridor",
    confidence: 91,
    x: 500,
    y: 320,
    status: "pending",
  },
  {
    id: "ai-door",
    name: "Cửa phòng · kiểm tra độ rộng",
    kind: "door",
    confidence: 63,
    x: 840,
    y: 250,
    status: "pending",
  },
  {
    id: "ai-elevator",
    name: "Thang máy E1",
    kind: "elevator",
    confidence: 78,
    x: 610,
    y: 320,
    status: "pending",
  },
  {
    id: "ai-stairs",
    name: "Cầu thang S1",
    kind: "stairs",
    confidence: 86,
    x: 770,
    y: 320,
    status: "pending",
  },
  {
    id: "ai-qr",
    name: "Đề xuất mốc QR · chưa có mã",
    kind: "qr",
    confidence: 59,
    x: 500,
    y: 580,
    status: "pending",
  },
  {
    id: "ai-edge",
    name: "Hành lang → Thang máy",
    kind: "edge",
    confidence: 67,
    x: 0,
    y: 0,
    status: "pending",
  },
]
type Props = {
  image: PlanImage | null
  onAccept: (node: MapNode | null, edge: boolean) => boolean
  onPending: (count: number) => void
}
export default function AIAnalysis({ image, onAccept, onPending }: Props) {
  const [connected, setConnected] = useState(false)
  const [endpoint, setEndpoint] = useState("http://localhost:1234/v1")
  const [progress, setProgress] = useState(0)
  const [running, setRunning] = useState(false)
  const [items, setItems] = useState<Suggestion[]>([])
  const [editing, setEditing] = useState("")
  const [error, setError] = useState("")
  useEffect(() => {
    if (!running) return
    const timer = setInterval(
      () => setProgress((p) => Math.min(100, p + 25)),
      400,
    )
    return () => clearInterval(timer)
  }, [running])
  useEffect(() => {
    if (progress !== 100 || !running) return
    setRunning(false)
    setItems(suggestions.map((s) => ({ ...s })))
    onPending(suggestions.length)
  }, [progress, running, onPending])
  const graph: Graph = {
    nodes: items
      .filter((s) => s.kind !== "edge" && s.status !== "rejected")
      .map((s) => ({
        ...s,
        kind: s.kind as MapNode["kind"],
        qr: "",
        connector: "",
        accessible: "unknown",
      })),
    edges: items.find((i) => i.id === "ai-edge" && i.status !== "rejected")
      ? [
          {
            id: "analysis-link",
            from: "ai-corridor",
            to: "ai-elevator",
            accessible: "unknown",
          },
        ]
      : [],
  }
  function review(id: string, accept: boolean) {
    const item = items.find((s) => s.id === id)!
    if (accept) {
      const ok = onAccept(
        item.kind === "edge"
          ? null
          : {
              id: item.id,
              name: item.name,
              kind: item.kind,
              x: item.x,
              y: item.y,
              qr: "",
              connector:
                item.kind === "elevator"
                  ? "E1"
                  : item.kind === "stairs"
                    ? "S1"
                    : "",
              accessible: "unknown",
            },
        item.kind === "edge",
      )
      if (!ok) {
        setError(
          "Duyệt nút hành lang và thang máy trước khi chấp nhận cạnh nối.",
        )
        return
      }
    }
    const updated = items.map((s) =>
      s.id === id
        ? { ...s, status: accept ? "accepted" as const : "rejected" as const }
        : s,
    )
    setItems(updated)
    onPending(updated.filter((s) => s.status === "pending").length)
    setError("")
    setEditing("")
  }
  return (
    <div className="ai-workspace">
      <div className="ai-intro">
        <div>
          <div className="eyebrow">HỖ TRỢ PHÂN TÍCH MẶT BẰNG</div>
          <Title>AI gợi ý. Bạn quyết định.</Title>
          <p>
            Chuyển sơ đồ thành bản nháp có cấu trúc — luôn có bước kiểm duyệt
            của con người.
          </p>
        </div>
        <span className="simulation-label">
          <Sparkles size={14} />
          MÔ PHỎNG · KHÔNG SUY LUẬN THẬT
        </span>
      </div>
      <div className="ai-connection">
        <div className="ai-model-icon">
          <Cpu size={24} />
        </div>
        <div>
          <strong>LM Studio · Mô hình thị giác cục bộ</strong>
          <p>
            <Circle
              size={8}
              className={connected ? "text-cyan-600" : "text-slate-400"}
            />
            {connected
              ? "Kết nối mô phỏng sẵn sàng · Qwen2.5-VL"
              : "Chưa kết nối · Không gửi dữ liệu ra ngoài"}
          </p>
        </div>
        <TextField
          aria-label="Địa chỉ LM Studio mô phỏng"
          value={endpoint}
          onChange={(e) => {
            setEndpoint(e.target.value)
            setConnected(false)
          }}
        />
        <Button onClick={() => setConnected(!connected)}>
          {connected ? "Ngắt mô phỏng" : "Mô phỏng kết nối"}
        </Button>
      </div>
      <div className="ai-disclaimer">
        <ShieldAlert size={18} />
        <span>
          Gợi ý AI bắt buộc được con người kiểm duyệt. Vị trí, cấu trúc nối,
          kích thước và khả năng tiếp cận chưa được xác minh. Không có kết nối
          LM Studio thực tế.
        </span>
      </div>
      <div className="analysis-command">
        <div>
          <strong>
            {running
              ? "Đang tạo kết quả mẫu…"
              : items.length
                ? "Bản phân tích mẫu đã sẵn sàng"
                : "Sẵn sàng phân tích ảnh mặt bằng"}
          </strong>
          <p>
            {running
              ? `Tiến trình mô phỏng ${progress}% · Không chạy mô hình`
              : "7 gợi ý mẫu: phòng, hành lang, cửa, thang máy, cầu thang, QR và cạnh nối."}
          </p>
        </div>
        <Button
          className="primary-action"
          disabled={!image || !connected || running || items.length > 0}
          onClick={() => {
            setProgress(0)
            setRunning(true)
          }}
        >
          {running ? (
            <LoaderCircle size={16} className="animate-spin" />
          ) : (
            <Play size={16} />
          )}
          Phân tích mặt bằng · Mô phỏng
        </Button>
      </div>
      {running && (
        <progress
          className="analysis-progress"
          value={progress}
          max={100}
          aria-label="Tiến trình phân tích mô phỏng"
        />
      )}
      {!image && (
        <div className="ai-disclaimer">
          Hãy tải ảnh hoặc chọn sơ đồ mẫu trong mục Mặt bằng trước.
        </div>
      )}
      <div className="analysis-comparison">
        <div className="comparison-card">
          <div className="comparison-heading">
            <strong>Ảnh gốc</strong>
            <span>{image?.name || "Chưa tải ảnh"}</span>
          </div>
          <MapCanvas
            image={image}
            graph={{ nodes: [], edges: [] }}
            mode="edit"
            tool="select"
            visible={false}
            selected=""
            onSelect={() => {}}
            onAdd={() => {}}
            onMove={() => {}}
            zoom={1}
            pan={{ x: 0, y: 0 }}
            onPan={() => {}}
          />
        </div>
        <div className="comparison-card">
          <div className="comparison-heading">
            <strong>Chú thích AI · Mô phỏng</strong>
            <span>
              {items.length
                ? `${items.filter((i) => i.status === "pending").length} cần xem xét`
                : "Chưa có kết quả"}
            </span>
          </div>
          <MapCanvas
            image={image}
            graph={graph}
            mode="edit"
            tool="select"
            visible
            selected=""
            onSelect={setEditing}
            onAdd={() => {}}
            onMove={() => {}}
            zoom={1}
            pan={{ x: 0, y: 0 }}
            onPan={() => {}}
            annotation
          />
        </div>
      </div>
      {error && (
        <div className="upload-error" role="alert">
          {error}
        </div>
      )}
      {items.length > 0 && (
        <div className="suggestions-table">
          <div className="suggestions-title">
            <Title>Kiểm duyệt từng gợi ý</Title>
            <span>
              {items.filter((s) => s.status !== "pending").length}/
              {items.length} đã xử lý
            </span>
          </div>
          {items.map((s) => (
            <div
              className={`suggestion-item ${
                s.status === "rejected" ? "is-rejected" : ""
              }`}
              key={s.id}
            >
              <div
                className={`confidence-ring ${
                  s.confidence < 80 ? "uncertain" : ""
                }`}
              >
                {s.confidence}%
              </div>
              <div className="suggestion-description">
                {editing === s.id && s.status === "pending" ? (
                  <>
                    <TextField
                      aria-label="Tên gợi ý"
                      value={s.name}
                      onChange={(e) =>
                        setItems(
                          items.map((i) =>
                            i.id === s.id ? { ...i, name: e.target.value } : i,
                          ),
                        )
                      }
                    />
                    <div className="coordinate-fields">
                      <label>
                        X
                        <TextField
                          aria-label="Tọa độ X gợi ý"
                          type="number"
                          min={0}
                          max={1000}
                          value={s.x}
                          onChange={(e) =>
                            setItems(
                              items.map((i) =>
                                i.id === s.id
                                  ? {
                                      ...i,
                                      x: Math.max(
                                        0,
                                        Math.min(1000, Number(e.target.value)),
                                      ),
                                    }
                                  : i,
                              ),
                            )
                          }
                        />
                      </label>
                      <label>
                        Y
                        <TextField
                          aria-label="Tọa độ Y gợi ý"
                          type="number"
                          min={0}
                          max={660}
                          value={s.y}
                          onChange={(e) =>
                            setItems(
                              items.map((i) =>
                                i.id === s.id
                                  ? {
                                      ...i,
                                      y: Math.max(
                                        0,
                                        Math.min(660, Number(e.target.value)),
                                      ),
                                    }
                                  : i,
                              ),
                            )
                          }
                        />
                      </label>
                    </div>
                  </>
                ) : (
                  <strong>{s.name}</strong>
                )}
                <span>
                  {s.kind === "edge" ? "Cạnh có hướng" : kindLabels[s.kind]} ·{" "}
                  {s.confidence < 80
                    ? "Độ tin cậy thấp · Cần đối chiếu"
                    : "Đề xuất mẫu · Chưa kiểm chứng"}
                </span>
              </div>
              {s.status === "pending" ? (
                <div className="suggestion-actions">
                  <Button
                    aria-label={`Chỉnh sửa ${s.name}`}
                    onClick={() => setEditing(editing === s.id ? "" : s.id)}
                  >
                    <Pencil size={15} />
                  </Button>
                  <Button
                    aria-label={`Từ chối ${s.name}`}
                    onClick={() => review(s.id, false)}
                  >
                    <X size={15} />
                  </Button>
                  <Button
                    className="accept-suggestion"
                    onClick={() => review(s.id, true)}
                  >
                    <Check size={15} />
                    Chấp nhận
                  </Button>
                </div>
              ) : (
                <span className="reviewed-label">
                  {s.status === "accepted" ? (
                    <CheckCircle2 size={14} />
                  ) : (
                    <X size={14} />
                  )}
                  {s.status === "accepted"
                    ? "Đã thêm vào bản nháp"
                    : "Đã từ chối"}
                </span>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
