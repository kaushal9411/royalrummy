'use client';
import { useEffect, useState, useCallback } from 'react';
import {
  getAdminWithdrawals, getPaymentStats, approveWithdrawal, rejectWithdrawal,
  type AdminTransaction, type PaymentStats,
} from '../../lib/api';
import { formatCurrency, formatDateTime } from '../../lib/utils';

type Filter = '' | 'pending' | 'success' | 'failed';

function StatusBadge({ status }: { status: string }) {
  const cfg: Record<string, { bg: string; text: string; dot: string }> = {
    pending: { bg: 'bg-accent/10',   text: 'text-accent-light',   dot: 'bg-accent' },
    success: { bg: 'bg-success/10',  text: 'text-success-light',  dot: 'bg-success' },
    failed:  { bg: 'bg-danger/10',   text: 'text-danger-light',   dot: 'bg-danger' },
  };
  const s = cfg[status] ?? { bg: 'bg-gray-500/10', text: 'text-gray-400', dot: 'bg-gray-500' };
  return (
    <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold ${s.bg} ${s.text}`}>
      <span className={`w-1.5 h-1.5 rounded-full ${s.dot}`} />
      {status}
    </span>
  );
}

export default function WithdrawalsPage() {
  const [items,   setItems]   = useState<AdminTransaction[]>([]);
  const [stats,   setStats]   = useState<PaymentStats | null>(null);
  const [filter,  setFilter]  = useState<Filter>('pending');
  const [search,  setSearch]  = useState('');
  const [loading, setLoading] = useState(true);
  const [approveTarget, setApproveTarget] = useState<AdminTransaction | null>(null);
  const [rejectTarget,  setRejectTarget]  = useState<AdminTransaction | null>(null);
  const [rejectReason,  setRejectReason]  = useState('');
  const [busy, setBusy] = useState(false);
  const [toast, setToast] = useState<{ msg: string; ok: boolean } | null>(null);

  const showToast = (msg: string, ok = true) => {
    setToast({ msg, ok });
    setTimeout(() => setToast(null), 3500);
  };

  const loadItems = useCallback(async () => {
    setLoading(true);
    try {
      setItems(await getAdminWithdrawals({ status: filter || undefined, limit: 200 }));
    } catch { showToast('Failed to load withdrawals', false); }
    finally { setLoading(false); }
  }, [filter]);

  const loadStats = useCallback(async () => {
    try { setStats(await getPaymentStats()); } catch {}
  }, []);

  useEffect(() => { loadItems(); loadStats(); }, [loadItems, loadStats]);
  useEffect(() => {
    const id = setInterval(() => { loadItems(); loadStats(); }, 30_000);
    return () => clearInterval(id);
  }, [loadItems, loadStats]);

  const doApprove = async () => {
    if (!approveTarget) return;
    setBusy(true);
    try {
      await approveWithdrawal(approveTarget.id);
      showToast('Withdrawal approved');
      setApproveTarget(null);
      loadItems(); loadStats();
    } catch { showToast('Approval failed', false); }
    finally { setBusy(false); }
  };

  const doReject = async () => {
    if (!rejectTarget) return;
    setBusy(true);
    try {
      await rejectWithdrawal(rejectTarget.id, rejectReason);
      showToast('Withdrawal rejected');
      setRejectTarget(null); setRejectReason('');
      loadItems(); loadStats();
    } catch { showToast('Rejection failed', false); }
    finally { setBusy(false); }
  };

  const filtered = items.filter(t =>
    !search || t.username?.toLowerCase().includes(search.toLowerCase()) ||
               t.email?.toLowerCase().includes(search.toLowerCase()),
  );

  const pendingTotal = items.filter(t => t.status === 'pending').reduce((s, t) => s + Number(t.amount), 0);

  return (
    <div className="min-h-screen">
      {toast && (
        <div className={`fixed top-5 right-5 z-50 flex items-center gap-2 px-4 py-3 rounded-xl border text-sm font-medium shadow-lg
                         ${toast.ok ? 'bg-success/10 border-success/30 text-success-light' : 'bg-danger/10 border-danger/30 text-danger-light'}`}>
          <span>{toast.ok ? '✓' : '✕'}</span> {toast.msg}
        </div>
      )}

      {/* Header */}
      <div className="flex items-start justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-white flex items-center gap-2">
            <span className="text-3xl">🏦</span>
            <span style={{ background: 'linear-gradient(90deg,#F87171,#FB923C)', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' }}>
              Withdrawals
            </span>
          </h1>
          <p className="text-gray-500 text-sm mt-1">Manage user withdrawal requests</p>
        </div>
        <button onClick={() => { loadItems(); loadStats(); }}
                className="flex items-center gap-2 px-4 py-2 rounded-xl border border-dark-border
                           text-gray-400 text-sm hover:bg-dark-border/40 hover:text-white transition-all">
          <span>↻</span> Refresh
        </button>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        {[
          { label: 'Pending Amount',  value: formatCurrency(stats?.pending_amount ?? 0),  icon: '⏳', color: '#F59E0B' },
          { label: 'Pending Count',   value: `${stats?.pending_count ?? 0} requests`,      icon: '📋', color: '#8B5CF6' },
          { label: 'Total Withdrawn', value: formatCurrency(stats?.total_withdrawn ?? 0), icon: '✅', color: '#10B981' },
          { label: 'Filtered Total',  value: formatCurrency(pendingTotal),                 icon: '🔍', color: '#3B82F6' },
        ].map(({ label, value, icon, color }) => (
          <div key={label} className="relative rounded-2xl p-4 border overflow-hidden"
               style={{ background: '#0F1420', borderColor: `${color}20`, boxShadow: `0 0 18px ${color}12` }}>
            <div className="absolute inset-0 opacity-5" style={{ background: `radial-gradient(circle at top right, ${color}, transparent 60%)` }} />
            <div className="relative flex items-start justify-between">
              <div>
                <p className="text-gray-500 text-xs uppercase tracking-wider mb-1">{label}</p>
                <p className="text-lg font-bold text-white">{value}</p>
              </div>
              <span className="text-2xl">{icon}</span>
            </div>
          </div>
        ))}
      </div>

      {/* Filters + Search */}
      <div className="flex flex-wrap items-center gap-3 mb-5">
        <div className="relative">
          <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500 text-sm">🔍</span>
          <input value={search} onChange={e => setSearch(e.target.value)}
                 placeholder="Search by name or email…"
                 className="pl-9 pr-4 py-2.5 rounded-xl border border-dark-border bg-dark-card
                            text-sm text-white placeholder-gray-600 focus:outline-none focus:border-primary transition-colors w-64" />
        </div>
        <div className="flex gap-1 p-1 rounded-xl border border-dark-border" style={{ background: '#0B0F1A' }}>
          {(['all', 'pending', 'success', 'failed'] as const).map(s => (
            <button key={s} onClick={() => setFilter(s === 'all' ? '' : s)}
                    className={`px-3 py-1.5 rounded-lg text-xs font-medium capitalize transition-all
                                ${(s === 'all' ? !filter : filter === s)
                                  ? 'bg-dark-card text-white border border-dark-border'
                                  : 'text-gray-500 hover:text-gray-300'}`}>
              {s}
              {s === 'pending' && (stats?.pending_count ?? 0) > 0 && (
                <span className="ml-1.5 inline-flex items-center justify-center w-4 h-4 rounded-full
                                 bg-accent text-dark-bg text-xs font-bold">
                  {stats!.pending_count}
                </span>
              )}
            </button>
          ))}
        </div>
        <p className="text-gray-600 text-xs ml-auto">{filtered.length} records</p>
      </div>

      {/* Table */}
      <div className="rounded-2xl border border-dark-border overflow-hidden" style={{ background: '#0F1420' }}>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr style={{ background: '#0B0F1A' }}>
                {['User', 'Email', 'Amount', 'Coins', 'Status', 'Requested', 'Actions'].map(h => (
                  <th key={h} className="px-5 py-3.5 text-left text-xs font-semibold text-gray-500 uppercase tracking-wider">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-dark-border">
              {loading ? (
                [...Array(5)].map((_, i) => (
                  <tr key={i}>{[...Array(7)].map((__, j) => (
                    <td key={j} className="px-5 py-4">
                      <div className="h-4 rounded bg-dark-border animate-pulse" style={{ width: `${55 + (j * 11) % 30}%` }} />
                    </td>
                  ))}</tr>
                ))
              ) : filtered.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-5 py-16 text-center">
                    <div className="flex flex-col items-center gap-3 text-gray-600">
                      <span className="text-4xl">🏦</span>
                      <p>{search ? 'No results match your search' : filter === 'pending' ? 'No pending withdrawals' : 'No records found'}</p>
                    </div>
                  </td>
                </tr>
              ) : (
                filtered.map(tx => (
                  <tr key={tx.id} className="hover:bg-white/3 transition-colors">
                    <td className="px-5 py-3.5">
                      <div className="flex items-center gap-2.5">
                        <div className="w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold flex-shrink-0"
                             style={{ background: 'rgba(239,68,68,0.12)', color: '#F87171' }}>
                          {tx.username?.[0]?.toUpperCase() ?? '?'}
                        </div>
                        <span className="text-white font-medium">{tx.username}</span>
                      </div>
                    </td>
                    <td className="px-5 py-3.5 text-gray-400 text-sm">{tx.email}</td>
                    <td className="px-5 py-3.5">
                      <span className="text-danger-light font-bold">-{formatCurrency(Number(tx.amount))}</span>
                    </td>
                    <td className="px-5 py-3.5">
                      <span className="text-accent">🪙 {tx.coins}</span>
                    </td>
                    <td className="px-5 py-3.5"><StatusBadge status={tx.status} /></td>
                    <td className="px-5 py-3.5 text-gray-500 text-xs">{formatDateTime(tx.created_at)}</td>
                    <td className="px-5 py-3.5">
                      {tx.status === 'pending' ? (
                        <div className="flex items-center gap-2">
                          <button onClick={() => setApproveTarget(tx)}
                                  className="px-3 py-1.5 rounded-lg bg-success/10 text-success-light border border-success/20
                                             text-xs font-semibold hover:bg-success/20 transition-colors">
                            ✓ Approve
                          </button>
                          <button onClick={() => { setRejectTarget(tx); setRejectReason(''); }}
                                  className="px-3 py-1.5 rounded-lg bg-danger/10 text-danger-light border border-danger/20
                                             text-xs font-semibold hover:bg-danger/20 transition-colors">
                            ✕ Reject
                          </button>
                        </div>
                      ) : <span className="text-gray-600 text-xs">—</span>}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
        {filtered.length > 0 && (
          <div className="px-5 py-3 border-t border-dark-border flex justify-between" style={{ background: '#0B0F1A' }}>
            <p className="text-gray-600 text-xs">
              {filtered.length} records · Total:
              <span className="text-danger-light font-semibold ml-1">
                {formatCurrency(filtered.reduce((s, t) => s + Number(t.amount), 0))}
              </span>
            </p>
          </div>
        )}
      </div>

      {/* Approve modal */}
      {approveTarget && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4"
             style={{ background: 'rgba(0,0,0,0.75)', backdropFilter: 'blur(4px)' }}>
          <div className="w-full max-w-sm rounded-2xl border border-dark-border p-6" style={{ background: '#0F1420' }}>
            <h3 className="text-lg font-bold text-white mb-2">Approve Withdrawal</h3>
            <p className="text-gray-400 text-sm mb-5">
              Approve <span className="text-success-light font-semibold">{formatCurrency(Number(approveTarget.amount))}</span> for{' '}
              <span className="text-white font-semibold">{approveTarget.username}</span>?
              This action cannot be undone.
            </p>
            <div className="flex gap-3">
              <button onClick={() => setApproveTarget(null)}
                      className="flex-1 px-4 py-2 rounded-lg border border-dark-border text-gray-300 text-sm hover:bg-dark-border/50 transition-colors">
                Cancel
              </button>
              <button onClick={doApprove} disabled={busy}
                      className="flex-1 px-4 py-2 rounded-lg bg-success text-white text-sm font-semibold hover:opacity-90 disabled:opacity-50 transition-colors">
                {busy ? 'Approving…' : 'Approve'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Reject modal */}
      {rejectTarget && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4"
             style={{ background: 'rgba(0,0,0,0.75)', backdropFilter: 'blur(4px)' }}>
          <div className="w-full max-w-sm rounded-2xl border border-dark-border p-6" style={{ background: '#0F1420' }}>
            <h3 className="text-lg font-bold text-white mb-2">Reject Withdrawal</h3>
            <p className="text-gray-400 text-sm mb-4">
              Reject <span className="text-danger-light font-semibold">{formatCurrency(Number(rejectTarget.amount))}</span> for{' '}
              <span className="text-white font-semibold">{rejectTarget.username}</span>?
              Their coins will be refunded.
            </p>
            <textarea value={rejectReason} onChange={e => setRejectReason(e.target.value)}
                      placeholder="Reason for rejection (optional)" rows={3}
                      className="w-full px-3 py-2.5 rounded-xl border border-dark-border bg-dark-bg
                                 text-sm text-white placeholder-gray-600 focus:outline-none focus:border-danger resize-none transition-colors mb-4" />
            <div className="flex gap-3">
              <button onClick={() => { setRejectTarget(null); setRejectReason(''); }}
                      className="flex-1 px-4 py-2 rounded-lg border border-dark-border text-gray-300 text-sm hover:bg-dark-border/50 transition-colors">
                Cancel
              </button>
              <button onClick={doReject} disabled={busy}
                      className="flex-1 px-4 py-2 rounded-lg bg-danger text-white text-sm font-semibold hover:opacity-90 disabled:opacity-50 transition-colors">
                {busy ? 'Rejecting…' : 'Reject'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
