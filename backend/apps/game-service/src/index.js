require('dotenv').config({ path: '../../../.env' });
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const { createAdapter } = require('@socket.io/redis-adapter');
const { createClient } = require('redis');
const jwt = require('jsonwebtoken');
const db = require('../../../libs/database/db');
const redis = require('../../../libs/cache/redis');
const logger = require('../../../libs/utils/logger');
const { sendResponse, sendError } = require('../../../libs/utils/response');
const GameEngine = require('./engine/GameEngine');
const MatchmakingQueue = require('./engine/MatchmakingQueue');
const TurnTimerService = require('./engine/TurnTimerService');
const BotManager = require('./engine/BotManager');

const app = express();
const server = http.createServer(app);
const PORT = process.env.GAME_SERVICE_PORT || 3002;

app.use(express.json());

// Socket.IO with Redis Adapter for multi-node scaling
const io = new Server(server, {
  cors: {
    origin: process.env.ALLOWED_ORIGINS?.split(',') || '*',
    credentials: true,
  },
  transports: ['websocket', 'polling'],
  pingInterval: 25000,
  pingTimeout: 60000,
});

// Redis Pub/Sub for multi-node Socket.IO
(async () => {
  const pubClient = createClient({ url: process.env.REDIS_URL });
  const subClient = pubClient.duplicate();
  await Promise.all([pubClient.connect(), subClient.connect()]);
  io.adapter(createAdapter(pubClient, subClient));
  logger.info('Redis Socket.IO adapter initialized');
})();

// Services
const gameEngine = new GameEngine(db, redis, io);
const turnTimer = new TurnTimerService(io, gameEngine, redis);
const botManager = new BotManager(io, gameEngine, redis);

// =============================================================================
// REST Endpoints
// =============================================================================

app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'game-service',
    ws_connections: io.engine.clientsCount,
  });
});

// Get available tables
app.get('/v1/games/tables', require('../../../libs/middleware/auth.middleware').authenticateJWT, async (req, res) => {
  const { type, variant, min_fee, max_fee, page = 1, limit = 20 } = req.query;

  let query = `
    SELECT gt.*,
           COUNT(mp.id) FILTER (WHERE mp.status = 'playing') as current_players
    FROM game_tables gt
    LEFT JOIN matches m ON m.table_id = gt.id AND m.status = 'in_progress'
    LEFT JOIN match_players mp ON mp.match_id = m.id
    WHERE gt.status IN ('waiting', 'in_progress')
  `;
  const params = [];

  if (type) { params.push(type); query += ` AND gt.game_type = $${params.length}`; }
  if (variant) { params.push(variant); query += ` AND gt.variant = $${params.length}`; }
  if (min_fee) { params.push(min_fee); query += ` AND gt.entry_fee >= $${params.length}`; }
  if (max_fee) { params.push(max_fee); query += ` AND gt.entry_fee <= $${params.length}`; }

  query += ` GROUP BY gt.id ORDER BY gt.created_at DESC`;
  query += ` LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
  params.push(limit, (page - 1) * limit);

  const result = await db.query(query, params);
  sendResponse(res, 200, result.rows, { page, limit, total: result.rowCount });
});

// Create private table
app.post('/v1/games/tables', require('../../../libs/middleware/auth.middleware').authenticateJWT, async (req, res) => {
  const { game_type, max_players, entry_fee } = req.body;
  const userId = req.user.id;

  try {
    const table = await gameEngine.createPrivateTable(userId, {
      game_type,
      max_players: parseInt(max_players),
      entry_fee: parseFloat(entry_fee),
      is_private: true,
    });
    sendResponse(res, 201, table);
  } catch (err) {
    sendError(res, 400, 'GAME_001', err.message);
  }
});

// Get match history
app.get('/v1/games/history', require('../../../libs/middleware/auth.middleware').authenticateJWT, async (req, res) => {
  const { page = 1, limit = 20 } = req.query;

  const result = await db.query(`
    SELECT m.id, m.started_at, m.ended_at, m.duration_secs,
           gt.game_type, gt.entry_fee,
           mp.final_points, mp.prize_won, mp.rank,
           mp.status as player_status,
           (m.winner_id = $1) as is_winner
    FROM match_players mp
    JOIN matches m ON m.id = mp.match_id
    JOIN game_tables gt ON gt.id = m.table_id
    WHERE mp.user_id = $1
    ORDER BY m.started_at DESC
    LIMIT $2 OFFSET $3
  `, [req.user.id, limit, (page - 1) * limit]);

  sendResponse(res, 200, result.rows);
});

// =============================================================================
// WebSocket /game Namespace
// =============================================================================

const gameNs = io.of('/game');

gameNs.use(async (socket, next) => {
  try {
    const token = socket.handshake.auth.token?.replace('Bearer ', '');
    if (!token) return next(new Error('AUTH_MISSING_TOKEN'));

    const payload = jwt.verify(token, process.env.JWT_SECRET);

    // Check user is active
    const user = await db.query(
      'SELECT id, username, status FROM users WHERE id = $1',
      [payload.sub]
    );

    if (!user.rows.length || user.rows[0].status !== 'active') {
      return next(new Error('AUTH_USER_INACTIVE'));
    }

    socket.data.userId = payload.sub;
    socket.data.username = user.rows[0].username;
    socket.data.deviceId = socket.handshake.auth.device_id;

    // Mark online
    await redis.setex(`user:online:${payload.sub}`, 300, '1');
    next();
  } catch (err) {
    next(new Error('AUTH_INVALID_TOKEN'));
  }
});

gameNs.on('connection', async (socket) => {
  const userId = socket.data.userId;
  logger.info(`[WS] User connected: ${userId}`);

  // Join personal room
  socket.join(`user:${userId}`);

  // ── join_table ──────────────────────────────────────────────────────────────
  socket.on('join_table', async ({ table_id }) => {
    try {
      const state = await gameEngine.joinTable(userId, table_id);

      socket.join(`table:${table_id}`);
      await redis.setex(`player:table:${userId}`, 3600, table_id);

      // Send full state to this player (includes their hand if game in progress)
      socket.emit('table_state', await gameEngine.getPlayerView(table_id, userId));

      // Broadcast to room
      socket.to(`table:${table_id}`).emit('player_joined', {
        user_id: userId,
        username: socket.data.username,
        seat: state.seat,
      });

      // Check if table is ready to start
      if (state.can_start) {
        await startGame(table_id);
      }
    } catch (err) {
      socket.emit('error', { code: err.code || 'GAME_001', message: err.message });
    }
  });

  // ── draw_card ──────────────────────────────────────────────────────────────
  socket.on('draw_card', async ({ table_id, source }) => {
    try {
      const result = await gameEngine.drawCard(userId, table_id, source);
      turnTimer.cancelTimer(table_id, userId);

      // Tell this player the card they drew
      socket.emit('card_drawn', {
        source,
        your_new_card: result.drawn_card,
        open_pile_top: result.open_pile_top,
        valid_actions: ['discard_card'],
      });

      // Tell others a draw happened (hide card value)
      socket.to(`table:${table_id}`).emit('card_drawn', {
        user_id: userId,
        source,
        open_pile_top: result.open_pile_top,
      });

      // Start discard timer
      turnTimer.startTimer(table_id, userId, 30, 'discard_card');
    } catch (err) {
      socket.emit('error', { code: err.code || 'GAME_004', message: err.message });
    }
  });

  // ── discard_card ───────────────────────────────────────────────────────────
  socket.on('discard_card', async ({ table_id, card }) => {
    try {
      const result = await gameEngine.discardCard(userId, table_id, card);
      turnTimer.cancelTimer(table_id, userId);

      gameNs.to(`table:${table_id}`).emit('card_discarded', {
        user_id: userId,
        card,
        open_pile_top: result.open_pile_top,
        next_player_id: result.next_player_id,
      });

      // Start next player's draw timer
      turnTimer.startTimer(table_id, result.next_player_id, 30, 'draw_card');

      gameNs.to(`user:${result.next_player_id}`).emit('your_turn', {
        time_limit: 30,
        valid_actions: ['draw_card'],
        open_pile_top: result.open_pile_top,
      });
    } catch (err) {
      socket.emit('error', { code: err.code || 'GAME_005', message: err.message });
    }
  });

  // ── declare ────────────────────────────────────────────────────────────────
  socket.on('declare', async ({ table_id, hand }) => {
    try {
      const result = await gameEngine.declare(userId, table_id, hand);
      turnTimer.cancelAllTimers(table_id);

      if (result.is_valid) {
        gameNs.to(`table:${table_id}`).emit('game_over', result.gameOverPayload);
        // Distribute prizes asynchronously
        gameEngine.distributeWinnings(table_id, result).catch(err =>
          logger.error(`Prize distribution error: ${err.message}`)
        );
      } else {
        gameNs.to(`table:${table_id}`).emit('invalid_declaration', {
          user_id: userId,
          penalty: 80,
          reason: result.reason,
        });
        // Continue game, player continues with 80-point penalty
      }
    } catch (err) {
      socket.emit('error', { code: err.code || 'GAME_005', message: err.message });
    }
  });

  // ── drop_game ──────────────────────────────────────────────────────────────
  socket.on('drop_game', async ({ table_id }) => {
    try {
      const result = await gameEngine.dropGame(userId, table_id);
      turnTimer.cancelTimer(table_id, userId);

      gameNs.to(`table:${table_id}`).emit('player_dropped', {
        user_id: userId,
        penalty_points: result.penalty,
        next_player_id: result.next_player_id,
      });

      if (result.game_over) {
        gameNs.to(`table:${table_id}`).emit('game_over', result.gameOverPayload);
        gameEngine.distributeWinnings(table_id, result);
      }
    } catch (err) {
      socket.emit('error', { message: err.message });
    }
  });

  // ── send_message (chat) ────────────────────────────────────────────────────
  socket.on('send_message', async ({ room_id, message, type = 'text' }) => {
    // Sanitize message
    const sanitized = message.trim().substring(0, 200);

    gameNs.to(room_id).emit('new_message', {
      sender_id: userId,
      sender_username: socket.data.username,
      message: sanitized,
      type,
      timestamp: Date.now(),
    });

    // Persist chat to DB async
    db.query(
      'INSERT INTO chat_messages (id, room_id, sender_id, message, message_type) VALUES ($1, $2, $3, $4, $5)',
      [require('uuid').v4(), room_id, userId, sanitized, type]
    ).catch(() => {});
  });

  // ── ping ────────────────────────────────────────────────────────────────────
  socket.on('ping', async () => {
    await redis.setex(`user:online:${userId}`, 300, '1');
    socket.emit('pong', { server_time: Date.now() });
  });

  // ── disconnect ──────────────────────────────────────────────────────────────
  socket.on('disconnect', async () => {
    logger.info(`[WS] User disconnected: ${userId}`);
    await redis.del(`user:online:${userId}`);

    const activeTable = await redis.get(`player:table:${userId}`);
    if (activeTable) {
      socket.to(`table:${activeTable}`).emit('player_disconnected', {
        user_id: userId,
        reconnect_timeout: 60,
      });
    }
  });
});

// =============================================================================
// Helper: Start game after all players join
// =============================================================================
async function startGame(tableId) {
  gameNs.to(`table:${tableId}`).emit('game_starting', { countdown: 3 });

  setTimeout(async () => {
    try {
      const gameData = await gameEngine.startGame(tableId);

      // Send personalized start payload to each player
      for (const player of gameData.players) {
        const hand = await gameEngine.getPlayerHand(tableId, player.user_id);
        gameNs.to(`user:${player.user_id}`).emit('game_started', {
          match_id: gameData.match_id,
          your_hand: hand,
          open_pile_top: gameData.open_pile_top,
          wild_joker: gameData.wild_joker,
          first_turn_user_id: gameData.first_player_id,
          turn_time_limit: 30,
        });
      }

      // Start first player's timer
      turnTimer.startTimer(tableId, gameData.first_player_id, 30, 'draw_card');
      gameNs.to(`user:${gameData.first_player_id}`).emit('your_turn', {
        time_limit: 30,
        valid_actions: ['draw_card'],
        open_pile_top: gameData.open_pile_top,
      });
    } catch (err) {
      logger.error(`Start game error for table ${tableId}: ${err.message}`);
    }
  }, 3000);
}

server.listen(PORT, () => logger.info(`Game Service running on port ${PORT}`));
module.exports = { app, io };
