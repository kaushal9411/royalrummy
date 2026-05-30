const { query } = require('../../config/database');

// Ensure compliance columns exist on users table (idempotent)
const ensureComplianceColumns = async () => {
  await query(`
    ALTER TABLE users
      ADD COLUMN IF NOT EXISTS date_of_birth DATE,
      ADD COLUMN IF NOT EXISTS kyc_verified   BOOLEAN DEFAULT FALSE,
      ADD COLUMN IF NOT EXISTS is_minor        BOOLEAN DEFAULT FALSE
  `);
};
ensureComplianceColumns().catch(() => {}); // fire-and-forget on startup

function computeAge(dob) {
  if (!dob) return null;
  const now = new Date();
  const birth = new Date(dob);
  let age = now.getFullYear() - birth.getFullYear();
  if (now.getMonth() < birth.getMonth() ||
      (now.getMonth() === birth.getMonth() && now.getDate() < birth.getDate())) age--;
  return age;
}

const getProfile = async (userId) => {
  const result = await query(
    `SELECT u.id, u.username, u.email, u.mobile, u.avatar_url, u.coins, u.xp, u.level,
            u.provider, u.created_at, u.last_seen,
            u.date_of_birth, u.kyc_verified, u.is_minor,
            ps.matches_played, ps.matches_won, ps.total_score,
            ps.bids_exact, ps.bids_failed, ps.bids_over
     FROM users u
     LEFT JOIN player_stats ps ON ps.user_id = u.id
     WHERE u.id = $1`,
    [userId]
  );
  if (!result.rows.length) throw { status: 404, message: 'User not found' };
  const row = result.rows[0];
  row.age = computeAge(row.date_of_birth);
  return row;
};

const updateProfile = async (userId, { username, email, avatarUrl, dateOfBirth, date_of_birth }) => {
  dateOfBirth = dateOfBirth || date_of_birth; // accept both camelCase and snake_case
  if (username) {
    const taken = await query('SELECT id FROM users WHERE username = $1 AND id != $2', [username, userId]);
    if (taken.rows.length) throw { status: 409, message: 'Username taken' };
  }

  // Compute is_minor if DOB is being set
  let isMinor = null;
  if (dateOfBirth) {
    const age = computeAge(dateOfBirth);
    isMinor = age !== null && age < 18;
  }

  const result = await query(
    `UPDATE users SET
       username       = COALESCE($1, username),
       email          = COALESCE($2, email),
       avatar_url     = COALESCE($3, avatar_url),
       date_of_birth  = COALESCE($5, date_of_birth),
       is_minor       = CASE WHEN $5 IS NOT NULL THEN $6 ELSE is_minor END
     WHERE id = $4
     RETURNING id, username, email, mobile, avatar_url, coins, xp, level, provider,
               date_of_birth, kyc_verified, is_minor`,
    [username || null, email || null, avatarUrl || null, userId,
     dateOfBirth || null, isMinor]
  );
  return result.rows[0];
};

const getMatchHistory = async (userId, limit = 20, offset = 0) => {
  const result = await query(
    `SELECT m.id, m.created_at, m.finished_at, m.status,
            mp.final_score, mp.seat,
            u.username AS winner_name
     FROM match_players mp
     JOIN matches m ON m.id = mp.match_id
     LEFT JOIN users u ON u.id = m.winner_id
     WHERE mp.user_id = $1
     ORDER BY m.created_at DESC
     LIMIT $2 OFFSET $3`,
    [userId, limit, offset]
  );
  return result.rows;
};

const sendFriendRequest = async (userId, friendId) => {
  if (userId === friendId) throw { status: 400, message: 'Cannot add yourself' };
  const existing = await query(
    'SELECT status FROM friendships WHERE user_id = $1 AND friend_id = $2',
    [userId, friendId]
  );
  if (existing.rows.length) throw { status: 409, message: 'Request already exists' };

  await query(
    'INSERT INTO friendships (user_id, friend_id) VALUES ($1, $2)',
    [userId, friendId]
  );
  // Also create a notification
  await query(
    `INSERT INTO notifications (user_id, type, title, body, data)
     VALUES ($1, 'friend_request', 'Friend Request', 'You have a new friend request', $2)`,
    [friendId, JSON.stringify({ fromUserId: userId })]
  );
};

const acceptFriendRequest = async (userId, friendId) => {
  await query(
    `UPDATE friendships SET status = 'accepted'
     WHERE user_id = $1 AND friend_id = $2 AND status = 'pending'`,
    [friendId, userId]
  );
  // Create reverse row
  const existing = await query(
    'SELECT id FROM friendships WHERE user_id = $1 AND friend_id = $2',
    [userId, friendId]
  );
  if (!existing.rows.length) {
    await query(
      `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted')`,
      [userId, friendId]
    );
  }
};

const declineFriendRequest = async (userId, friendId) => {
  await query(
    `DELETE FROM friendships
     WHERE user_id = $1 AND friend_id = $2 AND status = 'pending'`,
    [friendId, userId]
  );
};

const getPendingRequests = async (userId) => {
  const result = await query(
    `SELECT f.id, f.user_id as from_user_id, u.username as from_user_name, u.avatar_url as from_user_avatar, u.level, f.created_at
     FROM friendships f
     JOIN users u ON u.id = f.user_id
     WHERE f.friend_id = $1 AND f.status = 'pending'
     ORDER BY f.created_at DESC`,
    [userId]
  );
  return result.rows;
};

const getFriends = async (userId) => {
  const result = await query(
    `SELECT u.id, u.username, u.avatar_url, u.level, u.last_seen, f.status
     FROM friendships f
     JOIN users u ON u.id = f.friend_id
     WHERE f.user_id = $1 AND f.status = 'accepted'
     ORDER BY u.username`,
    [userId]
  );
  return result.rows;
};

const getNotifications = async (userId) => {
  const result = await query(
    `SELECT id, type, title, body, is_read, data, created_at
     FROM notifications WHERE user_id = $1
     ORDER BY created_at DESC LIMIT 50`,
    [userId]
  );
  return result.rows;
};

const markNotificationsRead = async (userId) => {
  await query('UPDATE notifications SET is_read = TRUE WHERE user_id = $1', [userId]);
};

const searchUsers = async (currentUserId, q, limit = 30) => {
  const result = await query(
    `SELECT id, username, avatar_url, level, xp
     FROM users
     WHERE id != $1
       AND (username ILIKE $2 OR $2 = '')
     ORDER BY level DESC, username
     LIMIT $3`,
    [currentUserId, q ? `%${q}%` : '', limit]
  );
  return result.rows;
};

module.exports = {
  getProfile, updateProfile, getMatchHistory,
  sendFriendRequest, acceptFriendRequest, declineFriendRequest, getPendingRequests, getFriends,
  getNotifications, markNotificationsRead,
  searchUsers,
};
