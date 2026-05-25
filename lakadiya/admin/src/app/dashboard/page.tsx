'use client';
import { useEffect, useState } from 'react';
import { getDashboard } from '../../lib/api';
import StatCard from '../../components/dashboard/stat_card';

interface Stats {
  totalUsers: number; activeGames: number;
  todayMatches: number; totalMatches: number;
}

const STAT_CONFIG = [
  {
    key:      'totalUsers'   as keyof Stats,
    label:    'Total Players',
    icon:     '👥',
    gradient: 'from-emerald-500 to-green-700',
    glow:     'rgba(34,197,94,0.3)',
    delay:    0,
  },
  {
    key:      'activeGames'  as keyof Stats,
    label:    'Active Games',
    icon:     '🃏',
    gradient: 'from-blue-500 to-indigo-700',
    glow:     'rgba(59,130,246,0.3)',
    delay:    100,
  },
  {
    key:      'todayMatches' as keyof Stats,
    label:    "Today's Matches",
    icon:     '📅',
    gradient: 'from-amber-400 to-orange-600',
    glow:     'rgba(245,158,11,0.3)',
    delay:    200,
  },
  {
    key:      'totalMatches' as keyof Stats,
    label:    'Total Matches',
    icon:     '🏆',
    gradient: 'from-purple-500 to-violet-700',
    glow:     'rgba(168,85,247,0.3)',
    delay:    300,
  },
];

const QUICK_LINKS = [
  { href: '/users',           label: 'Manage Users',    icon: '👥', color: 'from-green-600/20 to-emerald-600/10',  border: 'border-green-500/30',  text: 'text-green-400' },
  { href: '/matches',         label: 'View Matches',    icon: '🃏', color: 'from-blue-600/20 to-indigo-600/10',    border: 'border-blue-500/30',   text: 'text-blue-400' },
  { href: '/analytics',       label: 'Analytics',       icon: '📈', color: 'from-amber-600/20 to-orange-600/10',   border: 'border-amber-500/30',  text: 'text-amber-400' },
  { href: '/users?banned=true',label: 'Banned Users',   icon: '🚫', color: 'from-red-600/20 to-rose-600/10',       border: 'border-red-500/30',    text: 'text-red-400' },
];

export default function DashboardPage() {
  const [stats, setStats]     = useState<Stats | null>(null);
  const [loading, setLoading] = useState(true);
  const [time, setTime]       = useState('');

  useEffect(() => {
    getDashboard().then(setStats).finally(() => setLoading(false));
    const id = setInterval(() => getDashboard().then(setStats), 30_000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    const tick = () => setTime(new Date().toLocaleTimeString());
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, []);

  return (
    <div className="min-h-screen" style={{ background: 'transparent' }}>

      {/* ── Page header ── */}
      <div className="flex items-start justify-between mb-8 animate-fade-in-up">
        <div>
          <h1 className="text-3xl font-bold text-white flex items-center gap-3">
            <span className="text-4xl">♠</span>
            <span className="gradient-text">Dashboard</span>
          </h1>
          <p className="text-gray-400 text-sm mt-1">
            Welcome back, Admin · Live data updates every 30s
          </p>
        </div>
        <div className="text-right">
          <div className="text-white font-mono text-lg font-bold">{time}</div>
          <div className="text-gray-500 text-xs mt-0.5">
            {new Date().toLocaleDateString('en-IN', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })}
          </div>
          {/* Live indicator */}
          <div className="flex items-center justify-end gap-1.5 mt-1.5">
            <span className="w-2 h-2 rounded-full bg-green-500 animate-pulse" />
            <span className="text-green-400 text-xs font-semibold">LIVE</span>
          </div>
        </div>
      </div>

      {/* ── Stat cards ── */}
      {loading ? (
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
          {[...Array(4)].map((_, i) => (
            <div key={i} className="h-32 rounded-2xl shimmer" />
          ))}
        </div>
      ) : (
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
          {STAT_CONFIG.map((cfg) => (
            <StatCard
              key={cfg.key}
              label={cfg.label}
              value={stats?.[cfg.key] ?? 0}
              icon={cfg.icon}
              gradient={cfg.gradient}
              glow={cfg.glow}
              delay={cfg.delay}
            />
          ))}
        </div>
      )}

      {/* ── Game status banner ── */}
      <div className="mb-6 animate-fade-in-up delay-400 rounded-2xl overflow-hidden relative"
           style={{ background: 'linear-gradient(135deg, #0d2618 0%, #0a1628 50%, #1a0d28 100%)', border: '1px solid rgba(255,255,255,0.06)' }}>
        <div className="absolute inset-0 opacity-30"
             style={{ background: 'linear-gradient(90deg, #238636, #1F6FEB, #E3B341, #DA3633)', backgroundSize: '400% 100%', animation: 'gradientShift 6s ease infinite' }} />
        <div className="relative flex items-center justify-between px-6 py-4">
          <div className="flex items-center gap-4">
            <div className="text-4xl">🃏</div>
            <div>
              <p className="text-white font-bold text-lg">Lakadiya · Callbreak</p>
              <p className="text-gray-400 text-sm">Real-time multiplayer card game platform</p>
            </div>
          </div>
          <div className="flex items-center gap-6 text-center">
            <div>
              <p className="text-2xl font-bold text-emerald-400">{stats?.activeGames ?? '—'}</p>
              <p className="text-gray-400 text-xs">Live Tables</p>
            </div>
            <div className="w-px h-10 bg-white/10" />
            <div>
              <p className="text-2xl font-bold text-blue-400">{stats ? stats.activeGames * 4 : '—'}</p>
              <p className="text-gray-400 text-xs">Players In-Game</p>
            </div>
          </div>
        </div>
      </div>

      {/* ── Quick links ── */}
      <div className="animate-fade-in-up delay-500">
        <h2 className="text-lg font-bold text-white mb-4 flex items-center gap-2">
          <span className="text-xl">⚡</span> Quick Actions
        </h2>
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
          {QUICK_LINKS.map((item, i) => (
            <a key={item.href} href={item.href}
               className={`group flex flex-col items-center gap-3 p-5 rounded-2xl
                           bg-gradient-to-br ${item.color} border ${item.border}
                           hover-lift transition-all duration-200`}
               style={{ animationDelay: `${i * 80}ms` }}>
              <span className="text-3xl group-hover:scale-110 transition-transform duration-200">
                {item.icon}
              </span>
              <span className={`text-sm font-semibold ${item.text}`}>{item.label}</span>
            </a>
          ))}
        </div>
      </div>

      {/* ── Suit decorations bottom ── */}
      <div className="flex justify-center gap-8 mt-10 opacity-10 animate-fade-in-up delay-600">
        {['♠','♥','♦','♣'].map((s, i) => (
          <span key={s} className="text-5xl font-bold select-none"
                style={{
                  color: s === '♥' || s === '♦' ? '#ff6b81' : '#8b949e',
                  animationDelay: `${i * 0.1}s`,
                  animation: `floatCard ${6 + i}s ease-in-out ${i * 0.5}s infinite`,
                  '--r': `${(i - 1.5) * 8}deg`,
                  '--o': '0.15',
                } as React.CSSProperties}>
            {s}
          </span>
        ))}
      </div>
    </div>
  );
}
