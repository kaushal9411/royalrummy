require('dotenv').config({ path: '../../../.env' });
const express = require('express');
const { v4: uuidv4 } = require('uuid');
const db = require('../../../libs/database/db');
const redis = require('../../../libs/cache/redis');
const logger = require('../../../libs/utils/logger');
const { sendResponse, sendError } = require('../../../libs/utils/response');
const { authenticateJWT } = require('../../../libs/middleware/auth.middleware');
const { errorHandler, asyncHandler } = require('../../../libs/middleware/error.middleware');
const { requestLogger } = require('../../../libs/middleware/logger.middleware');

const app = express();
app.use(express.json());
app.use(requestLogger);

const PORT = process.env.MATCHMAKING_SERVICE_PORT || 3004;

// Queue key: "mm:{gameType}:{feeBucket}"
// Redis sorted set: score = joinedAt timestamp; member = userId
const QUEUE_PREFIX = 'mm:queue:';
const PLAYER_QUEUE_PREFIX = 'mm:player:';
const BOT_FILL_DELAY_MS = 30_000;
const TABLE_START_DELAY_MS = 5_000;

function feeBucket(entryFee) {
  const fee = parseFloat(entryFee || 0);
  if (fee === 0) return 'free';
  if (fee <= 10) return 'micro';
  if (fee <= 50) return 'low';
  if (fee <= 200) return 'mid';
  return 'high';
}

function queueKey(gameType, entryFee) {
  return `${QUEUE_PREFIX}${gameType}:${feeBucket(entryFee)}`;
}

// Health
app.get('/health', (req, res) => res.json({ status: 'ok', service: 'matchmaking-service' }));

// =============================================================================
// POST /v1/matchmaking/join — join the queue
// =============================================================================
app.post('/v1/matchmaking/join', authenticateJWT, asyncHandler(async (req, res) => {
  const { game_type = 'points', entry_fee = 0, max_players = 6 } = req.body;
  const userId = req.user.id;

  // Check if user is already in a queue
  const existingQueue = await redis.get(`${PLAYER_QUEUE_PREFIX}${userId}`);
  if (existingQueue) {
    return sendError(res, 409, 'MM_001', 'Already in a matchmaking queue. Leave first.');
  }

  // Check wallet balance for paid tables
  if (parseFloat(entry_fee) > 0) {
    const wallet = await db.query(
      'SELECT balance_cash + balance_bonus AS total FROM wallets WHERE user_id = $1',
      [userId]
    );
    if (!wallet.rows.length || parseFloat(wallet.rows[0].total) < parseFloat(entry_fee)) {
      return sendError(res, 400, 'WALLET_001', 'Insufficient balance for this table');
    }
  }

  const key = queueKey(game_type, entry_fee);
  const joinedAt = Date.now();

  // Add to sorted set (score = timestamp for FIFO ordering)
  await redis.zadd(key, joinedAt, userId);
  await redis.expire(key, 300); // Queue expires in 5 minutes

  // Store user's queue info
  await redis.setex(`${PLAYER_QUEUE_PREFIX}${userId}`, 300, JSON.stringify({
    key, game_type, entry_fee, max_players, joinedAt,
  }));

  // Get queue size and position
  const queueSize = await redis.client.zcard(key);
  const position = await redis.client.zrank(key, userId);

  logger.info({ event: 'queue_joined', userId, key, queueSize });

  // Check if we have enough players to create a table
  if (queueSize >= max_players) {
    await _tryCreateTable(key, game_type, entry_fee, max_players, max_players);
  }

  sendResponse(res, 200, {
    status: 'queued',
    queue_key: key,
    position: (position ?? 0) + 1,
    players_waiting: queueSize,
    estimated_wait_ms: queueSize >= 2 ? TABLE_START_DELAY_MS : BOT_FILL_DELAY_MS,
  });
}));

// =============================================================================
// DELETE /v1/matchmaking/leave — leave the queue
// =============================================================================
app.delete('/v1/matchmaking/leave', authenticateJWT, asyncHandler(async (req, res) => {
  const userId = req.user.id;
  const queueInfo = await redis.get(`${PLAYER_QUEUE_PREFIX}${userId}`);

  if (!queueInfo) {
    return sendError(res, 404, 'MM_002', 'Not currently in any queue');
  }

  const { key } = JSON.parse(queueInfo);
  await redis.client.zrem(key, userId);
  await redis.del(`${PLAYER_QUEUE_PREFIX}${userId}`);

  logger.info({ event: 'queue_left', userId, key });
  sendResponse(res, 200, { message: 'Left matchmaking queue' });
}));

// =============================================================================
// GET /v1/matchmaking/status — current queue status
// =============================================================================
app.get('/v1/matchmaking/status', authenticateJWT, asyncHandler(async (req, res) => {
  const userId = req.user.id;
  const queueInfo = await redis.get(`${PLAYER_QUEUE_PREFIX}${userId}`);

  if (!queueInfo) {
    return sendResponse(res, 200, { in_queue: false });
  }

  const info = JSON.parse(queueInfo);
  const queueSize = await redis.client.zcard(info.key);
  const position = await redis.client.zrank(info.key, userId);

  sendResponse(res, 200, {
    in_queue: true,
    queue_key: info.key,
    game_type: info.game_type,
    entry_fee: info.entry_fee,
    position: (position ?? 0) + 1,
    players_waiting: queueSize,
    wait_time_ms: Date.now() - info.joinedAt,
  });
}));

// =============================================================================
// POST /v1/matchmaking/bot — add bot to a table (internal/admin use)
// =============================================================================
app.post('/v1/matchmaking/bot', authenticateJWT, asyncHandler(async (req, res) => {
  if (req.user.role !== 'admin') return sendError(res, 403, 'FORBIDDEN', 'Admins only');

  const { table_id, difficulty = 'beginner' } = req.body;
  const botId = `bot:${uuidv4()}`;

  await db.query(`
    INSERT INTO table_seats (id, table_id, user_id, seat_position, is_bot)
    SELECT $1, $2, $3,
      COALESCE((SELECT MAX(seat_position) FROM table_seats WHERE table_id = $2), 0) + 1,
      true
    WHERE EXISTS (SELECT 1 FROM game_tables WHERE id = $2 AND status = 'waiting')
  `, [uuidv4(), table_id, botId]);

  sendResponse(res, 201, { bot_id: botId, table_id, difficulty });
}));

// =============================================================================
// GET /v1/matchmaking/queues — list active queues (admin)
// =============================================================================
app.get('/v1/matchmaking/queues', authenticateJWT, asyncHandler(async (req, res) => {
  if (req.user.role !== 'admin') return sendError(res, 403, 'FORBIDDEN', 'Admins only');

  const keys = await redis.client.keys(`${QUEUE_PREFIX}*`);
  const queues = [];

  for (const key of keys) {
    const count = await redis.client.zcard(key);
    queues.push({ key, players_waiting: count });
  }

  sendResponse(res, 200, queues);
}));

// =============================================================================
// Internal: create a game table from queued players
// =============================================================================
async function _tryCreateTable(key, gameType, entryFee, maxPlayers, minPlayers) {
  // Pop exactly maxPlayers from the front of the sorted set (oldest first)
  const members = await redis.client.zpopmin(key, maxPlayers);
  if (!members || members.length < minPlayers * 2) {
    // Not enough players — push back what we took
    if (members) {
      for (let i = 0; i < members.length; i += 2) {
        await redis.zadd(key, members[i + 1], members[i]);
      }
    }
    return null;
  }

  // Extract userIds (zpopmin returns [member, score, member, score, ...])
  const playerIds = [];
  for (let i = 0; i < members.length; i += 2) {
    playerIds.push(members[i]);
  }

  const tableId = uuidv4();

  try {
    await db.query(`
      INSERT INTO game_tables (id, game_type, max_players, min_players, entry_fee, status, is_private)
      VALUES ($1, $2, $3, $4, $5, 'waiting', false)
    `, [tableId, gameType, maxPlayers, minPlayers, entryFee]);

    for (let i = 0; i < playerIds.length; i++) {
      await db.query(`
        INSERT INTO table_seats (id, table_id, user_id, seat_position)
        VALUES ($1, $2, $3, $4)
      `, [uuidv4(), tableId, playerIds[i], i + 1]);

      // Clear queue registration
      await redis.del(`${PLAYER_QUEUE_PREFIX}${playerIds[i]}`);
    }

    logger.info({ event: 'table_created', tableId, players: playerIds.length, gameType, entryFee });
    return tableId;
  } catch (err) {
    logger.error({ event: 'table_create_failed', error: err.message });
    // Re-queue players on failure
    const now = Date.now();
    for (const pid of playerIds) {
      await redis.zadd(key, now, pid);
    }
    return null;
  }
}

// Periodic queue processor — runs every 5 seconds
// Matches players who've been waiting and creates tables
setInterval(async () => {
  try {
    const keys = await redis.client.keys(`${QUEUE_PREFIX}*`);
    for (const key of keys) {
      const count = await redis.client.zcard(key);
      if (count < 2) continue;

      // Parse key back to params
      const parts = key.replace(QUEUE_PREFIX, '').split(':');
      const gameType = parts[0];
      const bucket = parts[1];

      const entryFeeMap = { free: 0, micro: 5, low: 25, mid: 100, high: 500 };
      const entryFee = entryFeeMap[bucket] || 0;

      // Check how long oldest player has been waiting
      const oldest = await redis.client.zrange(key, 0, 0, 'WITHSCORES');
      if (oldest && oldest.length >= 2) {
        const waitMs = Date.now() - parseInt(oldest[1]);
        if (count >= 2 && waitMs >= TABLE_START_DELAY_MS) {
          await _tryCreateTable(key, gameType, entryFee, Math.min(count, 6), 2);
        }
      }
    }
  } catch (err) {
    logger.error({ event: 'queue_processor_error', error: err.message });
  }
}, 5000);

app.use(errorHandler);

app.listen(PORT, () => logger.info(`Matchmaking Service running on port ${PORT}`));
module.exports = { app };
