import { useId, useRef, useState } from "react"
import type { PointerEvent as ReactPointerEvent } from "react"
import { ImageOff } from "lucide-react"
import type { Graph, MapNode, PlanImage } from "./model"
import { kindLabels, routeFor } from "./model"

type Point = {
  x: number
  y: number
}
type MovingNode = Point & {
  id: string
}
type Props = {
  image: PlanImage | null
  graph: Graph
  mode: string
  tool: string
  visible: boolean
  selected: string
  onSelect: (id: string) => void
  onAdd: (x: number, y: number) => void
  onMove: (id: string, x: number, y: number) => void
  zoom: number
  pan: Point
  onPan: (p: Point) => void
  start?: string
  end?: string
  annotation?: boolean
}
export default function MapCanvas({
  image,
  graph,
  mode,
  tool,
  visible,
  selected,
  onSelect,
  onAdd,
  onMove,
  zoom,
  pan,
  onPan,
  start,
  end,
  annotation,
}: Props) {
  const id = useId()
  const svg = useRef<SVGSVGElement>(null)
  const drag = useRef<{
    id: string
    x: number
    y: number
    moved: boolean
    panX: number
    panY: number
  } | null>(null)
  const [moving, setMoving] = useState<MovingNode | null>(null)
  const movingRef = useRef<MovingNode | null>(null)
  const route = routeFor(graph, start, end)
  function point(e: ReactPointerEvent) {
    const matrix = svg.current?.getScreenCTM()
    if (!matrix) return { x: 0, y: 0 }
    const p = new DOMPoint(e.clientX, e.clientY).matrixTransform(
      matrix.inverse(),
    )
    return {
      x: (p.x - pan.x - 500 * (1 - zoom)) / zoom,
      y: (p.y - pan.y - 330 * (1 - zoom)) / zoom,
    }
  }
  function down(e: ReactPointerEvent, node?: MapNode) {
    if (mode === "preview" || annotation) return
    const p = point(e)
    if (node && tool !== "pan") {
      e.stopPropagation()
      onSelect(node.id)
      if (tool !== "select") return
      drag.current = {
        id: node.id,
        ...p,
        moved: false,
        panX: pan.x,
        panY: pan.y,
      }
    } else if (tool === "pan") {
      drag.current = {
        id: "__pan",
        ...p,
        moved: false,
        panX: pan.x,
        panY: pan.y,
      }
    } else if (tool === "node" || tool === "qr") {
      onAdd(Math.max(15, Math.min(985, p.x)), Math.max(15, Math.min(645, p.y)))
      return
    } else return
    svg.current?.setPointerCapture(e.pointerId)
  }
  function move(e: ReactPointerEvent) {
    const d = drag.current
    if (!d) return
    const p = point(e)
    d.moved = true
    if (d.id === "__pan") {
      // Use screen-space deltas so the transform does not feed back into the gesture.
      const matrix = svg.current!.getScreenCTM()!
      const origin = new DOMPoint(e.clientX, e.clientY).matrixTransform(
        matrix.inverse(),
      )
      onPan({
        x: origin.x - 500 * (1 - zoom) - d.x * zoom,
        y: origin.y - 330 * (1 - zoom) - d.y * zoom,
      })
    } else {
      movingRef.current = {
        id: d.id,
        x: Math.max(15, Math.min(985, p.x)),
        y: Math.max(15, Math.min(645, p.y)),
      }
      setMoving(movingRef.current)
    }
  }
  function finish() {
    const lastPosition = movingRef.current
    if (lastPosition && drag.current?.moved)
      onMove(
        lastPosition.id,
        Math.round(lastPosition.x),
        Math.round(lastPosition.y),
      )
    drag.current = null
    movingRef.current = null
    setMoving(null)
  }
  const nodes = graph.nodes.map((n) =>
    moving?.id === n.id ? { ...n, x: moving.x, y: moving.y } : n,
  )
  return (
    <div className={`wm-map-canvas ${tool === "pan" ? "is-pan" : ""}`}>
      {!image ? (
        <div className="map-empty">
          <ImageOff size={40} />
          <strong>Chưa có mặt bằng cho tầng này</strong>
          <p>Tải ảnh PNG/JPG hoặc sử dụng sơ đồ mẫu để bắt đầu.</p>
        </div>
      ) : (
        <svg
          ref={svg}
          viewBox="0 0 1000 660"
          aria-label="Canvas chỉnh sửa bản đồ bệnh viện"
          onPointerDown={(e) => down(e)}
          onPointerMove={move}
          onPointerUp={finish}
          onPointerCancel={() => {
            drag.current = null
            movingRef.current = null
            setMoving(null)
          }}
        >
          <defs>
            <marker
              id={`${id}-edge`}
              viewBox="0 0 10 10"
              refX="9"
              refY="5"
              markerWidth="5"
              markerHeight="5"
              orient="auto"
            >
              <path d="M0 0 L10 5 L0 10Z" className="edge-arrow-fill" />
            </marker>
            <marker
              id={`${id}-route`}
              viewBox="0 0 10 10"
              refX="6"
              refY="5"
              markerWidth="4"
              markerHeight="4"
              orient="auto"
            >
              <path
                d="M2 1 L7 5 L2 9"
                fill="none"
                stroke="white"
                strokeWidth="2"
              />
            </marker>
          </defs>
          <g
            transform={`translate(${pan.x + 500 * (1 - zoom)} ${pan.y + 330 * (1 - zoom)}) scale(${zoom})`}
          >
            <image
              href={image.url}
              width="1000"
              height="660"
              preserveAspectRatio="xMidYMid meet"
            />
            {visible &&
              mode !== "preview" &&
              graph.edges.map((edge) => {
                const a = nodes.find((n) => n.id === edge.from),
                  b = nodes.find((n) => n.id === edge.to)
                if (!a || !b) return null
                return (
                  <g
                    key={edge.id}
                    className={`editable-edge access-${edge.accessible} ${
                      selected === edge.id ? "is-selected" : ""
                    }`}
                    role="button"
                    tabIndex={0}
                    aria-label={`Cạnh ${a.name} đến ${b.name}`}
                    onPointerDown={(e) => {
                      e.stopPropagation()
                      onSelect(edge.id)
                    }}
                    onKeyDown={(e) => e.key === "Enter" && onSelect(edge.id)}
                  >
                    <line
                      x1={a.x}
                      y1={a.y}
                      x2={b.x}
                      y2={b.y}
                      className="edge-hit"
                    />
                    <line
                      x1={a.x}
                      y1={a.y}
                      x2={b.x}
                      y2={b.y}
                      className={annotation ? "analysis-edge" : "graph-edge"}
                      markerEnd={`url(#${id}-edge)`}
                    />
                  </g>
                )
              })}
            {mode === "preview" && route.slice(1).map((n, i) => {
                const a = nodes.find((node) => node.id === route[i])!,
                  b = nodes.find((node) => node.id === n)!
                return (
                  <g key={`${a.id}-${b.id}`}>
                    <line
                      x1={a.x}
                      y1={a.y}
                      x2={b.x}
                      y2={b.y}
                      className="preview-route-halo"
                    />
                    <line
                      x1={a.x}
                      y1={a.y}
                      x2={b.x}
                      y2={b.y}
                      className="preview-route-line"
                    />
                    <line
                      x1={(a.x + b.x) / 2}
                      y1={(a.y + b.y) / 2}
                      x2={(a.x + b.x) / 2 + (b.x - a.x) * 0.04}
                      y2={(a.y + b.y) / 2 + (b.y - a.y) * 0.04}
                      stroke="white"
                      strokeWidth="2"
                      markerEnd={`url(#${id}-route)`}
                    />
                  </g>
                )
              })}
            {(visible || mode === "preview") &&
              nodes
                .filter(
                  (n) =>
                    mode !== "preview" ||
                    n.id === route[0] ||
                    n.id === route[route.length - 1],
                )
                .map((n) => (
                  <g
                    key={n.id}
                    className={`canvas-node kind-${n.kind} ${
                      selected === n.id ? "is-selected" : ""
                    } ${annotation ? "suggested-node" : ""}`}
                    transform={`translate(${n.x} ${n.y})`}
                    role="button"
                    tabIndex={mode === "preview" ? -1 : 0}
                    aria-label={`${kindLabels[n.kind]}: ${n.name}`}
                    onPointerDown={(e) => down(e, n)}
                    onKeyDown={(e) => e.key === "Enter" && onSelect(n.id)}
                  >
                    <circle r="17" className="node-halo" />
                    <circle r="10" className="node-body" />
                    <text y="4" className="node-symbol">
                      {n.kind === "qr" || n.qr
                        ? "▦"
                        : n.kind === "elevator"
                          ? "↕"
                          : n.kind === "stairs"
                            ? "↗"
                            : n.kind === "destination"
                              ? "B"
                              : n.kind === "entrance"
                                ? "A"
                                : "•"}
                    </text>
                    <text
                      y={n.kind === "stairs" ? 34 : -26}
                      className="canvas-node-label"
                    >
                      {n.name}
                    </text>
                  </g>
                ))}
          </g>
        </svg>
      )}
    </div>
  )
}
