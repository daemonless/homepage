# syntax=docker/dockerfile:1
ARG BASE_VERSION=15

# Build stage
FROM ghcr.io/daemonless/base:${BASE_VERSION} AS builder

# Install build dependencies
RUN pkg update && \
    pkg install -y node22 npm-node22 jq && \
    npm install -g pnpm

# Download and build homepage
WORKDIR /build
RUN HOMEPAGE_VERSION=$(fetch -qo - "https://api.github.com/repos/gethomepage/homepage/releases/latest" | jq -r '.tag_name' | sed 's/^v//') && \
    echo "Building homepage v${HOMEPAGE_VERSION}" && \
    fetch -qo homepage.tar.gz "https://github.com/gethomepage/homepage/archive/refs/tags/v${HOMEPAGE_VERSION}.tar.gz" && \
    tar xzf homepage.tar.gz --strip-components=1 && \
    rm homepage.tar.gz && \
    pnpm install --frozen-lockfile && \
    pnpm build && \
    echo "v${HOMEPAGE_VERSION}" > /build/version

# Final stage
FROM ghcr.io/daemonless/base:${BASE_VERSION}

ARG HEALTHCHECK_ENDPOINT="http://localhost:3000/"
ARG UPSTREAM_URL="https://api.github.com/repos/gethomepage/homepage/releases/latest"
ARG UPSTREAM_JQ=".tag_name"

LABEL org.opencontainers.image.source="https://github.com/daemonless/homepage" \
    org.opencontainers.image.title="Homepage" \
    org.opencontainers.image.description="Homepage - A modern dashboard for your homelab" \
    org.opencontainers.image.url="https://gethomepage.dev/" \
    org.opencontainers.image.licenses="GPL-3.0" \
    org.opencontainers.image.vendor="daemonless" \
    io.daemonless.port="3000" \
    io.daemonless.upstream-mode="source" \
    io.daemonless.upstream-url="${UPSTREAM_URL}" \
    io.daemonless.upstream-jq="${UPSTREAM_JQ}" \
    io.daemonless.healthcheck-url="${HEALTHCHECK_ENDPOINT}"

ENV HEALTHCHECK_URL="${HEALTHCHECK_ENDPOINT}"

# Install runtime dependency only
RUN pkg update && \
    pkg install -y node22 && \
    pkg clean -ay && \
    rm -rf /var/cache/pkg/*

# Copy standalone build output from builder
WORKDIR /app
COPY --from=builder /build/.next/standalone/ /app/
COPY --from=builder /build/.next/static /app/.next/static
COPY --from=builder /build/public /app/public
COPY --from=builder /build/src/skeleton /app/src/skeleton
COPY --from=builder /build/version /app/version

# Create config directory
RUN mkdir -p /config && \
    chown -R bsd:bsd /config /app

# Copy s6 service
COPY root/ /

# Make scripts executable
RUN chmod +x /etc/services.d/homepage/run /etc/cont-init.d/*

EXPOSE 3000
VOLUME /config
