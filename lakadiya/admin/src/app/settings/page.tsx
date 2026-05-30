'use client';
import { useEffect, useState } from 'react';
import { getAdminSettings, updateAdminSettings, type AdminSettings } from '../../lib/api';

function Toggle({ value, onChange, disabled }: { value: boolean; onChange: (v: boolean) => void; disabled?: boolean }) {
  return (
    <button type="button" onClick={() => !disabled && onChange(!value)}
            className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors
                        ${value ? 'bg-primary' : 'bg-dark-border'} ${disabled ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}`}>
      <span className={`inline-block h-4 w-4 rounded-full bg-white transition-transform
                        ${value ? 'translate-x-6' : 'translate-x-1'}`} />
    </button>
  );
}

function NumberInput({ value, onChange, min, max, step = 1, prefix, suffix }: {
  value: number; onChange: (v: number) => void;
  min?: number; max?: number; step?: number;
  prefix?: string; suffix?: string;
}) {
  return (
    <div className="flex items-center border border-dark-border rounded-xl overflow-hidden focus-within:border-primary transition-colors">
      {prefix && <span className="px-3 py-2 text-sm text-gray-400 bg-dark-border/30">{prefix}</span>}
      <input type="number" value={value} min={min} max={max} step={step}
             onChange={e => onChange(Number(e.target.value))}
             className="flex-1 px-3 py-2 bg-dark-bg text-sm text-white focus:outline-none min-w-0" />
      {suffix && <span className="px-3 py-2 text-sm text-gray-400 bg-dark-border/30">{suffix}</span>}
    </div>
  );
}

export default function SettingsPage() {
  const [settings, setSettings] = useState<AdminSettings | null>(null);
  const [draft,    setDraft]    = useState<AdminSettings | null>(null);
  const [loading,  setLoading]  = useState(true);
  const [saving,   setSaving]   = useState(false);
  const [toast, setToast] = useState<{ msg: string; ok: boolean } | null>(null);

  const showToast = (msg: string, ok = true) => {
    setToast({ msg, ok });
    setTimeout(() => setToast(null), 3500);
  };

  useEffect(() => {
    getAdminSettings()
      .then(s => { setSettings(s); setDraft({ ...s }); })
      .catch(() => {
        const defaults: AdminSettings = {
          maintenance_mode: false, registration_enabled: true,
          min_withdrawal: 100, max_withdrawal: 10000,
          welcome_bonus: 50, max_bet_amount: 100, platform_fee_pct: 0, payment_gateway_fee_pct: 2,
        };
        setSettings(defaults);
        setDraft({ ...defaults });
      })
      .finally(() => setLoading(false));
  }, []);

  const handleSave = async () => {
    if (!draft) return;
    setSaving(true);
    try {
      const updated = await updateAdminSettings(draft);
      setSettings(updated);
      setDraft({ ...updated });
      showToast('Settings saved successfully');
    } catch {
      showToast('Failed to save settings', false);
    } finally {
      setSaving(false);
    }
  };

  const isDirty = JSON.stringify(settings) !== JSON.stringify(draft);

  const set = <K extends keyof AdminSettings>(k: K, v: AdminSettings[K]) =>
    setDraft(d => d ? { ...d, [k]: v } : d);

  return (
    <div className="min-h-screen">
      {toast && (
        <div className={`fixed top-5 right-5 z-50 flex items-center gap-2 px-4 py-3 rounded-xl border text-sm font-medium shadow-lg
                         ${toast.ok ? 'bg-success/10 border-success/30 text-success-light' : 'bg-danger/10 border-danger/30 text-danger-light'}`}>
          <span>{toast.ok ? '✓' : '✕'}</span> {toast.msg}
        </div>
      )}

      {/* Header */}
      <div className="flex items-start justify-between mb-7">
        <div>
          <h1 className="text-2xl font-bold text-white flex items-center gap-2">
            <span className="text-3xl">⚙️</span>
            <span style={{ background: 'linear-gradient(90deg,#9CA3AF,#D1D5DB)', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' }}>
              Platform Settings
            </span>
          </h1>
          <p className="text-gray-500 text-sm mt-1">Configure platform-wide settings and limits</p>
        </div>
        {isDirty && !loading && (
          <div className="flex gap-3">
            <button onClick={() => setDraft(settings ? { ...settings } : null)}
                    className="px-4 py-2 rounded-xl border border-dark-border text-gray-400 text-sm hover:bg-dark-border/50 transition-colors">
              Reset
            </button>
            <button onClick={handleSave} disabled={saving}
                    className="px-4 py-2 rounded-xl text-white text-sm font-semibold disabled:opacity-50 transition-all"
                    style={{ background: 'linear-gradient(135deg, #6366F1, #8B5CF6)', boxShadow: '0 4px 12px rgba(99,102,241,0.3)' }}>
              {saving ? 'Saving…' : '✓ Save Changes'}
            </button>
          </div>
        )}
      </div>

      {loading ? (
        <div className="space-y-4">
          {[...Array(3)].map((_, i) => <div key={i} className="h-48 rounded-2xl bg-dark-card border border-dark-border animate-pulse" />)}
        </div>
      ) : draft ? (
        <div className="space-y-5">

          {/* Platform status */}
          <div className="rounded-2xl border border-dark-border p-5" style={{ background: '#0F1420' }}>
            <h2 className="text-sm font-semibold text-white mb-4 flex items-center gap-2">
              <span>🌐</span> Platform Status
            </h2>
            <div className="space-y-4">
              <div className="flex items-center justify-between py-3 border-b border-dark-border">
                <div>
                  <p className="text-white text-sm font-medium">Maintenance Mode</p>
                  <p className="text-gray-500 text-xs mt-0.5">Disable access for all non-admin users</p>
                </div>
                <Toggle value={draft.maintenance_mode} onChange={v => set('maintenance_mode', v)} />
              </div>
              {draft.maintenance_mode && (
                <div className="flex items-center gap-2 px-3 py-2.5 rounded-xl bg-danger/10 border border-danger/20">
                  <span className="text-danger text-sm">⚠</span>
                  <p className="text-danger-light text-xs">Maintenance mode is ON — users cannot access the platform</p>
                </div>
              )}
              <div className="flex items-center justify-between py-3">
                <div>
                  <p className="text-white text-sm font-medium">User Registration</p>
                  <p className="text-gray-500 text-xs mt-0.5">Allow new users to register</p>
                </div>
                <Toggle value={draft.registration_enabled} onChange={v => set('registration_enabled', v)} />
              </div>
            </div>
          </div>

          {/* Wallet limits */}
          <div className="rounded-2xl border border-dark-border p-5" style={{ background: '#0F1420' }}>
            <h2 className="text-sm font-semibold text-white mb-4 flex items-center gap-2">
              <span>💰</span> Wallet Configuration
            </h2>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-2 uppercase tracking-wider">Min Withdrawal</label>
                <NumberInput value={draft.min_withdrawal} onChange={v => set('min_withdrawal', v)} min={1} />
                <p className="text-xs text-gray-600 mt-1">Minimum amount users can withdraw</p>
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-2 uppercase tracking-wider">Max Withdrawal</label>
                <NumberInput value={draft.max_withdrawal} onChange={v => set('max_withdrawal', v)} min={1} />
                <p className="text-xs text-gray-600 mt-1">Maximum amount users can withdraw</p>
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-2 uppercase tracking-wider">Welcome Bonus</label>
                <NumberInput value={draft.welcome_bonus} onChange={v => set('welcome_bonus', v)} min={0} />
                <p className="text-xs text-gray-600 mt-1">Coins given to new users on signup</p>
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-2 uppercase tracking-wider">Platform Fee</label>
                <NumberInput value={draft.platform_fee_pct} onChange={v => set('platform_fee_pct', v)} min={0} max={50} step={0.5} suffix="%" />
                <p className="text-xs text-gray-600 mt-1">Percentage cut on bet winnings</p>
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-2 uppercase tracking-wider">Payment Gateway Fee</label>
                <NumberInput value={draft.payment_gateway_fee_pct} onChange={v => set('payment_gateway_fee_pct', v)} min={0} max={10} step={0.1} suffix="%" />
                <p className="text-xs text-gray-600 mt-1">Fee charged per wallet top-up transaction</p>
              </div>
            </div>
          </div>

          {/* Game settings */}
          <div className="rounded-2xl border border-dark-border p-5" style={{ background: '#0F1420' }}>
            <h2 className="text-sm font-semibold text-white mb-4 flex items-center gap-2">
              <span>🎮</span> Game Settings
            </h2>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-2 uppercase tracking-wider">Max Bet Amount</label>
                <NumberInput value={draft.max_bet_amount} onChange={v => set('max_bet_amount', v)} min={0} />
                <p className="text-xs text-gray-600 mt-1">Maximum allowed bet per room</p>
              </div>
            </div>
          </div>

          {/* Dirty state banner */}
          {isDirty && (
            <div className="flex items-center justify-between px-5 py-3.5 rounded-xl border"
                 style={{ background: 'rgba(99,102,241,0.08)', borderColor: 'rgba(99,102,241,0.2)' }}>
              <p className="text-primary-light text-sm">You have unsaved changes</p>
              <div className="flex gap-3">
                <button onClick={() => setDraft(settings ? { ...settings } : null)}
                        className="px-3 py-1.5 rounded-lg border border-dark-border text-gray-400 text-xs hover:bg-dark-border/50 transition-colors">
                  Reset
                </button>
                <button onClick={handleSave} disabled={saving}
                        className="px-3 py-1.5 rounded-lg text-white text-xs font-semibold disabled:opacity-50"
                        style={{ background: '#6366F1' }}>
                  {saving ? 'Saving…' : 'Save Changes'}
                </button>
              </div>
            </div>
          )}
        </div>
      ) : null}
    </div>
  );
}
