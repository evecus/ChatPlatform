package handlers

import (
	"database/sql"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"

	"github.com/yourname/chat-platform/config"
	"github.com/yourname/chat-platform/db"
	"github.com/yourname/chat-platform/middleware"
	"github.com/yourname/chat-platform/models"
)

func Register(c *gin.Context) {
	var req struct {
		Username   string `json:"username" binding:"required,min=2,max=20"`
		Password   string `json:"password" binding:"required,min=6"`
		InviteCode string `json:"invite_code" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate invite code
	var codeID int64
	var usedBy sql.NullInt64
	err := db.DB.QueryRow(`SELECT id, used_by FROM invite_codes WHERE code = ?`, req.InviteCode).
		Scan(&codeID, &usedBy)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid invite code"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	if usedBy.Valid {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invite code already used"})
		return
	}

	// Check username taken
	var exists int
	db.DB.QueryRow(`SELECT COUNT(*) FROM users WHERE username = ?`, req.Username).Scan(&exists)
	if exists > 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "username already taken"})
		return
	}

	// Hash password
	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "server error"})
		return
	}

	// Determine role: first user ever = admin
	var userCount int
	db.DB.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&userCount)
	role := "user"
	if userCount == 0 {
		role = "admin"
	}

	// Insert user
	result, err := db.DB.Exec(
		`INSERT INTO users (username, password, role, status) VALUES (?, ?, ?, 'active')`,
		req.Username, string(hash), role,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create user"})
		return
	}
	userID, _ := result.LastInsertId()

	// Mark invite code as used
	db.DB.Exec(`UPDATE invite_codes SET used_by = ? WHERE id = ?`, userID, codeID)

	token, err := generateToken(userID, req.Username, role, "active")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "token error"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"token": token,
		"user": gin.H{
			"id":       userID,
			"username": req.Username,
			"role":     role,
		},
	})
}

func Login(c *gin.Context) {
	var req struct {
		Username string `json:"username" binding:"required"`
		Password string `json:"password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var user models.User
	err := db.DB.QueryRow(
		`SELECT id, username, password, role, status FROM users WHERE username = ?`,
		req.Username,
	).Scan(&user.ID, &user.Username, &user.Password, &user.Role, &user.Status)

	if err == sql.ErrNoRows {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid username or password"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	if user.Status == "banned" {
		c.JSON(http.StatusForbidden, gin.H{"error": "account banned"})
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(req.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid username or password"})
		return
	}

	token, err := generateToken(user.ID, user.Username, user.Role, user.Status)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "token error"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"token": token,
		"user": gin.H{
			"id":       user.ID,
			"username": user.Username,
			"role":     user.Role,
		},
	})
}

func Me(c *gin.Context) {
	userID, _ := c.Get("user_id")
	username, _ := c.Get("username")
	role, _ := c.Get("role")
	c.JSON(http.StatusOK, gin.H{
		"id":       userID,
		"username": username,
		"role":     role,
	})
}

// Bootstrap: create first admin invite code if no users exist
// Called on startup so admin can register
func CreateBootstrapCode() {
	var count int
	db.DB.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&count)
	if count > 0 {
		return
	}
	// Check if a bootstrap code already exists (created_by = 0)
	var existing int
	db.DB.QueryRow(`SELECT COUNT(*) FROM invite_codes WHERE created_by = 0`).Scan(&existing)
	if existing > 0 {
		var code string
		db.DB.QueryRow(`SELECT code FROM invite_codes WHERE created_by = 0 AND used_by IS NULL`).Scan(&code)
		if code != "" {
			// Print to log so admin can see it
			println("=== BOOTSTRAP INVITE CODE:", code, "(use this to register the first admin) ===")
		}
		return
	}
	code := generateCode()
	db.DB.Exec(`INSERT INTO invite_codes (code, created_by) VALUES (?, 0)`, code)
	println("=== BOOTSTRAP INVITE CODE:", code, "(use this to register the first admin) ===")
}

func generateToken(userID int64, username, role, status string) (string, error) {
	claims := middleware.Claims{
		UserID:   userID,
		Username: username,
		Role:     role,
		Status:   status,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(30 * 24 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString([]byte(config.C.JWTSecret))
}
