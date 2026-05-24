'use client';
import { useEffect, useState, useCallback } from 'react';
import { getMatches, AdminMatch } from '../../lib/api';
import { format } from 'date-fns';

const STATUSES = ['', 'active', 'completed', 'abandoned'];

export default function MatchesPage() {
  const [matches, setMatches] = useState<AdminMatch[]>([]);
  const [total, setTotal]     = useState(0);
  const [page, setPage]       = useState(1);
  const [status, setStatus]   = useState('');
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const data = await getMatches({ page, status: status || undefined });
      setMatches(data.matches);
      setTotal(data.total);
    } finally {
      setLoading(false);
    }
  }, [page, status]);

  useEffect(() => { load(); }, [load]);

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-white">Matches</h1>
        <span className="text-gray-400 text-sm">{total} total</span>
      </div>

      {/* Filter */}
      <div className="flex gap-2 mb-4">
        {STATUSES.map((s) => (
          <button
            key={s || 'all'}
            onClick={() => { setStatus(s); setPage(1); }}
            className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
              status === s
                ? 'bg-primary text-white'
                : 'bg-dark-card text-gray-400 hover:text-white border border-dark-border'
            }`}
          >
            {s || 'All'}
          </button>
        ))}
      </div>

      <div className="card overflow-x-auto p-0">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-dark-border text-gray-400 text-left">
              {['Room', 'Players', 'Status', 'Winner', 'Started', 'Duration', ''].map((h) => (
                <th key={h} className="px-4 py-3 font-medium">{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {loading
              ? <tr><td colSpan={7} className="px-4 py-8 text-center text-gray-500">Loading…</td></tr>
              : matches.map((m) => {
                const duration = m.finished_at
                  ? Math.round((new Date(m.finished_at).getTime() - new Date(m.created_at).getTime()) / 60000)
                  : null;
                return (
                  <tr key={m.id} className="border-b border-dark-border hover:bg-dark-bg transition-colors">
                    <td className="px-4 py-3 font-mono text-accent font-semibold">{m.room_code}</td>
                    <td className="px-4 py-3 text-gray-300">{m.player_count}</td>
                    <td className="px-4 py-3">
                      <span className={`badge ${
                        m.status === 'active'    ? 'bg-blue-500/20 text-blue-400' :
                        m.status === 'completed' ? 'bg-green-500/20 text-green-400' :
                        'bg-gray-500/20 text-gray-400'
                      }`}>{m.status}</span>
                    </td>
                    <td className="px-4 py-3 text-gray-300">{m.winner_name ?? '—'}</td>
                    <td className="px-4 py-3 text-gray-400 text-xs">
                      {format(new Date(m.created_at), 'MMM d, HH:mm')}
                    </td>
                    <td className="px-4 py-3 text-gray-400 text-xs">
                      {duration != null ? `${duration}m` : '—'}
                    </td>
                    <td className="px-4 py-3">
                      <span className="text-xs text-gray-500 font-mono">{m.id.slice(0, 8)}…</span>
                    </td>
                  </tr>
                );
              })
            }
          </tbody>
        </table>
      </div>

      <div className="flex items-center justify-between mt-4 text-sm text-gray-400">
        <span>Page {page} of {Math.ceil(total / 20) || 1}</span>
        <div className="flex gap-2">
          <button onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1}
            className="btn-primary disabled:opacity-40 text-xs py-1 px-3">Prev</button>
          <button onClick={() => setPage((p) => p + 1)} disabled={page * 20 >= total}
            className="btn-primary disabled:opacity-40 text-xs py-1 px-3">Next</button>
        </div>
      </div>
    </div>
  );
}
