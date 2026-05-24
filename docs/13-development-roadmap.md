# Development Roadmap — RummyRoyale

## Phase Overview

```
Phase 1 (Months 1-3):   Core Platform MVP
Phase 2 (Months 4-6):   Monetization & Scale
Phase 3 (Months 7-9):   Social & Growth
Phase 4 (Months 10-12): Advanced Features & AI
```

---

## Phase 1: Core Platform MVP (Months 1–3)

### Month 1: Foundation

**Backend Infrastructure**
- [ ] NestJS monorepo setup with TypeScript
- [ ] Docker Compose for local development
- [ ] PostgreSQL schema with all core tables + migrations
- [ ] Redis setup with connection pooling
- [ ] API Gateway with JWT auth middleware
- [ ] Health check endpoints for all services

**Auth Service**
- [ ] Phone OTP registration/login
- [ ] Email registration option
- [ ] JWT + refresh token system
- [ ] Device binding
- [ ] User profile CRUD

**Database**
- [ ] All core table migrations
- [ ] Seed data for development
- [ ] PgBouncer connection pooling setup

**DevOps**
- [ ] GitHub repository + branch strategy (main/develop/feature/*)
- [ ] GitHub Actions CI pipeline (lint, test, build)
- [ ] Docker images for all services
- [ ] Dev/staging environment on AWS

---

### Month 2: Game Engine

**Game Service**
- [ ] Deck management and shuffle algorithm
- [ ] Game state machine (waiting → dealing → in_progress → completed)
- [ ] Points Rummy complete implementation
- [ ] Meld validation engine (sequences, sets, pure/impure)
- [ ] Score calculator
- [ ] Anti-cheat validation layer

**WebSocket System**
- [ ] Socket.IO gateway with Redis adapter
- [ ] Room management (join/leave/rejoin)
- [ ] Turn timer system
- [ ] Reconnection handling with state recovery
- [ ] Full event system (draw, discard, declare, drop)
- [ ] Multi-node WebSocket support

**Matchmaking Service**
- [ ] Queue-based matchmaking for 2-player and 6-player
- [ ] Table auto-creation on match found
- [ ] Entry fee validation before match

---

### Month 3: Wallet & Mobile MVP

**Wallet Service**
- [ ] Wallet CRUD with atomic transactions
- [ ] Redis locking for concurrent operations
- [ ] Transaction ledger
- [ ] Razorpay deposit integration
- [ ] Manual withdrawal request (manual processing initially)
- [ ] Game entry fee deduction + prize credit

**Flutter Mobile App**
- [ ] Clean architecture setup (Riverpod state management)
- [ ] Authentication screens (OTP login)
- [ ] Lobby screen with table list
- [ ] Game screen with card UI
- [ ] Basic wallet screen
- [ ] Push notification integration (Firebase FCM)

**Admin Panel (Basic)**
- [ ] Next.js setup with TailwindCSS
- [ ] User list + basic user detail view
- [ ] Transaction viewer
- [ ] Manual withdrawal processing UI

**Play Store**
- [ ] App signing setup
- [ ] Internal testing track deployment

**Deliverable:** Playable MVP with Points Rummy, real money flow, iOS/Android build

---

## Phase 2: Monetization & Scale (Months 4–6)

### Month 4: More Game Types + Tournaments

**Game Engine Extensions**
- [ ] Pool Rummy 101
- [ ] Pool Rummy 201
- [ ] Deals Rummy (2/3/6 deals)
- [ ] Practice mode (no real money)
- [ ] Private table creation + invite code

**Tournament Service**
- [ ] Tournament creation (admin)
- [ ] Registration + entry fee handling
- [ ] Bracket generation (single elimination)
- [ ] Automated match scheduling
- [ ] Prize distribution engine
- [ ] Tournament leaderboard

**Bot System**
- [ ] Bot user accounts (50 per difficulty level)
- [ ] Beginner bot decision engine
- [ ] Medium bot with probability calculations
- [ ] Auto-fill empty tables after 30s
- [ ] Human behavior simulation (delays, reactions)

---

### Month 5: Social & Referral

**Referral Engine**
- [ ] Referral code generation
- [ ] Dynamic link creation (Firebase)
- [ ] Referral tracking and qualification
- [ ] Referral reward distribution

**Social Features**
- [ ] Friends system (request/accept/block)
- [ ] Friends leaderboard
- [ ] Basic in-game chat

**Notification System**
- [ ] Full FCM integration
- [ ] Notification templates (game, wallet, tournament)
- [ ] In-app notification center
- [ ] Email notifications (AWS SES)

**Daily Rewards**
- [ ] Login streak tracking
- [ ] Streak reward calendar
- [ ] Mission system (daily/weekly)
- [ ] Achievement system

---

### Month 6: Scaling & Admin

**Kubernetes Production**
- [ ] EKS cluster setup
- [ ] All services deployed to K8s
- [ ] HPA configured for all services
- [ ] Redis cluster (3-node)
- [ ] RDS Multi-AZ PostgreSQL
- [ ] Cloudflare WAF configured

**Admin Panel Full**
- [ ] KYC review workflow
- [ ] Fraud event dashboard
- [ ] Revenue reports
- [ ] Live match monitor
- [ ] Push notification campaigns
- [ ] CMS banner management
- [ ] Game configuration panel

**Security Hardening**
- [ ] Root/emulator detection (Kotlin)
- [ ] SSL certificate pinning
- [ ] Rate limiting refined per endpoint
- [ ] Audit logging all sensitive operations

**Deliverable:** Full feature launch on Play Store

---

## Phase 3: Social & Growth (Months 7–9)

### Month 7: Teams & Clan System
- [ ] Team/clan creation and management
- [ ] Clan battle tournaments
- [ ] Team leaderboards
- [ ] Team chat
- [ ] Invite system

### Month 8: Advanced Monetization
- [ ] VIP membership tiers
- [ ] Battle Pass system
- [ ] Token shop (cosmetics)
- [ ] Cashback program
- [ ] Special event tournaments
- [ ] Seasonal leaderboards with prizes

### Month 9: Analytics & A/B Testing
- [ ] BigQuery data warehouse integration
- [ ] Custom analytics dashboard
- [ ] Funnel analysis
- [ ] Cohort retention analysis
- [ ] A/B testing framework
- [ ] Automated fraud ML model (v1)

---

## Phase 4: Advanced Features (Months 10–12)

### Month 10: Live Events & Spectator Mode
- [ ] Spectator mode for final tables
- [ ] Live commentary system
- [ ] Special event tables (celebrity matches)
- [ ] Live event notifications

### Month 11: Pro Bot AI (ML)
- [ ] ML model training for Pro bots
- [ ] ONNX model deployment
- [ ] Bot difficulty auto-adjustment based on player skill

### Month 12: Platform Polish
- [ ] iOS App Store launch
- [ ] Web version (React game client)
- [ ] Performance optimization pass
- [ ] Complete load testing (100K concurrent)
- [ ] Penetration testing
- [ ] Regulatory compliance review

---

## Team Structure Required

| Role                          | Count | Phase   |
|-------------------------------|-------|---------|
| Backend Engineers (NestJS)    | 3-4   | Phase 1 |
| Flutter Mobile Developer      | 2     | Phase 1 |
| DevOps/Cloud Engineer         | 1     | Phase 1 |
| Frontend Engineer (Next.js)   | 1     | Phase 1 |
| QA Engineer                   | 1     | Phase 1 |
| Product Manager               | 1     | Phase 1 |
| Game Designer                 | 1     | Phase 1 |
| ML Engineer (Bot AI)          | 1     | Phase 4 |
| Security Engineer             | 1     | Phase 2 |
| Data Engineer                 | 1     | Phase 3 |

**Total core team:** 12-14 people

---

## Sprint Velocity (2-week sprints)
- Backend: 40-50 story points/sprint/engineer
- Mobile: 30-40 story points/sprint/engineer
- Full feature (backend + mobile + admin): ~2-3 sprints average

---

## Risk Register

| Risk                              | Likelihood | Impact | Mitigation                                   |
|-----------------------------------|-----------|--------|----------------------------------------------|
| Play Store rejection (real money) | High      | High   | Submit under "skill game" category, legal review |
| Payment gateway delays            | Medium    | High   | Apply for Razorpay early (2-4 weeks approval) |
| WebSocket scaling issues          | Low       | High   | Load test from Month 2                       |
| Fraud exploitation at launch      | Medium    | High   | Hard limits, manual review first 30 days    |
| DB performance at scale           | Low       | Medium | Query optimization, read replicas from Phase 2|
| Key engineer departure            | Low       | High   | Documentation, pair programming              |
