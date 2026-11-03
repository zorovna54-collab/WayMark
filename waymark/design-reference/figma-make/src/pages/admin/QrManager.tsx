import { QrCode, Download, Filter, Search } from 'lucide-react';

export function QrManager() {
  return (
    <div className="p-8 h-full flex flex-col">
      <div className="flex justify-between items-center mb-6">
          <h2 className="text-2xl font-bold text-primary">Quản lý mã QR (WayMarks)</h2>
          <button className="bg-primary text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-slate-800 transition-colors">
          Tạo QR mới
        </button>
      </div>

      <div className="bg-white rounded-2xl shadow-sm border border-slate-200 flex-1 flex flex-col overflow-hidden">
        {/* Toolbar */}
        <div className="p-4 border-b border-slate-200 flex gap-4">
          <div className="flex-1 relative">
            <Search size={18} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
            <input 
              type="text" 
              placeholder="Tìm kiếm theo ID, Tên, Khu vực..." 
              className="w-full pl-10 pr-4 py-2 bg-slate-50 border border-slate-200 rounded-lg text-sm focus:outline-none focus:border-accent"
            />
          </div>
          <button className="px-4 py-2 border border-slate-200 rounded-lg text-sm font-medium text-slate-600 flex items-center gap-2 hover:bg-slate-50">
            <Filter size={16} /> Lọc
          </button>
          <button className="px-4 py-2 border border-slate-200 rounded-lg text-sm font-medium text-slate-600 flex items-center gap-2 hover:bg-slate-50">
            <Download size={16} /> Xuất PDF
          </button>
        </div>

        {/* Table */}
        <div className="flex-1 overflow-auto">
          <table className="w-full text-sm text-left">
            <thead className="text-xs text-slate-500 bg-slate-50 uppercase sticky top-0">
              <tr>
                <th className="px-6 py-4 font-semibold">WayMark ID</th>
                <th className="px-6 py-4 font-semibold">Tên hiển thị</th>
                <th className="px-6 py-4 font-semibold">Khu vực</th>
                <th className="px-6 py-4 font-semibold">Lượt quét</th>
                <th className="px-6 py-4 font-semibold">Trạng thái</th>
                <th className="px-6 py-4 font-semibold text-right">Thao tác</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {[
                { id: 'WM-A01', name: 'Cổng chính Khu A', area: 'Tầng 1, Khu A', scans: 1245, status: 'Hoạt động' },
                { id: 'WM-A02', name: 'Ngã ba hành lang', area: 'Tầng 1, Khu A', scans: 890, status: 'Hoạt động' },
                { id: 'WM-B01', name: 'Thang máy B', area: 'Tầng 2, Khu B', scans: 432, status: 'Bảo trì' },
                { id: 'WM-C12', name: 'Phòng chờ Cấp cứu', area: 'Tầng trệt, Khu C', scans: 2100, status: 'Hoạt động' },
              ].map((row, i) => (
                <tr key={i} className="hover:bg-slate-50 transition-colors">
                  <td className="px-6 py-4 font-medium text-primary flex items-center gap-2">
                    <QrCode size={16} className="text-slate-400" />
                    {row.id}
                  </td>
                  <td className="px-6 py-4 text-slate-700">{row.name}</td>
                  <td className="px-6 py-4 text-slate-500">{row.area}</td>
                  <td className="px-6 py-4 font-medium">{row.scans}</td>
                  <td className="px-6 py-4">
                    <span className={`px-2.5 py-1 rounded-full text-xs font-semibold ${row.status === 'Hoạt động' ? 'bg-emerald-100 text-emerald-700' : 'bg-amber-100 text-amber-700'}`}>
                      {row.status}
                    </span>
                  </td>
                  <td className="px-6 py-4 text-right">
                    <button className="text-accent hover:underline font-medium text-xs">In lại</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
