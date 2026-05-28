'use client';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import Cookies from 'js-cookie';

const NAV_SECTIONS = [
  {
    label: 'Overview',
    items: [
      { href: '/dashboard',     label: 'Dashboard',      icon: '📊', accent: '#6366F1' },
    ],
  },
  {
    label: 'Users & Games',
    items: [
      { href: '/users',         label: 'Users',          icon: '👥', accent: '#3B82F6' },
      { href: '/matches',       label: 'Matches',        icon: '🃏', accent: '#F59E0B' },
      { href: '/rooms',         label: 'Live Rooms',     icon: '🎮', accent: '#8B5CF6' },
    ],
  },
  {
    label: 'Finance',
    items: [
      { href: '/payments',      label: 'Payments',       icon: '💳', accent: '#10B981' },
      { href: '/withdrawals',   label: 'Withdrawals',    icon: '🏦', accent: '#EF4444' },
    ],
  },
  {
    label: 'Insights',
    items: [
      { href: '/analytics',     label: 'Analytics',      icon: '📈', accent: '#06B6D4' },
    ],
  },
  {
    label: 'Admin',
    items: [
      { href: '/notifications', label: 'Notifications',  icon: '🔔', accent: '#F59E0B' },
      { href: '/settings',      label: 'Settings',       icon: '⚙️',  accent: '#6B7280' },
    ],
  },
];

export default function Sidebar() {
  const pathname = usePathname();
  const router   = useRouter();

  const logout = () => {
    Cookies.remove('admin_token');
    router.push('/login');
  };

  return (
    <aside className="w-60 min-h-screen flex flex-col flex-shrink-0"
           style={{
             background: 'linear-gradient(180deg, #06080F 0%, #0B0F1A 100%)',
             borderRight: '1px solid rgba(99,102,241,0.12)',
           }}>

      {/* Logo */}
      <div className="px-4 py-5 border-b" style={{ borderColor: 'rgba(99,102,241,0.12)' }}>
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-xl flex items-center justify-center text-xl font-bold flex-shrink-0"
               style={{
                 background: 'linear-gradient(135deg, #6366F1 0%, #8B5CF6 100%)',
                 boxShadow: '0 0 16px rgba(99,102,241,0.4)',
               }}>
            ♠
          </div>
          <div className="min-w-0">
            <h1 className="text-white font-bold text-sm leading-tight truncate">Lakadiya</h1>
            <p className="text-gray-500 text-xs">Admin Panel v2</p>
          </div>
        </div>
        <div className="flex gap-2 mt-3">
          {['♠', '♥', '♦', '♣'].map((s) => (
            <span key={s} className="text-xs opacity-30"
                  style={{ color: s === '♥' || s === '♦' ? '#F87171' : '#818CF8' }}>
              {s}
            </span>
          ))}
        </div>
      </div>

      {/* Nav */}
      <nav className="flex-1 px-3 py-3 overflow-y-auto space-y-4">
        {NAV_SECTIONS.map((section) => (
          <div key={section.label}>
            <p className="px-2 mb-1.5 text-xs font-semibold uppercase tracking-wider text-gray-600">
              {section.label}
            </p>
            <div className="space-y-0.5">
              {section.items.map((item) => {
                const active = pathname.startsWith(item.href);
                return (
                  <Link key={item.href} href={item.href}
                        className={`group flex items-center gap-2.5 px-2.5 py-2 rounded-lg text-sm
                                    font-medium transition-all duration-150 border
                                    ${active
                                      ? 'text-white border-white/10'
                                      : 'text-gray-400 border-transparent hover:text-gray-200 hover:bg-white/5'}`}
                        style={active ? {
                          background: `linear-gradient(135deg, ${item.accent}22 0%, ${item.accent}10 100%)`,
                          borderColor: `${item.accent}30`,
                        } : {}}>
                    <span className={`text-base flex-shrink-0 transition-transform duration-150 ${active ? '' : 'group-hover:scale-110'}`}>
                      {item.icon}
                    </span>
                    <span className="truncate">{item.label}</span>
                    {active && (
                      <span className="ml-auto w-1.5 h-1.5 rounded-full flex-shrink-0"
                            style={{ background: item.accent }} />
                    )}
                  </Link>
                );
              })}
            </div>
          </div>
        ))}
      </nav>

      {/* Live indicator */}
      <div className="mx-3 mb-2 px-3 py-2 rounded-xl flex items-center gap-2.5"
           style={{ background: 'rgba(99,102,241,0.08)', border: '1px solid rgba(99,102,241,0.15)' }}>
        <span className="relative flex-shrink-0">
          <span className="w-2 h-2 rounded-full bg-primary block" />
          <span className="absolute inset-0 rounded-full bg-primary animate-ping opacity-40" />
        </span>
        <div className="min-w-0">
          <p className="text-primary-light text-xs font-semibold">System Online</p>
          <p className="text-gray-600 text-xs truncate">All services running</p>
        </div>
      </div>

      {/* Logout */}
      <div className="px-3 pb-4" style={{ borderTop: '1px solid rgba(255,255,255,0.04)', paddingTop: 8 }}>
        <button onClick={logout}
                className="w-full flex items-center gap-2.5 px-2.5 py-2 rounded-lg text-sm
                           text-gray-400 hover:bg-danger/10 hover:text-danger-light
                           border border-transparent hover:border-danger/20 transition-all duration-150">
          <span className="text-base">🚪</span>
          <span>Logout</span>
        </button>
      </div>
    </aside>
  );
}
