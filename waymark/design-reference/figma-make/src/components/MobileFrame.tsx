import { Outlet, useLocation, useNavigate } from "react-router"
import { Home, ScanLine, History, Settings } from "lucide-react"

export function MobileFrame() {
  const location = useLocation()
  const navigate = useNavigate()

  const isNavigation = location.pathname.includes("/navigation")
  const isScanner = location.pathname.includes("/scanner")
  const isPreview = location.pathname.includes("/preview")
  const isAuth =
    location.pathname.includes("/login") ||
    location.pathname.includes("/register")

  return (
    <div className="mobile-workspace min-h-screen bg-slate-900 flex items-center justify-center p-4">
      {/* Device Mockup */}
      <div className="mobile-device relative w-full max-w-[400px] h-[844px] bg-background rounded-[3rem] shadow-2xl overflow-hidden border-[8px] border-slate-800 flex flex-col">
        {/* Status Bar */}
        <div className="h-9 w-full flex justify-between items-center px-6 pt-2 text-xs font-semibold shrink-0 z-50 text-primary">
          <span>9:41</span>
          <div className="flex gap-2 items-center">
            <span
              className="w-4 h-4 bg-current rounded-full"
              style={{ clipPath: "polygon(0 100%, 100% 100%, 100% 0)" }}
            ></span>
            <span className="w-5 h-3 border border-current rounded-sm"></span>
          </div>
        </div>

        {/* Dynamic Content */}
        <div
          className={`flex-1 min-h-0 overflow-y-auto relative no-scrollbar ${
            !isAuth && !isNavigation && !isScanner && !isPreview ? "pb-20" : ""
          }`}
        >
          <Outlet />
        </div>

        {/* Bottom Navigation (Hidden on Auth, Scanner and Navigation views) */}
        {!isNavigation && !isScanner && !isAuth && !isPreview && (
          <div className="absolute bottom-0 left-0 right-0 h-20 bg-card border-t border-border flex justify-around items-center px-4 pb-2 z-40 rounded-b-[2.5rem]">
            <NavItem
              icon={<Home size={24} />}
              label="Trang chủ"
              active={location.pathname === "/"}
              onClick={() => navigate("/")}
            />
            <NavItem
              icon={<ScanLine size={24} />}
              label="Quét QR"
              active={location.pathname === "/scanner"}
              onClick={() => navigate("/scanner")}
            />
            <NavItem
              icon={<History size={24} />}
              label="Lịch sử"
              active={location.pathname === "/history"}
              onClick={() => navigate("/history")}
            />
            <NavItem
              icon={<Settings size={24} />}
              label="Cài đặt"
              active={location.pathname === "/settings"}
              onClick={() => navigate("/admin")}
            />
          </div>
        )}
      </div>

      {/* Hint for demo */}
      <div className="preview-switcher absolute top-4 right-4 bg-white/10 text-white p-4 rounded-xl text-sm backdrop-blur">
        <p className="font-semibold mb-2">Chế độ Xem</p>
        <button
          onClick={() => navigate("/admin")}
          className="block text-cyan-400 hover:underline"
        >
          Chuyển sang Admin
        </button>
      </div>
    </div>
  )
}

function NavItem({
  icon,
  label,
  active,
  onClick,
}: {
  icon: React.ReactNode
  label: string
  active: boolean
  onClick: () => void
}) {
  return (
    <button
      onClick={onClick}
      className={`flex flex-col items-center gap-1 p-2 rounded-xl transition-colors ${
        active ? "text-accent" : "text-slate-400 hover:text-slate-600"
      }`}
    >
      {icon}
      <span className="text-[10px] font-medium">{label}</span>
    </button>
  )
}
