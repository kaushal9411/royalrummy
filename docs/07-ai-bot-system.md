# AI Bot System — RummyRoyale

## 1. Bot Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         BOT SERVICE                                 │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                   BOT POOL MANAGER                         │    │
│  │  Maintains pool of virtual bot users in Redis              │    │
│  │  Spawns bots when tables need filling                      │    │
│  │  Scales pool based on matchmaking queue depth              │    │
│  └─────────────────────┬───────────────────────────────────────┘    │
│                        │                                             │
│  ┌─────────────────────▼──────────────────────────────────────┐     │
│  │                DECISION ENGINE                              │     │
│  │  ┌───────────────┐ ┌───────────────┐ ┌──────────────────┐  │     │
│  │  │ Beginner Bot  │ │  Medium Bot   │ │    Pro Bot       │  │     │
│  │  │ Rule-based    │ │ Probability   │ │ Monte Carlo +    │  │     │
│  │  │ Simple heur.  │ │ heuristics    │ │ Pattern memory   │  │     │
│  │  └───────────────┘ └───────────────┘ └──────────────────┘  │     │
│  └────────────────────────────────────────────────────────────┘     │
│                        │                                             │
│  ┌─────────────────────▼──────────────────────────────────────┐     │
│  │              HUMAN BEHAVIOR SIMULATOR                      │     │
│  │  Think delays │ Typing indicators │ Random emotes         │     │
│  │  Occasional mistakes │ Realistic timing distributions     │     │
│  └────────────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. Bot Difficulty Levels

### Level 1: Beginner Bot
```typescript
class BeginnerBot extends BaseBot {
  // Strategy: basic grouping, no advanced planning

  async decideAction(gameState: PlayerGameView): Promise<GameAction> {
    const hand = gameState.my_hand;

    if (gameState.action_required === 'draw') {
      // Simple: always draw from closed pile
      return { type: 'draw_card', source: 'closed' };
    }

    if (gameState.action_required === 'discard') {
      // Discard the highest point card not in any partial meld
      const sorted = sortByPoints(hand);
      return { type: 'discard_card', card: sorted[sorted.length - 1] };
    }

    // Drop if points > 60 after 5+ turns
    if (gameState.turn_number > 5 && this.calculatePoints(hand) > 60) {
      if (Math.random() < 0.15) {  // 15% chance to drop
        return { type: 'drop_game' };
      }
    }

    return null;
  }
}
```

### Level 2: Medium Bot
```typescript
class MediumBot extends BaseBot {
  // Strategy: probability-based, tracks discards

  private discardHistory: Card[] = [];

  async decideAction(gameState: PlayerGameView): Promise<GameAction> {
    const hand = [...gameState.my_hand];
    this.updateDiscardHistory(gameState);

    if (gameState.action_required === 'draw') {
      const openCard = gameState.open_pile_top;

      // Evaluate if open card fits current melds
      const usefulness = this.evaluateCardUsefulness(openCard, hand);

      if (usefulness > 0.6) {
        return { type: 'draw_card', source: 'open' };
      }
      return { type: 'draw_card', source: 'closed' };
    }

    if (gameState.action_required === 'discard') {
      const bestDiscard = this.findBestDiscard(hand, gameState.wild_joker);
      return { type: 'discard_card', card: bestDiscard };
    }

    // Check if can declare
    const declaration = this.tryFormDeclaration(hand, gameState.wild_joker);
    if (declaration) {
      return { type: 'declare', hand: declaration };
    }

    return null;
  }

  private evaluateCardUsefulness(card: Card, hand: Card[]): number {
    // Count how many partial melds this card completes or extends
    let score = 0;

    const rank = card.slice(0, -1);
    const suit = card.slice(-1);

    // Check if extends any partial sequence
    for (const c of hand) {
      if (c.slice(-1) === suit) {
        const rankDiff = Math.abs(RANKS.indexOf(rank) - RANKS.indexOf(c.slice(0, -1)));
        if (rankDiff === 1 || rankDiff === 2) score += 0.3;
      }
      // Check if completes a set
      if (c.slice(0, -1) === rank) score += 0.25;
    }

    return Math.min(score, 1.0);
  }

  private findBestDiscard(hand: Card[], wildJoker: string): Card {
    // Score each card — lower is better to discard
    const scores = hand.map(card => ({
      card,
      score: this.cardRetentionScore(card, hand, wildJoker),
    }));

    scores.sort((a, b) => a.score - b.score);
    return scores[0].card;
  }

  private cardRetentionScore(card: Card, hand: Card[], wildJoker: string): number {
    let score = 0;

    // Jokers are extremely valuable
    if (card.startsWith('JK') || card === wildJoker) return 1000;

    const jokerCards = new RummyValidationEngine().getJokerCards(wildJoker);
    if (jokerCards.includes(card)) return 900;

    // High face cards with no meld potential = low score (better to discard)
    const points = getCardPoints(card);
    score -= points * 0.5;  // Penalize high-point cards

    // Reward cards that form melds with existing hand
    score += this.evaluateCardUsefulness(card, hand.filter(c => c !== card)) * 50;

    return score;
  }
}
```

### Level 3: Pro Bot (Monte Carlo)
```typescript
class ProBot extends BaseBot {
  private readonly SIMULATIONS = 500;

  async decideAction(gameState: PlayerGameView): Promise<GameAction> {
    // Use Monte Carlo simulation to evaluate moves
    if (gameState.action_required === 'discard') {
      const bestCard = await this.monteCarloBestDiscard(gameState);
      return { type: 'discard_card', card: bestCard };
    }

    if (gameState.action_required === 'draw') {
      const openCard = gameState.open_pile_top;
      const openScore = await this.simulateDrawResult(gameState, 'open');
      const closedScore = await this.simulateDrawResult(gameState, 'closed');
      return {
        type: 'draw_card',
        source: openScore > closedScore ? 'open' : 'closed',
      };
    }

    const declaration = this.tryFormDeclaration(
      gameState.my_hand, gameState.wild_joker
    );
    if (declaration) return { type: 'declare', hand: declaration };

    return null;
  }

  private async monteCarloBestDiscard(gameState: PlayerGameView): Promise<Card> {
    const hand = gameState.my_hand;
    const candidateDiscards = hand.filter(c =>
      !c.startsWith('JK') && c !== gameState.wild_joker
    );

    const scores: Record<string, number> = {};

    for (const discardCandidate of candidateDiscards) {
      let totalScore = 0;

      for (let i = 0; i < this.SIMULATIONS; i++) {
        const remainingHand = hand.filter(c => c !== discardCandidate);
        totalScore += await this.simulateGameFromState(remainingHand, gameState);
      }

      scores[discardCandidate] = totalScore / this.SIMULATIONS;
    }

    return Object.entries(scores)
      .sort(([, a], [, b]) => b - a)[0][0];
  }

  private async simulateGameFromState(
    hand: Card[],
    gameState: PlayerGameView,
  ): Promise<number> {
    // Simulate random draws and calculate expected points to complete
    const sim = [...hand];
    let turnsToComplete = 0;
    const MAX_SIM_TURNS = 20;

    while (turnsToComplete < MAX_SIM_TURNS) {
      const declaration = this.tryFormDeclaration(sim, gameState.wild_joker);
      if (declaration) return MAX_SIM_TURNS - turnsToComplete;

      // Draw a random unknown card
      const unknownCard = this.drawRandomUnknownCard(gameState);
      sim.push(unknownCard);

      // Discard worst card
      const worstCard = this.findWorstCard(sim, gameState.wild_joker);
      sim.splice(sim.indexOf(worstCard), 1);

      turnsToComplete++;
    }

    // Return negative of remaining deadwood (lower is better)
    return -this.calculateDeadwood(sim, gameState.wild_joker);
  }
}
```

---

## 3. Human Behavior Simulation

```typescript
class HumanBehaviorSimulator {

  // Add realistic delays to bot actions
  async simulateThinkTime(difficulty: BotDifficulty): Promise<void> {
    const delays = {
      beginner: { min: 3000, max: 8000 },  // 3-8 seconds
      medium:   { min: 2000, max: 5000 },
      pro:      { min: 1500, max: 3500 },
    };

    const { min, max } = delays[difficulty];
    const thinkTime = min + Math.random() * (max - min);

    // Add occasional "long think" (bot is confused)
    const extraThink = Math.random() < 0.1 ? 3000 : 0;

    await sleep(thinkTime + extraThink);
  }

  // Bots occasionally make suboptimal plays to appear human
  shouldMakeHumanMistake(difficulty: BotDifficulty): boolean {
    const mistakeRates = {
      beginner: 0.25,  // 25% chance of mistake
      medium:   0.10,
      pro:      0.03,
    };
    return Math.random() < mistakeRates[difficulty];
  }

  // Random emoji reactions
  getRandomReaction(event: string): string | null {
    if (Math.random() > 0.2) return null;

    const reactions = {
      good_draw: ['👍', '😊', '🎉'],
      bad_draw: ['😤', '🙄'],
      opponent_declare: ['😮', '👏', '🤦'],
    };

    const options = reactions[event] || [];
    return options[Math.floor(Math.random() * options.length)];
  }
}
```

---

## 4. Bot Pool Management

```typescript
@Injectable()
export class BotPoolManager {

  // Keep 50 pre-authenticated bot accounts per difficulty
  async initializeBotPool(): Promise<void> {
    for (const difficulty of ['beginner', 'medium', 'pro']) {
      for (let i = 1; i <= 50; i++) {
        const botId = `bot_${difficulty}_${i.toString().padStart(3, '0')}`;
        await this.redis.sadd(`bot:pool:${difficulty}`, botId);
      }
    }
  }

  async assignBotToTable(
    tableId: string,
    difficulty: BotDifficulty,
  ): Promise<string> {
    const botId = await this.redis.spop(`bot:pool:${difficulty}`);
    if (!botId) throw new Error('No bots available');

    await this.redis.setex(`bot:active:${botId}`, 3600, tableId);
    return botId;
  }

  async releaseBotFromTable(botId: string, difficulty: BotDifficulty): Promise<void> {
    await this.redis.del(`bot:active:${botId}`);
    await this.redis.sadd(`bot:pool:${difficulty}`, botId);
  }

  // Auto-fill tables that have waited too long
  @Cron('*/10 * * * * *')  // Every 10 seconds
  async autoFillEmptyTables(): Promise<void> {
    const waitingTables = await this.getTablesWaitingOver30s();

    for (const table of waitingTables) {
      const neededBots = table.min_players - table.current_players;
      for (let i = 0; i < neededBots; i++) {
        const botId = await this.assignBotToTable(table.id, 'medium');
        await this.joinTableAsBot(botId, table.id);
      }
    }
  }
}
```

---

## 5. Bot Detection Prevention

```typescript
// Measures to ensure bots feel human
const botHumanizationConfig = {
  // Vary avatar (pre-set real-looking avatars)
  useRealAvatars: true,

  // Use real Indian names
  useRealisticNames: true,
  namePool: ['Rahul K.', 'Priya S.', 'Amit V.', ...],  // 1000 names

  // Show typing indicator before chat
  showTypingIndicator: true,

  // Occasional disconnection simulation (rejoins quickly)
  simulateDisconnect: { probability: 0.02, reconnectInMs: 3000 },

  // Vary ELO ratings
  eloRange: { min: 1100, max: 1600 },

  // Realistic game history
  hasPastGamesHistory: true,
};
```

---

## 6. Reinforcement Learning Extension (Future)

```
Architecture for ML-based bots (Phase 3):

State Space:
  - Own 13 cards (one-hot: 54 possible cards × 2 decks)
  - Discard pile history (last 10 cards)
  - Opponent card counts
  - Turn number, points scores

Action Space:
  - Draw from open pile (1)
  - Draw from closed pile (1)
  - Discard one of 14 cards (14)
  - Declare (1)
  - Drop (1)
  Total: 18 actions

Reward Function:
  +10  for winning a game
  -10  for losing
  +1   for reducing deadwood by 1 card-point
  -5   for wrong declaration
  +3   for completing a pure sequence

Training:
  - Self-play with 1M simulated games
  - PPO (Proximal Policy Optimization) algorithm
  - Training on GPU cluster, deploy as ONNX model
  - Inference: < 10ms per decision
```
