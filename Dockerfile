# syntax=docker/dockerfile:1

###############################################################################
# Multi-stage build for the node-hello application.
#   - deps    : installs production-only dependencies from the lockfile
#   - runtime : minimal image running as a non-root user with a HEALTHCHECK
###############################################################################

# ---- Base -------------------------------------------------------------------
FROM node:22-alpine AS base
WORKDIR /app
ENV NODE_ENV=production

# ---- Dependencies -----------------------------------------------------------
# Reproducible, production-only install. Optional native add-ons are skipped so
# the image builds without a C toolchain (New Relic works fine without them).
FROM base AS deps
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --omit=optional && npm cache clean --force

# ---- Runtime ----------------------------------------------------------------
FROM base AS runtime

# Create and switch to an unprivileged user.
RUN addgroup -S nodejs && adduser -S nodejs -G nodejs

# Copy production dependencies and application source.
COPY --from=deps --chown=nodejs:nodejs /app/node_modules ./node_modules
COPY --chown=nodejs:nodejs . .

USER nodejs

ENV PORT=3000
EXPOSE 3000

# Container-level healthcheck against the /health endpoint.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:'+(process.env.PORT||3000)+'/health',res=>process.exit(res.statusCode===200?0:1)).on('error',()=>process.exit(1))"

CMD ["node", "index.js"]
