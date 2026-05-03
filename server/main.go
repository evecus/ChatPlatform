package main

import (
	"log"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/yourname/chat-platform/config"
	"github.com/yourname/chat-platform/db"
	"github.com/yourname/chat-platform/handlers"
	"github.com/yourname/chat-platform/middleware"
)

func main() {
	loadDotEnv()
	config.Load()

	// Refuse to start with the default insecure JWT secret
	if config.C.JWTSecret == "change_me_please" {
		log.Fatal("FATAL: JWT_SECRET is not set. Generate one with: openssl rand -hex 32")
	}

	db.Init()
	handlers.CreateBootstrapCode()

	if os.Getenv("GIN_MODE") == "" {
		gin.SetMode(gin.ReleaseMode)
	}

	r := gin.New()
	r.Use(gin.Recovery())

	// ── CORS ──────────────────────────────────────────────────────────────────
	// Only allow the configured origin (set ALLOWED_ORIGIN env var).
	// Defaults to empty string which blocks all cross-origin requests.
	allowedOrigin := os.Getenv("ALLOWED_ORIGIN") // e.g. "https://chat.example.com"
	r.Use(func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		if allowedOrigin == "*" || (allowedOrigin != "" && origin == allowedOrigin) {
			c.Header("Access-Control-Allow-Origin", origin)
			c.Header("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS")
			c.Header("Access-Control-Allow-Headers", "Authorization,Content-Type")
			c.Header("Vary", "Origin")
		}
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	})

	// ── Public routes ─────────────────────────────────────────────────────────
	auth := r.Group("/api/auth")
	{
		// Rate-limit login/register: max 10 attempts per IP per minute
		auth.POST("/register", rateLimitMiddleware(10, time.Minute), handlers.Register)
		auth.POST("/login", rateLimitMiddleware(10, time.Minute), handlers.Login)
	}

	// ── Authenticated routes ──────────────────────────────────────────────────
	api := r.Group("/api", middleware.AuthRequired())
	{
		api.GET("/auth/me", handlers.Me)
		api.POST("/files/upload", handlers.UploadFile)
	}

	r.GET("/api/files/:filename", middleware.AuthRequired(), handlers.DownloadFile)
	r.GET("/ws", handlers.WSHandler)

	// ── Admin routes ──────────────────────────────────────────────────────────
	admin := r.Group("/api/admin", middleware.AuthRequired(), middleware.AdminRequired())
	{
		admin.GET("/users", handlers.AdminListUsers)
		admin.POST("/users/:id/ban", handlers.AdminBanUser)
		admin.POST("/users/:id/unban", handlers.AdminUnbanUser)
		admin.POST("/users/:id/kick", handlers.AdminKickUser)
		admin.DELETE("/users/:id", handlers.AdminDeleteUser)
		admin.GET("/online", handlers.AdminOnlineUsers)
		admin.GET("/invite-codes", handlers.AdminListInviteCodes)
		admin.POST("/invite-codes", handlers.AdminCreateInviteCode)
		admin.DELETE("/invite-codes/:id", handlers.AdminDeleteInviteCode)
	}

	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	addr := ":" + config.C.Port
	log.Printf("Server starting on %s", addr)
	if err := r.Run(addr); err != nil {
		log.Fatal(err)
	}
}

// ── Simple in-memory rate limiter ─────────────────────────────────────────────
// Keyed by IP. Resets the counter every `window` duration.
// Not suitable for multi-instance deployments (use Redis there).

type ipBucket struct {
	count  int
	resetAt time.Time
}

type rateLimiter struct {
	mu      sync.Mutex
	buckets map[string]*ipBucket
	max     int
	window  time.Duration
}

func newRateLimiter(max int, window time.Duration) *rateLimiter {
	rl := &rateLimiter{
		buckets: make(map[string]*ipBucket),
		max:     max,
		window:  window,
	}
	// Periodically clean up stale entries
	go func() {
		for range time.Tick(5 * time.Minute) {
			rl.mu.Lock()
			now := time.Now()
			for ip, b := range rl.buckets {
				if now.After(b.resetAt) {
					delete(rl.buckets, ip)
				}
			}
			rl.mu.Unlock()
		}
	}()
	return rl
}

func (rl *rateLimiter) allow(ip string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	now := time.Now()
	b, ok := rl.buckets[ip]
	if !ok || now.After(b.resetAt) {
		rl.buckets[ip] = &ipBucket{count: 1, resetAt: now.Add(rl.window)}
		return true
	}
	if b.count >= rl.max {
		return false
	}
	b.count++
	return true
}

func rateLimitMiddleware(max int, window time.Duration) gin.HandlerFunc {
	rl := newRateLimiter(max, window)
	return func(c *gin.Context) {
		ip := c.ClientIP()
		if !rl.allow(ip) {
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
				"error": "too many requests, please try again later",
			})
			return
		}
		c.Next()
	}
}

// ── .env loader ───────────────────────────────────────────────────────────────

func loadDotEnv() {
	data, err := os.ReadFile(".env")
	if err != nil {
		return
	}
	for _, line := range splitLines(string(data)) {
		if len(line) == 0 || line[0] == '#' {
			continue
		}
		for i, ch := range line {
			if ch == '=' {
				key := line[:i]
				val := line[i+1:]
				if os.Getenv(key) == "" {
					os.Setenv(key, val)
				}
				break
			}
		}
	}
}

func splitLines(s string) []string {
	var lines []string
	start := 0
	for i, c := range s {
		if c == '\n' {
			lines = append(lines, s[start:i])
			start = i + 1
		}
	}
	if start < len(s) {
		lines = append(lines, s[start:])
	}
	return lines
}
