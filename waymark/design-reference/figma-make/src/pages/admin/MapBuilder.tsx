import { useCallback, useEffect, useRef, useState } from "react"
import {
  Accessibility,
  ArrowLeft,
  ArrowRight,
  Building2,
  Check,
  CheckCircle2,
  ChevronDown,
  ChevronRight,
  CircleDot,
  Clock3,
  Eye,
  EyeOff,
  FileImage,
  GitBranch,
  Hand,
  History,
  ImagePlus,
  Layers,
  LoaderCircle,
  Maximize,
  Minus,
  MousePointer2,
  Plus,
  QrCode,
  Redo2,
  Route,
  Save,
  ShieldCheck,
  Sparkles,
  Trash2,
  TriangleAlert,
  Undo2,
  Upload,
  X,
} from "lucide-react"
import {
  Button,
  SelectField,
  TextField,
  Title,
} from "../../components/WaymarkUI"
import MapCanvas from "../../components/map-builder/MapCanvas"
import AIAnalysis from "../../components/map-builder/AIAnalysis"
import {
  kindLabels,
  routeFor,
  seedDocument,
  statusLabels,
  validateMap,
} from "../../components/map-builder/model"
import type {
  FloorDocument,
  Graph,
  MapNode,
  NodeKind,
} from "../../components/map-builder/model"

const tabs = [
  { id: "editor", title: "Trình chỉnh sửa", icon: GitBranch },
  { id: "plans", title: "Mặt bằng", icon: FileImage },
  { id: "ai", title: "Phân tích AI", icon: Sparkles },
  { id: "review", title: "Kiểm tra & xuất bản", icon: ShieldCheck },
]
const tools = [
  { id: "select", label: "Chọn / kéo đối tượng", icon: MousePointer2 },
  { id: "pan", label: "Di chuyển bản đồ", icon: Hand },
  { id: "node", label: "Thêm nút", icon: Plus },
  { id: "connect", label: "Nối hai nút có hướng", icon: GitBranch },
  { id: "qr", label: "Thêm mốc QR", icon: QrCode },
]
const now = () =>
  new Date().toLocaleTimeString("vi-VN", { hour: "2-digit", minute: "2-digit" })
export function MapBuilder() {
  const [hospital, setHospital] = useState("waymark")
  const [building, setBuilding] = useState("A")
  const [floor, setFloor] = useState(0)
  const key = `${hospital}-${building}-${floor}`
  const [docs, setDocs] = useState<Record<string, FloorDocument>>({
    "waymark-A-0": seedDocument(0),
    "waymark-A-1": seedDocument(1),
  })
  const doc = docs[key] || seedDocument(floor, false)
  const other = docs[`${hospital}-${building}-${1 - floor}`]
  const [tab, setTab] = useState("editor")
  const [tool, setTool] = useState("select")
  const [mode, setMode] = useState("edit")
  const [selected, setSelected] = useState("n3")
  const [connectFrom, setConnectFrom] = useState("")
  const [visible, setVisible] = useState(true)
  const [zoom, setZoom] = useState(1)
  const [pan, setPan] = useState({ x: 0, y: 0 })
  const [routeStart, setRouteStart] = useState("")
  const [routeEnd, setRouteEnd] = useState("")
  const [role, setRole] = useState("admin")
  const [notice, setNotice] = useState("")
  const [uploadState, setUploadState] = useState<Record<string, {
    loading: boolean
    error: string
  }>>({})
  const [dragOver, setDragOver] = useState(false)
  const [confirmPublish, setConfirmPublish] = useState(false)
  const input = useRef<HTMLInputElement>(null)
  const urls = useRef<string[]>([])
  const requests = useRef<Record<string, number>>({})
  const graph = doc.graph
  const selectedNode = graph.nodes.find((n) => n.id === selected)
  const selectedEdge = graph.edges.find((e) => e.id === selected)
  const checks = validateMap(doc, other)
  const blockers = checks.filter((c) => c.blocking && !c.pass)
  const warnings = checks.filter((c) => !c.blocking && !c.pass)
  const imageState = uploadState[key]
  const canPublish =
    doc.status === "review" &&
    doc.reviewed &&
    doc.acknowledged &&
    !blockers.length &&
    role === "reviewer"
  useEffect(
    () => () => urls.current.forEach((url) => URL.revokeObjectURL(url)),
    [],
  )
  useEffect(() => {
    setDocs((all) =>
      all[key] ? all : { ...all, [key]: seedDocument(floor, false) },
    )
    setSelected(docs[key]?.graph.nodes[2]?.id || "")
    setConnectFrom("")
    setZoom(1)
    setPan({ x: 0, y: 0 })
    setRouteStart("")
    setRouteEnd("")
    setConfirmPublish(false)
  }, [key])
  function updateDoc(fn: (d: FloorDocument) => FloorDocument) {
    setDocs((all) => ({
      ...all,
      [key]: fn(all[key] || seedDocument(floor, false)),
    }))
  }
  function editGraph(fn: (g: Graph) => Graph) {
    updateDoc((d) => ({
      ...d,
      graph: fn(d.graph),
      past: [...d.past.slice(-39), d.graph],
      future: [],
      dirty: true,
      status: "draft",
      reviewed: false,
      acknowledged: false,
    }))
  }
  const onPending = useCallback(
    (count: number) => {
      setDocs((all) => {
        const current = all[key] || seedDocument(floor, false)
        return {
          ...all,
          [key]: {
            ...current,
            aiPending: count,
            status: "draft",
            dirty: true,
            reviewed: false,
            acknowledged: false,
          },
        }
      })
    },
    [key, floor],
  )
  function changeHistory(redo: boolean) {
    updateDoc((d) => {
      const source = redo ? d.future : d.past
      if (!source.length) return d
      return {
        ...d,
        graph: source[source.length - 1],
        past: redo ? [...d.past, d.graph] : d.past.slice(0, -1),
        future: redo ? d.future.slice(0, -1) : [...d.future, d.graph],
        dirty: true,
        status: "draft",
        reviewed: false,
        acknowledged: false,
      }
    })
  }
  function selectObject(id: string) {
    setSelected(id)
    if (tool !== "connect" || !graph.nodes.some((n) => n.id === id)) return
    if (!connectFrom) {
      setConnectFrom(id)
      setNotice("Đã chọn nút đầu. Chọn nút đích để nối cạnh có hướng.")
      return
    }
    if (connectFrom === id) {
      setNotice("Chọn một nút khác để nối.")
      return
    }
    if (graph.edges.some((e) => e.from === connectFrom && e.to === id)) {
      setNotice("Cạnh có hướng này đã tồn tại.")
      setConnectFrom("")
      return
    }
    editGraph((g) => ({
      ...g,
      edges: [
        ...g.edges,
        {
          id: crypto.randomUUID(),
          from: connectFrom,
          to: id,
          accessible: "unknown",
        },
      ],
    }))
    setConnectFrom("")
    setNotice(
      "Đã nối cạnh có hướng. Kiểm tra trên mặt bằng để tránh đi xuyên tường.",
    )
  }
  function addNode(x: number, y: number) {
    if (!doc.image) return
    const id = crypto.randomUUID()
    editGraph((g) => ({
      ...g,
      nodes: [
        ...g.nodes,
        {
          id,
          name:
            tool === "qr"
              ? `Mốc QR ${g.nodes.length + 1}`
              : `Điểm mới ${g.nodes.length + 1}`,
          kind: tool === "qr" ? "qr" : "corridor",
          x: Math.round(x),
          y: Math.round(y),
          qr: "",
          connector: "",
          accessible: "unknown",
        },
      ],
    }))
    setSelected(id)
    setNotice(
      tool === "qr"
        ? "Đã thêm mốc QR. Nhập mã liên kết trong bảng thuộc tính."
        : "Đã thêm nút. Kéo để điều chỉnh và nối với mạng lưới.",
    )
  }
  function patchNode(patch: Partial<MapNode>) {
    editGraph((g) => ({
      ...g,
      nodes: g.nodes.map((n) => (n.id === selected ? { ...n, ...patch } : n)),
    }))
  }
  function saveDraft() {
    updateDoc((d) => ({
      ...d,
      saved: now(),
      dirty: false,
      status: "draft",
      reviewed: false,
      acknowledged: false,
      versions: [
        {
          name: `v0.${d.versions.length + 1} · Bản nháp`,
          date: now(),
          status: "Đã lưu trong phiên",
        },
        ...d.versions,
      ],
    }))
    setNotice(
      "Đã lưu bản nháp trong phiên này. Chưa lưu lên máy chủ; tải lại trang sẽ khôi phục dữ liệu mẫu.",
    )
  }
  async function upload(file?: File) {
    if (!file) return
    const target = key,
      targetFloor = floor
    const request = (requests.current[target] || 0) + 1
    requests.current[target] = request
    if (
      !["image/png", "image/jpeg"].includes(file.type) ||
      file.size > 20 * 1024 * 1024
    ) {
      setUploadState((s) => ({
        ...s,
        [target]: {
          loading: false,
          error:
            "Chọn ảnh PNG hoặc JPG, dung lượng tối đa 20 MB. Ảnh hiện tại chưa bị thay đổi.",
        },
      }))
      return
    }
    setUploadState((s) => ({ ...s, [target]: { loading: true, error: "" } }))
    const url = URL.createObjectURL(file)
    urls.current.push(url)
    const image = new Image()
    image.src = url
    try {
      await image.decode()
      if (requests.current[target] !== request) return
      setDocs((all) => {
        const previous = all[target] || seedDocument(targetFloor, false)
        return {
          ...all,
          [target]: {
            ...seedDocument(targetFloor, false),
            image: {
              url,
              name: file.name,
              width: image.naturalWidth,
              height: image.naturalHeight,
              size: file.size,
              sample: false,
            },
            dirty: true,
            versions: previous.versions,
          },
        }
      })
      setUploadState((s) => ({ ...s, [target]: { loading: false, error: "" } }))
      setNotice(
        `Đã tải ${file.name} lên tầng ${
          targetFloor ? "L1" : "G"
        }. Ảnh đã hiển thị; đồ thị cũ được xóa để tránh lệch tọa độ.`,
      )
      setSelected("")
      setZoom(1)
      setPan({ x: 0, y: 0 })
    } catch {
      if (requests.current[target] !== request) return
      setUploadState((s) => ({
        ...s,
        [target]: {
          loading: false,
          error:
            "Không đọc được ảnh. Tệp có thể bị hỏng; vui lòng thử ảnh khác. Ảnh cũ được giữ nguyên.",
        },
      }))
    }
  }
  function removeImage() {
    requests.current[key] = (requests.current[key] || 0) + 1
    updateDoc((d) => ({
      ...seedDocument(floor, false),
      dirty: true,
      versions: d.versions,
    }))
    setUploadState((s) => ({ ...s, [key]: { loading: false, error: "" } }))
    setNotice(
      "Đã xóa ảnh và đồ thị của tầng đang chọn. Các tầng khác được giữ nguyên.",
    )
  }
  function useSample() {
    requests.current[key] = (requests.current[key] || 0) + 1
    updateDoc((d) => ({
      ...seedDocument(floor),
      dirty: true,
      versions: d.versions,
    }))
    setUploadState((s) => ({ ...s, [key]: { loading: false, error: "" } }))
    setNotice("Đã mở sơ đồ và đồ thị mẫu cho tầng đang chọn.")
  }
  function acceptSuggestion(node: MapNode | null, edge: boolean) {
    if (
      edge &&
      !(
        graph.nodes.some((n) => n.id === "ai-corridor") &&
        graph.nodes.some((n) => n.id === "ai-elevator")
      )
    )
      return false
    editGraph((g) =>
      node
        ? { ...g, nodes: [...g.nodes.filter((n) => n.id !== node.id), node] }
        : {
            ...g,
            edges: [
              ...g.edges,
              {
                id: crypto.randomUUID(),
                from: "ai-corridor",
                to: "ai-elevator",
                accessible: "unknown",
              },
            ],
          },
    )
    return true
  }
  const canvas = (
    <MapCanvas
      image={doc.image}
      graph={graph}
      mode={mode}
      tool={tool}
      visible={visible}
      selected={selected}
      onSelect={selectObject}
      onAdd={addNode}
      onMove={(id, x, y) =>
        editGraph((g) => ({
          ...g,
          nodes: g.nodes.map((n) => (n.id === id ? { ...n, x, y } : n)),
        }))
      }
      zoom={zoom}
      pan={pan}
      onPan={setPan}
      start={routeStart}
      end={routeEnd}
    />
  )
  return (
    <div className="floor-studio">
      <header className="studio-header">
        <div>
          <div className="studio-breadcrumb">
            Không gian quản trị <ChevronRight size={12} /> Quản lý bản đồ
          </div>
          <div className="studio-title">
            <Title>Bản đồ & tuyến đường</Title>
            <span className={`document-status status-${doc.status}`}>
              <span />
              {statusLabels[doc.status]}
            </span>
          </div>
          <p>Mỗi điểm kết nối, một hành trình rõ ràng.</p>
        </div>
        <div className="studio-header-actions">
          <span className="simulation-label">BẢN MẪU TƯƠNG TÁC</span>
          <Button className="save-draft" onClick={saveDraft}>
            <Save size={16} />
            Lưu bản nháp
          </Button>
          <Button className="primary-action" onClick={() => setTab("review")}>
            <ShieldCheck size={16} />
            Kiểm tra & xuất bản
            <ArrowRight size={15} />
          </Button>
        </div>
      </header>
      <div className="studio-context">
        <div>
          <Building2 size={18} />
          <SelectField
            aria-label="Bệnh viện"
            value={hospital}
            onChange={(e) => setHospital(e.target.value)}
          >
            <option value="waymark">Bệnh viện WayMark</option>
            <option value="satellite">Cơ sở 2 · Dữ liệu trống</option>
          </SelectField>
        </div>
        <ChevronRight size={14} />
        <div>
          <SelectField
            aria-label="Tòa nhà"
            value={building}
            onChange={(e) => setBuilding(e.target.value)}
          >
            <option value="A">Tòa A · Khám bệnh</option>
            <option value="B">Tòa B · Điều trị</option>
          </SelectField>
        </div>
        <ChevronRight size={14} />
        <div>
          <Layers size={16} />
          <SelectField
            aria-label="Chọn tầng"
            value={floor}
            onChange={(e) => setFloor(Number(e.target.value))}
          >
            <option value={0}>G · Tầng trệt</option>
            <option value={1}>L1 · Lầu 1</option>
          </SelectField>
        </div>
        <span className="context-session">
          <Clock3 size={13} />
          {doc.dirty
            ? "Có thay đổi chưa lưu"
            : doc.saved
              ? `Đã lưu lúc ${doc.saved}`
              : "Dữ liệu minh họa"}
        </span>
      </div>
      <div className="studio-tabs" role="tablist" aria-label="Quản lý mặt bằng">
        {tabs.map((t) => (
          <Button
            role="tab"
            aria-selected={tab === t.id}
            key={t.id}
            className={tab === t.id ? "active" : ""}
            onClick={() => setTab(t.id)}
          >
            <t.icon size={16} />
            {t.title}
            {t.id === "ai" && <span className="tab-new">MỚI</span>}
          </Button>
        ))}
      </div>
      {notice && (
        <div className="studio-notice" role="status">
          <CheckCircle2 size={16} />
          <span>{notice}</span>
          <Button aria-label="Đóng thông báo" onClick={() => setNotice("")}>
            <X size={14} />
          </Button>
        </div>
      )}
      <TextField
        ref={input}
        type="file"
        accept="image/png,image/jpeg"
        className="sr-only"
        aria-label="Tải ảnh mặt bằng"
        onChange={(e) => {
          void upload(e.target.files?.[0])
          e.target.value = ""
        }}
      />
      {Object.entries(docs).map(([documentKey, document]) => (
        <div
          key={`${documentKey}-${document.image?.url || "empty"}`}
          hidden={tab !== "ai" || documentKey !== key}
        >
          <AIAnalysis
            image={document.image}
            onAccept={acceptSuggestion}
            onPending={
              documentKey === key
                ? onPending
                : (count) =>
                    setDocs((all) => ({
                      ...all,
                      [documentKey]: {
                        ...all[documentKey],
                        aiPending: count,
                        status: "draft",
                        dirty: true,
                        reviewed: false,
                        acknowledged: false,
                      },
                    }))
            }
          />
        </div>
      ))}
      {tab === "plans" && (
        <div className="plan-manager">
          <div className="plan-upload-panel">
            <div className="eyebrow">THƯ VIỆN MẶT BẰNG</div>
            <Title>Mặt bằng tầng {floor ? "L1" : "G"}</Title>
            <p>
              Ảnh nền là cơ sở để định nghĩa các điểm WayMark và tuyến đường
              trong nhà.
            </p>
            <div
              className={`plan-dropzone ${dragOver ? "drag-over" : ""}`}
              onDragOver={(e) => {
                e.preventDefault()
                setDragOver(true)
              }}
              onDragLeave={() => setDragOver(false)}
              onDrop={(e) => {
                e.preventDefault()
                setDragOver(false)
                void upload(e.dataTransfer.files[0])
              }}
            >
              <div className="upload-symbol">
                {imageState?.loading ? (
                  <LoaderCircle size={26} className="animate-spin" />
                ) : (
                  <Upload size={26} />
                )}
              </div>
              <strong>
                {imageState?.loading
                  ? "Đang đọc ảnh mặt bằng…"
                  : "Kéo ảnh mặt bằng vào đây"}
              </strong>
              <span>PNG, JPG · Tối đa 20 MB</span>
              <Button
                onClick={() => input.current?.click()}
                disabled={imageState?.loading}
              >
                <ImagePlus size={16} />
                {doc.image ? "Chọn ảnh thay thế" : "Chọn ảnh từ thiết bị"}
              </Button>
            </div>
            {imageState?.error && (
              <div className="upload-error" role="alert">
                <TriangleAlert size={16} />
                {imageState.error}
              </div>
            )}
            {doc.image ? (
              <div className="file-details">
                <div>
                  <FileImage size={24} />
                  <strong>
                    {doc.image.name}
                    <span>
                      {doc.image.sample
                        ? "Sơ đồ mẫu minh họa"
                        : "Ảnh tải lên thành công"}
                    </span>
                  </strong>
                  <CheckCircle2 size={17} />
                </div>
                <dl>
                  <div>
                    <dt>Kích thước</dt>
                    <dd>
                      {doc.image.width} × {doc.image.height} px
                    </dd>
                  </div>
                  <div>
                    <dt>Dung lượng</dt>
                    <dd>{(doc.image.size / 1024).toFixed(1)} KB</dd>
                  </div>
                  <div>
                    <dt>Vị trí</dt>
                    <dd>
                      Tòa {building} · Tầng {floor ? "L1" : "G"}
                    </dd>
                  </div>
                  <div>
                    <dt>Trạng thái</dt>
                    <dd>{statusLabels[doc.status]}</dd>
                  </div>
                </dl>
                <Button className="remove-plan" onClick={removeImage}>
                  <Trash2 size={14} />
                  Xóa ảnh & đồ thị tầng này
                </Button>
              </div>
            ) : (
              <div className="empty-plan-note">
                <FileImage size={20} />
                <strong>Chưa có mặt bằng</strong>
                <p>Ảnh xuất hiện ngay trên canvas sau khi đọc thành công.</p>
              </div>
            )}
            <Button className="sample-plan" onClick={useSample}>
              Dùng sơ đồ bệnh viện mẫu
              <ArrowRight size={14} />
            </Button>
            <div className="ai-disclaimer">
              <ShieldCheck size={17} />
              <span>
                Chỉ dùng dữ liệu minh họa. Thay ảnh sẽ xóa đồ thị cũ của tầng
                này để tránh sai lệch vị trí.
              </span>
            </div>
          </div>
          <div className="plan-preview-panel">
            <div className="comparison-heading">
              <strong>Xem trước mặt bằng · Tầng {floor ? "L1" : "G"}</strong>
              <span>
                {doc.image ? "Đã hiển thị trên canvas" : "Đang chờ ảnh"}
              </span>
            </div>
            {canvas}
            <div className="plan-preview-footer">
              <span>
                <span className="status-dot" />
                Ảnh riêng cho từng tòa và tầng
              </span>
              <Button
                className="primary-action"
                disabled={!doc.image}
                onClick={() => {
                  setTab("editor")
                  setMode("edit")
                }}
              >
                Mở trình chỉnh sửa
                <ArrowRight size={16} />
              </Button>
            </div>
          </div>
        </div>
      )}
      {tab === "editor" && (
        <div className="studio-editor">
          <aside className="studio-objects">
            <div className="section-caption">CẤU TRÚC BỆNH VIỆN</div>
            <Button
              className="building-tree"
              onClick={() => setBuilding(building === "A" ? "B" : "A")}
            >
              <Building2 size={16} />
              Tòa {building}
              <ChevronDown size={13} />
            </Button>
            {[0, 1].map((f) => (
              <Button
                key={f}
                className={`floor-tree ${floor === f ? "active" : ""}`}
                onClick={() => setFloor(f)}
              >
                <Layers size={14} />
                <span>{f ? "L1 · Khám chuyên khoa" : "G · Tiếp đón"}</span>
                <span>
                  {docs[`${hospital}-${building}-${f}`]?.graph.nodes.length ||
                    0}
                </span>
              </Button>
            ))}
            <div className="section-caption layer-heading">LỚP HIỂN THỊ</div>
            <Button
              className="layer-toggle"
              onClick={() => setVisible(!visible)}
              aria-pressed={visible}
            >
              {visible ? <Eye size={15} /> : <EyeOff size={15} />}Đồ thị điều
              hướng<span>{graph.nodes.length}</span>
            </Button>
            <Button className="layer-toggle" onClick={() => setTab("plans")}>
              <FileImage size={15} />
              Mặt bằng gốc
              <ChevronRight size={13} />
            </Button>
            <div className="section-caption layer-heading">
              ĐỐI TƯỢNG BẢN ĐỒ <span>{graph.nodes.length}</span>
            </div>
            <div className="objects-scroll">
              {graph.nodes.map((n) => (
                <Button
                  key={n.id}
                  className={`studio-object ${
                    selected === n.id ? "active" : ""
                  }`}
                  onClick={() => selectObject(n.id)}
                >
                  {n.kind === "qr" || n.qr ? (
                    <QrCode size={15} />
                  ) : (
                    <CircleDot size={15} />
                  )}
                  <span>
                    {n.name}
                    <small>{kindLabels[n.kind]}</small>
                  </span>
                </Button>
              ))}
              {!graph.nodes.length && (
                <p className="object-empty">
                  Thêm nút trên canvas hoặc xem gợi ý AI để bắt đầu.
                </p>
              )}
            </div>
            <div className="object-footnote">
              <ShieldCheck size={18} />
              <strong>Bản đồ an toàn cần kiểm chứng</strong>
              <p>Gợi ý AI không thay thế khảo sát thực địa.</p>
            </div>
          </aside>
          <div className="studio-center">
            <div className="editor-toolbar">
              <div className="tool-group">
                {tools.map((t) => (
                  <Button
                    title={t.label}
                    aria-label={t.label}
                    aria-pressed={tool === t.id}
                    disabled={mode === "preview"}
                    key={t.id}
                    className={tool === t.id && mode === "edit" ? "active" : ""}
                    onClick={() => {
                      setTool(t.id)
                      setConnectFrom("")
                    }}
                  >
                    <t.icon size={17} />
                  </Button>
                ))}
              </div>
              <div className="tool-group">
                <Button
                  title="Hoàn tác"
                  aria-label="Hoàn tác"
                  disabled={!doc.past.length || mode === "preview"}
                  onClick={() => changeHistory(false)}
                >
                  <Undo2 size={17} />
                </Button>
                <Button
                  title="Làm lại"
                  aria-label="Làm lại"
                  disabled={!doc.future.length || mode === "preview"}
                  onClick={() => changeHistory(true)}
                >
                  <Redo2 size={17} />
                </Button>
              </div>
              <div className="editor-mode">
                <Button
                  className={mode === "edit" ? "active" : ""}
                  onClick={() => setMode("edit")}
                >
                  <GitBranch size={14} />
                  Chỉnh đồ thị
                </Button>
                <Button
                  className={mode === "preview" ? "active" : ""}
                  onClick={() => {
                    setMode("preview")
                    setZoom(1)
                    setPan({ x: 0, y: 0 })
                  }}
                >
                  <Route size={14} />
                  Xem tuyến
                </Button>
              </div>
            </div>
            <div className="canvas-info">
              <span>
                <span className="status-dot" />
                Tòa {building} / {floor ? "Lầu 1" : "Tầng trệt"}
                <span className="mini-mock">MINH HỌA</span>
              </span>
              <span>
                {doc.image?.sample
                  ? "Mặt bằng mẫu · Chưa khảo sát"
                  : doc.image
                    ? "Ảnh cục bộ · Cần căn chỉnh tọa độ"
                    : "Chưa có ảnh mặt bằng"}
              </span>
            </div>
            <div className="editable-map-area">
              {canvas}
              {!doc.image && (
                <div className="empty-canvas-actions">
                  <Button
                    className="primary-action"
                    onClick={() => setTab("plans")}
                  >
                    <Upload size={16} />
                    Tải mặt bằng
                  </Button>
                  <Button onClick={useSample}>Mở sơ đồ mẫu</Button>
                </div>
              )}
            </div>
            <div className="canvas-controls">
              <div className="canvas-legend">
                <span>
                  <i className="legend-dot" />
                  Nút điều hướng
                </span>
                <span>
                  <i className="cyan-dot" />
                  Điểm đến
                </span>
                <span>
                  <i className="amber-dot" />
                  Chưa xác minh
                </span>
              </div>
              <div className="zoom-control">
                <Button
                  aria-label="Thu nhỏ bản đồ"
                  onClick={() => setZoom((z) => Math.max(0.5, z - 0.15))}
                >
                  <Minus size={15} />
                </Button>
                <span>{Math.round(zoom * 100)}%</span>
                <Button
                  aria-label="Phóng to bản đồ"
                  onClick={() => setZoom((z) => Math.min(2.5, z + 0.15))}
                >
                  <Plus size={15} />
                </Button>
                <Button
                  aria-label="Vừa khung hình"
                  title="Vừa khung hình"
                  onClick={() => {
                    setZoom(1)
                    setPan({ x: 0, y: 0 })
                  }}
                >
                  <Maximize size={15} />
                </Button>
              </div>
            </div>
            {mode === "preview" ? (
              <div className="route-preview-controls">
                <div>
                  <Route size={18} />
                  <strong>
                    Tuyến xem trước <span>Chỉ hiển thị đường đi đã chọn</span>
                  </strong>
                </div>
                <div className="route-selectors">
                  <SelectField
                    aria-label="Điểm đầu xem tuyến"
                    value={routeStart}
                    onChange={(e) => setRouteStart(e.target.value)}
                  >
                    <option value="">Điểm đầu mặc định</option>
                    {graph.nodes.map((n) => (
                      <option key={n.id} value={n.id}>
                        {n.name}
                      </option>
                    ))}
                  </SelectField>
                  <ArrowRight size={14} />
                  <SelectField
                    aria-label="Điểm đích xem tuyến"
                    value={routeEnd}
                    onChange={(e) => setRouteEnd(e.target.value)}
                  >
                    <option value="">Điểm đến mặc định</option>
                    {graph.nodes.map((n) => (
                      <option key={n.id} value={n.id}>
                        {n.name}
                      </option>
                    ))}
                  </SelectField>
                </div>
                <p>
                  {routeFor(graph, routeStart, routeEnd).length > 1
                    ? "Tìm thấy tuyến mẫu theo cạnh có hướng. Đơn vị tọa độ ảnh, chưa hiệu chuẩn khoảng cách thực."
                    : "Không có tuyến có hướng giữa hai điểm. Quay lại chỉnh đồ thị để bổ sung kết nối."}
                </p>
              </div>
            ) : (
              <div className="editor-hint">
                <MousePointer2 size={14} />
                <span>
                  {tool === "connect"
                    ? connectFrom
                      ? "Chọn nút đích để tạo cạnh."
                      : "Chọn nút đầu, sau đó chọn nút đích."
                    : tool === "node" || tool === "qr"
                      ? "Chạm lên mặt bằng để thêm điểm mới."
                      : tool === "pan"
                        ? "Kéo nền bản đồ để di chuyển. Nhấn vừa khung để đặt lại."
                        : "Kéo điểm để chỉnh tọa độ · Chọn cạnh để sửa kết nối."}
                </span>
                <span>
                  {graph.nodes.length} nút · {graph.edges.length} cạnh
                </span>
              </div>
            )}
          </div>
          <aside className="studio-inspector">
            <div className="inspector-heading">
              <strong>Thuộc tính đối tượng</strong>
              <span>
                {selectedEdge
                  ? "Cạnh"
                  : selectedNode
                    ? kindLabels[selectedNode.kind]
                    : "Chưa chọn"}
              </span>
            </div>
            {selectedNode ? (
              <>
                <div className="selected-object-title">
                  <div>
                    <MapNodeIcon kind={selectedNode.kind} />
                  </div>
                  <strong>
                    {selectedNode.name}
                    <span>{selectedNode.id.slice(0, 12)}</span>
                  </strong>
                </div>
                <label>
                  Tên hiển thị
                  <TextField
                    value={selectedNode.name}
                    disabled={mode === "preview"}
                    onChange={(e) => patchNode({ name: e.target.value })}
                  />
                </label>
                <label>
                  Loại đối tượng
                  <SelectField
                    value={selectedNode.kind}
                    disabled={mode === "preview"}
                    onChange={(e) =>
                      patchNode({ kind: e.target.value as NodeKind })
                    }
                  >
                    {Object.entries(kindLabels).map(([value, label]) => (
                      <option key={value} value={value}>
                        {label}
                      </option>
                    ))}
                  </SelectField>
                </label>
                <div className="coordinate-fields">
                  <label>
                    X · đơn vị ảnh
                    <TextField
                      type="number"
                      min={0}
                      max={1000}
                      value={selectedNode.x}
                      disabled={mode === "preview"}
                      onChange={(e) =>
                        patchNode({
                          x: Math.max(
                            0,
                            Math.min(1000, Number(e.target.value)),
                          ),
                        })
                      }
                    />
                  </label>
                  <label>
                    Y · đơn vị ảnh
                    <TextField
                      type="number"
                      min={0}
                      max={660}
                      value={selectedNode.y}
                      disabled={mode === "preview"}
                      onChange={(e) =>
                        patchNode({
                          y: Math.max(0, Math.min(660, Number(e.target.value))),
                        })
                      }
                    />
                  </label>
                </div>
                <label>
                  Mã QR liên kết
                  <TextField
                    placeholder="Ví dụ: WM-G01"
                    value={selectedNode.qr}
                    disabled={mode === "preview"}
                    onChange={(e) => patchNode({ qr: e.target.value })}
                  />
                </label>
                {(selectedNode.kind === "elevator" ||
                  selectedNode.kind === "stairs") && (
                  <label>
                    Mã kết nối liên tầng
                    <TextField
                      placeholder="Ví dụ: E1 hoặc S1"
                      value={selectedNode.connector}
                      disabled={mode === "preview"}
                      onChange={(e) => patchNode({ connector: e.target.value })}
                    />
                    <small>Hai tầng phải dùng cùng mã và loại điểm.</small>
                  </label>
                )}
                <label>
                  Điều kiện tiếp cận
                  <SelectField
                    value={selectedNode.accessible}
                    disabled={mode === "preview"}
                    onChange={(e) =>
                      patchNode({
                        accessible: e.target.value as MapNode["accessible"],
                      })
                    }
                  >
                    <option value="unknown">Chưa xác minh</option>
                    <option value="yes">
                      Phù hợp xe lăn · Khai báo mô phỏng
                    </option>
                    <option value="no">Không phù hợp xe lăn</option>
                  </SelectField>
                </label>
                <div className="inspector-warning">
                  <TriangleAlert size={16} />
                  <span>
                    Đây là khai báo trong bản mẫu, không phải chứng nhận tiếp
                    cận thực tế.
                  </span>
                </div>
                <Button
                  className="delete-object"
                  disabled={mode === "preview"}
                  onClick={() => {
                    editGraph((g) => ({
                      nodes: g.nodes.filter((n) => n.id !== selected),
                      edges: g.edges.filter(
                        (e) => e.from !== selected && e.to !== selected,
                      ),
                    }))
                    setSelected("")
                  }}
                >
                  <Trash2 size={14} />
                  Xóa đối tượng
                </Button>
              </>
            ) : selectedEdge ? (
              <>
                <div className="selected-object-title">
                  <GitBranch size={22} />
                  <strong>
                    Cạnh có hướng<span>{selectedEdge.id.slice(0, 12)}</span>
                  </strong>
                </div>
                {(["from", "to"] as const).map((field) => (
                  <label key={field}>
                    {field === "from" ? "Nút đầu" : "Nút đích"}
                    <SelectField
                      disabled={mode === "preview"}
                      value={selectedEdge[field]}
                      onChange={(e) =>
                        editGraph((g) => ({
                          ...g,
                          edges: g.edges.map((edge) =>
                            edge.id === selected
                              ? { ...edge, [field]: e.target.value }
                              : edge,
                          ),
                        }))
                      }
                    >
                      {graph.nodes.map((n) => (
                        <option key={n.id} value={n.id}>
                          {n.name}
                        </option>
                      ))}
                    </SelectField>
                  </label>
                ))}
                <label>
                  Điều kiện tiếp cận
                  <SelectField
                    disabled={mode === "preview"}
                    value={selectedEdge.accessible}
                    onChange={(e) =>
                      editGraph((g) => ({
                        ...g,
                        edges: g.edges.map((edge) =>
                          edge.id === selected
                            ? {
                                ...edge,
                                accessible: e.target
                                  .value as MapNode["accessible"],
                              }
                            : edge,
                        ),
                      }))
                    }
                  >
                    <option value="unknown">Chưa xác minh</option>
                    <option value="yes">Phù hợp xe lăn · Mô phỏng</option>
                    <option value="no">Không phù hợp xe lăn</option>
                  </SelectField>
                </label>
                <div className="inspector-warning">
                  Cạnh hiển thị là đoạn nối thẳng. Thêm nút tại các góc hành
                  lang để không xuyên tường.
                </div>
                <Button
                  className="delete-object"
                  disabled={mode === "preview"}
                  onClick={() => {
                    editGraph((g) => ({
                      ...g,
                      edges: g.edges.filter((e) => e.id !== selected),
                    }))
                    setSelected("")
                  }}
                >
                  <Trash2 size={14} />
                  Xóa cạnh
                </Button>
              </>
            ) : (
              <div className="inspector-empty">
                <MousePointer2 size={30} />
                <strong>Chọn một đối tượng</strong>
                <p>
                  Chọn phòng, nút, cạnh hoặc mốc QR trên canvas để xem thuộc
                  tính.
                </p>
                <Button
                  onClick={() => {
                    setTab("ai")
                  }}
                >
                  Thử gợi ý AI
                  <Sparkles size={14} />
                </Button>
              </div>
            )}
            <div className="inspector-bottom">
              <ShieldCheck size={17} />
              <p>
                Thay đổi được ghi vào bản nháp. Kiểm tra lại trước khi xuất bản
                mô phỏng.
              </p>
            </div>
          </aside>
        </div>
      )}
      {tab === "review" && (
        <div className="validation-workspace">
          <div className="validation-intro">
            <div>
              <div className="eyebrow">CHẤT LƯỢNG DỮ LIỆU & PHÊ DUYỆT</div>
              <Title>Một bước kiểm tra. Một hành trình an toàn.</Title>
              <p>
                Kiểm tra đồ thị trước, phê duyệt bởi con người sau. Không xuất
                bản tự động.
              </p>
            </div>
            <span className="simulation-label">
              CHỈ XUẤT BẢN TRONG PHIÊN MÔ PHỎNG
            </span>
          </div>
          <div className="workflow-steps">
            {(["draft", "validation", "review", "published"] as const).map(
              (status, i) => (
                <div
                  key={status}
                  className={doc.status === status ? "active" : ""}
                >
                  <span>
                    {doc.status === "published" ||
                    i <
                      ["draft", "validation", "review", "published"].indexOf(
                        doc.status,
                      ) ? (
                      <Check size={15} />
                    ) : (
                      i + 1
                    )}
                  </span>
                  <strong>{statusLabels[status]}</strong>
                  {i < 3 && <ArrowRight size={15} />}
                </div>
              ),
            )}
          </div>
          <div className="validation-columns">
            <section className="validation-card">
              <div className="validation-card-heading">
                <ShieldCheck size={19} />
                <Title>Kiểm tra bản đồ tầng {floor ? "L1" : "G"}</Title>
                <Button
                  onClick={() => {
                    updateDoc((d) => ({
                      ...d,
                      status: "validation",
                      reviewed: false,
                      acknowledged: false,
                    }))
                    setNotice(
                      `Đã kiểm tra đồ thị: ${blockers.length} lỗi chặn, ${warnings.length} cảnh báo. Không kiểm tra tính đúng đắn với bệnh viện thực tế.`,
                    )
                  }}
                >
                  Chạy kiểm tra
                </Button>
              </div>
              {doc.status === "draft" ? (
                <div className="validation-pending">
                  <ShieldCheck size={36} />
                  <strong>Bản nháp cần được kiểm tra</strong>
                  <p>
                    Kiểm tra cấu trúc kết nối, mã QR, điểm chuyển tầng và thông
                    tin tiếp cận.
                  </p>
                </div>
              ) : (
                checks.map((check) => (
                  <div
                    className={`validation-check ${
                      check.pass ? "pass" : check.blocking ? "fail" : "warn"
                    }`}
                    key={check.name}
                  >
                    {check.pass ? (
                      <CheckCircle2 size={19} />
                    ) : (
                      <TriangleAlert size={19} />
                    )}
                    <div>
                      <strong>{check.name}</strong>
                      <p>
                        {check.pass
                          ? "Đạt kiểm tra cấu trúc trong bản mẫu."
                          : check.detail}
                      </p>
                    </div>
                    <span>
                      {check.pass
                        ? "Đạt"
                        : check.blocking
                          ? "Cần sửa"
                          : "Cảnh báo"}
                    </span>
                  </div>
                ))
              )}
              <div className="validation-actions">
                <Button
                  onClick={() => {
                    setTab("editor")
                    setMode("edit")
                  }}
                >
                  <ArrowLeft size={14} />
                  Chỉnh sửa bản đồ
                </Button>
                <Button
                  className="primary-action"
                  disabled={doc.status !== "validation" || blockers.length > 0}
                  onClick={() => updateDoc((d) => ({ ...d, status: "review" }))}
                >
                  Chuyển kiểm duyệt
                  <ArrowRight size={15} />
                </Button>
              </div>
            </section>
            <div className="review-side">
              <section className="review-card">
                <div className="validation-card-heading">
                  <ShieldCheck size={18} />
                  <Title>Phê duyệt con người</Title>
                </div>
                <label>
                  Vai trò trong bản mẫu
                  <SelectField
                    value={role}
                    onChange={(e) => setRole(e.target.value)}
                  >
                    <option value="admin">Admin · Chỉnh sửa, gửi duyệt</option>
                    <option value="reviewer">
                      Reviewer · Phê duyệt, xuất bản
                    </option>
                  </SelectField>
                </label>
                <p className="role-note">
                  Chuyển vai trò để thử quy trình. Đây không phải phân quyền hay
                  đăng nhập thực tế.
                </p>
                <Button
                  className={`review-acknowledgement ${
                    doc.acknowledged ? "checked" : ""
                  }`}
                  disabled={doc.status !== "review" || role !== "reviewer"}
                  aria-pressed={doc.acknowledged}
                  onClick={() =>
                    updateDoc((d) => ({
                      ...d,
                      acknowledged: !d.acknowledged,
                      reviewed: false,
                    }))
                  }
                >
                  <span>{doc.acknowledged && <Check size={13} />}</span>Tôi đã
                  xem các cảnh báo và hiểu bản đồ chưa được kiểm chứng thực địa.
                </Button>
                <Button
                  disabled={
                    doc.status !== "review" ||
                    role !== "reviewer" ||
                    !doc.acknowledged ||
                    blockers.length > 0
                  }
                  className={
                    doc.reviewed ? "approved-button" : "review-approve"
                  }
                  onClick={() => updateDoc((d) => ({ ...d, reviewed: true }))}
                >
                  <CheckCircle2 size={16} />
                  {doc.reviewed ? "Đã phê duyệt bản mẫu" : "Phê duyệt bản mẫu"}
                </Button>
                <Button
                  className="primary-action"
                  disabled={!canPublish}
                  onClick={() => setConfirmPublish(true)}
                >
                  Xuất bản mô phỏng
                  <ArrowRight size={16} />
                </Button>
              </section>
              <section className="version-card">
                <div className="validation-card-heading">
                  <History size={18} />
                  <Title>Lịch sử phiên bản</Title>
                </div>
                {doc.versions.map((v, i) => (
                  <div key={`${v.name}-${i}`} className="version-entry">
                    <span />
                    <div>
                      <strong>{v.name}</strong>
                      <p>
                        {v.date} · {v.status}
                      </p>
                    </div>
                  </div>
                ))}
              </section>
            </div>
          </div>
        </div>
      )}
      <footer className="studio-footer">
        <span>
          <ShieldCheck size={13} />
          WayMark Studio · Mặt bằng minh họa, không dùng làm hướng dẫn thực địa
        </span>
        <span>Chỉ lưu trong phiên · Không có backend</span>
      </footer>
      {confirmPublish && (
        <div className="modal-backdrop">
          <div
            className="confirm-card"
            role="dialog"
            aria-modal="true"
            aria-label="Xác nhận xuất bản mô phỏng"
          >
            <div className="publish-symbol">
              <ShieldCheck size={29} />
            </div>
            <Title>Xuất bản bản mẫu này?</Title>
            <p>
              Tòa {building} · Tầng {floor ? "L1" : "G"} · {graph.nodes.length}{" "}
              nút · {graph.edges.length} cạnh. Chỉ cập nhật trạng thái trong
              phiên làm việc này.
            </p>
            <div className="inspector-warning">
              <TriangleAlert size={17} />
              Không đưa dữ liệu này vào ứng dụng bệnh viện thực tế. Điều kiện
              tiếp cận và đo lường chưa được khảo sát.
            </div>
            <Button
              className="primary-action"
              disabled={!canPublish}
              onClick={() => {
                if (!canPublish) return
                updateDoc((d) => ({
                  ...d,
                  status: "published",
                  dirty: false,
                  saved: now(),
                  versions: [
                    {
                      name: `v0.${d.versions.length + 1} · Xuất bản mô phỏng`,
                      date: now(),
                      status: "Reviewer đã duyệt",
                    },
                    ...d.versions,
                  ],
                }))
                setConfirmPublish(false)
                setNotice(
                  "Đã xuất bản bản mẫu trong phiên. Không gửi dữ liệu tới máy chủ hoặc ứng dụng bệnh viện.",
                )
              }}
            >
              <Check size={17} />
              Xác nhận xuất bản mô phỏng
            </Button>
            <Button onClick={() => setConfirmPublish(false)}>
              Quay lại kiểm duyệt
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}
function MapNodeIcon({ kind }: { kind: NodeKind }) {
  return kind === "qr" ? (
    <QrCode size={21} />
  ) : kind === "room" ? (
    <Building2 size={21} />
  ) : kind === "elevator" ? (
    <Layers size={21} />
  ) : kind === "destination" ? (
    <Route size={21} />
  ) : (
    <CircleDot size={21} />
  )
}
export default MapBuilder
