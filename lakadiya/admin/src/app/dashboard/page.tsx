'use client';
import { useEffect, useState, useCallback } from 'react';
import {
  AreaChart, Area, BarChart, Bar, XAxis, YAxis,
  Tooltip, ResponsiveContainer, CartesianGrid,
} from 'recharts';
import { getDashboard, getPaymentStats, getAnalytics, type Analytics } from '../../lib/api';
import { formatCurrency, formatNumber } from '../../lib/utils';
import { format } from 'date-fns';

interface Stats {
  totalUsers:  number;
  activeGames: number;
  todayMatches:number;
  totalMatches:number;
}

const STAT_CARDS = [
  { key: 'totalUsers'   as keyof Stats, label: 'Total Players',   icon: '👥', color: '#3B82F6',  glow: 'rgba(59,130,246,0.2)' },
  { key: 'activeGames'  as keyof Stats, label: 'Active Tables',   icon: '🎮', color: '#6366F1',  glow: 'rgba(99,102,241,0.2)' },
  { key: 'todayMatches' as keyof Stats, label: "Today's Matches", icon: '📅', color: '#F59E0B',  glow: 'rgba(245,158,11,0.2)' },
  { key: 'totalMatches' as keyof Stats, label: 'Total Matches',   icon: '🏆', color: '#10B981',  glow: 'rgba(16,185,129,0.2)' },
];

function StatCard({ label, value, icon, color, glow, delay = 0 }: {
  label: string; value: number; icon: string; color: string; glow: string; delay?: number;
}) {
  const [displayed, setDisplayed] = useState(0);
  useEffect(() => {
    const start = Date.now();
    const duration = 800;
    const timer = setInterval(() => {
      const elapsed = Date.now() - start;
      const progress = Math.min(elapsed / duration, 1);
      setDisplayed(Math.floor(value * (1 - Math.pow(1 - progress, 3))));
      if (progress === 1) clearInterval(timer);
    }, 16);
    return () => clearInterval(timer);
  }, [value]);

  return (
    <div className="relative rounded-2xl p-5 border overflow-hidden transition-transform hover:-translate-y-0.5"
         style={{
           background: 'linear-gradient(135deg, rgba(15,20,32,0.9) 0%, rgba(11,15,26,0.9) 100%)',
           borderColor: `${color}25`,
           boxShadow: `0 0 24px ${glow}`,
           animationDelay: `${delay}ms`,
         }}>
      <div className="absolute inset-0 opacity-5"
           style={{ background: `radial-gradient(circle at top right, ${color} 0%, transparent 60%)` }} />
      <div className="relative flex items-start justify-between">
        <div>
          <p className="text-gray-500 text-xs font-medium uppercase tracking-wider mb-2">{label}</p>
          <p className="text-3xl font-bold text-white">{formatNumber(displayed)}</p>
        </div>
        <div className="w-11 h-11 rounded-xl flex items-center justify-center text-2xl flex-shrink-0"
             style={{ background: `${color}18`, border: `1px solid ${color}25` }}>
          {icon}
        </div>
      </div>
    </div>
  );
}

const ChartTooltipStyle = {
  contentStyle: { backgroundColor: '#0F1420', border: '1px solid #1A2235', borderRadius: 10, fontSize: 12 },
  labelStyle:   { color: '#E2E8F0' },
};

export default function DashboardPage() {
  const [stats,  setStats]  = useState<Stats | null>(null);
  const [pstats, setPstats] = useState<{ total_revenue: number; today_revenue: number; pending_count: number } | null>(null);
  const [charts, setCharts] = useState<Analytics | null>(null);
  const [loading, setLoading] = useState(true);
  const [time, setTime] = useState('');

  const load = useCallback(async () => {
    try {
      const [s, p, c] = await Promise.all([getDashboard(), getPaymentStats(), getAnalytics()]);
      setStats(s as unknown as Stats);
      setPstats(p);
      setCharts(c);
    } catch {}
    finally { setLoading(false); }
  }, []);

  useEffect(() => { load(); const id = setInterval(load, 30_000); return () => clearInterval(id); }, [load]);
  useEffect(() => { const tick = () => setTime(new Date().toLocaleTimeString()); tick(); const id = setInterval(tick, 1000); return () => clearInterval(id); }, []);

  const matchData  = (charts?.matchesByDay ?? []).map(d => ({ date: format(new Date(d.date), 'MMM d'), matches: Number(d.matches) }));
  const regData    = (charts?.registrationsByDay ?? []).map(d => ({ date: format(new Date(d.date), 'MMM d'), users: Number(d.users) }));

  return (
    <div className="min-h-screen">
      {/* Header */}
      <div className="flex items-start justify-between mb-7">
        <div>
          <h1 className="text-2xl font-bold text-white flex items-center gap-2">
            <span className="text-3xl">📊</span>
            <span style={{ background: 'linear-gradient(90deg,#818CF8,#A78BFA)', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' }}>
              Dashboard
            </span>
          </h1>
          <p className="text-gray-500 text-sm mt-1">Welcome back, Admin · Auto-refresh every 30s</p>
        </div>
        <div className="text-right">
          <div className="font-mono text-lg font-bold text-white">{time}</div>
          <div className="text-gray-600 text-xs mt-0.5">
            {new Date().toLocaleDateString('en-IN', { weekday: 'short', year: 'numeric', month: 'short', day: 'numeric' })}
          </div>
          <div className="flex items-center justify-end gap-1.5 mt-1">
            <span className="relative flex-shrink-0">
              <span className="w-1.5 h-1.5 rounded-full bg-primary block" />
              <span className="absolute inset-0 rounded-full bg-primary animate-ping opacity-50" />
            </span>
            <span className="text-primary-light text-xs font-semibold">LIVE</span>
          </div>
        </div>
      </div>

      {/* Game stat cards */}
      {loading ? (
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-4">
          {[...Array(4)].map((_, i) => <div key={i} className="h-28 rounded-2xl bg-dark-card border border-dark-border animate-pulse" />)}
        </div>
      ) : (
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-4">
          {STAT_CARDS.map((c, i) => (
            <StatCard key={c.key} label={c.label} value={stats?.[c.key] ?? 0}
              icon={c.icon} color={c.color} glow={c.glow} delay={i * 80} />
          ))}
        </div>
      )}

      {/* Platform Earnings — withdrawal fee is actual profit; gateway fee is Razorpay cost recovery */}
      <div className="mb-3">
        <p className="text-xs font-semibold text-gray-500 uppercase tracking-widest mb-3 flex items-center gap-2">
          <span className="w-4 h-px bg-emerald-500/40 inline-block" />
          Platform Earnings
          <span className="w-4 h-px bg-emerald-500/40 inline-block" />
        </p>
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div className="relative rounded-2xl p-4 border overflow-hidden"
               style={{ background: '#0A1A14', borderColor: '#10B98130', boxShadow: '0 0 24px #10B98118' }}>
            <div className="absolute inset-0 opacity-5" style={{ background: 'radial-gradient(circle at top right, #10B981, transparent 60%)' }} />
            <div className="relative flex items-start justify-between">
              <div>
                <p className="text-gray-500 text-xs uppercase tracking-wider mb-1">Total Earnings</p>
                <p className="text-xl font-bold text-emerald-400">
                  {loading ? '—' : formatCurrency(pstats?.total_platform_fee_earned ?? 0)}
                </p>
                <p className="text-gray-600 text-xs mt-1">Withdrawal fee collected</p>
              </div>
              <span className="text-2xl">🏦</span>
            </div>
          </div>

          <div className="relative rounded-2xl p-4 border overflow-hidden"
               style={{ background: '#0A1A14', borderColor: '#6366F130', boxShadow: '0 0 24px #6366F118' }}>
            <div className="absolute inset-0 opacity-5" style={{ background: 'radial-gradient(circle at top right, #6366F1, transparent 60%)' }} />
            <div className="relative flex items-start justify-between">
              <div>
                <p className="text-gray-500 text-xs uppercase tracking-wider mb-1">Today's Earnings</p>
                <p className="text-xl font-bold text-indigo-400">
                  {loading ? '—' : formatCurrency(pstats?.today_platform_fee_earned ?? 0)}
                </p>
                <p className="text-gray-600 text-xs mt-1">Withdrawal fee today</p>
              </div>
              <span className="text-2xl">📈</span>
            </div>
          </div>

          <div className="relative rounded-2xl p-4 border overflow-hidden"
               style={{ background: '#0F1420', borderColor: '#F59E0B20', boxShadow: '0 0 20px #F59E0B12' }}>
            <div className="absolute inset-0 opacity-5" style={{ background: 'radial-gradient(circle at top right, #F59E0B, transparent 60%)' }} />
            <div className="relative flex items-start justify-between">
              <div>
                <p className="text-gray-500 text-xs uppercase tracking-wider mb-1">Gateway Fee Recovered</p>
                <p className="text-xl font-bold text-amber-400">
                  {loading ? '—' : formatCurrency(pstats?.total_gateway_fee_earned ?? 0)}
                </p>
                <p className="text-gray-600 text-xs mt-1">Razorpay cost recovery</p>
              </div>
              <span className="text-2xl">💳</span>
            </div>
          </div>
        </div>
      </div>

      {/* Deposit & withdrawal overview */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-7">
        {[
          { label: "Today's Deposits", value: pstats?.today_revenue    ?? 0, icon: '📅', color: '#3B82F6', fmt: true },
          { label: 'Total Deposits',   value: pstats?.total_revenue    ?? 0, icon: '💰', color: '#64748B', fmt: true },
          { label: 'Pending Withdrawals', value: pstats?.pending_count ?? 0, icon: '⏳', color: '#EF4444', fmt: false },
        ].map(({ label, value, icon, color, fmt: isCurrency }) => (
          <div key={label} className="relative rounded-2xl p-4 border overflow-hidden"
               style={{ background: '#0F1420', borderColor: `${color}20`, boxShadow: `0 0 16px ${color}12` }}>
            <div className="absolute inset-0 opacity-5" style={{ background: `radial-gradient(circle at top right, ${color}, transparent 60%)` }} />
            <div className="relative flex items-center justify-between">
              <div>
                <p className="text-gray-500 text-xs uppercase tracking-wider mb-1">{label}</p>
                <p className="text-xl font-bold text-white">
                  {loading ? '—' : isCurrency ? formatCurrency(value) : formatNumber(value)}
                </p>
              </div>
              <span className="text-2xl">{icon}</span>
            </div>
          </div>
        ))}
      </div>

      {/* Charts row */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-5 mb-7">
        <div className="rounded-2xl border border-dark-border p-5" style={{ background: '#0F1420' }}>
          <h2 className="text-sm font-semibold text-white mb-4">Matches — Last 7 Days</h2>
          {matchData.length > 0 ? (
            <ResponsiveContainer width="100%" height={180}>
              <BarChart data={matchData} {...ChartTooltipStyle}>
                <CartesianGrid strokeDasharray="3 3" stroke="#1A2235" />
                <XAxis dataKey="date" tick={{ fill: '#64748B', fontSize: 11 }} axisLine={false} tickLine={false} />
                <YAxis allowDecimals={false} tick={{ fill: '#64748B', fontSize: 11 }} axisLine={false} tickLine={false} />
                <Tooltip {...ChartTooltipStyle} itemStyle={{ color: '#818CF8' }} />
                <Bar dataKey="matches" fill="#6366F1" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          ) : <p className="text-gray-600 text-sm">No data yet</p>}
        </div>

        <div className="rounded-2xl border border-dark-border p-5" style={{ background: '#0F1420' }}>
          <h2 className="text-sm font-semibold text-white mb-4">New Users — Last 7 Days</h2>
          {regData.length > 0 ? (
            <ResponsiveContainer width="100%" height={180}>
              <AreaChart data={regData}>
                <defs>
                  <linearGradient id="userGrad" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%"  stopColor="#10B981" stopOpacity={0.25} />
                    <stop offset="95%" stopColor="#10B981" stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="#1A2235" />
                <XAxis dataKey="date" tick={{ fill: '#64748B', fontSize: 11 }} axisLine={false} tickLine={false} />
                <YAxis allowDecimals={false} tick={{ fill: '#64748B', fontSize: 11 }} axisLine={false} tickLine={false} />
                <Tooltip {...ChartTooltipStyle} itemStyle={{ color: '#34D399' }} />
                <Area type="monotone" dataKey="users" stroke="#10B981" strokeWidth={2}
                      fill="url(#userGrad)" dot={{ r: 3, fill: '#10B981' }} />
              </AreaChart>
            </ResponsiveContainer>
          ) : <p className="text-gray-600 text-sm">No data yet</p>}
        </div>
      </div>

      {/* Top players + Quick links */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
        {/* Top players */}
        <div className="lg:col-span-2 rounded-2xl border border-dark-border p-5" style={{ background: '#0F1420' }}>
          <h2 className="text-sm font-semibold text-white mb-4 flex items-center gap-2">
            <span>🏆</span> Top Players
          </h2>
          <div className="space-y-2">
            {(charts?.topPlayers ?? []).slice(0, 5).map((p, i) => (
              <div key={p.username} className="flex items-center gap-3 py-2 border-b border-dark-border/50 last:border-0">
                <span className={`w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold flex-shrink-0
                                  ${i === 0 ? 'bg-accent/20 text-accent' : i === 1 ? 'bg-gray-500/20 text-gray-400' : 'bg-dark-border text-gray-500'}`}>
                  {i + 1}
                </span>
                <span className="flex-1 text-sm text-white font-medium truncate">{p.username}</span>
                <span className="text-success text-xs font-semibold">{p.matches_won} wins</span>
                <span className="text-gray-600 text-xs">{Number(p.total_score).toFixed(0)} pts</span>
              </div>
            ))}
            {!charts && <p className="text-gray-600 text-sm">Loading…</p>}
          </div>
        </div>

        {/* Quick actions */}
        <div className="rounded-2xl border border-dark-border p-5" style={{ background: '#0F1420' }}>
          <h2 className="text-sm font-semibold text-white mb-4 flex items-center gap-2">
            <span>⚡</span> Quick Actions
          </h2>
          <div className="space-y-2">
            {[
              { href: '/users',         label: 'Manage Users',       icon: '👥', color: '#3B82F6' },
              { href: '/withdrawals',   label: 'Pending Withdrawals', icon: '🏦', color: '#EF4444' },
              { href: '/rooms',         label: 'Live Rooms',         icon: '🎮', color: '#8B5CF6' },
              { href: '/notifications', label: 'Send Notification',  icon: '🔔', color: '#F59E0B' },
              { href: '/analytics',     label: 'View Analytics',     icon: '📈', color: '#06B6D4' },
            ].map((item) => (
              <a key={item.href} href={item.href}
                 className="flex items-center gap-2.5 p-2.5 rounded-xl border border-transparent
                            hover:border-white/10 hover:bg-white/5 transition-all group">
                <span className="text-lg group-hover:scale-110 transition-transform">{item.icon}</span>
                <span className="text-sm text-gray-400 group-hover:text-white transition-colors">{item.label}</span>
                <span className="ml-auto text-gray-600 group-hover:text-gray-400 transition-colors text-xs">→</span>
              </a>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
