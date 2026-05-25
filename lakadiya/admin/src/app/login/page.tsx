'use client';
import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import Cookies from 'js-cookie';
import { adminLogin } from '../../lib/api';

/* ── Floating playing card config ─────────────────────────────────── */
const FLOATING_CARDS = [
  { suit: '♠', rank: 'A',  top: '8%',  left: '6%',   r: '-15deg', o: 0.18, dur: '7s',  delay: '0s'   },
  { suit: '♥', rank: 'K',  top: '15%', left: '82%',  r: '20deg',  o: 0.15, dur: '9s',  delay: '1s'   },
  { suit: '♦', rank: 'Q',  top: '60%', left: '4%',   r: '-8deg',  o: 0.12, dur: '8s',  delay: '2s'   },
  { suit: '♣', rank: 'J',  top: '70%', left: '88%',  r: '12deg',  o: 0.14, dur: '11s', delay: '0.5s' },
  { suit: '♠', rank: '10', top: '40%', left: '92%',  r: '-22deg', o: 0.10, dur: '6s',  delay: '3s'   },
  { suit: '♥', rank: 'A',  top: '80%', left: '20%',  r: '18deg',  o: 0.13, dur: '10s', delay: '1.5s' },
  { suit: '♦', rank: 'K',  top: '5%',  left: '55%',  r: '-5deg',  o: 0.09, dur: '12s', delay: '4s'   },
  { suit: '♣', rank: 'Q',  top: '50%', left: '50%',  r: '30deg',  o: 0.08, dur: '8.5s',delay: '2.5s' },
  { suit: '♠', rank: '7',  top: '30%', left: '15%',  r: '-28deg', o: 0.11, dur: '9.5s',delay: '0.8s' },
  { suit: '♥', rank: '9',  top: '88%', left: '65%',  r: '8deg',   o: 0.10, dur: '7.5s',delay: '3.5s' },
];

const isRed = (suit: string) => suit === '♥' || suit === '♦';

/* ── Component ────────────────────────────────────────────────────── */
export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail]         = useState('');
  const [password, setPassword]   = useState('');
  const [showPass, setShowPass]   = useState(false);
  const [error, setError]         = useState('');
  const [loading, setLoading]     = useState(false);
  const [mounted, setMounted]     = useState(false);

  useEffect(() => { setMounted(true); }, []);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      const { token } = await adminLogin(email, password);
      Cookies.set('admin_token', token, { expires: 7 });
      router.push('/dashboard');
    } catch {
      setError('Invalid email or password');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="relative min-h-screen overflow-hidden flex items-center justify-center"
         style={{ background: 'radial-gradient(ellipse at 20% 50%, #0d2618 0%, #0D1117 50%, #0a0d16 100%)' }}>

      {/* ── Animated mesh background ── */}
      <div className="absolute inset-0 overflow-hidden pointer-events-none">
        <div className="absolute w-[600px] h-[600px] rounded-full opacity-10"
             style={{
               background: 'radial-gradient(circle, #238636 0%, transparent 70%)',
               top: '-200px', left: '-200px',
               animation: 'drift 20s ease-in-out infinite',
               '--r': '0deg',
             } as React.CSSProperties} />
        <div className="absolute w-[500px] h-[500px] rounded-full opacity-8"
             style={{
               background: 'radial-gradient(circle, #1F6FEB 0%, transparent 70%)',
               bottom: '-150px', right: '-150px',
               animation: 'drift 25s ease-in-out infinite reverse',
               '--r': '0deg',
             } as React.CSSProperties} />
        <div className="absolute w-[400px] h-[400px] rounded-full opacity-6"
             style={{
               background: 'radial-gradient(circle, #E3B341 0%, transparent 70%)',
               top: '40%', left: '40%',
               animation: 'drift 30s ease-in-out infinite',
               '--r': '0deg',
             } as React.CSSProperties} />

        {/* Grid overlay */}
        <div className="absolute inset-0 opacity-5"
             style={{
               backgroundImage: `linear-gradient(rgba(255,255,255,0.1) 1px, transparent 1px),
                                  linear-gradient(90deg, rgba(255,255,255,0.1) 1px, transparent 1px)`,
               backgroundSize: '60px 60px',
             }} />
      </div>

      {/* ── Floating playing cards ── */}
      {mounted && FLOATING_CARDS.map((c, i) => (
        <div key={i}
             className="absolute pointer-events-none select-none"
             style={{
               top: c.top, left: c.left,
               '--r': c.r, '--o': c.o,
               animation: `floatCard ${c.dur} ease-in-out ${c.delay} infinite`,
             } as React.CSSProperties}>
          <div className="rounded-lg flex flex-col items-center justify-between p-1.5 select-none"
               style={{
                 width: 44, height: 62,
                 background: 'rgba(255,255,255,0.04)',
                 border: '1px solid rgba(255,255,255,0.08)',
                 backdropFilter: 'blur(4px)',
                 color: isRed(c.suit) ? '#ff6b81' : 'rgba(255,255,255,0.7)',
                 fontSize: 11, fontWeight: 700,
               }}>
            <span style={{ alignSelf: 'flex-start', lineHeight: 1 }}>{c.rank}</span>
            <span style={{ fontSize: 20 }}>{c.suit}</span>
            <span style={{ alignSelf: 'flex-end', lineHeight: 1, transform: 'rotate(180deg)' }}>{c.rank}</span>
          </div>
        </div>
      ))}

      {/* ── Login card ── */}
      <div className={`relative z-10 w-full max-w-md px-4 ${mounted ? 'animate-fade-in-scale' : 'opacity-0'}`}>

        {/* Glow ring behind card */}
        <div className="absolute inset-0 rounded-2xl opacity-30 blur-xl"
             style={{ background: 'linear-gradient(135deg, #238636, #1F6FEB)', transform: 'scale(0.95)' }} />

        <div className="relative glass rounded-2xl overflow-hidden shadow-2xl">

          {/* Top gradient stripe */}
          <div className="h-1 w-full"
               style={{ background: 'linear-gradient(90deg, #238636, #E3B341, #1F6FEB, #DA3633)', backgroundSize: '300% 100%', animation: 'gradientShift 4s ease infinite' }} />

          <div className="p-8">
            {/* Logo */}
            <div className="text-center mb-8">
              <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl mb-4 relative"
                   style={{ background: 'linear-gradient(135deg, #238636, #1a5c28)', animation: 'pulse-ring 2.5s infinite' }}>
                <span className="text-3xl">♠</span>
                <div className="absolute -top-1 -right-1 w-5 h-5 rounded-full bg-accent flex items-center justify-center"
                     style={{ fontSize: 10, fontWeight: 900 }}>A</div>
              </div>
              <h1 className="text-2xl font-bold text-white">Lakadiya Admin</h1>
              <p className="text-gray-400 text-sm mt-1">Sign in to manage the game</p>

              {/* Suit row */}
              <div className="flex justify-center gap-3 mt-3">
                {['♠','♥','♦','♣'].map((s, i) => (
                  <span key={s}
                        className="text-lg opacity-60"
                        style={{
                          color: s === '♥' || s === '♦' ? '#ff6b81' : '#8b949e',
                          animation: `bounceIn 0.5s ease ${0.1 * i}s both`,
                        }}>
                    {s}
                  </span>
                ))}
              </div>
            </div>

            {/* Error */}
            {error && (
              <div className="mb-4 px-4 py-3 rounded-xl text-sm font-medium animate-fade-in-up"
                   style={{ background: 'rgba(218,54,51,0.12)', border: '1px solid rgba(218,54,51,0.3)', color: '#ff6b6b' }}>
                ⚠ {error}
              </div>
            )}

            {/* Form */}
            <form onSubmit={handleSubmit} className="space-y-5">
              {/* Email */}
              <div className="animate-fade-in-up delay-100">
                <label className="block text-xs font-semibold text-gray-400 mb-1.5 uppercase tracking-wider">
                  Email Address
                </label>
                <div className="relative">
                  <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500 text-sm">✉</span>
                  <input
                    type="email" required autoComplete="email"
                    className="w-full pl-9 pr-3 py-3 rounded-xl text-sm text-white transition-all duration-200"
                    style={{
                      background: 'rgba(13,17,23,0.8)',
                      border: '1px solid rgba(48,54,61,0.8)',
                      outline: 'none',
                    }}
                    placeholder="admin@lakadiya.com"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    onFocus={(e) => { e.target.style.borderColor = '#238636'; e.target.style.boxShadow = '0 0 0 3px rgba(35,134,54,0.15)'; }}
                    onBlur={(e)  => { e.target.style.borderColor = 'rgba(48,54,61,0.8)'; e.target.style.boxShadow = 'none'; }}
                  />
                </div>
              </div>

              {/* Password */}
              <div className="animate-fade-in-up delay-200">
                <label className="block text-xs font-semibold text-gray-400 mb-1.5 uppercase tracking-wider">
                  Password
                </label>
                <div className="relative">
                  <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500 text-sm">🔒</span>
                  <input
                    type={showPass ? 'text' : 'password'} required autoComplete="current-password"
                    className="w-full pl-9 pr-10 py-3 rounded-xl text-sm text-white transition-all duration-200"
                    style={{
                      background: 'rgba(13,17,23,0.8)',
                      border: '1px solid rgba(48,54,61,0.8)',
                      outline: 'none',
                    }}
                    placeholder="••••••••"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    onFocus={(e) => { e.target.style.borderColor = '#238636'; e.target.style.boxShadow = '0 0 0 3px rgba(35,134,54,0.15)'; }}
                    onBlur={(e)  => { e.target.style.borderColor = 'rgba(48,54,61,0.8)'; e.target.style.boxShadow = 'none'; }}
                  />
                  <button type="button"
                          className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-500 hover:text-gray-300 text-sm transition-colors"
                          onClick={() => setShowPass((v) => !v)}>
                    {showPass ? '🙈' : '👁'}
                  </button>
                </div>
              </div>

              {/* Submit */}
              <div className="animate-fade-in-up delay-300 pt-2">
                <button
                  type="submit" disabled={loading}
                  className="w-full py-3.5 rounded-xl font-bold text-white text-sm relative overflow-hidden
                             transition-all duration-200 disabled:opacity-60 disabled:cursor-not-allowed
                             hover:shadow-lg hover:-translate-y-0.5 active:translate-y-0"
                  style={{
                    background: loading
                      ? '#238636'
                      : 'linear-gradient(135deg, #238636 0%, #2ea043 100%)',
                    boxShadow: '0 4px 15px rgba(35,134,54,0.3)',
                  }}>
                  {/* Shimmer on hover */}
                  <span className="absolute inset-0 opacity-0 hover:opacity-20 transition-opacity"
                        style={{ background: 'linear-gradient(45deg, transparent 30%, rgba(255,255,255,0.5) 50%, transparent 70%)', backgroundSize: '200% 100%' }} />

                  {loading ? (
                    <span className="flex items-center justify-center gap-2">
                      <svg className="animate-spin h-4 w-4" fill="none" viewBox="0 0 24 24">
                        <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"/>
                        <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z"/>
                      </svg>
                      Signing in…
                    </span>
                  ) : (
                    <span className="flex items-center justify-center gap-2">
                      ♠ Sign In
                    </span>
                  )}
                </button>
              </div>
            </form>

            {/* Footer hint */}
            <p className="text-center text-xs text-gray-600 mt-6 animate-fade-in-up delay-400">
              Lakadiya Game Platform · Admin Panel
            </p>
          </div>
        </div>

        {/* Floating card suit decorations below form */}
        <div className="flex justify-center gap-6 mt-6 animate-fade-in-up delay-500">
          {[
            { s: '♠', label: 'Spades',   color: '#8b949e' },
            { s: '♥', label: 'Hearts',   color: '#ff6b81' },
            { s: '♦', label: 'Diamonds', color: '#ff6b81' },
            { s: '♣', label: 'Clubs',    color: '#8b949e' },
          ].map(({ s, label, color }) => (
            <div key={s} className="flex flex-col items-center gap-1 opacity-40 hover:opacity-70 transition-opacity cursor-default">
              <span style={{ color, fontSize: 20 }}>{s}</span>
              <span className="text-gray-600 text-xs">{label}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
