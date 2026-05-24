'use client';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import Cookies from 'js-cookie';

const NAV = [
  { href: '/dashboard', label: 'Dashboard',   icon: '📊' },
  { href: '/users',     label: 'Users',        icon: '👥' },
  { href: '/matches',   label: 'Matches',      icon: '🃏' },
  { href: '/analytics', label: 'Analytics',    icon: '📈' },
];

export default function Sidebar() {
  const pathname = usePathname();
  const router   = useRouter();

  const logout = () => {
    Cookies.remove('admin_token');
    router.push('/login');
  };

  return (
    <aside className="w-56 min-h-screen bg-dark-surface border-r border-dark-border flex flex-col">
      <div className="px-5 py-5 border-b border-dark-border">
        <h1 className="text-xl font-bold text-white">♠ Lakadiya</h1>
        <p className="text-xs text-gray-400 mt-0.5">Admin Panel</p>
      </div>

      <nav className="flex-1 px-3 py-4 space-y-1">
        {NAV.map((item) => {
          const active = pathname.startsWith(item.href);
          return (
            <Link
              key={item.href}
              href={item.href}
              className={`flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors
                ${active
                  ? 'bg-primary/20 text-white border border-primary/40'
                  : 'text-gray-400 hover:bg-dark-card hover:text-white'}`}
            >
              <span>{item.icon}</span>
              {item.label}
            </Link>
          );
        })}
      </nav>

      <div className="px-3 py-4 border-t border-dark-border">
        <button
          onClick={logout}
          className="w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm
                     text-gray-400 hover:bg-dark-card hover:text-danger transition-colors"
        >
          <span>🚪</span> Logout
        </button>
      </div>
    </aside>
  );
}
