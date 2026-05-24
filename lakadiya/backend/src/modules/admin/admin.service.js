const { query } = require('../../config/database');

const getDashboardStats = async () => {
  const [users, activeGames, todayMatches, totalMatches] = await Promise.all([
    query('SELECT COUNT(*) FROM users WHERE is_banned = FALSE'),
    query("SELECT COUNT(*) FROM rooms WHERE status = 'playing'"),
    query("SELECT COUNT(*) FROM matches WHERE created_at >= CURRENT_DATE"),
    query('SELECT COUNT(*) FROM matches'),
  ]);

  return {
    totalUsers:    parseInt(users.rows[0].count),
    activeGames:   parseInt(activeGames.rows[0].count),
    todayMatches:  parseInt(todayMatches.rows[0].count),
    totalMatches:  parseInt(totalMatches.rows[0].count),
  };
};

const getUsers = async ({ page = 1, limit = 20, search = '', banned = null }) => {
  const offset = (page - 1) * limit;
  let whereClause = 'WHERE 1=1';
  const params = [];

  if (search) {
    params.push(`%${search}%`);
    whereClause += ` AND (u.username ILIKE $${params.length} OR u.email ILIKE $${params.length})`;
  }
  if (banned !== null) {
    params.push(banned);
    whereClause += ` AND u.is_banned = $${params.length}`;
  }

  params.push(limit, offset);
  const result = await query(
    `SELECT u.id, u.username, u.email, u.provider, u.coins, u.xp, u.level,
            u.is_banned, u.created_at, u.last_seen,
            ps.matches_played, ps.matches_won
     FROM users u
     LEFT JOIN player_stats ps ON ps.user_id = u.id
     ${whereClause}
     ORDER BY u.created_at DESC
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );

  const countParams = params.slice(0, params.length - 2);
  const count = await query(
    `SELECT COUNT(*) FROM users u ${whereClause}`, countParams
  );

  return { users: result.rows, total: parseInt(count.rows[0].count) };
};

const banUser = async (userId, reason) => {
  await query(
    'UPDATE users SET is_banned = TRUE, ban_reason = $1 WHERE id = $2',
    [reason, userId]
  );
};

const unbanUser = async (userId) => {
  await query(
    'UPDATE users SET is_banned = FALSE, ban_reason = NULL WHERE id = $1',
    [userId]
  );
};

const getMatches = async ({ page = 1, limit = 20, status = '' }) => {
  const offset = (page - 1) * limit;
  const params = [limit, offset];
  let where = 'WHERE 1=1';
  if (status) { params.unshift(status); where = `WHERE m.status = $1`; }

  const result = await query(
    `SELECT m.id, m.status, m.created_at, m.finished_at,
            r.code AS room_code,
            u.username AS winner_name,
            (SELECT COUNT(*) FROM match_players WHERE match_id = m.id) AS player_count
     FROM matches m
     JOIN rooms r ON r.id = m.room_id
     LEFT JOIN users u ON u.id = m.winner_id
     ${where}
     ORDER BY m.created_at DESC
     LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params
  );

  const count = await query(`SELECT COUNT(*) FROM matches m ${where}`, status ? [status] : []);
  return { matches: result.rows, total: parseInt(count.rows[0].count) };
};

const getAnalytics = async () => {
  const last7days = await query(
    `SELECT DATE(created_at) AS date, COUNT(*) AS matches
     FROM matches
     WHERE created_at >= NOW() - INTERVAL '7 days'
     GROUP BY DATE(created_at)
     ORDER BY date`
  );

  const registrations = await query(
    `SELECT DATE(created_at) AS date, COUNT(*) AS users
     FROM users
     WHERE created_at >= NOW() - INTERVAL '7 days'
     GROUP BY DATE(created_at)
     ORDER BY date`
  );

  const topPlayers = await query(
    `SELECT u.username, ps.matches_won, ps.total_score
     FROM player_stats ps JOIN users u ON u.id = ps.user_id
     ORDER BY ps.matches_won DESC LIMIT 10`
  );

  return {
    matchesByDay:    last7days.rows,
    registrationsByDay: registrations.rows,
    topPlayers:      topPlayers.rows,
  };
};

module.exports = { getDashboardStats, getUsers, banUser, unbanUser, getMatches, getAnalytics };
