# ── Build stage ──────────────────────────────────────────────────────────────
FROM golang:1.21-alpine AS builder

RUN apk add --no-cache git

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

# CGO_ENABLED=0 → pure-Go SQLite (modernc.org/sqlite), no C toolchain needed
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o chatwave-server .

# ── Final stage ───────────────────────────────────────────────────────────────
# Use alpine (not scratch) so the container has a shell and ca-certs,
# and works correctly on both amd64 and arm64.
FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app

COPY --from=builder /app/chatwave-server .

# Data directory (mount a volume here in production)
RUN mkdir -p /app/data/uploads

EXPOSE 8080

ENTRYPOINT ["/app/chatwave-server"]
