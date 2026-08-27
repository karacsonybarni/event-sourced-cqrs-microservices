FROM node:24.15.0-alpine AS build

WORKDIR /app
ARG VITE_SERVERLESS_PROJECTION_ENABLED=false
ENV VITE_SERVERLESS_PROJECTION_ENABLED=${VITE_SERVERLESS_PROJECTION_ENABLED}
COPY package.json package-lock.json ./
RUN npm ci
COPY index.html tsconfig.json vite.config.ts ./
COPY src ./src
RUN npm run build

FROM nginx:1.29.4-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=10s --timeout=3s --retries=10 \
  CMD wget -qO- http://127.0.0.1/ >/dev/null || exit 1
