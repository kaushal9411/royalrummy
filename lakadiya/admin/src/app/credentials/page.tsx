'use client';
import { useEffect, useState } from 'react';
import {
  listCredentials, saveCredential, deleteCredential,
  type AdminCredential,
} from '../../lib/api';

// ── Suggested key names so admins don't have to guess ────────────────────────
const SUGGESTED_KEYS = [
  { key: 'razorpay_key_id',     label: 'Razorpay Key ID',       hint: 'rzp_live_…  (fetched by mobile app)' },
  { key: 'razorpay_key_secret', label: 'Razorpay Key Secret',   hint: 'Server-side only — never sent to app' },
  { key: 'gmail_user',          label: 'Gmail User',            hint: 'Email address for sending receipts' },
  { key: 'gmail_app_password',  label: 'Gmail App Password',    hint: 'Google App Password (not account password)' },
  { key: 'firebase_server_key', label: 'Firebase Server Key',   hint: 'FCM legacy server key (if not using service account)' },
];

function Toast({ msg, ok, onClose }: { msg: string; ok: boolean; onClose: () => void }) {
  return (
    <div className={`fixed top-5 right-5 z-50 flex items-center gap-3 px-4 py-3 rounded-xl border text-sm font-medium shadow-xl
                     ${ok ? 'bg-success/10 border-success/30 text-success-light' : 'bg-danger/10 border-danger/30 text-danger-light'}`}>
      <span>{ok ? '✓' : '✕'}</span>
      <span>{msg}</span>
      <button onClick={onClose} className="ml-2 opacity-60 hover:opacity-100">✕</button>
    </div>
  );
}

function ConfirmModal({ keyName, onConfirm, onCancel }: {
  keyName: string; onConfirm: () => void; onCancel: () => void;
}) {
  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center"
         style={{ background: 'rgba(0,0,0,0.75)', backdropFilter: 'blur(4px)' }}>
      <div className="w-full max-w-sm mx-4 rounded-2xl border p-6"
           style={{ background: '#0F1420', borderColor: 'rgba(239,68,68,0.3)' }}>
        <div className="flex items-center gap-3 mb-4">
          <span className="text-2xl">🗑️</span>
          <h3 className="text-white font-bold text-lg">Delete Credential?</h3>
        </div>
        <p className="text-gray-400 text-sm mb-2">
          You are about to permanently delete:
        </p>
        <p className="font-mono text-danger-light text-sm font-bold mb-4 px-3 py-2 rounded-lg"
           style={{ background: 'rgba(239,68,68,0.08)', border: '1px solid rgba(239,68,68,0.2)' }}>
          {keyName}
        </p>
        <p className="text-gray-500 text-xs mb-6">
          This cannot be undone. Any service relying on this key will stop working.
        </p>
        <div className="flex gap-3">
          <button onClick={onCancel}
                  className="flex-1 py-2.5 rounded-xl border border-dark-border text-gray-400 text-sm hover:bg-dark-border/40 transition-colors">
            Cancel
          </button>
          <button onClick={onConfirm}
                  className="flex-1 py-2.5 rounded-xl text-white text-sm font-semibold transition-all"
                  style={{ background: 'linear-gradient(135deg,#EF4444,#DC2626)', boxShadow: '0 4px 12px rgba(239,68,68,0.35)' }}>
            Delete
          </button>
        </div>
      </div>
    </div>
  );
}

export default function CredentialsPage() {
  const [credentials, setCredentials] = useState<AdminCredential[]>([]);
  const [loading, setLoading]         = useState(true);
  const [toast, setToast]             = useState<{ msg: string; ok: boolean } | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);
  const [deleting, setDeleting]         = useState(false);

  // Form state
  const [formKey,   setFormKey]   = useState('');
  const [formValue, setFormValue] = useState('');
  const [showValue, setShowValue] = useState(false);
  const [saving,    setSaving]    = useState(false);
  const [editMode,  setEditMode]  = useState<string | null>(null); // key_name being edited

  const showToast = (msg: string, ok = true) => {
    setToast({ msg, ok });
    setTimeout(() => setToast(null), 4000);
  };

  const load = async () => {
    try {
      setCredentials(await listCredentials());
    } catch {
      showToast('Failed to load credentials', false);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, []);

  const handleSave = async () => {
    const k = formKey.trim();
    const v = formValue.trim();
    if (!k) { showToast('Key name is required', false); return; }
    if (!v) { showToast('Value is required', false); return; }
    setSaving(true);
    try {
      await saveCredential(k, v);
      showToast(editMode ? `"${k}" updated successfully` : `"${k}" saved successfully`);
      setFormKey(''); setFormValue(''); setEditMode(null); setShowValue(false);
      await load();
    } catch {
      showToast('Failed to save credential', false);
    } finally {
      setSaving(false);
    }
  };

  const handleEdit = (cred: AdminCredential) => {
    setEditMode(cred.key_name);
    setFormKey(cred.key_name);
    setFormValue(''); // never pre-fill the value for security
    setShowValue(false);
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    setDeleting(true);
    try {
      await deleteCredential(deleteTarget);
      showToast(`"${deleteTarget}" deleted`);
      setDeleteTarget(null);
      await load();
    } catch {
      showToast('Failed to delete credential', false);
    } finally {
      setDeleting(false);
    }
  };

  const cancelEdit = () => {
    setEditMode(null); setFormKey(''); setFormValue(''); setShowValue(false);
  };

  const fmt = (iso: string) => {
    try {
      return new Date(iso).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' });
    } catch { return iso; }
  };

  return (
    <div className="min-h-screen">
      {toast && <Toast msg={toast.msg} ok={toast.ok} onClose={() => setToast(null)} />}
      {deleteTarget && (
        <ConfirmModal
          keyName={deleteTarget}
          onConfirm={handleDelete}
          onCancel={() => setDeleteTarget(null)}
        />
      )}

      {/* Header */}
      <div className="mb-7">
        <h1 className="text-2xl font-bold text-white flex items-center gap-2">
          <span className="text-3xl">🔐</span>
          <span style={{ background: 'linear-gradient(90deg,#6366F1,#8B5CF6)', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' }}>
            Credentials Manager
          </span>
        </h1>
        <p className="text-gray-500 text-sm mt-1">
          Store API keys and secrets encrypted in the database (AES-256). Values are never returned in plaintext.
        </p>
      </div>

      {/* Security banner */}
      <div className="mb-6 flex items-start gap-3 px-4 py-3.5 rounded-xl border"
           style={{ background: 'rgba(99,102,241,0.06)', borderColor: 'rgba(99,102,241,0.2)' }}>
        <span className="text-base mt-0.5">🛡️</span>
        <p className="text-gray-400 text-xs leading-relaxed">
          All values are encrypted with AES-256-GCM before storage. The masked preview shows only the first and last 4 characters.
          The mobile app fetches only <code className="text-primary-light">razorpay_key_id</code> — all other keys remain server-side.
        </p>
      </div>

      {/* ── Add / Edit form ──────────────────────────────────────────────────── */}
      <div className="rounded-2xl border border-dark-border p-5 mb-6"
           style={{ background: '#0F1420' }}>
        <h2 className="text-sm font-semibold text-white mb-4 flex items-center gap-2">
          <span>{editMode ? '✏️' : '➕'}</span>
          {editMode ? `Edit — ${editMode}` : 'Add / Update Credential'}
        </h2>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 mb-4">
          {/* Key name */}
          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1.5 uppercase tracking-wider">Key Name</label>
            <input
              value={formKey}
              onChange={e => setFormKey(e.target.value)}
              disabled={!!editMode}
              placeholder="e.g. razorpay_key_id"
              className="w-full px-3 py-2.5 rounded-xl border border-dark-border bg-dark-bg text-white text-sm
                         focus:outline-none focus:border-primary transition-colors
                         placeholder-gray-600 disabled:opacity-50 disabled:cursor-not-allowed font-mono"
            />
            {/* Suggested keys */}
            {!editMode && (
              <div className="flex flex-wrap gap-1.5 mt-2">
                {SUGGESTED_KEYS.map(s => (
                  <button key={s.key}
                          onClick={() => setFormKey(s.key)}
                          className="px-2 py-0.5 rounded-md text-xs border border-dark-border text-gray-400
                                     hover:border-primary/40 hover:text-primary-light transition-colors font-mono">
                    {s.key}
                  </button>
                ))}
              </div>
            )}
          </div>

          {/* Value */}
          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1.5 uppercase tracking-wider">
              Value {editMode && <span className="text-gray-600 normal-case">(leave blank to keep existing)</span>}
            </label>
            <div className="relative">
              <input
                type={showValue ? 'text' : 'password'}
                value={formValue}
                onChange={e => setFormValue(e.target.value)}
                placeholder={editMode ? 'Enter new value to change…' : 'Paste the secret key value…'}
                className="w-full px-3 py-2.5 pr-10 rounded-xl border border-dark-border bg-dark-bg text-white text-sm
                           focus:outline-none focus:border-primary transition-colors placeholder-gray-600 font-mono"
              />
              <button type="button" onClick={() => setShowValue(v => !v)}
                      className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-500 hover:text-gray-300 transition-colors text-xs">
                {showValue ? '🙈' : '👁️'}
              </button>
            </div>
            {/* Hint for selected key */}
            {formKey && (() => {
              const hint = SUGGESTED_KEYS.find(s => s.key === formKey)?.hint;
              return hint ? <p className="text-xs text-gray-600 mt-1.5">{hint}</p> : null;
            })()}
          </div>
        </div>

        <div className="flex gap-3">
          <button
            onClick={handleSave}
            disabled={saving || !formKey.trim() || (!formValue.trim() && !editMode)}
            className="px-5 py-2.5 rounded-xl text-white text-sm font-semibold disabled:opacity-40 transition-all"
            style={{ background: 'linear-gradient(135deg,#6366F1,#8B5CF6)', boxShadow: '0 4px 12px rgba(99,102,241,0.3)' }}>
            {saving ? 'Saving…' : editMode ? '✓ Update' : '✓ Save Credential'}
          </button>
          {editMode && (
            <button onClick={cancelEdit}
                    className="px-4 py-2.5 rounded-xl border border-dark-border text-gray-400 text-sm hover:bg-dark-border/40 transition-colors">
              Cancel
            </button>
          )}
        </div>
      </div>

      {/* ── Credentials table ─────────────────────────────────────────────────── */}
      <div className="rounded-2xl border border-dark-border overflow-hidden" style={{ background: '#0F1420' }}>
        <div className="px-5 py-4 border-b border-dark-border flex items-center justify-between">
          <h2 className="text-sm font-semibold text-white flex items-center gap-2">
            <span>📋</span> Stored Credentials
            <span className="ml-1 px-2 py-0.5 rounded-full text-xs font-bold"
                  style={{ background: 'rgba(99,102,241,0.15)', color: '#818CF8' }}>
              {credentials.length}
            </span>
          </h2>
          <button onClick={load}
                  className="text-xs text-gray-500 hover:text-gray-300 transition-colors flex items-center gap-1.5">
            <span>↻</span> Refresh
          </button>
        </div>

        {loading ? (
          <div className="space-y-0">
            {[...Array(3)].map((_, i) => (
              <div key={i} className="h-14 border-b border-dark-border/50 animate-pulse"
                   style={{ background: 'rgba(255,255,255,0.02)' }} />
            ))}
          </div>
        ) : credentials.length === 0 ? (
          <div className="py-16 text-center">
            <p className="text-4xl mb-3">🔑</p>
            <p className="text-gray-500 text-sm">No credentials stored yet</p>
            <p className="text-gray-600 text-xs mt-1">Use the form above to add your first credential</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr style={{ borderBottom: '1px solid rgba(255,255,255,0.06)' }}>
                  {['Key Name', 'Masked Value', 'Last Updated', 'Actions'].map(h => (
                    <th key={h} className="text-left px-5 py-3 text-xs font-semibold uppercase tracking-wider text-gray-600">
                      {h}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {credentials.map((cred, i) => (
                  <tr key={cred.key_name}
                      className="group transition-colors hover:bg-white/[0.02]"
                      style={{ borderBottom: i < credentials.length - 1 ? '1px solid rgba(255,255,255,0.04)' : 'none' }}>

                    {/* Key name */}
                    <td className="px-5 py-3.5">
                      <div className="flex items-center gap-2">
                        <span className="font-mono text-primary-light text-sm font-medium">{cred.key_name}</span>
                        {cred.key_name === 'razorpay_key_id' && (
                          <span className="px-1.5 py-0.5 rounded text-xs"
                                style={{ background: 'rgba(16,185,129,0.12)', color: '#6EE7B7', border: '1px solid rgba(16,185,129,0.2)' }}>
                            App
                          </span>
                        )}
                      </div>
                    </td>

                    {/* Masked value */}
                    <td className="px-5 py-3.5">
                      <code className="font-mono text-xs text-gray-400 tracking-widest"
                            style={{ background: 'rgba(255,255,255,0.04)', padding: '2px 8px', borderRadius: 6 }}>
                        {cred.masked_value}
                      </code>
                    </td>

                    {/* Updated at */}
                    <td className="px-5 py-3.5 text-gray-500 text-xs whitespace-nowrap">
                      {fmt(cred.updated_at)}
                    </td>

                    {/* Actions */}
                    <td className="px-5 py-3.5">
                      <div className="flex items-center gap-2">
                        <button onClick={() => handleEdit(cred)}
                                className="px-3 py-1.5 rounded-lg text-xs font-medium border border-dark-border text-gray-400
                                           hover:border-primary/40 hover:text-primary-light transition-all">
                          ✏️ Edit
                        </button>
                        <button onClick={() => setDeleteTarget(cred.key_name)}
                                disabled={deleting}
                                className="px-3 py-1.5 rounded-lg text-xs font-medium border border-transparent text-gray-500
                                           hover:border-danger/30 hover:text-danger-light hover:bg-danger/5 transition-all disabled:opacity-40">
                          🗑️ Delete
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Reference: what each suggested key does */}
      <div className="mt-6 rounded-2xl border border-dark-border p-5" style={{ background: '#0F1420' }}>
        <h3 className="text-sm font-semibold text-white mb-3 flex items-center gap-2">
          <span>📖</span> Key Reference
        </h3>
        <div className="space-y-2">
          {SUGGESTED_KEYS.map(s => (
            <div key={s.key} className="flex items-start gap-3 py-2 border-b border-dark-border/50 last:border-0">
              <code className="font-mono text-primary-light text-xs w-48 flex-shrink-0 pt-0.5">{s.key}</code>
              <span className="text-gray-500 text-xs">{s.hint}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
