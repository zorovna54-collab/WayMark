import { Search, MapPin, Navigation as NavIcon, QrCode } from 'lucide-react';
import { useNavigate } from 'react-router';

export function Home() {
  const navigate = useNavigate();

  return (
    <div className="px-6 pt-2 pb-8 flex flex-col gap-6">
      <div className="flex justify-between items-center mt-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-primary">Xin chào,</h1>
          <p className="text-muted-foreground text-sm mt-1">Bạn muốn đi đâu hôm nay?</p>
        </div>
        <div 
          onClick={() => navigate('/login')}
          className="w-12 h-12 rounded-full bg-slate-200 overflow-hidden cursor-pointer hover:ring-2 hover:ring-accent transition-all"
          title="Đăng nhập / Đăng ký"
        >
          <img src="https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=100&h=100&fit=crop&auto=format" alt="Profile" className="w-full h-full object-cover" />
        </div>
      </div>

      <button 
        onClick={() => navigate('/search')}
        className="w-full bg-card rounded-2xl p-4 flex items-center gap-3 text-slate-400 shadow-sm border border-border"
      >
        <Search size={20} />
        <span className="text-sm">Tìm kiếm địa điểm, phòng ban...</span>
      </button>

      {/* Main Action - Scan QR */}
        <div className="bg-primary text-primary-foreground rounded-[2rem] p-6 relative overflow-hidden shadow-lg">
          <div className="absolute -right-10 -top-10 w-40 h-40 bg-white/10 rounded-full blur-2xl"></div>
          <div className="relative z-10">
            <div className="w-12 h-12 bg-white/20 rounded-xl flex items-center justify-center mb-4 backdrop-blur-sm">
              <QrCode size={24} className="text-white" />
            </div>
            <h2 className="text-xl font-bold mb-2">Đang lạc đường?</h2>
            <p className="text-sm text-primary-foreground/80 mb-6 max-w-[200px]">
              Quét mã QR gần nhất để xác định vị trí hiện tại của bạn.
            </p>
            <button 
              onClick={() => navigate('/scanner')}
              className="bg-accent text-accent-foreground px-6 py-3 rounded-full text-sm font-semibold w-full flex justify-center items-center gap-2"
            >
              Quét mã WayMark
            </button>
          </div>
        </div>

      {/* Recent Destinations */}
      <div>
        <h3 className="text-sm font-semibold text-slate-900 mb-4">Gần đây</h3>
        <div className="flex flex-col gap-3">
          {[
            { name: 'Phòng khám Nội', location: 'Tầng 2, Khu A' },
            { name: 'Nhà thuốc trung tâm', location: 'Tầng 1, Sảnh chính' },
            { name: 'Khoa Nhi', location: 'Tầng 3, Khu B' }
          ].map((item, i) => (
            <div key={i} className="bg-card p-4 rounded-2xl flex items-center gap-4 border border-border">
              <div className="w-10 h-10 rounded-full bg-secondary flex items-center justify-center text-primary shrink-0">
                <MapPin size={18} />
              </div>
              <div className="flex-1">
                <h4 className="text-sm font-semibold text-primary">{item.name}</h4>
                <p className="text-xs text-muted-foreground">{item.location}</p>
              </div>
              <button 
                onClick={() => navigate('/preview')}
                className="w-8 h-8 rounded-full bg-slate-100 flex items-center justify-center text-accent"
              >
                <NavIcon size={16} />
              </button>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
