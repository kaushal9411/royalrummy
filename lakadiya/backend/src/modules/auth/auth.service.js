const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const { query } = require('../../config/database');
const logger = require('../../config/logger');
const { sendOtp, verifyOtp } = require('./otp.service');
const { getSettings } = require('../admin/settings.service');

// Ensure mobile column exists
query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS mobile VARCHAR(15) UNIQUE`).catch(() => {});

const generateToken = (userId, username, isAdmin = false) =>
  jwt.sign({ userId, username, isAdmin }, process.env.JWT_SECRET, {
    expiresIn: process.env.JWT_EXPIRES_IN || '7d',
  });

const _creditWelcomeBonus = async (userId) => {
  const { welcome_bonus } = await getSettings();
  const bonus = parseInt(welcome_bonus) || 50;
  await query(`UPDATE users SET coins = coins + $1 WHERE id = $2`, [bonus, userId]);
  await query(
    `INSERT INTO payment_transactions (user_id, amount, coins, type, status, description)
     VALUES ($1, $2, $3, 'add', 'success', 'Welcome bonus')`,
    [userId, bonus, bonus]
  );
};

const _randomUsername = () => {
  const adjectives = ['Royal', 'Lucky', 'Wild', 'Ace', 'King', 'Bold', 'Sharp', 'Swift'];
  const nouns      = ['Player', 'Dealer', 'Shark', 'Champ', 'Pro', 'Master', 'Star', 'Ace'];
  const adj  = adjectives[Math.floor(Math.random() * adjectives.length)];
  const noun = nouns[Math.floor(Math.random() * nouns.length)];
  const num  = Math.floor(1000 + Math.random() * 9000);
  return `${adj}${noun}${num}`;
};

// ─── OTP: send ────────────────────────────────────────────────────────────────
const requestOtp = async ({ mobile, fcmToken }) => {
  if (!mobile) throw { status: 400, message: 'Mobile number is required' };
  await sendOtp(mobile, fcmToken);
  return { success: true };
};

// ─── OTP: verify → login OR auto-register ─────────────────────────────────────
const verifyAndLogin = async ({ mobile, otp }) => {
  const settings = await getSettings();
  if (settings.maintenance_mode)
    throw { status: 503, message: 'Platform is under maintenance. Please try again later.' };

  await verifyOtp(mobile, otp);

  // Find any existing user by mobile (including guests who may have registered earlier)
  let userResult = await query(
    `SELECT id, username, email, mobile, coins, xp, level, provider, is_banned
     FROM users WHERE mobile = $1`,
    [mobile]
  );

  let isNewUser = false;

  if (userResult.rows.length && userResult.rows[0].provider === 'guest') {
    // Guest account with this mobile exists — upgrade it to a real account
    userResult = await query(
      `UPDATE users SET provider = 'local', last_seen = NOW()
       WHERE mobile = $1
       RETURNING id, username, email, mobile, coins, xp, level, provider, is_banned`,
      [mobile]
    );
  } else if (!userResult.rows.length) {
    // No account at all — check if registration is enabled
    if (!settings.registration_enabled)
      throw { status: 403, message: 'New registrations are currently disabled.' };

    let username = _randomUsername();
    while ((await query('SELECT id FROM users WHERE username = $1', [username])).rows.length) {
      username = _randomUsername();
    }

    try {
      userResult = await query(
        `INSERT INTO users (username, mobile, provider, coins)
         VALUES ($1, $2, 'local', 0)
         RETURNING id, username, email, mobile, coins, xp, level, provider`,
        [username, mobile]
      );
      await query(`INSERT INTO player_stats (user_id) VALUES ($1)`, [userResult.rows[0].id]);
      await _creditWelcomeBonus(userResult.rows[0].id);
      userResult.rows[0].coins = WELCOME_BONUS;
      isNewUser = true;
    } catch (insertErr) {
      // Race condition: a concurrent request just inserted this user
      if (insertErr.code === '23505') {
        userResult = await query(
          `SELECT id, username, email, mobile, coins, xp, level, provider, is_banned
           FROM users WHERE mobile = $1`,
          [mobile]
        );
        if (!userResult.rows.length) throw insertErr;
      } else {
        throw insertErr;
      }
    }
  }

  const user = userResult.rows[0];
  if (user.is_banned) throw { status: 403, message: 'Account banned' };

  if (!isNewUser) {
    await query(`UPDATE users SET last_seen = NOW() WHERE id = $1`, [user.id]);
  }

  const { is_banned, ...safeUser } = user;
  return {
    token: generateToken(user.id, user.username, user.is_admin),
    user: safeUser,
    isNewUser,
  };
};

// ─── Guest: find-or-create by mobile, no OTP ──────────────────────────────────
const guestLogin = async ({ mobile } = {}) => {
  if (!mobile) throw { status: 400, message: 'Mobile number is required' };
  const settings = await getSettings();
  if (settings.maintenance_mode)
    throw { status: 503, message: 'Platform is under maintenance. Please try again later.' };

  // Check if any user (real or guest) already exists with this mobile
  const existing = await query(
    `SELECT id, username, email, mobile, coins, xp, level, provider, is_banned
     FROM users WHERE mobile = $1`,
    [mobile]
  );

  if (existing.rows.length) {
    const user = existing.rows[0];
    if (user.is_banned) throw { status: 403, message: 'Account banned' };
    await query(`UPDATE users SET last_seen = NOW() WHERE id = $1`, [user.id]);
    const { is_banned, ...safeUser } = user;
    return { token: generateToken(user.id, user.username), user: safeUser };
  }

  // New guest — create account
  const username = _randomUsername();
  const result = await query(
    `INSERT INTO users (username, mobile, provider, coins)
     VALUES ($1, $2, 'guest', 0)
     RETURNING id, username, email, mobile, coins, xp, level, provider`,
    [username, mobile]
  );
  const user = result.rows[0];
  await query(`INSERT INTO player_stats (user_id) VALUES ($1)`, [user.id]);
  return { token: generateToken(user.id, user.username), user };
};

// ─── Google ───────────────────────────────────────────────────────────────────
const googleAuth = async ({ googleId, email, name, avatarUrl }) => {
  let result = await query(
    `SELECT id, username, email, mobile, coins, xp, level, provider, is_banned
     FROM users WHERE provider = 'google' AND provider_id = $1`,
    [googleId]
  );

  if (!result.rows.length) {
    let username = name.replace(/\s+/g, '_').substring(0, 25);
    const taken = await query(`SELECT id FROM users WHERE username = $1`, [username]);
    if (taken.rows.length) username = _randomUsername();

    result = await query(
      `INSERT INTO users (username, email, provider, provider_id, avatar_url, coins)
       VALUES ($1, $2, 'google', $3, $4, 0)
       RETURNING id, username, email, mobile, coins, xp, level, provider`,
      [username, email, googleId, avatarUrl]
    );
    const newUserId = result.rows[0].id;
    await query(`INSERT INTO player_stats (user_id) VALUES ($1)`, [newUserId]);
    await _creditWelcomeBonus(newUserId);
    result.rows[0].coins = WELCOME_BONUS;
  }

  const user = result.rows[0];
  if (user.is_banned) throw { status: 403, message: 'Account banned' };
  await query(`UPDATE users SET last_seen = NOW() WHERE id = $1`, [user.id]);
  return { token: generateToken(user.id, user.username), user };
};

// ─── Admin login ──────────────────────────────────────────────────────────────
const adminLogin = async ({ email, password }) => {
  const result = await query(
    `SELECT id, username, password_hash, is_admin FROM users WHERE email = $1 AND is_admin = TRUE`,
    [email]
  );
  if (!result.rows.length) throw { status: 401, message: 'Invalid credentials' };

  const user = result.rows[0];
  const valid = await bcrypt.compare(password, user.password_hash);
  if (!valid) throw { status: 401, message: 'Invalid credentials' };

  return { token: generateToken(user.id, user.username, true) };
};

module.exports = {
  requestOtp,
  verifyAndLogin,
  guestLogin,
  googleAuth,
  adminLogin,
};
