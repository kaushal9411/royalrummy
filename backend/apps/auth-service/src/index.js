require('dotenv').config({ path: '../../../.env' });
const express = require('express');
const rateLimit = require('express-rate-limit');
const { body, validationResult } = require('express-validator');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const db = require('../../../libs/database/db');
const redis = require('../../../libs/cache/redis');
const logger = require('../../../libs/utils/logger');
const { generateReferralCode, generateOtp } = require('../../../libs/utils/helpers');
const { sendOtp } = require('../../../libs/services/sms.service');
const { sendResponse, sendError } = require('../../../libs/utils/response');

const app = express();
app.use(express.json());

const PORT = process.env.AUTH_SERVICE_PORT || 3001;

// OTP rate limiter
const otpLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 3,
  keyGenerator: (req) => req.body.phone || req.ip,
});

// Health
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'auth-service' });
});

// POST /v1/auth/otp/send
app.post('/v1/auth/otp/send',
  otpLimiter,
  [body('phone').matches(/^\+91[6-9]\d{9}$/).withMessage('Invalid Indian phone number')],
  async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return sendError(res, 400, 'AUTH_VALIDATION', 'Invalid input', errors.array());
    }

    const { phone } = req.body;
    const otp = generateOtp();
    const otpKey = `otp:${phone}`;

    // Store OTP in Redis for 5 minutes
    await redis.setex(otpKey, 300, otp);

    // Send OTP via SMS
    await sendOtp(phone, otp);

    logger.info(`OTP sent to ${phone}`);
    sendResponse(res, 200, { message: 'OTP sent successfully', expires_in: 300 });
  }
);

// POST /v1/auth/otp/verify
app.post('/v1/auth/otp/verify',
  [
    body('phone').matches(/^\+91[6-9]\d{9}$/),
    body('otp').isLength({ min: 6, max: 6 }).isNumeric(),
  ],
  async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return sendError(res, 400, 'AUTH_VALIDATION', 'Invalid input');
    }

    const { phone, otp } = req.body;
    const storedOtp = await redis.get(`otp:${phone}`);

    if (!storedOtp || storedOtp !== otp) {
      return sendError(res, 400, 'AUTH_003', 'Invalid or expired OTP');
    }

    await redis.del(`otp:${phone}`);

    // Check if user exists
    const user = await db.query('SELECT id FROM users WHERE phone = $1', [phone]);

    if (user.rows.length === 0) {
      // New user — mark phone as verified, needs registration
      await redis.setex(`phone:verified:${phone}`, 600, '1');
      return sendResponse(res, 200, { verified: true, needs_registration: true });
    }

    // Existing user — issue tokens
    const tokens = await issueTokens(user.rows[0].id, req.body.device_id);
    sendResponse(res, 200, { verified: true, needs_registration: false, ...tokens });
  }
);

// POST /v1/auth/register
app.post('/v1/auth/register',
  [
    body('phone').matches(/^\+91[6-9]\d{9}$/),
    body('username').isLength({ min: 3, max: 50 }).matches(/^[a-zA-Z0-9_]+$/),
    body('email').optional().isEmail(),
  ],
  async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return sendError(res, 400, 'AUTH_VALIDATION', 'Invalid input', errors.array());
    }

    const { phone, username, email, referral_code, device_id, fcm_token } = req.body;

    // Verify phone was OTP-verified
    const phoneVerified = await redis.get(`phone:verified:${phone}`);
    if (!phoneVerified) {
      return sendError(res, 400, 'AUTH_002', 'Phone not verified. Please verify OTP first.');
    }

    // Check username uniqueness
    const usernameCheck = await db.query('SELECT id FROM users WHERE username = $1', [username]);
    if (usernameCheck.rows.length > 0) {
      return sendError(res, 409, 'AUTH_USERNAME_TAKEN', 'Username already taken');
    }

    const client = await db.connect();
    try {
      await client.query('BEGIN');

      const userId = uuidv4();
      const newReferralCode = generateReferralCode(username);

      // Find referrer
      let referrerId = null;
      if (referral_code) {
        const referrer = await client.query(
          'SELECT id FROM users WHERE referral_code = $1',
          [referral_code]
        );
        if (referrer.rows.length > 0) referrerId = referrer.rows[0].id;
      }

      // Create user
      await client.query(`
        INSERT INTO users (id, phone, email, username, referral_code, referred_by, status)
        VALUES ($1, $2, $3, $4, $5, $6, 'active')
      `, [userId, phone, email || null, username, newReferralCode, referrerId]);

      // Create profile
      await client.query(`
        INSERT INTO user_profiles (id, user_id)
        VALUES ($1, $2)
      `, [uuidv4(), userId]);

      // Create wallet with signup bonus
      await client.query(`
        INSERT INTO wallets (id, user_id, balance_bonus)
        VALUES ($1, $2, $3)
      `, [uuidv4(), userId, process.env.SIGNUP_BONUS || 50]);

      // Record signup bonus transaction
      await client.query(`
        INSERT INTO transactions (id, user_id, type, amount, currency_type, balance_before, balance_after)
        VALUES ($1, $2, 'bonus', $3, 'bonus', 0, $3)
      `, [uuidv4(), userId, process.env.SIGNUP_BONUS || 50]);

      // Register device
      if (device_id) {
        await client.query(`
          INSERT INTO user_devices (id, user_id, device_id, fcm_token, is_trusted)
          VALUES ($1, $2, $3, $4, true)
          ON CONFLICT (user_id, device_id) DO UPDATE SET fcm_token = $4
        `, [uuidv4(), userId, device_id, fcm_token]);
      }

      // Create referral record
      if (referrerId) {
        await client.query(`
          INSERT INTO referrals (id, referrer_id, referee_id, code_used, status)
          VALUES ($1, $2, $3, $4, 'pending')
        `, [uuidv4(), referrerId, userId, referral_code]);
      }

      await client.query('COMMIT');
      await redis.del(`phone:verified:${phone}`);

      const tokens = await issueTokens(userId, device_id);
      logger.info(`New user registered: ${userId} (${username})`);

      sendResponse(res, 201, {
        user: { id: userId, username, referral_code: newReferralCode },
        ...tokens,
      });
    } catch (err) {
      await client.query('ROLLBACK');
      logger.error(`Registration error: ${err.message}`);
      sendError(res, 500, 'GENERAL_003', 'Registration failed');
    } finally {
      client.release();
    }
  }
);

// POST /v1/auth/refresh
app.post('/v1/auth/refresh', async (req, res) => {
  const { refresh_token } = req.body;
  if (!refresh_token) return sendError(res, 400, 'AUTH_005', 'Refresh token required');

  try {
    const payload = jwt.verify(refresh_token, process.env.JWT_REFRESH_SECRET);

    // Check token exists and not revoked
    const tokenHash = require('crypto')
      .createHash('sha256').update(refresh_token).digest('hex');

    const stored = await db.query(
      'SELECT id, user_id FROM refresh_tokens WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > NOW()',
      [tokenHash]
    );

    if (stored.rows.length === 0) {
      // Possible token reuse — revoke all user tokens
      if (payload.sub) {
        await db.query('UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = $1', [payload.sub]);
      }
      return sendError(res, 401, 'AUTH_006', 'Invalid refresh token');
    }

    // Revoke old token, issue new pair
    await db.query('UPDATE refresh_tokens SET revoked_at = NOW() WHERE id = $1', [stored.rows[0].id]);

    const tokens = await issueTokens(payload.sub, payload.device_id);
    sendResponse(res, 200, tokens);
  } catch (err) {
    sendError(res, 401, 'AUTH_005', 'Invalid or expired refresh token');
  }
});

// POST /v1/auth/logout
app.post('/v1/auth/logout', async (req, res) => {
  const { refresh_token } = req.body;
  if (refresh_token) {
    const tokenHash = require('crypto')
      .createHash('sha256').update(refresh_token).digest('hex');
    await db.query('UPDATE refresh_tokens SET revoked_at = NOW() WHERE token_hash = $1', [tokenHash]);
  }
  sendResponse(res, 200, { message: 'Logged out successfully' });
});

// GET /v1/auth/me
app.get('/v1/auth/me', require('../../../libs/middleware/auth.middleware').authenticateJWT, async (req, res) => {
  const user = await db.query(`
    SELECT u.id, u.username, u.phone, u.email, u.status, u.kyc_status, u.referral_code, u.created_at,
           p.full_name, p.avatar_url, p.level, p.xp_points, p.total_games, p.wins, p.elo_rating,
           w.balance_cash, w.balance_bonus, w.balance_tokens
    FROM users u
    LEFT JOIN user_profiles p ON p.user_id = u.id
    LEFT JOIN wallets w ON w.user_id = u.id
    WHERE u.id = $1
  `, [req.user.id]);

  if (user.rows.length === 0) return sendError(res, 404, 'AUTH_USER_NOT_FOUND', 'User not found');
  sendResponse(res, 200, user.rows[0]);
});

// Helper: issue JWT pair
async function issueTokens(userId, deviceId) {
  const accessToken = jwt.sign(
    { sub: userId, device_id: deviceId },
    process.env.JWT_SECRET,
    { expiresIn: '15m' }
  );

  const refreshToken = jwt.sign(
    { sub: userId, device_id: deviceId },
    process.env.JWT_REFRESH_SECRET,
    { expiresIn: '30d' }
  );

  // Store refresh token hash in DB
  const tokenHash = require('crypto')
    .createHash('sha256').update(refreshToken).digest('hex');

  await db.query(`
    INSERT INTO refresh_tokens (id, user_id, token_hash, device_id, expires_at)
    VALUES ($1, $2, $3, $4, NOW() + INTERVAL '30 days')
  `, [uuidv4(), userId, tokenHash, deviceId]);

  return {
    access_token: accessToken,
    refresh_token: refreshToken,
    expires_in: 900,
  };
}

app.listen(PORT, () => logger.info(`Auth Service running on port ${PORT}`));
module.exports = app;
