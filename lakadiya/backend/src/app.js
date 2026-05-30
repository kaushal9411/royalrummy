require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const path = require('path');
const rateLimit = require('express-rate-limit');

const authRoutes = require('./modules/auth/auth.routes');
const userRoutes = require('./modules/users/user.routes');
const roomRoutes = require('./modules/rooms/room.routes');
const leaderboardRoutes = require('./modules/leaderboard/leaderboard.routes');
const paymentRoutes = require('./modules/payments/payment.routes');
const notificationRoutes = require('./modules/notifications/notification.routes');
const adminRoutes = require('./modules/admin/admin.routes');
const messageRoutes = require('./modules/messages/message.routes');
const credentialsRoutes = require('./modules/credentials/credentials.routes');
const kycRoutes = require('./modules/kyc/kyc.routes');
const responsibleGamingRoutes = require('./modules/responsible_gaming/responsible_gaming.routes');
const { getSettings } = require('./modules/admin/settings.service');
const { autoSeedFromEnv } = require('./modules/credentials/credentials.service');
const { errorHandler, notFound } = require('./middleware/error.middleware');

const app = express();

app.use(helmet({ contentSecurityPolicy: false })); // CSP disabled for served HTML legal pages
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') || '*',
  credentials: true,
}));
app.use(express.json({ limit: '10kb' }));
app.use(express.urlencoded({ extended: true }));

const limiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 200 });
app.use('/api', limiter);

// Seed Razorpay credentials from env into encrypted DB on first boot
autoSeedFromEnv('razorpay_key_id',     process.env.RAZORPAY_KEY_ID).catch(() => {});
autoSeedFromEnv('razorpay_key_secret', process.env.RAZORPAY_KEY_SECRET).catch(() => {});

app.get('/health', (req, res) => res.json({ status: 'ok', uptime: process.uptime() }));

app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/rooms', roomRoutes);
app.use('/api/leaderboard', leaderboardRoutes);
app.use('/api/payments', paymentRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/messages', messageRoutes);
app.use('/api/credentials', credentialsRoutes);
app.use('/api/kyc', kycRoutes);
app.use('/api/responsible-gaming', responsibleGamingRoutes);

// Serve uploaded KYC documents (admin access only — protect in production with auth middleware)
app.use('/uploads', express.static(path.join(__dirname, '../../uploads')));

// Legal pages — public, served as HTML
app.get('/privacy-policy', (req, res) => {
  res.sendFile(path.join(__dirname, 'modules/legal/privacy_policy.html'));
});
app.get('/terms', (req, res) => {
  res.sendFile(path.join(__dirname, 'modules/legal/terms_of_service.html'));
});

// Public settings — no auth required, mobile app fetches on startup
app.get('/api/settings/public', async (req, res, next) => {
  try {
    const s = await getSettings();
    res.json({
      maintenance_mode:     s.maintenance_mode,
      registration_enabled: s.registration_enabled,
      min_withdrawal:       Number(s.min_withdrawal),
      max_withdrawal:       Number(s.max_withdrawal),
      welcome_bonus:        Number(s.welcome_bonus),
      max_bet_amount:       Number(s.max_bet_amount),
      platform_fee_pct:          Number(s.platform_fee_pct),
      payment_gateway_fee_pct:   Number(s.payment_gateway_fee_pct ?? 2),
    });
  } catch (e) { next(e); }
});

app.use(notFound);
app.use(errorHandler);

module.exports = app;
