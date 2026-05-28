require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');

const authRoutes = require('./modules/auth/auth.routes');
const userRoutes = require('./modules/users/user.routes');
const roomRoutes = require('./modules/rooms/room.routes');
const leaderboardRoutes = require('./modules/leaderboard/leaderboard.routes');
const paymentRoutes = require('./modules/payments/payment.routes');
const notificationRoutes = require('./modules/notifications/notification.routes');
const adminRoutes = require('./modules/admin/admin.routes');
const { getSettings } = require('./modules/admin/settings.service');
const { errorHandler, notFound } = require('./middleware/error.middleware');

const app = express();

app.use(helmet());
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') || '*',
  credentials: true,
}));
app.use(express.json({ limit: '10kb' }));
app.use(express.urlencoded({ extended: true }));

const limiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 200 });
app.use('/api', limiter);

app.get('/health', (req, res) => res.json({ status: 'ok', uptime: process.uptime() }));

app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/rooms', roomRoutes);
app.use('/api/leaderboard', leaderboardRoutes);
app.use('/api/payments', paymentRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/admin', adminRoutes);

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
      platform_fee_pct:     Number(s.platform_fee_pct),
    });
  } catch (e) { next(e); }
});

app.use(notFound);
app.use(errorHandler);

module.exports = app;
