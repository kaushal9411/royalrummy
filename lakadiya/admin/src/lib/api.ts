import axios from 'axios';
import Cookies from 'js-cookie';

const BASE_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:3001/api';

export const api = axios.create({
  baseURL: BASE_URL,
  timeout: 10000,
});

api.interceptors.request.use((config) => {
  const token = Cookies.get('admin_token');
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

api.interceptors.response.use(
  (res) => res,
  (err) => {
    if (err.response?.status === 401) {
      Cookies.remove('admin_token');
      window.location.href = '/login';
    }
    return Promise.reject(err);
  }
);

export const adminLogin = async (email: string, password: string) => {
  const res = await api.post('/auth/admin/login', { email, password });
  return res.data as { token: string };
};

export const getDashboard = async () => {
  const res = await api.get('/admin/dashboard');
  return res.data as {
    totalUsers: number; activeGames: number;
    todayMatches: number; totalMatches: number;
  };
};

export const getUsers = async (params?: {
  page?: number; limit?: number; search?: string; banned?: boolean;
}) => {
  const res = await api.get('/admin/users', { params });
  return res.data as { users: AdminUser[]; total: number };
};

export const banUser   = (userId: string, reason: string) =>
  api.post(`/admin/users/${userId}/ban`, { reason });

export const unbanUser = (userId: string) =>
  api.post(`/admin/users/${userId}/unban`);

export const getMatches = async (params?: {
  page?: number; limit?: number; status?: string;
}) => {
  const res = await api.get('/admin/matches', { params });
  return res.data as { matches: AdminMatch[]; total: number };
};

export const getAnalytics = async () => {
  const res = await api.get('/admin/analytics');
  return res.data as Analytics;
};

// ─── Types ────────────────────────────────────────────────────────────────────

export interface AdminUser {
  id: string; username: string; email: string; provider: string;
  coins: number; xp: number; level: number;
  is_banned: boolean; created_at: string; last_seen: string;
  matches_played: number; matches_won: number;
}

export interface AdminMatch {
  id: string; status: string; created_at: string; finished_at: string | null;
  room_code: string; winner_name: string | null; player_count: number;
}

export interface Analytics {
  matchesByDay:       { date: string; matches: number }[];
  registrationsByDay: { date: string; users: number }[];
  topPlayers:         { username: string; matches_won: number; total_score: number }[];
}
