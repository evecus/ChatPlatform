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

	// Send history
	history := loadHistory()
	client.Send <- mustMarshal(models.WSMessage{Type: "history", Messages: history})

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

func loadHistory() []models.Message {
	rows, err := db.DB.Query(
		`SELECT id, user_id, username, type, content, COALESCE(file_name,''), COALESCE(file_size,0), created_at
		 FROM messages ORDER BY created_at DESC LIMIT ?`,
		config.C.HistoryLimit,
	)
	if err != nil {
		return nil
	}
	defer rows.Close()

	msgs := []models.Message{}
	for rows.Next() {
		var m models.Message
		rows.Scan(&m.ID, &m.UserID, &m.Username, &m.Type, &m.Content, &m.FileName, &m.FileSize, &m.CreatedAt)
		msgs = append([]models.Message{m}, msgs...)
	}
	return msgs
}

func mustMarshal(v interface{}) []byte {
	b, _ := json.Marshal(v)
	return b
}
