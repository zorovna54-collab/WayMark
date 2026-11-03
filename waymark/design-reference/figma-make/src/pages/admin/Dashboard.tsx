import { Users, MapPin, Navigation, QrCode } from 'lucide-react';

export function AdminDashboard() {
  return (
    <div className="p-8">
      <h2 className="text-2xl font-bold text-primary mb-6">Tổng quan hệ thống</h2>
      
      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
        <StatCard title="Tổng WayMarks" value="245" icon={<MapPin />} trend="+12 trong tháng" />
        <StatCard title="Lượt quét QR (30 ngày)" value="12,450" icon={<QrCode />} trend="+15%" />
        <StatCard title="Điều hướng thành công" value="11,920" icon={<Navigation />} trend="95% tỷ lệ" />
        <StatCard title="Người dùng active" value="3,200" icon={<Users />} trend="+5% trong tuần" />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 bg-white rounded-2xl p-6 shadow-sm border border-slate-200">
          <h3 className="text-lg font-bold text-primary mb-4">Lưu lượng quét theo khu vực</h3>
          <div className="h-64 flex items-end gap-4">
            {/* Fake chart */}
            {[40, 70, 45, 90, 60, 30, 80].map((h, i) => (
              <div key={i} className="flex-1 bg-accent/20 rounded-t-lg relative group hover:bg-accent/30 transition-colors" style={{ height: `${h}%` }}>
                <div className="absolute bottom-full mb-2 left-1/2 -translate-x-1/2 bg-slate-800 text-white text-xs py-1 px-2 rounded opacity-0 group-hover:opacity-100 transition-opacity">
                  {h * 12}
                </div>
              </div>
            ))}
          </div>
          <div className="flex justify-between mt-4 text-xs font-semibold text-slate-400">
            <span>Khu A</span>
            <span>Khu B</span>
            <span>Khu C</span>
            <span>Sảnh chính</span>
            <span>Tầng 2</span>
            <span>Tầng 3</span>
            <span>Tầng 4</span>
          </div>
        </div>

        <div className="bg-white rounded-2xl p-6 shadow-sm border border-slate-200">
          <h3 className="text-lg font-bold text-primary mb-4">Hoạt động gần đây</h3>
          <div className="flex flex-col gap-4">
            {[
              { type: 'qr', msg: 'QR #WM-A01 được quét', time: '2 phút trước' },
              { type: 'map', msg: 'Admin cập nhật route Khu B', time: '1 giờ trước' },
              { type: 'node', msg: 'Thêm mới WayMark Tầng 4', time: '3 giờ trước' },
              { type: 'qr', msg: 'QR #WM-C12 được quét', time: '5 giờ trước' },
            ].map((activity, i) => (
              <div key={i} className="flex gap-3">
                <div className={`w-2 h-2 mt-1.5 rounded-full ${activity.type === 'qr' ? 'bg-accent' : 'bg-primary'}`}></div>
                <div>
                  <p className="text-sm font-medium text-slate-700">{activity.msg}</p>
                  <p className="text-xs text-slate-400">{activity.time}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

function StatCard({ title, value, icon, trend }: { title: string, value: string, icon: React.ReactNode, trend: string }) {
  return (
    <div className="bg-white p-6 rounded-2xl shadow-sm border border-slate-200 flex flex-col gap-4">
      <div className="flex justify-between items-start">
        <div className="p-3 bg-slate-50 text-accent rounded-xl">
          {icon}
        </div>
        <span className="text-xs font-semibold text-emerald-500 bg-emerald-50 px-2 py-1 rounded-full">{trend}</span>
      </div>
      <div>
        <h4 className="text-slate-500 text-sm font-medium">{title}</h4>
        <p className="text-3xl font-bold text-primary mt-1">{value}</p>
      </div>
    </div>
  );
}
