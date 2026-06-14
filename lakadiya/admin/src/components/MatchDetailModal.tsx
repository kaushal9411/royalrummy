'use client';
import { useEffect, useState } from 'react';
import { getAdminMatchDetail, type AdminMatchDetail } from '../lib/api';
import { formatDateTime } from '../lib/utils';

const POS_BADGE: Record<number, { label: string; cls: string }> = {
  1: { label: '🥇 1st', cls: 'bg-yellow-400/15 text-yellow-300 border-yellow-400/30' },
  2: { label: '🥈 2nd', cls: 'bg-gray-300/15 text-gray-200 border-gray-300/30' },
  3: { label: '🥉 3rd', cls: 'bg-amber-600/15 text-amber-400 border-amber-600/30' },
  4: { label: '4th',    cls: 'bg-dark-border text-gray-400 border-dark-border' },
};

function fmtDuration(start: string, end: string | null): string {
  if (!end) return '—';
  const ms = new Date(end).getTime() - new Date(start).getTime();
  if (ms <= 0) return '—';
  const mins = Math.floor(ms / 60000);
  const secs = Math.floor((ms % 60000) / 1000);
  return mins > 0 ? `${mins}m ${secs}s` : `${secs}s`;
}

export default function MatchDetailModal({
  matchId, onClose,
}: { matchId: string; onClose: () => void }) {
  const [data, setData] = useState<AdminMatchDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  useEffect(() => {
    let cancelled = false;
    setLoading(true); setError(false);
    getAdminMatchDetail(matchId)
      .then(d => { if (!cancelled) { setData(d); setLoading(false); } })
      .catch(() => { if (!cancelled) { setError(true); setLoading(false); } });
    return () => { cancelled = true; };
  }, [matchId]);

  const m = data?.match;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4"
         style={{ background: 'rgba(0,0,0,0.75)', backdropFilter: 'blur(4px)' }}
         onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="w-full max-w-lg rounded-2xl border border-dark-border overflow-hidden max-h-[88vh] flex flex-col"
           style={{ background: '#0F1420' }}>
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-dark-border">
          <div>
            <h3 className="text-base font-bold text-white flex items-center gap-2">
              <span>🏁</span> Match Detail
              {m && <span className="font-mono text-accent text-sm">· {m.room_code}</span>}
            </h3>
            {m && (
              <p className="text-gray-500 text-xs mt-0.5">
                {formatDateTime(m.created_at)} · {fmtDuration(m.created_at, m.finished_at)}
              </p>
            )}
          </div>
          <button onClick={onClose}
                  className="w-7 h-7 flex items-center justify-center rounded-lg text-gray-500 hover:text-white hover:bg-dark-border transition-colors text-lg">
            ×
          </button>
        </div>

        <div className="overflow-y-auto">
          {loading ? (
            <div className="px-5 py-12 text-center text-gray-500 text-sm">Loading match…</div>
          ) : error || !data || !m ? (
            <div className="px-5 py-12 text-center text-gray-500 text-sm">
              No match data — this room hasn’t played a game yet.
            </div>
          ) : (
            <>
              {/* Meta chips */}
              <div className="flex flex-wrap gap-2 px-5 py-4 border-b border-dark-border">
                <span className={`px-2.5 py-1 rounded-lg text-xs font-semibold ${
                  m.status === 'completed' ? 'bg-green-500/15 text-green-400'
                  : m.status === 'active'  ? 'bg-blue-500/15 text-blue-400'
                  : 'bg-gray-500/15 text-gray-400'}`}>
                  {m.status}
                </span>
                <span className="px-2.5 py-1 rounded-lg text-xs font-semibold bg-dark-border text-gray-300">
                  {m.is_private ? '🔒 Private' : '🌐 Public'}
                </span>
                <span className="px-2.5 py-1 rounded-lg text-xs font-semibold bg-dark-border text-gray-300">
                  {Number(m.bet_amount) > 0 ? `Bet ₹${Number(m.bet_amount).toFixed(0)}` : 'Free'}
                </span>
                {Number(m.total_pot) > 0 && (
                  <span className="px-2.5 py-1 rounded-lg text-xs font-semibold bg-accent/15 text-accent">
                    Pot ₹{Number(m.total_pot).toFixed(0)}
                  </span>
                )}
                <span className="px-2.5 py-1 rounded-lg text-xs font-semibold bg-dark-border text-gray-300">
                  {m.total_rounds} rounds
                </span>
              </div>

              {/* Winner banner */}
              {data.players[0] && (
                <div className="mx-5 my-4 rounded-xl border border-yellow-400/25 px-4 py-3 flex items-center gap-3"
                     style={{ background: 'rgba(250,204,21,0.06)' }}>
                  <span className="text-2xl">🏆</span>
                  <div>
                    <p className="text-yellow-300 font-bold text-sm">{data.players[0].name}</p>
                    <p className="text-gray-400 text-xs">
                      Winner · {data.players[0].final_score} pts
                      {data.players[0].won_amount > 0 && ` · won ₹${data.players[0].won_amount.toFixed(0)}`}
                    </p>
                  </div>
                </div>
              )}

              {/* Player rows */}
              <div className="divide-y divide-dark-border">
                {data.players.map((p) => {
                  const pos = POS_BADGE[p.position] ?? POS_BADGE[4];
                  return (
                    <div key={p.seat} className="flex items-center gap-3 px-5 py-3">
                      <span className={`px-2 py-0.5 rounded-md text-[11px] font-bold border flex-shrink-0 ${pos.cls}`}>
                        {pos.label}
                      </span>
                      <div className="w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold flex-shrink-0"
                           style={{ background: p.is_bot ? 'rgba(99,102,241,0.15)' : 'rgba(139,92,246,0.15)',
                                    color: p.is_bot ? '#818CF8' : '#A78BFA' }}>
                        {p.is_bot ? '🤖' : (p.name?.[0]?.toUpperCase() ?? '?')}
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="text-white text-sm font-medium truncate">
                          {p.is_bot ? 'Bot' : p.name}
                          {p.is_bot && <span className="text-gray-500 text-xs ml-1">(AI)</span>}
                        </p>
                        <p className="text-gray-600 text-xs">
                          Seat {p.seat + 1}{!p.is_bot && p.level != null ? ` · Lv ${p.level}` : ''}
                        </p>
                      </div>
                      <div className="text-right flex-shrink-0">
                        <p className="text-white text-sm font-bold">{p.final_score} pts</p>
                        {p.won_amount > 0
                          ? <p className="text-accent text-xs font-semibold">+₹{p.won_amount.toFixed(0)}</p>
                          : p.is_bot && p.is_winner
                            ? <p className="text-gray-500 text-xs">bot — no payout</p>
                            : null}
                      </div>
                    </div>
                  );
                })}
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
