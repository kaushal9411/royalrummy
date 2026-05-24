'use client';
import { useEffect, useState } from 'react';
import {
  LineChart, Line, BarChart, Bar, XAxis, YAxis,
  Tooltip, ResponsiveContainer, CartesianGrid, Legend,
} from 'recharts';
import { getAnalytics, Analytics } from '../../lib/api';
import { format } from 'date-fns';

export default function AnalyticsPage() {
  const [data, setData]       = useState<Analytics | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    getAnalytics().then(setData).finally(() => setLoading(false));
  }, []);

  if (loading) return <div className="text-gray-400">Loading analytics…</div>;
  if (!data)   return <div className="text-red-400">Failed to load analytics</div>;

  const matchChartData = data.matchesByDay.map((d) => ({
    date:    format(new Date(d.date), 'MMM d'),
    matches: Number(d.matches),
  }));

  const regChartData = data.registrationsByDay.map((d) => ({
    date:  format(new Date(d.date), 'MMM d'),
    users: Number(d.users),
  }));

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-white">Analytics</h1>

      {/* Matches chart */}
      <div className="card">
        <h2 className="text-lg font-semibold text-white mb-4">Matches — Last 7 Days</h2>
        {matchChartData.length === 0
          ? <p className="text-gray-500 text-sm">No data yet</p>
          : (
            <ResponsiveContainer width="100%" height={220}>
              <BarChart data={matchChartData}>
                <CartesianGrid strokeDasharray="3 3" stroke="#30363D" />
                <XAxis dataKey="date" tick={{ fill: '#8B949E', fontSize: 12 }} />
                <YAxis allowDecimals={false} tick={{ fill: '#8B949E', fontSize: 12 }} />
                <Tooltip
                  contentStyle={{ backgroundColor: '#21262D', border: '1px solid #30363D', borderRadius: 8 }}
                  labelStyle={{ color: '#F0F6FC' }} itemStyle={{ color: '#2EA043' }}
                />
                <Bar dataKey="matches" fill="#238636" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          )
        }
      </div>

      {/* Registrations chart */}
      <div className="card">
        <h2 className="text-lg font-semibold text-white mb-4">New Users — Last 7 Days</h2>
        {regChartData.length === 0
          ? <p className="text-gray-500 text-sm">No data yet</p>
          : (
            <ResponsiveContainer width="100%" height={220}>
              <LineChart data={regChartData}>
                <CartesianGrid strokeDasharray="3 3" stroke="#30363D" />
                <XAxis dataKey="date" tick={{ fill: '#8B949E', fontSize: 12 }} />
                <YAxis allowDecimals={false} tick={{ fill: '#8B949E', fontSize: 12 }} />
                <Tooltip
                  contentStyle={{ backgroundColor: '#21262D', border: '1px solid #30363D', borderRadius: 8 }}
                  labelStyle={{ color: '#F0F6FC' }} itemStyle={{ color: '#1F6FEB' }}
                />
                <Legend />
                <Line type="monotone" dataKey="users" stroke="#1F6FEB" strokeWidth={2} dot={{ r: 4, fill: '#1F6FEB' }} />
              </LineChart>
            </ResponsiveContainer>
          )
        }
      </div>

      {/* Top players */}
      <div className="card">
        <h2 className="text-lg font-semibold text-white mb-4">Top 10 Players</h2>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-dark-border text-gray-400 text-left">
                <th className="py-2 pr-4">#</th>
                <th className="py-2 pr-4">Username</th>
                <th className="py-2 pr-4">Wins</th>
                <th className="py-2">Total Score</th>
              </tr>
            </thead>
            <tbody>
              {data.topPlayers.map((p, i) => (
                <tr key={p.username} className="border-b border-dark-border/50">
                  <td className="py-2 pr-4 text-gray-500">{i + 1}</td>
                  <td className="py-2 pr-4 text-white font-medium">{p.username}</td>
                  <td className="py-2 pr-4 text-green-400 font-bold">{p.matches_won}</td>
                  <td className="py-2 text-gray-300">{Number(p.total_score).toFixed(1)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
