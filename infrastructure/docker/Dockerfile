# Multi-stage Node.js Dockerfile for all backend services
ARG SERVICE=api-gateway

FROM node:20-alpine AS base
WORKDIR /app

# Install dependencies first (caching layer)
COPY package*.json ./
RUN npm ci --only=production && npm cache clean --force

# Copy source
COPY . .

FROM base AS runtime
ARG SERVICE
ENV NODE_ENV=production
ENV SERVICE_NAME=${SERVICE}

# Create non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
RUN chown -R appuser:appgroup /app
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD wget -qO- http://localhost:${PORT:-3000}/health || exit 1

EXPOSE ${PORT:-3000}

CMD ["node", "apps/${SERVICE}/src/index.js"]
