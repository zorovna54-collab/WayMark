import { createBrowserRouter } from 'react-router';
import { MobileFrame } from './components/MobileFrame';
import { Home } from './pages/mobile/Home';
import { Scanner } from './pages/mobile/Scanner';
import { Search } from './pages/mobile/Search';
import { RoutePreview } from './pages/mobile/RoutePreview';
import { Navigation } from './pages/mobile/Navigation';
import { History } from './pages/mobile/History';
import { Login } from './pages/mobile/Login';
import { Register } from './pages/mobile/Register';
import { AdminLayout } from './components/AdminLayout';
import { AdminDashboard } from './pages/admin/Dashboard';
import { MapBuilder } from './pages/admin/MapBuilder';
import { QrManager } from './pages/admin/QrManager';
import { Settings } from './pages/admin/Settings';

export const router = createBrowserRouter([
  {
    path: '/',
    Component: MobileFrame,
    children: [
      { index: true, Component: Home },
      { path: 'scanner', Component: Scanner },
      { path: 'search', Component: Search },
      { path: 'preview', Component: RoutePreview },
      { path: 'navigation', Component: Navigation },
      { path: 'history', Component: History },
      { path: 'login', Component: Login },
      { path: 'register', Component: Register },
    ],
  },
  {
    path: '/admin',
    Component: AdminLayout,
    children: [
      { index: true, Component: AdminDashboard },
      { path: 'map-builder', Component: MapBuilder },
      { path: 'qrs', Component: QrManager },
      { path: 'settings', Component: Settings },
    ],
  },
]);



