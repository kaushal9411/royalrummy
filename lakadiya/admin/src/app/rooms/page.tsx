'use client';
import { useEffect, useState, useCallback } from 'react';
import { getAdminRooms, closeAdminRoom, type AdminRoom } from '../../lib/api';
import { formatDateTime } from '../../lib/utils';

type Filter = '' | 'waiting' | 'playing' | 'finished';

function RoomStatusBadge({ status }: { status: string }) {
  const cfg: Record<string, { bg: string; text: string; dot: string }> = {
    waiting:  { bg: 'bg-accent/10',   text: 'text-accent-light',   dot: 'bg-accent animate-pulse' },
    playing:  { bg: 'bg-primary/10',  text: 'text-primary-light',  dot: 'bg-primary animate-pulse' },
    finished: { bg: 'bg-gray-500/10', text: 'text-gray-400',       dot: 'bg-gray-500' },
  };
  const s = cfg[status] ?? { bg: 'bg-gray-500/10', text: 'text-gray-400', dot: 'bg-gray-500' };
  return (
    <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold ${s.bg} ${s.text}`}>
      <span className={`w-1.5 h-1.5 rounded-full ${s.dot}`} />
      {status}
    </span>
  );
}

export default function RoomsPage() {
  const [rooms,   setRooms]   = useState<AdminRoom[]>([]);
  const [total,   setTotal]   = useState(0);
  const [filter,  setFilter]  = useState<Filter>('');
  const [search,  setSearch]  = useState('');
  const [loading, setLoading] = useState(true);
  const [closeTarget, setCloseTarget] = useState<AdminRoom | null>(null);
  const [busy, setBusy] = useState(false);
  const [toast, setToast] = useState<{ msg: string; ok: boolean } | null>(null);

  const showToast = (msg: string, ok = true) => {
    setToast({ msg, ok });
    setTimeout(() => setToast(null), 3500);
  };

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const data = await getAdminRooms({ status: filter || undefined, limit: 200 });
      setRooms(data.rooms ?? []);
      setTotal(data.total ?? 0);
    } catch {
      setRooms([]);
    } finally {
      setLoading(false);
    }
  }, [filter]);

  useEffect(() => { load(); }, [load]);
  useEffect(() => {
    const id = setInterval(load, 15_000);
    return () => clearInterval(id);
  }, [load]);

  const doClose = async () => {
    if (!closeTarget) return;
    setBusy(true);
    try {
      await closeAdminRoom(closeTarget.id);
      showToast(`Room ${closeTarget.code} closed`);
      setCloseTarget(null);
      load();
    } catch { showToast('Failed to close room', false); }
    finally { setBusy(false); }
  };

  const filtered = rooms.filter(r =>
    !search || r.code?.toLowerCase().includes(search.toLowerCase()) ||
               r.host_name?.toLowerCase().includes(search.toLowerCase()),
  );

  const liveCount    = rooms.filter(r => r.status === 'playing').length;
  const waitingCount = rooms.filter(r => r.status === 'waiting').length;
  const betRooms     = rooms.filter(r => Number(r.bet_amount) > 0).length;

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
            <span className="text-3xl">🎮</span>
            <span style={{ background: 'linear-gradient(90deg,#A78BFA,#818CF8)', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' }}>
              Live Rooms
            </span>
          </h1>
          <p className="text-gray-500 text-sm mt-1">Monitor active game rooms · Auto-refresh every 15s</p>
        </div>
        <button onClick={load}
                className="flex items-center gap-2 px-4 py-2 rounded-xl border border-dark-border
                           text-gray-400 text-sm hover:bg-dark-border/40 hover:text-white transition-all">
          <span>↻</span> Refresh
        </button>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        {[
          { label: 'Live Games',    value: liveCount,    icon: '🎮', color: '#6366F1' },
          { label: 'Waiting',       value: waitingCount, icon: '⏳', color: '#F59E0B' },
          { label: 'Bet Rooms',     value: betRooms,     icon: '💰', color: '#10B981' },
          { label: 'Total Rooms',   value: total,        icon: '📋', color: '#3B82F6' },
        ].map(({ label, value, icon, color }) => (
          <div key={label} className="relative rounded-2xl p-4 border overflow-hidden"
               style={{ background: '#0F1420', borderColor: `${color}20`, boxShadow: `0 0 18px ${color}12` }}>
            <div className="absolute inset-0 opacity-5" style={{ background: `radial-gradient(circle at top right, ${color}, transparent 60%)` }} />
            <div className="relative flex items-start justify-between">
              <div>
                <p className="text-gray-500 text-xs uppercase tracking-wider mb-1">{label}</p>
                <p className="text-2xl font-bold text-white">{value}</p>
              </div>
              <span className="text-2xl">{icon}</span>
            </div>
          </div>
        ))}
      </div>

      {/* Filters */}
      <div className="flex flex-wrap items-center gap-3 mb-5">
        <div className="relative">
          <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500 text-sm">🔍</span>
          <input value={search} onChange={e => setSearch(e.target.value)}
                 placeholder="Search by room code or host…"
                 className="pl-9 pr-4 py-2.5 rounded-xl border border-dark-border bg-dark-card
                            text-sm text-white placeholder-gray-600 focus:outline-none focus:border-primary transition-colors w-64" />
        </div>
        <div className="flex gap-1 p-1 rounded-xl border border-dark-border" style={{ background: '#0B0F1A' }}>
          {(['all', 'waiting', 'playing', 'finished'] as const).map(s => (
            <button key={s} onClick={() => setFilter(s === 'all' ? '' : s)}
                    className={`px-3 py-1.5 rounded-lg text-xs font-medium capitalize transition-all
                                ${(s === 'all' ? !filter : filter === s)
                                  ? 'bg-dark-card text-white border border-dark-border'
                                  : 'text-gray-500 hover:text-gray-300'}`}>
              {s}
            </button>
          ))}
        </div>
        <p className="text-gray-600 text-xs ml-auto">{filtered.length} rooms</p>
      </div>

      {/* Table */}
      <div className="rounded-2xl border border-dark-border overflow-hidden" style={{ background: '#0F1420' }}>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr style={{ background: '#0B0F1A' }}>
                {['Code', 'Host', 'Players', 'Bet', 'Type', 'Status', 'Created', 'Actions'].map(h => (
                  <th key={h} className="px-5 py-3.5 text-left text-xs font-semibold text-gray-500 uppercase tracking-wider">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-dark-border">
              {loading ? (
                [...Array(6)].map((_, i) => (
                  <tr key={i}>{[...Array(8)].map((__, j) => (
                    <td key={j} className="px-5 py-4">
                      <div className="h-4 rounded bg-dark-border animate-pulse" style={{ width: `${50 + (j * 13) % 35}%` }} />
                    </td>
                  ))}</tr>
                ))
              ) : filtered.length === 0 ? (
                <tr>
                  <td colSpan={8} className="px-5 py-16 text-center">
                    <div className="flex flex-col items-center gap-3 text-gray-600">
                      <span className="text-4xl">🎮</span>
                      <p>{search ? 'No rooms match your search' : 'No rooms found'}</p>
                    </div>
                  </td>
                </tr>
              ) : (
                filtered.map(room => (
                  <tr key={room.id} className="hover:bg-white/3 transition-colors">
                    <td className="px-5 py-3.5">
                      <span className="font-mono text-accent font-bold text-sm">{room.code}</span>
                    </td>
                    <td className="px-5 py-3.5">
                      <div className="flex items-center gap-2">
                        <div className="w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold flex-shrink-0"
                             style={{ background: 'rgba(139,92,246,0.15)', color: '#A78BFA' }}>
                          {room.host_name?.[0]?.toUpperCase() ?? '?'}
                        </div>
                        <span className="text-white font-medium">{room.host_name}</span>
                      </div>
                    </td>
                    <td className="px-5 py-3.5">
                      <div className="flex gap-0.5">
                        {[...Array(4)].map((_, i) => (
                          <span key={i} className={`w-4 h-4 rounded flex items-center justify-center text-xs
                                                    ${i < Number(room.player_count ?? 0)
                                                      ? 'bg-primary/30 text-primary-light'
                                                      : 'bg-dark-border text-gray-600'}`}>
                            ♟
                          </span>
                        ))}
                        <span className="ml-1.5 text-gray-400 text-xs">{room.player_count ?? 0}/4</span>
                      </div>
                    </td>
                    <td className="px-5 py-3.5">
                      {Number(room.bet_amount) > 0
                        ? <span className="text-accent font-bold">₹{Number(room.bet_amount).toFixed(0)}</span>
                        : <span className="text-gray-600">Free</span>}
                    </td>
                    <td className="px-5 py-3.5">
                      <span className={`text-xs px-2 py-0.5 rounded ${room.is_private ? 'bg-gray-500/10 text-gray-400' : 'bg-primary/10 text-primary-light'}`}>
                        {room.is_private ? '🔒 Private' : '🌐 Public'}
                      </span>
                    </td>
                    <td className="px-5 py-3.5"><RoomStatusBadge status={room.status} /></td>
                    <td className="px-5 py-3.5 text-gray-500 text-xs">{formatDateTime(room.created_at)}</td>
                    <td className="px-5 py-3.5">
                      {room.status !== 'finished' ? (
                        <button onClick={() => setCloseTarget(room)}
                                className="px-2.5 py-1 rounded-lg bg-danger/10 text-danger-light border border-danger/20
                                           text-xs font-semibold hover:bg-danger/20 transition-colors">
                          Close
                        </button>
                      ) : <span className="text-gray-600 text-xs">—</span>}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Close room modal */}
      {closeTarget && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4"
             style={{ background: 'rgba(0,0,0,0.75)', backdropFilter: 'blur(4px)' }}>
          <div className="w-full max-w-sm rounded-2xl border border-dark-border p-6" style={{ background: '#0F1420' }}>
            <h3 className="text-lg font-bold text-white mb-2">Close Room</h3>
            <p className="text-gray-400 text-sm mb-5">
              Force-close room <span className="text-accent font-bold font-mono">{closeTarget.code}</span>?
              All players will be removed.
            </p>
            <div className="flex gap-3">
              <button onClick={() => setCloseTarget(null)}
                      className="flex-1 px-4 py-2 rounded-lg border border-dark-border text-gray-300 text-sm hover:bg-dark-border/50 transition-colors">
                Cancel
              </button>
              <button onClick={doClose} disabled={busy}
                      className="flex-1 px-4 py-2 rounded-lg bg-danger text-white text-sm font-semibold hover:opacity-90 disabled:opacity-50 transition-colors">
                {busy ? 'Closing…' : 'Force Close'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
