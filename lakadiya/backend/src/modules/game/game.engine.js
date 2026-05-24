'use strict';

// ─── Constants ────────────────────────────────────────────────────────────────

const SUITS = ['spades', 'hearts', 'diamonds', 'clubs'];
const RANKS = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
const TRUMP_SUIT = 'spades';
const TOTAL_ROUNDS = 5;
const PLAYERS = 4;

const RANK_VALUE = Object.fromEntries(RANKS.map((r, i) => [r, i]));

// ─── Deck helpers ─────────────────────────────────────────────────────────────

function buildDeck() {
  const deck = [];
  for (const suit of SUITS) {
    for (const rank of RANKS) {
      deck.push({ suit, rank });
    }
  }
  return deck;
}

function shuffle(deck) {
  const d = [...deck];
  for (let i = d.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [d[i], d[j]] = [d[j], d[i]];
  }
  return d;
}

function deal() {
  const shuffled = shuffle(buildDeck());
  return [
    shuffled.slice(0, 13),
    shuffled.slice(13, 26),
    shuffled.slice(26, 39),
    shuffled.slice(39, 52),
  ];
}

// ─── Card comparison ──────────────────────────────────────────────────────────

function cardBeats(challenger, incumbent, ledSuit) {
  // challenger tries to beat incumbent given the led suit
  if (challenger.suit === TRUMP_SUIT && incumbent.suit !== TRUMP_SUIT) return true;
  if (challenger.suit !== TRUMP_SUIT && incumbent.suit === TRUMP_SUIT) return false;
  if (challenger.suit !== ledSuit && incumbent.suit === ledSuit) return false;
  if (challenger.suit === ledSuit && incumbent.suit !== ledSuit) return true;
  if (challenger.suit !== incumbent.suit) return false;
  return RANK_VALUE[challenger.rank] > RANK_VALUE[incumbent.rank];
}

function determineTrickWinner(plays, ledSuit) {
  // plays = [{ seat, card }]
  let winner = plays[0];
  for (let i = 1; i < plays.length; i++) {
    if (cardBeats(plays[i].card, winner.card, ledSuit)) {
      winner = plays[i];
    }
  }
  return winner.seat;
}

// ─── Validation ───────────────────────────────────────────────────────────────

function canPlayCard(card, hand, ledSuit) {
  if (!ledSuit) return true; // first play of trick
  const hasLedSuit = hand.some((c) => c.suit === ledSuit);
  if (hasLedSuit) return card.suit === ledSuit;
  return true; // no led suit in hand — play anything
}

function cardInHand(card, hand) {
  return hand.some((c) => c.suit === card.suit && c.rank === card.rank);
}

function removeCardFromHand(card, hand) {
  const idx = hand.findIndex((c) => c.suit === card.suit && c.rank === card.rank);
  if (idx === -1) return hand;
  return [...hand.slice(0, idx), ...hand.slice(idx + 1)];
}

// ─── Score calculation ────────────────────────────────────────────────────────

function calculateScore(bid, won) {
  if (won < bid) return -bid;
  if (won === bid) return bid;
  return bid + (won - bid) * 0.1;
}

// ─── In-memory game state factory ─────────────────────────────────────────────

function createGameState(roomId, players) {
  // players = [{ seat, userId, username, isBot, botLevel }]
  return {
    roomId,
    matchId: null,
    players,                  // static seat info
    round: 0,                 // current round number (1-based when active)
    currentRoundId: null,
    dealer: 0,                // seat index of current dealer
    phase: 'waiting',         // waiting | bidding | playing | round_end | game_end
    hands: {},                // { seat: [card] }
    bids: {},                 // { seat: number }
    tricksWon: {},            // { seat: number }
    currentTrick: [],         // [{ seat, card }]
    currentTurn: null,        // seat
    ledSuit: null,
    scores: {},               // { seat: totalScore }
    roundScores: [],          // [{ seat, bid, won, score }] per round
  };
}

function startRound(state) {
  state.round += 1;
  const hands = deal();
  state.hands = {};
  state.bids = {};
  state.tricksWon = {};
  state.currentTrick = [];
  state.ledSuit = null;
  state.phase = 'bidding';

  for (let s = 0; s < PLAYERS; s++) {
    state.hands[s] = hands[s];
    state.tricksWon[s] = 0;
  }

  // Bidding starts to the left of dealer
  state.currentTurn = (state.dealer + 1) % PLAYERS;
  return state;
}

function placeBid(state, seat, bid) {
  if (state.phase !== 'bidding') throw new Error('Not bidding phase');
  if (state.currentTurn !== seat) throw new Error('Not your turn');
  if (bid < 1 || bid > 13) throw new Error('Bid must be 1-13');

  state.bids[seat] = bid;
  const nextSeat = (seat + 1) % PLAYERS;

  // If we've wrapped back to seat after dealer, all have bid
  const allBid = Object.keys(state.bids).length === PLAYERS;
  if (allBid) {
    state.phase = 'playing';
    // First trick: player to left of dealer leads
    state.currentTurn = (state.dealer + 1) % PLAYERS;
  } else {
    state.currentTurn = nextSeat;
  }
  return state;
}

function playCard(state, seat, card) {
  if (state.phase !== 'playing') throw new Error('Not playing phase');
  if (state.currentTurn !== seat) throw new Error('Not your turn');

  const hand = state.hands[seat];
  if (!cardInHand(card, hand)) throw new Error('Card not in hand');

  const ledSuit = state.currentTrick.length === 0 ? null : state.ledSuit;
  if (!canPlayCard(card, hand, ledSuit)) {
    throw new Error(`Must follow suit: ${ledSuit}`);
  }

  state.hands[seat] = removeCardFromHand(card, hand);
  state.currentTrick.push({ seat, card });

  if (state.currentTrick.length === 1) {
    state.ledSuit = card.suit;
  }

  if (state.currentTrick.length === PLAYERS) {
    // Resolve trick
    const winnerSeat = determineTrickWinner(state.currentTrick, state.ledSuit);
    state.tricksWon[winnerSeat] = (state.tricksWon[winnerSeat] || 0) + 1;

    const completedTrick = {
      plays: [...state.currentTrick],
      winnerSeat,
      ledSuit: state.ledSuit,
    };
    state.currentTrick = [];
    state.ledSuit = null;
    state.currentTurn = winnerSeat;

    // Check if round is over (13 tricks)
    const totalTricks = Object.values(state.tricksWon).reduce((a, b) => a + b, 0);
    if (totalTricks === 13) {
      return finishRound(state, completedTrick);
    }
    return { state, trickResult: completedTrick, roundOver: false };
  }

  // Advance turn
  state.currentTurn = (seat + 1) % PLAYERS;
  return { state, trickResult: null, roundOver: false };
}

function finishRound(state, lastTrick) {
  const roundScoreRow = [];
  for (let s = 0; s < PLAYERS; s++) {
    const bid = state.bids[s];
    const won = state.tricksWon[s] || 0;
    const score = calculateScore(bid, won);
    state.scores[s] = (state.scores[s] || 0) + score;
    roundScoreRow.push({ seat: s, bid, won, score });
  }
  state.roundScores.push(roundScoreRow);

  state.dealer = (state.dealer + 1) % PLAYERS;
  state.phase = state.round >= TOTAL_ROUNDS ? 'game_end' : 'round_end';

  return { state, trickResult: lastTrick, roundOver: true, roundScores: roundScoreRow };
}

function getGameWinner(state) {
  let bestSeat = 0;
  let bestScore = -Infinity;
  for (let s = 0; s < PLAYERS; s++) {
    if ((state.scores[s] || 0) > bestScore) {
      bestScore = state.scores[s];
      bestSeat = s;
    }
  }
  return bestSeat;
}

module.exports = {
  createGameState,
  startRound,
  placeBid,
  playCard,
  finishRound,
  getGameWinner,
  calculateScore,
  canPlayCard,
  determineTrickWinner,
  TRUMP_SUIT,
  TOTAL_ROUNDS,
};
