# syntax=docker/dockerfile:1

# ---- Build stage --------------------------------------------------------
FROM node:20-alpine AS build
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci

COPY public ./public
COPY src ./src
# .env.production is intentionally not copied: REACT_APP_API_BASE_URL is left
# unset so the built app defaults to same-origin API calls (see src/config.js).
RUN npm run build

# ---- Runtime stage -------------------------------------------------------
# Unprivileged nginx image: runs as non-root (uid 101) and listens on a
# non-privileged port by default.
FROM nginxinc/nginx-unprivileged:1.27-alpine

# Pull latest patched OS packages (e.g. openssl) before dropping to the
# unprivileged nginx user. Named users (root/nginx) are used deliberately
# for readability; the base image's "nginx" user is fixed at uid 101.
# hadolint ignore=DL3066
USER root
RUN apk update && apk upgrade --no-cache
# hadolint ignore=DL3066
USER nginx

COPY --chown=nginx:nginx nginx.conf /etc/nginx/conf.d/default.conf
COPY --chown=nginx:nginx --from=build /app/build /usr/share/nginx/html

EXPOSE 8080

# Shell-form CMD is required here for the "|| exit 1" fallback; JSON array
# form doesn't support shell operators.
# hadolint ignore=DL3025
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -q -O- http://127.0.0.1:8080/healthz || exit 1

# hadolint ignore=DL3066
USER nginx

CMD ["nginx", "-g", "daemon off;"]
