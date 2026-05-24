const logger = require('../../../../libs/utils/logger');

const COUNTDOWN_INTERVAL_MS = 1000;
const WARN_THRESHOLD_SECS = 10; // Emit warning when <= 10 seconds remain

/**
 * Manages per-player turn timers for the game.
 * On timeout: auto-executes the expected action (draw→auto-discard highest, or auto-drop).
 */
class TurnTimerService {
  constructor(io, gameEngine, redis) {
    this.io = io;
    this.gameEngine = gameEngine;
    this.redis = redis;
    // Map of timerKey → { timeout, interval, remaining }
    this._timers = new Map();
  }

  /**
   * Start a countdown timer for a player's turn.
   * @param {string} tableId
   * @param {string} userId
   * @param {number} seconds - Total time allowed
   * @param {string} expectedAction - 'draw_card' | 'discard_card'
   */
  startTimer(tableId, userId, seconds, expectedAction) {
    const key = this._key(tableId, userId);
    this.cancelTimer(tableId, userId); // Cancel any existing timer

    let remaining = seconds;

    // Broadcast countdown ticks
    const interval = setInterval(() => {
      remaining -= 1;

      if (remaining <= WARN_THRESHOLD_SECS) {
        this.io.of('/game').to(`table:${tableId}`).emit('turn_countdown', {
          user_id: userId,
          seconds_left: remaining,
        });
      }

      if (remaining <= 0) clearInterval(interval);
    }, COUNTDOWN_INTERVAL_MS);

    // Auto-action on timeout
    const timeout = setTimeout(async () => {
      clearInterval(interval);
      this._timers.delete(key);

      logger.info({ tableId, userId, expectedAction, event: 'turn_timeout' });

      try {
        if (expectedAction === 'draw_card') {
          // Auto-draw from closed pile then auto-discard highest card
          await this._autoDrawAndDiscard(tableId, userId);
        } else if (expectedAction === 'discard_card') {
          // Auto-discard highest-value card in hand
          await this._autoDiscard(tableId, userId);
        }
      } catch (err) {
        logger.error({ tableId, userId, event: 'auto_action_failed', error: err.message });
        // Last resort: auto-drop
        try {
          await this._autoDrop(tableId, userId);
        } catch (dropErr) {
          logger.error({ tableId, userId, event: 'auto_drop_failed', error: dropErr.message });
        }
      }
    }, seconds * 1000);

    this._timers.set(key, { timeout, interval, remaining: seconds });
  }

  /**
   * Cancel the timer for a specific player at a table.
   */
  cancelTimer(tableId, userId) {
    const key = this._key(tableId, userId);
    const timer = this._timers.get(key);
    if (!timer) return;
    clearTimeout(timer.timeout);
    clearInterval(timer.interval);
    this._timers.delete(key);
  }

  /**
   * Cancel all timers for a table (called on game over).
   */
  cancelAllTimers(tableId) {
    for (const [key, timer] of this._timers) {
      if (key.startsWith(`${tableId}:`)) {
        clearTimeout(timer.timeout);
        clearInterval(timer.interval);
        this._timers.delete(key);
      }
    }
  }

  getRemainingTime(tableId, userId) {
    const timer = this._timers.get(this._key(tableId, userId));
    return timer ? timer.remaining : 0;
  }

  // ─── Auto Actions ─────────────────────────────────────────────────────────────

  async _autoDrawAndDiscard(tableId, userId) {
    const drawResult = await this.gameEngine.drawCard(userId, tableId, 'closed');

    this.io.of('/game').to(`table:${tableId}`).emit('card_drawn', {
      user_id: userId,
      source: 'closed',
      open_pile_top: drawResult.open_pile_top,
      auto: true,
    });

    // Now auto-discard the highest point card
    await this._autoDiscard(tableId, userId);
  }

  async _autoDiscard(tableId, userId) {
    const hand = await this.gameEngine.getPlayerHand(tableId, userId);
    if (!hand || hand.length === 0) return;

    // Discard highest-value card (prefer non-joker)
    const highestCard = this._pickHighestCard(hand);
    const discardResult = await this.gameEngine.discardCard(userId, tableId, highestCard);

    this.io.of('/game').to(`table:${tableId}`).emit('card_discarded', {
      user_id: userId,
      card: highestCard,
      open_pile_top: discardResult.open_pile_top,
      next_player_id: discardResult.next_player_id,
      auto: true,
    });

    // Notify next player it's their turn
    this.io.of('/game').to(`user:${discardResult.next_player_id}`).emit('your_turn', {
      time_limit: 30,
      valid_actions: ['draw_card'],
      open_pile_top: discardResult.open_pile_top,
    });

    this.startTimer(tableId, discardResult.next_player_id, 30, 'draw_card');
  }

  async _autoDrop(tableId, userId) {
    const result = await this.gameEngine.dropGame(userId, tableId);

    this.io.of('/game').to(`table:${tableId}`).emit('player_dropped', {
      user_id: userId,
      penalty_points: result.penalty,
      next_player_id: result.next_player_id,
      auto: true,
    });

    if (result.game_over) {
      this.cancelAllTimers(tableId);
      this.io.of('/game').to(`table:${tableId}`).emit('game_over', result.gameOverPayload);
      await this.gameEngine.distributeWinnings(tableId, result).catch(() => {});
    } else if (result.next_player_id) {
      this.io.of('/game').to(`user:${result.next_player_id}`).emit('your_turn', {
        time_limit: 30,
        valid_actions: ['draw_card'],
      });
      this.startTimer(tableId, result.next_player_id, 30, 'draw_card');
    }
  }

  _pickHighestCard(hand) {
    const DeckManager = require('./DeckManager');
    return hand
      .filter(c => !DeckManager.isJoker(c))
      .sort((a, b) => DeckManager.getCardPoints(b) - DeckManager.getCardPoints(a))[0]
      || hand[0];
  }

  _key(tableId, userId) { return `${tableId}:${userId}`; }
}

module.exports = TurnTimerService;
