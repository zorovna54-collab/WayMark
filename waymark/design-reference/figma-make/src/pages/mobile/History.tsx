import { useNavigate } from 'react-router';
import { ArrowLeft, Clock, MapPin, Navigation as NavIcon, Calendar } from 'lucide-react';

export function History() {
  const navigate = useNavigate();

  const historyData = [
    {
      date: 'Hôm nay',
      items: [
        { dest: 'Khoa Ngoại Thần Kinh', from: 'Cổng chính Khu A', time: '14:30', id: 'WM-B04' },
        { dest: 'Nhà vệ sinh (Nam)', from: 'Khu tiếp đón', time: '09:15', id: 'WM-A03' }
      ]
    },
    {
      date: 'Hôm qua',
      items: [
        { dest: 'Quầy thuốc Số 3', from: 'Cổng phụ Khu C', time: '16:45', id: 'WM-C02' },
        { dest: 'Phòng Cấp cứu', from: 'Bãi đỗ xe', time: '08:20', id: 'WM-E01' }
      ]
    }
  ];

  return (
    <div className="flex flex-col h-full bg-slate-50">
      {/* Header */}
      <div className="px-6 py-4 pt-12 bg-white border-b border-slate-200 sticky top-0 z-10 flex items-center gap-4">
        <button onClick={() => navigate(-1)} className="p-2 -ml-2 text-primary hover:bg-slate-100 rounded-full transition-colors">
          <ArrowLeft size={24} />
        </button>
        <h1 className="text-xl font-bold text-primary">Lịch sử di chuyển</h1>
      </div>

      {/* Content */}
      <div className="flex-1 p-6 overflow-y-auto pb-24">
        {historyData.map((group, index) => (
          <div key={index} className="mb-8">
            <div className="flex items-center gap-2 mb-4">
              <Calendar size={16} className="text-slate-400" />
              <h2 className="text-sm font-bold text-slate-500 uppercase tracking-wider">{group.date}</h2>
            </div>
            
            <div className="flex flex-col gap-4">
              {group.items.map((item, itemIdx) => (
                <div key={itemIdx} className="bg-white p-4 rounded-2xl shadow-sm border border-slate-200 flex flex-col gap-3 relative overflow-hidden">
                  
                  <div className="flex justify-between items-start">
                    <div className="flex-1">
                      <div className="flex items-center gap-2 mb-1">
                        <Clock size={14} className="text-accent" />
                        <span className="text-xs font-semibold text-accent">{item.time}</span>
                      </div>
                      <h3 className="text-base font-bold text-primary">{item.dest}</h3>
                    </div>
                    <button 
                      onClick={() => navigate('/preview')}
                      className="w-10 h-10 rounded-full bg-accent/10 flex items-center justify-center text-accent hover:bg-accent hover:text-white transition-colors shrink-0"
                    >
                      <NavIcon size={18} />
                    </button>
                  </div>

                  <div className="flex items-center gap-2 mt-1">
                    <div className="w-1.5 h-1.5 rounded-full bg-slate-300"></div>
                    <span className="text-xs font-medium text-slate-500">Từ: {item.from}</span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        ))}

        {/* Clear History Button */}
        <div className="mt-8 text-center">
          <button className="text-xs font-semibold text-slate-400 hover:text-red-500 transition-colors underline">
            Xóa toàn bộ lịch sử
          </button>
        </div>
      </div>
    </div>
  );
}
