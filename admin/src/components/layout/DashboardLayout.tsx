import { ReactNode } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/router';
import {
  LayoutDashboard, Users, Wallet, Shield, Trophy,
  Gamepad2, BarChart3, Settings, LogOut, Bell,
} from 'lucide-react';

const NAV_ITEMS = [
  { href: '/',                label: 'Dashboard',    icon: LayoutDashboard },
  { href: '/users',           label: 'Users',        icon: Users },
  { href: '/wallet',          label: 'Wallet',       icon: Wallet },
  { href: '/games',           label: 'Live Games',   icon: Gamepad2 },
  { href: '/tournaments',     label: 'Tournaments',  icon: Trophy },
  { href: '/reports',         label: 'Reports',      icon: BarChart3 },
  { href: '/reports/fraud',   label: 'Fraud',        icon: Shield },
  { href: '/settings',        label: 'Settings',     icon: Settings },
];

interface Props {
  children: ReactNode;
  title?: string;
}

export function DashboardLayout({ children, title }: Props) {
  const router = useRouter();

  const handleLogout = () => {
    localStorage.removeItem('admin_token');
    router.push('/login');
  };

  return (
    <div className="flex h-screen bg-gray-50 font-sans">
      {/* Sidebar */}
      <aside className="w-64 bg-gray-900 text-white flex flex-col shrink-0">
        {/* Logo */}
        <div className="px-6 py-5 border-b border-gray-700">
          <div className="text-xl font-bold tracking-tight">
            Royal<span className="text-yellow-400">Rummy</span>
          </div>
          <div className="text-xs text-gray-400 mt-0.5">Admin Console</div>
        </div>

        {/* Navigation */}
        <nav className="flex-1 overflow-y-auto py-4">
          {NAV_ITEMS.map(({ href, label, icon: Icon }) => {
            const active = router.pathname === href ||
              (href !== '/' && router.pathname.startsWith(href));
            return (
              <Link
                key={href}
                href={href}
                className={`flex items-center gap-3 px-6 py-2.5 text-sm transition-colors ${
                  active
                    ? 'bg-yellow-500 text-gray-900 font-medium'
                    : 'text-gray-300 hover:bg-gray-800 hover:text-white'
                }`}
              >
                <Icon className="w-4 h-4 shrink-0" />
                {label}
              </Link>
            );
          })}
        </nav>

        {/* Bottom */}
        <div className="px-4 py-4 border-t border-gray-700">
          <button
            onClick={handleLogout}
            className="flex items-center gap-3 w-full px-3 py-2 text-sm text-gray-400 hover:text-white hover:bg-gray-800 rounded-lg transition-colors"
          >
            <LogOut className="w-4 h-4" />
            Log out
          </button>
        </div>
      </aside>

      {/* Main content */}
      <div className="flex-1 flex flex-col overflow-hidden">
        {/* Top bar */}
        <header className="h-14 bg-white border-b border-gray-200 flex items-center justify-between px-6 shrink-0">
          <h1 className="text-base font-semibold text-gray-800">{title || 'Dashboard'}</h1>
          <div className="flex items-center gap-3">
            <button className="relative p-2 text-gray-500 hover:text-gray-800 hover:bg-gray-100 rounded-full">
              <Bell className="w-5 h-5" />
            </button>
            <div className="w-8 h-8 rounded-full bg-yellow-400 flex items-center justify-center text-sm font-bold text-gray-900">
              A
            </div>
          </div>
        </header>

        {/* Page content */}
        <main className="flex-1 overflow-y-auto p-6">
          {children}
        </main>
      </div>
    </div>
  );
}
