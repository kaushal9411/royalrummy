# Game Engine — RummyRoyale

## 1. Game Engine Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        RUMMY GAME ENGINE                            │
│                                                                     │
│  ┌─────────────────┐  ┌─────────────────┐  ┌────────────────────┐  │
│  │  Deck Manager   │  │  Turn Manager   │  │  Score Calculator  │  │
│  │  (52 cards)     │  │  (Timer/Queue)  │  │  (Deadwood Points) │  │
│  └────────┬────────┘  └────────┬────────┘  └──────────┬─────────┘  │
│           │                   │                       │             │
│  ┌────────▼───────────────────-▼───────────────────────▼─────────┐  │
│  │                    GAME STATE MACHINE                         │  │
│  │  waiting → dealing → in_progress → declaring → completed     │  │
│  └────────────────────────────┬──────────────────────────────────┘  │
│                               │                                     │
│  ┌────────────────────────────▼──────────────────────────────────┐  │
│  │                   VALIDATION ENGINE                           │  │
│  │  Card validity │ Meld validation │ Declaration rules          │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. Card Representation

```typescript
// Card encoding: <Rank><Suit>
// Ranks: A 2 3 4 5 6 7 8 9 10 J Q K
// Suits: S(Spades) H(Hearts) D(Diamonds) C(Clubs)
// Jokers: JK1, JK2 (printed jokers), WJ (wild joker)

type Card = string; // "AS", "KH", "10D", "JC", "JK1", "WJ"

const RANKS = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];
const SUITS = ['S', 'H', 'D', 'C'];

// Card point values in Rummy
function getCardPoints(card: Card): number {
  if (card.startsWith('JK') || card === 'WJ') return 0;  // Joker = 0 points
  const rank = card.slice(0, -1);
  if (['A', 'J', 'Q', 'K'].includes(rank)) return 10;
  return parseInt(rank);
}
```

---

## 3. Deck Manager

```typescript
export class DeckManager {
  private deck: Card[] = [];

  constructor(private readonly deckCount: number = 2) {
    this.initialize();
  }

  private initialize(): void {
    this.deck = [];
    for (let d = 0; d < this.deckCount; d++) {
      for (const suit of SUITS) {
        for (const rank of RANKS) {
          this.deck.push(`${rank}${suit}`);
        }
      }
      this.deck.push(`JK${d + 1}`);  // 2 jokers per deck
    }
  }

  shuffle(): void {
    // Fisher-Yates shuffle (cryptographically seeded for fairness)
    const seed = crypto.randomBytes(4).readUInt32BE(0);
    let m = this.deck.length;
    while (m) {
      const i = Math.floor((seed * m--) / 0xFFFFFFFF) % (m + 1);
      [this.deck[m], this.deck[i]] = [this.deck[i], this.deck[m]];
    }
  }

  dealHands(playerCount: number, cardsPerPlayer: number): { hands: Card[][], remaining: Card[] } {
    this.shuffle();
    const hands: Card[][] = [];
    let idx = 0;

    for (let p = 0; p < playerCount; p++) {
      hands.push(this.deck.slice(idx, idx + cardsPerPlayer));
      idx += cardsPerPlayer;
    }

    return {
      hands,
      remaining: this.deck.slice(idx),  // Draw pile
    };
  }

  selectWildJoker(remaining: Card[]): Card {
    // Top card of remaining pile becomes wild joker indicator
    const jokerCard = remaining[0];
    return jokerCard;
  }
}
```

---

## 4. Game State Machine

```typescript
export enum GameStatus {
  WAITING = 'waiting',
  DEALING = 'dealing',
  IN_PROGRESS = 'in_progress',
  DECLARING = 'declaring',
  COMPLETED = 'completed',
  CANCELLED = 'cancelled',
}

export class GameStateMachine {

  async startGame(tableId: string, players: string[]): Promise<void> {
    const deck = new DeckManager(2);
    const { hands, remaining } = deck.dealHands(players.length, 13);
    const wildJokerCard = deck.selectWildJoker(remaining);

    const state: GameState = {
      table_id: tableId,
      status: GameStatus.IN_PROGRESS,
      players: players.map((userId, idx) => ({
        user_id: userId,
        seat: idx,
        hand: hands[idx],
        status: 'playing',
        points: 0,
      })),
      closed_pile: remaining.slice(1),
      open_pile: [remaining[0]],
      wild_joker: wildJokerCard,
      current_turn_idx: 0,
      turn_number: 1,
      created_at: Date.now(),
    };

    // Store in Redis (game is authoritative in cache)
    await this.redisService.setex(
      `game:state:${tableId}`,
      3600,
      JSON.stringify(state)
    );

    // Store each player's hand separately (encrypted)
    for (let i = 0; i < players.length; i++) {
      const encrypted = this.encryptHand(hands[i], tableId);
      await this.redisService.setex(
        `game:hand:${tableId}:${players[i]}`,
        3600,
        encrypted
      );
    }
  }

  async processAction(
    tableId: string,
    userId: string,
    action: GameAction,
  ): Promise<ActionResult> {
    const state = await this.getGameState(tableId);

    // Anti-cheat: validate it's this player's turn
    const currentPlayer = state.players[state.current_turn_idx];
    if (currentPlayer.user_id !== userId) {
      throw new GameException('GAME_004');
    }

    switch (action.type) {
      case 'draw_card':
        return this.processDrawCard(state, userId, action.source);
      case 'discard_card':
        return this.processDiscard(state, userId, action.card);
      case 'declare':
        return this.processDeclaration(state, userId, action.hand);
      case 'drop_game':
        return this.processDrop(state, userId);
    }
  }

  private async processDeclaration(
    state: GameState,
    userId: string,
    declaredHand: DeclaredHand,
  ): Promise<ActionResult> {
    const validation = this.validationEngine.validate(
      declaredHand,
      state.wild_joker
    );

    if (!validation.isValid) {
      // Wrong declaration = 80 points penalty
      await this.applyPenalty(state, userId, 80);
      return { success: false, error: 'INVALID_DECLARATION', penalty: 80 };
    }

    // Calculate scores for all players
    const scores = this.scoreCalculator.calculateFinalScores(
      state.players,
      userId
    );

    return { success: true, scores, winner: userId };
  }
}
```

---

## 5. Validation Engine

```typescript
export class RummyValidationEngine {

  validate(hand: DeclaredHand, wildJoker: string): ValidationResult {
    const allCards = [
      ...hand.sets.flat(),
      ...hand.sequences.flat(),
      ...hand.unmatched,
    ];

    // Must have exactly 13 cards
    if (allCards.length !== 13) {
      return { isValid: false, reason: 'Must have exactly 13 cards' };
    }

    // Must have at least 2 sequences
    if (hand.sequences.length < 2) {
      return { isValid: false, reason: 'Minimum 2 sequences required' };
    }

    // At least one PURE sequence (no jokers)
    const pureSeqs = hand.sequences.filter(seq => this.isPureSequence(seq, wildJoker));
    if (pureSeqs.length < 1) {
      return { isValid: false, reason: 'At least one pure sequence required' };
    }

    // Validate all melds
    for (const seq of hand.sequences) {
      if (!this.isValidSequence(seq, wildJoker)) {
        return { isValid: false, reason: `Invalid sequence: ${seq.join(',')}` };
      }
    }

    for (const set of hand.sets) {
      if (!this.isValidSet(set, wildJoker)) {
        return { isValid: false, reason: `Invalid set: ${set.join(',')}` };
      }
    }

    // Unmatched cards must be 0 for full declaration
    if (hand.unmatched.length > 0) {
      return { isValid: false, reason: 'All cards must be in melds' };
    }

    return { isValid: true };
  }

  private isPureSequence(sequence: Card[], wildJoker: string): boolean {
    const jokers = this.getJokerCards(wildJoker);
    return !sequence.some(card => jokers.includes(card) || card.startsWith('JK'));
  }

  private isValidSequence(sequence: Card[], wildJoker: string): boolean {
    if (sequence.length < 3) return false;

    const jokers = this.getJokerCards(wildJoker);
    const realCards = sequence.filter(c => !jokers.includes(c) && !c.startsWith('JK'));

    // Sort real cards
    const sorted = this.sortByRank(realCards);

    // Check consecutive ranks, same suit
    let expectedRank = RANKS.indexOf(sorted[0].slice(0, -1));
    const suit = sorted[0].slice(-1);
    let jokerCount = sequence.length - realCards.length;

    for (const card of sorted.slice(1)) {
      const rank = RANKS.indexOf(card.slice(0, -1));
      const gap = rank - expectedRank - 1;

      if (card.slice(-1) !== suit) return false;  // Mixed suit
      if (gap > jokerCount) return false;          // Not enough jokers to fill

      jokerCount -= gap;
      expectedRank = rank;
    }

    return true;
  }

  private isValidSet(set: Card[], wildJoker: string): boolean {
    if (set.length < 3 || set.length > 4) return false;

    const jokers = this.getJokerCards(wildJoker);
    const realCards = set.filter(c => !jokers.includes(c) && !c.startsWith('JK'));

    const rank = realCards[0].slice(0, -1);
    const suits = new Set<string>();

    for (const card of realCards) {
      if (card.slice(0, -1) !== rank) return false;  // Different ranks
      if (suits.has(card.slice(-1))) return false;    // Duplicate suit
      suits.add(card.slice(-1));
    }

    return true;
  }

  getJokerCards(wildJokerCard: string): Card[] {
    const wildRank = wildJokerCard.slice(0, -1);
    return SUITS.map(s => `${wildRank}${s}`);
  }
}
```

---

## 6. Score Calculator

```typescript
export class ScoreCalculator {

  calculateDeadwood(hand: Card[], wildJoker: string): number {
    const jokers = this.validationEngine.getJokerCards(wildJoker);
    const printedJokers = hand.filter(c => c.startsWith('JK') || c === 'WJ');
    const regularCards = hand.filter(c =>
      !jokers.includes(c) && !printedJokers.includes(c)
    );

    return regularCards.reduce((sum, card) => sum + getCardPoints(card), 0);
  }

  calculateFinalScores(
    players: PlayerState[],
    winnerId: string,
    gameType: string,
  ): Record<string, number> {
    const scores: Record<string, number> = {};

    for (const player of players) {
      if (player.user_id === winnerId) {
        scores[player.user_id] = 0;
        continue;
      }

      if (player.status === 'dropped_first') {
        scores[player.user_id] = 20;  // First drop penalty
      } else if (player.status === 'dropped_mid') {
        scores[player.user_id] = 40;  // Middle drop penalty
      } else {
        const deadwood = this.calculateDeadwood(player.hand, player.wild_joker);
        scores[player.user_id] = Math.min(deadwood, 80);  // Max 80 points
      }
    }

    return scores;
  }

  calculatePrizePoints(scores: Record<string, number>, pointsPerCoin: number) {
    const prizes: Record<string, number> = {};
    const totalPoints = Object.values(scores).reduce((a, b) => a + b, 0);

    for (const [userId, points] of Object.entries(scores)) {
      if (points === 0) {
        // Winner gets total pool
        prizes[userId] = totalPoints * pointsPerCoin;
      } else {
        prizes[userId] = 0;
      }
    }

    return prizes;
  }
}
```

---

## 7. Game Variants

### Points Rummy
```
- Each player starts with 13 cards
- Points have monetary value (pointsPerCoin)
- Game ends when one player declares
- Loser pays winner: their_points × pointsPerCoin
```

### Pool Rummy (101 / 201)
```
- Players have cumulative score across deals
- Player eliminated when score exceeds 101 or 201
- Last surviving player wins the prize pool
- Rejoin allowed before 3 rounds if knocked out
```

### Deals Rummy
```
- Fixed number of deals (2, 3, or 6)
- Chips-based system
- Player with most chips after all deals wins
```

---

## 8. Anti-Cheat System

```typescript
export class AntiCheatEngine {

  // Validate server-side that action is legitimate
  async validateAction(
    userId: string,
    tableId: string,
    action: GameAction,
  ): Promise<boolean> {
    const serverHand = await this.getPlayerHand(tableId, userId);

    if (action.type === 'discard_card') {
      // Player must actually hold the card they're discarding
      if (!serverHand.includes(action.card)) {
        await this.flagFraud(userId, 'invalid_card_discard', 'high', {
          attempted_card: action.card,
          actual_hand: serverHand,
        });
        return false;
      }
    }

    if (action.type === 'declare') {
      // All declared cards must be from their actual hand
      const declaredCards = [
        ...action.hand.sets.flat(),
        ...action.hand.sequences.flat(),
        ...action.hand.unmatched,
      ];

      const isValid = declaredCards.every(card => serverHand.includes(card));
      if (!isValid) {
        await this.flagFraud(userId, 'invalid_declaration_cards', 'critical', {});
        return false;
      }
    }

    return true;
  }

  // Collude detection: same IP playing at same table
  async detectCollusion(tableId: string): Promise<void> {
    const players = await this.getTablePlayers(tableId);
    const ips = await this.getPlayerIPs(players.map(p => p.user_id));

    const ipGroups = new Map<string, string[]>();
    for (const [userId, ip] of Object.entries(ips)) {
      const existing = ipGroups.get(ip) || [];
      ipGroups.set(ip, [...existing, userId]);
    }

    for (const [ip, users] of ipGroups.entries()) {
      if (users.length > 1) {
        for (const userId of users) {
          await this.flagFraud(userId, 'collusion_suspected', 'high', {
            shared_ip: ip,
            co_players: users.filter(u => u !== userId),
          });
        }
      }
    }
  }
}
```
