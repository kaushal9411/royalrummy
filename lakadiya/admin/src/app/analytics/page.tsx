'use client';
import { useEffect, useState } from 'react';
import {
  AreaChart, Area, BarChart, Bar, LineChart, Line,
  XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid, Legend,
  PieChart, Pie, Cell,
} from 'recharts';
import { getAnalytics, getPaymentStats, type Analytics, type PaymentStats } from '../../lib/api';
import { formatCurrency } from '../../lib/utils';
import { format } from 'date-fns';

const CHART_STYLE = {
  contentStyle: { backgroundColor: '#0B0F1A', border: '1px solid #1A2235', borderRadius: 10, fontSize: 12 },
  labelStyle:   { color: '#E2E8F0' },
};

const MEDAL = ['🥇', '🥈', '🥉'];

export default function AnalyticsPage() {
  const [data,    setData]    = useState<Analytics | null>(null);
  const [pstats,  setPstats]  = useState<PaymentStats | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Promise.all([getAnalytics(), getPaymentStats()])
      .then(([a, p]) => { setData(a); setPstats(p); })
      .finally(() => setLoading(false));
  }, []);

  const matchData = (data?.matchesByDay ?? []).map(d => ({
    date: format(new Date(d.date), 'MMM d'),
    matches: Number(d.matches),
  }));

  const regData = (data?.registrationsByDay ?? []).map(d => ({
    date: format(new Date(d.date), 'MMM d'),
    users: Number(d.users),
  }));

  const financePie = pstats ? [
    { name: 'Revenue',   value: pstats.total_revenue,    fill: '#10B981' },
    { name: 'Withdrawn', value: pstats.total_withdrawn,  fill: '#EF4444' },
    { name: 'Pending',   value: pstats.pending_amount,   fill: '#F59E0B' },
  ] : [];

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
      </div>

      {loading ? (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">
          {[...Array(4)].map((_, i) => (
            <div key={i} className="h-64 rounded-2xl bg-dark-card border border-dark-border animate-pulse" />
          ))}
        </div>
      ) : (
        <>
          {/* Stats summary row */}
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
            {[
              { label: 'Total Revenue',   value: formatCurrency(pstats?.total_revenue ?? 0),   icon: '💰', color: '#10B981' },
              { label: 'Total Withdrawn', value: formatCurrency(pstats?.total_withdrawn ?? 0), icon: '📤', color: '#EF4444' },
              { label: 'Bet Volume',      value: formatCurrency(pstats?.total_bet_escrowed ?? 0), icon: '🎲', color: '#8B5CF6' },
              { label: 'Bet Payouts',     value: formatCurrency(pstats?.total_bet_payouts ?? 0),  icon: '🏆', color: '#F59E0B' },
            ].map(({ label, value, icon, color }) => (
              <div key={label} className="relative rounded-2xl p-4 border overflow-hidden"
                   style={{ background: '#0F1420', borderColor: `${color}20`, boxShadow: `0 0 18px ${color}12` }}>
                <div className="absolute inset-0 opacity-5" style={{ background: `radial-gradient(circle at top right, ${color}, transparent 60%)` }} />
                <div className="relative">
                  <p className="text-gray-500 text-xs uppercase tracking-wider mb-1">{label}</p>
                  <p className="text-xl font-bold text-white">{value}</p>
                  <span className="absolute top-0 right-0 text-2xl">{icon}</span>
                </div>
              </div>
            ))}
          </div>

          {/* Charts row 1 */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-5 mb-5">
            {/* Matches bar chart */}
            <div className="rounded-2xl border border-dark-border p-5" style={{ background: '#0F1420' }}>
              <h2 className="text-sm font-semibold text-white mb-4">Matches — Last 7 Days</h2>
              {matchData.length > 0 ? (
                <ResponsiveContainer width="100%" height={200}>
                  <BarChart data={matchData}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#1A2235" />
                    <XAxis dataKey="date" tick={{ fill: '#64748B', fontSize: 11 }} axisLine={false} tickLine={false} />
                    <YAxis allowDecimals={false} tick={{ fill: '#64748B', fontSize: 11 }} axisLine={false} tickLine={false} />
                    <Tooltip {...CHART_STYLE} itemStyle={{ color: '#818CF8' }} />
                    <Bar dataKey="matches" fill="#6366F1" radius={[4, 4, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              ) : <p className="text-gray-600 text-sm py-8 text-center">No match data yet</p>}
            </div>

            {/* Registrations area chart */}
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
                    <Tooltip {...CHART_STYLE} itemStyle={{ color: '#34D399' }} />
                    <Area type="monotone" dataKey="users" stroke="#10B981" strokeWidth={2}
                          fill="url(#regGrad)" dot={{ r: 3, fill: '#10B981' }} />
                  </AreaChart>
                </ResponsiveContainer>
              ) : <p className="text-gray-600 text-sm py-8 text-center">No registration data yet</p>}
            </div>
          </div>

          {/* Charts row 2 */}
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-5">
            {/* Finance pie */}
            <div className="rounded-2xl border border-dark-border p-5" style={{ background: '#0F1420' }}>
              <h2 className="text-sm font-semibold text-white mb-4">Financial Overview</h2>
              {financePie.length > 0 && pstats ? (
                <>
                  <ResponsiveContainer width="100%" height={160}>
                    <PieChart>
                      <Pie data={financePie} cx="50%" cy="50%" innerRadius={45} outerRadius={70}
                           paddingAngle={3} dataKey="value">
                        {financePie.map((entry, i) => <Cell key={i} fill={entry.fill} />)}
                      </Pie>
                      <Tooltip {...CHART_STYLE} formatter={(v: number) => formatCurrency(v)} />
                    </PieChart>
                  </ResponsiveContainer>
                  <div className="space-y-1.5 mt-3">
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

            {/* Top players leaderboard */}
            <div className="lg:col-span-2 rounded-2xl border border-dark-border p-5" style={{ background: '#0F1420' }}>
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
                          <span className="text-sm">
                            {i < 3 ? MEDAL[i] : <span className="text-gray-600 font-mono text-xs">{i + 1}</span>}
                          </span>
                        </td>
                        <td className="py-2.5 pr-4 text-white font-medium">{p.username}</td>
                        <td className="py-2.5 pr-4">
                          <span className="text-success font-semibold">{p.matches_won}</span>
                        </td>
                        <td className="py-2.5 text-gray-400">{Number(p.total_score).toFixed(1)}</td>
                      </tr>
                    ))}
                    {(!data?.topPlayers?.length) && (
                      <tr><td colSpan={4} className="py-8 text-center text-gray-600">No player data yet</td></tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
