import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Search, Filter, UserCheck, UserX, Eye } from 'lucide-react';
import { DashboardLayout } from '@/components/layout/DashboardLayout';
import { DataTable } from '@/components/tables/DataTable';
import { Badge } from '@/components/ui/Badge';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { useRouter } from 'next/router';
import { api } from '@/utils/api';
import { format } from 'date-fns';

interface User {
  id: string;
  username: string;
  phone: string;
  email: string;
  status: 'active' | 'suspended' | 'banned';
  kyc_status: 'pending' | 'verified' | 'rejected';
  balance_cash: number;
  total_games: number;
  wins: number;
  created_at: string;
  last_login_at: string;
}

const STATUS_COLORS = {
  active: 'green',
  suspended: 'yellow',
  banned: 'red',
};

const KYC_COLORS = {
  pending: 'gray',
  verified: 'green',
  rejected: 'red',
};

export default function UsersPage() {
  const router = useRouter();
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [kycFilter, setKycFilter] = useState('');
  const [page, setPage] = useState(1);

  const { data, isLoading, refetch } = useQuery({
    queryKey: ['users', search, statusFilter, kycFilter, page],
    queryFn: () =>
      api.get('/admin/users', {
        params: { search, status: statusFilter, kyc_status: kycFilter, page, limit: 25 },
      }).then(r => r.data),
    keepPreviousData: true,
  });

  const columns = [
    {
      header: 'User',
      cell: (row: User) => (
        <div>
          <p className="font-medium text-gray-900">{row.username}</p>
          <p className="text-sm text-gray-500">{row.phone}</p>
        </div>
      ),
    },
    {
      header: 'Status',
      cell: (row: User) => (
        <Badge color={STATUS_COLORS[row.status]}>{row.status}</Badge>
      ),
    },
    {
      header: 'KYC',
      cell: (row: User) => (
        <Badge color={KYC_COLORS[row.kyc_status]}>{row.kyc_status}</Badge>
      ),
    },
    {
      header: 'Balance',
      cell: (row: User) => <span className="font-mono">₹{(+row.balance_cash).toFixed(2)}</span>,
    },
    {
      header: 'Games / Wins',
      cell: (row: User) => (
        <span>{row.total_games} / {row.wins}</span>
      ),
    },
    {
      header: 'Joined',
      cell: (row: User) => format(new Date(row.created_at), 'dd MMM yyyy'),
    },
    {
      header: 'Last Active',
      cell: (row: User) =>
        row.last_login_at ? format(new Date(row.last_login_at), 'dd MMM HH:mm') : '—',
    },
    {
      header: 'Actions',
      cell: (row: User) => (
        <div className="flex gap-2">
          <Button
            size="sm"
            variant="outline"
            onClick={() => router.push(`/users/${row.id}`)}
          >
            <Eye className="w-3 h-3 mr-1" />
            View
          </Button>
        </div>
      ),
    },
  ];

  return (
    <DashboardLayout title="User Management">
      {/* Filters */}
      <div className="flex flex-wrap gap-3 mb-6">
        <div className="relative flex-1 min-w-64">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
          <Input
            className="pl-9"
            placeholder="Search username, phone, email..."
            value={search}
            onChange={e => { setSearch(e.target.value); setPage(1); }}
          />
        </div>
        <select
          className="border rounded-lg px-3 py-2 text-sm bg-white"
          value={statusFilter}
          onChange={e => setStatusFilter(e.target.value)}
        >
          <option value="">All Status</option>
          <option value="active">Active</option>
          <option value="suspended">Suspended</option>
          <option value="banned">Banned</option>
        </select>
        <select
          className="border rounded-lg px-3 py-2 text-sm bg-white"
          value={kycFilter}
          onChange={e => setKycFilter(e.target.value)}
        >
          <option value="">All KYC</option>
          <option value="pending">Pending</option>
          <option value="verified">Verified</option>
          <option value="rejected">Rejected</option>
        </select>
        <Button variant="outline" onClick={() => refetch()}>
          <Filter className="w-4 h-4 mr-1" />
          Refresh
        </Button>
      </div>

      {/* Stats row */}
      <div className="grid grid-cols-4 gap-4 mb-6">
        {[
          { label: 'Total Users', value: data?.pagination?.total?.toLocaleString() || '—' },
          { label: 'Active Today', value: data?.meta?.active_today || '—' },
          { label: 'Pending KYC', value: data?.meta?.pending_kyc || '—' },
          { label: 'Suspended', value: data?.meta?.suspended || '—' },
        ].map(stat => (
          <div key={stat.label} className="bg-white rounded-xl p-4 shadow-sm border">
            <p className="text-sm text-gray-500">{stat.label}</p>
            <p className="text-2xl font-bold text-gray-900">{stat.value}</p>
          </div>
        ))}
      </div>

      <DataTable
        columns={columns}
        data={data?.data || []}
        isLoading={isLoading}
        pagination={data?.pagination}
        onPageChange={setPage}
      />
    </DashboardLayout>
  );
}
