const { v4: uuidv4 } = require('uuid');
const crypto = require('crypto');
const DeckManager = require('./DeckManager');
const RummyValidator = require('./RummyValidator');
const ScoreCalculator = require('./ScoreCalculator');
const logger = require('../../../../libs/utils/logger');

const ENCRYPTION_KEY = process.env.GAME_HAND_ENCRYPTION_KEY;

class GameEngine {
  constructor(db, redis, io) {
    this.db = db;
    this.redis = redis;
    this.io = io;
    this.validator = new RummyValidator();
    this.scorer = new ScoreCalculator();
  }

  // ── Join Table ─────────────────────────────────────────────────────────────
  async joinTable(userId, tableId) {
    const tableResult = await this.db.query(
      'SELECT * FROM game_tables WHERE id = $1',
      [tableId]
    );
    if (!tableResult.rows.length) {
      const err = new Error('Table not found'); err.code = 'GAME_002'; throw err;
    }

    const table = tableResult.rows[0];

    if (table.status === 'in_progress') {
      // Check if this is a rejoin
      const existing = await this.db.query(`
        SELECT mp.seat_position FROM match_players mp
        JOIN matches m ON m.id = mp.match_id
        WHERE m.table_id = $1 AND mp.user_id = $2 AND m.status = 'in_progress'
      `, [tableId, userId]);

      if (existing.rows.length) {
        return { is_rejoin: true, seat: existing.rows[0].seat_position };
      }
      const err = new Error('Game already started'); err.code = 'GAME_003'; throw err;
    }

    // Check wallet balance
    if (table.entry_fee > 0) {
      const wallet = await this.db.query(
        'SELECT balance_cash + balance_bonus AS total FROM wallets WHERE user_id = $1',
        [userId]
      );
      if (!wallet.rows.length || parseFloat(wallet.rows[0].total) < table.entry_fee) {
        const err = new Error('Insufficient balance'); err.code = 'WALLET_001'; throw err;
      }
    }

    // Get current players
    const playersResult = await this.db.query(`
      SELECT user_id, seat_position FROM table_seats
      WHERE table_id = $1
    `, [tableId]);

    const takenSeats = playersResult.rows.map(r => r.seat_position);
    const availableSeats = Array.from({ length: table.max_players }, (_, i) => i + 1)
      .filter(s => !takenSeats.includes(s));

    if (!availableSeats.length) {
      const err = new Error('Table is full'); err.code = 'GAME_001'; throw err;
    }

    const seat = availableSeats[0];

    // Deduct entry fee
    if (table.entry_fee > 0) {
      await this._deductEntryFee(userId, table.id, table.entry_fee);
    }

    // Assign seat
    await this.db.query(`
      INSERT INTO table_seats (id, table_id, user_id, seat_position)
      VALUES ($1, $2, $3, $4)
      ON CONFLICT (table_id, seat_position) DO NOTHING
    `, [uuidv4(), tableId, userId, seat]);

    const totalPlayers = playersResult.rows.length + 1;
    const can_start = totalPlayers >= table.min_players;

    if (can_start && totalPlayers === table.max_players) {
      // Immediately start if table is full
    }

    return { seat, can_start };
  }

  // ── Start Game ─────────────────────────────────────────────────────────────
  async startGame(tableId) {
    const table = await this.db.query('SELECT * FROM game_tables WHERE id = $1', [tableId]);
    const tableData = table.rows[0];

    const seatsResult = await this.db.query(
      'SELECT user_id, seat_position FROM table_seats WHERE table_id = $1 ORDER BY seat_position',
      [tableId]
    );
    const players = seatsResult.rows;

    if (players.length < tableData.min_players) {
      throw new Error('Not enough players to start');
    }

    // Deal cards
    const deck = new DeckManager(2);
    deck.shuffle();
    const { hands, remaining } = deck.deal(players.length, 13);
    const wildJoker = deck.selectWildJoker(remaining);

    // Create match record
    const matchId = uuidv4();
    await this.db.query(`
      INSERT INTO matches (id, table_id, status, started_at)
      VALUES ($1, $2, 'in_progress', NOW())
    `, [matchId, tableId]);

    // Update table status
    await this.db.query(
      'UPDATE game_tables SET status = $1, started_at = NOW() WHERE id = $2',
      ['in_progress', tableId]
    );

    // Create match_players records
    for (let i = 0; i < players.length; i++) {
      await this.db.query(`
        INSERT INTO match_players (id, match_id, user_id, seat_position, status)
        VALUES ($1, $2, $3, $4, 'playing')
      `, [uuidv4(), matchId, players[i].user_id, players[i].seat_position]);
    }

    // Store game state in Redis
    const gameState = {
      match_id: matchId,
      table_id: tableId,
      game_type: tableData.game_type,
      status: 'in_progress',
      players: players.map((p, i) => ({
        user_id: p.user_id,
        seat: p.seat_position,
        hand_size: 13,
        status: 'playing',
        points: 0,
      })),
      open_pile: [remaining[0]],
      closed_pile_count: remaining.length - 1,
      wild_joker: wildJoker,
      current_turn_index: 0,
      turn_number: 1,
    };

    await this.redis.setex(`game:state:${tableId}`, 3600, JSON.stringify(gameState));
    await this.redis.setex(`game:closed_pile:${tableId}`, 3600, JSON.stringify(remaining.slice(1)));

    // Store each player's hand (encrypted)
    for (let i = 0; i < players.length; i++) {
      const encryptedHand = this._encryptHand(hands[i], tableId);
      await this.redis.setex(
        `game:hand:${tableId}:${players[i].user_id}`,
        3600,
        encryptedHand
      );
    }

    return {
      match_id: matchId,
      players: players.map((p, i) => ({
        user_id: p.user_id,
        hand: hands[i],
      })),
      open_pile_top: remaining[0],
      wild_joker: wildJoker,
      first_player_id: players[0].user_id,
    };
  }

  // ── Draw Card ──────────────────────────────────────────────────────────────
  async drawCard(userId, tableId, source) {
    const state = await this._getState(tableId);
    this._validateTurn(state, userId);

    const encryptedHand = await this.redis.get(`game:hand:${tableId}:${userId}`);
    const hand = this._decryptHand(encryptedHand, tableId);

    let drawnCard;

    if (source === 'open') {
      if (!state.open_pile.length) throw new Error('Open pile is empty');
      drawnCard = state.open_pile.pop();
    } else {
      const closedPileRaw = await this.redis.get(`game:closed_pile:${tableId}`);
      const closedPile = JSON.parse(closedPileRaw);
      if (!closedPile.length) throw new Error('Deck is exhausted');
      drawnCard = closedPile.shift();
      await this.redis.setex(`game:closed_pile:${tableId}`, 3600, JSON.stringify(closedPile));
    }

    hand.push(drawnCard);
    state.closed_pile_count = source === 'open' ? state.closed_pile_count : state.closed_pile_count - 1;

    // Update state
    await this.redis.setex(`game:state:${tableId}`, 3600, JSON.stringify(state));
    await this.redis.setex(
      `game:hand:${tableId}:${userId}`,
      3600,
      this._encryptHand(hand, tableId)
    );

    // Log round
    await this.db.query(`
      INSERT INTO game_rounds (id, match_id, round_number, current_player, action, card_drawn, timestamp)
      VALUES ($1, $2, $3, $4, $5, $6, NOW())
    `, [uuidv4(), state.match_id, state.turn_number, userId, `draw_${source}`, source === 'closed' ? null : drawnCard]);

    return { drawn_card: drawnCard, open_pile_top: state.open_pile[state.open_pile.length - 1] || null };
  }

  // ── Discard Card ───────────────────────────────────────────────────────────
  async discardCard(userId, tableId, card) {
    const state = await this._getState(tableId);
    this._validateTurn(state, userId);

    const encryptedHand = await this.redis.get(`game:hand:${tableId}:${userId}`);
    const hand = this._decryptHand(encryptedHand, tableId);

    // Anti-cheat: player must hold the card
    if (!hand.includes(card)) {
      const err = new Error('Invalid card - not in hand'); err.code = 'GAME_005'; throw err;
    }

    // Remove from hand
    hand.splice(hand.indexOf(card), 1);
    state.open_pile.push(card);
    // Keep open pile to max 20 (remove oldest)
    if (state.open_pile.length > 20) state.open_pile.shift();

    // Advance turn
    const currentIdx = state.current_turn_index;
    const activePlayers = state.players.filter(p => p.status === 'playing');
    const nextPlayer = activePlayers[(activePlayers.indexOf(activePlayers.find(p =>
      p.user_id === userId)) + 1) % activePlayers.length];

    state.current_turn_index = state.players.indexOf(nextPlayer);
    state.turn_number += 1;

    await this.redis.setex(`game:state:${tableId}`, 3600, JSON.stringify(state));
    await this.redis.setex(
      `game:hand:${tableId}:${userId}`,
      3600,
      this._encryptHand(hand, tableId)
    );

    await this.db.query(`
      INSERT INTO game_rounds (id, match_id, round_number, current_player, action, card_discarded, timestamp)
      VALUES ($1, $2, $3, $4, 'discard', $5, NOW())
    `, [uuidv4(), state.match_id, state.turn_number, userId, card]);

    return { open_pile_top: card, next_player_id: nextPlayer.user_id };
  }

  // ── Declare ────────────────────────────────────────────────────────────────
  async declare(userId, tableId, declaredHand) {
    const state = await this._getState(tableId);
    this._validateTurn(state, userId);

    const encryptedHand = await this.redis.get(`game:hand:${tableId}:${userId}`);
    const actualHand = this._decryptHand(encryptedHand, tableId);

    // Anti-cheat: verify declared cards match actual hand
    const declaredCards = [
      ...declaredHand.sets.flat(),
      ...declaredHand.sequences.flat(),
      ...(declaredHand.unmatched || []),
    ];

    const handCopy = [...actualHand];
    for (const card of declaredCards) {
      const idx = handCopy.indexOf(card);
      if (idx === -1) {
        return { is_valid: false, reason: 'Declared cards do not match hand' };
      }
      handCopy.splice(idx, 1);
    }

    // Validate the declaration
    const validation = this.validator.validate(declaredHand, state.wild_joker);

    if (!validation.isValid) {
      // 80-point penalty for invalid declaration
      await this._applyPenalty(userId, tableId, state, 80);
      return { is_valid: false, reason: validation.reason };
    }

    // Calculate scores for all players
    const scores = {};
    for (const player of state.players) {
      if (player.user_id === userId) {
        scores[player.user_id] = 0;
        continue;
      }
      const pHand = this._decryptHand(
        await this.redis.get(`game:hand:${tableId}:${player.user_id}`),
        tableId
      );
      scores[player.user_id] = this.scorer.calculateDeadwood(pHand, state.wild_joker);
    }

    // Build game over payload
    const prizePool = await this._getPrizePool(tableId);
    const rake = prizePool * 0.10;
    const netPrize = prizePool - rake;

    const gameOverPayload = {
      match_id: state.match_id,
      winner_id: userId,
      reason: 'declaration',
      prize_pool: prizePool,
      net_prize: netPrize,
      players: state.players.map(p => ({
        user_id: p.user_id,
        points: scores[p.user_id],
        is_winner: p.user_id === userId,
        final_hand: p.user_id === userId ? actualHand : null,
      })),
    };

    // Update match in DB
    await this.db.query(`
      UPDATE matches SET status = 'completed', winner_id = $1, ended_at = NOW(),
      winning_hand = $2, total_points = $3
      WHERE id = $4
    `, [userId, JSON.stringify(declaredHand), Object.values(scores).reduce((a, b) => a + b, 0), state.match_id]);

    state.status = 'completed';
    await this.redis.setex(`game:state:${tableId}`, 300, JSON.stringify(state));

    return { is_valid: true, gameOverPayload, scores, winner_id: userId, prize: netPrize };
  }

  // ── Create Private Table ───────────────────────────────────────────────────
  async createPrivateTable(userId, options = {}) {
    const { game_type = 'points', max_players = 6, entry_fee = 0 } = options;
    const { generateTableCode } = require('../../../../libs/utils/helpers');
    const tableId = require('uuid').v4();
    const tableCode = generateTableCode();

    await this.db.query(`
      INSERT INTO game_tables (id, game_type, max_players, min_players, entry_fee, status, is_private, table_code)
      VALUES ($1, $2, $3, 2, $4, 'waiting', true, $5)
    `, [tableId, game_type, max_players, entry_fee, tableCode]);

    return { table_id: tableId, table_code: tableCode, game_type, max_players, entry_fee };
  }

  // ── Drop Game ──────────────────────────────────────────────────────────────
  async dropGame(userId, tableId) {
    const state = await this._getState(tableId);
    const player = state.players.find(p => p.user_id === userId);

    // First drop = 20 points, mid-game drop = 40 points
    const isFirstTurn = state.turn_number <= state.players.length;
    const penalty = isFirstTurn ? 20 : 40;

    player.status = 'dropped';
    player.points = penalty;

    const activePlayers = state.players.filter(p => p.status === 'playing');

    if (activePlayers.length === 1) {
      // Only one player left — they win
      const winner = activePlayers[0];
      return await this._endGameWithWinner(tableId, state, winner.user_id, 'all_dropped');
    }

    // Advance turn if it was this player's turn
    const nextPlayer = activePlayers[0];
    state.current_turn_index = state.players.indexOf(nextPlayer);

    await this.redis.setex(`game:state:${tableId}`, 3600, JSON.stringify(state));

    return { penalty, next_player_id: nextPlayer.user_id, game_over: false };
  }

  // ── Distribute Winnings ────────────────────────────────────────────────────
  async distributeWinnings(tableId, result) {
    const client = await this.db.connect();
    try {
      await client.query('BEGIN');

      const { winner_id, prize } = result;

      // Get wallet snapshot
      const wallet = await client.query(
        'SELECT balance_cash FROM wallets WHERE user_id = $1 FOR UPDATE',
        [winner_id]
      );

      const balanceBefore = parseFloat(wallet.rows[0]?.balance_cash || 0);

      // Credit winner
      await client.query(`
        UPDATE wallets SET balance_cash = balance_cash + $1, total_won = total_won + $1
        WHERE user_id = $2
      `, [prize, winner_id]);

      // Record transaction
      await client.query(`
        INSERT INTO transactions (id, user_id, type, amount, currency_type, balance_before, balance_after, reference_id, reference_type)
        VALUES ($1, $2, 'game_win', $3, 'cash', $4, $5, $6, 'game')
      `, [uuidv4(), winner_id, prize, balanceBefore, balanceBefore + prize, result.gameOverPayload.match_id]);

      await client.query('COMMIT');

      // Update user stats
      await this.db.query(`
        UPDATE user_profiles SET wins = wins + 1, total_games = total_games + 1
        WHERE user_id = $1
      `, [winner_id]);

      logger.info(`Prize ₹${prize} distributed to ${winner_id}`);
    } catch (err) {
      await client.query('ROLLBACK');
      logger.error(`Prize distribution failed: ${err.message}`);
    } finally {
      client.release();
    }
  }

  // ── Get Player View (safe state for client) ────────────────────────────────
  async getPlayerView(tableId, userId) {
    const stateRaw = await this.redis.get(`game:state:${tableId}`);
    if (!stateRaw) {
      // Load from DB
      return await this._loadStateFromDb(tableId);
    }

    const state = JSON.parse(stateRaw);
    let yourHand = null;

    if (state.status === 'in_progress') {
      const encryptedHand = await this.redis.get(`game:hand:${tableId}:${userId}`);
      if (encryptedHand) yourHand = this._decryptHand(encryptedHand, tableId);
    }

    return {
      ...state,
      closed_pile: undefined, // Don't expose server pile
      your_hand: yourHand,
    };
  }

  async getPlayerHand(tableId, userId) {
    const raw = await this.redis.get(`game:hand:${tableId}:${userId}`);
    if (!raw) return null;
    return this._decryptHand(raw, tableId);
  }

  async getTablePlayers(tableId) {
    const result = await this.db.query(
      'SELECT user_id, seat_position FROM table_seats WHERE table_id = $1',
      [tableId]
    );
    return result.rows;
  }

  // ── Private Helpers ────────────────────────────────────────────────────────
  _validateTurn(state, userId) {
    const currentPlayer = state.players[state.current_turn_index];
    if (!currentPlayer || currentPlayer.user_id !== userId) {
      const err = new Error('Not your turn'); err.code = 'GAME_004'; throw err;
    }
  }

  async _getState(tableId) {
    const raw = await this.redis.get(`game:state:${tableId}`);
    if (!raw) throw new Error('Game state not found');
    return JSON.parse(raw);
  }

  _encryptHand(hand, tableId) {
    const key = crypto.createHash('sha256').update(`${ENCRYPTION_KEY}:${tableId}`).digest();
    const iv = crypto.randomBytes(16);
    const cipher = crypto.createCipheriv('aes-256-cbc', key, iv);
    let encrypted = cipher.update(JSON.stringify(hand), 'utf8', 'hex');
    encrypted += cipher.final('hex');
    return `${iv.toString('hex')}:${encrypted}`;
  }

  _decryptHand(encryptedData, tableId) {
    if (!encryptedData) return [];
    const [ivHex, encrypted] = encryptedData.split(':');
    const key = crypto.createHash('sha256').update(`${ENCRYPTION_KEY}:${tableId}`).digest();
    const iv = Buffer.from(ivHex, 'hex');
    const decipher = crypto.createDecipheriv('aes-256-cbc', key, iv);
    let decrypted = decipher.update(encrypted, 'hex', 'utf8');
    decrypted += decipher.final('utf8');
    return JSON.parse(decrypted);
  }

  async _deductEntryFee(userId, tableId, amount) {
    const client = await this.db.connect();
    try {
      await client.query('BEGIN');
      const wallet = await client.query(
        'SELECT id, balance_cash, balance_bonus FROM wallets WHERE user_id = $1 FOR UPDATE',
        [userId]
      );
      const w = wallet.rows[0];
      const total = parseFloat(w.balance_cash) + parseFloat(w.balance_bonus);
      if (total < amount) throw new Error('Insufficient balance');

      const bonusDed = Math.min(parseFloat(w.balance_bonus), amount);
      const cashDed = amount - bonusDed;

      await client.query(`
        UPDATE wallets SET balance_cash = balance_cash - $1, balance_bonus = balance_bonus - $2
        WHERE user_id = $3
      `, [cashDed, bonusDed, userId]);

      await client.query(`
        INSERT INTO transactions (id, user_id, type, amount, currency_type, balance_before, balance_after, reference_id, reference_type)
        VALUES ($1, $2, 'game_entry', $3, 'mixed', $4, $5, $6, 'game')
      `, [uuidv4(), userId, -amount, w.balance_cash, parseFloat(w.balance_cash) - cashDed, tableId]);

      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  async _getPrizePool(tableId) {
    const result = await this.db.query(
      'SELECT entry_fee, max_players FROM game_tables WHERE id = $1',
      [tableId]
    );
    const t = result.rows[0];
    return parseFloat(t.entry_fee) * t.max_players;
  }
}

module.exports = GameEngine;
