'use client';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import Cookies from 'js-cookie';

const NAV = [
  { href: '/dashboard', label: 'Dashboard',   icon: '📊', color: 'from-emerald-500/20 to-green-600/10',  active: 'border-emerald-500/50 text-emerald-400' },
  { href: '/users',     label: 'Users',        icon: '👥', color: 'from-blue-500/20 to-indigo-600/10',    active: 'border-blue-500/50 text-blue-400' },
  { href: '/matches',   label: 'Matches',      icon: '🃏', color: 'from-amber-500/20 to-orange-600/10',   active: 'border-amber-500/50 text-amber-400' },
  { href: '/payments',  label: 'Payments',     icon: '💰', color: 'from-green-500/20 to-emerald-600/10',  active: 'border-green-500/50 text-green-400' },
  { href: '/analytics', label: 'Analytics',    icon: '📈', color: 'from-purple-500/20 to-violet-600/10',  active: 'border-purple-500/50 text-purple-400' },
];

export default function Sidebar() {
  const pathname = usePathname();
  const router   = useRouter();

  const logout = () => {
    Cookies.remove('admin_token');
    router.push('/login');
  };

  return (
    <aside className="w-60 min-h-screen flex flex-col"
           style={{
             background: 'linear-gradient(180deg, #0d1a12 0%, #0D1117 40%, #0a0d1a 100%)',
             borderRight: '1px solid rgba(255,255,255,0.05)',
           }}>

      {/* Logo */}
      <div className="px-5 py-6 border-b" style={{ borderColor: 'rgba(255,255,255,0.05)' }}>
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-xl flex items-center justify-center text-xl font-bold"
               style={{ background: 'linear-gradient(135deg, #238636, #1a5c28)', boxShadow: '0 0 12px rgba(35,134,54,0.4)' }}>
            ♠
          </div>
          <div>
            <h1 className="text-white font-bold text-base leading-tight">Lakadiya</h1>
            <p className="text-gray-500 text-xs">Admin Panel</p>
          </div>
        </div>

        {/* Suit row */}
        <div className="flex gap-2 mt-3 opacity-40">
          {['♠','♥','♦','♣'].map((s) => (
            <span key={s} className="text-sm" style={{ color: s === '♥' || s === '♦' ? '#ff6b81' : '#8b949e' }}>{s}</span>
          ))}
        </div>
      </div>

      {/* Nav */}
      <nav className="flex-1 px-3 py-4 space-y-1.5">
        {NAV.map((item) => {
          const active = pathname.startsWith(item.href);
          return (
            <Link key={item.href} href={item.href}
                  className={`group flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm
                              font-medium transition-all duration-200 border
                              ${active
                                ? `bg-gradient-to-r ${item.color} ${item.active} border-opacity-60`
                                : 'text-gray-400 border-transparent hover:bg-white/5 hover:text-white'}`}>
              <span className={`text-lg transition-transform duration-200 ${active ? '' : 'group-hover:scale-110'}`}>
                {item.icon}
              </span>
              {item.label}
              {active && (
                <span className="ml-auto w-1.5 h-1.5 rounded-full bg-current opacity-80" />
              )}
            </Link>
          );
        })}
      </nav>

      {/* Live indicator */}
      <div className="mx-3 mb-3 px-3 py-2.5 rounded-xl flex items-center gap-2.5"
           style={{ background: 'rgba(35,134,54,0.1)', border: '1px solid rgba(35,134,54,0.2)' }}>
        <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse flex-shrink-0" />
        <div>
          <p className="text-emerald-400 text-xs font-semibold">System Online</p>
          <p className="text-gray-600 text-xs">All services running</p>
        </div>
      </div>

      {/* Logout */}
      <div className="px-3 pb-4" style={{ borderTop: '1px solid rgba(255,255,255,0.05)', paddingTop: 12 }}>
        <button onClick={logout}
                className="w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm
                           text-gray-400 hover:bg-red-500/10 hover:text-red-400
                           border border-transparent hover:border-red-500/20 transition-all duration-200">
          <span className="text-lg">🚪</span>
          Logout
        </button>
      </div>
    </aside>
  );
}
