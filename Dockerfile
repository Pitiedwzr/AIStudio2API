# syntax=docker/dockerfile:1

FROM node:22-bookworm-slim AS web-builder

WORKDIR /src/web
COPY web/package.json web/package-lock.json ./
RUN npm ci

COPY web/ ./
COPY internal/webui/ /src/internal/webui/
RUN npm run build

FROM golang:1.25-bookworm AS go-builder

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download

COPY . .
COPY --from=web-builder /src/internal/webui/dist ./internal/webui/dist
ARG TARGETOS
ARG TARGETARCH

RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags="-s -w" \
    -o /out/aistudio2api ./cmd/aistudio2api
FROM debian:bookworm-slim AS runtime

# Camoufox is Firefox-based and needs these libraries even when running headless.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        fonts-liberation \
        libasound2 \
        libatk-bridge2.0-0 \
        libatk1.0-0 \
        libc6 \
        libcairo2 \
        libdbus-1-3 \
        libdrm2 \
        libgbm1 \
        libglib2.0-0 \
        libgtk-3-0 \
        libnspr4 \
        libnss3 \
        libpango-1.0-0 \
        libx11-6 \
        libx11-xcb1 \
        libxcb1 \
        libxcomposite1 \
        libxdamage1 \
        libxext6 \
        libxfixes3 \
        libxrandr2 \
        xdg-utils \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 10001 --shell /usr/sbin/nologin app

WORKDIR /app
COPY --from=go-builder /out/aistudio2api /app/aistudio2api

RUN mkdir -p /app/auth /app/runtime \
    && chown -R app:app /app

USER app

ENV LISTEN_ADDR=0.0.0.0:2048 \
    AISTUDIO_AUTH_STATES=/app/auth \
    HOME=/home/app

EXPOSE 2048

VOLUME ["/app/auth", "/app/runtime"]

ENTRYPOINT ["/app/aistudio2api"]
CMD ["-open-ui=false"]
