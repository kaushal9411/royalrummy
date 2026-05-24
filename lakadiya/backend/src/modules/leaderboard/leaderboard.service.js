const { query } = require('../../config/database');

const getLeaderboard = async (type = 'wins', limit = 50) => {
  const orderMap = {
    wins:  'ps.matches_won',
    score: 'ps.total_score',
    level: 'u.level',
  };
  const orderBy = orderMap[type] || orderMap.wins;

  const result = await query(
    `SELECT u.id, u.username, u.avatar_url, u.level,
            ps.matches_played, ps.matches_won, ps.total_score,
            ROW_NUMBER() OVER (ORDER BY ${orderBy} DESC) AS rank
     FROM users u
     JOIN player_stats ps ON ps.user_id = u.id
     WHERE u.is_banned = FALSE AND ps.matches_played > 0
     ORDER BY ${orderBy} DESC
     LIMIT $1`,
    [limit]
  );
  return result.rows;
};

const getUserRank = async (userId) => {
  const result = await query(
    `SELECT rank FROM (
       SELECT user_id,
              ROW_NUMBER() OVER (ORDER BY matches_won DESC) AS rank
       FROM player_stats
     ) ranked
     WHERE user_id = $1`,
    [userId]
  );
  return result.rows[0]?.rank || null;
};

module.exports = { getLeaderboard, getUserRank };
