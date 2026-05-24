const DeckManager = require('./DeckManager');

const MAX_PENALTY = 80;
const FIRST_DROP_PENALTY = 20;
const MID_DROP_PENALTY = 40;
const WRONG_DECLARE_PENALTY = 80;

class ScoreCalculator {
  /**
   * Calculate deadwood points for unmatched cards in a hand.
   * Returns a value capped at MAX_PENALTY (80).
   */
  calculateDeadwood(hand, wildJokerCard) {
    let total = 0;
    for (const card of hand) {
      if (DeckManager.isJoker(card)) continue;
      if (this._isWildJoker(card, wildJokerCard)) continue;
      total += DeckManager.getCardPoints(card);
    }
    return Math.min(total, MAX_PENALTY);
  }

  /**
   * Compute prize distribution given entry fees and scores.
   * Returns { winnerId, prize, rake }.
   */
  computePrizeDistribution(entryFee, playerCount, rakePercent = 0.10) {
    const prizePool = entryFee * playerCount;
    const rake = Math.floor(prizePool * rakePercent * 100) / 100;
    const prize = Math.floor((prizePool - rake) * 100) / 100;
    return { prizePool, rake, prize };
  }

  /**
   * Determine drop penalty based on turn number and total player count.
   * First turn (before drawing on turn 1) = 20 pts; all others = 40 pts.
   */
  getDropPenalty(turnNumber, playerCount) {
    return turnNumber <= playerCount ? FIRST_DROP_PENALTY : MID_DROP_PENALTY;
  }

  getWrongDeclarePenalty() { return WRONG_DECLARE_PENALTY; }
  getMaxPenalty() { return MAX_PENALTY; }

  _isWildJoker(card, wildJokerCard) {
    if (!wildJokerCard || DeckManager.isJoker(wildJokerCard)) return false;
    const wildRank = wildJokerCard.slice(0, -1);
    const cardRank = card.slice(0, -1);
    return cardRank === wildRank;
  }
}

module.exports = ScoreCalculator;
module.exports.MAX_PENALTY = MAX_PENALTY;
module.exports.FIRST_DROP_PENALTY = FIRST_DROP_PENALTY;
module.exports.MID_DROP_PENALTY = MID_DROP_PENALTY;
module.exports.WRONG_DECLARE_PENALTY = WRONG_DECLARE_PENALTY;
