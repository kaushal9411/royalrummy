'use client';
import { useEffect, useState, useCallback } from 'react';
import { getUsers, banUser, unbanUser, AdminUser } from '../../lib/api';
import { format } from 'date-fns';

export default function UsersPage() {
  const [users, setUsers]     = useState<AdminUser[]>([]);
  const [total, setTotal]     = useState(0);
  const [page, setPage]       = useState(1);
  const [search, setSearch]   = useState('');
  const [loading, setLoading] = useState(true);
  const [banReason, setBanReason] = useState('');
  const [banTarget, setBanTarget] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const data = await getUsers({ page, search: search || undefined });
      setUsers(data.users);
      setTotal(data.total);
    } finally {
      setLoading(false);
    }
  }, [page, search]);

  useEffect(() => { load(); }, [load]);

  const handleBan = async () => {
    if (!banTarget) return;
    await banUser(banTarget, banReason || 'Policy violation');
    setBanTarget(null);
    setBanReason('');
    load();
  };

  const handleUnban = async (id: string) => {
    await unbanUser(id);
    load();
  };

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-white">Users</h1>
        <span className="text-gray-400 text-sm">{total} total</span>
      </div>

      {/* Search */}
      <div className="flex gap-3 mb-4">
        <input
          className="input flex-1"
          placeholder="Search by username or email…"
          value={search}
          onChange={(e) => { setSearch(e.target.value); setPage(1); }}
        />
      </div>

      {/* Table */}
      <div className="card overflow-x-auto p-0">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-dark-border text-gray-400 text-left">
              {['Username', 'Email', 'Provider', 'Level', 'Matches', 'Joined', 'Status', ''].map((h) => (
                <th key={h} className="px-4 py-3 font-medium">{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {loading
              ? (
                <tr><td colSpan={8} className="px-4 py-8 text-center text-gray-500">Loading…</td></tr>
              )
              : users.map((u) => (
                <tr key={u.id} className="border-b border-dark-border hover:bg-dark-bg transition-colors">
                  <td className="px-4 py-3 font-medium text-white">{u.username}</td>
                  <td className="px-4 py-3 text-gray-400">{u.email ?? '—'}</td>
                  <td className="px-4 py-3">
                    <span className={`badge ${
                      u.provider === 'google' ? 'bg-blue-500/20 text-blue-400' :
                      u.provider === 'guest'  ? 'bg-gray-500/20 text-gray-400' :
                      'bg-green-500/20 text-green-400'
                    }`}>{u.provider}</span>
                  </td>
                  <td className="px-4 py-3 text-gray-300">{u.level}</td>
                  <td className="px-4 py-3 text-gray-300">{u.matches_played}</td>
                  <td className="px-4 py-3 text-gray-400 text-xs">
                    {format(new Date(u.created_at), 'MMM d, yyyy')}
                  </td>
                  <td className="px-4 py-3">
                    <span className={`badge ${u.is_banned ? 'bg-red-500/20 text-red-400' : 'bg-green-500/20 text-green-400'}`}>
                      {u.is_banned ? 'Banned' : 'Active'}
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    {u.is_banned
                      ? (
                        <button onClick={() => handleUnban(u.id)}
                          className="text-xs text-green-400 hover:text-green-300 font-medium">
                          Unban
                        </button>
                      )
                      : (
                        <button onClick={() => setBanTarget(u.id)}
                          className="text-xs text-red-400 hover:text-red-300 font-medium">
                          Ban
                        </button>
                      )
                    }
                  </td>
                </tr>
              ))
            }
          </tbody>
        </table>
      </div>

      {/* Pagination */}
      <div className="flex items-center justify-between mt-4 text-sm text-gray-400">
        <span>Page {page} of {Math.ceil(total / 20) || 1}</span>
        <div className="flex gap-2">
          <button onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1}
            className="btn-primary disabled:opacity-40 text-xs py-1 px-3">Prev</button>
          <button onClick={() => setPage((p) => p + 1)} disabled={page * 20 >= total}
            className="btn-primary disabled:opacity-40 text-xs py-1 px-3">Next</button>
        </div>
      </div>

      {/* Ban modal */}
      {banTarget && (
        <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50">
          <div className="bg-dark-surface border border-dark-border rounded-xl p-6 w-80">
            <h3 className="text-white font-semibold mb-3">Ban User</h3>
            <input
              className="input w-full mb-4"
              placeholder="Reason (optional)"
              value={banReason}
              onChange={(e) => setBanReason(e.target.value)}
            />
            <div className="flex gap-3">
              <button onClick={() => setBanTarget(null)} className="flex-1 py-2 rounded-lg border border-dark-border text-gray-400 hover:text-white text-sm">
                Cancel
              </button>
              <button onClick={handleBan} className="flex-1 btn-danger text-sm">
                Confirm Ban
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
