'use client';
import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { getUsers, AdminUser } from '../../lib/api';
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

function AgeBadge({ age, isMinor }: { age: number | null; isMinor: boolean | null }) {
  if (age === null) return <span className="text-gray-600 text-xs">—</span>;
  if (isMinor) return (
    <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-bold bg-danger/15 text-danger-light border border-danger/30">
      🔞 {age}y <span className="text-danger">⚠ MINOR</span>
    </span>
  );
  return (
    <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-success/10 text-success-light">
      ✓ {age}y
    </span>
  );
}

function KycBadge({ status }: { status: string }) {
  const cfgMap: Record<string, { cls: string; icon: string; label: string }> = {
    approved:      { cls: 'bg-success/10 text-success-light border-success/25',   icon: '✓', label: 'KYC OK'   },
    pending:       { cls: 'bg-yellow-500/10 text-yellow-400 border-yellow-500/25', icon: '⏳', label: 'Pending'  },
    rejected:      { cls: 'bg-danger/10 text-danger-light border-danger/25',       icon: '✕', label: 'Rejected' },
    not_submitted: { cls: 'bg-gray-700/20 text-gray-500 border-gray-700/30',      icon: '—', label: 'No KYC'   },
  };
  const cfg = cfgMap[status] ?? cfgMap.not_submitted;
  return (
    <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium border ${cfg.cls}`}>
      {cfg.icon} {cfg.label}
    </span>
  );
}

export default function UsersPage() {
  const router = useRouter();
  const [users,   setUsers]   = useState<AdminUser[]>([]);
  const [total,   setTotal]   = useState(0);
  const [page,    setPage]    = useState(1);
  const [search,  setSearch]  = useState('');
  const [loading, setLoading] = useState(true);
  const [toast,   setToast]   = useState<{ msg: string; ok: boolean } | null>(null);

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

  const totalPages = Math.ceil(total / 20) || 1;

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
            <span className="text-3xl">👥</span>
            <span style={{ background: 'linear-gradient(90deg,#60A5FA,#818CF8)', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' }}>
              User Management
            </span>
          </h1>
          <p className="text-gray-500 text-sm mt-1">
            {total.toLocaleString()} registered players · click any row to open profile
          </p>
        </div>
        <button onClick={load}
                className="flex items-center gap-2 px-4 py-2 rounded-xl border border-dark-border
                           text-gray-400 text-sm hover:bg-dark-border/40 hover:text-white transition-all">
          <span>↻</span> Refresh
        </button>
      </div>

      {/* Search */}
      <div className="mb-5">
        <div className="relative max-w-md">
          <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500 text-sm">🔍</span>
          <input
            className="w-full pl-9 pr-4 py-2.5 rounded-xl border border-dark-border bg-dark-card
                       text-sm text-white placeholder-gray-600 focus:outline-none focus:border-primary transition-colors"
            placeholder="Search by username, email or mobile…"
            value={search}
            onChange={e => { setSearch(e.target.value); setPage(1); }}
          />
        </div>
      </div>

      {/* Table */}
      <div className="rounded-2xl border border-dark-border overflow-hidden" style={{ background: '#0F1420' }}>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr style={{ background: '#0B0F1A' }}>
                {['Player', 'Contact', 'Provider', 'Age', 'KYC', 'Level', 'Matches', 'Wallet', 'Joined', 'Status'].map(h => (
                  <th key={h} className="px-4 py-3.5 text-left text-xs font-semibold text-gray-500 uppercase tracking-wider whitespace-nowrap">
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-dark-border">
              {loading ? (
                [...Array(8)].map((_, i) => (
                  <tr key={i}>
                    {[...Array(10)].map((__, j) => (
                      <td key={j} className="px-4 py-3.5">
                        <div className="h-4 rounded bg-dark-border animate-pulse" style={{ width: `${50 + (j * 13) % 35}%` }} />
                      </td>
                    ))}
                  </tr>
                ))
              ) : users.length === 0 ? (
                <tr>
                  <td colSpan={10} className="px-4 py-16 text-center">
                    <div className="flex flex-col items-center gap-3 text-gray-600">
                      <span className="text-4xl">👤</span>
                      <p>{search ? 'No users match your search' : 'No users found'}</p>
                      {search && (
                        <button onClick={() => setSearch('')} className="text-xs text-primary hover:underline">
                          Clear search
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              ) : (
                users.map(u => (
                  <tr
                    key={u.id}
                    onClick={() => router.push(`/users/${u.id}`)}
                    className={`hover:bg-white/[0.03] transition-colors group cursor-pointer ${u.is_minor ? 'bg-danger/[0.03]' : ''}`}
                    style={u.is_minor ? { borderLeft: '2px solid rgba(239,68,68,0.5)' } : {}}
                  >
                    {/* Player */}
                    <td className="px-4 py-3.5">
                      <div className="flex items-center gap-2.5">
                        <div className="w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold flex-shrink-0 relative"
                             style={{ background: 'rgba(99,102,241,0.15)', border: '1px solid rgba(99,102,241,0.2)', color: '#818CF8' }}>
                          {u.username?.[0]?.toUpperCase() ?? '?'}
                          {u.is_minor && (
                            <span className="absolute -top-1 -right-1 w-3.5 h-3.5 rounded-full bg-danger text-white flex items-center justify-center text-[8px] font-black">!</span>
                          )}
                        </div>
                        <div>
                          <p className="text-white font-medium group-hover:text-primary-light transition-colors">{u.username}</p>
                          <p className="text-gray-600 text-xs font-mono">{truncate(u.id, 14)}</p>
                        </div>
                      </div>
                    </td>
                    {/* Contact */}
                    <td className="px-4 py-3.5">
                      <p className="text-gray-400 text-xs">{u.email ?? '—'}</p>
                      <p className="text-gray-600 text-xs font-mono mt-0.5">{u.mobile ?? '—'}</p>
                    </td>
                    <td className="px-4 py-3.5"><ProviderBadge provider={u.provider} /></td>
                    <td className="px-4 py-3.5"><AgeBadge age={u.age} isMinor={u.is_minor} /></td>
                    <td className="px-4 py-3.5"><KycBadge status={u.kyc_status ?? 'not_submitted'} /></td>
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
                    <td className="px-4 py-3.5 text-gray-500 text-xs whitespace-nowrap">{formatDate(u.created_at)}</td>
                    <td className="px-4 py-3.5"><StatusBadge active={!u.is_banned} /></td>
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
    </div>
  );
}
