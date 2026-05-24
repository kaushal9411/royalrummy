# Admin Panel Architecture — RummyRoyale

## 1. Next.js Admin Dashboard Structure

```
admin/src/
├── pages/
│   ├── dashboard/        index.tsx       — Platform overview KPIs
│   ├── users/
│   │   ├── index.tsx                     — User list + search
│   │   ├── [id].tsx                      — User detail
│   │   └── kyc.tsx                       — KYC review queue
│   ├── games/
│   │   ├── index.tsx                     — Active tables
│   │   ├── live.tsx                      — Live match monitor
│   │   └── history.tsx                   — Match history
│   ├── tournaments/
│   │   ├── index.tsx                     — Tournament list
│   │   ├── create.tsx                    — Create tournament
│   │   └── [id].tsx                      — Tournament management
│   ├── wallet/
│   │   ├── transactions.tsx              — Transaction log
│   │   ├── withdrawals.tsx               — Pending withdrawals
│   │   └── manual-credit.tsx             — Manual credit/debit
│   ├── reports/
│   │   ├── revenue.tsx                   — Revenue dashboard
│   │   ├── users.tsx                     — User analytics
│   │   └── fraud.tsx                     — Fraud events
│   ├── cms/
│   │   ├── banners.tsx                   — Banner management
│   │   └── notifications.tsx            — Push notification campaigns
│   └── settings/
│       ├── game-config.tsx               — Game parameters
│       ├── bonus.tsx                     — Bonus configuration
│       └── admin-users.tsx              — Admin account management
│
├── components/
│   ├── layout/           Sidebar, Header, Breadcrumb
│   ├── tables/           DataTable with sort/filter/export
│   ├── charts/           Revenue charts, funnel charts
│   ├── forms/            Reusable form components
│   └── modals/           Confirmation, user detail modals
│
├── hooks/
│   ├── useUsers.ts
│   ├── useTransactions.ts
│   └── useWebSocket.ts   — Live match monitoring
│
└── store/
    ├── authStore.ts       — Admin auth state (Zustand)
    └── notificationStore.ts
```

---

## 2. Admin RBAC (Role-Based Access Control)

```typescript
// Admin permission matrix
const PERMISSIONS = {
  // User management
  'users:read':       ['super_admin', 'admin', 'support'],
  'users:write':      ['super_admin', 'admin'],
  'users:ban':        ['super_admin', 'admin'],
  'users:delete':     ['super_admin'],

  // Wallet management
  'wallet:read':      ['super_admin', 'admin', 'finance', 'support'],
  'wallet:credit':    ['super_admin', 'finance'],
  'wallet:debit':     ['super_admin'],
  'wallet:approve_withdrawal': ['super_admin', 'finance'],

  // KYC
  'kyc:read':         ['super_admin', 'admin', 'kyc_reviewer'],
  'kyc:approve':      ['super_admin', 'admin', 'kyc_reviewer'],
  'kyc:reject':       ['super_admin', 'admin', 'kyc_reviewer'],

  // Game management
  'games:read':       ['super_admin', 'admin', 'support'],
  'games:cancel':     ['super_admin', 'admin'],
  'games:config':     ['super_admin', 'admin'],

  // Fraud
  'fraud:read':       ['super_admin', 'admin', 'fraud_analyst'],
  'fraud:resolve':    ['super_admin', 'admin', 'fraud_analyst'],

  // Reports
  'reports:revenue':  ['super_admin', 'admin', 'finance'],
  'reports:users':    ['super_admin', 'admin'],

  // CMS
  'cms:write':        ['super_admin', 'admin', 'content_manager'],
  'notifications:send': ['super_admin', 'admin', 'marketing'],
};
```

---

## 3. Admin Dashboard Components

### KPI Overview
```tsx
// admin/src/pages/dashboard/index.tsx
export default function DashboardPage() {
  const { data: metrics } = useQuery(['dashboard-metrics'], fetchDashboardMetrics);

  return (
    <DashboardLayout>
      {/* Top KPIs */}
      <KpiGrid>
        <KpiCard title="Active Users (24h)" value={metrics?.dau} trend="+12%" />
        <KpiCard title="Revenue Today" value={`₹${metrics?.revenue_today}`} trend="+8%" />
        <KpiCard title="Active Tables" value={metrics?.active_tables} status="live" />
        <KpiCard title="WS Connections" value={metrics?.websocket_connections} status="live" />
        <KpiCard title="Pending Withdrawals" value={metrics?.pending_withdrawals} alert />
        <KpiCard title="Fraud Flags" value={metrics?.open_fraud_events} alert />
      </KpiGrid>

      {/* Revenue Chart */}
      <RevenueChart data={metrics?.revenue_7d} />

      {/* Live Game Monitor */}
      <LiveTablesList tables={metrics?.active_tables_list} />

      {/* Recent Registrations */}
      <RecentUsers users={metrics?.recent_users} />
    </DashboardLayout>
  );
}
```

### User Management
```tsx
// Search, filter, paginate users
// View: profile, wallet, game history, devices, fraud flags
// Actions: suspend, ban, credit wallet, force KYC, view sessions

interface UserDetailProps {
  user: User;
}

function UserDetail({ user }: UserDetailProps) {
  return (
    <div>
      <UserProfileCard user={user} />
      <WalletCard userId={user.id} />
      <KycStatusCard kyc={user.kyc} />
      <GameHistoryTable userId={user.id} />
      <TransactionHistory userId={user.id} />
      <DeviceList devices={user.devices} />
      <FraudEventList userId={user.id} />
      <AdminActionBar
        onSuspend={() => suspendUser(user.id)}
        onBan={() => banUser(user.id)}
        onCreditWallet={() => setShowCreditModal(true)}
      />
    </div>
  );
}
```

---

## 4. Live Match Monitor

```tsx
// Real-time game monitoring via WebSocket
function LiveMatchMonitor() {
  const [tables, setTables] = useState<LiveTable[]>([]);

  useEffect(() => {
    const socket = io('/admin', {
      auth: { token: adminToken },
    });

    socket.on('live_tables_update', (data: LiveTable[]) => {
      setTables(data);
    });

    socket.on('fraud_alert', (alert: FraudAlert) => {
      showFraudAlertToast(alert);
    });

    return () => socket.disconnect();
  }, []);

  return (
    <div>
      {tables.map(table => (
        <LiveTableCard
          key={table.id}
          table={table}
          onSpectate={() => navigateToSpectate(table.id)}
          onCancel={() => cancelTable(table.id)}
          onFlag={() => flagTableForReview(table.id)}
        />
      ))}
    </div>
  );
}
```

---

## 5. Withdrawal Management

```tsx
// Process pending withdrawals with KYC verification
function WithdrawalQueue() {
  const { data: withdrawals } = useQuery(['pending-withdrawals'], fetchPending);

  return (
    <DataTable
      columns={[
        { key: 'user', label: 'User' },
        { key: 'amount', label: 'Amount', render: (v) => `₹${v}` },
        { key: 'bank_account', label: 'Bank Account' },
        { key: 'kyc_status', label: 'KYC', render: KycBadge },
        { key: 'created_at', label: 'Requested' },
        {
          key: 'actions',
          label: 'Actions',
          render: (_, row) => (
            <>
              <Button variant="success" onClick={() => approveWithdrawal(row.id)}>
                Approve
              </Button>
              <Button variant="danger" onClick={() => rejectWithdrawal(row.id)}>
                Reject
              </Button>
            </>
          ),
        },
      ]}
      data={withdrawals}
    />
  );
}
```

---

## 6. Push Notification Campaign Builder

```tsx
function NotificationCampaign() {
  const [form, setForm] = useState({
    title: '',
    body: '',
    target: 'all',  // all | segment | specific_users
    segment: '',    // inactive_7d | high_value | new_users
    schedule: 'now',
    scheduled_at: '',
  });

  const segments = [
    { value: 'all', label: 'All Users', estimated: '1,24,567' },
    { value: 'inactive_3d', label: 'Inactive 3+ Days', estimated: '23,456' },
    { value: 'inactive_7d', label: 'Inactive 7+ Days', estimated: '12,234' },
    { value: 'high_value', label: 'Deposited > ₹5000', estimated: '8,765' },
    { value: 'new_users_7d', label: 'Joined Last 7 Days', estimated: '4,321' },
    { value: 'tournament_players', label: 'Tournament Players', estimated: '6,543' },
  ];

  return (
    <form onSubmit={handleSubmit}>
      <Input label="Title" maxLength={50} {...bindField('title')} />
      <Textarea label="Body" maxLength={150} {...bindField('body')} />
      <Select label="Target Audience" options={segments} {...bindField('target')} />
      <RadioGroup label="Schedule" options={['Send Now', 'Schedule']} {...bindField('schedule')} />
      {form.schedule === 'scheduled' && (
        <DateTimePicker {...bindField('scheduled_at')} />
      )}
      <PreviewCard title={form.title} body={form.body} />
      <Button type="submit">Send Campaign</Button>
    </form>
  );
}
```

---

## 7. CMS Banner Management

```typescript
// Banner CRUD with preview
interface Banner {
  id: string;
  title: string;
  image_url: string;
  link_type: 'game' | 'tournament' | 'external' | 'none';
  link_url?: string;
  screen: 'home' | 'lobby' | 'tournament' | 'wallet';
  position: number;
  is_active: boolean;
  starts_at?: Date;
  ends_at?: Date;
}

// Admin API
POST   /admin/cms/banners          Create banner
PATCH  /admin/cms/banners/:id      Update banner
DELETE /admin/cms/banners/:id      Delete banner
PATCH  /admin/cms/banners/reorder  Reorder banners (drag & drop)
```

---

## 8. Revenue Reports

```typescript
// Revenue report aggregation query
SELECT
  DATE_TRUNC('day', created_at) as date,
  SUM(CASE WHEN type = 'game_entry' THEN ABS(amount) ELSE 0 END) as gross_entry_fees,
  SUM(CASE WHEN type = 'game_win' THEN amount ELSE 0 END) as gross_payouts,
  SUM(CASE WHEN type = 'platform_fee' THEN ABS(amount) ELSE 0 END) as net_revenue,
  COUNT(DISTINCT user_id) FILTER (WHERE type = 'deposit') as depositing_users,
  SUM(CASE WHEN type = 'deposit' THEN amount ELSE 0 END) as total_deposits,
  SUM(CASE WHEN type = 'withdraw' THEN amount ELSE 0 END) as total_withdrawals
FROM transactions
WHERE created_at >= NOW() - INTERVAL '30 days'
GROUP BY 1
ORDER BY 1 DESC;
```
