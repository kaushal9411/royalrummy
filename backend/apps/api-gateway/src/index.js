require('dotenv').config({ path: '../../../.env' });
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const morgan = require('morgan');
const { createProxyMiddleware } = require('http-proxy-middleware');
const rateLimit = require('express-rate-limit');
const { authenticateJWT } = require('../../../libs/middleware/auth.middleware');
const { errorHandler } = require('../../../libs/middleware/error.middleware');
const { requestLogger } = require('../../../libs/middleware/logger.middleware');
const logger = require('../../../libs/utils/logger');

const app = express();
const PORT = process.env.API_GATEWAY_PORT || 3000;

// Security middleware
app.use(helmet());
app.use(compression());
app.use(morgan('combined'));
app.use(requestLogger);

// CORS
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') || ['http://localhost:3001'],
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Device-ID', 'X-App-Version'],
}));

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// Global rate limiter
const globalLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 100,
  keyGenerator: (req) => req.headers['x-device-id'] || req.ip,
  message: { success: false, error: { code: 'GENERAL_001', message: 'Rate limit exceeded' } },
  standardHeaders: true,
  legacyHeaders: false,
});
app.use(globalLimiter);

// Auth rate limiter (stricter)
const authLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 10,
  keyGenerator: (req) => req.ip,
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'api-gateway', timestamp: new Date().toISOString() });
});

// Service routes proxied to microservices
const SERVICE_URLS = {
  auth:          process.env.AUTH_SERVICE_URL          || 'http://localhost:3001',
  game:          process.env.GAME_SERVICE_URL          || 'http://localhost:3002',
  wallet:        process.env.WALLET_SERVICE_URL        || 'http://localhost:3003',
  matchmaking:   process.env.MATCHMAKING_SERVICE_URL   || 'http://localhost:3004',
  tournament:    process.env.TOURNAMENT_SERVICE_URL    || 'http://localhost:3005',
  notification:  process.env.NOTIFICATION_SERVICE_URL || 'http://localhost:3006',
  social:        process.env.SOCIAL_SERVICE_URL        || 'http://localhost:3007',
  leaderboard:   process.env.LEADERBOARD_SERVICE_URL  || 'http://localhost:3008',
};

const proxyOptions = (target) => ({
  target,
  changeOrigin: true,
  logLevel: 'warn',
  on: {
    error: (err, req, res) => {
      logger.error(`Proxy error to ${target}: ${err.message}`);
      res.status(503).json({
        success: false,
        error: { code: 'GENERAL_004', message: 'Service temporarily unavailable' },
      });
    },
  },
});

// Public routes (no auth required)
app.use('/v1/auth', authLimiter, createProxyMiddleware(proxyOptions(SERVICE_URLS.auth)));

// Protected routes (JWT required)
app.use('/v1/games',        authenticateJWT, createProxyMiddleware(proxyOptions(SERVICE_URLS.game)));
app.use('/v1/wallet',       authenticateJWT, createProxyMiddleware(proxyOptions(SERVICE_URLS.wallet)));
app.use('/v1/matchmaking',  authenticateJWT, createProxyMiddleware(proxyOptions(SERVICE_URLS.matchmaking)));
app.use('/v1/tournaments',  authenticateJWT, createProxyMiddleware(proxyOptions(SERVICE_URLS.tournament)));
app.use('/v1/social',       authenticateJWT, createProxyMiddleware(proxyOptions(SERVICE_URLS.social)));
app.use('/v1/leaderboard',  authenticateJWT, createProxyMiddleware(proxyOptions(SERVICE_URLS.leaderboard)));
app.use('/v1/notifications',authenticateJWT, createProxyMiddleware(proxyOptions(SERVICE_URLS.notification)));

// 404
app.use((req, res) => {
  res.status(404).json({
    success: false,
    error: { code: 'GENERAL_003', message: 'Route not found' },
  });
});

// Global error handler
app.use(errorHandler);

app.listen(PORT, () => {
  logger.info(`API Gateway running on port ${PORT}`);
});

module.exports = app;
