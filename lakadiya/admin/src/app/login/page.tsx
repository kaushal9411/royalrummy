'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import Cookies from 'js-cookie';
import { adminLogin } from '../../lib/api';

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail]       = useState('');
  const [password, setPassword] = useState('');
  const [error, setError]       = useState('');
  const [loading, setLoading]   = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      const { token } = await adminLogin(email, password);
      Cookies.set('admin_token', token, { expires: 7 });
      router.push('/dashboard');
    } catch {
      setError('Invalid credentials');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-dark-bg">
      <div className="w-full max-w-sm">
        <div className="text-center mb-8">
          <h1 className="text-3xl font-bold text-white">♠ Lakadiya</h1>
          <p className="text-gray-400 mt-1">Admin Panel</p>
        </div>

        <form onSubmit={handleSubmit} className="card space-y-4">
          {error && (
            <div className="bg-danger/10 border border-danger/40 text-danger rounded-lg px-3 py-2 text-sm">
              {error}
            </div>
          )}

          <div>
            <label className="block text-sm text-gray-400 mb-1">Email</label>
            <input
              type="email" required
              className="input w-full"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="admin@lakadiya.com"
            />
          </div>

          <div>
            <label className="block text-sm text-gray-400 mb-1">Password</label>
            <input
              type="password" required
              className="input w-full"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="••••••••"
            />
          </div>

          <button type="submit" disabled={loading} className="btn-primary w-full">
            {loading ? 'Signing in…' : 'Sign In'}
          </button>
        </form>
      </div>
    </div>
  );
}
