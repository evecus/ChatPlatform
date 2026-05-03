package hub

import (
	"encoding/json"
	"sync"

	"github.com/gorilla/websocket"
	"github.com/yourname/chat-platform/models"
)

type Client struct {
	UserID   int64
	Username string
	Role     string
	Conn     *websocket.Conn
	Send     chan []byte
	Hub      *Hub
}

type Hub struct {
	mu      sync.RWMutex
	clients map[int64]*Client // userID → client
}

var H = &Hub{
	clients: make(map[int64]*Client),
}

func (h *Hub) Register(c *Client) {
	h.mu.Lock()
	// If same user connects again, close old connection
	if old, ok := h.clients[c.UserID]; ok {
		close(old.Send)
	}
	h.clients[c.UserID] = c
	h.mu.Unlock()
}

func (h *Hub) Unregister(c *Client) {
	h.mu.Lock()
	if current, ok := h.clients[c.UserID]; ok && current == c {
		delete(h.clients, c.UserID)
	}
	h.mu.Unlock()
}

func (h *Hub) Broadcast(msg models.WSMessage) {
	data, err := json.Marshal(msg)
	if err != nil {
		return
	}
	h.mu.RLock()
	defer h.mu.RUnlock()
	for _, c := range h.clients {
		select {
		case c.Send <- data:
		default:
			// slow client, skip
		}
	}
}

func (h *Hub) SendTo(userID int64, msg models.WSMessage) {
	data, err := json.Marshal(msg)
	if err != nil {
		return
	}
	h.mu.RLock()
	c, ok := h.clients[userID]
	h.mu.RUnlock()
	if ok {
		select {
		case c.Send <- data:
		default:
		}
	}
}

func (h *Hub) KickUser(userID int64) {
	h.mu.Lock()
	c, ok := h.clients[userID]
	if ok {
		delete(h.clients, userID)
	}
	h.mu.Unlock()

	if ok {
		msg, _ := json.Marshal(models.WSMessage{Type: "kicked", Reason: "removed by admin"})
		c.Conn.WriteMessage(websocket.TextMessage, msg)
		c.Conn.Close()
		close(c.Send)
	}
}

func (h *Hub) OnlineUsers() []models.OnlineUser {
	h.mu.RLock()
	defer h.mu.RUnlock()
	users := make([]models.OnlineUser, 0, len(h.clients))
	for _, c := range h.clients {
		users = append(users, models.OnlineUser{ID: c.UserID, Username: c.Username})
	}
	return users
}

func (h *Hub) IsOnline(userID int64) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()
	_, ok := h.clients[userID]
	return ok
}

// WritePump sends messages from the send channel to the WebSocket connection
func (c *Client) WritePump() {
	defer c.Conn.Close()
	for data := range c.Send {
		if err := c.Conn.WriteMessage(websocket.TextMessage, data); err != nil {
			return
		}
	}
}
