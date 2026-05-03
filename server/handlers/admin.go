package handlers

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"github.com/yourname/chat-platform/db"
	"github.com/yourname/chat-platform/hub"
	"github.com/yourname/chat-platform/models"
)

func generateCode() string {
	b := make([]byte, 6)
	rand.Read(b)
	return hex.EncodeToString(b)
}

// GET /api/admin/users
func AdminListUsers(c *gin.Context) {
	rows, err := db.DB.Query(
		`SELECT id, username, role, status, created_at FROM users ORDER BY created_at`,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer rows.Close()

	users := []gin.H{}
	for rows.Next() {
		var u models.User
		rows.Scan(&u.ID, &u.Username, &u.Role, &u.Status, &u.CreatedAt)
		users = append(users, gin.H{
			"id":         u.ID,
			"username":   u.Username,
			"role":       u.Role,
			"status":     u.Status,
			"created_at": u.CreatedAt,
			"online":     hub.H.IsOnline(u.ID),
		})
	}
	c.JSON(http.StatusOK, users)
}

// POST /api/admin/users/:id/ban
func AdminBanUser(c *gin.Context) {
	targetID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	adminID, _ := c.Get("user_id")
	if targetID == adminID.(int64) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cannot ban yourself"})
		return
	}

	// Check target role
	var role string
	err = db.DB.QueryRow(`SELECT role FROM users WHERE id = ?`, targetID).Scan(&role)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}
	if role == "admin" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cannot ban admin"})
		return
	}

	db.DB.Exec(`UPDATE users SET status = 'banned' WHERE id = ?`, targetID)

	// Notify and disconnect
	hub.H.SendTo(targetID, models.WSMessage{Type: "banned", Reason: "your account has been banned"})
	hub.H.KickUser(targetID)

	// Broadcast to all
	var username string
	db.DB.QueryRow(`SELECT username FROM users WHERE id = ?`, targetID).Scan(&username)
	hub.H.Broadcast(models.WSMessage{Type: "user_banned", Username: username})

	c.JSON(http.StatusOK, gin.H{"message": "user banned"})
}

// POST /api/admin/users/:id/unban
func AdminUnbanUser(c *gin.Context) {
	targetID, _ := strconv.ParseInt(c.Param("id"), 10, 64)
	db.DB.Exec(`UPDATE users SET status = 'active' WHERE id = ?`, targetID)
	c.JSON(http.StatusOK, gin.H{"message": "user unbanned"})
}

// POST /api/admin/users/:id/kick
func AdminKickUser(c *gin.Context) {
	targetID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	adminID, _ := c.Get("user_id")
	if targetID == adminID.(int64) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cannot kick yourself"})
		return
	}

	if !hub.H.IsOnline(targetID) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "user is not online"})
		return
	}

	hub.H.KickUser(targetID)

	var username string
	db.DB.QueryRow(`SELECT username FROM users WHERE id = ?`, targetID).Scan(&username)
	hub.H.Broadcast(models.WSMessage{Type: "user_left", Username: username})

	c.JSON(http.StatusOK, gin.H{"message": "user kicked"})
}

// DELETE /api/admin/users/:id
func AdminDeleteUser(c *gin.Context) {
	targetID, _ := strconv.ParseInt(c.Param("id"), 10, 64)
	adminID, _ := c.Get("user_id")
	if targetID == adminID.(int64) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cannot delete yourself"})
		return
	}
	hub.H.KickUser(targetID)
	db.DB.Exec(`DELETE FROM users WHERE id = ?`, targetID)
	c.JSON(http.StatusOK, gin.H{"message": "user deleted"})
}

// POST /api/admin/invite-codes
func AdminCreateInviteCode(c *gin.Context) {
	adminID, _ := c.Get("user_id")
	code := generateCode()
	_, err := db.DB.Exec(`INSERT INTO invite_codes (code, created_by) VALUES (?, ?)`, code, adminID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create code"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"code": code})
}

// GET /api/admin/invite-codes
func AdminListInviteCodes(c *gin.Context) {
	rows, err := db.DB.Query(`
		SELECT ic.id, ic.code, ic.created_at,
		       u.username as used_by_username
		FROM invite_codes ic
		LEFT JOIN users u ON ic.used_by = u.id
		ORDER BY ic.created_at DESC
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer rows.Close()

	codes := []gin.H{}
	for rows.Next() {
		var id int64
		var code, createdAt string
		var usedByUsername sql.NullString
		rows.Scan(&id, &code, &createdAt, &usedByUsername)
		codes = append(codes, gin.H{
			"id":         id,
			"code":       code,
			"created_at": createdAt,
			"used_by":    usedByUsername.String,
			"used":       usedByUsername.Valid,
		})
	}
	c.JSON(http.StatusOK, codes)
}

// DELETE /api/admin/invite-codes/:id
func AdminDeleteInviteCode(c *gin.Context) {
	id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
	db.DB.Exec(`DELETE FROM invite_codes WHERE id = ? AND used_by IS NULL`, id)
	c.JSON(http.StatusOK, gin.H{"message": "deleted"})
}

// GET /api/admin/online
func AdminOnlineUsers(c *gin.Context) {
	c.JSON(http.StatusOK, hub.H.OnlineUsers())
}
