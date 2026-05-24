'use strict';

const { TRUMP_SUIT, canPlayCard } = require('./game.engine');

const RANK_VALUE = {
  '2': 0, '3': 1, '4': 2, '5': 3, '6': 4, '7': 5,
  '8': 6, '9': 7, '10': 8, 'J': 9, 'Q': 10, 'K': 11, 'A': 12,
};

// ─── Bid Logic ────────────────────────────────────────────────────────────────

function estimateBid(hand, level) {
  let score = 0;
  for (const card of hand) {
    const rv = RANK_VALUE[card.rank];
    if (card.suit === TRUMP_SUIT) {
      if (rv >= 10) score += 1.0;      // J, Q, K, A trump = likely trick
      else if (rv >= 7) score += 0.6;  // 10, 9, 8 trump
      else score += 0.3;
    } else {
      if (rv === 12) score += 0.7;     // Ace non-trump
      else if (rv === 11) score += 0.5;
      else if (rv >= 9) score += 0.2;
    }
  }

  let bid = Math.max(1, Math.round(score));

  if (level === 'easy') {
    // Easy bot: slightly random bid
    bid = Math.max(1, bid + Math.floor(Math.random() * 3) - 1);
  } else if (level === 'medium') {
    bid = Math.max(1, bid);
  } else {
    // Hard bot: exact estimate, never below 1
    bid = Math.max(1, bid);
  }

  return Math.min(bid, 13);
}

// ─── Card Play Logic ──────────────────────────────────────────────────────────

function getLegalCards(hand, ledSuit) {
  const legal = hand.filter((c) => canPlayCard(c, hand, ledSuit));
  return legal.length > 0 ? legal : hand;
}

function highestCard(cards) {
  return cards.reduce((best, c) =>
    RANK_VALUE[c.rank] > RANK_VALUE[best.rank] ? c : best
  );
}

function lowestCard(cards) {
  return cards.reduce((best, c) =>
    RANK_VALUE[c.rank] < RANK_VALUE[best.rank] ? c : best
  );
}

function lowestTrump(hand) {
  const trumps = hand.filter((c) => c.suit === TRUMP_SUIT);
  return trumps.length ? lowestCard(trumps) : null;
}

function highestTrump(hand) {
  const trumps = hand.filter((c) => c.suit === TRUMP_SUIT);
  return trumps.length ? highestCard(trumps) : null;
}

// Current winner of the in-progress trick
function trickWinner(currentTrick, ledSuit) {
  if (!currentTrick.length) return null;
  let best = currentTrick[0];
  for (let i = 1; i < currentTrick.length; i++) {
    const c = currentTrick[i];
    const isTrump = (card) => card.card.suit === TRUMP_SUIT;
    const isLed = (card) => card.card.suit === ledSuit;

    if (isTrump(c) && !isTrump(best)) { best = c; continue; }
    if (!isTrump(c) && isTrump(best)) continue;
    if (isLed(c) && !isLed(best) && !isTrump(best)) { best = c; continue; }
    if (!isLed(c) && isLed(best)) continue;
    if (RANK_VALUE[c.card.rank] > RANK_VALUE[best.card.rank]) best = c;
  }
  return best;
}

// ─── Difficulty strategies ────────────────────────────────────────────────────

function chooseCardEasy(hand, currentTrick, ledSuit) {
  const legal = getLegalCards(hand, ledSuit);
  return legal[Math.floor(Math.random() * legal.length)];
}

function chooseCardMedium(hand, currentTrick, ledSuit, bids, tricksWon, seat) {
  const legal = getLegalCards(hand, ledSuit);
  const needed = bids[seat] - (tricksWon[seat] || 0);
  const winner = trickWinner(currentTrick, ledSuit);

  if (currentTrick.length === 0) {
    // Leading: if need tricks, play highest card; otherwise dump low
    if (needed > 0) return highestCard(legal);
    return lowestCard(legal);
  }

  const iAmWinning = winner && winner.seat === seat;
  if (iAmWinning) {
    // Already winning; play lowest legal to conserve good cards
    return lowestCard(legal);
  }

  // Try to win with minimum card
  const winnerCard = winner ? winner.card : null;
  if (needed > 0) {
    // Try to beat with trump
    const trumpCards = legal.filter((c) => c.suit === TRUMP_SUIT);
    if (trumpCards.length && (!winnerCard || winnerCard.suit !== TRUMP_SUIT)) {
      return lowestCard(trumpCards);
    }
    // Try to beat with same suit
    const suitCards = legal.filter((c) => c.suit === ledSuit &&
      (!winnerCard || RANK_VALUE[c.rank] > RANK_VALUE[winnerCard.rank]));
    if (suitCards.length) return lowestCard(suitCards);
  }

  return lowestCard(legal);
}

function chooseCardHard(hand, currentTrick, ledSuit, bids, tricksWon, seat) {
  const legal = getLegalCards(hand, ledSuit);
  const needed = bids[seat] - (tricksWon[seat] || 0);
  const winner = trickWinner(currentTrick, ledSuit);
  const iAmWinning = winner && winner.seat === seat;
  const isLastToPlay = currentTrick.length === 3;

  if (currentTrick.length === 0) {
    // Leading
    if (needed <= 0) return lowestCard(legal); // avoid extra tricks
    const trumps = legal.filter((c) => c.suit === TRUMP_SUIT);
    const nonTrumps = legal.filter((c) => c.suit !== TRUMP_SUIT);
    // Lead high non-trump aces first
    const aces = nonTrumps.filter((c) => c.rank === 'A');
    if (aces.length) return aces[0];
    if (needed > 0 && trumps.length) return lowestCard(trumps);
    return highestCard(nonTrumps.length ? nonTrumps : legal);
  }

  if (iAmWinning && (isLastToPlay || needed <= 0)) {
    return lowestCard(legal);
  }

  if (needed > 0) {
    const winnerCard = winner ? winner.card : null;

    // Try to win with suited card
    if (ledSuit) {
      const suitCards = legal.filter(
        (c) => c.suit === ledSuit &&
          (!winnerCard || RANK_VALUE[c.rank] > RANK_VALUE[winnerCard.rank])
      );
      if (suitCards.length) return lowestCard(suitCards);
    }

    // Try to win with trump
    const trumpCards = legal.filter((c) => c.suit === TRUMP_SUIT);
    if (trumpCards.length) {
      if (!winnerCard || winnerCard.suit !== TRUMP_SUIT) return lowestCard(trumpCards);
      const beatTrump = trumpCards.filter(
        (c) => RANK_VALUE[c.rank] > RANK_VALUE[winnerCard.rank]
      );
      if (beatTrump.length) return lowestCard(beatTrump);
    }
  }

  return lowestCard(legal);
}

// ─── Public API ───────────────────────────────────────────────────────────────

function getBotBid(hand, level = 'medium') {
  return estimateBid(hand, level);
}

function getBotCard(hand, currentTrick, ledSuit, bids, tricksWon, seat, level = 'medium') {
  switch (level) {
    case 'easy':   return chooseCardEasy(hand, currentTrick, ledSuit);
    case 'hard':   return chooseCardHard(hand, currentTrick, ledSuit, bids, tricksWon, seat);
    default:       return chooseCardMedium(hand, currentTrick, ledSuit, bids, tricksWon, seat);
  }
}

module.exports = { getBotBid, getBotCard };
