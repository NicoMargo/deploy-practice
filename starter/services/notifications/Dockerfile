#syntax=docker/dockerfile:1
FROM node:20-alpine AS build
WORKDIR /app

COPY package.json package-lock.json ./
COPY packages/logger/package.json packages/logger/
COPY packages/secrets/package.json packages/secrets/
COPY packages/types/package.json packages/types/
COPY services/notifications/package.json services/notifications/

RUN npm ci

COPY packages/logger packages/logger
COPY packages/secrets packages/secrets
COPY packages/types packages/types
COPY services/notifications services/notifications

RUN npm run build -w @aceup/logger -w @aceup/secrets -w @aceup/types -w @aceup/notifications-service

FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production

COPY package.json package-lock.json ./
COPY packages/logger/package.json packages/logger/
COPY packages/secrets/package.json packages/secrets/
COPY packages/types/package.json packages/types/
COPY services/notifications/package.json services/notifications/

# npm and yarn are only needed to install dependencies. At runtime we just run
# node, so they are removed: their own bundled dependencies were the source of
# every HIGH/CRITICAL finding in the image scan. Same RUN as the install, or the
# files would still exist in the previous layer.
RUN npm ci --omit=dev \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx /opt/yarn*

COPY --from=build /app/packages/logger/dist packages/logger/dist
COPY --from=build /app/packages/secrets/dist packages/secrets/dist
COPY --from=build /app/packages/types/dist packages/types/dist
COPY --from=build /app/services/notifications/dist services/notifications/dist

USER node
EXPOSE 8082
CMD ["node", "services/notifications/dist/index.js"]
