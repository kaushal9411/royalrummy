# System Architecture — RummyRoyale

## 1. High-Level Architecture

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                              CLOUDFLARE CDN / WAF                               │
└──────────────────────────────────┬───────────────────────────────────────────────┘
                                   │
┌──────────────────────────────────▼───────────────────────────────────────────────┐
│                         NGINX LOAD BALANCER (Layer 7)                           │
│              SSL Termination │ WebSocket Upgrade │ Rate Limiting                │
└─────┬──────────────┬─────────────────┬─────────────────┬────────────────────────┘
      │              │                 │                 │
   REST API     WebSocket         Admin API          Static Assets
      │              │                 │                 │
┌─────▼──────────────▼─────────────────▼─────────────────▼────────────────────────┐
│                         API GATEWAY SERVICE                                     │
│    NestJS Gateway  │  JWT Validation  │  Request Routing  │  Circuit Breaker   │
└─────┬──────────────┬─────────────────┬────────────────────┬─────────────────────┘
      │              │                 │                    │
 ┌────▼────┐   ┌─────▼────┐   ┌────────▼───────┐   ┌──────▼──────┐
 │  Auth   │   │  Game    │   │    Wallet      │   │  Tournament │
 │ Service │   │ Service  │   │   Service      │   │   Service   │
 └────┬────┘   └──────────┘   └────────────────┘   └─────────────┘
      │
 ┌────▼──────────────────────────────────────────────────────────────────────────┐
 │                     MESSAGE BROKER — Redis Pub/Sub + Bull                    │
 │    matchmaking.queue │ notification.queue │ analytics.queue │ reward.queue  │
 └────────────────────────────────┬──────────────────────────────────────────────┘
                                  │
 ┌────────────────────────────────▼──────────────────────────────────────────────┐
 │                            DATA LAYER                                        │
 │  ┌──────────────────┐  ┌───────────────────┐  ┌─────────────────────────┐   │
 │  │  PostgreSQL 15   │  │   Redis Cluster   │  │  Firebase (FCM + Auth)  │   │
 │  │  Primary + 2     │  │  3-node + Sentinel│  │  Crashlytics + Analytics│   │
 │  │  Read Replicas   │  │  Cache + PubSub   │  │  Remote Config          │   │
 │  └──────────────────┘  └───────────────────┘  └─────────────────────────┘   │
 └───────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Microservices Map

| Service              | Port  | Responsibility                                    |
|----------------------|-------|---------------------------------------------------|
| api-gateway          | 3000  | Auth, routing, rate limiting, circuit breaker     |
| auth-service         | 3001  | Registration, login, JWT, device binding          |
| game-service         | 3002  | Rummy engine, game state, WebSocket rooms         |
| wallet-service       | 3003  | Ledger, transactions, payment gateway             |
| matchmaking-service  | 3004  | Queue, ELO matching, table creation               |
| tournament-service   | 3005  | Brackets, scheduling, prize distribution          |
| notification-service | 3006  | FCM push, email (SES), in-app                    |
| analytics-service    | 3007  | Event ingestion, reports, funnels                 |
| bot-service          | 3008  | AI bots, decision engine, dynamic scaling         |
| admin-service        | 3009  | Admin CRUD, KYC, fraud, CMS                       |

---

## 3. Service Communication Patterns

### Synchronous (HTTP/gRPC)
- Client → API Gateway → Microservice
- Auth validation on every request
- Circuit breaker with exponential backoff

### Asynchronous (Bull/Redis Queue)
```
[Game Service] ──publish──► [notification.queue] ──consume──► [Notification Service]
[Wallet Service] ──publish──► [analytics.queue] ──consume──► [Analytics Service]
[Matchmaking] ──publish──► [game.queue] ──consume──► [Game Service]
```

### Real-time (Socket.IO + Redis Adapter)
```
[Flutter Client] ◄──WSS──► [Game Service Node 1]
                                    │ Redis Pub/Sub
[Flutter Client] ◄──WSS──► [Game Service Node 2]
```

---

## 4. Infrastructure Topology

```
AWS Region: ap-south-1 (Mumbai)
│
├── VPC (10.0.0.0/16)
│   ├── Public Subnets (10.0.1.0/24, 10.0.2.0/24)
│   │   └── NGINX ALB, Cloudflare Tunnel
│   │
│   ├── Private Subnets (10.0.10.0/24, 10.0.11.0/24)
│   │   ├── EKS Worker Nodes (t3.xlarge × 10)
│   │   └── Game Server Nodes (c5.2xlarge × 5) — dedicated for WebSockets
│   │
│   └── Data Subnets (10.0.20.0/24, 10.0.21.0/24)
│       ├── RDS PostgreSQL (db.r6g.2xlarge, Multi-AZ)
│       └── ElastiCache Redis (cache.r6g.xlarge × 3 cluster)
│
├── S3 Buckets
│   ├── rummy-assets (avatars, card images, sounds)
│   └── rummy-backups (daily DB snapshots)
│
└── CloudFront → S3 (static asset CDN)
```

---

## 5. Horizontal Scaling Strategy

### API Services (Stateless)
- Kubernetes HPA: min 2, max 20 pods per service
- CPU threshold: 70%, Memory: 80%
- Rolling deployments, zero-downtime

### Game Service (Stateful WebSockets)
- Redis Socket.IO adapter for multi-node broadcasting
- Sticky sessions via NGINX `ip_hash`
- Room state stored in Redis (not in-memory)
- Node can die without losing game state

### Database
- Primary handles writes
- 2 read replicas handle all read queries
- Connection pooling via PgBouncer (max 500 per node)
- Redis caches leaderboards, active tables, user sessions

---

## 6. Technology Decision Records

### Why NestJS over Express?
- Built-in DI container — essential for microservices
- First-class TypeScript support
- Decorators-based architecture mirrors enterprise patterns
- WebSocket gateway built-in
- Easier testing with module isolation

### Why PostgreSQL over MongoDB?
- ACID transactions critical for wallet operations
- Complex relational queries (leaderboards, tournament brackets)
- Row-level locking for concurrent game operations
- Partitioning support for match history at scale

### Why Flutter?
- Single codebase for Android + iOS
- 60/120fps rendering via Skia engine
- Native-equivalent performance for card animations
- Strong Dart ecosystem for game logic

### Why Redis Pub/Sub for WebSockets?
- Horizontal WebSocket scaling without shared memory
- O(1) message fan-out to all nodes
- TTL-based game state expiry
- Atomic operations (INCR, SETNX) for matchmaking locks

---

## 7. Failure Modes & Mitigation

| Failure                      | Detection              | Mitigation                          |
|------------------------------|------------------------|-------------------------------------|
| Game server crash            | K8s liveness probe     | Auto-restart, Redis state recovery  |
| DB primary failure           | RDS Multi-AZ           | Automatic failover < 60s            |
| Redis node failure           | Redis Sentinel         | Automatic promotion of replica      |
| Payment gateway timeout      | Circuit breaker        | Queue retry, user notification      |
| WebSocket disconnection      | Client heartbeat       | Auto-rejoin with state sync         |
| Matchmaking queue overflow   | Queue depth metric     | Spawn extra bot players             |
| DDoS attack                  | Cloudflare WAF         | IP block, rate limit, CAPTCHA       |

---

## 8. Observability Stack

```
Application Logs → Fluentd → Elasticsearch → Kibana (log analysis)
Metrics → Prometheus → Grafana (dashboards, alerts)
Traces → Jaeger (distributed tracing per request)
Errors → Sentry (error tracking + stack traces)
Uptime → Pingdom / AWS CloudWatch
```

### Key Metrics to Monitor
- WebSocket connections per second
- Game rooms active count
- Matchmaking queue depth
- Wallet transaction TPS
- API p99 latency per service
- Redis memory usage
- PostgreSQL slow queries
- Bot pool utilization
