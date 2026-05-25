FROM cgr.dev/chainguard/node:latest-dev@sha256:ce3f18966af7a0ba76f96aa32d6240b437d00eeb775d92c1e7e75f457fe5a8b7 AS deps

WORKDIR /app

COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

FROM deps AS build

WORKDIR /app

COPY tsconfig.json ./
COPY src ./src
RUN yarn build

FROM cgr.dev/chainguard/node:latest-dev@sha256:ce3f18966af7a0ba76f96aa32d6240b437d00eeb775d92c1e7e75f457fe5a8b7 AS prod-deps

WORKDIR /app

COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile --production=true && yarn cache clean

FROM cgr.dev/chainguard/node:latest@sha256:3e212e37f83e078397dd8431964a4d703b5ecba9ed508c2748ad24a11930a746 AS runtime

WORKDIR /app

ENV NODE_ENV=production

COPY package.json ./
COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist

EXPOSE 3000

CMD ["dist/index.js"]