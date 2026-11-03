import { useState } from "react"
import { useNavigate, Link } from "react-router"
import { Mail, Lock, MapPin } from "lucide-react"

export function Login() {
  const navigate = useNavigate()
  const [email, setEmail] = useState("")
  const [password, setPassword] = useState("")

  const handleLogin = (e: React.FormEvent) => {
    e.preventDefault()
    // Simulate login
    navigate("/")
  }

  return (
    <div className="flex flex-col h-full bg-background px-6 pt-12 pb-8">
      <div className="flex-1 flex flex-col justify-center">
        {/* Logo/Header */}
        <div className="flex flex-col items-center mb-10">
          <div className="w-16 h-16 bg-primary rounded-2xl flex items-center justify-center mb-4 shadow-lg shadow-primary/20">
            <MapPin size={32} className="text-accent" />
          </div>
          <h1 className="text-3xl font-bold text-primary tracking-tight">
            WayMark
          </h1>
          <p className="text-sm text-slate-500 mt-2 text-center">
            Đăng nhập để lưu lịch sử di chuyển và cá nhân hóa trải nghiệm.
          </p>
        </div>

        {/* Form */}
        <form onSubmit={handleLogin} className="flex flex-col gap-4">
          <div>
            <label className="text-xs font-semibold text-slate-500 mb-1.5 block ml-1">
              Email
            </label>
            <div className="relative">
              <Mail
                size={18}
                className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-400"
              />
              <input
                type="email"
                placeholder="Nhập email của bạn"
                className="w-full bg-white border border-slate-200 rounded-2xl py-3.5 pl-11 pr-4 text-sm font-medium text-primary placeholder:text-slate-400 focus:outline-none focus:border-accent focus:ring-1 focus:ring-accent transition-all shadow-sm"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
              />
            </div>
          </div>

          <div>
            <label className="text-xs font-semibold text-slate-500 mb-1.5 block ml-1">
              Mật khẩu
            </label>
            <div className="relative">
              <Lock
                size={18}
                className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-400"
              />
              <input
                type="password"
                placeholder="Nhập mật khẩu"
                className="w-full bg-white border border-slate-200 rounded-2xl py-3.5 pl-11 pr-4 text-sm font-medium text-primary placeholder:text-slate-400 focus:outline-none focus:border-accent focus:ring-1 focus:ring-accent transition-all shadow-sm"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
              />
            </div>
            <div className="flex justify-end mt-2">
              <button
                type="button"
                className="text-xs font-semibold text-accent hover:underline"
              >
                Quên mật khẩu?
              </button>
            </div>
          </div>

          <button
            type="submit"
            className="w-full bg-primary text-white font-bold py-4 rounded-2xl mt-4 shadow-lg shadow-primary/20 hover:bg-slate-800 transition-colors"
          >
            Đăng nhập
          </button>
        </form>

        <div className="mt-8 text-center">
          <p className="text-sm text-slate-500 font-medium">
            Chưa có tài khoản?{" "}
            <Link
              to="/register"
              className="text-accent font-bold hover:underline"
            >
              Đăng ký ngay
            </Link>
          </p>
        </div>
      </div>

      <div className="text-center">
        <button
          onClick={() => navigate("/")}
          className="text-xs font-semibold text-slate-400 underline hover:text-slate-600"
        >
          Bỏ qua, tiếp tục với tư cách khách
        </button>
      </div>
    </div>
  )
}
