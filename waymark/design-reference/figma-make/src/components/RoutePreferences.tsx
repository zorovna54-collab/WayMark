import { Accessibility, Check, ChevronDown, ShieldCheck } from "lucide-react"
import { useState } from "react"
import { Button } from "./WaymarkUI"
export const preferences = [
  "Tuyến thông thường",
  "Phù hợp xe lăn",
  "Tránh cầu thang",
  "Ưu tiên thang máy",
  "Ít phải đi bộ",
]
export default function RoutePreferences({
  value,
  onChange,
}: {
  value: string
  onChange: (v: string) => void
}) {
  const [open, setOpen] = useState(false)
  return (
    <div>
      <Button
        className="preference-trigger"
        onClick={() => setOpen(!open)}
        aria-expanded={open}
      >
        <Accessibility size={17} />
        <span>{value}</span>
        <ChevronDown size={15} />
      </Button>
      {open && (
        <div className="preference-options">
          {preferences.map((p) => (
            <Button
              key={p}
              onClick={() => {
                onChange(p)
                setOpen(false)
              }}
              className={value === p ? "selected" : ""}
            >
              {p}
              {value === p && <Check size={16} />}
            </Button>
          ))}
        </div>
      )}
      {value !== preferences[0] && (
        <div className="access-note">
          <ShieldCheck size={15} />
          <span>
            {value === "Phù hợp xe lăn"
              ? "Chưa xác minh chiều rộng cửa và thang máy. Chưa tìm được tuyến xe lăn đã kiểm chứng."
              : "Tuyến minh họa dùng thang máy E1, không qua cầu thang. Điều kiện tiếp cận chưa xác minh."}
          </span>
        </div>
      )}
    </div>
  )
}
