'use client';
import { useEffect, useState, useCallback } from 'react';
import { getUsers, banUser, unbanUser, AdminUser } from '../../lib/api';
import { formatDate, truncate } from '../../lib/utils';

function StatusBadge({ active }: { active: boolean }) {
  return (
    <span className={`inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-xs font-semibold
                      ${active ? 'bg-success/10 text-success-light' : 'bg-danger/10 text-danger-light'}`}>
      <span className={`w-1.5 h-1.5 rounded-full ${active ? 'bg-success' : 'bg-danger'}`} />
      {active ? 'Active' : 'Banned'}
    </span>
  );
}

function ProviderBadge({ provider }: { provider: string }) {
  const cfg: Record<string, string> = {
    google: 'bg-blue-500/10 text-blue-400',
    local:  'bg-success/10 text-success-light',
    guest:  'bg-gray-500/10 text-gray-400',
  };
  return (
    <span className={`inline-flex px-2 py-0.5 rounded text-xs font-medium ${cfg[provider] ?? 'bg-gray-700/20 text-gray-500'}`}>
      {provider}
    </span>
  );
}

export default function UsersPage() {
  const [users,   setUsers]   = useState<AdminUser[]>([]);
  const [total,   setTotal]   = useState(0);
  const [page,    setPage]    = useState(1);
  const [search,  setSearch]  = useState('');
  const [loading, setLoading] = useState(true);
  const [banReason,  setBanReason]  = useState('');
  const [banTarget,  setBanTarget]  = useState<AdminUser | null>(null);
  const [actionBusy, setActionBusy] = useState(false);
  const [toast, setToast] = useState<{ msg: string; ok: boolean } | null>(null);

  const showToast = (msg: string, ok = true) => {
    setToast({ msg, ok });
    setTimeout(() => setToast(null), 3000);
  };

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const data = await getUsers({ page, search: search || undefined });
      setUsers(data.users);
      setTotal(data.total);
    } catch {
      showToast('Failed to load users', false);
    } finally {
      setLoading(false);
    }
  }, [page, search]);

  useEffect(() => { load(); }, [load]);

  const handleBan = async () => {
    if (!banTarget) return;
    setActionBusy(true);
    try {
      await banUser(banTarget.id, banReason || 'Policy violation');
      showToast(`${banTarget.username} has been banned`);
      setBanTarget(null); setBanReason('');
      load();
    } catch {
      showToast('Failed to ban user', false);
    } finally { setActionBusy(false); }
  };

  const handleUnban = async (user: AdminUser) => {
    try {
      await unbanUser(user.id);
      showToast(`${user.username} has been unbanned`);
      load();
    } catch { showToast('Failed to unban user', false); }
  };

  const totalPages = Math.ceil(total / 20) || 1;

  return (
    <div className="min-h-screen">
      {/* Toast */}
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
            <span className="text-3xl">👥</span>
            <span style={{ background: 'linear-gradient(90deg,#60A5FA,#818CF8)', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' }}>
              User Management
            </span>
          </h1>
          <p className="text-gray-500 text-sm mt-1">
            {total.toLocaleString()} registered players
          </p>
        </div>
        <button onClick={load}
                className="flex items-center gap-2 px-4 py-2 rounded-xl border border-dark-border
                           text-gray-400 text-sm hover:bg-dark-border/40 hover:text-white transition-all">
          <span>↻</span> Refresh
        </button>
      </div>

      {/* Search */}
      <div className="flex gap-3 mb-5">
        <div className="relative flex-1 max-w-md">
          <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500 text-sm">🔍</span>
          <input
            className="w-full pl-9 pr-4 py-2.5 rounded-xl border border-dark-border bg-dark-card
                       text-sm text-white placeholder-gray-600 focus:outline-none focus:border-primary transition-colors"
            placeholder="Search by username, email or mobile…"
            value={search}
            onChange={(e) => { setSearch(e.target.value); setPage(1); }}
          />
        </div>
      </div>

      {/* Table */}
      <div className="rounded-2xl border border-dark-border overflow-hidden" style={{ background: '#0F1420' }}>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr style={{ background: '#0B0F1A' }}>
                {['Player', 'Contact', 'Provider', 'Level', 'Matches', 'Wallet', 'Joined', 'Status', ''].map(h => (
                  <th key={h} className="px-4 py-3.5 text-left text-xs font-semibold text-gray-500 uppercase tracking-wider">
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-dark-border">
              {loading ? (
                [...Array(8)].map((_, i) => (
                  <tr key={i}>
                    {[...Array(9)].map((__, j) => (
                      <td key={j} className="px-4 py-3.5">
                        <div className="h-4 rounded bg-dark-border animate-pulse" style={{ width: `${50 + (j * 13) % 35}%` }} />
                      </td>
                    ))}
                  </tr>
                ))
              ) : users.length === 0 ? (
                <tr>
                  <td colSpan={9} className="px-4 py-16 text-center">
                    <div className="flex flex-col items-center gap-3 text-gray-600">
                      <span className="text-4xl">👤</span>
                      <p>{search ? 'No users match your search' : 'No users found'}</p>
                      {search && <button onClick={() => setSearch('')} className="text-xs text-primary hover:underline">Clear search</button>}
                    </div>
                  </td>
                </tr>
              ) : (
                users.map((u) => (
                  <tr key={u.id} className="hover:bg-white/3 transition-colors group">
                    <td className="px-4 py-3.5">
                      <div className="flex items-center gap-2.5">
                        <div className="w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold flex-shrink-0"
                             style={{ background: 'rgba(99,102,241,0.15)', border: '1px solid rgba(99,102,241,0.2)', color: '#818CF8' }}>
                          {u.username?.[0]?.toUpperCase() ?? '?'}
                        </div>
                        <div>
                          <p className="text-white font-medium">{u.username}</p>
                          <p className="text-gray-600 text-xs font-mono">{truncate(u.id, 14)}</p>
                        </div>
                      </div>
                    </td>
                    <td className="px-4 py-3.5">
                      <p className="text-gray-400 text-xs">{u.email ?? '—'}</p>
                      <p className="text-gray-600 text-xs font-mono mt-0.5">{u.mobile ?? '—'}</p>
                    </td>
                    <td className="px-4 py-3.5"><ProviderBadge provider={u.provider} /></td>
                    <td className="px-4 py-3.5">
                      <span className="text-gray-300 font-medium">Lv.{u.level}</span>
                    </td>
                    <td className="px-4 py-3.5">
                      <p className="text-gray-300">{u.matches_played}</p>
                      <p className="text-gray-600 text-xs">{u.matches_won} wins</p>
                    </td>
                    <td className="px-4 py-3.5">
                      <span className="text-accent font-medium text-sm">🪙 {Number(u.coins ?? 0).toLocaleString()}</span>
                    </td>
                    <td className="px-4 py-3.5 text-gray-500 text-xs">{formatDate(u.created_at)}</td>
                    <td className="px-4 py-3.5"><StatusBadge active={!u.is_banned} /></td>
                    <td className="px-4 py-3.5">
                      {u.is_banned ? (
                        <button onClick={() => handleUnban(u)}
                                className="px-2.5 py-1 rounded-lg bg-success/10 text-success-light border border-success/20
                                           text-xs font-semibold hover:bg-success/20 transition-colors">
                          Unban
                        </button>
                      ) : (
                        <button onClick={() => setBanTarget(u)}
                                className="px-2.5 py-1 rounded-lg bg-danger/10 text-danger-light border border-danger/20
                                           text-xs font-semibold hover:bg-danger/20 opacity-0 group-hover:opacity-100 transition-all">
                          Ban
                        </button>
                      )}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>

        {/* Pagination */}
        {total > 0 && (
          <div className="flex items-center justify-between px-5 py-3 border-t border-dark-border" style={{ background: '#0B0F1A' }}>
            <p className="text-gray-600 text-xs">
              Page <span className="text-gray-400 font-medium">{page}</span> of <span className="text-gray-400 font-medium">{totalPages}</span>
              {' '}· <span className="text-gray-400 font-medium">{total}</span> total users
            </p>
            <div className="flex gap-2">
              <button onClick={() => setPage(p => Math.max(1, p - 1))} disabled={page === 1}
                      className="px-3 py-1.5 rounded-lg border border-dark-border text-xs text-gray-400
                                 hover:bg-dark-border/50 disabled:opacity-40 transition-all">
                ← Prev
              </button>
              <button onClick={() => setPage(p => p + 1)} disabled={page >= totalPages}
                      className="px-3 py-1.5 rounded-lg border border-dark-border text-xs text-gray-400
                                 hover:bg-dark-border/50 disabled:opacity-40 transition-all">
                Next →
              </button>
            </div>
          </div>
        )}
      </div>

      {/* Ban modal */}
      {banTarget && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4"
             style={{ background: 'rgba(0,0,0,0.75)', backdropFilter: 'blur(4px)' }}>
          <div className="w-full max-w-sm rounded-2xl border border-dark-border p-6" style={{ background: '#0F1420' }}>
            <h3 className="text-lg font-bold text-white mb-1">Ban User</h3>
            <p className="text-gray-400 text-sm mb-4">
              Ban <span className="text-white font-semibold">{banTarget.username}</span>? They will lose access immediately.
            </p>
            <input
              className="w-full px-3 py-2.5 rounded-xl border border-dark-border bg-dark-bg
                         text-sm text-white placeholder-gray-600 focus:outline-none focus:border-danger mb-4 transition-colors"
              placeholder="Reason (optional)"
              value={banReason}
              onChange={(e) => setBanReason(e.target.value)}
            />
            <div className="flex gap-3">
              <button onClick={() => { setBanTarget(null); setBanReason(''); }}
                      className="flex-1 px-4 py-2 rounded-lg border border-dark-border text-gray-300 text-sm hover:bg-dark-border/50 transition-colors">
                Cancel
              </button>
              <button onClick={handleBan} disabled={actionBusy}
                      className="flex-1 px-4 py-2 rounded-lg bg-danger text-white text-sm font-semibold hover:opacity-90 disabled:opacity-50 transition-colors">
                {actionBusy ? 'Banning…' : 'Confirm Ban'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
