# Pre-built binary is downloaded from CI artifacts and passed via build context.
# Build with: --build-arg ARCH=amd64  or  --build-arg ARCH=arm64
FROM alpine:3.19

ARG ARCH=amd64

RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app

# Copy the arch-specific binary and rename it to a fixed name
COPY chatwave-server-${ARCH} ./chatwave-server

RUN chmod +x /app/chatwave-server && \
    mkdir -p /app/data/uploads

EXPOSE 8080

ENTRYPOINT ["/app/chatwave-server"]
