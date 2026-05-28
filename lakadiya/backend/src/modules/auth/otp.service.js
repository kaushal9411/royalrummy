const axios = require('axios');
const { query } = require('../../config/database');
const logger = require('../../config/logger');
const { sendOtpNotification } = require('../notifications/notification.service');

// Ensure otp_codes table exists on startup
const _init = query(`
  CREATE TABLE IF NOT EXISTS otp_codes (
    id          SERIAL PRIMARY KEY,
    mobile      VARCHAR(15)  NOT NULL,
    code        VARCHAR(6)   NOT NULL,
    expires_at  TIMESTAMPTZ  NOT NULL,
    used        BOOLEAN      DEFAULT FALSE,
    created_at  TIMESTAMPTZ  DEFAULT NOW()
  )
`).catch(() => {});

// ── Delivery via Fast2SMS ─────────────────────────────────────────────────────
const _sendViaSms = async (mobile, code) => {
  const apiKey = process.env.FAST2SMS_API_KEY;
  const number = mobile.replace(/^\+91/, '').replace(/\D/g, '');

  const response = await axios.get('https://www.fast2sms.com/dev/bulkV2', {
    params: {
      authorization:    apiKey,
      variables_values: code,
      route:            'otp',
      numbers:          number,
    },
    timeout: 8000,
  });

  if (response.data?.return !== true) {
    logger.error('[Fast2SMS] Unexpected response:', response.data);
    throw new Error(response.data?.message || 'SMS send failed');
  }

  logger.info(`[Fast2SMS] OTP sent to ${number}`);
};

// ── Public: send OTP ─────────────────────────────────────────────────────────
/**
 * @param {string} mobile     — E.164 format, e.g. "+919876543210"
 * @param {string} [fcmToken] — Device FCM token; required when Fast2SMS is not configured
 */
const sendOtp = async (mobile, fcmToken) => {
  await _init;

  const code      = String(Math.floor(100000 + Math.random() * 900000));
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 min

  // Invalidate previous unused OTPs for this mobile
  await query(
    `UPDATE otp_codes SET used = TRUE WHERE mobile = $1 AND used = FALSE`,
    [mobile]
  );

  // Store OTP before delivery attempt
  await query(
    `INSERT INTO otp_codes (mobile, code, expires_at) VALUES ($1, $2, $3)`,
    [mobile, code, expiresAt]
  );

  const fast2smsKey = process.env.FAST2SMS_API_KEY;
  const useSms = fast2smsKey &&
                 fast2smsKey !== 'null' &&
                 fast2smsKey !== 'your_fast2sms_api_key_here';

  if (useSms) {
    // ── Path A: Send via Fast2SMS (SMS) ────────────────────────────────────
    try {
      await _sendViaSms(mobile, code);
    } catch (err) {
      logger.error('[OTP] Fast2SMS delivery failed:', err.message);
      throw { status: 503, message: 'Failed to send OTP via SMS. Please try again.' };
    }
  } else {
    // ── Path B: Send via Firebase push notification ─────────────────────────
    try {
      if (fcmToken) {
        // Extract user_id from fcmToken context or use mobile as fallback
        // In production, you'd query DB for user_id by mobile
        const result = await query(
          `SELECT id FROM users WHERE mobile = $1 LIMIT 1`,
          [mobile]
        );
        
        if (result.rows.length > 0) {
          const userId = result.rows[0].id;
          await sendOtpNotification(userId, code);
        } else {
          logger.warn(`[OTP] No user found for mobile ${mobile}`);
          throw new Error('User not found');
        }
      } else {
        throw new Error('No FCM token provided');
      }
    } catch (err) {
      if (process.env.NODE_ENV === 'development') {
        // Dev safety net — log OTP to console when neither service is configured
        logger.warn(`[OTP DEV] ${mobile} → ${code}  (no Fast2SMS / Firebase configured)`);
      } else {
        logger.error('[OTP] FCM delivery failed:', err.message);
        throw { status: 503, message: err.message || 'Failed to deliver OTP. Please try again.' };
      }
    }
  }

  return true;
};

// ── Public: verify OTP ───────────────────────────────────────────────────────
const verifyOtp = async (mobile, code) => {
  await _init;

  const result = await query(
    `SELECT id FROM otp_codes
     WHERE mobile = $1 AND code = $2 AND used = FALSE AND expires_at > NOW()
     ORDER BY created_at DESC LIMIT 1`,
    [mobile, code]
  );

  if (!result.rows.length) {
    throw { status: 400, message: 'Invalid or expired OTP' };
  }

  await query(`UPDATE otp_codes SET used = TRUE WHERE id = $1`, [result.rows[0].id]);
  return true;
};

module.exports = { sendOtp, verifyOtp };
