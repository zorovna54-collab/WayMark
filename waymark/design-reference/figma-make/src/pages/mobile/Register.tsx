import { useState } from 'react';
import { useNavigate, Link } from 'react-router';
import { Mail, Lock, User, MapPin } from 'lucide-react';

export function Register() {
  const navigate = useNavigate();
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');

  const handleRegister = (e: React.FormEvent) => {
    e.preventDefault();
    // Simulate register
    navigate('/');
  };

  return (
    <div className="flex flex-col h-full bg-background px-6 pt-12 pb-8 overflow-y-auto">
      <div className="flex-1 flex flex-col justify-center">
        {/* Header */}
        <div className="flex flex-col items-center mb-8">
          <div className="w-12 h-12 bg-primary/10 rounded-2xl flex items-center justify-center mb-4">
            <MapPin size={24} className="text-primary" />
          </div>
          <h1 className="text-2xl font-bold text-primary tracking-tight">Tạo tài khoản mới</h1>
          <p className="text-sm text-slate-500 mt-2 text-center">Gia nhập cộng đồng WayMark để trải nghiệm điều hướng tốt nhất.</p>
        </div>

        {/* Form */}
        <form onSubmit={handleRegister} className="flex flex-col gap-4">
          <div>
            <label className="text-xs font-semibold text-slate-500 mb-1.5 block ml-1">Họ và tên</label>
            <div className="relative">
              <User size={18} className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-400" />
              <input 
                type="text" 
                placeholder="Ví dụ: Nguyễn Văn A"
                className="w-full bg-white border border-slate-200 rounded-2xl py-3.5 pl-11 pr-4 text-sm font-medium text-primary placeholder:text-slate-400 focus:outline-none focus:border-accent focus:ring-1 focus:ring-accent transition-all shadow-sm"
                value={name}
                onChange={(e) => setName(e.target.value)}
                required
              />
            </div>
          </div>

          <div>
            <label className="text-xs font-semibold text-slate-500 mb-1.5 block ml-1">Email</label>
            <div className="relative">
              <Mail size={18} className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-400" />
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
            <label className="text-xs font-semibold text-slate-500 mb-1.5 block ml-1">Mật khẩu</label>
            <div className="relative">
              <Lock size={18} className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-400" />
              <input 
                type="password" 
                placeholder="Tạo mật khẩu (ít nhất 6 ký tự)"
                className="w-full bg-white border border-slate-200 rounded-2xl py-3.5 pl-11 pr-4 text-sm font-medium text-primary placeholder:text-slate-400 focus:outline-none focus:border-accent focus:ring-1 focus:ring-accent transition-all shadow-sm"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                minLength={6}
              />
            </div>
          </div>

          <button 
            type="submit"
            className="w-full bg-primary text-white font-bold py-4 rounded-2xl mt-4 shadow-lg shadow-primary/20 hover:bg-slate-800 transition-colors"
          >
            Đăng ký
          </button>
        </form>

        <div className="mt-8 text-center">
          <p className="text-sm text-slate-500 font-medium">
            Đã có tài khoản?{' '}
            <Link to="/login" className="text-accent font-bold hover:underline">Đăng nhập</Link>
          </p>
        </div>
      </div>
    </div>
  );
}
