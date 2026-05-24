# WebSocket Architecture — RummyRoyale

## 1. Connection Architecture

```
Client                     NGINX                 Game Service Node         Redis
  │                           │                       │                      │
  │── WSS Handshake ──────────►│                       │                      │
  │   (JWT in handshake)       │                       │                      │
  │                           │── Proxy Upgrade ──────►│                      │
  │                           │                       │── Subscribe ─────────►│
  │                           │                       │   game:{tableId}      │
  │◄────────────── connected ──────────────────────────│                      │
  │                           │                       │                      │
  │── join_table ─────────────────────────────────────►│                      │
  │                           │                       │── Publish ───────────►│
  │                           │                       │   player_joined       │
  │◄── player_joined (broadcast) ──────────────────────────────────────────────│
```

---

## 2. Socket.IO Namespace Structure

```
Namespace: /game        — All game-related events
Namespace: /lobby       — Table browser, matchmaking status
Namespace: /chat        — Chat rooms
Namespace: /tournament  — Tournament bracket events
Namespace: /social      — Friends, presence
```

---

## 3. Connection Lifecycle

### 3.1 Authentication Handshake
```typescript
// Client sends JWT during connection
const socket = io('wss://api.rummyroyale.com/game', {
  auth: {
    token: 'Bearer eyJ...',
    device_id: 'ANDROID-UUID-xxx',
  },
  transports: ['websocket'],
  reconnection: true,
  reconnectionAttempts: 10,
  reconnectionDelay: 1000,
  reconnectionDelayMax: 10000,
  timeout: 20000,
});
```

### 3.2 Server Auth Middleware
```typescript
// game-service/src/gateways/game.gateway.ts
@WebSocketGateway({ namespace: '/game' })
export class GameGateway implements OnGatewayInit, OnGatewayConnection {

  afterInit(server: Server) {
    server.use(async (socket: Socket, next) => {
      try {
        const token = socket.handshake.auth.token?.replace('Bearer ', '');
        const deviceId = socket.handshake.auth.device_id;

        const payload = await this.jwtService.verifyAsync(token);
        const user = await this.usersService.findById(payload.sub);

        if (!user || user.status !== 'active') {
          return next(new Error('AUTH_FAILED'));
        }

        socket.data.userId = user.id;
        socket.data.username = user.username;
        socket.data.deviceId = deviceId;

        // Track online presence in Redis
        await this.redisService.setex(
          `user:online:${user.id}`, 300, '1'
        );

        next();
      } catch (err) {
        next(new Error('AUTH_FAILED'));
      }
    });
  }
}
```

---

## 4. Event Architecture

### Client → Server Events

```typescript
// Table events
'join_table'         { table_id: string, entry_fee_currency: string }
'leave_table'        { table_id: string }
'ready'              { table_id: string }

// Gameplay events (game-specific, turn-based)
'draw_card'          { table_id: string, source: 'open' | 'closed' }
'discard_card'       { table_id: string, card: string }
'declare'            { table_id: string, hand: DeclaredHand }
'drop_game'          { table_id: string }
'sort_hand'          { table_id: string, hand: string[] }

// Chat
'send_message'       { room_id: string, message: string, type: 'text' | 'emoji' }

// Heartbeat
'ping'               {}   // Client sends every 15s
```

### Server → Client Events

```typescript
// Table lifecycle
'table_state'        TableState          // Full state on join/rejoin
'player_joined'      PlayerInfo          // Another player joined
'player_left'        { user_id: string }
'game_starting'      { countdown: number }
'game_started'       GameStartPayload    // Cards dealt, first turn

// Turn events
'your_turn'          TurnPayload         // { time_limit: 30, valid_actions: string[] }
'player_turn'        { user_id: string, time_remaining: number }
'card_drawn'         CardDrawPayload
'card_discarded'     { user_id: string, card: string, open_pile: string[] }
'turn_timer'         { user_id: string, seconds_remaining: number }
'auto_drop'          { user_id: string, reason: 'timeout' }

// Game end
'game_over'          GameOverPayload     // Scores, winner, prizes
'score_update'       ScorePayload
'player_declared'    { user_id: string, hand: DeclaredHand, valid: boolean }

// Presence
'player_reconnected' { user_id: string }
'player_disconnected'{ user_id: string, reconnect_timeout: number }

// System
'pong'               { server_time: number }
'error'              { code: string, message: string }
'kicked'             { reason: string }
```

---

## 5. Socket Payload Structures

```typescript
interface TableState {
  table_id: string;
  game_type: 'points_rummy' | 'pool_rummy_101' | 'pool_rummy_201' | 'deals_rummy';
  status: 'waiting' | 'in_progress';
  players: PlayerInfo[];
  current_turn_user_id: string | null;
  open_pile_top: string | null;    // Top card of discard pile
  closed_pile_count: number;
  your_hand: string[] | null;      // Only your cards
  turn_timer: number;
  match_number: number;
  scores: Record<string, number>;  // userId → current score/points
}

interface PlayerInfo {
  user_id: string;
  username: string;
  avatar_url: string;
  seat: number;
  status: 'waiting' | 'playing' | 'disconnected';
  card_count: number;              // How many cards they hold
  elo_rating: number;
}

interface GameStartPayload {
  match_id: string;
  your_hand: string[];             // ["AS","KH","QD","JC","10S","9H","8D","7C","6S","5H","4D","3C","2S"]
  open_pile_top: string;
  first_turn_user_id: string;
  turn_time_limit: 30;
}

interface CardDrawPayload {
  source: 'open' | 'closed';
  card: string | null;             // null if you drew from closed (only revealed to drawer)
  your_new_card?: string;          // Populated only for the drawing player
  open_pile_top: string | null;    // New top of open pile
}

interface DeclaredHand {
  sets: string[][];    // [["AS","AH","AD"], ["KS","KH","KD","KC"]]
  sequences: string[][];
  unmatched: string[];
}

interface GameOverPayload {
  match_id: string;
  winner_id: string;
  reason: 'declaration' | 'all_dropped' | 'timeout';
  players: {
    user_id: string;
    final_hand: string[];
    points: number;
    prize_won: number;
    rank: number;
  }[];
  next_game_in?: number;     // Seconds until next deal (deals rummy)
}
```

---

## 6. Room Management

```typescript
// Room naming conventions
`table:${tableId}`          — All players at a table
`user:${userId}`            — Private user room (personal notifications)
`tournament:${tournId}`     — Tournament participants
`team:${teamId}`            — Team chat room
`lobby`                     — Global lobby (table updates)
```

### Redis Adapter (multi-node broadcasting)
```typescript
// game-service/src/app.module.ts
import { createAdapter } from '@socket.io/redis-adapter';
import { createClient } from 'redis';

const pubClient = createClient({ url: process.env.REDIS_URL });
const subClient = pubClient.duplicate();

await Promise.all([pubClient.connect(), subClient.connect()]);

io.adapter(createAdapter(pubClient, subClient));
// Now emit to table:xxx reaches ALL nodes
```

---

## 7. Reconnection & State Recovery

### Client-Side
```dart
// Flutter socket reconnection flow
socket.onDisconnect((_) {
  _startReconnectTimer();
});

void _startReconnectTimer() {
  _reconnectTimer = Timer.periodic(Duration(seconds: 2), (timer) async {
    if (_reconnectAttempts >= 10) {
      timer.cancel();
      _showReconnectFailedDialog();
      return;
    }
    _reconnectAttempts++;
    await _reconnect();
  });
}

void _reconnect() async {
  socket.connect();
  // On connect, rejoin table
  socket.emit('join_table', { 'table_id': _activeTableId });
  // Server responds with full table_state
}
```

### Server-Side State Recovery
```typescript
@SubscribeMessage('join_table')
async handleJoinTable(
  @ConnectedSocket() client: Socket,
  @MessageBody() dto: JoinTableDto,
) {
  const userId = client.data.userId;
  const tableId = dto.table_id;

  // Get game state from Redis (persisted regardless of server node)
  const gameState = await this.redisService.get(`game:state:${tableId}`);
  if (!gameState) throw new WsException('TABLE_NOT_FOUND');

  const state = JSON.parse(gameState);

  // Check if player is reconnecting mid-game
  const isRejoin = state.players.some(p => p.user_id === userId);

  if (isRejoin) {
    // Get their encrypted hand
    const hand = await this.redisService.get(`game:hand:${tableId}:${userId}`);
    const playerHand = this.gameService.decryptHand(hand);

    // Emit full state to reconnecting player only
    client.emit('table_state', {
      ...state,
      your_hand: playerHand,
    });

    // Broadcast reconnection to others
    client.to(`table:${tableId}`).emit('player_reconnected', { user_id: userId });
  }

  client.join(`table:${tableId}`);
  client.join(`user:${userId}`);
}
```

---

## 8. Turn Timer System

```typescript
// Server-side turn timer with Redis TTL
class TurnTimerService {
  async startTurn(tableId: string, userId: string, timeLimit: number) {
    // Store turn start in Redis
    await this.redis.setex(
      `turn:active:${tableId}`,
      timeLimit + 5,  // +5s grace
      JSON.stringify({ userId, startedAt: Date.now(), limit: timeLimit })
    );

    // Broadcast turn notification
    this.io.to(`table:${tableId}`).emit('player_turn', {
      user_id: userId,
      time_remaining: timeLimit,
    });

    // Emit countdown every 5 seconds
    let remaining = timeLimit;
    const interval = setInterval(() => {
      remaining -= 5;
      if (remaining <= 0) {
        clearInterval(interval);
        this.handleTurnTimeout(tableId, userId);
        return;
      }
      this.io.to(`table:${tableId}`).emit('turn_timer', {
        user_id: userId,
        seconds_remaining: remaining,
      });
    }, 5000);

    // Store interval ref for early cancellation
    this.activeTimers.set(`${tableId}:${userId}`, interval);
  }

  async handleTurnTimeout(tableId: string, userId: string) {
    // Auto-discard highest card or auto-drop based on game type
    await this.gameService.executeAutoAction(tableId, userId);
    this.io.to(`table:${tableId}`).emit('auto_drop', {
      user_id: userId,
      reason: 'timeout',
    });
  }
}
```

---

## 9. WebSocket Scaling Strategy

```
┌─────────────────────────────────────────────────────────┐
│                   NGINX (Sticky Sessions)               │
│              ip_hash ensures same server                │
└──────┬────────────────┬──────────────────┬──────────────┘
       │                │                  │
 ┌─────▼──────┐  ┌──────▼──────┐  ┌───────▼──────┐
 │Game Node 1 │  │Game Node 2  │  │ Game Node 3  │
 │(5000 conns)│  │(5000 conns) │  │ (5000 conns) │
 └─────┬──────┘  └──────┬──────┘  └───────┬──────┘
       │                │                  │
       └────────────────┼──────────────────┘
                        │ Redis Pub/Sub
                   ┌────▼────┐
                   │  Redis  │
                   │ Cluster │
                   └─────────┘
```

### Capacity Planning
- Each game node: 5,000 concurrent WebSocket connections
- 100K concurrent users = 20 game server nodes
- Each node: 4 vCPU, 8GB RAM (c5.xlarge)
- Redis handles all cross-node messaging
