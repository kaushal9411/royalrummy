'use client';
import { useEffect, useState, useCallback } from 'react';
import {
  getAdminRooms, deleteAdminRoom, getAdminRoomPlayers, kickRoomPlayer,
  type AdminRoom, type AdminRoomPlayer,
} from '../../lib/api';
import MatchDetailModal from '../../components/MatchDetailModal';
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
  const [deleteTarget,  setDeleteTarget]  = useState<AdminRoom | null>(null);
  const [viewMatchId,   setViewMatchId]   = useState<string | null>(null);
  const [playersRoom,   setPlayersRoom]   = useState<AdminRoom | null>(null);
  const [players,       setPlayers]       = useState<AdminRoomPlayer[]>([]);
  const [playersLoading, setPlayersLoading] = useState(false);
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

  const doDelete = async () => {
    if (!deleteTarget) return;
    setBusy(true);
    try {
      await deleteAdminRoom(deleteTarget.id);
      showToast(`Room ${deleteTarget.code} deleted`);
      setDeleteTarget(null);
      load();
    } catch { showToast('Failed to delete room', false); }
    finally { setBusy(false); }
  };

  const viewRoom = (room: AdminRoom) => {
    // Show full match breakdown if the room has played; else its current roster.
    if (room.match_id) setViewMatchId(room.match_id);
    else openPlayers(room);
  };

  const openPlayers = async (room: AdminRoom) => {
    setPlayersRoom(room);
    setPlayers([]);
    setPlayersLoading(true);
    try {
      const data = await getAdminRoomPlayers(room.id);
      setPlayers(data);
    } catch { showToast('Failed to load players', false); }
    finally { setPlayersLoading(false); }
  };

  const doKick = async (userId: string) => {
    if (!playersRoom) return;
    try {
      await kickRoomPlayer(playersRoom.id, userId);
      showToast('Player kicked');
      setPlayers(prev => prev.filter(p => p.user_id !== userId));
      load();
    } catch { showToast('Failed to kick player', false); }
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
                {['Code', 'Host', 'Players', 'Bet', 'Type', 'Status', 'Winner / Won', 'Created', 'Actions'].map(h => (
                  <th key={h} className="px-5 py-3.5 text-left text-xs font-semibold text-gray-500 uppercase tracking-wider">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-dark-border">
              {loading ? (
                [...Array(6)].map((_, i) => (
                  <tr key={i}>{[...Array(9)].map((__, j) => (
                    <td key={j} className="px-5 py-4">
                      <div className="h-4 rounded bg-dark-border animate-pulse" style={{ width: `${50 + (j * 13) % 35}%` }} />
                    </td>
                  ))}</tr>
                ))
              ) : filtered.length === 0 ? (
                <tr>
                  <td colSpan={9} className="px-5 py-16 text-center">
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
                      <button onClick={() => openPlayers(room)}
                              className="text-left hover:opacity-90 transition-opacity group max-w-[230px]">
                        <div className="flex flex-wrap gap-1 items-center">
                          {(room.players ?? []).length === 0 ? (
                            <span className="text-gray-600 text-xs">Empty</span>
                          ) : (
                            <>
                              {(room.players ?? []).slice(0, 3).map((p, i) => (
                                <span key={i}
                                      className={`px-1.5 py-0.5 rounded text-[11px] font-medium truncate max-w-[90px]
                                                  ${p.is_bot ? 'bg-indigo-500/10 text-indigo-300' : 'bg-primary/10 text-primary-light'}`}>
                                  {p.is_bot ? '🤖 Bot' : p.name}
                                </span>
                              ))}
                              {(room.players?.length ?? 0) > 3 && (
                                <span className="text-gray-500 text-[11px]">+{(room.players!.length - 3)}</span>
                              )}
                            </>
                          )}
                        </div>
                        <span className="text-gray-600 text-[10px] group-hover:text-gray-400 transition-colors">
                          {room.player_count ?? 0}/4 · view details
                        </span>
                      </button>
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
                    <td className="px-5 py-3.5">
                      {room.winner_name ? (
                        <div className="flex flex-col leading-tight">
                          <span className="text-white text-sm font-medium flex items-center gap-1">
                            🏆 {room.winner_name}
                          </span>
                          {Number(room.won_amount) > 0 && (
                            <span className="text-accent text-xs font-bold">won ₹{Number(room.won_amount).toFixed(0)}</span>
                          )}
                        </div>
                      ) : room.status === 'finished' ? (
                        <span className="text-gray-600 text-xs">No winner</span>
                      ) : (
                        <span className="text-gray-600 text-xs">—</span>
                      )}
                    </td>
                    <td className="px-5 py-3.5 text-gray-500 text-xs">{formatDateTime(room.created_at)}</td>
                    <td className="px-5 py-3.5">
                      <div className="flex items-center gap-2">
                        <button onClick={() => viewRoom(room)}
                                className="px-2.5 py-1 rounded-lg bg-primary/10 text-primary-light border border-primary/20
                                           text-xs font-semibold hover:bg-primary/20 transition-colors">
                          View
                        </button>
                        <button onClick={() => setDeleteTarget(room)}
                                className="px-2.5 py-1 rounded-lg bg-danger/10 text-danger-light border border-danger/20
                                           text-xs font-semibold hover:bg-danger/20 transition-colors">
                          Delete
                        </button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Delete room modal */}
      {deleteTarget && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4"
             style={{ background: 'rgba(0,0,0,0.75)', backdropFilter: 'blur(4px)' }}>
          <div className="w-full max-w-sm rounded-2xl border border-dark-border p-6" style={{ background: '#0F1420' }}>
            <h3 className="text-lg font-bold text-white mb-2">Delete Room</h3>
            <p className="text-gray-400 text-sm mb-5">
              Permanently delete room <span className="text-accent font-bold font-mono">{deleteTarget.code}</span>?
              Any players will be removed and this can’t be undone.
            </p>
            <div className="flex gap-3">
              <button onClick={() => setDeleteTarget(null)}
                      className="flex-1 px-4 py-2 rounded-lg border border-dark-border text-gray-300 text-sm hover:bg-dark-border/50 transition-colors">
                Cancel
              </button>
              <button onClick={doDelete} disabled={busy}
                      className="flex-1 px-4 py-2 rounded-lg bg-danger text-white text-sm font-semibold hover:opacity-90 disabled:opacity-50 transition-colors">
                {busy ? 'Deleting…' : 'Delete Room'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Match detail modal (room View) */}
      {viewMatchId && (
        <MatchDetailModal matchId={viewMatchId} onClose={() => setViewMatchId(null)} />
      )}

      {/* Players modal */}
      {playersRoom && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4"
             style={{ background: 'rgba(0,0,0,0.75)', backdropFilter: 'blur(4px)' }}
             onClick={(e) => { if (e.target === e.currentTarget) setPlayersRoom(null); }}>
          <div className="w-full max-w-md rounded-2xl border border-dark-border overflow-hidden" style={{ background: '#0F1420' }}>
            {/* Header */}
            <div className="flex items-center justify-between px-5 py-4 border-b border-dark-border">
              <div>
                <h3 className="text-base font-bold text-white">
                  Room <span className="font-mono text-accent">{playersRoom.code}</span> · Players
                </h3>
                <p className="text-gray-500 text-xs mt-0.5">
                  {players.filter(p => p.is_online).length} online · {players.filter(p => !p.is_online && !p.is_bot).length} offline
                </p>
              </div>
              <button onClick={() => setPlayersRoom(null)}
                      className="w-7 h-7 flex items-center justify-center rounded-lg text-gray-500 hover:text-white hover:bg-dark-border transition-colors text-lg">
                ×
              </button>
            </div>

            {/* Player list */}
            <div className="divide-y divide-dark-border">
              {playersLoading ? (
                [...Array(3)].map((_, i) => (
                  <div key={i} className="flex items-center gap-3 px-5 py-3.5">
                    <div className="w-9 h-9 rounded-full bg-dark-border animate-pulse" />
                    <div className="flex-1 space-y-1.5">
                      <div className="h-3.5 w-28 rounded bg-dark-border animate-pulse" />
                      <div className="h-3 w-16 rounded bg-dark-border animate-pulse" />
                    </div>
                  </div>
                ))
              ) : players.length === 0 ? (
                <div className="px-5 py-10 text-center text-gray-600 text-sm">No players in this room</div>
              ) : (
                players.map(p => (
                  <div key={p.is_bot ? `bot-${p.seat}` : p.user_id}
                       className="flex items-center gap-3 px-5 py-3.5 hover:bg-white/2 transition-colors">
                    {/* Avatar */}
                    <div className="relative flex-shrink-0">
                      <div className="w-9 h-9 rounded-full flex items-center justify-center text-sm font-bold"
                           style={{ background: p.is_bot ? 'rgba(99,102,241,0.15)' : 'rgba(139,92,246,0.15)',
                                    color: p.is_bot ? '#818CF8' : '#A78BFA' }}>
                        {p.is_bot ? '🤖' : (p.username?.[0]?.toUpperCase() ?? '?')}
                      </div>
                      {/* Online dot */}
                      {!p.is_bot && (
                        <span className={`absolute -bottom-0.5 -right-0.5 w-3 h-3 rounded-full border-2
                                          ${p.is_online
                                            ? 'bg-green-400 border-[#0F1420]'
                                            : 'bg-gray-600 border-[#0F1420]'}`} />
                      )}
                    </div>

                    {/* Info */}
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="text-white text-sm font-medium truncate">
                          {p.is_bot ? `Bot (${p.bot_level ?? 'medium'})` : (p.username ?? 'Unknown')}
                        </span>
                        {!p.is_bot && (
                          <span className={`text-xs px-1.5 py-0.5 rounded font-semibold flex-shrink-0
                                            ${p.is_online
                                              ? 'bg-green-400/10 text-green-400'
                                              : 'bg-gray-500/10 text-gray-500'}`}>
                            {p.is_online ? 'Online' : 'Offline'}
                          </span>
                        )}
                      </div>
                      <p className="text-gray-600 text-xs">Seat {p.seat + 1}{p.is_bot ? ' · Bot' : ` · Lv ${p.level ?? 1}`}</p>
                    </div>

                    {/* Kick button — only for real (non-bot) players */}
                    {!p.is_bot && p.user_id && (
                      <button onClick={() => doKick(p.user_id!)}
                              className="px-2.5 py-1 rounded-lg text-xs font-semibold border transition-colors flex-shrink-0
                                         bg-danger/10 text-danger-light border-danger/20 hover:bg-danger/20">
                        Kick
                      </button>
                    )}
                  </div>
                ))
              )}
            </div>

            {/* Footer */}
            <div className="px-5 py-4 border-t border-dark-border flex justify-end">
              <button onClick={() => { setDeleteTarget(playersRoom); setPlayersRoom(null); }}
                      className="px-4 py-2 rounded-lg bg-danger/10 text-danger-light border border-danger/20
                                 text-xs font-semibold hover:bg-danger/20 transition-colors">
                Delete Room
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
