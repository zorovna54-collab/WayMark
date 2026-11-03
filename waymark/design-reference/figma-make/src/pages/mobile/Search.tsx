import { useState } from "react"
import { useNavigate } from "react-router"
import { ArrowLeft, Search as SearchIcon, MapPin } from "lucide-react"

export function Search() {
  const navigate = useNavigate()
  const [query, setQuery] = useState("")

  const results = [
    {
      name: "Khoa Ngoại Thần Kinh",
      location: "Tầng 4, Khu B",
      distance: "120m",
    },
    { name: "Nhà vệ sinh (Nam)", location: "Tầng 1, Khu A", distance: "15m" },
    {
      name: "Quầy thuốc Số 3",
      location: "Tầng 1, Sảnh chính",
      distance: "45m",
    },
    { name: "Phòng Cấp cứu", location: "Tầng trệt, Khu C", distance: "85m" },
  ]

  return (
    <div className="flex flex-col h-full bg-background">
      <div className="px-4 py-4 flex gap-3 items-center bg-card border-b border-border z-10 pt-12">
        <button onClick={() => navigate(-1)} className="p-2 -ml-2 text-primary">
          <ArrowLeft size={24} />
        </button>
        <div className="flex-1 bg-secondary rounded-full flex items-center px-4 h-12">
          <SearchIcon size={20} className="text-slate-400" />
          <input
            type="text"
            autoFocus
            placeholder="Tìm địa điểm, phòng..."
            className="bg-transparent border-none outline-none flex-1 ml-3 text-sm font-medium text-primary placeholder:text-slate-400"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>
      </div>

      <div className="flex-1 p-4 overflow-y-auto">
        <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider mb-4 px-2">
          Gợi ý
        </h3>
        <div className="flex flex-col gap-2">
          {results
            .filter((item) =>
              `${item.name} ${item.location}`
                .toLocaleLowerCase("vi")
                .includes(query.toLocaleLowerCase("vi")),
            )
            .map((item, i) => (
              <button
                key={i}
                onClick={() =>
                  navigate(`/preview?to=${encodeURIComponent(item.name)}`)
                }
                className="flex items-center gap-4 p-4 bg-card rounded-2xl border border-border hover:border-accent transition-colors text-left"
              >
                <div className="w-12 h-12 rounded-xl bg-secondary flex items-center justify-center text-primary shrink-0">
                  <MapPin size={20} />
                </div>
                <div className="flex-1">
                  <h4 className="text-sm font-bold text-primary">
                    {item.name}
                  </h4>
                  <p className="text-xs text-muted-foreground mt-1">
                    {item.location}
                  </p>
                </div>
                <span className="text-xs font-semibold text-accent bg-accent/10 px-2 py-1 rounded-md">
                  {item.distance}
                </span>
              </button>
            ))}
        </div>
      </div>
    </div>
  )
}
