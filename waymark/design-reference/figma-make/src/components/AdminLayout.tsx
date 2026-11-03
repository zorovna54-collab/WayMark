import { useState, useEffect } from 'react';
import { Outlet, NavLink, useLocation } from 'react-router';
import { LayoutDashboard, Map as MapIcon, QrCode, Settings, LogOut, Smartphone, Menu, X } from 'lucide-react';

export function AdminLayout() {
  const [isSidebarOpen, setIsSidebarOpen] = useState(false);
  const location = useLocation();

  // Tự động thu lại thanh bên (sidebar) khi chuyển trang trên thiết bị di động
  useEffect(() => {
    setIsSidebarOpen(false);
  }, [location.pathname]);

  return (
    <div className="min-h-screen bg-slate-100 flex relative overflow-hidden">
      {/* Mobile Header */}
      <div className="md:hidden absolute top-0 left-0 right-0 h-16 bg-primary text-white flex items-center px-4 z-20 shadow-md">
        <button onClick={() => setIsSidebarOpen(true)} className="p-2 -ml-2 text-white/80 hover:text-white">
          <Menu size={24} />
        </button>
        <h1 className="text-lg font-bold ml-2">WayMark Admin</h1>
      </div>

      {/* Overlay for mobile */}
      {isSidebarOpen && (
        <div 
          className="fixed inset-0 bg-black/50 z-30 md:hidden backdrop-blur-sm"
          onClick={() => setIsSidebarOpen(false)}
        />
      )}

      {/* Sidebar */}
      <aside className={`
        fixed md:static inset-y-0 left-0 z-40
        ${isSidebarOpen ? 'translate-x-0' : '-translate-x-full md:translate-x-0'}
        w-64 bg-primary text-primary-foreground flex flex-col transition-transform duration-300 ease-in-out shadow-2xl md:shadow-none
      `}>
        <div className="h-16 flex items-center justify-between px-6 border-b border-white/10 shrink-0">
          <h1 className="text-xl font-bold tracking-tight text-white flex items-center gap-2">
            <MapIcon className="text-accent" /> WayMark
          </h1>
          <button className="md:hidden text-slate-400 hover:text-white" onClick={() => setIsSidebarOpen(false)}>
            <X size={24} />
          </button>
        </div>
        
        <nav className="flex-1 p-4 flex flex-col gap-2 overflow-y-auto">
          <NavItem to="/admin" icon={<LayoutDashboard size={20} />} label="Tổng quan" end />
          <NavItem to="/admin/map-builder" icon={<MapIcon size={20} />} label="Bản đồ & Routes" />
          <NavItem to="/admin/qrs" icon={<QrCode size={20} />} label="Quản lý QR" />
          <NavItem to="/admin/settings" icon={<Settings size={20} />} label="Cài đặt hệ thống" />
        </nav>

        <div className="p-4 border-t border-white/10 shrink-0">
          <NavLink to="/" className="flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-medium text-slate-400 hover:bg-white/5 hover:text-white transition-colors mb-2">
            <Smartphone size={20} />
            <span>Xem App Mobile</span>
          </NavLink>
          <button className="w-full flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-medium text-slate-400 hover:bg-white/5 hover:text-red-400 transition-colors">
            <LogOut size={20} />
            <span>Đăng xuất</span>
          </button>
        </div>
      </aside>

      {/* Main Content */}
      <main className="flex-1 h-screen overflow-y-auto md:pt-0 pt-16 relative">
        <Outlet />
      </main>
    </div>
  );
}

function NavItem({ to, icon, label, end }: { to: string, icon: React.ReactNode, label: string, end?: boolean }) {
  return (
    <NavLink 
      to={to} 
      end={end}
      className={({ isActive }) => `flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-medium transition-colors ${isActive ? 'bg-accent text-white' : 'text-slate-400 hover:bg-white/5 hover:text-white'}`}
    >
      {icon}
      {label}
    </NavLink>
  );
}
