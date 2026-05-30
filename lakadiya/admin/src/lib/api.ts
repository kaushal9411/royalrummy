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
  id: string; username: string; email: string | null; mobile: string | null; provider: string;
  coins: number; xp: number; level: number;
  is_banned: boolean; created_at: string; last_seen: string;
  matches_played: number; matches_won: number;
  // Compliance fields
  date_of_birth: string | null;
  age: number | null;
  kyc_verified: boolean;
  kyc_status: 'not_submitted' | 'pending' | 'approved' | 'rejected';
  is_minor: boolean | null;
}

export interface UserKyc {
  id: string; status: string; pan_number: string | null; full_name: string | null;
  admin_remark: string | null; submitted_at: string; reviewed_at: string | null;
}

export interface UserResponsibleGaming {
  daily_limit: number | null; weekly_limit: number | null; monthly_limit: number | null;
  self_excluded: boolean; exclusion_until: string | null;
}

export interface UserNotifPrefs {
  game:   boolean;
  wallet: boolean;
  promo:  boolean;
}

export interface AdminUserDetail extends AdminUser {
  ban_reason: string | null; total_score: number; bids_exact: number; bids_failed: number;
  kyc: UserKyc | null;
  responsible_gaming: UserResponsibleGaming | null;
  notification_prefs: UserNotifPrefs;
}

export interface KycSubmission {
  id: string; user_id: string; username: string; mobile: string | null;
  status: string; pan_number: string | null; full_name: string | null;
  pan_doc_path: string | null; selfie_path: string | null;
  admin_remark: string | null; submitted_at: string; reviewed_at: string | null;
}

export const liftSelfExclusion = async (userId: string): Promise<void> => {
  await api.post(`/admin/users/${userId}/lift-exclusion`);
};

export const getUserDetail = async (userId: string): Promise<AdminUserDetail> => {
  const res = await api.get(`/admin/users/${userId}/detail`);
  return res.data;
};

export const getPendingKyc = async (): Promise<KycSubmission[]> => {
  const res = await api.get('/admin/kyc/pending');
  return res.data;
};

export const approveKyc = async (kycId: string): Promise<void> => {
  await api.post(`/admin/kyc/${kycId}/approve`);
};

export const rejectKyc = async (kycId: string, remark: string): Promise<void> => {
  await api.post(`/admin/kyc/${kycId}/reject`, { remark });
};

/** Returns a URL that serves the KYC document inline — includes admin token as query param */
export const kycDocUrl = (kycId: string, docType: 'pan_doc' | 'selfie'): string => {
  const token  = Cookies.get('admin_token') ?? '';
  const apiUrl = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:3001/api';
  return `${apiUrl}/admin/kyc/${kycId}/document/${docType}?token=${encodeURIComponent(token)}`;
};

export interface AdminMatch {
  id: string; status: string; created_at: string; finished_at: string | null;
  room_code: string; winner_name: string | null; player_count: number;
}

export interface Analytics {
  matchesByDay:       { date: string; matches: number }[];
  registrationsByDay: { date: string; users: number }[];
  topPlayers:         { username: string; matches_won: number; total_score: number }[];
  feesByDay:          { date: string; gateway_fee: number; platform_fee: number }[];
}

// ─── Extended dashboard ───────────────────────────────────────────────────────

export interface DashboardStats {
  totalUsers:     number;
  activeGames:    number;
  todayMatches:   number;
  totalMatches:   number;
  todayRevenue:   number;
  totalRevenue:   number;
  pendingWithdrawals: number;
  onlineUsers:    number;
}

export const getDashboardStats = async (): Promise<DashboardStats> => {
  const res = await api.get('/admin/dashboard');
  return res.data;
};

// ─── Room types & calls ───────────────────────────────────────────────────────

export interface AdminRoom {
  id:           string;
  code:         string;
  status:       string;
  is_private:   boolean;
  bet_amount:   number;
  host_id:      string;
  host_name:    string;
  player_count: number;
  created_at:   string;
  started_at:   string | null;
  finished_at:  string | null;
}

export const getAdminRooms = async (params?: {
  status?: string; limit?: number; offset?: number;
}): Promise<{ rooms: AdminRoom[]; total: number }> => {
  const res = await api.get('/admin/rooms', { params });
  return res.data;
};

export const closeAdminRoom = async (roomId: string): Promise<void> => {
  await api.patch(`/admin/rooms/${roomId}/close`);
};

// ─── Notification types & calls ───────────────────────────────────────────────

export interface NotificationLog {
  id:         string;
  type:       string;
  title:      string;
  body:       string;
  sent_to:    number;
  created_at: string;
}

export const sendBroadcastNotification = async (payload: {
  title: string;
  body:  string;
  type?: string;
  data?: Record<string, string>;
}): Promise<{ sent: number }> => {
  const res = await api.post('/admin/notifications/broadcast', payload);
  return res.data;
};

export const getNotificationHistory = async (): Promise<NotificationLog[]> => {
  const res = await api.get('/admin/notifications/history');
  return res.data;
};

// ─── Settings types & calls ───────────────────────────────────────────────────

export interface AdminSettings {
  maintenance_mode:          boolean;
  registration_enabled:      boolean;
  min_withdrawal:            number;
  max_withdrawal:            number;
  welcome_bonus:             number;
  max_bet_amount:            number;
  platform_fee_pct:          number;
  payment_gateway_fee_pct:   number;
}

export const getAdminSettings = async (): Promise<AdminSettings> => {
  const res = await api.get('/admin/settings');
  return res.data;
};

export const updateAdminSettings = async (data: Partial<AdminSettings>): Promise<AdminSettings> => {
  const res = await api.patch('/admin/settings', data);
  return res.data;
};

// ─── Payment types & calls ────────────────────────────────────────────────────

export interface PaymentStats {
  total_revenue:             number;
  total_withdrawn:           number;
  pending_amount:            number;
  pending_count:             number;
  total_add_count:           number;
  today_revenue:             number;
  total_bet_payouts:         number;
  total_bet_escrowed:        number;
  total_bet_games:           number;
  today_bet_volume:          number;
  total_gateway_fee_earned:  number;
  today_gateway_fee_earned:  number;
  total_platform_fee_earned: number;
  today_platform_fee_earned: number;
}

export interface GameBet {
  id: string;
  room_id: string;
  match_id: string | null;
  seat: number;
  amount: number;
  status: string;   // escrowed | won | lost | refunded
  created_at: string;
  settled_at: string | null;
  username: string;
  email: string;
  room_code: string;
  room_bet_amount: number;
}

export interface TxMetadata {
  baseAmount?:    number;
  gatewayFee?:    number;
  gatewayFeePct?: number;
  platformFee?:   number;
  platformFeePct?: number;
  netAmount?:     number;
}

export interface AdminTransaction {
  id: string; user_id: string; username: string; email: string;
  amount: number; coins: number; type: string; status: string;
  created_at: string; updated_at: string;
  metadata?: TxMetadata | null;
  razorpay_payment_id?: string | null;
}

export const getPaymentStats = async (): Promise<PaymentStats> => {
  const res = await api.get('/payments/admin/stats');
  return res.data;
};

export const getAdminTransactions = async (params?: {
  userId?: string; limit?: number; offset?: number;
}): Promise<AdminTransaction[]> => {
  const res = await api.get('/payments/admin/transactions', { params });
  return res.data;
};

export const getAdminWithdrawals = async (params?: {
  status?: string; limit?: number; offset?: number;
}): Promise<AdminTransaction[]> => {
  const res = await api.get('/payments/admin/withdrawals', { params });
  return res.data;
};

export const getAdminGameBets = async (params?: {
  status?: string; limit?: number; offset?: number;
}): Promise<GameBet[]> => {
  const res = await api.get('/payments/admin/bets', { params });
  return res.data;
};

export const approveWithdrawal = async (id: string) => {
  const res = await api.patch(`/payments/admin/withdrawals/${id}/approve`);
  return res.data;
};

export const rejectWithdrawal = async (id: string, reason: string) => {
  const res = await api.patch(`/payments/admin/withdrawals/${id}/reject`, { reason });
  return res.data;
};

// ─── Credentials ──────────────────────────────────────────────────────────────

export interface AdminCredential {
  key_name:     string;
  masked_value: string;  // e.g. "rzp_••••••••live" — never returns plaintext
  updated_at:   string;
}

export const listCredentials = async (): Promise<AdminCredential[]> => {
  const res = await api.get('/admin/credentials');
  return res.data;
};

export const saveCredential = async (key_name: string, value: string): Promise<void> => {
  await api.post('/admin/credentials', { key_name, value });
};

export const deleteCredential = async (key_name: string): Promise<void> => {
  await api.delete(`/admin/credentials/${encodeURIComponent(key_name)}`);
};
