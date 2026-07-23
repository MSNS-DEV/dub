# ============================================
# Dockerfile for Dub.co on Railway
# ============================================
# Multi-stage build optimized for Railway monorepo
# ============================================

# ---- Stage 1: Build & Install ----
FROM node:20-alpine AS builder
RUN apk add --no-cache libc6-compat openssl
WORKDIR /app

RUN corepack enable && corepack prepare pnpm@latest --activate

# Copy all repository source files
COPY . .

# Install all workspace dependencies
RUN pnpm install --frozen-lockfile

# Generate Prisma Client (doesn't require DB connection)
WORKDIR /app/apps/web
RUN pnpm exec prisma generate --schema=./prisma/schema

# Build shared workspace packages first, then the web app
WORKDIR /app
RUN pnpm build:packages || true
RUN pnpm --filter web build

# ---- Stage 2: Production Runner ----
FROM node:20-alpine AS runner
RUN apk add --no-cache libc6-compat openssl curl
WORKDIR /app

ENV NODE_ENV=production
ENV HOSTNAME="0.0.0.0"
ENV PORT=3000

# Create non-root user
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Copy standalone output from builder
COPY --from=builder /app/apps/web/.next/standalone ./
COPY --from=builder /app/apps/web/.next/static ./apps/web/.next/static
COPY --from=builder /app/apps/web/public ./apps/web/public

# Copy Prisma schema & generated client for runtime
COPY --from=builder /app/apps/web/prisma ./apps/web/prisma
COPY --from=builder /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=builder /app/node_modules/@prisma ./node_modules/@prisma

USER nextjs

EXPOSE 3000

# Health check endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:3000/api/health || exit 1

CMD ["node", "apps/web/server.js"]
