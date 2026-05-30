'use client';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import {
  getPendingKyc, approveKyc, rejectKyc, kycDocUrl,
  type KycSubmission,
} from '../../lib/api';
import { formatDate } from '../../lib/utils';

// ── Document lightbox ─────────────────────────────────────────────────────────
function DocViewer({
  kycId, docType, label, onClose,
}: {
  kycId: string;
  docType: 'pan_doc' | 'selfie';
  label: string;
  onClose: () => void;
}) {
  const url = kycDocUrl(kycId, docType);
  const isPdf = false; // multer saves .jpg/.png so always image in practice

  return (
    <div
      className="fixed inset-0 z-50 flex flex-col items-center justify-center"
      style={{ background: 'rgba(0,0,0,0.92)', backdropFilter: 'blur(8px)' }}
    >
      {/* Header */}
      <div className="w-full max-w-3xl flex items-center justify-between px-4 py-3 mb-3">
        <div className="flex items-center gap-2">
          <span className="text-white font-semibold text-sm">{label}</span>
          <span className="text-gray-500 text-xs font-mono">{kycId.slice(0, 8)}…</span>
        </div>
        <div className="flex items-center gap-2">
          <a
            href={url}
            target="_blank"
            rel="noopener noreferrer"
            className="px-3 py-1.5 rounded-lg border border-dark-border text-gray-300 text-xs
                       hover:border-primary/40 hover:text-primary-light transition-all"
          >
            ↗ Open Full Size
          </a>
          <button
            onClick={onClose}
            className="px-3 py-1.5 rounded-lg border border-dark-border text-gray-400 text-xs hover:bg-white/5 transition-colors"
          >
            ✕ Close
          </button>
        </div>
      </div>

      {/* Image */}
      <div className="w-full max-w-3xl flex-1 overflow-auto flex items-center justify-center px-4 pb-8">
        {isPdf ? (
          <iframe src={url} className="w-full h-full rounded-xl" title={label} />
        ) : (
          /* eslint-disable-next-line @next/next/no-img-element */
          <img
            src={url}
            alt={label}
            className="max-w-full max-h-[75vh] rounded-xl border border-white/10 object-contain"
            onError={(e) => {
              (e.target as HTMLImageElement).src = '';
              (e.target as HTMLImageElement).alt = 'Failed to load document';
            }}
          />
        )}
      </div>
    </div>
  );
}

// ── Thumb preview ─────────────────────────────────────────────────────────────
function DocThumb({
  kycId, docType, label, onClick,
}: {
  kycId: string; docType: 'pan_doc' | 'selfie'; label: string; onClick: () => void;
}) {
  const url = kycDocUrl(kycId, docType);
  return (
    <button
      onClick={onClick}
      className="flex flex-col items-center gap-1.5 group"
    >
      <div
        className="w-24 h-20 rounded-xl overflow-hidden border-2 border-dark-border
                   group-hover:border-primary/50 transition-colors relative"
        style={{ background: '#0B0F1A' }}
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={url}
          alt={label}
          className="w-full h-full object-cover"
          onError={(e) => { (e.currentTarget.parentElement!).classList.add('doc-error'); }}
        />
        <div className="absolute inset-0 bg-black/0 group-hover:bg-black/30 transition-colors flex items-center justify-center">
          <span className="opacity-0 group-hover:opacity-100 text-white text-lg transition-opacity">🔍</span>
        </div>
      </div>
      <span className="text-gray-500 text-xs">{label}</span>
    </button>
  );
}

// ── Main page ─────────────────────────────────────────────────────────────────
export default function KycPage() {
  const router = useRouter();
  const [submissions, setSubmissions]     = useState<KycSubmission[]>([]);
  const [loading,     setLoading]         = useState(true);
  const [busy,        setBusy]            = useState<string | null>(null);
  const [toast,       setToast]           = useState<{ msg: string; ok: boolean } | null>(null);
  const [rejectTarget, setRejectTarget]   = useState<KycSubmission | null>(null);
  const [rejectRemark, setRejectRemark]   = useState('');
  const [viewer, setViewer]               = useState<{ kycId: string; docType: 'pan_doc' | 'selfie'; label: string } | null>(null);

  const showToast = (msg: string, ok = true) => {
    setToast({ msg, ok });
    setTimeout(() => setToast(null), 3500);
  };

  const load = async () => {
    setLoading(true);
    try { setSubmissions(await getPendingKyc()); }
    catch { showToast('Failed to load KYC submissions', false); }
    finally { setLoading(false); }
  };

  useEffect(() => { load(); }, []);

  const handleApprove = async (kyc: KycSubmission) => {
    setBusy(kyc.id);
    try { await approveKyc(kyc.id); showToast(`KYC approved for ${kyc.username}`); await load(); }
    catch { showToast('Failed to approve', false); }
    finally { setBusy(null); }
  };

  const handleReject = async () => {
    if (!rejectTarget) return;
    setBusy(rejectTarget.id);
    try {
      await rejectKyc(rejectTarget.id, rejectRemark || 'Documents not acceptable');
      showToast(`KYC rejected for ${rejectTarget.username}`);
      setRejectTarget(null); setRejectRemark('');
      await load();
    } catch { showToast('Failed to reject', false); }
    finally { setBusy(null); }
  };

  return (
    <div className="min-h-screen">
      {/* Toast */}
      {toast && (
        <div className={`fixed top-5 right-5 z-40 flex items-center gap-2 px-4 py-3 rounded-xl border text-sm font-medium shadow-xl
                         ${toast.ok ? 'bg-success/10 border-success/30 text-success-light' : 'bg-danger/10 border-danger/30 text-danger-light'}`}>
          <span>{toast.ok ? '✓' : '✕'}</span> {toast.msg}
        </div>
      )}

      {/* Document lightbox */}
      {viewer && (
        <DocViewer
          kycId={viewer.kycId}
          docType={viewer.docType}
          label={viewer.label}
          onClose={() => setViewer(null)}
        />
      )}

      {/* Reject modal */}
      {rejectTarget && (
        <div className="fixed inset-0 z-40 flex items-center justify-center"
             style={{ background: 'rgba(0,0,0,0.75)', backdropFilter: 'blur(4px)' }}>
          <div className="w-full max-w-sm mx-4 rounded-2xl border border-dark-border p-6" style={{ background: '#0F1420' }}>
            <h3 className="text-white font-bold text-lg mb-1">Reject KYC</h3>
            <p className="text-gray-400 text-sm mb-4">
              Rejecting <span className="text-white font-semibold">{rejectTarget.username}</span>
            </p>
            <textarea
              value={rejectRemark}
              onChange={e => setRejectRemark(e.target.value)}
              placeholder="Reason (e.g. PAN card unclear, selfie mismatch)…"
              className="w-full px-3 py-2.5 rounded-xl border border-dark-border bg-dark-bg text-white text-sm
                         placeholder-gray-600 focus:outline-none focus:border-danger resize-none mb-4"
              rows={3}
            />
            <div className="flex gap-3">
              <button onClick={() => { setRejectTarget(null); setRejectRemark(''); }}
                      className="flex-1 py-2 rounded-lg border border-dark-border text-gray-400 text-sm hover:bg-dark-border/40 transition-colors">
                Cancel
              </button>
              <button onClick={handleReject} disabled={!!busy}
                      className="flex-1 py-2 rounded-lg bg-danger text-white text-sm font-semibold disabled:opacity-40 transition-colors">
                {busy ? 'Rejecting…' : 'Reject KYC'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Header */}
      <div className="flex items-start justify-between mb-7">
        <div>
          <h1 className="text-2xl font-bold text-white flex items-center gap-2">
            <span className="text-3xl">🪪</span>
            <span style={{ background: 'linear-gradient(90deg,#F59E0B,#EF4444)', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' }}>
              KYC Review Queue
            </span>
          </h1>
          <p className="text-gray-500 text-sm mt-1">
            {submissions.length} pending submission{submissions.length !== 1 ? 's' : ''} awaiting review
          </p>
        </div>
        <button onClick={load}
                className="flex items-center gap-2 px-4 py-2 rounded-xl border border-dark-border text-gray-400 text-sm hover:bg-dark-border/40 transition-all">
          ↻ Refresh
        </button>
      </div>

      {/* List */}
      {loading ? (
        <div className="space-y-3">
          {[...Array(3)].map((_, i) => (
            <div key={i} className="h-52 rounded-2xl bg-dark-card border border-dark-border animate-pulse" />
          ))}
        </div>
      ) : submissions.length === 0 ? (
        <div className="rounded-2xl border border-dark-border p-16 text-center" style={{ background: '#0F1420' }}>
          <p className="text-4xl mb-4">✅</p>
          <p className="text-white font-semibold text-lg">All Clear</p>
          <p className="text-gray-500 text-sm mt-1">No pending KYC submissions</p>
        </div>
      ) : (
        <div className="space-y-5">
          {submissions.map((kyc) => (
            <div key={kyc.id} className="rounded-2xl border p-5"
                 style={{ background: '#0F1420', borderColor: 'rgba(245,158,11,0.2)' }}>

              {/* Top row: user info + actions */}
              <div className="flex items-start justify-between gap-4 flex-wrap mb-5">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-full flex items-center justify-center text-sm font-bold flex-shrink-0"
                       style={{ background: 'rgba(245,158,11,0.15)', border: '1px solid rgba(245,158,11,0.3)', color: '#FCD34D' }}>
                    {kyc.username?.[0]?.toUpperCase()}
                  </div>
                  <div>
                    <button onClick={() => router.push(`/users/${kyc.user_id}`)}
                            className="text-white font-semibold hover:text-primary-light transition-colors text-left">
                      {kyc.username}
                    </button>
                    <p className="text-gray-500 text-xs font-mono">{kyc.mobile ?? '—'}</p>
                  </div>
                </div>
                <div className="flex gap-2 flex-shrink-0 flex-wrap">
                  <button onClick={() => router.push(`/users/${kyc.user_id}`)}
                          className="px-3 py-1.5 rounded-lg border border-dark-border text-gray-400 text-xs hover:border-primary/40 hover:text-primary-light transition-all">
                    👤 User Profile
                  </button>
                  <button onClick={() => handleApprove(kyc)} disabled={!!busy}
                          className="px-4 py-1.5 rounded-lg text-white text-xs font-semibold disabled:opacity-40 transition-all"
                          style={{ background: 'linear-gradient(135deg,#10B981,#059669)' }}>
                    {busy === kyc.id ? '…' : '✓ Approve'}
                  </button>
                  <button onClick={() => { setRejectTarget(kyc); setRejectRemark(''); }} disabled={!!busy}
                          className="px-4 py-1.5 rounded-lg text-xs font-semibold border border-danger/30 text-danger-light
                                     hover:bg-danger/10 transition-colors disabled:opacity-40">
                    ✕ Reject
                  </button>
                </div>
              </div>

              {/* Details + Documents side by side */}
              <div className="flex flex-wrap gap-6">
                {/* KYC details */}
                <div className="flex-1 min-w-[220px] space-y-2">
                  <DetailRow label="Full Name"  value={kyc.full_name ?? '—'} />
                  <DetailRow label="PAN Number" value={kyc.pan_number ?? '—'} mono />
                  <DetailRow label="Submitted"  value={formatDate(kyc.submitted_at)} />
                </div>

                {/* Document previews */}
                <div className="flex-shrink-0">
                  <p className="text-gray-600 text-xs uppercase tracking-wider mb-2.5">Documents</p>
                  <div className="flex gap-4">
                    {kyc.pan_doc_path ? (
                      <DocThumb
                        kycId={kyc.id}
                        docType="pan_doc"
                        label="PAN Card"
                        onClick={() => setViewer({ kycId: kyc.id, docType: 'pan_doc', label: `PAN Card — ${kyc.username}` })}
                      />
                    ) : (
                      <div className="w-24 h-20 rounded-xl border-2 border-dashed border-dark-border flex items-center justify-center">
                        <span className="text-gray-700 text-xs">No file</span>
                      </div>
                    )}
                    {kyc.selfie_path ? (
                      <DocThumb
                        kycId={kyc.id}
                        docType="selfie"
                        label="Selfie"
                        onClick={() => setViewer({ kycId: kyc.id, docType: 'selfie', label: `Selfie — ${kyc.username}` })}
                      />
                    ) : (
                      <div className="w-24 h-20 rounded-xl border-2 border-dashed border-dark-border flex items-center justify-center">
                        <span className="text-gray-700 text-xs">No file</span>
                      </div>
                    )}
                  </div>
                  <p className="text-gray-700 text-xs mt-2">Click a thumbnail to view full size</p>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function DetailRow({ label, value, mono = false }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="flex items-center gap-3">
      <span className="text-gray-600 text-xs w-24 flex-shrink-0">{label}</span>
      <span className={`text-sm ${mono ? 'font-mono text-gray-300' : 'text-white'}`}>{value}</span>
    </div>
  );
}
