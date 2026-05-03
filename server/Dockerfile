# No build stage needed — binary is pre-built by CI and copied directly in.
FROM alpine:3.19

RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app

# The binary is passed in via build context (CI downloads artifact first)
# Expected: chatwave-server-amd64 or chatwave-server-arm64 → renamed to chatwave-server
COPY chatwave-server .

RUN mkdir -p /app/data/uploads

EXPOSE 8080

ENTRYPOINT ["/app/chatwave-server"]
