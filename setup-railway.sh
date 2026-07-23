#!/bin/bash
# ============================================
# Dub.co Railway Deployment Setup Script
# ============================================
# Run this script ONCE after cloning the Dub
# repository to prepare it for Railway deployment.
#
# Usage: bash setup-railway.sh
# ============================================

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Dub.co Railway Deployment Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if we're in the dub repo root
if [ ! -f "package.json" ] || [ ! -d "apps/web" ]; then
  echo "❌ ERROR: Please run this script from the root of the Dub repository."
  echo "   Expected to find package.json and apps/web/ directory."
  exit 1
fi

echo "📁 Detected Dub monorepo root."
echo ""

# Step 1: Copy Railway deployment files
echo "━━ Step 1: Copying deployment files ━━"

# Copy Dockerfile if it doesn't exist
if [ ! -f "Dockerfile" ]; then
  echo "📄 Creating Dockerfile..."
  cat > Dockerfile << 'DOCKERFILE_EOF'
# ============================================
# Dockerfile for Dub.co on Railway
# ============================================
# Multi-stage build optimized for Railway
# ============================================

# ---- Stage 1: Install dependencies ----
FROM node:20-alpine AS deps
RUN apk add --no-cache libc6-compat openssl
WORKDIR /app

RUN corepack enable && corepack prepare pnpm@latest --activate

COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY turbo.json ./
COPY apps/web/package.json ./apps/web/package.json
COPY packages/ ./packages/

RUN pnpm install --frozen-lockfile

# ---- Stage 2: Build ----
FROM node:20-alpine AS builder
RUN apk add --no-cache libc6-compat openssl
WORKDIR /app

RUN corepack enable && corepack prepare pnpm@latest --activate

COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/apps/web/node_modules ./apps/web/node_modules
COPY . .

WORKDIR /app/apps/web
RUN pnpm run prisma:generate

WORKDIR /app
RUN pnpm --filter web build

# ---- Stage 3: Run ----
FROM node:20-alpine AS runner
RUN apk add --no-cache libc6-compat openssl curl
WORKDIR /app

ENV NODE_ENV=production
ENV HOSTNAME="0.0.0.0"
ENV PORT=3000

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

COPY --from=builder /app/apps/web/.next/standalone ./
COPY --from=builder /app/apps/web/.next/static ./apps/web/.next/static
COPY --from=builder /app/apps/web/public ./apps/web/public
COPY --from=builder /app/apps/web/prisma ./apps/web/prisma
COPY --from=builder /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=builder /app/node_modules/@prisma ./node_modules/@prisma

USER nextjs
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:3000/api/health || exit 1

CMD ["node", "apps/web/server.js"]
DOCKERFILE_EOF
  echo "   ✅ Dockerfile created"
else
  echo "   ⏭️  Dockerfile already exists, skipping."
fi

# Copy railway.toml if it doesn't exist
if [ ! -f "railway.toml" ]; then
  echo "📄 Creating railway.toml..."
  cat > railway.toml << 'TOML_EOF'
[build]
dockerfilePath = "Dockerfile"

[deploy]
healthcheckPath = "/api/health"
healthcheckTimeout = 300
restartPolicyType = "ON_FAILURE"
restartPolicyMaxRetries = 5
numReplicas = 1
TOML_EOF
  echo "   ✅ railway.toml created"
else
  echo "   ⏭️  railway.toml already exists, skipping."
fi

echo ""

# Step 2: Modify Next.js config for standalone output
echo "━━ Step 2: Checking Next.js standalone config ━━"

NEXT_CONFIG="apps/web/next.config.ts"
if [ -f "$NEXT_CONFIG" ]; then
  if grep -q "output.*standalone" "$NEXT_CONFIG" 2>/dev/null; then
    echo "   ✅ Next.js standalone output already configured"
  else
    echo "   ⚠️  You need to add 'output: \"standalone\"' to your next.config.ts"
    echo "   Add this inside the nextConfig object in $NEXT_CONFIG:"
    echo ""
    echo '   output: "standalone",'
    echo ""
    echo "   This is REQUIRED for Railway deployment."
  fi
else
  echo "   ⚠️  next.config.ts not found at expected path: $NEXT_CONFIG"
fi

echo ""

# Step 3: Remove Vercel-specific files
echo "━━ Step 3: Removing Vercel-specific files ━━"

if [ -f "apps/web/vercel.json" ]; then
  rm apps/web/vercel.json
  echo "   ✅ Removed apps/web/vercel.json"
else
  echo "   ⏭️  apps/web/vercel.json not found, skipping."
fi

echo ""

# Step 4: Generate secrets
echo "━━ Step 4: Generating secrets ━━"

NEXTAUTH_SECRET=$(node -e "console.log(require('crypto').randomBytes(32).toString('base64'))" 2>/dev/null || echo "PLEASE_GENERATE_MANUALLY")
CRON_SECRET=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))" 2>/dev/null || echo "PLEASE_GENERATE_MANUALLY")
ENCRYPTION_KEY=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))" 2>/dev/null || echo "PLEASE_GENERATE_MANUALLY")

echo "   Generated secrets (save these for Railway environment variables):"
echo ""
echo "   NEXTAUTH_SECRET=$NEXTAUTH_SECRET"
echo "   CRON_SECRET=$CRON_SECRET"
echo "   ENCRYPTION_KEY=$ENCRYPTION_KEY"
echo ""

# Step 5: Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo ""
echo "  1. Add 'output: \"standalone\"' to apps/web/next.config.ts"
echo "  2. Commit and push changes to GitHub"
echo "  3. In Railway: Create new project from your GitHub repo"
echo "  4. In Railway: Add a MySQL database service"
echo "  5. In Railway: Set all environment variables (see .env.railway)"
echo "  6. In Railway: Deploy!"
echo ""
echo "  📖 See the full guide: DEPLOYMENT_GUIDE.md"
echo ""
