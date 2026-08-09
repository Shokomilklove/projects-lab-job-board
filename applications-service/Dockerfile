# ── Stage 1: install production dependencies ──────────────────
FROM node:20-alpine@sha256:fb4cd12c85ee03686f6af5362a0b0d56d50c58a04632e6c0fb8363f609372293 AS deps

WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev

# ── Stage 2: lean runtime image ───────────────────────────────
FROM node:20-alpine

LABEL maintainer="DevSecOps Lab"
LABEL service="applications-service"

RUN apk update && apk upgrade --no-cache && \
    addgroup -S appgroup && adduser -S appuser -G appgroup && \
    apk add --no-cache curl
    

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY src/ ./src/
COPY package.json ./

RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE 3001

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:3001/health || exit 1

CMD ["node", "src/index.js"]
