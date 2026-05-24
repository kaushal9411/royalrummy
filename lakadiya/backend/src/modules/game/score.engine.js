const { query } = require('../../config/database');
const { calculateScore } = require('./game.engine');

async function persistRound(matchId, roundNumber, dealerSeat, bids, tricksWon) {
  const roundResult = await query(
    `INSERT INTO rounds (match_id, round_number, dealer_seat, status)
     VALUES ($1, $2, $3, 'completed') RETURNING id`,
    [matchId, roundNumber, dealerSeat]
  );
  const roundId = roundResult.rows[0].id;

  for (const seat of Object.keys(bids)) {
    const bid = bids[seat];
    const won = tricksWon[seat] || 0;
    const score = calculateScore(bid, won);
    await query(
      `INSERT INTO bids (round_id, seat, bid_amount, tricks_won, score)
       VALUES ($1, $2, $3, $4, $5)`,
      [roundId, parseInt(seat), bid, won, score]
    );
  }
  return roundId;
}

async function persistMatch(matchId, winnerUserId, finalScores, players) {
  await query(
    `UPDATE matches SET status = 'completed', winner_id = $1, finished_at = NOW()
     WHERE id = $2`,
    [winnerUserId, matchId]
  );

  for (const player of players) {
    if (player.isBot) continue;
    const score = finalScores[player.seat] || 0;
    await query(
      `INSERT INTO match_players (match_id, user_id, seat, final_score)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (match_id, seat) DO UPDATE SET final_score = $4`,
      [matchId, player.userId, player.seat, score]
    );
  }
}

async function updatePlayerStats(players, finalScores, winnerSeat) {
  for (const player of players) {
    if (player.isBot) continue;
    const isWinner = player.seat === winnerSeat;
    await query(
      `INSERT INTO player_stats (user_id, matches_played, matches_won, total_score)
         VALUES ($1, 1, $2, $3)
       ON CONFLICT (user_id) DO UPDATE SET
         matches_played = player_stats.matches_played + 1,
         matches_won    = player_stats.matches_won + $2,
         total_score    = player_stats.total_score + $3,
         highest_score  = GREATEST(player_stats.highest_score, $3),
         updated_at     = NOW()`,
      [player.userId, isWinner ? 1 : 0, finalScores[player.seat] || 0]
    );

    // XP reward
    const xp = isWinner ? 100 : 25;
    await query('UPDATE users SET xp = xp + $1 WHERE id = $2', [xp, player.userId]);

    // Update level (every 500 XP = 1 level)
    await query(
      `UPDATE users SET level = GREATEST(1, FLOOR(xp / 500) + 1) WHERE id = $1`,
      [player.userId]
    );

    // Coins reward
    const coins = isWinner ? 50 : 10;
    await query('UPDATE users SET coins = coins + $1 WHERE id = $2', [coins, player.userId]);
    await query(
      `INSERT INTO coin_transactions (user_id, amount, type, description)
       VALUES ($1, $2, $3, $4)`,
      [player.userId, coins, 'game_reward', isWinner ? 'Match winner reward' : 'Participation reward']
    );
  }
}

async function createMatch(roomId) {
  const result = await query(
    `INSERT INTO matches (room_id) VALUES ($1) RETURNING id`,
    [roomId]
  );
  await query(`UPDATE rooms SET status = 'playing' WHERE id = $1`, [roomId]);
  return result.rows[0].id;
}

module.exports = { persistRound, persistMatch, updatePlayerStats, createMatch };
