export type NodeKind = "entrance" | "corridor" | "elevator" | "stairs" | "destination" | "qr" | "room" | "door"
export const kindLabels: Record<NodeKind, string> = {
  entrance: "Lối vào",
  corridor: "Hành lang",
  elevator: "Thang máy",
  stairs: "Cầu thang",
  destination: "Điểm đến",
  qr: "Mốc QR",
  room: "Phòng / khoa",
  door: "Cửa ra vào",
}
export type MapNode = {
  id: string
  name: string
  kind: NodeKind
  x: number
  y: number
  qr: string
  connector: string
  accessible: "unknown" | "yes" | "no"
}
export type MapEdge = {
  id: string
  from: string
  to: string
  accessible: "unknown" | "yes" | "no"
}
export type Graph = {
  nodes: MapNode[]
  edges: MapEdge[]
}
export type PlanImage = {
  url: string
  name: string
  width: number
  height: number
  size: number
  sample: boolean
}
export type FloorDocument = {
  graph: Graph
  past: Graph[]
  future: Graph[]
  image: PlanImage | null
  dirty: boolean
  saved: string
  status: "draft" | "validation" | "review" | "published"
  reviewed: boolean
  acknowledged: boolean
  aiPending: number
  versions: {
    name: string
    date: string
    status: string
  }[]
}
export const statusLabels = {
  draft: "Bản nháp",
  validation: "Kiểm tra",
  review: "Chờ duyệt",
  published: "Đã xuất bản",
}
export function floorArtwork(floor: number) {
  const upper = floor === 1
  const rooms = [
    {
      x: 60,
      y: 80,
      w: 200,
      h: 170,
      label: upper ? "KHOA NỘI" : "NHÀ THUỐC",
      sub: upper ? "201 · Khám tổng quát" : "G.01 · Nhận thuốc",
    },
    {
      x: 290,
      y: 80,
      w: 180,
      h: 170,
      label: upper ? "KHOA NHI" : "CHẨN ĐOÁN",
      sub: upper ? "202 · Phòng khám" : "G.02 · Hình ảnh",
    },
    {
      x: 530,
      y: 80,
      w: 180,
      h: 170,
      label: upper ? "KHOA MẮT" : "PHÒNG KHÁM",
      sub: upper ? "203 · Chuyên khoa" : "G.03 · Đa khoa",
    },
    {
      x: 740,
      y: 80,
      w: 200,
      h: 170,
      label: upper ? "THẦN KINH" : "TIẾP ĐÓN",
      sub: upper ? "204 · Điểm đến" : "G.04 · Đăng ký",
    },
    {
      x: 60,
      y: 390,
      w: 210,
      h: 180,
      label: upper ? "KHU CHỜ" : "SẢNH CHÍNH",
      sub: upper ? "Ghế nghỉ · Nước uống" : "Lối vào A · Thông tin",
    },
    {
      x: 300,
      y: 390,
      w: 170,
      h: 180,
      label: "XÉT NGHIỆM",
      sub: upper ? "205 · Lấy mẫu" : "G.05 · Lấy mẫu",
    },
    { x: 530, y: 390, w: 160, h: 180, label: "THANG MÁY", sub: "E1 · G ↔ L1" },
    { x: 720, y: 390, w: 100, h: 180, label: "CẦU THANG", sub: "S1 · G ↔ L1" },
    { x: 850, y: 390, w: 90, h: 180, label: "WC", sub: "G.06" },
  ]
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 660"><rect width="1000" height="660" fill="#f8fafc"/><rect x="40" y="60" width="920" height="530" rx="5" fill="white" stroke="#cbd5e1" stroke-width="4"/><path d="M45 320 H955 M500 65 V585" fill="none" stroke="#f0fdfa" stroke-width="50"/>${rooms.map((r, i) => `<rect x="${r.x}" y="${r.y}" width="${r.w}" height="${r.h}" rx="3" fill="${i === 3 ? "#ecfeff" : i === 6 ? "#eff6ff" : "#f1f5f9"}" stroke="#cbd5e1" stroke-width="2"/><path d="M${r.x + r.w / 2 - 16} ${r.y < 300 ? r.y + r.h : r.y} h32" stroke="white" stroke-width="6"/><path d="M${r.x + r.w / 2 - 16} ${r.y < 300 ? r.y + r.h : r.y} v${r.y < 300 ? -28 : 28} a28 28 0 0 ${r.y < 300 ? 1 : 0} 28 ${r.y < 300 ? 28 : -28}" fill="none" stroke="#cbd5e1"/><text x="${r.x + r.w / 2}" y="${r.y + r.h / 2 - 6}" text-anchor="middle" font-family="Inter,Arial,sans-serif" font-size="${r.w < 120 ? 10 : 13}" font-weight="600" fill="#475569">${r.label}</text><text x="${r.x + r.w / 2}" y="${r.y + r.h / 2 + 17}" text-anchor="middle" font-family="Inter,Arial,sans-serif" font-size="10" fill="#64748b">${r.sub}</text>`).join("")}<text x="260" y="286" font-family="Inter,Arial,sans-serif" fill="#94a3b8" font-size="10" letter-spacing="2">HÀNH LANG A</text><text x="730" y="368" font-family="Inter,Arial,sans-serif" fill="#94a3b8" font-size="10" letter-spacing="2">HÀNH LANG B</text><path d="M500 590 V625" stroke="#cbd5e1" stroke-width="2"/><text x="500" y="646" text-anchor="middle" font-family="Inter,Arial,sans-serif" fill="#64748b" font-size="11">${
    upper ? "LẦU 1 · KHÁM CHUYÊN KHOA" : "TẦNG TRỆT · LỐI VÀO CHÍNH"
  }</text></svg>`
}
export function sampleImage(floor: number): PlanImage {
  const svg = floorArtwork(floor)
  return {
    url: `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`,
    name: `Toa-A_${floor ? "L1" : "G"}_minh-hoa.svg`,
    width: 1000,
    height: 660,
    size: new Blob([svg]).size,
    sample: true,
  }
}
export function seedDocument(floor: number, sample = true): FloorDocument {
  const base = { qr: "", connector: "", accessible: "unknown" as const }
  const nodes: MapNode[] = [
    {
      ...base,
      id: "n1",
      name: floor ? "Sảnh lầu 1" : "Cổng chính A",
      kind: floor ? "corridor" : "entrance",
      x: 500,
      y: 580,
      qr: floor ? "WM-L101" : "WM-G01",
    },
    {
      ...base,
      id: "n2",
      name: "Ngã tư hành lang",
      kind: "corridor",
      x: 500,
      y: 320,
    },
    {
      ...base,
      id: "n3",
      name: "Thang máy E1",
      kind: "elevator",
      x: 610,
      y: 320,
      connector: "E1",
      qr: floor ? "WM-L103" : "WM-G03",
    },
    {
      ...base,
      id: "n4",
      name: floor ? "Phòng 204 · Thần kinh" : "Quầy tiếp đón",
      kind: "destination",
      x: 840,
      y: 250,
    },
    {
      ...base,
      id: "n5",
      name: "Cầu thang S1",
      kind: "stairs",
      x: 770,
      y: 320,
      connector: "S1",
    },
    {
      ...base,
      id: "n6",
      name: "Hành lang trước phòng",
      kind: "corridor",
      x: 840,
      y: 320,
    },
  ]
  const pairs = [
    ["n1", "n2"],
    ["n2", "n3"],
    ["n3", "n5"],
    ["n5", "n6"],
    ["n6", "n4"],
  ]
  return {
    graph: sample
      ? {
          nodes,
          edges: pairs.map(([from, to], i) => ({
            id: `e${i + 1}`,
            from,
            to,
            accessible: "unknown",
          })),
        }
      : { nodes: [], edges: [] },
    past: [],
    future: [],
    image: sample ? sampleImage(floor) : null,
    dirty: false,
    saved: "",
    status: "draft",
    reviewed: false,
    acknowledged: false,
    aiPending: 0,
    versions: [
      {
        name: "v0.1 · Sơ đồ minh họa",
        date: "Phiên làm việc hiện tại",
        status: "Bản nháp",
      },
    ],
  }
}
export function routeFor(graph: Graph, start?: string, end?: string) {
  const from =
    start ||
    graph.nodes.find((n) => n.kind === "entrance")?.id ||
    graph.nodes[0]?.id
  const to = end || graph.nodes.find((n) => n.kind === "destination")?.id
  if (!from || !to) return []
  const queue: string[][] = [[from]]
  const visited = new Set<string>()
  while (queue.length) {
    const path = queue.shift()!
    const current = path[path.length - 1]
    if (current === to) return path
    if (visited.has(current)) continue
    visited.add(current)
    graph.edges
      .filter((e) => e.from === current)
      .forEach((e) => queue.push([...path, e.to]))
  }
  return []
}
export function validateMap(doc: FloorDocument, other?: FloorDocument) {
  const { nodes, edges } = doc.graph
  const visited = new Set<string>()
  const walk = (id: string) => {
    if (visited.has(id)) return
    visited.add(id)
    edges
      .filter((e) => e.from === id || e.to === id)
      .forEach((e) => walk(e.from === id ? e.to : e.from))
  }
  if (nodes[0]) walk(nodes[0].id)
  return [
    {
      name: "Mặt bằng và mạng lưới",
      pass: Boolean(doc.image && nodes.length >= 2),
      detail: "Cần ảnh mặt bằng và ít nhất hai nút.",
      blocking: true,
    },
    {
      name: "Tính liên thông của đồ thị",
      pass: nodes.length > 0 && visited.size === nodes.length,
      detail: `${nodes.length - visited.size} nút rời rạc; kiểm tra cạnh nối các điểm.`,
      blocking: true,
    },
    {
      name: "Tuyến có hướng đến đích",
      pass: routeFor(doc.graph).length > 1,
      detail: "Cần một tuyến có hướng từ điểm đầu tới điểm đến.",
      blocking: true,
    },
    {
      name: "Mốc xác nhận QR",
      pass: nodes.some((n) => n.qr.trim()),
      detail: "Chưa có mã QR liên kết với bất kỳ nút nào.",
      blocking: true,
    },
    {
      name: "Gợi ý AI đã được xử lý",
      pass: doc.aiPending === 0,
      detail: `${doc.aiPending} gợi ý AI chưa được chấp nhận hoặc từ chối.`,
      blocking: true,
    },
    {
      name: "Kết nối liên tầng",
      pass:
        nodes.some((n) => n.connector) &&
        nodes
          .filter((n) => n.connector)
          .every((n) =>
            other?.graph.nodes.some(
              (o) => o.connector === n.connector && o.kind === n.kind,
            ),
          ),
      detail: "Thang máy / cầu thang cần cùng mã kết nối ở tầng còn lại.",
      blocking: true,
    },
    {
      name: "Khả năng tiếp cận",
      pass:
        nodes.length > 0 &&
        nodes.every((n) => n.accessible !== "unknown") &&
        edges.every((e) => e.accessible !== "unknown"),
      detail:
        "Chưa xác minh chiều rộng cửa, độ dốc và điều kiện thang máy. Không quảng bá tuyến xe lăn.",
      blocking: false,
    },
  ]
}
