'use client';
import { useEffect, useState } from 'react';
import {
  AreaChart, Area, BarChart, Bar, ComposedChart, Line,
  XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid, Legend,
  PieChart, Pie, Cell,
} from 'recharts';
import { getAnalytics, getPaymentStats, getAdminSettings, type Analytics, type PaymentStats } from '../../lib/api';
import { formatCurrency } from '../../lib/utils';
import { format } from 'date-fns';

const CS = {
  contentStyle: { backgroundColor: '#0B0F1A', border: '1px solid #1A2235', borderRadius: 10, fontSize: 12 },
  labelStyle:   { color: '#E2E8F0' },
};
const MEDAL = ['🥇', '🥈', '🥉'];

// ── Stat card ──────────────────────────────────────────────────────────────────
function MiniCard({ label, value, icon, color, sub }: { label: string; value: string; icon: string; color: string; sub?: string }) {
  return (
    <div className="relative rounded-2xl p-4 border overflow-hidden"
         style={{ background: '#0F1420', borderColor: `${color}20`, boxShadow: `0 0 18px ${color}12` }}>
      <div className="absolute inset-0 opacity-5" style={{ background: `radial-gradient(circle at top right, ${color}, transparent 60%)` }} />
      <div className="relative flex items-start justify-between">
        <div>
          <p className="text-gray-500 text-xs uppercase tracking-wider mb-1">{label}</p>
          <p className="text-xl font-bold text-white">{value}</p>
          {sub && <p className="text-gray-600 text-xs mt-1">{sub}</p>}
        </div>
        <span className="text-2xl absolute top-3 right-4">{icon}</span>
      </div>
    </div>
  );
}

export default function AnalyticsPage() {
  const [data,    setData]    = useState<Analytics | null>(null);
  const [pstats,  setPstats]  = useState<PaymentStats | null>(null);
  const [settings, setSettings] = useState<{ platform_fee_pct: number; payment_gateway_fee_pct: number } | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Promise.all([getAnalytics(), getPaymentStats(), getAdminSettings()])
      .then(([a, p, s]) => {
        setData(a);
        setPstats(p);
        setSettings({ platform_fee_pct: s.platform_fee_pct, payment_gateway_fee_pct: s.payment_gateway_fee_pct });
      })
      .finally(() => setLoading(false));
  }, []);

  const matchData = (data?.matchesByDay ?? []).map(d => ({
    date: format(new Date(d.date), 'MMM d'), matches: Number(d.matches),
  }));

  const regData = (data?.registrationsByDay ?? []).map(d => ({
    date: format(new Date(d.date), 'MMM d'), users: Number(d.users),
  }));

  // Daily earnings chart — withdrawal fee is actual profit
  const earningsData = (data?.feesByDay ?? []).map(d => ({
    date:          format(new Date(d.date), 'MMM d'),
    earnings:      Number(d.platform_fee),    // actual profit
    gwRecovered:   Number(d.gateway_fee),     // cost pass-through (NOT profit)
    total:         Number(d.platform_fee) + Number(d.gateway_fee),
  }));

  // Revenue breakdown for pie
  const financePie = pstats ? [
    { name: 'Platform Earnings',   value: pstats.total_platform_fee_earned, fill: '#10B981' },
    { name: 'Total Withdrawn',     value: pstats.total_withdrawn,           fill: '#EF4444' },
    { name: 'Gateway Recovered',   value: pstats.total_gateway_fee_earned,  fill: '#64748B' },
    { name: 'Pending Payouts',     value: pstats.pending_amount,            fill: '#F59E0B' },
  ].filter(d => d.value > 0) : [];

  return (
    <div className="min-h-screen">
      {/* Header */}
      <div className="flex items-start justify-between mb-7">
        <div>
          <h1 className="text-2xl font-bold text-white flex items-center gap-2">
            <span className="text-3xl">📈</span>
            <span style={{ background: 'linear-gradient(90deg,#06B6D4,#818CF8)', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' }}>
              Analytics
            </span>
          </h1>
          <p className="text-gray-500 text-sm mt-1">Platform insights — last 7 days</p>
        </div>
        {settings && (
          <div className="flex gap-3 text-xs">
            <div className="px-3 py-1.5 rounded-lg border border-emerald-500/30 bg-emerald-500/5 text-emerald-400">
              Withdrawal Fee: <strong>{settings.platform_fee_pct}%</strong>
            </div>
            <div className="px-3 py-1.5 rounded-lg border border-slate-500/30 bg-slate-500/5 text-slate-400">
              Gateway Recovery: <strong>{settings.payment_gateway_fee_pct}%</strong>
            </div>
          </div>
        )}
      </div>

      {loading ? (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">
          {[...Array(6)].map((_, i) => <div key={i} className="h-64 rounded-2xl bg-dark-card border border-dark-border animate-pulse" />)}
        </div>
      ) : (
        <>
          {/* ── Stats row: earnings first ── */}
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
            <MiniCard label="Platform Earnings"   value={formatCurrency(pstats?.total_platform_fee_earned ?? 0)} icon="🏦" color="#10B981"
              sub="Withdrawal fee = profit" />
            <MiniCard label="Today's Earnings"    value={formatCurrency(pstats?.today_platform_fee_earned ?? 0)} icon="📈" color="#6366F1" />
            <MiniCard label="Total Deposits"      value={formatCurrency(pstats?.total_revenue ?? 0)}            icon="💰" color="#3B82F6"
              sub={`${pstats?.total_add_count ?? 0} transactions`} />
            <MiniCard label="Total Withdrawn"     value={formatCurrency(pstats?.total_withdrawn ?? 0)}          icon="📤" color="#EF4444" />
          </div>

          <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-7">
            <MiniCard label="Bet Volume"           value={formatCurrency(pstats?.total_bet_escrowed ?? 0)}       icon="🎲" color="#8B5CF6"
              sub={`${pstats?.total_bet_games ?? 0} games`} />
            <MiniCard label="Bet Payouts"          value={formatCurrency(pstats?.total_bet_payouts ?? 0)}        icon="🏆" color="#F59E0B" />
            <MiniCard label="Gateway Recovered"    value={formatCurrency(pstats?.total_gateway_fee_earned ?? 0)} icon="💳" color="#64748B"
              sub="Not platform profit" />
            <MiniCard label="Pending Withdrawals"  value={formatCurrency(pstats?.pending_amount ?? 0)}           icon="⏳" color="#F97316"
              sub={`${pstats?.pending_count ?? 0} requests`} />
          </div>

          {/* ── Row 1: Daily Earnings + Deposits ── */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-5 mb-5">

            {/* Daily Platform Earnings (withdrawal fee) */}
            <div className="rounded-2xl border border-dark-border p-5" style={{ background: '#0F1420' }}>
              <div className="flex items-center justify-between mb-4">
                <h2 className="text-sm font-semibold text-white flex items-center gap-2">
                  <span className="w-2 h-2 rounded-full bg-emerald-400 inline-block" />
                  Platform Earnings — Last 7 Days
                </h2>
                <span className="text-xs text-gray-600">Withdrawal fee only</span>
              </div>
              {earningsData.length > 0 ? (
                <ResponsiveContainer width="100%" height={200}>
                  <ComposedChart data={earningsData}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#1A2235" />
                    <XAxis dataKey="date" tick={{ fill: '#64748B', fontSize: 11 }} axisLine={false} tickLine={false} />
                    <YAxis tick={{ fill: '#64748B', fontSize: 11 }} axisLine={false} tickLine={false}
                           tickFormatter={(v) => `₹${v}`} />
                    <Tooltip {...CS}
                      formatter={(v: number, name: string) => [
                        formatCurrency(v),
                        name === 'earnings' ? 'Platform Earnings' : 'Gateway Recovered',
                      ]} />
                    <Legend formatter={(v) => v === 'earnings' ? 'Platform Earnings' : 'Gateway Recovered'} />
                    <Bar dataKey="earnings"    fill="#10B981" radius={[4,4,0,0]} name="earnings" />
                    <Bar dataKey="gwRecovered" fill="#334155" radius={[4,4,0,0]} name="gwRecovered" />
                  </ComposedChart>
                </ResponsiveContainer>
              ) : (
                <div className="flex flex-col items-center justify-center h-48 text-gray-600">
                  <span className="text-3xl mb-2">📊</span>
                  <p className="text-sm">No fee data yet</p>
                </div>
              )}
            </div>

            {/* Registrations */}
            <div className="rounded-2xl border border-dark-border p-5" style={{ background: '#0F1420' }}>
              <h2 className="text-sm font-semibold text-white mb-4">New Registrations — Last 7 Days</h2>
              {regData.length > 0 ? (
                <ResponsiveContainer width="100%" height={200}>
                  <AreaChart data={regData}>
                    <defs>
                      <linearGradient id="regGrad" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="5%"  stopColor="#10B981" stopOpacity={0.3} />
                        <stop offset="95%" stopColor="#10B981" stopOpacity={0} />
                      </linearGradient>
                    </defs>
                    <CartesianGrid strokeDasharray="3 3" stroke="#1A2235" />
                    <XAxis dataKey="date" tick={{ fill: '#64748B', fontSize: 11 }} axisLine={false} tickLine={false} />
                    <YAxis allowDecimals={false} tick={{ fill: '#64748B', fontSize: 11 }} axisLine={false} tickLine={false} />
                    <Tooltip {...CS} itemStyle={{ color: '#34D399' }} />
                    <Area type="monotone" dataKey="users" stroke="#10B981" strokeWidth={2}
                          fill="url(#regGrad)" dot={{ r: 3, fill: '#10B981' }} />
                  </AreaChart>
                </ResponsiveContainer>
              ) : <p className="text-gray-600 text-sm py-8 text-center">No registration data yet</p>}
            </div>
          </div>

          {/* ── Row 2: Matches + Revenue Pie ── */}
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-5 mb-5">
            {/* Matches bar chart */}
            <div className="lg:col-span-2 rounded-2xl border border-dark-border p-5" style={{ background: '#0F1420' }}>
              <h2 className="text-sm font-semibold text-white mb-4">Matches — Last 7 Days</h2>
              {matchData.length > 0 ? (
                <ResponsiveContainer width="100%" height={200}>
                  <BarChart data={matchData}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#1A2235" />
                    <XAxis dataKey="date" tick={{ fill: '#64748B', fontSize: 11 }} axisLine={false} tickLine={false} />
                    <YAxis allowDecimals={false} tick={{ fill: '#64748B', fontSize: 11 }} axisLine={false} tickLine={false} />
                    <Tooltip {...CS} itemStyle={{ color: '#818CF8' }} />
                    <Bar dataKey="matches" fill="#6366F1" radius={[4, 4, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              ) : <p className="text-gray-600 text-sm py-8 text-center">No match data yet</p>}
            </div>

            {/* Financial pie */}
            <div className="rounded-2xl border border-dark-border p-5" style={{ background: '#0F1420' }}>
              <h2 className="text-sm font-semibold text-white mb-1">Financial Breakdown</h2>
              <p className="text-gray-600 text-xs mb-4">Green = actual platform profit</p>
              {financePie.length > 0 ? (
                <>
                  <ResponsiveContainer width="100%" height={160}>
                    <PieChart>
                      <Pie data={financePie} cx="50%" cy="50%" innerRadius={45} outerRadius={70}
                           paddingAngle={3} dataKey="value">
                        {financePie.map((entry, i) => <Cell key={i} fill={entry.fill} />)}
                      </Pie>
                      <Tooltip {...CS} formatter={(v: number) => formatCurrency(v)} />
                    </PieChart>
                  </ResponsiveContainer>
                  <div className="space-y-1.5 mt-2">
                    {financePie.map(({ name, value, fill }) => (
                      <div key={name} className="flex items-center justify-between text-xs">
                        <div className="flex items-center gap-2">
                          <span className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ background: fill }} />
                          <span className="text-gray-400">{name}</span>
                        </div>
                        <span className="text-white font-medium">{formatCurrency(value)}</span>
                      </div>
                    ))}
                  </div>
                </>
              ) : <p className="text-gray-600 text-sm py-8 text-center">No data</p>}
            </div>
          </div>

          {/* ── Row 3: Top players ── */}
          <div className="rounded-2xl border border-dark-border p-5" style={{ background: '#0F1420' }}>
            <h2 className="text-sm font-semibold text-white mb-4">Top 10 Players</h2>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr>
                    <th className="pb-2 pr-4 text-left text-xs text-gray-500 font-medium">#</th>
                    <th className="pb-2 pr-4 text-left text-xs text-gray-500 font-medium">Player</th>
                    <th className="pb-2 pr-4 text-left text-xs text-gray-500 font-medium">Wins</th>
                    <th className="pb-2 text-left text-xs text-gray-500 font-medium">Score</th>
                  </tr>
                </thead>
                <tbody>
                  {(data?.topPlayers ?? []).map((p, i) => (
                    <tr key={p.username} className="border-t border-dark-border/40">
                      <td className="py-2.5 pr-4">
                        {i < 3 ? <span>{MEDAL[i]}</span> : <span className="text-gray-600 font-mono text-xs">{i + 1}</span>}
                      </td>
                      <td className="py-2.5 pr-4 text-white font-medium">{p.username}</td>
                      <td className="py-2.5 pr-4 text-emerald-400 font-semibold">{p.matches_won}</td>
                      <td className="py-2.5 text-gray-400">{Number(p.total_score).toFixed(1)}</td>
                    </tr>
                  ))}
                  {!data?.topPlayers?.length && (
                    <tr><td colSpan={4} className="py-8 text-center text-gray-600">No player data yet</td></tr>
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
