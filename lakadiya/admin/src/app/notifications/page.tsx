'use client';
import { useState, useEffect } from 'react';
import { sendBroadcastNotification, getNotificationHistory, type NotificationLog } from '../../lib/api';
import { formatDateTime } from '../../lib/utils';

type NotifType = 'GENERAL' | 'PROMO' | 'ALERT' | 'EVENT';
type Template  = { type: NotifType; label: string; title: string; body: string };

const QUICK_TEMPLATES: Record<NotifType, Template[]> = {
  GENERAL: [
    {
      type: 'GENERAL', label: 'Back Online',
      title: '✅ We\'re Back Online!',
      body:  'Maintenance is complete! The app is fully restored and running smoothly. Come back and enjoy the game!',
    },
    {
      type: 'GENERAL', label: 'Back Online (Hindi)',
      title: '✅ ऐप वापस आ गया है!',
      body:  'रखरखाव पूरा हो गया है! ऐप अब पूरी तरह से ठीक है। वापस आएं और खेलें — आपका इंतजार है!',
    },
    {
      type: 'GENERAL', label: 'New Feature',
      title: '✨ New Feature Available',
      body:  'Exciting new features have been added to Lakadiya. Update to the latest version and check them out!',
    },
    {
      type: 'GENERAL', label: 'App Update',
      title: '📱 New App Update Available',
      body:  'A new version of Lakadiya is live on the store. Update now for a faster and smoother experience!',
    },
  ],
  PROMO: [
    {
      type: 'PROMO', label: 'Limited Offer',
      title: '💰 Limited Time Offer!',
      body:  'Add money now and get 20% bonus coins. Offer valid for 24 hours only — don\'t miss it!',
    },
    {
      type: 'PROMO', label: 'Free Bonus',
      title: '🎁 Free Bonus Waiting for You!',
      body:  'Your free bonus coins are ready to claim. Open the app and visit your wallet to collect before they expire!',
    },
    {
      type: 'PROMO', label: 'Deposit Cashback',
      title: '💸 50% Cashback — Today Only!',
      body:  'Add ₹200 or more today and receive 50% cashback instantly in your wallet. Limited slots available!',
    },
    {
      type: 'PROMO', label: 'Refer & Earn',
      title: '👥 Refer Friends, Earn ₹100!',
      body:  'Invite a friend to Lakadiya and earn ₹100 for every friend who signs up and plays their first game!',
    },
  ],
  ALERT: [
    {
      type: 'ALERT', label: 'Scheduled Maintenance',
      title: '🔧 Scheduled Maintenance',
      body:  'The platform will be briefly down for maintenance. We\'ll be back soon. Thank you for your patience!',
    },
    {
      type: 'ALERT', label: 'Emergency Downtime',
      title: '⚠️ Temporary Service Disruption',
      body:  'We\'re experiencing a technical issue and working to resolve it urgently. We apologise for the inconvenience.',
    },
    {
      type: 'ALERT', label: 'KYC Reminder',
      title: '📋 Complete Your KYC',
      body:  'KYC verification is required to withdraw winnings. Complete it now in Settings → Profile to unlock withdrawals.',
    },
    {
      type: 'ALERT', label: 'Account Security',
      title: '🔐 Security Reminder',
      body:  'Never share your OTP or password with anyone. Lakadiya staff will never ask for your OTP.',
    },
  ],
  EVENT: [
    {
      type: 'EVENT', label: 'Weekend Event',
      title: '🎉 Weekend Special Event!',
      body:  'Play this weekend for double XP and bonus rewards. Compete with top players — don\'t miss out!',
    },
    {
      type: 'EVENT', label: 'Tournament',
      title: '🏆 Tournament Starting Soon!',
      body:  'A big tournament kicks off in 30 minutes! Register now from the lobby and compete for the top prize.',
    },
    {
      type: 'EVENT', label: 'Daily Free Game',
      title: '🃏 Your Free Daily Game is Ready!',
      body:  'Your free daily game is available now. Play with no entry fee for a chance to win real cash!',
    },
    {
      type: 'EVENT', label: 'Festival Bonus',
      title: '🪔 Festival Special Bonus!',
      body:  'Celebrating the festive season with 2x winnings on all games today. Limited time — play now!',
    },
  ],
};

export default function NotificationsPage() {
  const [title,        setTitle]        = useState('');
  const [body,         setBody]         = useState('');
  const [type,         setType]         = useState<NotifType>('GENERAL');
  const [sending,      setSending]      = useState(false);
  const [history,      setHistory]      = useState<NotificationLog[]>([]);
  const [histLoading,  setHistLoading]  = useState(true);
  const [toast,        setToast]        = useState<{ msg: string; ok: boolean } | null>(null);
  const [templateTab,  setTemplateTab]  = useState<NotifType>('GENERAL');

  const showToast = (msg: string, ok = true) => {
    setToast({ msg, ok });
    setTimeout(() => setToast(null), 4000);
  };

  const loadHistory = async () => {
    try {
      setHistory(await getNotificationHistory());
    } catch {
      setHistory([]);
    } finally {
      setHistLoading(false);
    }
  };

  useEffect(() => { loadHistory(); }, []);

  const handleSend = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim() || !body.trim()) return;
    setSending(true);
    try {
      const result = await sendBroadcastNotification({ title: title.trim(), body: body.trim(), type });
      showToast(`Broadcast sent to ${result.sent ?? 'all'} devices`);
      setTitle(''); setBody('');
      loadHistory();
    } catch {
      showToast('Failed to send broadcast notification', false);
    } finally {
      setSending(false);
    }
  };

  const applyTemplate = (t: Template) => {
    setTitle(t.title);
    setBody(t.body);
    setType(t.type);
    window.scrollTo({ top: 0, behavior: 'smooth' });
  };

  const TYPE_COLORS: Record<NotifType, string> = {
    GENERAL: '#6366F1',
    PROMO:   '#F59E0B',
    ALERT:   '#EF4444',
    EVENT:   '#10B981',
  };

  return (
    <div className="min-h-screen">
      {toast && (
        <div className={`fixed top-5 right-5 z-50 flex items-center gap-2 px-4 py-3 rounded-xl border text-sm font-medium shadow-lg
                         ${toast.ok ? 'bg-success/10 border-success/30 text-success-light' : 'bg-danger/10 border-danger/30 text-danger-light'}`}>
          <span>{toast.ok ? '✓' : '✕'}</span> {toast.msg}
        </div>
      )}

      {/* Header */}
      <div className="mb-7">
        <h1 className="text-2xl font-bold text-white flex items-center gap-2">
          <span className="text-3xl">🔔</span>
          <span style={{ background: 'linear-gradient(90deg,#FCD34D,#F59E0B)', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' }}>
            Notifications
          </span>
        </h1>
        <p className="text-gray-500 text-sm mt-1">Send broadcast notifications to all users</p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Compose form */}
        <div>
          <div className="rounded-2xl border border-dark-border p-5 mb-5" style={{ background: '#0F1420' }}>
            <h2 className="text-sm font-semibold text-white mb-4 flex items-center gap-2">
              <span>📢</span> Compose Broadcast
            </h2>
            <form onSubmit={handleSend} className="space-y-4">
              {/* Type selector */}
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-2 uppercase tracking-wider">Type</label>
                <div className="flex gap-2 flex-wrap">
                  {(['GENERAL', 'PROMO', 'ALERT', 'EVENT'] as NotifType[]).map(t => (
                    <button key={t} type="button" onClick={() => setType(t)}
                            className={`px-3 py-1.5 rounded-lg text-xs font-semibold border transition-all
                                        ${type === t
                                          ? 'text-white'
                                          : 'text-gray-500 border-dark-border hover:text-gray-300'}`}
                            style={type === t ? { background: `${TYPE_COLORS[t]}20`, borderColor: `${TYPE_COLORS[t]}40`, color: TYPE_COLORS[t] } : {}}>
                      {t}
                    </button>
                  ))}
                </div>
              </div>

              {/* Title */}
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-1.5 uppercase tracking-wider">Title</label>
                <input value={title} onChange={e => setTitle(e.target.value)} required
                       maxLength={100}
                       placeholder="Notification title…"
                       className="w-full px-3 py-2.5 rounded-xl border border-dark-border bg-dark-bg
                                  text-sm text-white placeholder-gray-600 focus:outline-none focus:border-primary transition-colors" />
                <p className="text-xs text-gray-600 mt-1 text-right">{title.length}/100</p>
              </div>

              {/* Body */}
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-1.5 uppercase tracking-wider">Message</label>
                <textarea value={body} onChange={e => setBody(e.target.value)} required rows={4}
                          maxLength={500}
                          placeholder="Write your message here…"
                          className="w-full px-3 py-2.5 rounded-xl border border-dark-border bg-dark-bg
                                     text-sm text-white placeholder-gray-600 focus:outline-none focus:border-primary resize-none transition-colors" />
                <p className="text-xs text-gray-600 mt-1 text-right">{body.length}/500</p>
              </div>

              {/* Preview */}
              {(title || body) && (
                <div className="rounded-xl border border-dark-border p-3.5" style={{ background: '#06080F' }}>
                  <p className="text-xs text-gray-500 mb-2 uppercase tracking-wider">Preview</p>
                  <div className="flex gap-3">
                    <div className="w-9 h-9 rounded-xl flex items-center justify-center text-lg flex-shrink-0"
                         style={{ background: `${TYPE_COLORS[type]}18`, border: `1px solid ${TYPE_COLORS[type]}25` }}>
                      🔔
                    </div>
                    <div className="min-w-0">
                      <p className="text-white text-sm font-semibold truncate">{title || 'Notification Title'}</p>
                      <p className="text-gray-400 text-xs mt-0.5 line-clamp-2">{body || 'Message body…'}</p>
                    </div>
                  </div>
                </div>
              )}

              <button type="submit" disabled={sending || !title.trim() || !body.trim()}
                      className="w-full py-3 rounded-xl font-semibold text-white text-sm transition-all
                                 disabled:opacity-50 disabled:cursor-not-allowed"
                      style={{ background: 'linear-gradient(135deg, #6366F1, #8B5CF6)', boxShadow: '0 4px 15px rgba(99,102,241,0.3)' }}>
                {sending ? (
                  <span className="flex items-center justify-center gap-2">
                    <svg className="animate-spin h-4 w-4" fill="none" viewBox="0 0 24 24">
                      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"/>
                      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z"/>
                    </svg>
                    Sending…
                  </span>
                ) : '📢 Send to All Users'}
              </button>
            </form>
          </div>

          {/* Quick templates */}
          <div className="rounded-2xl border border-dark-border p-5" style={{ background: '#0F1420' }}>
            <h2 className="text-sm font-semibold text-white mb-4 flex items-center gap-2">
              <span>⚡</span> Quick Templates
              <span className="ml-auto text-xs text-gray-600 font-normal">Click to auto-fill</span>
            </h2>

            {/* Type tabs */}
            <div className="flex gap-1.5 mb-4 flex-wrap">
              {(['GENERAL', 'PROMO', 'ALERT', 'EVENT'] as NotifType[]).map(t => (
                <button key={t} onClick={() => setTemplateTab(t)}
                        className={`px-3 py-1 rounded-lg text-xs font-semibold border transition-all`}
                        style={templateTab === t
                          ? { background: `${TYPE_COLORS[t]}20`, borderColor: `${TYPE_COLORS[t]}50`, color: TYPE_COLORS[t] }
                          : { background: 'transparent', borderColor: '#1E2940', color: '#4B5563' }}>
                  {t === 'GENERAL' ? '💬' : t === 'PROMO' ? '💰' : t === 'ALERT' ? '⚠️' : '🎉'} {t}
                </button>
              ))}
            </div>

            {/* Templates for active tab */}
            <div className="space-y-2">
              {QUICK_TEMPLATES[templateTab].map(t => (
                <button key={t.label} onClick={() => applyTemplate(t)}
                        className="w-full text-left p-3 rounded-xl border transition-all group"
                        style={{ borderColor: '#1E2940', background: '#080E1A' }}
                        onMouseEnter={e => {
                          (e.currentTarget as HTMLButtonElement).style.borderColor = `${TYPE_COLORS[templateTab]}40`;
                          (e.currentTarget as HTMLButtonElement).style.background  = `${TYPE_COLORS[templateTab]}08`;
                        }}
                        onMouseLeave={e => {
                          (e.currentTarget as HTMLButtonElement).style.borderColor = '#1E2940';
                          (e.currentTarget as HTMLButtonElement).style.background  = '#080E1A';
                        }}>
                  <div className="flex items-center gap-2">
                    <span className="text-xs px-1.5 py-0.5 rounded font-semibold flex-shrink-0"
                          style={{ background: `${TYPE_COLORS[templateTab]}15`, color: TYPE_COLORS[templateTab] }}>
                      {t.label}
                    </span>
                  </div>
                  <p className="text-white text-sm font-medium mt-1.5 leading-snug">{t.title}</p>
                  <p className="text-gray-600 text-xs mt-0.5 line-clamp-2 leading-relaxed">{t.body}</p>
                </button>
              ))}
            </div>
          </div>
        </div>

        {/* History */}
        <div className="rounded-2xl border border-dark-border p-5" style={{ background: '#0F1420' }}>
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-sm font-semibold text-white flex items-center gap-2">
              <span>📜</span> Notification History
            </h2>
            <button onClick={loadHistory} className="text-xs text-gray-500 hover:text-gray-300 transition-colors">↻ Refresh</button>
          </div>

          {histLoading ? (
            <div className="space-y-3">
              {[...Array(4)].map((_, i) => (
                <div key={i} className="h-16 rounded-xl bg-dark-border animate-pulse" />
              ))}
            </div>
          ) : history.length === 0 ? (
            <div className="flex flex-col items-center gap-3 py-12 text-gray-600">
              <span className="text-4xl">🔔</span>
              <p className="text-sm">No notifications sent yet</p>
            </div>
          ) : (
            <div className="space-y-3 max-h-[600px] overflow-y-auto pr-1">
              {history.map(n => (
                <div key={n.id} className="p-3.5 rounded-xl border border-dark-border hover:border-white/10 transition-all">
                  <div className="flex items-start justify-between gap-2">
                    <p className="text-white text-sm font-medium truncate">{n.title}</p>
                    <span className="text-xs text-gray-600 flex-shrink-0 font-mono">{n.sent_to} sent</span>
                  </div>
                  <p className="text-gray-400 text-xs mt-1 line-clamp-2">{n.body}</p>
                  <div className="flex items-center justify-between mt-2">
                    <span className="text-xs px-2 py-0.5 rounded" style={{
                      background: `${TYPE_COLORS[(n.type as NotifType) ?? 'GENERAL']}15`,
                      color: TYPE_COLORS[(n.type as NotifType) ?? 'GENERAL'],
                    }}>
                      {n.type ?? 'GENERAL'}
                    </span>
                    <span className="text-gray-600 text-xs">{formatDateTime(n.created_at)}</span>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
