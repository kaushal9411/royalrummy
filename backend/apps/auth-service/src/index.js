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

// POST /v1/auth/login (password-based — for users who set a password)
app.post('/v1/auth/login',
  [
    body('phone').optional().matches(/^\+91[6-9]\d{9}$/),
    body('email').optional().isEmail(),
    body('password').isLength({ min: 6 }),
    body('device_id').notEmpty(),
  ],
  async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return sendError(res, 400, 'AUTH_VALIDATION', 'Invalid input');

    const { phone, email, password, device_id, fcm_token } = req.body;
    const identifier = phone || email;
    if (!identifier) return sendError(res, 400, 'AUTH_VALIDATION', 'Phone or email required');

    const field = phone ? 'phone' : 'email';
    const result = await db.query(
      `SELECT id, password_hash, status, username, role FROM users WHERE ${field} = $1 AND deleted_at IS NULL`,
      [identifier]
    );

    if (result.rows.length === 0) return sendError(res, 401, 'AUTH_001', 'Invalid credentials');

    const user = result.rows[0];
    if (user.status === 'banned') return sendError(res, 403, 'AUTH_004', 'Account banned');
    if (user.status === 'suspended') return sendError(res, 403, 'AUTH_004', 'Account suspended');

    if (!user.password_hash) {
      return sendError(res, 400, 'AUTH_NO_PASSWORD', 'Account uses OTP login. Please use /auth/otp/send');
    }

    const valid = await bcrypt.compare(password, user.password_hash);
    if (!valid) return sendError(res, 401, 'AUTH_001', 'Invalid credentials');

    // Update last login + device
    await db.query('UPDATE users SET last_login_at = NOW() WHERE id = $1', [user.id]);
    if (device_id) {
      await db.query(`
        INSERT INTO user_devices (id, user_id, device_id, fcm_token, is_trusted)
        VALUES ($1, $2, $3, $4, true)
        ON CONFLICT (user_id, device_id) DO UPDATE SET fcm_token = $4, last_active_at = NOW()
      `, [uuidv4(), user.id, device_id, fcm_token]);
    }

    const tokens = await issueTokens(user.id, device_id, user.role);
    sendResponse(res, 200, {
      user: { id: user.id, username: user.username, role: user.role },
      ...tokens,
    });
  }
);

// POST /v1/auth/logout/all
app.post('/v1/auth/logout/all', require('../../../libs/middleware/auth.middleware').authenticateJWT, async (req, res) => {
  await db.query(
    'UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = $1 AND revoked_at IS NULL',
    [req.user.id]
  );
  sendResponse(res, 200, { message: 'Logged out from all devices' });
});

// PATCH /v1/auth/profile
app.patch('/v1/auth/profile', require('../../../libs/middleware/auth.middleware').authenticateJWT,
  [
    body('full_name').optional().isLength({ min: 2, max: 100 }),
    body('avatar_url').optional().isURL(),
    body('bio').optional().isLength({ max: 500 }),
    body('date_of_birth').optional().isDate(),
    body('gender').optional().isIn(['male', 'female', 'other']),
    body('city').optional().isLength({ max: 100 }),
    body('state').optional().isLength({ max: 100 }),
  ],
  async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return sendError(res, 400, 'GENERAL_002', 'Validation failed', errors.array());

    const { full_name, avatar_url, bio, date_of_birth, gender, city, state } = req.body;
    const fields = [];
    const values = [];

    if (full_name !== undefined) { fields.push(`full_name = $${fields.length + 1}`); values.push(full_name); }
    if (avatar_url !== undefined) { fields.push(`avatar_url = $${fields.length + 1}`); values.push(avatar_url); }
    if (bio !== undefined) { fields.push(`bio = $${fields.length + 1}`); values.push(bio); }
    if (date_of_birth !== undefined) { fields.push(`date_of_birth = $${fields.length + 1}`); values.push(date_of_birth); }
    if (gender !== undefined) { fields.push(`gender = $${fields.length + 1}`); values.push(gender); }
    if (city !== undefined) { fields.push(`city = $${fields.length + 1}`); values.push(city); }
    if (state !== undefined) { fields.push(`state = $${fields.length + 1}`); values.push(state); }

    if (fields.length === 0) return sendError(res, 400, 'GENERAL_002', 'No fields to update');

    values.push(req.user.id);
    await db.query(
      `UPDATE user_profiles SET ${fields.join(', ')}, updated_at = NOW() WHERE user_id = $${values.length}`,
      values
    );

    sendResponse(res, 200, { message: 'Profile updated' });
  }
);

// POST /v1/auth/change-password
app.post('/v1/auth/change-password', require('../../../libs/middleware/auth.middleware').authenticateJWT,
  [
    body('current_password').optional().isLength({ min: 6 }),
    body('new_password').isLength({ min: 8 }).matches(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/),
  ],
  async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return sendError(res, 400, 'GENERAL_002', 'Password must be 8+ chars with uppercase, lowercase, and number');
    }

    const { current_password, new_password } = req.body;
    const result = await db.query('SELECT password_hash FROM users WHERE id = $1', [req.user.id]);
    const user = result.rows[0];

    // If user already has a password, verify current
    if (user.password_hash && current_password) {
      const valid = await bcrypt.compare(current_password, user.password_hash);
      if (!valid) return sendError(res, 400, 'AUTH_001', 'Current password is incorrect');
    }

    const hash = await bcrypt.hash(new_password, 12);
    await db.query('UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2', [hash, req.user.id]);

    sendResponse(res, 200, { message: 'Password updated successfully' });
  }
);

// DELETE /v1/auth/account
app.delete('/v1/auth/account', require('../../../libs/middleware/auth.middleware').authenticateJWT, async (req, res) => {
  // Soft delete: set deleted_at and update status
  await db.query(
    "UPDATE users SET deleted_at = NOW(), status = 'banned', updated_at = NOW() WHERE id = $1",
    [req.user.id]
  );
  // Revoke all tokens
  await db.query('UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = $1', [req.user.id]);
  sendResponse(res, 200, { message: 'Account deleted' });
});

// POST /v1/auth/kyc/submit
app.post('/v1/auth/kyc/submit', require('../../../libs/middleware/auth.middleware').authenticateJWT,
  [
    body('doc_type').isIn(['aadhaar', 'pan', 'passport', 'driving_license']),
    body('doc_number').notEmpty().isLength({ min: 5, max: 30 }),
    body('doc_front_url').isURL(),
  ],
  async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return sendError(res, 400, 'GENERAL_002', 'Validation failed', errors.array());

    const { doc_type, doc_number, doc_front_url, doc_back_url, selfie_url } = req.body;

    // Check for existing pending/approved KYC
    const existing = await db.query(
      "SELECT id, status FROM kyc_documents WHERE user_id = $1 AND status NOT IN ('rejected')",
      [req.user.id]
    );
    if (existing.rows.length > 0) {
      return sendError(res, 409, 'KYC_ALREADY_SUBMITTED', `KYC already ${existing.rows[0].status}`);
    }

    await db.query(`
      INSERT INTO kyc_documents (id, user_id, doc_type, doc_number, doc_front_url, doc_back_url, selfie_url, status)
      VALUES ($1, $2, $3, $4, $5, $6, $7, 'pending')
    `, [uuidv4(), req.user.id, doc_type, doc_number, doc_front_url, doc_back_url || null, selfie_url || null]);

    // Update user kyc_status
    await db.query(
      "UPDATE users SET kyc_status = 'pending', updated_at = NOW() WHERE id = $1",
      [req.user.id]
    );

    sendResponse(res, 201, { message: 'KYC documents submitted successfully. Under review.' });
  }
);

// GET /v1/auth/kyc/status
app.get('/v1/auth/kyc/status', require('../../../libs/middleware/auth.middleware').authenticateJWT, async (req, res) => {
  const result = await db.query(
    `SELECT doc_type, status, rejection_reason, submitted_at, reviewed_at
     FROM kyc_documents WHERE user_id = $1
     ORDER BY submitted_at DESC LIMIT 1`,
    [req.user.id]
  );

  const user = await db.query(
    'SELECT kyc_status FROM users WHERE id = $1',
    [req.user.id]
  );

  sendResponse(res, 200, {
    kyc_status: user.rows[0]?.kyc_status || 'pending',
    latest_submission: result.rows[0] || null,
  });
});

// Helper: issue JWT pair
async function issueTokens(userId, deviceId, role = 'player') {
  const userRow = await db.query('SELECT username FROM users WHERE id = $1', [userId]);
  const username = userRow.rows[0]?.username || '';
  const jti = uuidv4();

  const accessToken = jwt.sign(
    { sub: userId, username, role, device_id: deviceId, jti },
    process.env.JWT_SECRET,
    { expiresIn: '15m' }
  );

  const refreshToken = jwt.sign(
    { sub: userId, username, role, device_id: deviceId },
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
