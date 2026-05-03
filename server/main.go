package main

import (
	"log"
	"os"

	"github.com/gin-gonic/gin"

	"github.com/yourname/chat-platform/config"
	"github.com/yourname/chat-platform/db"
	"github.com/yourname/chat-platform/handlers"
	"github.com/yourname/chat-platform/middleware"
)

func main() {
	// Load .env if present
	loadDotEnv()
	config.Load()

	db.Init()
	handlers.CreateBootstrapCode()

	if os.Getenv("GIN_MODE") == "" {
		gin.SetMode(gin.ReleaseMode)
	}

	r := gin.Default()

	// CORS middleware
	r.Use(func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Authorization,Content-Type")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	})

	// Public routes
	auth := r.Group("/api/auth")
	{
		auth.POST("/register", handlers.Register)
		auth.POST("/login", handlers.Login)
	}

	// Authenticated routes
	api := r.Group("/api", middleware.AuthRequired())
	{
		api.GET("/auth/me", handlers.Me)
		api.POST("/files/upload", handlers.UploadFile)
	}

	// File download (auth required to prevent hotlinking)
	r.GET("/api/files/:filename", middleware.AuthRequired(), handlers.DownloadFile)

	// WebSocket
	r.GET("/ws", handlers.WSHandler)

	// Admin routes
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

	// Health check
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})

	addr := ":" + config.C.Port
	log.Printf("Server starting on %s", addr)
	if err := r.Run(addr); err != nil {
		log.Fatal(err)
	}
}

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
