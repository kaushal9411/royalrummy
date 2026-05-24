# Lakadiya (Callbreak) — Production Multiplayer Card Game

A production-ready, real-time multiplayer Callbreak (Lakadi) card game platform.

## Architecture Overview

```
lakadiya/
├── backend/          # Node.js + Express + Socket.IO
├── mobile/           # Flutter (Android + iOS)
├── admin/            # Next.js Admin Panel
└── database/         # PostgreSQL migrations & seeds
```

## Tech Stack

| Layer       | Technology                                |
|-------------|-------------------------------------------|
| Mobile      | Flutter 3.x, Dart, flutter_bloc, go_router |
| Backend     | Node.js, Express.js, Socket.IO            |
| Database    | PostgreSQL 15                              |
| Cache       | Redis 7                                   |
| Auth        | JWT + Google OAuth                        |
| Admin       | Next.js 14, TypeScript, Tailwind CSS      |

## Game Rules

- **Players**: 4 (human or AI bot)
- **Deck**: Standard 52-card deck, 13 cards each
- **Trump**: Spades (♠) always trump
- **Rounds**: 5 rounds per match
- **Card Rank**: A > K > Q > J > 10 > 9 > 8 > 7 > 6 > 5 > 4 > 3 > 2
- **Scoring**:
  - Exact bid: `score = bid`
  - Overtrick: `score = bid + (overtricks × 0.1)`
  - Failed bid: `score = -bid`

## Quick Start

### Backend
```bash
cd backend
cp .env.example .env
npm install
npm run migrate
npm run dev
```

### Admin Panel
```bash
cd admin
npm install
npm run dev
```

### Flutter App
```bash
cd mobile
flutter pub get
flutter run
```

## Environment Variables

See `backend/.env.example` for all required variables.

## Folder Structure

See individual README files inside each sub-project for detailed documentation.
