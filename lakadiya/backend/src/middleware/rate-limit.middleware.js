const rateLimit = require('express-rate-limit');

// ── All limits are configurable via .env — defaults shown in comments ────────
// Add these to your .env to override:
//   RATE_GLOBAL_MAX=500          (requests per 15 min, all /api)
//   RATE_OTP_MAX=5               (OTP sends per 10 min per IP)
//   RATE_AUTH_MAX=15             (login attempts per 15 min per IP)
//   RATE_MESSAGE_MAX=60          (messages per 1 min per user)
//   RATE_PAYMENT_MAX=20          (payment ops per 15 min per user)
//   RATE_UPLOAD_MAX=5            (file uploads per 15 min per user)

const env = (key, fallback) => {
  const v = parseInt(process.env[key], 10);
  return Number.isFinite(v) && v > 0 ? v : fallback;
};

const _json = (msg) => ({ error: msg });

// ── Global fallback — all /api routes ────────────────────────────────────────
const globalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: env('RATE_GLOBAL_MAX', 500),
  standardHeaders: true,
  legacyHeaders: false,
  message: _json('Too many requests. Please try again later.'),
});

// ── OTP send — prevent SMS bombing ───────────────────────────────────────────
const otpSendLimiter = rateLimit({
  windowMs: 10 * 60 * 1000,
  max: env('RATE_OTP_MAX', 5),
  standardHeaders: true,
  legacyHeaders: false,
  message: _json('Too many OTP requests. Please wait 10 minutes before retrying.'),
});

// ── OTP verify / login — brute-force protection ──────────────────────────────
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: env('RATE_AUTH_MAX', 15),
  standardHeaders: true,
  legacyHeaders: false,
  message: _json('Too many authentication attempts. Please wait 15 minutes.'),
});

// ── Message send — per-user anti-spam ────────────────────────────────────────
// Applied after authenticate middleware so req.user.id is available for keying.
const messageLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: env('RATE_MESSAGE_MAX', 60),
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => req.user?.id || req.ip,
  message: _json('You are sending messages too fast. Please slow down.'),
});

// ── Payment endpoints ─────────────────────────────────────────────────────────
const paymentLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: env('RATE_PAYMENT_MAX', 20),
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => req.user?.id || req.ip,
  message: _json('Too many payment requests. Please wait before trying again.'),
});

// ── File upload (avatar) ──────────────────────────────────────────────────────
const uploadLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: env('RATE_UPLOAD_MAX', 5),
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => req.user?.id || req.ip,
  message: _json('Too many file uploads. Please wait 15 minutes.'),
});

module.exports = {
  globalLimiter,
  otpSendLimiter,
  authLimiter,
  messageLimiter,
  paymentLimiter,
  uploadLimiter,
};
