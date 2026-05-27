'use client';

import { useState, useEffect, useCallback } from 'react';
import { format } from 'date-fns';
import {
  getPaymentStats, getAdminTransactions, getAdminWithdrawals,
  getAdminGameBets, approveWithdrawal, rejectWithdrawal,
  type PaymentStats, type AdminTransaction, type GameBet,
} from '../../lib/api';

// ── Stat card ──────────────────────────────────────────────────────────────────
function StatCard({
  label, value, icon, gradient, glow, sub,
}: {
  label: string; value: string; icon: string;
  gradient: string; glow: string; sub?: string;
}) {
  return (
    <div className="relative rounded-2xl p-5 border border-dark-border overflow-hidden"
      style={{ background: 'var(--card)', boxShadow: `0 0 24px ${glow}` }}>
      <div className={`absolute inset-0 bg-gradient-to-br ${gradient} opacity-10`} />
      <div className="relative z-10 flex items-start justify-between">
        <div>
          <p className="text-gray-400 text-xs font-medium uppercase tracking-wider mb-1">{label}</p>
          <p className="text-2xl font-bold text-white">{value}</p>
          {sub && <p className="text-gray-500 text-xs mt-1">{sub}</p>}
        </div>
        <span className="text-3xl">{icon}</span>
      </div>
    </div>
  );
}

// ── Status badge ───────────────────────────────────────────────────────────────
function StatusBadge({ status }: { status: string }) {
  const cfg: Record<string, { bg: string; text: string; dot: string }> = {
    success:  { bg: 'bg-primary/10', text: 'text-primary',     dot: 'bg-primary' },
    pending:  { bg: 'bg-accent/10',  text: 'text-accent',      dot: 'bg-accent' },
    failed:   { bg: 'bg-danger/10',  text: 'text-danger',      dot: 'bg-danger' },
    escrowed: { bg: 'bg-blue-500/10',text: 'text-blue-400',    dot: 'bg-blue-400' },
    won:      { bg: 'bg-primary/10', text: 'text-primary',     dot: 'bg-primary' },
    lost:     { bg: 'bg-danger/10',  text: 'text-danger',      dot: 'bg-danger' },
    refunded: { bg: 'bg-gray-500/10',text: 'text-gray-400',    dot: 'bg-gray-500' },
  };
  const s = cfg[status] ?? { bg: 'bg-gray-700/30', text: 'text-gray-400', dot: 'bg-gray-500' };
  return (
    <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold ${s.bg} ${s.text}`}>
      <span className={`w-1.5 h-1.5 rounded-full ${s.dot}`} />
      {status}
    </span>
  );
}

// ── Loading skeleton row ───────────────────────────────────────────────────────
function SkeletonRow({ cols }: { cols: number }) {
  return (
    <tr>
      {Array.from({ length: cols }).map((_, i) => (
        <td key={i} className="px-5 py-3">
          <div className="h-4 rounded bg-dark-border animate-pulse" style={{ width: `${60 + (i * 17) % 30}%` }} />
        </td>
      ))}
    </tr>
  );
}

// ── Confirm modal ──────────────────────────────────────────────────────────────
function ConfirmModal({
  title, message, confirmLabel, confirmClass, onConfirm, onCancel, children,
}: {
  title: string; message?: string; confirmLabel: string; confirmClass: string;
  onConfirm: () => void; onCancel: () => void; children?: React.ReactNode;
}) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4"
      style={{ background: 'rgba(0,0,0,0.7)', backdropFilter: 'blur(4px)' }}>
      <div className="w-full max-w-md rounded-2xl border border-dark-border p-6"
        style={{ background: 'var(--card)' }}>
        <h3 className="text-lg font-bold text-white mb-2">{title}</h3>
        {message && <p className="text-gray-400 text-sm mb-4">{message}</p>}
        {children}
        <div className="flex gap-3 mt-4">
          <button onClick={onCancel}
            className="flex-1 px-4 py-2 rounded-lg border border-dark-border text-gray-300 text-sm
                       hover:bg-dark-border/50 transition-colors">
            Cancel
          </button>
          <button onClick={onConfirm}
            className={`flex-1 px-4 py-2 rounded-lg text-white text-sm font-semibold transition-colors ${confirmClass}`}>
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Main page ──────────────────────────────────────────────────────────────────
export default function PaymentManagement() {
  const [tab, setTab]               = useState<'addmoney' | 'withdrawals' | 'bets'>('addmoney');
  const [stats, setStats]           = useState<PaymentStats | null>(null);
  const [transactions, setTxns]     = useState<AdminTransaction[]>([]);
  const [withdrawals, setWithdraws] = useState<AdminTransaction[]>([]);
  const [gameBets, setGameBets]     = useState<GameBet[]>([]);
  const [wFilter, setWFilter]       = useState<string>('pending');
  const [betFilter, setBetFilter]   = useState<string>('');
  const [search, setSearch]         = useState('');
  const [loading, setLoading]       = useState(false);
  const [statsLoading, setStatsL]   = useState(true);

  const [approveTarget, setApproveTarget] = useState<AdminTransaction | null>(null);
  const [rejectTarget,  setRejectTarget]  = useState<AdminTransaction | null>(null);
  const [rejectReason,  setRejectReason]  = useState('');
  const [actionLoading, setActionL]       = useState(false);
  const [toast, setToast]                 = useState<{ msg: string; ok: boolean } | null>(null);

  const showToast = (msg: string, ok = true) => {
    setToast({ msg, ok });
    setTimeout(() => setToast(null), 3500);
  };

  const loadStats = useCallback(async () => {
    setStatsL(true);
    try { setStats(await getPaymentStats()); } catch {}
    finally { setStatsL(false); }
  }, []);

  const loadData = useCallback(async () => {
    setLoading(true);
    try {
      if (tab === 'addmoney') {
        setTxns(await getAdminTransactions({ limit: 100 }));
      } else if (tab === 'withdrawals') {
        setWithdraws(await getAdminWithdrawals({ status: wFilter || undefined, limit: 100 }));
      } else {
        setGameBets(await getAdminGameBets({ status: betFilter || undefined, limit: 100 }));
      }
    } catch {
      showToast('Failed to load data', false);
    } finally {
      setLoading(false);
    }
  }, [tab, wFilter, betFilter]);

  useEffect(() => { loadStats(); }, [loadStats]);
  useEffect(() => { loadData(); }, [loadData]);

  // Auto-refresh every 30 s so balance, withdrawals, and stats stay current
  useEffect(() => {
    const id = setInterval(() => { loadStats(); loadData(); }, 30_000);
    return () => clearInterval(id);
  }, [loadStats, loadData]);

  const handleApprove = async () => {
    if (!approveTarget) return;
    setActionL(true);
    try {
      await approveWithdrawal(approveTarget.id);
      showToast('Withdrawal approved successfully');
      setApproveTarget(null);
      loadData(); loadStats();
    } catch {
      showToast('Failed to approve withdrawal', false);
    } finally { setActionL(false); }
  };

  const handleReject = async () => {
    if (!rejectTarget) return;
    setActionL(true);
    try {
      await rejectWithdrawal(rejectTarget.id, rejectReason);
      showToast('Withdrawal rejected');
      setRejectTarget(null);
      setRejectReason('');
      loadData(); loadStats();
    } catch {
      showToast('Failed to reject withdrawal', false);
    } finally { setActionL(false); }
  };

  const txFiltered = (tab === 'addmoney' ? transactions : withdrawals).filter(tx =>
    !search || tx.username?.toLowerCase().includes(search.toLowerCase())
               || tx.email?.toLowerCase().includes(search.toLowerCase()),
  );

  const betsFiltered = gameBets.filter(b =>
    !search || b.username?.toLowerCase().includes(search.toLowerCase())
               || b.email?.toLowerCase().includes(search.toLowerCase())
               || b.room_code?.toLowerCase().includes(search.toLowerCase()),
  );

  const fmt = (n: number) => `₹${Number(n).toLocaleString('en-IN', { minimumFractionDigits: 2 })}`;

  return (
    <div className="min-h-screen p-6 md:p-8">

      {/* Toast */}
      {toast && (
        <div className={`fixed top-5 right-5 z-50 flex items-center gap-2 px-4 py-3 rounded-xl
                         border text-sm font-medium shadow-lg
                         ${toast.ok
                           ? 'bg-primary/10 border-primary/30 text-primary'
                           : 'bg-danger/10 border-danger/30 text-danger'}`}>
          <span>{toast.ok ? '✓' : '✕'}</span>{toast.msg}
        </div>
      )}

      {/* Page header */}
      <div className="flex items-start justify-between mb-8">
        <div>
          <h1 className="text-3xl font-bold text-white flex items-center gap-3">
            <span className="text-4xl">💳</span>
            <span style={{
              background: 'linear-gradient(90deg,#238636,#2EA043)',
              WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent',
            }}>Payment Management</span>
          </h1>
          <p className="text-gray-500 text-sm mt-1">Monitor transactions, withdrawals &amp; game bets</p>
        </div>
        <button onClick={() => { loadData(); loadStats(); }}
          className="flex items-center gap-2 px-4 py-2 rounded-xl border border-dark-border
                     text-gray-300 text-sm hover:bg-dark-border/40 transition-colors">
          <span className="text-base">↻</span> Refresh
        </button>
      </div>

      {/* Stats — row 1: deposits & withdrawals */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-4">
        {statsLoading ? (
          Array.from({ length: 4 }).map((_, i) => (
            <div key={i} className="h-24 rounded-2xl bg-dark-card border border-dark-border animate-pulse" />
          ))
        ) : stats ? (
          <>
            <StatCard label="Total Revenue"      value={fmt(stats.total_revenue)}
              icon="💰" gradient="from-emerald-500 to-green-700" glow="rgba(34,197,94,0.2)"
              sub={`${stats.total_add_count} deposits`} />
            <StatCard label="Today's Revenue"    value={fmt(stats.today_revenue)}
              icon="📅" gradient="from-blue-500 to-indigo-700" glow="rgba(59,130,246,0.2)" />
            <StatCard label="Pending Withdrawals" value={fmt(stats.pending_amount)}
              icon="⏳" gradient="from-amber-400 to-orange-600" glow="rgba(245,158,11,0.2)"
              sub={`${stats.pending_count} request${stats.pending_count !== 1 ? 's' : ''}`} />
            <StatCard label="Total Withdrawn"    value={fmt(stats.total_withdrawn)}
              icon="📤" gradient="from-rose-500 to-red-700" glow="rgba(239,68,68,0.2)" />
          </>
        ) : null}
      </div>

      {/* Stats — row 2: bet activity */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        {statsLoading ? (
          Array.from({ length: 4 }).map((_, i) => (
            <div key={i} className="h-24 rounded-2xl bg-dark-card border border-dark-border animate-pulse" />
          ))
        ) : stats ? (
          <>
            <StatCard label="Total Bet Volume"   value={fmt(stats.total_bet_escrowed)}
              icon="🎲" gradient="from-violet-500 to-purple-700" glow="rgba(139,92,246,0.2)"
              sub={`${stats.total_bet_games} games settled`} />
            <StatCard label="Today's Bet Volume" value={fmt(stats.today_bet_volume)}
              icon="🔥" gradient="from-orange-400 to-red-600" glow="rgba(249,115,22,0.2)" />
            <StatCard label="Total Bet Payouts"  value={fmt(stats.total_bet_payouts)}
              icon="🏆" gradient="from-yellow-400 to-amber-600" glow="rgba(234,179,8,0.2)"
              sub="Paid to winners" />
            <StatCard label="Net Bet Activity"
              value={fmt(Math.abs(stats.total_bet_escrowed - stats.total_bet_payouts))}
              icon="📊" gradient="from-cyan-400 to-teal-600" glow="rgba(6,182,212,0.2)"
              sub="Escrowed vs paid out" />
          </>
        ) : null}
      </div>

      {/* Tabs */}
      <div className="flex gap-1 p-1 rounded-xl border border-dark-border mb-6 w-fit"
        style={{ background: 'var(--surface)' }}>
        {([
          ['addmoney',   '💸 Add Money'],
          ['withdrawals','🏦 Withdrawals'],
          ['bets',       '🎲 Bet History'],
        ] as const).map(([key, label]) => (
          <button key={key} onClick={() => setTab(key)}
            className={`px-5 py-2 rounded-lg text-sm font-medium transition-all
              ${tab === key
                ? 'bg-primary text-white shadow'
                : 'text-gray-400 hover:text-gray-200'}`}>
            {label}
            {key === 'withdrawals' && stats && stats.pending_count > 0 && (
              <span className="ml-2 inline-flex items-center justify-center w-5 h-5 rounded-full
                               bg-accent text-dark-bg text-xs font-bold">
                {stats.pending_count}
              </span>
            )}
          </button>
        ))}
      </div>

      {/* Controls */}
      <div className="flex flex-wrap items-center gap-3 mb-4">
        <div className="relative flex-1 min-w-48">
          <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500 text-sm">🔍</span>
          <input value={search} onChange={e => setSearch(e.target.value)}
            placeholder={tab === 'bets' ? 'Search by name, email, or room code…' : 'Search by name or email…'}
            className="w-full pl-9 pr-4 py-2 rounded-xl border border-dark-border bg-dark-card
                       text-sm text-white placeholder-gray-600 focus:outline-none focus:border-primary
                       transition-colors" />
        </div>

        {tab === 'withdrawals' && (
          <div className="flex gap-1 p-1 rounded-xl border border-dark-border"
            style={{ background: 'var(--surface)' }}>
            {(['all', 'pending', 'success', 'failed'] as const).map(s => (
              <button key={s} onClick={() => setWFilter(s === 'all' ? '' : s)}
                className={`px-3 py-1.5 rounded-lg text-xs font-medium capitalize transition-all
                  ${(s === 'all' ? !wFilter : wFilter === s)
                    ? 'bg-dark-card text-white border border-dark-border'
                    : 'text-gray-500 hover:text-gray-300'}`}>
                {s}
              </button>
            ))}
          </div>
        )}

        {tab === 'bets' && (
          <div className="flex gap-1 p-1 rounded-xl border border-dark-border"
            style={{ background: 'var(--surface)' }}>
            {(['all', 'escrowed', 'won', 'lost', 'refunded'] as const).map(s => (
              <button key={s} onClick={() => setBetFilter(s === 'all' ? '' : s)}
                className={`px-3 py-1.5 rounded-lg text-xs font-medium capitalize transition-all
                  ${(s === 'all' ? !betFilter : betFilter === s)
                    ? 'bg-dark-card text-white border border-dark-border'
                    : 'text-gray-500 hover:text-gray-300'}`}>
                {s}
              </button>
            ))}
          </div>
        )}

        <p className="text-gray-600 text-xs ml-auto">
          {tab === 'bets' ? betsFiltered.length : txFiltered.length} record{(tab === 'bets' ? betsFiltered.length : txFiltered.length) !== 1 ? 's' : ''}
        </p>
      </div>

      {/* Table */}
      <div className="rounded-2xl border border-dark-border overflow-hidden"
        style={{ background: 'var(--card)' }}>
        <div className="overflow-x-auto">

          {/* ── Add Money & Withdrawals table ── */}
          {tab !== 'bets' && (
            <table className="w-full text-sm">
              <thead>
                <tr style={{ background: 'var(--surface)' }}>
                  <th className="px-5 py-3.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wider">User</th>
                  <th className="px-5 py-3.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wider">Email</th>
                  <th className="px-5 py-3.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wider">Amount</th>
                  <th className="px-5 py-3.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wider">Coins</th>
                  <th className="px-5 py-3.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wider">Status</th>
                  <th className="px-5 py-3.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wider">Date</th>
                  {tab === 'withdrawals' && (
                    <th className="px-5 py-3.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wider">Actions</th>
                  )}
                </tr>
              </thead>
              <tbody className="divide-y divide-dark-border">
                {loading ? (
                  Array.from({ length: 6 }).map((_, i) => (
                    <SkeletonRow key={i} cols={tab === 'withdrawals' ? 7 : 6} />
                  ))
                ) : txFiltered.length === 0 ? (
                  <tr>
                    <td colSpan={tab === 'withdrawals' ? 7 : 6} className="px-5 py-16 text-center">
                      <div className="flex flex-col items-center gap-3 text-gray-600">
                        <span className="text-4xl">{tab === 'addmoney' ? '💸' : '🏦'}</span>
                        <p className="font-medium">{search ? 'No results match your search' : 'No records found'}</p>
                        {search && <button onClick={() => setSearch('')} className="text-xs text-primary hover:underline">Clear search</button>}
                      </div>
                    </td>
                  </tr>
                ) : (
                  txFiltered.map((tx, i) => (
                    <tr key={tx.id} className="group hover:bg-dark-border/20 transition-colors">
                      <td className="px-5 py-3.5">
                        <div className="flex items-center gap-2.5">
                          <div className="w-7 h-7 rounded-full bg-primary/15 border border-primary/20
                                          flex items-center justify-center text-xs font-bold text-primary flex-shrink-0">
                            {tx.username?.[0]?.toUpperCase() ?? '?'}
                          </div>
                          <span className="text-white font-medium">{tx.username}</span>
                        </div>
                      </td>
                      <td className="px-5 py-3.5 text-gray-400">{tx.email}</td>
                      <td className="px-5 py-3.5">
                        <span className={`font-bold ${tab === 'addmoney' ? 'text-primary' : 'text-danger'}`}>
                          {tab === 'addmoney' ? '+' : '-'}₹{Number(tx.amount).toFixed(2)}
                        </span>
                      </td>
                      <td className="px-5 py-3.5"><span className="text-accent font-medium">🪙 {tx.coins}</span></td>
                      <td className="px-5 py-3.5"><StatusBadge status={tx.status} /></td>
                      <td className="px-5 py-3.5 text-gray-500 text-xs">
                        {format(new Date(tx.created_at), 'MMM dd, yyyy')}<br />
                        <span className="text-gray-600">{format(new Date(tx.created_at), 'HH:mm')}</span>
                      </td>
                      {tab === 'withdrawals' && (
                        <td className="px-5 py-3.5">
                          {tx.status === 'pending' ? (
                            <div className="flex items-center gap-2">
                              <button onClick={() => setApproveTarget(tx)}
                                className="px-3 py-1.5 rounded-lg bg-primary/10 text-primary border border-primary/20
                                           text-xs font-semibold hover:bg-primary/20 transition-colors">
                                ✓ Approve
                              </button>
                              <button onClick={() => { setRejectTarget(tx); setRejectReason(''); }}
                                className="px-3 py-1.5 rounded-lg bg-danger/10 text-danger border border-danger/20
                                           text-xs font-semibold hover:bg-danger/20 transition-colors">
                                ✕ Reject
                              </button>
                            </div>
                          ) : (
                            <span className="text-gray-600 text-xs">—</span>
                          )}
                        </td>
                      )}
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          )}

          {/* ── Bet History table ── */}
          {tab === 'bets' && (
            <table className="w-full text-sm">
              <thead>
                <tr style={{ background: 'var(--surface)' }}>
                  <th className="px-5 py-3.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wider">Player</th>
                  <th className="px-5 py-3.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wider">Room</th>
                  <th className="px-5 py-3.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wider">Seat</th>
                  <th className="px-5 py-3.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wider">Bet</th>
                  <th className="px-5 py-3.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wider">Outcome</th>
                  <th className="px-5 py-3.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wider">Placed</th>
                  <th className="px-5 py-3.5 text-left text-xs font-semibold text-gray-400 uppercase tracking-wider">Settled</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-dark-border">
                {loading ? (
                  Array.from({ length: 6 }).map((_, i) => <SkeletonRow key={i} cols={7} />)
                ) : betsFiltered.length === 0 ? (
                  <tr>
                    <td colSpan={7} className="px-5 py-16 text-center">
                      <div className="flex flex-col items-center gap-3 text-gray-600">
                        <span className="text-4xl">🎲</span>
                        <p className="font-medium">{search ? 'No results match your search' : 'No bet records found'}</p>
                        {search && <button onClick={() => setSearch('')} className="text-xs text-primary hover:underline">Clear search</button>}
                      </div>
                    </td>
                  </tr>
                ) : (
                  betsFiltered.map((bet) => (
                    <tr key={bet.id} className="hover:bg-dark-border/20 transition-colors">
                      <td className="px-5 py-3.5">
                        <div className="flex items-center gap-2.5">
                          <div className="w-7 h-7 rounded-full bg-violet-500/15 border border-violet-500/20
                                          flex items-center justify-center text-xs font-bold text-violet-400 flex-shrink-0">
                            {bet.username?.[0]?.toUpperCase() ?? '?'}
                          </div>
                          <div>
                            <p className="text-white font-medium text-sm">{bet.username}</p>
                            <p className="text-gray-600 text-xs">{bet.email}</p>
                          </div>
                        </div>
                      </td>
                      <td className="px-5 py-3.5">
                        <span className="font-mono text-accent text-sm font-bold">{bet.room_code}</span>
                        <p className="text-gray-600 text-xs mt-0.5">₹{Number(bet.room_bet_amount).toFixed(0)}/player</p>
                      </td>
                      <td className="px-5 py-3.5">
                        <span className="text-gray-300 font-medium">#{bet.seat}</span>
                      </td>
                      <td className="px-5 py-3.5">
                        <span className="text-white font-bold">₹{Number(bet.amount).toFixed(2)}</span>
                      </td>
                      <td className="px-5 py-3.5"><StatusBadge status={bet.status} /></td>
                      <td className="px-5 py-3.5 text-gray-500 text-xs">
                        {format(new Date(bet.created_at), 'MMM dd, yyyy')}<br />
                        <span className="text-gray-600">{format(new Date(bet.created_at), 'HH:mm')}</span>
                      </td>
                      <td className="px-5 py-3.5 text-gray-500 text-xs">
                        {bet.settled_at
                          ? <>{format(new Date(bet.settled_at), 'MMM dd, yyyy')}<br /><span className="text-gray-600">{format(new Date(bet.settled_at), 'HH:mm')}</span></>
                          : <span className="text-gray-600">—</span>}
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          )}
        </div>

        {/* Footer */}
        {((tab === 'bets' ? betsFiltered.length : txFiltered.length) > 0) && (
          <div className="px-5 py-3 border-t border-dark-border flex items-center justify-between"
            style={{ background: 'var(--surface)' }}>
            <p className="text-gray-600 text-xs">
              Showing <span className="text-gray-400 font-medium">
                {tab === 'bets' ? betsFiltered.length : txFiltered.length}
              </span> records
            </p>
            {tab === 'addmoney' && (
              <p className="text-gray-600 text-xs">
                Total: <span className="text-primary font-semibold">
                  ₹{txFiltered.reduce((s, t) => s + Number(t.amount), 0).toFixed(2)}
                </span>
              </p>
            )}
            {tab === 'bets' && (
              <p className="text-gray-600 text-xs">
                Total volume: <span className="text-violet-400 font-semibold">
                  ₹{betsFiltered.reduce((s, b) => s + Number(b.amount), 0).toFixed(2)}
                </span>
              </p>
            )}
          </div>
        )}
      </div>

      {/* Approve modal */}
      {approveTarget && (
        <ConfirmModal
          title="Approve Withdrawal"
          message={`Approve ₹${Number(approveTarget.amount).toFixed(2)} for ${approveTarget.username}? This cannot be undone.`}
          confirmLabel={actionLoading ? 'Approving…' : 'Approve'}
          confirmClass="bg-primary hover:bg-primary-light disabled:opacity-50"
          onConfirm={handleApprove}
          onCancel={() => setApproveTarget(null)}
        />
      )}

      {/* Reject modal */}
      {rejectTarget && (
        <ConfirmModal
          title="Reject Withdrawal"
          message={`Reject ₹${Number(rejectTarget.amount).toFixed(2)} for ${rejectTarget.username}? Their coins will be refunded.`}
          confirmLabel={actionLoading ? 'Rejecting…' : 'Reject'}
          confirmClass="bg-danger hover:opacity-80 disabled:opacity-50"
          onConfirm={handleReject}
          onCancel={() => { setRejectTarget(null); setRejectReason(''); }}
        >
          <textarea
            value={rejectReason}
            onChange={e => setRejectReason(e.target.value)}
            placeholder="Reason for rejection (optional)"
            rows={3}
            className="w-full px-3 py-2.5 rounded-xl border border-dark-border bg-dark-bg
                       text-sm text-white placeholder-gray-600 focus:outline-none
                       focus:border-danger resize-none transition-colors"
          />
        </ConfirmModal>
      )}
    </div>
  );
}
