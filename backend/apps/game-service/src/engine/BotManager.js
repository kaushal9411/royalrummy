const { v4: uuidv4 } = require('uuid');
const logger = require('../../../../libs/utils/logger');
const DeckManager = require('./DeckManager');

// Human-like think delays (ms) per difficulty
const THINK_DELAYS = {
  beginner: { min: 2000, max: 5000 },
  medium:   { min: 1500, max: 3500 },
  pro:      { min: 800,  max: 2000 },
};

// Mistake rates: probability of sub-optimal play
const MISTAKE_RATES = {
  beginner: 0.25,
  medium:   0.10,
  pro:      0.02,
};

const EMOJI_REACTIONS = ['😊', '🎉', '🤔', '😅', '👍', '🔥'];

/**
 * Manages AI bots in game tables.
 * Three tiers: beginner (rule-based), medium (probability), pro (greedy/look-ahead).
 */
class BotManager {
  constructor(io, gameEngine, redis) {
    this.io = io;
    this.gameEngine = gameEngine;
    this.redis = redis;
    // Active bots: botId → { id, name, difficulty, tableId, thinkTimeout }
    this._bots = new Map();
  }

  /**
   * Create bot player descriptors (not persisted to DB — bots use temp IDs).
   */
  async createBots(count, difficulty = 'beginner') {
    const bots = [];
    for (let i = 0; i < count; i++) {
      const bot = {
        id: `bot:${uuidv4()}`,
        name: this._botName(),
        difficulty,
        isBot: true,
      };
      bots.push(bot);
    }
    return bots;
  }

  /**
   * Register a bot to act on a specific table.
   * Call this after the bot has been seated.
   */
  registerBot(botId, tableId, difficulty = 'beginner') {
    this._bots.set(botId, { id: botId, tableId, difficulty, thinkTimeout: null });
    logger.info({ event: 'bot_registered', botId, tableId, difficulty });
  }

  /**
   * Trigger bot to take its turn.
   * Called by game service when it's the bot's turn.
   */
  async takeTurn(botId, tableId) {
    const bot = this._bots.get(botId);
    if (!bot) return;

    const delay = this._thinkDelay(bot.difficulty);

    bot.thinkTimeout = setTimeout(async () => {
      try {
        await this._executeTurn(bot, tableId);
      } catch (err) {
        logger.warn({ event: 'bot_turn_failed', botId, tableId, error: err.message });
      }
    }, delay);
  }

  /**
   * Remove a bot from management (when game ends or bot drops).
   */
  removeBot(botId) {
    const bot = this._bots.get(botId);
    if (!bot) return;
    if (bot.thinkTimeout) clearTimeout(bot.thinkTimeout);
    this._bots.delete(botId);
  }

  // ─── Turn Execution ──────────────────────────────────────────────────────────

  async _executeTurn(bot, tableId) {
    const hand = await this.gameEngine.getPlayerHand(tableId, bot.id);
    const state = await this._getState(tableId);
    if (!state || !hand) return;

    const wildJoker = state.wild_joker;
    const openPileTop = state.open_pile[state.open_pile.length - 1];

    // Decide draw source
    const drawSource = this._decideDrawSource(hand, openPileTop, wildJoker, bot.difficulty);
    const drawResult = await this.gameEngine.drawCard(bot.id, tableId, drawSource);

    // Broadcast draw event (without revealing card to other players)
    this.io.of('/game').to(`table:${tableId}`).emit('card_drawn', {
      user_id: bot.id,
      source: drawSource,
      open_pile_top: drawResult.open_pile_top,
    });

    // Small pause to simulate thinking after drawing
    await this._sleep(500);

    // Get updated hand after draw
    const updatedHand = await this.gameEngine.getPlayerHand(tableId, bot.id);

    // Decide whether to declare or discard
    const shouldDeclare = this._checkDeclareOpportunity(updatedHand, wildJoker, bot.difficulty);

    if (shouldDeclare) {
      const groups = this._buildDeclaration(updatedHand, wildJoker);
      const result = await this.gameEngine.declare(bot.id, tableId, groups);

      if (result.is_valid) {
        this.io.of('/game').to(`table:${tableId}`).emit('game_over', result.gameOverPayload);
        await this.gameEngine.distributeWinnings(tableId, result).catch(() => {});
      }
      return;
    }

    // Discard
    const cardToDiscard = this._pickDiscard(updatedHand, wildJoker, bot.difficulty);
    const discardResult = await this.gameEngine.discardCard(bot.id, tableId, cardToDiscard);

    this.io.of('/game').to(`table:${tableId}`).emit('card_discarded', {
      user_id: bot.id,
      card: cardToDiscard,
      open_pile_top: discardResult.open_pile_top,
      next_player_id: discardResult.next_player_id,
    });

    // Occasionally send an emoji reaction
    if (Math.random() < 0.08) {
      const emoji = EMOJI_REACTIONS[Math.floor(Math.random() * EMOJI_REACTIONS.length)];
      this.io.of('/game').to(`table:${tableId}`).emit('new_message', {
        sender_id: bot.id,
        sender_username: this._bots.get(bot.id)?.name || 'Bot',
        message: emoji,
        type: 'emoji',
        timestamp: Date.now(),
      });
    }
  }

  // ─── Decision Logic ──────────────────────────────────────────────────────────

  _decideDrawSource(hand, openPileTop, wildJoker, difficulty) {
    if (!openPileTop) return 'closed';

    if (difficulty === 'beginner') {
      // Beginner randomly prefers closed pile
      return Math.random() < 0.7 ? 'closed' : 'open';
    }

    // Medium/Pro: take open pile card if it helps form a sequence or set
    if (this._isUsefulCard(hand, openPileTop, wildJoker)) {
      return 'open';
    }
    return 'closed';
  }

  _isUsefulCard(hand, card, wildJoker) {
    if (DeckManager.isJoker(card)) return true;

    const cardRank = DeckManager.getRank(card);
    const cardSuit = DeckManager.getSuit(card);
    const rankIdx = DeckManager.getRankIndex(card);
    const RANKS = require('./DeckManager').RANKS;

    return hand.some(h => {
      if (DeckManager.isJoker(h)) return false;
      if (DeckManager.getSuit(h) === cardSuit) {
        const diff = Math.abs(DeckManager.getRankIndex(h) - rankIdx);
        if (diff === 1 || diff === 2) return true; // Sequence potential
      }
      if (DeckManager.getRank(h) === cardRank && DeckManager.getSuit(h) !== cardSuit) {
        return true; // Set potential
      }
      return false;
    });
  }

  _pickDiscard(hand, wildJoker, difficulty) {
    if (difficulty === 'beginner' && Math.random() < MISTAKE_RATES.beginner) {
      // Beginners sometimes discard randomly
      return hand[Math.floor(Math.random() * hand.length)];
    }

    // Discard highest-point card that is not part of any potential group
    const isolated = hand
      .filter(c => !DeckManager.isJoker(c) && !this._isWildJoker(c, wildJoker))
      .map(card => ({ card, points: DeckManager.getCardPoints(card), potential: this._groupPotential(card, hand, wildJoker) }))
      .sort((a, b) => {
        if (a.potential !== b.potential) return a.potential - b.potential;
        return b.points - a.points;
      });

    return isolated.length > 0 ? isolated[0].card : hand[0];
  }

  _groupPotential(card, hand, wildJoker) {
    let count = 0;
    const rank = DeckManager.getRank(card);
    const suit = DeckManager.getSuit(card);
    const idx = DeckManager.getRankIndex(card);

    for (const h of hand) {
      if (h === card || DeckManager.isJoker(h)) continue;
      if (DeckManager.getSuit(h) === suit && Math.abs(DeckManager.getRankIndex(h) - idx) <= 2) count++;
      if (DeckManager.getRank(h) === rank && DeckManager.getSuit(h) !== suit) count++;
    }
    return count;
  }

  _checkDeclareOpportunity(hand, wildJoker, difficulty) {
    // Simplified check: see if hand deadwood is 0 (all cards grouped)
    const totalPoints = hand.reduce((sum, c) => {
      if (DeckManager.isJoker(c) || this._isWildJoker(c, wildJoker)) return sum;
      return sum + DeckManager.getCardPoints(c);
    }, 0);
    // Pro bots try to declare when very low deadwood; beginners only on zero
    if (difficulty === 'pro') return totalPoints <= 5;
    if (difficulty === 'medium') return totalPoints === 0;
    return totalPoints === 0;
  }

  _buildDeclaration(hand, wildJoker) {
    // Simplified grouping: return all cards as one group (engine will validate)
    // Real implementation would use sequence/set finder — sufficient for auto-declare on 0 deadwood
    return [hand];
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  async _getState(tableId) {
    const raw = await this.redis.get(`game:state:${tableId}`);
    return raw ? JSON.parse(raw) : null;
  }

  _thinkDelay(difficulty) {
    const { min, max } = THINK_DELAYS[difficulty] || THINK_DELAYS.medium;
    return Math.floor(Math.random() * (max - min) + min);
  }

  _sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

  _isWildJoker(card, wildJoker) {
    if (!wildJoker || DeckManager.isJoker(wildJoker)) return false;
    return DeckManager.getRank(card) === DeckManager.getRank(wildJoker);
  }

  _botName() {
    const names = ['AceBot', 'RummyKing', 'CardShark', 'JokerPro', 'DealMaster',
      'QuickDraw', 'SequenceKing', 'WildCard', 'RoyalPlayer', 'ChampBot'];
    return names[Math.floor(Math.random() * names.length)] + Math.floor(Math.random() * 99);
  }
}

module.exports = BotManager;
