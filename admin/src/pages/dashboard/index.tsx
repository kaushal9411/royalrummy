import { useQuery } from '@tanstack/react-query';
import { Users, Activity, DollarSign, AlertTriangle, Wifi, Trophy } from 'lucide-react';
import { DashboardLayout } from '@/components/layout/DashboardLayout';
import { KpiCard } from '@/components/dashboard/KpiCard';
import { RevenueChart } from '@/components/dashboard/RevenueChart';
import { LiveTablesList } from '@/components/dashboard/LiveTablesList';
import { RecentUsers } from '@/components/dashboard/RecentUsers';
import { FraudAlerts } from '@/components/dashboard/FraudAlerts';
import { api } from '@/utils/api';

interface DashboardMetrics {
  dau: number;
  mau: number;
  dau_change: number;
  revenue_today: number;
  revenue_change: number;
  active_tables: number;
  ws_connections: number;
  pending_withdrawals: number;
  open_fraud_events: number;
  revenue_7d: { date: string; revenue: number; deposits: number }[];
  active_tables_list: LiveTable[];
  recent_users: RecentUser[];
}

export default function DashboardPage() {
  const { data: metrics, isLoading } = useQuery<DashboardMetrics>({
    queryKey: ['dashboard-metrics'],
    queryFn: () => api.get('/admin/metrics/dashboard').then(r => r.data.data),
    refetchInterval: 30000, // Refresh every 30s
  });

  if (isLoading) return <DashboardLayout><div className="p-8 text-center">Loading...</div></DashboardLayout>;

  return (
    <DashboardLayout title="Dashboard">
      {/* KPI Row */}
      <div className="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-4 mb-8">
        <KpiCard
          title="Daily Active Users"
          value={metrics?.dau?.toLocaleString()}
          change={`${metrics?.dau_change > 0 ? '+' : ''}${metrics?.dau_change}%`}
          changeType={metrics?.dau_change >= 0 ? 'positive' : 'negative'}
          icon={<Users className="w-5 h-5" />}
          color="blue"
        />
        <KpiCard
          title="Revenue Today"
          value={`₹${(metrics?.revenue_today || 0).toLocaleString()}`}
          change={`${metrics?.revenue_change > 0 ? '+' : ''}${metrics?.revenue_change}%`}
          changeType={metrics?.revenue_change >= 0 ? 'positive' : 'negative'}
          icon={<DollarSign className="w-5 h-5" />}
          color="green"
        />
        <KpiCard
          title="Active Tables"
          value={metrics?.active_tables?.toString()}
          badge="LIVE"
          icon={<Activity className="w-5 h-5" />}
          color="purple"
        />
        <KpiCard
          title="WS Connections"
          value={metrics?.ws_connections?.toLocaleString()}
          badge="LIVE"
          icon={<Wifi className="w-5 h-5" />}
          color="indigo"
        />
        <KpiCard
          title="Pending Withdrawals"
          value={metrics?.pending_withdrawals?.toString()}
          alert={!!metrics?.pending_withdrawals}
          icon={<DollarSign className="w-5 h-5" />}
          color="yellow"
          href="/wallet/withdrawals"
        />
        <KpiCard
          title="Fraud Flags"
          value={metrics?.open_fraud_events?.toString()}
          alert={!!metrics?.open_fraud_events}
          icon={<AlertTriangle className="w-5 h-5" />}
          color="red"
          href="/reports/fraud"
        />
      </div>

      {/* Charts + Live Tables */}
      <div className="grid grid-cols-1 xl:grid-cols-3 gap-6 mb-6">
        <div className="xl:col-span-2">
          <RevenueChart data={metrics?.revenue_7d || []} />
        </div>
        <div>
          <LiveTablesList tables={metrics?.active_tables_list || []} />
        </div>
      </div>

      {/* Bottom Row */}
      <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
        <RecentUsers users={metrics?.recent_users || []} />
        <FraudAlerts />
      </div>
    </DashboardLayout>
  );
}
