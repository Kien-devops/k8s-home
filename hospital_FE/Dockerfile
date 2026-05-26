FROM node:22-alpine AS build

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

FROM nginx:1.27-alpine AS runtime

# Pull patched Alpine packages before dropping privileges.
# nginx user (UID 101) already exists in alpine image.
RUN apk upgrade --no-cache && \
    touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid /var/cache/nginx /var/log/nginx /etc/nginx/conf.d

WORKDIR /usr/share/nginx/html

COPY --from=build /app/dist ./
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Switch to non-root user nginx (UID 101).
# Non-root users cannot bind to ports < 1024, so nginx config must listen on 8000.
USER nginx

EXPOSE 8000
