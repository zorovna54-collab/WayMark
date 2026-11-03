import { Save } from 'lucide-react';

export function Settings() {
  return (
    <div className="p-8 h-full overflow-y-auto">
      <div className="max-w-3xl">
        <h2 className="text-2xl font-bold text-primary mb-6">Cài đặt hệ thống</h2>
        
        <div className="bg-white rounded-2xl shadow-sm border border-slate-200 overflow-hidden">
          <div className="p-6 border-b border-slate-100">
            <h3 className="text-lg font-bold text-primary mb-1">Cấu hình chung</h3>
            <p className="text-sm text-slate-500">Quản lý các thông số cơ bản của ứng dụng WayMark.</p>
          </div>
          
          <div className="p-6 flex flex-col gap-6">
            <div>
              <label className="text-sm font-semibold text-slate-700 block mb-2">Tên tổ chức / Địa điểm</label>
              <input type="text" defaultValue="Bệnh viện Đa khoa Quốc tế" className="w-full bg-slate-50 border border-slate-200 rounded-lg px-4 py-2.5 text-sm focus:outline-none focus:border-accent" />
            </div>
            
            <div className="grid grid-cols-2 gap-6">
              <div>
                <label className="text-sm font-semibold text-slate-700 block mb-2">Đơn vị đo lường</label>
                <select className="w-full bg-slate-50 border border-slate-200 rounded-lg px-4 py-2.5 text-sm focus:outline-none focus:border-accent">
                  <option>Mét (m)</option>
                  <option>Feet (ft)</option>
                </select>
              </div>
              <div>
                <label className="text-sm font-semibold text-slate-700 block mb-2">Ngôn ngữ mặc định</label>
                <select className="w-full bg-slate-50 border border-slate-200 rounded-lg px-4 py-2.5 text-sm focus:outline-none focus:border-accent">
                  <option>Tiếng Việt</option>
                  <option>English</option>
                </select>
              </div>
            </div>

            <div>
              <label className="text-sm font-semibold text-slate-700 block mb-2">Tự động xóa lịch sử điều hướng</label>
              <select className="w-full bg-slate-50 border border-slate-200 rounded-lg px-4 py-2.5 text-sm focus:outline-none focus:border-accent">
                <option>Sau 30 ngày</option>
                <option>Sau 60 ngày</option>
                <option>Không bao giờ</option>
              </select>
            </div>
          </div>
        </div>

        <div className="bg-white rounded-2xl shadow-sm border border-slate-200 overflow-hidden mt-6">
          <div className="p-6 border-b border-slate-100 flex justify-between items-center">
            <div>
              <h3 className="text-lg font-bold text-primary mb-1">Cấu hình điều hướng (Routing Engine)</h3>
              <p className="text-sm text-slate-500">Thông số thuật toán tìm đường.</p>
            </div>
          </div>
          
          <div className="p-6 flex flex-col gap-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="font-semibold text-slate-700 text-sm">Ưu tiên tuyến đường có thang máy</p>
                <p className="text-xs text-slate-500 mt-1">Dành cho người dùng xe lăn hoặc hạn chế vận động.</p>
              </div>
              <div className="w-12 h-6 bg-accent rounded-full relative cursor-pointer">
                <div className="w-4 h-4 bg-white rounded-full absolute top-1 left-7"></div>
              </div>
            </div>
            <div className="flex items-center justify-between border-t border-slate-100 pt-6">
              <div>
                <p className="font-semibold text-slate-700 text-sm">Hiển thị đường đi AR</p>
                <p className="text-xs text-slate-500 mt-1">Cho phép người dùng bật chế độ Camera.</p>
              </div>
              <div className="w-12 h-6 bg-accent rounded-full relative cursor-pointer">
                <div className="w-4 h-4 bg-white rounded-full absolute top-1 left-7"></div>
              </div>
            </div>
          </div>
        </div>

        <div className="mt-8 flex justify-end">
          <button className="bg-primary text-white px-6 py-2.5 rounded-lg text-sm font-medium hover:bg-slate-800 transition-colors flex items-center gap-2">
            <Save size={18} /> Lưu cấu hình
          </button>
        </div>
      </div>
    </div>
  );
}
