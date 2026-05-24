# RummyRoyale — Enterprise Multiplayer Card Gaming Platform

> A production-ready, massively scalable real-money style multiplayer card gaming ecosystem.

---

## Platform Overview

RummyRoyale is a full-stack, mobile-first gaming platform supporting real-time multiplayer Rummy
in all variants, AI bot games, tournaments, wallet economy, referral engine, team/clan system,
and a complete admin ecosystem — built to enterprise-grade standards.

---

## Architecture at a Glance

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        CLIENT LAYER                                     │
│  ┌──────────────────┐          ┌─────────────────────────────────────┐  │
│  │  Flutter Mobile  │          │     Next.js Admin Dashboard         │  │
│  │  (Android/iOS)   │          │     (Web + CMS + Analytics)         │  │
│  └────────┬─────────┘          └──────────────┬──────────────────────┘  │
└───────────┼──────────────────────────────────-┼─────────────────────────┘
            │ HTTPS / WSS                        │ HTTPS
┌───────────▼──────────────────────────────────-▼─────────────────────────┐
│                     API GATEWAY (NestJS + NGINX)                        │
│          Rate Limiting │ Auth Middleware │ Load Balancing               │
└──────┬────────┬────────┬────────┬────────┬────────┬──────────┬──────────┘
       │        │        │        │        │        │          │
┌──────▼─┐ ┌───▼──┐ ┌───▼──┐ ┌──▼───┐ ┌──▼──┐ ┌───▼──┐ ┌────▼────┐
│  Auth  │ │ Game │ │Wallet│ │Match │ │Tour │ │Notif │ │Analytics│
│Service │ │Svc   │ │ Svc  │ │making│ │nament│ │ Svc  │ │  Svc    │
└──────┬─┘ └──┬───┘ └──┬───┘ └──┬───┘ └──┬──┘ └───┬──┘ └────┬────┘
       │       │        │        │        │        │          │
┌──────▼───────▼────────▼────────▼────────▼────────▼──────────▼──────────┐
│                    DATA & MESSAGING LAYER                               │
│  PostgreSQL (Primary)  │  Redis Cluster  │  Bull Queues  │  Firebase   │
│  Read Replicas         │  Pub/Sub        │  Job Workers  │  FCM/FCB    │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Tech Stack

| Layer           | Technology                                          |
|-----------------|-----------------------------------------------------|
| Mobile          | Flutter 3.x, Dart, Kotlin (native modules)          |
| Admin Web       | Next.js 14, TypeScript, TailwindCSS, React Query    |
| Backend         | Node.js + Express.js, Microservices architecture   |
| Realtime        | Socket.IO, Redis Pub/Sub, WebSockets                |
| Database        | PostgreSQL 15, Redis 7                              |
| Auth            | JWT, Refresh Tokens, Device Binding                 |
| Payments        | Razorpay, Stripe                                    |
| Push            | Firebase FCM                                        |
| Infrastructure  | Docker, Kubernetes, NGINX, AWS/GCP                  |
| CI/CD           | GitHub Actions, Docker Hub                          |
| Monitoring      | Prometheus, Grafana, ELK Stack                      |
| CDN             | Cloudflare                                          |

---

## Project Structure

```
OwnProject/
├── mobile/                    # Flutter mobile application
│   ├── lib/
│   │   ├── core/             # App-wide core (DI, network, storage, theme)
│   │   ├── features/         # Feature modules (auth, game, wallet, ...)
│   │   └── shared/           # Reusable widgets, models, services
│   ├── android/              # Android native modules (Kotlin)
│   ├── ios/
│   └── pubspec.yaml
│
├── backend/                   # NestJS microservices monorepo
│   ├── apps/
│   │   ├── api-gateway/      # Main entry point, routing, rate limiting
│   │   ├── auth-service/     # JWT, OAuth, device management
│   │   ├── game-service/     # Rummy engine, game state, WebSockets
│   │   ├── wallet-service/   # Transactions, ledger, payments
│   │   ├── matchmaking-service/  # Queue-based matchmaking
│   │   ├── tournament-service/   # Tournament lifecycle
│   │   ├── notification-service/ # FCM, email, SMS
│   │   ├── analytics-service/    # Event tracking, reports
│   │   ├── bot-service/          # AI bot engine
│   │   └── admin-service/        # Admin panel APIs
│   └── libs/
│       ├── common/           # Shared DTOs, guards, decorators
│       ├── database/         # TypeORM entities, migrations
│       ├── redis/            # Cache, pub/sub helpers
│       ├── firebase/         # Firebase admin SDK
│       └── queue/            # Bull queue definitions
│
├── admin/                     # Next.js admin dashboard
│   └── src/
│       ├── components/
│       ├── pages/
│       └── store/
│
├── infrastructure/            # DevOps & deployment
│   ├── docker/               # Dockerfiles per service
│   ├── kubernetes/           # K8s manifests
│   ├── terraform/            # IaC for AWS/GCP
│   ├── nginx/                # NGINX config
│   └── monitoring/           # Prometheus, Grafana configs
│
├── docs/                      # Architecture documentation
│   ├── 01-system-architecture.md
│   ├── 02-database-schema.md
│   ├── 03-api-architecture.md
│   ├── 04-websocket-architecture.md
│   ├── 05-wallet-system.md
│   ├── 06-game-engine.md
│   ├── 07-ai-bot-system.md
│   ├── 08-security.md
│   ├── 09-devops.md
│   ├── 10-firebase-integration.md
│   ├── 11-analytics-monetization.md
│   ├── 12-admin-panel.md
│   ├── 13-development-roadmap.md
│   └── 14-cost-estimation.md
│
└── scripts/                   # Utility scripts
    ├── db/
    ├── deploy/
    └── seed/
```

---

## Quick Links

- [System Architecture](docs/01-system-architecture.md)
- [Database Schema](docs/02-database-schema.md)
- [API Architecture](docs/03-api-architecture.md)
- [WebSocket Architecture](docs/04-websocket-architecture.md)
- [Wallet System](docs/05-wallet-system.md)
- [Game Engine](docs/06-game-engine.md)
- [AI Bot System](docs/07-ai-bot-system.md)
- [Security](docs/08-security.md)
- [DevOps](docs/09-devops.md)
- [Development Roadmap](docs/13-development-roadmap.md)

---

## Performance Targets

| Metric                    | Target       |
|---------------------------|--------------|
| Registered Users          | 1M+          |
| Concurrent Users          | 100K+        |
| API Response Time (p99)   | < 200ms      |
| WebSocket Latency         | < 50ms       |
| Uptime SLA                | 99.95%       |
| Game State Sync Freq      | 10 fps       |
| DB Queries (p99)          | < 50ms       |

---

*Built with enterprise gaming industry standards. See docs/ for full specifications.*
