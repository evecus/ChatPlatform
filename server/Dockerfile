# Build stage
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o chat-server .

# Final stage - minimal image
FROM scratch
COPY --from=builder /app/chat-server /chat-server
EXPOSE 8080
ENTRYPOINT ["/chat-server"]
