# DevOps & Deployment — RummyRoyale

## 1. Production Infrastructure (AWS)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        AWS ap-south-1 (Mumbai)                             │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                  Cloudflare (DNS + WAF + CDN)                        │  │
│  └──────────────────────────────┬────────────────────────────────────────┘  │
│                                 │                                           │
│  ┌──────────────────────────────▼────────────────────────────────────────┐  │
│  │                    VPC (10.0.0.0/16)                                 │  │
│  │                                                                       │  │
│  │  Public Subnets (Multi-AZ):                                          │  │
│  │  ┌──────────────────────────────────────────────────────────────┐    │  │
│  │  │  Application Load Balancer  │  NAT Gateway  │  Bastion Host  │    │  │
│  │  └──────────────────────────────────────────────────────────────┘    │  │
│  │                                                                       │  │
│  │  Private Subnets (Compute):                                          │  │
│  │  ┌──────────────────────────────────────────────────────────────┐    │  │
│  │  │           EKS Cluster (Kubernetes 1.28)                     │    │  │
│  │  │  ┌────────────┐  ┌────────────┐  ┌────────────────────────┐  │    │  │
│  │  │  │ App Node   │  │ App Node   │  │  Game Socket Nodes     │  │    │  │
│  │  │  │ Group      │  │ Group      │  │  (c5.2xlarge × 5)      │  │    │  │
│  │  │  │ t3.xlarge  │  │ t3.xlarge  │  │  High memory, WebSocket│  │    │  │
│  │  │  │ ×8 pods    │  │ ×8 pods    │  │  optimized             │  │    │  │
│  │  │  └────────────┘  └────────────┘  └────────────────────────┘  │    │  │
│  │  └──────────────────────────────────────────────────────────────┘    │  │
│  │                                                                       │  │
│  │  Data Subnets:                                                       │  │
│  │  ┌────────────────────────────────────────────────────────────┐      │  │
│  │  │  RDS PostgreSQL (db.r6g.2xlarge, Multi-AZ)                │      │  │
│  │  │  ElastiCache Redis (cache.r6g.xlarge, 3-node cluster)     │      │  │
│  │  └────────────────────────────────────────────────────────────┘      │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  S3: rummy-assets, rummy-backups, rummy-logs                               │
│  CloudFront: static assets CDN                                             │
│  Route53: DNS management                                                   │
│  ACM: SSL certificates                                                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Docker Configuration

### API Gateway Dockerfile
```dockerfile
# infrastructure/docker/api-gateway.Dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
COPY tsconfig*.json ./
RUN npm ci --only=production
COPY . .
RUN npm run build:api-gateway

FROM node:20-alpine AS runtime
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
USER appuser
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s \
  CMD wget -qO- http://localhost:3000/health || exit 1
CMD ["node", "dist/apps/api-gateway/main"]
```

### Docker Compose (Development)
```yaml
# docker-compose.yml
version: '3.9'

services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: rummyroyale
      POSTGRES_USER: rummy_user
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./scripts/db/init.sql:/docker-entrypoint-initdb.d/init.sql
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U rummy_user -d rummyroyale"]
      interval: 10s

  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes --requirepass ${REDIS_PASSWORD}
    volumes:
      - redis_data:/data
    ports:
      - "6379:6379"

  api-gateway:
    build:
      context: ./backend
      dockerfile: ../infrastructure/docker/api-gateway.Dockerfile
    ports:
      - "3000:3000"
    environment:
      DATABASE_URL: postgresql://rummy_user:${DB_PASSWORD}@postgres:5432/rummyroyale
      REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379
      JWT_SECRET: ${JWT_SECRET}
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_started

  game-service:
    build:
      context: ./backend
      dockerfile: ../infrastructure/docker/game-service.Dockerfile
    ports:
      - "3002:3002"
    environment:
      REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379
      DATABASE_URL: postgresql://rummy_user:${DB_PASSWORD}@postgres:5432/rummyroyale
    depends_on:
      - redis
      - postgres

volumes:
  postgres_data:
  redis_data:
```

---

## 3. Kubernetes Manifests

### Deployment: Game Service
```yaml
# infrastructure/kubernetes/deployments/game-service.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: game-service
  namespace: rummy-prod
  labels:
    app: game-service
    version: v1
spec:
  replicas: 5
  selector:
    matchLabels:
      app: game-service
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 2
  template:
    metadata:
      labels:
        app: game-service
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9090"
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                  - key: app
                    operator: In
                    values: [game-service]
              topologyKey: kubernetes.io/hostname
      containers:
        - name: game-service
          image: rummyroyale/game-service:latest
          ports:
            - containerPort: 3002
              name: http
            - containerPort: 9090
              name: metrics
          env:
            - name: NODE_ENV
              value: "production"
            - name: REDIS_URL
              valueFrom:
                secretKeyRef:
                  name: rummy-secrets
                  key: redis-url
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: rummy-secrets
                  key: database-url
          resources:
            requests:
              memory: "512Mi"
              cpu: "500m"
            limits:
              memory: "1Gi"
              cpu: "1000m"
          livenessProbe:
            httpGet:
              path: /health
              port: 3002
            initialDelaySeconds: 30
            periodSeconds: 15
          readinessProbe:
            httpGet:
              path: /health/ready
              port: 3002
            initialDelaySeconds: 10
            periodSeconds: 5
```

### HPA: Auto-scaling
```yaml
# infrastructure/kubernetes/hpa/game-service-hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: game-service-hpa
  namespace: rummy-prod
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: game-service
  minReplicas: 5
  maxReplicas: 30
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
    - type: Pods
      pods:
        metric:
          name: websocket_connections_per_pod
        target:
          type: AverageValue
          averageValue: "4000"  # Scale when avg > 4000 WS connections
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
        - type: Pods
          value: 3
          periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Pods
          value: 1
          periodSeconds: 120
```

---

## 4. NGINX Configuration

```nginx
# infrastructure/nginx/nginx.conf
upstream api_gateway {
    least_conn;
    server api-gateway-1:3000;
    server api-gateway-2:3000;
    server api-gateway-3:3000;
    keepalive 32;
}

upstream game_service {
    ip_hash;  # Sticky sessions for WebSockets
    server game-service-1:3002;
    server game-service-2:3002;
    server game-service-3:3002;
    server game-service-4:3002;
    server game-service-5:3002;
    keepalive 64;
}

server {
    listen 443 ssl http2;
    server_name api.rummyroyale.com;

    ssl_certificate /etc/ssl/certs/rummy.crt;
    ssl_certificate_key /etc/ssl/private/rummy.key;
    ssl_protocols TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header Referrer-Policy strict-origin-when-cross-origin;

    # REST API
    location /v1/ {
        proxy_pass http://api_gateway;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_connect_timeout 10s;
        proxy_read_timeout 30s;
        proxy_send_timeout 30s;
    }

    # WebSocket connections
    location /socket.io/ {
        proxy_pass http://game_service;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 3600s;  # Long timeout for WS
        proxy_send_timeout 3600s;
    }
}
```

---

## 5. CI/CD Pipeline (GitHub Actions)

```yaml
# .github/workflows/deploy-production.yml
name: Deploy to Production

on:
  push:
    branches: [main]
    paths:
      - 'backend/**'

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
      redis:
        image: redis:7
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci
      - run: npm run test:all
        env:
          DATABASE_URL: postgresql://postgres:test@localhost:5432/test
          REDIS_URL: redis://localhost:6379

  security-scan:
    runs-on: ubuntu-latest
    needs: test
    steps:
      - uses: actions/checkout@v4
      - name: Run Snyk security scan
        uses: snyk/actions/node@master
        env:
          SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
      - name: Run Trivy image scan
        uses: aquasecurity/trivy-action@master

  build-and-push:
    runs-on: ubuntu-latest
    needs: [test, security-scan]
    strategy:
      matrix:
        service: [api-gateway, game-service, wallet-service, matchmaking-service]
    steps:
      - uses: actions/checkout@v4
      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: ./backend
          file: ./infrastructure/docker/${{ matrix.service }}.Dockerfile
          push: true
          tags: |
            rummyroyale/${{ matrix.service }}:${{ github.sha }}
            rummyroyale/${{ matrix.service }}:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max

  deploy:
    runs-on: ubuntu-latest
    needs: build-and-push
    environment: production
    steps:
      - name: Deploy to EKS
        run: |
          aws eks update-kubeconfig --name rummy-prod --region ap-south-1
          kubectl set image deployment/game-service \
            game-service=rummyroyale/game-service:${{ github.sha }} \
            -n rummy-prod
          kubectl rollout status deployment/game-service -n rummy-prod --timeout=5m

      - name: Notify Slack
        if: always()
        uses: 8398a7/action-slack@v3
        with:
          status: ${{ job.status }}
          text: "Deployment ${{ job.status }} for ${{ github.sha }}"
```

---

## 6. Monitoring Stack

```yaml
# infrastructure/monitoring/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'game-service'
    static_configs:
      - targets: ['game-service:9090']
    metrics_path: '/metrics'

  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres-exporter:9187']

  - job_name: 'redis'
    static_configs:
      - targets: ['redis-exporter:9121']

  - job_name: 'nginx'
    static_configs:
      - targets: ['nginx-exporter:9113']
```

### Key Grafana Dashboards
```
Dashboard 1: Platform Health
  - Total active WebSocket connections
  - API request rate (req/s)
  - API error rate (%)
  - Active game tables count
  - Matchmaking queue depth

Dashboard 2: Game Metrics
  - Games started per minute
  - Average game duration
  - Drop rate per game type
  - Bot vs human ratio

Dashboard 3: Wallet & Revenue
  - Deposits last 24h (₹)
  - Withdrawals last 24h (₹)
  - Active wallet TPS
  - Failed transactions count

Dashboard 4: Infrastructure
  - CPU per pod
  - Memory per pod
  - DB connection pool usage
  - Redis memory + hit rate
  - Network I/O
```

---

## 7. Backup & Disaster Recovery

```bash
# scripts/db/backup.sh — runs daily via K8s CronJob
#!/bin/bash
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="rummy_backup_${TIMESTAMP}.sql.gz"

pg_dump $DATABASE_URL | gzip > /tmp/$BACKUP_FILE

# Upload to S3 with server-side encryption
aws s3 cp /tmp/$BACKUP_FILE \
  s3://rummy-backups/daily/$BACKUP_FILE \
  --server-side-encryption AES256

# Keep only last 30 days
aws s3 ls s3://rummy-backups/daily/ | \
  awk '{print $4}' | \
  head -n -30 | \
  xargs -I {} aws s3 rm s3://rummy-backups/daily/{}
```

### RTO/RPO Targets
| Scenario          | RTO    | RPO    | Strategy                          |
|-------------------|--------|--------|-----------------------------------|
| Pod crash         | < 30s  | 0      | K8s auto-restart                  |
| Node failure      | < 2min | 0      | K8s reschedule + Redis state      |
| DB primary fail   | < 60s  | < 5s   | RDS Multi-AZ failover             |
| Region failure    | < 30m  | < 1h   | S3 restore to standby region      |
| Data corruption   | < 2h   | < 24h  | Point-in-time restore from S3     |

---

## 8. Environment Variables

```bash
# backend/.env.example
NODE_ENV=production
PORT=3000

# Database
DATABASE_URL=postgresql://user:pass@host:5432/rummyroyale
DATABASE_POOL_MIN=5
DATABASE_POOL_MAX=20

# Redis
REDIS_URL=redis://:password@host:6379
REDIS_TLS=true

# JWT
JWT_SECRET=your-256-bit-secret-here
JWT_EXPIRES_IN=900
REFRESH_TOKEN_EXPIRES_IN=2592000

# Firebase
FIREBASE_PROJECT_ID=rummyroyale
FIREBASE_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----...

# Razorpay
RAZORPAY_KEY_ID=rzp_live_xxx
RAZORPAY_KEY_SECRET=xxx
RAZORPAY_WEBHOOK_SECRET=xxx

# AWS
AWS_REGION=ap-south-1
AWS_S3_BUCKET=rummy-assets
AWS_SES_FROM=noreply@rummyroyale.com

# Feature Flags
ENABLE_BOT_AUTOFILL=true
MIN_WAIT_BEFORE_BOT_SECS=30
MAX_BOT_RATIO=0.6

# Limits
MAX_DAILY_WITHDRAWAL_INR=100000
MIN_WITHDRAWAL_INR=100
MAX_DEPOSIT_INR=100000
```
