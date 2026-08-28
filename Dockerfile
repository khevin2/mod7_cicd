ARG NODE_IMAGE=node:24.20.0-alpine@sha256:e67514e5d0f6c46656005e1b693b2ec9d52e80b641307de684d4a015ba7a4eaf

FROM ${NODE_IMAGE} AS production-dependencies

WORKDIR /app

COPY package.json package-lock.json ./

RUN npm ci --omit=dev --ignore-scripts

FROM ${NODE_IMAGE} AS runtime

ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=3000 \
    METRICS_HOST=0.0.0.0 \
    METRICS_PORT=9464

# The upstream Node image is pinned for reproducibility. Upgrade the OpenSSL
# packages from Alpine's signed stable repository so the runtime image includes
# the available security remediation rather than inheriting a stale layer.
RUN apk upgrade --no-cache openssl libcrypto3 libssl3

RUN addgroup -g 10001 -S appgroup \
    && adduser -u 10001 -S -D -H -G appgroup appuser

# npm is required only in the dependency stage. Removing it from the runtime
# image reduces the attack surface while retaining the Node.js executable.
RUN rm -rf /usr/local/lib/node_modules/npm \
    && rm -f /usr/local/bin/npm /usr/local/bin/npx

WORKDIR /app

COPY --from=production-dependencies --chown=10001:10001 /app/node_modules ./node_modules
COPY --chown=10001:10001 package.json package-lock.json ./
COPY --chown=10001:10001 src ./src

USER 10001:10001

EXPOSE 3000 9464

HEALTHCHECK --interval=5s --timeout=3s --start-period=5s --retries=3 \
  CMD ["node", "-e", "fetch('http://127.0.0.1:' + (process.env.PORT || '3000') + '/health').then((response) => { if (!response.ok) process.exit(1); }).catch(() => process.exit(1));"]

STOPSIGNAL SIGTERM

CMD ["node", "src/server.js"]
