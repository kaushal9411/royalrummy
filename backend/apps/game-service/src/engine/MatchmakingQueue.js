const { v4: uuidv4 } = require('uuid');
const logger = require('../../../../libs/utils/logger');

const BOT_FILL_DELAY_MS = 30_000; // Fill with bots after 30 seconds

/**
 * In-process matchmaking queue.
 * Groups players by (game_type + entry_fee bucket) and creates tables
 * when min player count is reached or after a timeout.
 */
class MatchmakingQueue {
  constructor(db, redis, io, gameEngine, botManager) {
    this.db = db;
    this.redis = redis;
    this.io = io;
    this.gameEngine = gameEngine;
    this.botManager = botManager;
    // Map of queueKey → { players: [...], timer, minPlayers, maxPlayers, entryFee, gameType }
    this._queues = new Map();
  }

  /**
   * Add a player to the matchmaking queue.
   * Returns { queue_key, position, estimated_wait_ms }
   */
  async joinQueue(userId, username, gameType, entryFee, options = {}) {
    const key = this._queueKey(gameType, entryFee);
    const maxPlayers = options.maxPlayers || 6;
    const minPlayers = options.minPlayers || 2;

    if (!this._queues.has(key)) {
      this._queues.set(key, {
        players: [], minPlayers, maxPlayers,
        entryFee, gameType, timer: null,
      });
    }

    const queue = this._queues.get(key);

    // Prevent duplicate joins
    if (queue.players.some(p => p.userId === userId)) {
      return { queue_key: key, position: queue.players.findIndex(p => p.userId === userId) + 1 };
    }

    queue.players.push({ userId, username, joinedAt: Date.now() });
    const position = queue.players.length;

    logger.info({ event: 'queue_joined', userId, key, position });

    // Store in Redis so other nodes know this user is queued
    await this.redis.setex(`queue:player:${userId}`, 120, key);

    if (position >= maxPlayers) {
      // Table is full — start immediately
      await this._createTableAndStart(key, queue, maxPlayers);
    } else if (position >= minPlayers && !queue.timer) {
      // Enough players — set a short wait for more to join
      queue.timer = setTimeout(async () => {
        await this._createTableAndStart(key, queue, queue.players.length);
      }, 5000);
    } else if (position === 1) {
      // First player — start bot-fill countdown
      queue.timer = setTimeout(async () => {
        if (queue.players.length < minPlayers) {
          // Not enough players even for minimum — fill with bots
          await this._fillWithBotsAndStart(key, queue);
        } else {
          await this._createTableAndStart(key, queue, queue.players.length);
        }
      }, BOT_FILL_DELAY_MS);
    }

    return { queue_key: key, position, estimated_wait_ms: BOT_FILL_DELAY_MS };
  }

  /**
   * Remove a player from the queue.
   */
  async leaveQueue(userId) {
    const key = await this.redis.get(`queue:player:${userId}`);
    if (!key || !this._queues.has(key)) return false;

    const queue = this._queues.get(key);
    queue.players = queue.players.filter(p => p.userId !== userId);
    await this.redis.del(`queue:player:${userId}`);

    if (queue.players.length === 0) {
      clearTimeout(queue.timer);
      this._queues.delete(key);
    }

    return true;
  }

  /**
   * Get current queue status for a player.
   */
  async getStatus(userId) {
    const key = await this.redis.get(`queue:player:${userId}`);
    if (!key || !this._queues.has(key)) return { in_queue: false };

    const queue = this._queues.get(key);
    const position = queue.players.findIndex(p => p.userId === userId) + 1;
    return {
      in_queue: true,
      queue_key: key,
      position,
      players_waiting: queue.players.length,
      min_players: queue.minPlayers,
    };
  }

  // ─── Private ────────────────────────────────────────────────────────────────

  async _createTableAndStart(key, queue, playerCount) {
    clearTimeout(queue.timer);
    const players = queue.players.splice(0, playerCount);

    if (queue.players.length === 0) {
      this._queues.delete(key);
    }

    logger.info({ event: 'table_creating', key, playerCount });

    try {
      // Create table in DB
      const tableId = uuidv4();
      await this.db.query(`
        INSERT INTO game_tables (id, game_type, max_players, min_players, entry_fee, status, is_private)
        VALUES ($1, $2, $3, $4, $5, 'waiting', false)
      `, [tableId, queue.gameType, playerCount, queue.minPlayers, queue.entryFee]);

      // Seat all players
      for (let i = 0; i < players.length; i++) {
        await this.db.query(`
          INSERT INTO table_seats (id, table_id, user_id, seat_position)
          VALUES ($1, $2, $3, $4)
        `, [uuidv4(), tableId, players[i].userId, i + 1]);
        await this.redis.del(`queue:player:${players[i].userId}`);
      }

      // Notify all players of their table assignment
      for (const player of players) {
        this.io.of('/game').to(`user:${player.userId}`).emit('match_found', {
          table_id: tableId,
          game_type: queue.gameType,
          entry_fee: queue.entryFee,
          players: players.map(p => ({ user_id: p.userId, username: p.username })),
        });
      }

      logger.info({ event: 'match_found', tableId, players: players.length });
      return tableId;
    } catch (err) {
      logger.error({ event: 'table_create_failed', key, error: err.message });
    }
  }

  async _fillWithBotsAndStart(key, queue) {
    const needed = queue.minPlayers - queue.players.length;
    if (this.botManager) {
      const bots = await this.botManager.createBots(needed, 'beginner');
      for (const bot of bots) {
        queue.players.push({ userId: bot.id, username: bot.name, isBot: true });
      }
    }
    if (queue.players.length >= queue.minPlayers) {
      await this._createTableAndStart(key, queue, queue.players.length);
    } else {
      this._queues.delete(key);
    }
  }

  _queueKey(gameType, entryFee) {
    // Bucket entry fees to avoid excessive fragmentation
    const bucket = entryFee <= 10 ? 'micro'
      : entryFee <= 50 ? 'low'
      : entryFee <= 200 ? 'mid'
      : 'high';
    return `${gameType}:${bucket}`;
  }
}

module.exports = MatchmakingQueue;
