const crypto = require('crypto');

const RANKS = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];
const SUITS = ['S', 'H', 'D', 'C'];

const CARD_POINTS = {
  A: 10, J: 10, Q: 10, K: 10,
  '2': 2, '3': 3, '4': 4, '5': 5, '6': 6,
  '7': 7, '8': 8, '9': 9, '10': 10,
};

class DeckManager {
  constructor(deckCount = 2) {
    this.deckCount = deckCount;
    this.deck = [];
    this._initialize();
  }

  _initialize() {
    this.deck = [];
    for (let d = 0; d < this.deckCount; d++) {
      for (const suit of SUITS) {
        for (const rank of RANKS) {
          this.deck.push(`${rank}${suit}`);
        }
      }
      // 2 jokers per deck
      this.deck.push(`JK${d + 1}`);
      this.deck.push(`JK${d + 1}B`); // Black joker
    }
  }

  shuffle() {
    // Cryptographically seeded Fisher-Yates shuffle for fair dealing
    for (let i = this.deck.length - 1; i > 0; i--) {
      const randomBytes = crypto.randomBytes(4);
      const j = randomBytes.readUInt32BE(0) % (i + 1);
      [this.deck[i], this.deck[j]] = [this.deck[j], this.deck[i]];
    }
    return this;
  }

  deal(playerCount, cardsEach) {
    const hands = Array.from({ length: playerCount }, () => []);
    let idx = 0;

    // Deal one card at a time (like real dealing)
    for (let round = 0; round < cardsEach; round++) {
      for (let p = 0; p < playerCount; p++) {
        hands[p].push(this.deck[idx++]);
      }
    }

    return {
      hands,
      remaining: this.deck.slice(idx),
    };
  }

  selectWildJoker(remaining) {
    // Top card of remaining pile determines wild joker rank
    const topCard = remaining[0];
    // Remove from remaining
    remaining.shift();
    return topCard;
  }

  static getCardPoints(card) {
    if (!card || card.startsWith('JK')) return 0;
    const rank = card.slice(0, -1);
    return CARD_POINTS[rank] || 0;
  }

  static getRank(card) {
    return card.slice(0, -1);
  }

  static getSuit(card) {
    return card.slice(-1);
  }

  static getRankIndex(card) {
    return RANKS.indexOf(DeckManager.getRank(card));
  }

  static isJoker(card) {
    return card.startsWith('JK');
  }
}

module.exports = DeckManager;
module.exports.RANKS = RANKS;
module.exports.SUITS = SUITS;
