const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const { query } = require('../../config/database');

const generateToken = (userId, username, isAdmin = false) =>
  jwt.sign({ userId, username, isAdmin }, process.env.JWT_SECRET, {
    expiresIn: process.env.JWT_EXPIRES_IN || '7d',
  });

const register = async ({ username, email, password }) => {
  const existing = await query(
    'SELECT id FROM users WHERE email = $1 OR username = $2',
    [email, username]
  );
  if (existing.rows.length) throw { status: 409, message: 'Email or username already taken' };

  const hash = await bcrypt.hash(password, 12);
  const result = await query(
    `INSERT INTO users (username, email, password_hash, provider)
     VALUES ($1, $2, $3, 'local') RETURNING id, username, email, coins, xp, level`,
    [username, email, hash]
  );
  const user = result.rows[0];
  await query('INSERT INTO player_stats (user_id) VALUES ($1)', [user.id]);
  return { token: generateToken(user.id, user.username), user };
};

const login = async ({ email, password }) => {
  const result = await query(
    'SELECT id, username, email, password_hash, coins, xp, level, is_banned FROM users WHERE email = $1 AND provider = $2',
    [email, 'local']
  );
  if (!result.rows.length) throw { status: 401, message: 'Invalid credentials' };

  const user = result.rows[0];
  if (user.is_banned) throw { status: 403, message: 'Account banned' };

  const valid = await bcrypt.compare(password, user.password_hash);
  if (!valid) throw { status: 401, message: 'Invalid credentials' };

  await query('UPDATE users SET last_seen = NOW() WHERE id = $1', [user.id]);
  const { password_hash, ...safeUser } = user;
  return { token: generateToken(user.id, user.username, user.is_admin), user: safeUser };
};

const guestLogin = async () => {
  const guestNum = Math.floor(Math.random() * 900000) + 100000;
  const username = `Guest_${guestNum}`;
  const result = await query(
    `INSERT INTO users (username, provider, coins) VALUES ($1, 'guest', 500)
     RETURNING id, username, coins, xp, level`,
    [username]
  );
  const user = result.rows[0];
  await query('INSERT INTO player_stats (user_id) VALUES ($1)', [user.id]);
  return { token: generateToken(user.id, user.username), user };
};

const googleAuth = async ({ googleId, email, name, avatarUrl }) => {
  let result = await query(
    'SELECT id, username, email, coins, xp, level, is_banned FROM users WHERE provider = $1 AND provider_id = $2',
    ['google', googleId]
  );

  if (!result.rows.length) {
    let username = name.replace(/\s+/g, '_').substring(0, 25);
    const taken = await query('SELECT id FROM users WHERE username = $1', [username]);
    if (taken.rows.length) username = `${username}_${Math.floor(Math.random() * 9999)}`;

    result = await query(
      `INSERT INTO users (username, email, provider, provider_id, avatar_url)
       VALUES ($1, $2, 'google', $3, $4) RETURNING id, username, email, coins, xp, level`,
      [username, email, googleId, avatarUrl]
    );
    await query('INSERT INTO player_stats (user_id) VALUES ($1)', [result.rows[0].id]);
  }

  const user = result.rows[0];
  if (user.is_banned) throw { status: 403, message: 'Account banned' };
  await query('UPDATE users SET last_seen = NOW() WHERE id = $1', [user.id]);
  return { token: generateToken(user.id, user.username), user };
};

const adminLogin = async ({ email, password }) => {
  const result = await query(
    'SELECT id, username, email, password_hash, is_admin FROM users WHERE email = $1 AND is_admin = TRUE',
    [email]
  );
  if (!result.rows.length) throw { status: 401, message: 'Invalid credentials' };

  const user = result.rows[0];
  const valid = await bcrypt.compare(password, user.password_hash);
  if (!valid) throw { status: 401, message: 'Invalid credentials' };

  return { token: generateToken(user.id, user.username, true) };
};

module.exports = { register, login, guestLogin, googleAuth, adminLogin };
