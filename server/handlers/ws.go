package handlers

import (
	"encoding/json"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"

	"github.com/yourname/chat-platform/config"
	"github.com/yourname/chat-platform/db"
	"github.com/yourname/chat-platform/hub"
	"github.com/yourname/chat-platform/middleware"
	"github.com/yourname/chat-platform/models"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

func WSHandler(c *gin.Context) {
	token := c.Query("token")
	if token == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing token"})
		return
	}
	claims, err := middleware.ParseToken(token)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
		return
	}
	if claims.Status == "banned" {
		c.JSON(http.StatusForbidden, gin.H{"error": "account banned"})
		return
	}

	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Println("ws upgrade error:", err)
		return
	}

	client := &hub.Client{
		UserID:   claims.UserID,
		Username: claims.Username,
		Role:     claims.Role,
		Conn:     conn,
		Send:     make(chan []byte, 64),
		Hub:      hub.H,
	}

	hub.H.Register(client)

	// Send initial history (newest 50, no before_id)
	history, hasMore := loadHistory(0, config.C.HistoryLimit)
	client.Send <- mustMarshal(models.WSMessage{
		Type:     "history",
		Messages: history,
		HasMore:  hasMore,
	})

	// Send online users
	client.Send <- mustMarshal(models.WSMessage{Type: "online_users", Users: hub.H.OnlineUsers()})

	// Broadcast join
	hub.H.Broadcast(models.WSMessage{Type: "user_joined", Username: claims.Username, UserID: claims.UserID})

	go client.WritePump()
	readPump(client)
}

func readPump(client *hub.Client) {
	defer func() {
		hub.H.Unregister(client)
		client.Conn.Close()
		hub.H.Broadcast(models.WSMessage{Type: "user_left", Username: client.Username, UserID: client.UserID})
	}()

	for {
		_, raw, err := client.Conn.ReadMessage()
		if err != nil {
			break
		}

		var cm models.ClientMessage
		if err := json.Unmarshal(raw, &cm); err != nil {
			continue
		}

		switch cm.Type {
		case "send_message":
			handleTextMessage(client, cm)
		case "send_file":
			handleFileMessage(client, cm)
		case "load_history":
			handleLoadHistory(client, cm)
		}
	}
}

func handleTextMessage(client *hub.Client, cm models.ClientMessage) {
	if len(cm.Content) == 0 || len(cm.Content) > 2000 {
		return
	}

	result, err := db.DB.Exec(
		`INSERT INTO messages (user_id, username, type, content) VALUES (?, ?, 'text', ?)`,
		client.UserID, client.Username, cm.Content,
	)
	if err != nil {
		return
	}
	msgID, _ := result.LastInsertId()

	var msg models.Message
	db.DB.QueryRow(
		`SELECT id, user_id, username, type, content, created_at FROM messages WHERE id = ?`, msgID,
	).Scan(&msg.ID, &msg.UserID, &msg.Username, &msg.Type, &msg.Content, &msg.CreatedAt)

	hub.H.Broadcast(models.WSMessage{Type: "message", Message: &msg})
}

func handleFileMessage(client *hub.Client, cm models.ClientMessage) {
	if cm.Content == "" || cm.FileName == "" {
		return
	}

	result, err := db.DB.Exec(
		`INSERT INTO messages (user_id, username, type, content, file_name, file_size) VALUES (?, ?, 'file', ?, ?, ?)`,
		client.UserID, client.Username, cm.Content, cm.FileName, cm.FileSize,
	)
	if err != nil {
		return
	}
	msgID, _ := result.LastInsertId()

	var msg models.Message
	db.DB.QueryRow(
		`SELECT id, user_id, username, type, content, file_name, file_size, created_at FROM messages WHERE id = ?`, msgID,
	).Scan(&msg.ID, &msg.UserID, &msg.Username, &msg.Type, &msg.Content, &msg.FileName, &msg.FileSize, &msg.CreatedAt)

	hub.H.Broadcast(models.WSMessage{Type: "message", Message: &msg})
}

// handleLoadHistory responds to a client's "load_history" request with older messages
func handleLoadHistory(client *hub.Client, cm models.ClientMessage) {
	if cm.BeforeID <= 0 {
		return
	}
	msgs, hasMore := loadHistory(cm.BeforeID, config.C.HistoryLimit)
	client.Send <- mustMarshal(models.WSMessage{
		Type:     "history_page",
		Messages: msgs,
		HasMore:  hasMore,
	})
}

// loadHistory fetches up to `limit` messages.
// If beforeID > 0, fetches messages with id < beforeID (older messages).
// If beforeID == 0, fetches the newest `limit` messages.
// Returns messages in ascending order and whether more exist beyond this page.
func loadHistory(beforeID int64, limit int) ([]models.Message, bool) {
	// Fetch one extra to determine hasMore
	fetchLimit := limit + 1

	var rows interface {
		Next() bool
		Scan(...interface{}) error
		Close() error
	}
	var err error

	if beforeID > 0 {
		rows, err = db.DB.Query(`
			SELECT m.id, m.user_id, m.username, m.type, m.content,
			       COALESCE(m.file_name,''), COALESCE(m.file_size,0), m.created_at,
			       COALESCE(f.expired,0)
			FROM messages m
			LEFT JOIN files f ON f.stored_name = m.content AND m.type = 'file'
			WHERE m.id < ?
			ORDER BY m.id DESC
			LIMIT ?`, beforeID, fetchLimit)
	} else {
		rows, err = db.DB.Query(`
			SELECT m.id, m.user_id, m.username, m.type, m.content,
			       COALESCE(m.file_name,''), COALESCE(m.file_size,0), m.created_at,
			       COALESCE(f.expired,0)
			FROM messages m
			LEFT JOIN files f ON f.stored_name = m.content AND m.type = 'file'
			ORDER BY m.id DESC
			LIMIT ?`, fetchLimit)
	}
	if err != nil {
		return nil, false
	}
	defer rows.Close()

	var msgs []models.Message
	for rows.Next() {
		var m models.Message
		var expiredInt int
		rows.Scan(&m.ID, &m.UserID, &m.Username, &m.Type, &m.Content,
			&m.FileName, &m.FileSize, &m.CreatedAt, &expiredInt)
		m.FileExpired = expiredInt == 1
		msgs = append(msgs, m)
	}

	hasMore := len(msgs) > limit
	if hasMore {
		msgs = msgs[:limit]
	}

	// Reverse to ascending order
	for i, j := 0, len(msgs)-1; i < j; i, j = i+1, j-1 {
		msgs[i], msgs[j] = msgs[j], msgs[i]
	}

	return msgs, hasMore
}

func mustMarshal(v interface{}) []byte {
	b, _ := json.Marshal(v)
	return b
}
