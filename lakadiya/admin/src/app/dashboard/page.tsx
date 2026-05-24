'use client';
import { useEffect, useState } from 'react';
import { getDashboard } from '../../lib/api';
import StatCard from '../../components/dashboard/stat_card';

interface Stats {
  totalUsers: number; activeGames: number;
  todayMatches: number; totalMatches: number;
}

export default function DashboardPage() {
  const [stats, setStats]   = useState<Stats | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    getDashboard().then(setStats).finally(() => setLoading(false));

    // Auto-refresh every 30 seconds
    const id = setInterval(() => getDashboard().then(setStats), 30_000);
    return () => clearInterval(id);
  }, []);

  if (loading) return <div className="text-gray-400">Loading dashboard…</div>;

  return (
    <div>
      <h1 className="text-2xl font-bold text-white mb-6">Dashboard</h1>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        <StatCard label="Total Users"   value={stats?.totalUsers   ?? 0} icon="👥" color="green" />
        <StatCard label="Active Games"  value={stats?.activeGames  ?? 0} icon="🃏" color="blue" />
        <StatCard label="Today Matches" value={stats?.todayMatches ?? 0} icon="📅" color="yellow" />
        <StatCard label="Total Matches" value={stats?.totalMatches ?? 0} icon="🏆" color="red" />
      </div>

      <div className="card">
        <h2 className="text-lg font-semibold text-white mb-2">Quick Links</h2>
        <div className="grid grid-cols-2 gap-3 mt-4">
          {[
            { href: '/users',     label: 'Manage Users',   icon: '👥' },
            { href: '/matches',   label: 'View Matches',   icon: '🃏' },
            { href: '/analytics', label: 'Analytics',      icon: '📈' },
            { href: '/users?banned=true', label: 'Banned Users', icon: '🚫' },
          ].map((item) => (
            <a
              key={item.href}
              href={item.href}
              className="flex items-center gap-3 p-3 rounded-lg bg-dark-bg border border-dark-border
                         hover:border-primary/50 transition-colors text-gray-300 hover:text-white"
            >
              <span className="text-xl">{item.icon}</span>
              <span className="text-sm font-medium">{item.label}</span>
            </a>
          ))}
        </div>
      </div>
    </div>
  );
}
