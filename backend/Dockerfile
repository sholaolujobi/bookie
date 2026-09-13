# syntax=docker/dockerfile:1

# ---- Dependencies stage ---------------------------------------------------
FROM node:26-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev

# ---- Runtime stage ---------------------------------------------------------
FROM node:26-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app

# Pull latest patched OS packages (e.g. openssl) and drop the bundled npm
# CLI and its vendored dependency tree: the running container only ever
# execs `node`, never `npm`, so npm's own supply chain isn't a runtime risk
# surface worth carrying.
RUN apk update && apk upgrade --no-cache \
  && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx

# node:alpine already ships an unprivileged "node" user (uid 1000).
COPY --chown=node:node --from=deps /app/node_modules ./node_modules
COPY --chown=node:node package.json ./
COPY --chown=node:node config.js ./
COPY --chown=node:node src ./src

EXPOSE 8080

# Shell-form CMD is used so node -e's quoting works normally; JSON array
# form would require escaping the embedded single/double quotes awkwardly.
# hadolint ignore=DL3025
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:8080/api/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

# hadolint ignore=DL3066
USER node

CMD ["node", "src/server.js"]
