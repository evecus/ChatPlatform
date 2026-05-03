package models

import "time"

type User struct {
	ID        int64     `json:"id"`
	Username  string    `json:"username"`
	Password  string    `json:"-"`
	Role      string    `json:"role"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

type Message struct {
	ID        int64     `json:"id"`
	UserID    int64     `json:"user_id"`
	Username  string    `json:"username"`
	Type      string    `json:"type"`      // "text" | "file"
	Content   string    `json:"content"`   // text body or file download path
	FileName  string    `json:"file_name"` // original filename (for file type)
	FileSize  int64     `json:"file_size"`
	CreatedAt time.Time `json:"created_at"`
}

type InviteCode struct {
	ID        int64     `json:"id"`
	Code      string    `json:"code"`
	CreatedBy int64     `json:"created_by"`
	UsedBy    *int64    `json:"used_by"`
	CreatedAt time.Time `json:"created_at"`
}

// WebSocket message envelope
type WSMessage struct {
	Type string `json:"type"`

	// type=message / file_message
	Message *Message `json:"message,omitempty"`

	// type=history
	Messages []Message `json:"messages,omitempty"`

	// type=user_joined / user_left
	Username string `json:"username,omitempty"`
	UserID   int64  `json:"user_id,omitempty"`

	// type=online_users
	Users []OnlineUser `json:"users,omitempty"`

	// type=error / kicked / banned
	Reason string `json:"reason,omitempty"`
}

type OnlineUser struct {
	ID       int64  `json:"id"`
	Username string `json:"username"`
}

// Incoming WS message from client
type ClientMessage struct {
	Type     string `json:"type"`    // "send_message" | "send_file"
	Content  string `json:"content"` // text or file_id
	FileName string `json:"file_name"`
	FileSize int64  `json:"file_size"`
}
