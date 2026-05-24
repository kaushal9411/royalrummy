const { RANKS, SUITS } = require('./DeckManager');

class RummyValidator {

  validate(hand, wildJokerCard) {
    const allCards = [
      ...hand.sets.flat(),
      ...hand.sequences.flat(),
      ...(hand.unmatched || []),
    ];

    if (allCards.length !== 13) {
      return { isValid: false, reason: 'Must have exactly 13 cards' };
    }

    if (hand.sequences.length < 2) {
      return { isValid: false, reason: 'Minimum 2 sequences required' };
    }

    // At least one PURE sequence (no jokers of any kind)
    const pureSequences = hand.sequences.filter(seq =>
      this._isPureSequence(seq, wildJokerCard)
    );

    if (pureSequences.length < 1) {
      return { isValid: false, reason: 'At least one pure (natural) sequence required' };
    }

    // Validate all sequences
    for (const seq of hand.sequences) {
      if (!this._isValidSequence(seq, wildJokerCard)) {
        return { isValid: false, reason: `Invalid sequence: [${seq.join(', ')}]` };
      }
    }

    // Validate all sets
    for (const set of hand.sets) {
      if (!this._isValidSet(set, wildJokerCard)) {
        return { isValid: false, reason: `Invalid set: [${set.join(', ')}]` };
      }
    }

    if (hand.unmatched && hand.unmatched.length > 0) {
      return { isValid: false, reason: 'All cards must be grouped into sequences or sets' };
    }

    return { isValid: true };
  }

  _getWildJokerCards(wildJokerCard) {
    if (!wildJokerCard || wildJokerCard.startsWith('JK')) return [];
    const rank = wildJokerCard.slice(0, -1);
    return SUITS.map(s => `${rank}${s}`);
  }

  _isJoker(card, wildJokerCard) {
    if (card.startsWith('JK')) return true;
    const wildCards = this._getWildJokerCards(wildJokerCard);
    return wildCards.includes(card);
  }

  _isPureSequence(sequence, wildJokerCard) {
    return !sequence.some(card => this._isJoker(card, wildJokerCard));
  }

  _isValidSequence(sequence, wildJokerCard) {
    if (sequence.length < 3) return false;

    const jokerCards = sequence.filter(c => this._isJoker(c, wildJokerCard));
    const realCards = sequence.filter(c => !this._isJoker(c, wildJokerCard));

    if (realCards.length === 0) return false;

    // All real cards must be same suit
    const suit = realCards[0].slice(-1);
    if (!realCards.every(c => c.slice(-1) === suit)) return false;

    // Sort by rank
    const sorted = realCards.sort((a, b) =>
      RANKS.indexOf(a.slice(0, -1)) - RANKS.indexOf(b.slice(0, -1))
    );

    let jokerCount = jokerCards.length;

    for (let i = 1; i < sorted.length; i++) {
      const rankDiff =
        RANKS.indexOf(sorted[i].slice(0, -1)) -
        RANKS.indexOf(sorted[i - 1].slice(0, -1));

      if (rankDiff === 0) return false; // Duplicate rank in sequence
      if (rankDiff < 0) return false;   // Should not happen after sort

      const gapNeeded = rankDiff - 1;
      if (gapNeeded > jokerCount) return false;
      jokerCount -= gapNeeded;
    }

    return true;
  }

  _isValidSet(set, wildJokerCard) {
    if (set.length < 3 || set.length > 4) return false;

    const jokers = set.filter(c => this._isJoker(c, wildJokerCard));
    const realCards = set.filter(c => !this._isJoker(c, wildJokerCard));

    if (realCards.length === 0) return false;

    const rank = realCards[0].slice(0, -1);
    const suits = new Set();

    for (const card of realCards) {
      if (card.slice(0, -1) !== rank) return false;  // Different rank
      const s = card.slice(-1);
      if (suits.has(s)) return false;                // Duplicate suit
      suits.add(s);
    }

    return true;
  }
}

module.exports = RummyValidator;
