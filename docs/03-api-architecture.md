# API Architecture — RummyRoyale

## 1. API Gateway Structure

```
Base URL: https://api.rummyroyale.com/v1

All requests require:
  Authorization: Bearer <JWT>
  X-Device-ID: <device-fingerprint>
  X-App-Version: <semver>
  Content-Type: application/json
```

---

## 2. Auth Service API

```
POST   /auth/register          Register with phone/email
POST   /auth/login             Login, returns JWT + refresh token
POST   /auth/otp/send          Send OTP to phone
POST   /auth/otp/verify        Verify OTP
POST   /auth/refresh           Refresh JWT using refresh token
POST   /auth/logout            Revoke refresh token
POST   /auth/logout/all        Revoke all devices
GET    /auth/me                Current user profile
PATCH  /auth/profile           Update profile
POST   /auth/change-password
DELETE /auth/account           Soft delete account
POST   /auth/kyc/submit        Submit KYC documents
GET    /auth/kyc/status        KYC status
```

### Register Request/Response
```json
POST /auth/register
{
  "phone": "+919876543210",
  "email": "user@example.com",
  "username": "rummyking99",
  "password": "SecureP@ss123",
  "referral_code": "REF123ABC",
  "device_id": "ANDROID-UUID-xxxx",
  "fcm_token": "fcm-token-here"
}

Response 201:
{
  "success": true,
  "data": {
    "user": {
      "id": "uuid",
      "username": "rummyking99",
      "referral_code": "KG99XY12"
    },
    "access_token": "eyJ...",
    "refresh_token": "eyJ...",
    "expires_in": 900
  }
}
```

---

## 3. Game Service API

```
GET    /games/tables           List available tables (filterable)
POST   /games/tables           Create private table
GET    /games/tables/:id       Table details
POST   /games/tables/:id/join  Join a table
POST   /games/tables/:id/leave Leave table
GET    /games/history          User's match history
GET    /games/history/:id      Match detail
GET    /games/active           User's active games
```

### Table List Request
```json
GET /games/tables?type=points_rummy&variant=real_money&entry_fee_min=10&entry_fee_max=100

Response 200:
{
  "data": [
    {
      "id": "table-uuid",
      "table_code": "TBL001",
      "game_type": "points_rummy",
      "max_players": 6,
      "current_players": 3,
      "entry_fee": 50,
      "prize_pool": 250,
      "points_per_coin": 0.10,
      "status": "waiting"
    }
  ],
  "pagination": { "page": 1, "limit": 20, "total": 150 }
}
```

---

## 4. Wallet Service API

```
GET    /wallet                 Get wallet balances
GET    /wallet/transactions    Transaction history (paginated)
POST   /wallet/deposit/init    Initiate deposit, returns payment order
POST   /wallet/deposit/verify  Verify Razorpay payment signature
POST   /wallet/withdraw/init   Request withdrawal
GET    /wallet/withdraw/:id    Withdrawal status
GET    /wallet/limits          Daily limits, KYC restrictions
POST   /wallet/reward/claim    Claim daily/mission rewards
```

### Deposit Init
```json
POST /wallet/deposit/init
{ "amount": 500 }

Response 200:
{
  "data": {
    "order_id": "order_razorpay_xxx",
    "amount": 50000,
    "currency": "INR",
    "key_id": "rzp_live_xxx",
    "prefill": {
      "name": "Rummy King",
      "email": "user@example.com",
      "contact": "+919876543210"
    }
  }
}
```

---

## 5. Matchmaking Service API

```
POST   /matchmaking/join       Join matchmaking queue
DELETE /matchmaking/leave      Leave queue
GET    /matchmaking/status     Current queue status
POST   /matchmaking/private    Create private room invite
POST   /matchmaking/bot        Request bot game (immediate)
```

### Join Queue
```json
POST /matchmaking/join
{
  "game_type": "points_rummy",
  "player_count": 2,
  "entry_fee_range": { "min": 10, "max": 50 }
}

Response 200:
{
  "data": {
    "queue_position": 3,
    "estimated_wait_secs": 15,
    "queue_id": "queue-uuid"
  }
}
```

---

## 6. Tournament Service API

```
GET    /tournaments                    List tournaments
GET    /tournaments/:id                Tournament details
POST   /tournaments/:id/register       Register for tournament
DELETE /tournaments/:id/register       Unregister
GET    /tournaments/:id/bracket        Bracket/standings
GET    /tournaments/:id/matches        Tournament matches
GET    /tournaments/my                 User's registered tournaments
```

---

## 7. Leaderboard Service API

```
GET    /leaderboard?period=daily       Daily leaderboard (top 100)
GET    /leaderboard?period=weekly
GET    /leaderboard?period=monthly
GET    /leaderboard?period=all_time
GET    /leaderboard/rank               User's current rank
GET    /leaderboard/friends            Friends leaderboard
```

---

## 8. Social Service API

```
GET    /social/friends                 Friend list
POST   /social/friends/request         Send friend request
PATCH  /social/friends/:id/respond     Accept/reject request
DELETE /social/friends/:id             Remove friend
GET    /social/teams                   Browse teams
POST   /social/teams                   Create team
PATCH  /social/teams/:id               Update team
POST   /social/teams/:id/join          Join request
POST   /social/teams/:id/invite        Invite user
DELETE /social/teams/:id/leave         Leave team
```

---

## 9. API Gateway Configuration (NestJS)

```typescript
// apps/api-gateway/src/main.ts
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import helmet from 'helmet';
import * as compression from 'compression';
import { ValidationPipe } from '@nestjs/common';
import rateLimit from 'express-rate-limit';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  app.use(helmet());
  app.use(compression());
  app.enableCors({
    origin: process.env.ALLOWED_ORIGINS?.split(','),
    credentials: true,
  });

  // Global rate limiting
  app.use(
    rateLimit({
      windowMs: 60 * 1000,
      max: 100,
      keyGenerator: (req) => req.headers['x-device-id'] || req.ip,
    }),
  );

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  await app.listen(3000);
}
bootstrap();
```

---

## 10. Standard Response Format

```typescript
// All API responses follow this envelope
interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: {
    code: string;           // ERROR_CODE for client-side handling
    message: string;        // Human-readable
    details?: any;          // Validation errors array
  };
  pagination?: {
    page: number;
    limit: number;
    total: number;
    has_next: boolean;
  };
  meta?: {
    request_id: string;     // For support/debugging
    server_time: string;    // ISO timestamp
    version: string;
  };
}
```

---

## 11. Error Code Registry

```
AUTH_001  Invalid credentials
AUTH_002  OTP expired
AUTH_003  OTP invalid
AUTH_004  Account suspended
AUTH_005  JWT expired
AUTH_006  JWT invalid
AUTH_007  Device not recognized

WALLET_001  Insufficient balance
WALLET_002  Below minimum withdrawal
WALLET_003  KYC not verified
WALLET_004  Daily limit exceeded
WALLET_005  Wallet frozen
WALLET_006  Payment verification failed

GAME_001   Table full
GAME_002   Table not found
GAME_003   Game already started
GAME_004   Not your turn
GAME_005   Invalid move
GAME_006   Invalid declaration

MATCH_001  Already in queue
MATCH_002  Not in queue
MATCH_003  Entry fee insufficient

GENERAL_001  Rate limit exceeded
GENERAL_002  Validation failed
GENERAL_003  Server error
GENERAL_004  Service unavailable
```

---

## 12. Rate Limiting Tiers

| Endpoint Group          | Window | Limit  | Key         |
|-------------------------|--------|--------|-------------|
| /auth/login             | 1 min  | 5      | IP          |
| /auth/otp/send          | 1 min  | 3      | Phone       |
| /auth/* (other)         | 1 min  | 20     | Device ID   |
| /wallet/withdraw        | 1 hour | 3      | User ID     |
| /wallet/* (other)       | 1 min  | 30     | User ID     |
| /games/*                | 1 min  | 100    | User ID     |
| /matchmaking/*          | 1 min  | 10     | User ID     |
| All other               | 1 min  | 100    | Device ID   |
