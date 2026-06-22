# ── Build stage ──────────────────────────────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci --prefer-offline

COPY . .

# VITE_API_URL is set at runtime via an env var passed to the container.
# For Render / most hosts, the frontend calls the same origin via a reverse
# proxy, so we leave VITE_API_URL empty and rely on the Vite dev-proxy config
# (which is not used in production — the Nginx config below handles it).
ARG VITE_API_URL=""
ENV VITE_API_URL=$VITE_API_URL

RUN npm run build

# ── Serve stage ───────────────────────────────────────────────────────────────
FROM nginx:alpine

# Replace default nginx config with one that handles SPA routing
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
