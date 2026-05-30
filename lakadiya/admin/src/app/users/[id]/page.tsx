'use client';
import { useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { getUserDetail, approveKyc, rejectKyc, banUser, unbanUser, type AdminUserDetail } from '../../../lib/api';
import { formatDate } from '../../../lib/utils';

function InfoRow({ label, value, mono = false }: { label: string; value: React.ReactNode; mono?: boolean }) {
  return (
    <div className="flex items-start justify-between py-2.5 border-b border-dark-border/60 last:border-0">
      <span className="text-gray-500 text-xs uppercase tracking-wider font-medium w-36 flex-shrink-0">{label}</span>
      <span className={`text-right text-sm ${mono ? 'font-mono text-gray-400' : 'text-white'}`}>{value ?? '—'}</span>
    </div>
  );
}

function Card({ title, icon, children }: { title: string; icon: string; children: React.ReactNode }) {
  return (
    <div className="rounded-2xl border border-dark-border p-5" style={{ background: '#0F1420' }}>
      <h2 className="text-sm font-semibold text-white mb-4 flex items-center gap-2">
        <span>{icon}</span> {title}
      </h2>
      {children}
    </div>
  );
}

function StatusChip({ label, color }: { label: string; color: 'green' | 'red' | 'yellow' | 'gray' }) {
  const cls = {
    green:  'bg-success/10 text-success-light border-success/25',
    red:    'bg-danger/10 text-danger-light border-danger/25',
    yellow: 'bg-yellow-500/10 text-yellow-400 border-yellow-500/25',
    gray:   'bg-gray-700/20 text-gray-500 border-gray-700/30',
  }[color];
  return <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-semibold border ${cls}`}>{label}</span>;
}

export default function UserDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router  = useRouter();

  const [user,    setUser]    = useState<AdminUserDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [toast,   setToast]   = useState<{ msg: string; ok: boolean } | null>(null);
  const [rejectRemark, setRejectRemark] = useState('');
  const [showReject,   setShowReject]   = useState(false);
  const [busy, setBusy] = useState(false);

  const showToast = (msg: string, ok = true) => {
    setToast({ msg, ok });
    setTimeout(() => setToast(null), 3500);
  };

  const load = async () => {
    try { setUser(await getUserDetail(id)); }
    catch { showToast('Failed to load user', false); }
    finally { setLoading(false); }
  };

  useEffect(() => { load(); }, [id]);

  const handleApproveKyc = async () => {
    if (!user?.kyc) return;
    setBusy(true);
    try { await approveKyc(user.kyc.id); showToast('KYC approved'); await load(); }
    catch { showToast('Failed to approve KYC', false); }
    finally { setBusy(false); }
  };

  const handleRejectKyc = async () => {
    if (!user?.kyc) return;
    setBusy(true);
    try {
      await rejectKyc(user.kyc.id, rejectRemark || 'Documents not acceptable');
      showToast('KYC rejected'); setShowReject(false); setRejectRemark('');
      await load();
    } catch { showToast('Failed to reject KYC', false); }
    finally { setBusy(false); }
  };

  const handleBan = async () => {
    if (!user) return;
    setBusy(true);
    try { await banUser(user.id, 'Admin action'); showToast('User banned'); await load(); }
    catch { showToast('Failed', false); }
    finally { setBusy(false); }
  };

  const handleUnban = async () => {
    if (!user) return;
    setBusy(true);
    try { await unbanUser(user.id); showToast('User unbanned'); await load(); }
    catch { showToast('Failed', false); }
    finally { setBusy(false); }
  };

  const kycColor = (s?: string | null): 'green' | 'red' | 'yellow' | 'gray' => {
    if (s === 'approved') return 'green';
    if (s === 'rejected') return 'red';
    if (s === 'pending')  return 'yellow';
    return 'gray';
  };

  if (loading) return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="w-8 h-8 rounded-full border-2 border-primary border-t-transparent animate-spin" />
    </div>
  );

  if (!user) return (
    <div className="min-h-screen flex flex-col items-center justify-center gap-4">
      <p className="text-4xl">😕</p>
      <p className="text-gray-400">User not found</p>
      <button onClick={() => router.back()} className="text-primary-light text-sm hover:underline">← Back</button>
    </div>
  );

  const age = user.age;
  const isMinor = user.is_minor;

  return (
    <div className="min-h-screen max-w-4xl mx-auto">
      {toast && (
        <div className={`fixed top-5 right-5 z-50 flex items-center gap-2 px-4 py-3 rounded-xl border text-sm font-medium shadow-xl
                         ${toast.ok ? 'bg-success/10 border-success/30 text-success-light' : 'bg-danger/10 border-danger/30 text-danger-light'}`}>
          <span>{toast.ok ? '✓' : '✕'}</span> {toast.msg}
        </div>
      )}

      {/* Header */}
      <div className="flex items-center gap-3 mb-7">
        <button onClick={() => router.back()}
                className="p-2 rounded-lg border border-dark-border text-gray-400 hover:bg-dark-border/40 transition-colors">
          ←
        </button>
        <div className="flex-1">
          <h1 className="text-xl font-bold text-white flex items-center gap-2">
            {user.username}
            {isMinor && <span className="px-2 py-0.5 rounded-full text-xs font-bold bg-danger text-white">🔞 MINOR</span>}
          </h1>
          <p className="text-gray-500 text-xs font-mono">{user.id}</p>
        </div>
        <div className="flex gap-2">
          {user.is_banned ? (
            <button onClick={handleUnban} disabled={busy}
                    className="px-4 py-2 rounded-xl text-sm font-semibold bg-success/10 text-success-light border border-success/25 hover:bg-success/20 transition-colors disabled:opacity-40">
              Unban User
            </button>
          ) : (
            <button onClick={handleBan} disabled={busy}
                    className="px-4 py-2 rounded-xl text-sm font-semibold bg-danger/10 text-danger-light border border-danger/25 hover:bg-danger/20 transition-colors disabled:opacity-40">
              Ban User
            </button>
          )}
        </div>
      </div>

      {/* Minor warning banner */}
      {isMinor && (
        <div className="mb-5 flex items-center gap-3 px-4 py-3.5 rounded-xl border-2 border-danger/50"
             style={{ background: 'rgba(239,68,68,0.08)' }}>
          <span className="text-2xl">⚠️</span>
          <div>
            <p className="text-danger-light font-bold text-sm">Underage User — Gambling Restriction Required</p>
            <p className="text-gray-400 text-xs mt-0.5">
              This user is {age} years old (under 18). Real-money betting should be blocked and account flagged for review.
            </p>
          </div>
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">

        {/* ── Basic Profile ──────────────────────────────────────────────── */}
        <Card title="Basic Profile" icon="👤">
          <InfoRow label="Username"  value={user.username} />
          <InfoRow label="Email"     value={user.email}    />
          <InfoRow label="Mobile"    value={user.mobile} mono />
          <InfoRow label="Provider"  value={user.provider} />
          <InfoRow label="Level"     value={`Lv.${user.level} · ${user.xp} XP`} />
          <InfoRow label="Coins"     value={`🪙 ${Number(user.coins).toLocaleString()}`} />
          <InfoRow label="Matches"   value={`${user.matches_played} played · ${user.matches_won} won`} />
          <InfoRow label="Joined"    value={formatDate(user.created_at)} />
          <InfoRow label="Last Seen" value={user.last_seen ? formatDate(user.last_seen) : '—'} />
          <InfoRow label="Status"    value={
            user.is_banned
              ? <StatusChip label="Banned" color="red" />
              : <StatusChip label="Active" color="green" />
          } />
          {user.is_banned && user.ban_reason && (
            <InfoRow label="Ban Reason" value={user.ban_reason} />
          )}
        </Card>

        {/* ── Age Verification ───────────────────────────────────────────── */}
        <Card title="Age Verification" icon="🎂">
          <InfoRow label="Date of Birth" value={user.date_of_birth ?? 'Not provided'} mono />
          <InfoRow label="Age" value={
            age !== null
              ? <span className={isMinor ? 'text-danger-light font-bold' : 'text-success-light'}>{age} years old</span>
              : <span className="text-gray-600">Not set</span>
          } />
          <InfoRow label="Verification" value={
            !user.date_of_birth
              ? <StatusChip label="Not Verified" color="gray" />
              : isMinor
                ? <StatusChip label="🔞 Under 18 — BLOCKED" color="red" />
                : <StatusChip label="✓ 18+ Verified" color="green" />
          } />
          {!user.date_of_birth && (
            <p className="text-gray-600 text-xs mt-3">
              User has not completed age verification. They should be prompted on next login.
            </p>
          )}
        </Card>

        {/* ── KYC Verification ───────────────────────────────────────────── */}
        <Card title="KYC Verification" icon="🪪">
          {!user.kyc ? (
            <div className="text-center py-6">
              <p className="text-gray-600 text-sm">No KYC submission yet</p>
              <p className="text-gray-700 text-xs mt-1">User must submit PAN card + selfie before first withdrawal</p>
            </div>
          ) : (
            <>
              <InfoRow label="Status" value={
                <StatusChip label={user.kyc.status.toUpperCase()} color={kycColor(user.kyc.status)} />
              } />
              <InfoRow label="Full Name"  value={user.kyc.full_name} />
              <InfoRow label="PAN Number" value={user.kyc.pan_number} mono />
              <InfoRow label="Submitted"  value={formatDate(user.kyc.submitted_at)} />
              {user.kyc.reviewed_at && (
                <InfoRow label="Reviewed" value={formatDate(user.kyc.reviewed_at)} />
              )}
              {user.kyc.admin_remark && (
                <InfoRow label="Remark" value={user.kyc.admin_remark} />
              )}

              {user.kyc.status === 'pending' && (
                <div className="mt-4 space-y-2">
                  {showReject ? (
                    <>
                      <textarea
                        value={rejectRemark}
                        onChange={e => setRejectRemark(e.target.value)}
                        placeholder="Reason for rejection (required)…"
                        className="w-full px-3 py-2 rounded-xl border border-dark-border bg-dark-bg
                                   text-sm text-white placeholder-gray-600 focus:outline-none focus:border-danger resize-none"
                        rows={2}
                      />
                      <div className="flex gap-2">
                        <button onClick={() => { setShowReject(false); setRejectRemark(''); }}
                                className="flex-1 py-2 rounded-lg border border-dark-border text-gray-400 text-sm hover:bg-dark-border/40 transition-colors">
                          Cancel
                        </button>
                        <button onClick={handleRejectKyc} disabled={busy || !rejectRemark.trim()}
                                className="flex-1 py-2 rounded-lg bg-danger text-white text-sm font-semibold disabled:opacity-40 transition-colors">
                          {busy ? 'Rejecting…' : 'Reject'}
                        </button>
                      </div>
                    </>
                  ) : (
                    <div className="flex gap-2">
                      <button onClick={handleApproveKyc} disabled={busy}
                              className="flex-1 py-2.5 rounded-xl text-white text-sm font-semibold disabled:opacity-40 transition-all"
                              style={{ background: 'linear-gradient(135deg,#10B981,#059669)', boxShadow: '0 4px 12px rgba(16,185,129,0.3)' }}>
                        {busy ? 'Approving…' : '✓ Approve KYC'}
                      </button>
                      <button onClick={() => setShowReject(true)}
                              className="flex-1 py-2.5 rounded-xl text-sm font-semibold border border-danger/30 text-danger-light
                                         hover:bg-danger/10 transition-colors">
                        ✕ Reject
                      </button>
                    </div>
                  )}
                </div>
              )}
            </>
          )}
        </Card>

        {/* ── Responsible Gaming ─────────────────────────────────────────── */}
        <Card title="Responsible Gaming" icon="🛡️">
          {!user.responsible_gaming ? (
            <div className="text-center py-6">
              <p className="text-gray-600 text-sm">No limits set</p>
              <p className="text-gray-700 text-xs mt-1">User has not configured any spending limits</p>
            </div>
          ) : (
            <>
              <InfoRow label="Daily Limit"   value={user.responsible_gaming.daily_limit   ? `₹${user.responsible_gaming.daily_limit}` : 'No limit'} />
              <InfoRow label="Weekly Limit"  value={user.responsible_gaming.weekly_limit  ? `₹${user.responsible_gaming.weekly_limit}` : 'No limit'} />
              <InfoRow label="Monthly Limit" value={user.responsible_gaming.monthly_limit ? `₹${user.responsible_gaming.monthly_limit}` : 'No limit'} />
              <InfoRow label="Self-Excluded" value={
                user.responsible_gaming.self_excluded
                  ? <StatusChip label="Yes — Excluded" color="red" />
                  : <StatusChip label="No" color="green" />
              } />
              {user.responsible_gaming.self_excluded && user.responsible_gaming.exclusion_until && (
                <InfoRow label="Excluded Until" value={formatDate(user.responsible_gaming.exclusion_until)} />
              )}
            </>
          )}
        </Card>

        {/* ── Notification Preferences ───────────────────────────────────── */}
        <Card title="Notification Preferences" icon="🔔">
          {(() => {
            const prefs = user.notification_prefs ?? { game: true, wallet: true, promo: true };
            const channels = [
              { label: 'OTP & Security',       key: 'otp',    on: true,         note: 'Always on — cannot be disabled' },
              { label: 'Game Room Alerts',      key: 'game',   on: prefs.game,   note: 'New bet rooms, match results'   },
              { label: 'Wallet & Payments',     key: 'wallet', on: prefs.wallet, note: 'Deposits, withdrawals, receipts' },
              { label: 'Promotions & General',  key: 'promo',  on: prefs.promo,  note: 'Admin broadcasts, offers'       },
            ];
            return (
              <div className="space-y-1">
                {channels.map(ch => (
                  <div key={ch.key}
                       className="flex items-center justify-between py-2.5 border-b border-dark-border/60 last:border-0">
                    <div>
                      <p className="text-white text-sm font-medium">{ch.label}</p>
                      <p className="text-gray-600 text-xs">{ch.note}</p>
                    </div>
                    <span className={`px-2.5 py-0.5 rounded-full text-xs font-bold border
                      ${ch.on
                        ? 'bg-success/10 text-success-light border-success/25'
                        : 'bg-danger/10 text-danger-light border-danger/25'}`}>
                      {ch.on ? '✓ On' : '✕ Off'}
                    </span>
                  </div>
                ))}
                <p className="text-gray-700 text-xs pt-2">
                  Preferences synced from user's device. OTP cannot be disabled.
                </p>
              </div>
            );
          })()}
        </Card>

      </div>
    </div>
  );
}
